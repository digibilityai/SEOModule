import { describe, expect, it } from "vitest";
import {
  LinkIntentError,
  handleCreateLinkIntent,
  handleProvisionCaseA,
  validateCreateLinkIntentRequest,
  validateProvisionRequest,
  type AdminAuthPort,
  type CreateIntentDbResult,
  type LinkIntentDataPort,
  type LinkIntentDeps,
} from "./link-intent.ts";

const VALID_CREATE_REQUEST = {
  brainActorId: "brain-actor-1",
  brainConfirmedEmail: "customer@example.com",
  brainBusinessId: "11111111-1111-1111-1111-111111111111",
  normalizedHost: "example.com",
};

function fakeDeps(overrides: Partial<LinkIntentDeps> = {}): LinkIntentDeps & {
  createCalls: unknown[];
  pendingEmailCalls: string[];
  finalizeCalls: Array<{ intentId: string; seoUserId: string }>;
  createUserCalls: string[];
} {
  const createCalls: unknown[] = [];
  const pendingEmailCalls: string[] = [];
  const finalizeCalls: Array<{ intentId: string; seoUserId: string }> = [];
  const createUserCalls: string[] = [];

  const db: LinkIntentDataPort = {
    async createIntent(request) {
      createCalls.push(request);
      return {
        resolution: "created",
        intentId: "intent-1",
        launchCode: "deadbeef",
        redemptionExpiresAt: "2026-01-01T00:02:00.000Z",
      } satisfies CreateIntentDbResult;
    },
    async pendingProvisioningEmail(intentId) {
      pendingEmailCalls.push(intentId);
      return "customer@example.com";
    },
    async finalizeCaseA(intentId, seoUserId) {
      finalizeCalls.push({ intentId, seoUserId });
      return { resolution: "resolved", intentId, seoUserId };
    },
  };

  const admin: AdminAuthPort = {
    async createPasswordlessUser(email) {
      createUserCalls.push(email);
      return { userId: "new-user-1" };
    },
  };

  return { db, admin, createCalls, pendingEmailCalls, finalizeCalls, createUserCalls, ...overrides };
}

describe("validateCreateLinkIntentRequest", () => {
  it("accepts a well formed request", () => {
    expect(validateCreateLinkIntentRequest(VALID_CREATE_REQUEST)).toEqual(VALID_CREATE_REQUEST);
  });

  it.each([
    ["a non-object body", "not an object"],
    ["a missing brainActorId", { ...VALID_CREATE_REQUEST, brainActorId: undefined }],
    ["an empty brainActorId", { ...VALID_CREATE_REQUEST, brainActorId: "  " }],
    ["a missing brainConfirmedEmail", { ...VALID_CREATE_REQUEST, brainConfirmedEmail: undefined }],
    ["a missing brainBusinessId", { ...VALID_CREATE_REQUEST, brainBusinessId: undefined }],
    ["a missing normalizedHost", { ...VALID_CREATE_REQUEST, normalizedHost: undefined }],
    ["a non-string businessDisplayName", { ...VALID_CREATE_REQUEST, businessDisplayName: 5 }],
  ])("refuses %s", (_label, body) => {
    expect(() => validateCreateLinkIntentRequest(body)).toThrow(LinkIntentError);
  });

  it("trims every field and drops an absent optional field", () => {
    const result = validateCreateLinkIntentRequest({
      ...VALID_CREATE_REQUEST,
      brainActorId: "  brain-actor-1  ",
      businessDisplayName: undefined,
    });
    expect(result.brainActorId).toBe("brain-actor-1");
    expect(result.businessDisplayName).toBeUndefined();
  });
});

