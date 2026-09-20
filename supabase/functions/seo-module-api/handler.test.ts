import { describe, expect, it } from "vitest";
import { SeoModuleContractError } from "./contract.ts";
import { handleModuleRequest } from "./handler.ts";
import {
  CAP_GENERATE_RECOMMENDATIONS,
  CAP_OWNERSHIP_VERIFICATION,
  CAP_READ_RECOMMENDATIONS,
  CAP_READ_TECHNICAL_AUDIT,
  CAP_REQUEST_TECHNICAL_AUDIT,
  CAP_TARGET_LINKAGE,
  DECLARED_CAPABILITIES,
  isExecuteCapability,
} from "./capabilities.ts";
import {
  FakeSeoDataPort,
  baseStore,
  crawlerFinding,
  generatedRecommendation,
  moduleRequest,
  type FakeStore,
} from "./test-support.ts";

function deps(store: FakeStore = baseStore()) {
  const db = new FakeSeoDataPort(store);
  return { db, handlerDeps: { db } };
}

async function expectErrorCode(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toBeInstanceOf(SeoModuleContractError);
  await promise.catch((error: SeoModuleContractError) => {
    expect(error.code).toBe(code);
  });
}

// ---------------------------------------------------------------------------
// Deterministic identity
// ---------------------------------------------------------------------------

describe("deterministic target resolution", () => {
  it("resolves an exact Business plus canonical host to its linked website", async () => {
    const { db, handlerDeps } = deps();
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_TARGET_LINKAGE }),
      "analyse",
      handlerDeps,
    );

    expect(result.dataAuthenticity).toBe("genuine");
    // The link is a human's declaration, not a measurement.
    expect(result.provenance.basis).toBe("declared");
    expect(result.observationMethod).toBe("customer_provided");
    // A successful linkage check with no findings IS the answer.
    expect(result.findings).toEqual([]);
    expect(db.calls[0]).toEqual({
      method: "resolveTarget",
      businessId: "biz-1",
      normalizedHost: "example.com",
    });
  });

  it("refuses a Business that has no link at all", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(
        moduleRequest({ capability: CAP_TARGET_LINKAGE, businessId: "biz-unknown" }),
        "analyse",
        handlerDeps,
      ),
      "target_not_linked",
    );
  });

  it("refuses the WRONG Business for a host another Business owns", async () => {
    const { handlerDeps } = deps();
    // biz-2 is real and linked, but to other.test, never to example.com.
    await expectErrorCode(
      handleModuleRequest(
        moduleRequest({ capability: CAP_TARGET_LINKAGE, businessId: "biz-2" }),
        "analyse",
        handlerDeps,
      ),
      "target_not_linked",
    );
  });

  it("refuses the WRONG host for a Business that is linked to another host", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(
        moduleRequest({
          capability: CAP_TARGET_LINKAGE,
          websiteIdentity: {
            normalizedHost: "shop.example.com",
            assessedUrl: "https://shop.example.com/",
          },
        }),
        "analyse",
        handlerDeps,
      ),
      "target_not_linked",
    );
  });

  it("refuses a revoked link instead of honouring it", async () => {
    const store = baseStore();
    store.links = [
      { businessId: "biz-1", websiteId: "site-a", normalizedHost: "example.com", linkStatus: "revoked" },
    ];
    const { handlerDeps } = deps(store);
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: CAP_TARGET_LINKAGE }), "analyse", handlerDeps),
      "target_not_linked",
    );
  });

  it("stops resolving when the linked website's URL no longer matches the linked host", async () => {
    const store = baseStore();
    // The website was edited to a different identity after the link was made.
    store.websites[0].websiteUrl = "https://renamed.example.org";
    const { handlerDeps } = deps(store);
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: CAP_TARGET_LINKAGE }), "analyse", handlerDeps),
      "target_not_linked",
    );
  });

  it("refuses an archived or inactive website", async () => {
    const store = baseStore();
    store.websites[0].isActive = false;
    const { handlerDeps } = deps(store);
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: CAP_TARGET_LINKAGE }), "analyse", handlerDeps),
      "target_not_linked",
    );
  });
});

