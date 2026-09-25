import { describe, expect, it } from "vitest";
import {
  LinkIntentError,
  handleContinueCaseD,
  handleCreateLinkIntent,
  handleProvisionCaseA,
  validateCreateLinkIntentRequest,
  validateProvisionRequest,
  type AdminAuthPort,
  type CreateIntentDbResult,
  type LinkIntentDataPort,
  type LinkIntentDeps,
} from "./link-intent.ts";
import { createSupabaseAdminAuthPort, type AdminUserApi } from "./link-intent-port.ts";

const VALID_CREATE_REQUEST = {
  brainActorId: "brain-actor-1",
  brainConfirmedEmail: "customer@example.com",
  brainBusinessId: "11111111-1111-1111-1111-111111111111",
  normalizedHost: "example.com",
};

type FakeDeps = LinkIntentDeps & {
  createCalls: unknown[];
  pendingCalls: string[];
  finalizeCalls: Array<{ intentId: string; seoUserId: string }>;
  continuationCalls: string[];
  createUserCalls: string[];
  linkCalls: string[];
  deleteCalls: string[];
  events: Array<Record<string, unknown>>;
};

function fakeDeps(
  overrides: { db?: Partial<LinkIntentDataPort>; admin?: Partial<AdminAuthPort> } = {},
): FakeDeps {
  const createCalls: unknown[] = [];
  const pendingCalls: string[] = [];
  const finalizeCalls: Array<{ intentId: string; seoUserId: string }> = [];
  const continuationCalls: string[] = [];
  const createUserCalls: string[] = [];
  const linkCalls: string[] = [];
  const deleteCalls: string[] = [];
  const events: Array<Record<string, unknown>> = [];

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
    async pendingProvisioning(launchCode) {
      pendingCalls.push(launchCode);
      return { intentId: "intent-1", email: "customer@example.com" };
    },
    async finalizeCaseA(intentId, seoUserId) {
      finalizeCalls.push({ intentId, seoUserId });
      return { resolution: "resolved", intentId, seoUserId };
    },
    async continuationByCode(launchCode) {
      continuationCalls.push(launchCode);
      return { intentId: "intent-1", seoUserId: "mapped-user-1", email: "customer@example.com" };
    },
    ...overrides.db,
  };

  const admin: AdminAuthPort = {
    async createPasswordlessUser(email) {
      createUserCalls.push(email);
      return { userId: "new-user-1" };
    },
    async generateMagicLinkToken(email) {
      linkCalls.push(email);
      return { tokenHash: "hashed-token-1" };
    },
    async deleteUser(userId) {
      deleteCalls.push(userId);
      return { ok: true };
    },
    ...overrides.admin,
  };

  return {
    db,
    admin,
    log: (event) => events.push(event),
    createCalls,
    pendingCalls,
    finalizeCalls,
    continuationCalls,
    createUserCalls,
    linkCalls,
    deleteCalls,
    events,
  };
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
      },
    });

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
      },
    });

    await expect(handleCreateLinkIntent(VALID_CREATE_REQUEST, deps)).rejects.toMatchObject({
      code: "module_unavailable",
    });
  });
});

describe("validateProvisionRequest", () => {
  it("accepts a bare launchCode and nothing else", () => {
    expect(validateProvisionRequest({ launchCode: "code-1" })).toEqual({ launchCode: "code-1" });
  });

  it("refuses a missing launchCode", () => {
    expect(() => validateProvisionRequest({})).toThrow(LinkIntentError);
  });

  it("does not accept an intentId in place of the launch code", () => {
    expect(() => validateProvisionRequest({ intentId: "intent-1" })).toThrow(LinkIntentError);
  });

  // The accepted shape carries no email field, so there is nothing a caller
  // could supply that handleProvisionCaseA would ever read as one.
  it("has no email field in its accepted shape", () => {
    const parsed = validateProvisionRequest({ launchCode: "code-1", email: "attacker@evil.example" });
    expect(parsed).toEqual({ launchCode: "code-1" });
  });
});

