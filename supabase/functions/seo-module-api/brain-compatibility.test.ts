import { describe, expect, it } from "vitest";
import { familyFromUrl, serveModuleRequest } from "./http.ts";
import { SEO_MODULE_DECLARATION } from "./capabilities.ts";
import { FakeSeoDataPort, baseStore, executeRequest, moduleRequest, statusRequest } from "./test-support.ts";

/**
 * Wire compatibility with Digi Brain Stage 2A (Digi_Brain 96baf21,
 * server/modules/seo/{transport,capabilities,adapter}.ts).
 *
 * These assertions encode what the Brain side actually does, so a future change
 * on either side that breaks the integration fails here rather than in a live
 * environment. They are deliberately written against observed Brain behaviour,
 * not against an idealized reading of the contract.
 */

const SECRET = "a".repeat(48);
const config = { moduleApiSecret: SECRET };
const BASE = "https://seo.internal.example.com/api/module-contract";

function deps() {
  return { db: new FakeSeoDataPort(baseStore()) };
}

/** Exactly how server/modules/seo/transport.ts builds a request. */
function brainPost(family: string, body: unknown): Request {
  return new Request(`${BASE}/${family}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${SECRET}` },
    body: JSON.stringify(body),
  });
}

describe("Digi Brain Stage 2A wire compatibility", () => {
  it("routes the capability-family paths Brain posts to", () => {
    expect(familyFromUrl(`${BASE}/analyse`)).toBe("analyse");
    expect(familyFromUrl(`${BASE}/execute`)).toBe("execute");
    expect(familyFromUrl(`${BASE}/status`)).toBe("status");
    // Declared by neither side in Stage 2A.
    expect(familyFromUrl(`${BASE}/verify`)).toBeNull();
    expect(familyFromUrl(`${BASE}/result-evidence`)).toBeNull();
  });

  it("works whichever path prefix the endpoint is mounted under", () => {
    expect(familyFromUrl("https://x.supabase.co/functions/v1/seo-module-api/analyse")).toBe("analyse");
    expect(familyFromUrl(`${BASE}/analyse`)).toBe("analyse");
  });

  it("declares exactly the six capability keys Brain Stage 2A sends", () => {
    expect(SEO_MODULE_DECLARATION.capabilities).toEqual([
      "analyse.target_linkage",
      "analyse.ownership_verification",
      "execute.technical_audit",
      "analyse.technical_audit",
      "execute.recommendations",
      "analyse.recommendations",
    ]);
    expect(SEO_MODULE_DECLARATION.contractVersion).toBe("module-contract.v1");
    expect(SEO_MODULE_DECLARATION.moduleId).toBe("seo");
  });

  it("accepts Brain's bearer credential", async () => {
    const response = await serveModuleRequest(brainPost("analyse", moduleRequest()), config, deps());
    expect(response.status).toBe(200);
  });

  it("returns an analyse envelope Brain's validateResponseBase accepts", async () => {
    const response = await serveModuleRequest(brainPost("analyse", moduleRequest()), config, deps());
    const body = (await response.json()) as Record<string, unknown>;

    // Brain refuses on any of these.
    expect(body.businessId).toBe("biz-1");
    expect(body.websiteIdentity).toEqual({
      normalizedHost: "example.com",
      assessedUrl: "https://www.example.com/",
    });
    expect(body.dataAuthenticity).toBe("genuine");
    expect(["measured_external", "first_party_connected", "public_signal", "customer_provided", "calculated", "inference"])
      .toContain(body.observationMethod);
    expect(["measured", "derived", "estimated", "declared"])
      .toContain((body.provenance as { basis: string }).basis);
    expect(Array.isArray(body.findings)).toBe(true);
  });

  it("echoes brainActionId on execute, which Brain's adapter enforces", async () => {
    const response = await serveModuleRequest(brainPost("execute", executeRequest()), config, deps());
    const body = (await response.json()) as Record<string, unknown>;

    // enforceBrainActionCorrelation in server/modules/seo/adapter.ts.
    expect(body.brainActionId).toBe("brain-action-1");
    expect(body.accepted).toBe(true);
    expect(typeof body.moduleStatus).toBe("string");
    expect(typeof body.moduleOperationId).toBe("string");
  });

  it("echoes brainActionId on status too", async () => {
    const dependencies = deps();
    await serveModuleRequest(brainPost("execute", executeRequest()), config, dependencies);
    const response = await serveModuleRequest(brainPost("status", statusRequest()), config, dependencies);
    const body = (await response.json()) as Record<string, unknown>;

    expect(body.brainActionId).toBe("brain-action-1");
    expect(typeof body.moduleStatus).toBe("string");
  });

  it("accepts Brain's derived idempotency key format verbatim", async () => {
    // deriveModuleIdempotencyKey(brainActionId, capability) === `${id}:${cap}`
    const request = executeRequest();
    expect(request.idempotencyKey).toBe("brain-action-1:execute.technical_audit");
    const response = await serveModuleRequest(brainPost("execute", request), config, deps());
    expect(response.status).toBe(200);
  });

  it("returns the closed error envelope Brain's transport reconstructs", async () => {
    const response = await serveModuleRequest(
      brainPost("analyse", moduleRequest({ businessId: "biz-unknown" })),
      config,
      deps(),
    );
    const body = (await response.json()) as { error: { code: string; message: string } };

    expect(response.ok).toBe(false);
    expect(body.error.code).toBe("target_not_linked");
    expect(typeof body.error.message).toBe("string");
  });

  it("keeps every error status out of the 5xx range unless the module is truly degraded", async () => {
    // Brain maps an unclassified 5xx onto module_unavailable, so a refusal that
    // SEO has classified must not be sent as a 5xx.
    const cases: Array<[string, unknown, string]> = [
      ["analyse", moduleRequest({ businessId: "biz-unknown" }), "target_not_linked"],
      ["analyse", moduleRequest({ capability: "analyse.nope" }), "unsupported_capability"],
      ["analyse", moduleRequest({ contractVersion: "module-contract.v2" }), "invalid_request"],
      ["execute", executeRequest({ actorId: "brain-actor-unknown" }), "unauthorized"],
    ];
    for (const [family, body, expectedCode] of cases) {
      const response = await serveModuleRequest(brainPost(family, body), config, deps());
      const parsed = (await response.json()) as { error: { code: string } };
      expect(parsed.error.code).toBe(expectedCode);
      expect(response.status).toBeLessThan(500);
    }
  });
});