describe("no substitution of any kind", () => {
  it("never falls back to a sibling website in the same workspace", async () => {
    const store = baseStore();
    // site-a is linked but has no completed audit; its sibling site-b has one.
    store.audits = { ...store.audits, "site-a": null };
    const { handlerDeps } = deps(store);

    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT }),
      "analyse",
      handlerDeps,
    );

    // An empty genuine answer, never the neighbour's data.
    expect(result.findings).toEqual([]);
    expect(JSON.stringify(result)).not.toContain("SIBLING::b");
  });

  it("never returns another tenant's findings", async () => {
    const { handlerDeps } = deps();
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT }),
      "analyse",
      handlerDeps,
    );
    expect(JSON.stringify(result)).not.toContain("TENANT::c");
    expect(result.findings.map((finding) => finding.findingKey)).toEqual(["MISSING_TITLE::abc123"]);
  });

  it("echoes the requested identity verbatim so Brain can detect a substitution", async () => {
    const { handlerDeps } = deps();
    const request = moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT });
    const result = await handleModuleRequest(request, "analyse", handlerDeps);

    expect(result.businessId).toBe("biz-1");
    expect(result.websiteIdentity).toEqual({
      normalizedHost: "example.com",
      assessedUrl: "https://www.example.com/",
    });
  });
});

// ---------------------------------------------------------------------------
// Capability gating and actor identity
// ---------------------------------------------------------------------------

describe("capability gating", () => {
  it("declares exactly Digi Brain's six Stage 2A capability keys", () => {
    expect(DECLARED_CAPABILITIES).toEqual([
      "analyse.target_linkage",
      "analyse.ownership_verification",
      "execute.technical_audit",
      "analyse.technical_audit",
      "execute.recommendations",
      "analyse.recommendations",
    ]);
  });

  it("allows each declared analyse capability", async () => {
    const { handlerDeps } = deps();
    for (const capability of DECLARED_CAPABILITIES.filter((key) => !isExecuteCapability(key))) {
      const result = await handleModuleRequest(moduleRequest({ capability }), "analyse", handlerDeps);
      expect(result.dataAuthenticity).toBe("genuine");
    }
  });

  it("refuses an undeclared capability as a refusal, never an attempt", async () => {
    const { db, handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: "analyse.competitor_benchmark" }), "analyse", handlerDeps),
      "unsupported_capability",
    );
    // Nothing was read on the way to refusing.
    expect(db.calls).toHaveLength(0);
  });

  it("refuses an execute capability sent to the analyse family", async () => {
    const { db, handlerDeps } = deps();
    // A capability/path disagreement is refused rather than quietly routed.
    await expectErrorCode(
      handleModuleRequest(
        moduleRequest({ capability: CAP_REQUEST_TECHNICAL_AUDIT }),
        "analyse",
        handlerDeps,
      ),
      "invalid_request",
    );
    expect(db.calls).toHaveLength(0);
  });

  it("refuses an analyse capability sent to the execute family", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: CAP_TARGET_LINKAGE }), "execute", handlerDeps),
      "invalid_request",
    );
  });

  it("classifies exactly the two write capabilities as execute", () => {
    expect(isExecuteCapability(CAP_REQUEST_TECHNICAL_AUDIT)).toBe(true);
    expect(isExecuteCapability(CAP_GENERATE_RECOMMENDATIONS)).toBe(true);
    expect(isExecuteCapability(CAP_TARGET_LINKAGE)).toBe(false);
    expect(isExecuteCapability(CAP_READ_TECHNICAL_AUDIT)).toBe(false);
  });

  it("refuses capabilities that would expose non-genuine SEO surfaces", async () => {
    const { handlerDeps } = deps();
    for (const capability of [
      "analyse.competitor_benchmark",
      "analyse.page_performance",
      "analyse.decline_diagnosis",
      "analyse.ai_visibility",
      "analyse.roadmap",
      "execute.content_publish",
      "execute.off_page_action",
    ]) {
      await expectErrorCode(
        handleModuleRequest(moduleRequest({ capability }), "analyse", handlerDeps),
        "unsupported_capability",
      );
    }
  });
});