describe("handleProvisionCaseA", () => {
  it("case A: creates the account, finalizes and returns only the passwordless sign-in material", async () => {
    const deps = fakeDeps();
    const result = await handleProvisionCaseA({ launchCode: "code-1", email: "attacker@evil.example" }, deps);

    expect(deps.pendingCalls).toEqual(["code-1"]);
    // The only email ever handed to account creation or link generation is the
    // one the trusted lookup returned, regardless of the request body.
    expect(deps.createUserCalls).toEqual(["customer@example.com"]);
    expect(deps.linkCalls).toEqual(["customer@example.com"]);
    expect(deps.finalizeCalls).toEqual([{ intentId: "intent-1", seoUserId: "new-user-1" }]);
    expect(deps.deleteCalls).toEqual([]);
    expect(result).toEqual({ intentId: "intent-1", tokenHash: "hashed-token-1", otpType: "magiclink" });
    // No user id, email or credential is exposed to the browser.
    expect(JSON.stringify(result)).not.toContain("new-user-1");
    expect(JSON.stringify(result)).not.toContain("customer@example.com");
  });

  it("never logs the token material", async () => {
    const deps = fakeDeps();
    await handleProvisionCaseA({ launchCode: "code-1" }, deps);
    expect(JSON.stringify(deps.events)).not.toContain("hashed-token-1");
  });

  it("refuses with not_pending when the launch code is not awaiting provisioning", async () => {
    const deps = fakeDeps({ db: { async pendingProvisioning() { return null; } } });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toMatchObject({ code: "not_pending" });
    expect(deps.createUserCalls).toHaveLength(0);
  });

  it("duplicate-email race: refuses as existing_account and never touches the pre-existing user", async () => {
    const deps = fakeDeps({
      admin: {
        async createPasswordlessUser() {
          return { error: "A user with this email address has already been registered", duplicate: true };
        },
      },
    });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "existing_account",
    });
    expect(deps.finalizeCalls).toHaveLength(0);
    expect(deps.linkCalls).toHaveLength(0);
    expect(deps.deleteCalls).toHaveLength(0);
  });

  it("refuses with provisioning_failed on any other account creation failure, without finalizing or deleting", async () => {
    const deps = fakeDeps({
      admin: {
        async createPasswordlessUser() {
          return { error: "upstream unavailable" };
        },
      },
    });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "provisioning_failed",
    });
    expect(deps.finalizeCalls).toHaveLength(0);
    expect(deps.deleteCalls).toHaveLength(0);
  });

  it("finalize failure: cleans up exactly the user it created and returns no token", async () => {
    const deps = fakeDeps({
      db: {
        async finalizeCaseA() {
          return { resolution: "actor_conflict" };
        },
      },
    });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "finalize_failed",
    });
    expect(deps.deleteCalls).toEqual(["new-user-1"]);
  });

  it("finalize failure: still reports finalize_failed when the cleanup itself fails", async () => {
    const deps = fakeDeps({
      db: {
        async finalizeCaseA() {
          return { resolution: "identity_mismatch" };
        },
      },
      admin: {
        async deleteUser() {
          return { error: "delete refused" };
        },
      },
    });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "finalize_failed",
    });
    expect(deps.events.some((event) => event.event === "seo_link_intent_provision_cleanup" && event.removed === false)).toBe(true);
  });

  it("finalize throwing: cleans up the created user and rethrows", async () => {
    const deps = fakeDeps({
      db: {
        async finalizeCaseA() {
          throw new Error("rpc transport down");
        },
      },
    });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toThrow("rpc transport down");
    expect(deps.deleteCalls).toEqual(["new-user-1"]);
  });

  it("link generation failure: cleans up the created user and never finalizes", async () => {
    const deps = fakeDeps({
      admin: {
        async generateMagicLinkToken() {
          return { error: "generateLink failed" };
        },
      },
    });
    await expect(handleProvisionCaseA({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "provisioning_failed",
    });
    expect(deps.deleteCalls).toEqual(["new-user-1"]);
    expect(deps.finalizeCalls).toHaveLength(0);
  });
});