describe("handleCreateLinkIntent", () => {
  it("returns the created intent on success", async () => {
    const deps = fakeDeps();
    const result = await handleCreateLinkIntent(VALID_CREATE_REQUEST, deps);
    expect(result).toEqual({
      intentId: "intent-1",
      launchCode: "deadbeef",
      redemptionExpiresAt: "2026-01-01T00:02:00.000Z",
    });
    expect(deps.createCalls).toHaveLength(1);
  });

  it("raises invalid_request when the database refuses the intent", async () => {
    const deps = fakeDeps({
      db: {
        async createIntent() {
          return { resolution: "invalid_request", detail: "normalized_host is not canonical" };
        },
        async pendingProvisioningEmail() {
          return null;
        },
        async finalizeCaseA() {
          return { resolution: "invalid_or_expired_intent" };
        },
      },
    } as Partial<LinkIntentDeps>);

    await expect(handleCreateLinkIntent(VALID_CREATE_REQUEST, deps)).rejects.toMatchObject({
      code: "invalid_request",
    });
  });

  it("raises module_unavailable on an unrecognized database result", async () => {
    const deps = fakeDeps({
      db: {
        async createIntent() {
          return { resolution: "created" } as CreateIntentDbResult; // missing intentId/launchCode
        },
        async pendingProvisioningEmail() {
          return null;
        },
        async finalizeCaseA() {
          return { resolution: "invalid_or_expired_intent" };
        },
      },
    } as Partial<LinkIntentDeps>);

    await expect(handleCreateLinkIntent(VALID_CREATE_REQUEST, deps)).rejects.toMatchObject({
      code: "module_unavailable",
    });
  });
});

describe("validateProvisionRequest", () => {
  it("accepts a bare intentId and nothing else", () => {
    expect(validateProvisionRequest({ intentId: "intent-1" })).toEqual({ intentId: "intent-1" });
  });

  it("refuses a missing intentId", () => {
    expect(() => validateProvisionRequest({})).toThrow(LinkIntentError);
  });

  // The request shape itself carries no email field, so there is nothing a
  // caller could supply that handleProvisionCaseA would ever read as one.
  it("has no email field in its accepted shape", () => {
    const parsed = validateProvisionRequest({ intentId: "intent-1", email: "attacker@evil.example" });
    expect(parsed).toEqual({ intentId: "intent-1" });
  });
});

describe("handleProvisionCaseA", () => {
  it("creates the account for the email SEO already has on file, never a caller supplied one", async () => {
    const deps = fakeDeps();
    const result = await handleProvisionCaseA({ intentId: "intent-1", email: "attacker@evil.example" }, deps);

    expect(deps.pendingEmailCalls).toEqual(["intent-1"]);
    // The only email ever handed to account creation is the one the trusted
    // lookup returned, regardless of what the request body also contained.
    expect(deps.createUserCalls).toEqual(["customer@example.com"]);
    expect(deps.finalizeCalls).toEqual([{ intentId: "intent-1", seoUserId: "new-user-1" }]);
    expect(result).toEqual({ intentId: "intent-1", seoUserId: "new-user-1" });
  });

  it("refuses with not_pending when the intent is not awaiting provisioning", async () => {
    const deps = fakeDeps({
      db: {
        async createIntent() {
          throw new Error("unused");
        },
        async pendingProvisioningEmail() {
          return null;
        },
        async finalizeCaseA() {
          throw new Error("unused");
        },
      },
    } as Partial<LinkIntentDeps>);

    await expect(handleProvisionCaseA({ intentId: "intent-1" }, deps)).rejects.toMatchObject({
      code: "not_pending",
    });
  });

  it("refuses with provisioning_failed when account creation fails, without finalizing", async () => {
    const deps = fakeDeps({
      admin: {
        async createPasswordlessUser() {
          return { error: "email already exists" };
        },
      },
    } as Partial<LinkIntentDeps>);

    await expect(handleProvisionCaseA({ intentId: "intent-1" }, deps)).rejects.toMatchObject({
      code: "provisioning_failed",
    });
    expect(deps.finalizeCalls).toHaveLength(0);
  });

  it("refuses with finalize_failed when the account was created but finalize refuses", async () => {
    const deps = fakeDeps({
      db: {
        async createIntent() {
          throw new Error("unused");
        },
        async pendingProvisioningEmail() {
          return "customer@example.com";
        },
        async finalizeCaseA() {
          return { resolution: "actor_conflict" };
        },
      },
    } as Partial<LinkIntentDeps>);

    await expect(handleProvisionCaseA({ intentId: "intent-1" }, deps)).rejects.toMatchObject({
      code: "finalize_failed",
    });
  });
});