describe("actor identity", () => {
  it("echoes a supplied actorId for correlation", async () => {
    const { handlerDeps } = deps();
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_TARGET_LINKAGE, actorId: "brain-user-123" }),
      "analyse",
      handlerDeps,
    );
    expect(result.actorId).toBe("brain-user-123");
  });

  it("omits actorId entirely when the request carried none", async () => {
    const { handlerDeps } = deps();
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_TARGET_LINKAGE }),
      "analyse",
      handlerDeps,
    );
    expect(result.actorId).toBeUndefined();
  });

  it("rejects a malformed actorId rather than ignoring it", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(
        moduleRequest({ capability: CAP_TARGET_LINKAGE, actorId: "   " }),
        "analyse",
        handlerDeps,
      ),
      "invalid_request",
    );
  });

  it("does not use actorId to widen what a read returns", async () => {
    const { handlerDeps } = deps();
    const withActor = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT, actorId: "brain-user-123" }),
      "analyse",
      handlerDeps,
    );
    const withoutActor = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT }),
      "analyse",
      handlerDeps,
    );
    expect(withActor.findings).toEqual(withoutActor.findings);
  });
});

// ---------------------------------------------------------------------------
// Envelope validation
// ---------------------------------------------------------------------------

describe("Contract v1 envelope validation", () => {
  it.each([
    ["a non-object body", "not-an-object"],
    ["a wrong contract version", moduleRequest({ contractVersion: "module-contract.v2" })],
    ["a wrong moduleId", moduleRequest({ moduleId: "social" })],
    ["a missing requestId", moduleRequest({ requestId: "" })],
    ["a missing businessId", moduleRequest({ businessId: "" })],
    ["a malformed capability key", moduleRequest({ capability: "analyse" })],
    ["a missing websiteIdentity", moduleRequest({ websiteIdentity: undefined })],
    [
      "a websiteIdentity with no assessedUrl",
      moduleRequest({ websiteIdentity: { normalizedHost: "example.com", assessedUrl: "" } }),
    ],
  ])("refuses %s", async (_label, body) => {
    const { handlerDeps } = deps();
    await expectErrorCode(handleModuleRequest(body, "analyse", handlerDeps), "invalid_request");
  });

  it.each(["https://example.com", "www.example.com", "EXAMPLE.COM", "example.com/"])(
    "refuses the non-canonical host %s instead of silently correcting it",
    async (normalizedHost) => {
      const { db, handlerDeps } = deps();
      await expectErrorCode(
        handleModuleRequest(
          moduleRequest({
            capability: CAP_TARGET_LINKAGE,
            websiteIdentity: { normalizedHost, assessedUrl: "https://www.example.com/" },
          }),
          "analyse",
          handlerDeps,
        ),
        "invalid_request",
      );
      expect(db.calls).toHaveLength(0);
    },
  );
});

// ---------------------------------------------------------------------------
// Authenticity and provenance
// ---------------------------------------------------------------------------