describe("handleContinueCaseD", () => {
  it("case D: mints a magic link for the already-mapped user and returns only sign-in material", async () => {
    const deps = fakeDeps();
    const result = await handleContinueCaseD({ launchCode: "code-1" }, deps);

    expect(deps.continuationCalls).toEqual(["code-1"]);
    expect(deps.linkCalls).toEqual(["customer@example.com"]);
    // No user is created, deleted, or finalized for case D: the mapping and
    // module access already exist.
    expect(deps.createUserCalls).toHaveLength(0);
    expect(deps.deleteCalls).toHaveLength(0);
    expect(deps.finalizeCalls).toHaveLength(0);
    expect(result).toEqual({ intentId: "intent-1", tokenHash: "hashed-token-1", otpType: "magiclink" });
    expect(JSON.stringify(result)).not.toContain("mapped-user-1");
    expect(JSON.stringify(result)).not.toContain("customer@example.com");
  });

  it("refuses with not_continuable when the launch code is not eligible for continuation", async () => {
    const deps = fakeDeps({ db: { async continuationByCode() { return null; } } });
    await expect(handleContinueCaseD({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "not_continuable",
    });
    expect(deps.linkCalls).toHaveLength(0);
  });

  it("refuses with continuation_failed when the magic link cannot be generated", async () => {
    const deps = fakeDeps({
      admin: {
        async generateMagicLinkToken() {
          return { error: "generateLink failed" };
        },
      },
    });
    await expect(handleContinueCaseD({ launchCode: "code-1" }, deps)).rejects.toMatchObject({
      code: "continuation_failed",
    });
  });

  it("rejects a missing launchCode the same way provision does", async () => {
    const deps = fakeDeps();
    await expect(handleContinueCaseD({}, deps)).rejects.toMatchObject({ code: "invalid_request" });
    expect(deps.continuationCalls).toHaveLength(0);
  });
});

describe("createSupabaseAdminAuthPort", () => {
  function api(overrides: Partial<AdminUserApi> = {}): AdminUserApi {
    return {
      async createUser() {
        return { data: { user: { id: "u1" } }, error: null };
      },
      async generateLink() {
        return { data: { properties: { hashed_token: "tok" } }, error: null };
      },
      async deleteUser() {
        return { error: null };
      },
      ...overrides,
    };
  }

  it("flags an already registered email as a duplicate", async () => {
    for (const error of [
      { message: "x", code: "email_exists" },
      { message: "x", status: 422 },
      { message: "A user with this email address has already been registered" },
    ]) {
      const port = createSupabaseAdminAuthPort(api({ async createUser() { return { data: null, error }; } }));
      await expect(port.createPasswordlessUser("a@b.co")).resolves.toMatchObject({ duplicate: true });
    }
  });

  it("does not flag an unrelated failure as a duplicate", async () => {
    const port = createSupabaseAdminAuthPort(
      api({ async createUser() { return { data: null, error: { message: "timeout" } }; } }),
    );
    const result = await port.createPasswordlessUser("a@b.co");
    expect(result).toEqual({ error: "timeout" });
  });

  it("returns only the hashed token from generateLink, and an error when it is absent", async () => {
    await expect(createSupabaseAdminAuthPort(api()).generateMagicLinkToken("a@b.co")).resolves.toEqual({ tokenHash: "tok" });
    const empty = createSupabaseAdminAuthPort(api({ async generateLink() { return { data: { properties: null }, error: null }; } }));
    await expect(empty.generateMagicLinkToken("a@b.co")).resolves.toHaveProperty("error");
  });
});
