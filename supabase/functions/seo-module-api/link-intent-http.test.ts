import { describe, expect, it } from "vitest";
import { linkIntentPathFromUrl, parseAllowedOrigins, serveLinkIntentRequest } from "./link-intent-http.ts";
import type { AdminAuthPort, LinkIntentDataPort, LinkIntentDeps } from "./link-intent.ts";

const SECRET = "a".repeat(48);
const ORIGIN = "https://seo.digibility.example";
const config = { moduleApiSecret: SECRET, allowedOrigins: [ORIGIN] };
const BASE = "https://seo.example/functions/v1/seo-module-api";

function post(path: string, body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`${BASE}/link-intent/${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

function deps(): LinkIntentDeps & { log: (event: Record<string, unknown>) => void; events: unknown[] } {
  const events: unknown[] = [];
  const db: LinkIntentDataPort = {
    async createIntent() {
      return {
        resolution: "created",
        intentId: "intent-1",
        launchCode: "deadbeef",
        redemptionExpiresAt: "2026-01-01T00:02:00.000Z",
      };
    },
    async pendingProvisioning() {
      return { intentId: "intent-1", email: "customer@example.com" };
    },
    async finalizeCaseA(intentId, seoUserId) {
      return { resolution: "resolved", intentId, seoUserId };
    },
    async continuationByCode() {
      return { intentId: "intent-1", seoUserId: "mapped-user-1", email: "customer@example.com" };
    },
  };
  const admin: AdminAuthPort = {
    async createPasswordlessUser() {
      return { userId: "new-user-1" };
    },
    async generateMagicLinkToken() {
      return { tokenHash: "hashed-token-1" };
    },
    async deleteUser() {
      return { ok: true };
    },
  };
  return { db, admin, log: (event) => events.push(event), events };
}

describe("linkIntentPathFromUrl", () => {
  it.each([
    [`${BASE}/link-intent/create`, "create"],
    [`${BASE}/link-intent/provision`, "provision"],
    [`${BASE}/link-intent/continue`, "continue"],
    [`${BASE}/analyse`, null],
    [`${BASE}/link-intent/unknown`, null],
    [`${BASE}/link-intent`, null],
  ])("resolves %s to %s", (url, expected) => {
    expect(linkIntentPathFromUrl(url)).toBe(expected);
  });
});

describe("link-intent/create machine credential", () => {
  it("accepts a caller presenting the configured secret", async () => {
    const response = await serveLinkIntentRequest(
      post("create", {
        brainActorId: "brain-actor-1",
        brainConfirmedEmail: "customer@example.com",
        brainBusinessId: "11111111-1111-1111-1111-111111111111",
        normalizedHost: "example.com",
      }, { authorization: `Bearer ${SECRET}` }),
      "create",
      config,
      deps(),
    );
    expect(response.status).toBe(200);
  });

  it.each([
    ["no secret header", {}],
    ["a wrong bearer token", { authorization: `Bearer ${"b".repeat(48)}` }],
  ])("refuses a caller with %s", async (_label, headers) => {
    const dependencies = deps();
    const response = await serveLinkIntentRequest(post("create", {}, headers), "create", config, dependencies);
    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: { code: "unauthorized", message: expect.any(String) },
    });
  });

  it("fails closed with module_unavailable when the endpoint has no secret configured", async () => {
    const response = await serveLinkIntentRequest(
      post("create", {}, { authorization: "Bearer whatever" }),
      "create",
      { moduleApiSecret: "", allowedOrigins: [] },
      deps(),
    );
    expect(response.status).toBe(503);
  });
});

describe("link-intent/provision", () => {
  it("is reachable with no machine secret at all, because a browser cannot hold one", async () => {
    const response = await serveLinkIntentRequest(post("provision", { launchCode: "code-1" }), "provision", config, deps());
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      intentId: "intent-1",
      tokenHash: "hashed-token-1",
      otpType: "magiclink",
    });
  });

  it("refuses a non-POST method", async () => {
    const request = new Request(`${BASE}/link-intent/provision`, { method: "GET" });
    const response = await serveLinkIntentRequest(request, "provision", config, deps());
    expect(response.status).toBe(400);
  });

  it("refuses invalid JSON with invalid_request", async () => {
    const request = new Request(`${BASE}/link-intent/provision`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "not json",
    });
    const response = await serveLinkIntentRequest(request, "provision", config, deps());
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: { code: "invalid_request", message: expect.any(String) },
    });
  });
});

describe("link-intent/continue", () => {
  it("is reachable with no machine secret at all, because a browser cannot hold one", async () => {
    const response = await serveLinkIntentRequest(post("continue", { launchCode: "code-1" }), "continue", config, deps());
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      intentId: "intent-1",
      tokenHash: "hashed-token-1",
      otpType: "magiclink",
    });
  });

  it("refuses not_continuable as a 409 when the launch code is not eligible", async () => {
    const dependencies = deps();
    dependencies.db.continuationByCode = async () => null;
    const response = await serveLinkIntentRequest(post("continue", { launchCode: "code-1" }), "continue", config, dependencies);
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toEqual({
      error: { code: "not_continuable", message: expect.any(String) },
    });
  });

  it("allows a configured SEO origin, same as provision", async () => {
    const response = await serveLinkIntentRequest(
      post("continue", { launchCode: "code-1" }, { origin: ORIGIN }),
      "continue",
      config,
      deps(),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBe(ORIGIN);
  });

  it("refuses an origin outside the allow-list, same as provision", async () => {
    const response = await serveLinkIntentRequest(
      post("continue", { launchCode: "code-1" }, { origin: "https://evil.example" }),
      "continue",
      config,
      deps(),
    );
    expect(response.status).toBe(403);
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("link-intent/provision CORS", () => {
  it("allows a configured SEO origin: preflight and POST both echo exactly that origin", async () => {
    const preflight = await serveLinkIntentRequest(
      new Request(`${BASE}/link-intent/provision`, { method: "OPTIONS", headers: { origin: ORIGIN } }),
      "provision",
      config,
      deps(),
    );
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("access-control-allow-origin")).toBe(ORIGIN);
    expect(preflight.headers.get("access-control-allow-methods")).toBe("POST, OPTIONS");
    expect(preflight.headers.get("vary")).toBe("Origin");

    const response = await serveLinkIntentRequest(
      post("provision", { launchCode: "code-1" }, { origin: ORIGIN }),
      "provision",
      config,
      deps(),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBe(ORIGIN);
  });

  it("refuses an origin outside the allow-list, for preflight and POST, with no CORS headers", async () => {
    const dependencies = deps();
    for (const request of [
      new Request(`${BASE}/link-intent/provision`, { method: "OPTIONS", headers: { origin: "https://evil.example" } }),
      post("provision", { launchCode: "code-1" }, { origin: "https://evil.example" }),
    ]) {
      const response = await serveLinkIntentRequest(request, "provision", config, dependencies);
      expect(response.status).toBe(403);
      expect(response.headers.get("access-control-allow-origin")).toBeNull();
    }
  });

  it("refuses every browser origin when no origin is configured", async () => {
    const response = await serveLinkIntentRequest(
      post("provision", { launchCode: "code-1" }, { origin: ORIGIN }),
      "provision",
      { moduleApiSecret: SECRET, allowedOrigins: [] },
      deps(),
    );
    expect(response.status).toBe(403);
  });

  it("never sends CORS headers on the machine-only create path", async () => {
    const response = await serveLinkIntentRequest(
      post("create", {}, { origin: ORIGIN, authorization: `Bearer ${SECRET}` }),
      "create",
      config,
      deps(),
    );
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
  });

  it("parseAllowedOrigins drops a wildcard and trailing slashes", () => {
    expect(parseAllowedOrigins(" https://a.example/ , *, ,https://b.example")).toEqual([
      "https://a.example",
      "https://b.example",
    ]);
    expect(parseAllowedOrigins(undefined)).toEqual([]);
  });
});