describe("authenticity and provenance", () => {
  it("reports crawler findings as genuine measurements", async () => {
    const { handlerDeps } = deps();
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT }),
      "analyse",
      handlerDeps,
    );

    expect(result.dataAuthenticity).toBe("genuine");
    expect(result.observationMethod).toBe("measured_external");
    expect(result.provenance.basis).toBe("measured");
    expect(result.provenance.generationMethod).toBe("crawler-rules-v1");
    // SEO's four-level severity collapses onto the contract's three, upward.
    expect(result.findings[0].severity).toBe("high");
    // findingKey is the crawler fingerprint, the evidence anchor back to the job.
    expect(result.findings[0].findingKey).toBe("MISSING_TITLE::abc123");
  });

  it("refuses to return a finding that did not come from the crawler", async () => {
    const store = baseStore();
    store.findings = {
      ...store.findings,
      "site-a": [crawlerFinding({ source: "seed", findingKey: "SEEDED::x" })],
    };
    const { handlerDeps } = deps(store);
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT }), "analyse", handlerDeps),
      "not_genuine",
    );
  });

  it("omits generationMethod when the rule version is not uniform", async () => {
    const store = baseStore();
    store.findings = {
      ...store.findings,
      "site-a": [
        crawlerFinding({ sourceRuleVersion: "crawler-rules-v1" }),
        crawlerFinding({ findingKey: "OTHER::y", sourceRuleVersion: "crawler-rules-v2" }),
      ],
    };
    const { handlerDeps } = deps(store);
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_TECHNICAL_AUDIT }),
      "analyse",
      handlerDeps,
    );
    // Better to say nothing than to claim one version produced both.
    expect(result.provenance.generationMethod).toBeUndefined();
  });

  it("reports recommendations as genuine derivations carrying their stored method", async () => {
    const { handlerDeps } = deps();
    const result = await handleModuleRequest(
      moduleRequest({ capability: CAP_READ_RECOMMENDATIONS }),
      "analyse",
      handlerDeps,
    );

    expect(result.dataAuthenticity).toBe("genuine");
    expect(result.observationMethod).toBe("calculated");
    expect(result.provenance.basis).toBe("derived");
    expect(result.provenance.generationMethod).toBe("rule_based_v1");
  });

  it("refuses a recommendation with no recorded generation method", async () => {
    const store = baseStore();
    store.recommendations = {
      ...store.recommendations,
      "site-a": [generatedRecommendation({ generationMethod: null })],
    };
    const { handlerDeps } = deps(store);
    await expectErrorCode(
      handleModuleRequest(moduleRequest({ capability: CAP_READ_RECOMMENDATIONS }), "analyse", handlerDeps),
      "not_genuine",
    );
  });

  it("reports a performed DNS check as measured and an absent one as derived", async () => {
    const verifiedStore = baseStore();
    verifiedStore.ownership = {
      "site-a": { status: "verified", lastCheckedAt: "2026-09-10T00:00:00.000Z", verifiedAt: "2026-09-10T00:00:00.000Z" },
    };
    const verified = await handleModuleRequest(
      moduleRequest({ capability: CAP_OWNERSHIP_VERIFICATION }),
      "analyse",
      deps(verifiedStore).handlerDeps,
    );
    expect(verified.observationMethod).toBe("measured_external");
    expect(verified.provenance.basis).toBe("measured");
    expect(verified.findings).toEqual([]);

    // Never checked: the state is derived from the absence of a verification,
    // and must not be presented as a DNS observation that happened.
    const uncheckedStore = baseStore();
    uncheckedStore.ownership = {};
    const unchecked = await handleModuleRequest(
      moduleRequest({ capability: CAP_OWNERSHIP_VERIFICATION }),
      "analyse",
      deps(uncheckedStore).handlerDeps,
    );
    expect(unchecked.observationMethod).toBe("calculated");
    expect(unchecked.provenance.basis).toBe("derived");
    expect(unchecked.findings[0].findingKey).toBe("seo.ownership.dns_txt_not_verified");
    expect(unchecked.findings[0].severity).toBe("high");
  });

  it("marks every successful analyse response genuine, as Brain refuses anything else", async () => {
    const { handlerDeps } = deps();
    for (const capability of DECLARED_CAPABILITIES.filter((key) => !isExecuteCapability(key))) {
      const result = await handleModuleRequest(moduleRequest({ capability }), "analyse", handlerDeps);
      expect(result.dataAuthenticity).toBe("genuine");
    }
  });
});
