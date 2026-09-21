import { describe, expect, it } from "vitest";
import { linkIntentPathFromUrl, serveLinkIntentRequest } from "./link-intent-http.ts";
import type { AdminAuthPort, LinkIntentDataPort, LinkIntentDeps } from "./link-intent.ts";

const SECRET = "a".repeat(48);
const config = { moduleApiSecret: SECRET };
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
    async pendingProvisioningEmail() {
      return "customer@example.com";
    },
    async finalizeCaseA(intentId, seoUserId) {
      return { resolution: "resolved", intentId, seoUserId };
    },
  };
  const admin: AdminAuthPort = {
    async createPasswordlessUser() {
      return { userId: "new-user-1" };
    },
  };
  return { db, admin, log: (event) => events.push(event), events };
}

describe("linkIntentPathFromUrl", () => {
  it.each([
    [`${BASE}/link-intent/create`, "create"],
    [`${BASE}/link-intent/provision`, "provision"],
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
      { moduleApiSecret: "" },
      deps(),
    );
    expect(response.status).toBe(503);
  });
});

describe("link-intent/provision", () => {
  it("is reachable with no machine secret at all, because a browser cannot hold one", async () => {
    const response = await serveLinkIntentRequest(post("provision", { intentId: "intent-1" }), "provision", config, deps());
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ intentId: "intent-1", seoUserId: "new-user-1" });
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
