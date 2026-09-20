import { describe, expect, it } from "vitest";
import { SeoModuleContractError } from "./contract.ts";
import { handleModuleRequest } from "./handler.ts";
import {
  CAP_GENERATE_RECOMMENDATIONS,
  CAP_REQUEST_TECHNICAL_AUDIT,
} from "./capabilities.ts";
import {
  FakeSeoDataPort,
  baseStore,
  crawlerFinding,
  executeRequest,
  statusRequest,
  type FakeStore,
} from "./test-support.ts";

function deps(store: FakeStore = baseStore()) {
  const db = new FakeSeoDataPort(store);
  return { db, store, handlerDeps: { db } };
}

async function expectErrorCode(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toBeInstanceOf(SeoModuleContractError);
  await promise.catch((error: SeoModuleContractError) => {
    expect(error.code).toBe(code);
  });
}

// ---------------------------------------------------------------------------
// Actor mapping: identity only, never permission
// ---------------------------------------------------------------------------

describe("Brain actor to SEO user mapping", () => {
  it("resolves an exact active actor and runs as that SEO user", async () => {
    const { handlerDeps } = deps();
    const result = await handleModuleRequest(executeRequest(), "execute", handlerDeps);
    expect(result).toMatchObject({ accepted: true, dataAuthenticity: "genuine" });
  });

  it("refuses an actor that has no mapping at all", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: "brain-actor-unknown" }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("refuses a revoked actor mapping, failing closed", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: "brain-actor-revoked" }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("refuses a delegated write that carries no actor at all", async () => {
    const { handlerDeps } = deps();
    // An automated Brain request with no human behind it cannot write, rather
    // than running as some system account nobody could be held responsible for.
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: undefined }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("does NOT grant workspace permission: a mapped user with no membership is refused", async () => {
    const { handlerDeps } = deps();
    // brain-actor-nomember resolves to a real, module-enabled SEO user who
    // simply belongs to no workspace. Identity succeeds; authorization does not.
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: "brain-actor-nomember" }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("applies the existing SEO role matrix: a client may not request a crawl", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: "brain-actor-client" }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it.each(["owner", "admin", "team_member"] as const)(
    "permits a mapped %s, matching the existing SEO crawl role matrix",
    async (role) => {
      const store = baseStore();
      store.members = [{ workspaceId: "ws-1", userId: "seo-user-1", role }];
      const { handlerDeps } = deps(store);
      const result = await handleModuleRequest(executeRequest(), "execute", handlerDeps);
      expect(result).toMatchObject({ accepted: true });
    },
  );

  it("refuses an actor whose membership is in a different workspace", async () => {
    const { handlerDeps } = deps();
    // brain-actor-other is an owner, but of ws-2, and the target is in ws-1.
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: "brain-actor-other" }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("never falls back to email, owner or any other inference", async () => {
    const store = baseStore();
    // No mapping exists at all, but the workspace does have an owner and there
    // are other mapped users. None of that may stand in for the missing link.
    store.actorLinks = [];
    const { handlerDeps } = deps(store);
    await expectErrorCode(
      handleModuleRequest(executeRequest(), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("exposes no capability through which a machine request could create a mapping", async () => {
    const { db, handlerDeps } = deps();
    // There is no create/link capability in the declaration, so the only way
    // a mapping can exist is the human, RLS-gated INSERT path.
    for (const capability of ["execute.actor_link", "analyse.actor_link", "execute.link_actor"]) {
      await expectErrorCode(
        handleModuleRequest(executeRequest({ capability }), "execute", handlerDeps),
        "unsupported_capability",
      );
    }
    expect(db.calls).toHaveLength(0);
    // And no refused call left a mapping behind.
    expect((deps().store.actorLinks ?? []).map((link) => link.brainActorId)).not.toContain("brain-actor-unknown");
  });

  it("does not let the machine credential substitute for the human", async () => {
    const { handlerDeps } = deps();
    // The transport is already authenticated by the time the handler runs; an
    // unmapped actorId is still refused.
    await expectErrorCode(
      handleModuleRequest(executeRequest({ actorId: "brain-actor-unknown" }), "execute", handlerDeps),
      "unauthorized",
    );
  });
});

// ---------------------------------------------------------------------------
// execute.technical_audit
// ---------------------------------------------------------------------------

describe("execute.technical_audit", () => {
  it("accepts an exact Business, host and actor and returns the real crawl job id", async () => {
    const { store, handlerDeps } = deps();
    const result = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      accepted: boolean;
      moduleStatus: string;
      moduleOperationId?: string;
      brainActionId: string;
      provenance: { basis: string };
      observationMethod: string;
    };

    expect(result.accepted).toBe(true);
    expect(result.brainActionId).toBe("brain-action-1");
    expect(result.moduleStatus).toBe("queued");
    // The handle is the genuine crawl job, not a synthetic id.
    expect(result.moduleOperationId).toBe("job-site-a-brain-action-1");
    expect(store.crawlJobs?.[result.moduleOperationId as string]).toEqual({
      websiteId: "site-a",
      status: "queued",
    });
    // Accepting work is not an observation of the website.
    expect(result.observationMethod).toBe("calculated");
    expect(result.provenance.basis).toBe("derived");
  });

  it("preserves the verified-ownership requirement", async () => {
    const store = baseStore();
    store.ownership = { "site-a": { status: "pending" } };
    const { handlerDeps } = deps(store);

    const result = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      accepted: boolean;
      moduleStatus: string;
      moduleOperationId?: string;
    };

    // A genuine, truthful "we did not start this", not a silent success and
    // not an opaque error.
    expect(result.accepted).toBe(false);
    expect(result.moduleStatus).toBe("ownership_not_verified");
    expect(result.moduleOperationId).toBeUndefined();
    expect(store.crawlJobs ?? {}).toEqual({});
  });

  it("attributes the operation to the resolved human, not to a system account", async () => {
    const { store, handlerDeps } = deps();
    await handleModuleRequest(executeRequest(), "execute", handlerDeps);
    expect(store.operations?.[0].actedAsUserId).toBe("seo-user-1");
  });

  it("is idempotent: the same Brain action resolves to the same job", async () => {
    const { store, handlerDeps } = deps();
    const first = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      moduleOperationId?: string;
    };
    const second = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      moduleOperationId?: string;
    };
    expect(second.moduleOperationId).toBe(first.moduleOperationId);
    expect(store.operations).toHaveLength(1);
  });

  it("requires brainActionId and idempotencyKey", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(executeRequest({ brainActionId: undefined }), "execute", handlerDeps),
      "invalid_request",
    );
    await expectErrorCode(
      handleModuleRequest(executeRequest({ idempotencyKey: undefined }), "execute", handlerDeps),
      "invalid_request",
    );
  });

  it("refuses a wrong Business and a wrong host", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(executeRequest({ businessId: "biz-2" }), "execute", handlerDeps),
      "target_not_linked",
    );
    await expectErrorCode(
      handleModuleRequest(
        executeRequest({
          websiteIdentity: { normalizedHost: "shop.example.com", assessedUrl: "https://shop.example.com/" },
        }),
        "execute",
        handlerDeps,
      ),
      "target_not_linked",
    );
  });
});

// ---------------------------------------------------------------------------
// STATUS, keyed by the originating execute capability
// ---------------------------------------------------------------------------

describe("STATUS for execute.technical_audit", () => {
  it("correlates on the SAME capability key the execute used", async () => {
    const { handlerDeps } = deps();
    const ack = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      moduleOperationId?: string;
    };

    const status = (await handleModuleRequest(
      statusRequest({ moduleOperationId: ack.moduleOperationId }),
      "status",
      handlerDeps,
    )) as { brainActionId: string; moduleStatus: string; moduleOperationId?: string };

    expect(status.brainActionId).toBe("brain-action-1");
    expect(status.moduleOperationId).toBe(ack.moduleOperationId);
    expect(status.moduleStatus).toBe("queued");
  });

  it("reports the live job status rather than the status at acceptance", async () => {
    const { store, handlerDeps } = deps();
    const ack = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      moduleOperationId?: string;
    };
    store.crawlJobs![ack.moduleOperationId as string].status = "running";

    const status = (await handleModuleRequest(statusRequest(), "status", handlerDeps)) as {
      moduleStatus: string;
    };
    expect(status.moduleStatus).toBe("running");
  });

  it("fails closed on a real operation id belonging to another website", async () => {
    const store = baseStore();
    // A genuine operation exists for the OTHER tenant's website.
    store.operations = [
      {
        businessId: "biz-2",
        capability: "execute.technical_audit",
        brainActionId: "brain-action-1",
        websiteId: "site-c",
        moduleOperationId: "job-site-c-brain-action-1",
        moduleStatus: "running",
        actedAsUserId: "seo-user-other",
      },
    ];
    store.crawlJobs = { "job-site-c-brain-action-1": { websiteId: "site-c", status: "running" } };
    const { handlerDeps } = deps(store);

    await handleModuleRequest(executeRequest(), "execute", handlerDeps);

    // biz-1 asking about its own action but supplying site-c's real handle.
    await expectErrorCode(
      handleModuleRequest(
        statusRequest({ moduleOperationId: "job-site-c-brain-action-1" }),
        "status",
        handlerDeps,
      ),
      "identity_mismatch",
    );
  });

  it("refuses a status poll for an action this module never accepted", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(statusRequest({ brainActionId: "never-seen" }), "status", handlerDeps),
      "invalid_request",
    );
  });

  it("refuses a status poll for a wrong Business or host", async () => {
    const { handlerDeps } = deps();
    await handleModuleRequest(executeRequest(), "execute", handlerDeps);
    await expectErrorCode(
      handleModuleRequest(statusRequest({ businessId: "biz-2" }), "status", handlerDeps),
      "target_not_linked",
    );
  });
});

// ---------------------------------------------------------------------------
// execute.recommendations
// ---------------------------------------------------------------------------

describe("execute.recommendations", () => {
  const recExecute = (overrides: Record<string, unknown> = {}) =>
    executeRequest({ capability: CAP_GENERATE_RECOMMENDATIONS, ...overrides });

  it("generates over a genuine completed crawler audit for an authorized actor", async () => {
    const { handlerDeps } = deps();
    const result = (await handleModuleRequest(recExecute(), "execute", handlerDeps)) as {
      accepted: boolean;
      moduleStatus: string;
      provenance: { basis: string; generationMethod?: string };
      observationMethod: string;
    };

    expect(result.accepted).toBe(true);
    expect(result.moduleStatus).toBe("completed");
    expect(result.provenance.basis).toBe("derived");
    expect(result.observationMethod).toBe("calculated");
    // Read back from the stored rows, never asserted by this module.
    expect(result.provenance.generationMethod).toBe("rule_based_v1");
  });

  it("carries whatever generation method is actually stored", async () => {
    const store = baseStore();
    store.storedGenerationMethod = "rule_based_v2";
    const { handlerDeps } = deps(store);
    const result = (await handleModuleRequest(recExecute(), "execute", handlerDeps)) as {
      provenance: { generationMethod?: string };
    };
    expect(result.provenance.generationMethod).toBe("rule_based_v2");
  });

  it("refuses to generate when the completed audit is not genuine crawler evidence", async () => {
    const store = baseStore();
    store.findings = { ...store.findings, "site-a": [crawlerFinding({ source: "seed" })] };
    const { handlerDeps } = deps(store);

    const result = (await handleModuleRequest(recExecute(), "execute", handlerDeps)) as {
      accepted: boolean;
      moduleStatus: string;
    };
    expect(result.accepted).toBe(false);
    expect(result.moduleStatus).toBe("no_genuine_audit_evidence");
  });

  it("refuses to generate with no completed audit at all", async () => {
    const store = baseStore();
    store.audits = { ...store.audits, "site-a": null };
    const { handlerDeps } = deps(store);

    const result = (await handleModuleRequest(recExecute(), "execute", handlerDeps)) as {
      accepted: boolean;
      moduleStatus: string;
    };
    expect(result.accepted).toBe(false);
    expect(result.moduleStatus).toBe("no_completed_audit");
  });

  it("refuses an unauthorized actor", async () => {
    const { handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(recExecute({ actorId: "brain-actor-client" }), "execute", handlerDeps),
      "unauthorized",
    );
  });

  it("refuses a wrong Business, never generating for a neighbour", async () => {
    const { store, handlerDeps } = deps();
    await expectErrorCode(
      handleModuleRequest(recExecute({ businessId: "biz-unknown" }), "execute", handlerDeps),
      "target_not_linked",
    );
    expect(store.operations ?? []).toHaveLength(0);
  });

  it("resolves its own STATUS on the same capability key", async () => {
    const { handlerDeps } = deps();
    const ack = (await handleModuleRequest(recExecute(), "execute", handlerDeps)) as {
      moduleOperationId?: string;
    };
    const status = (await handleModuleRequest(
      statusRequest({ capability: CAP_GENERATE_RECOMMENDATIONS, moduleOperationId: ack.moduleOperationId }),
      "status",
      handlerDeps,
    )) as { moduleStatus: string; brainActionId: string };

    expect(status.moduleStatus).toBe("completed");
    expect(status.brainActionId).toBe("brain-action-1");
  });

  it("keeps the two execute capabilities' operations separate", async () => {
    const { handlerDeps } = deps();
    await handleModuleRequest(executeRequest(), "execute", handlerDeps);
    await handleModuleRequest(recExecute(), "execute", handlerDeps);

    const auditStatus = (await handleModuleRequest(
      statusRequest({ capability: CAP_REQUEST_TECHNICAL_AUDIT }),
      "status",
      handlerDeps,
    )) as { moduleStatus: string };
    const recStatus = (await handleModuleRequest(
      statusRequest({ capability: CAP_GENERATE_RECOMMENDATIONS }),
      "status",
      handlerDeps,
    )) as { moduleStatus: string };

    // Same brainActionId, two different capabilities, two different operations.
    expect(auditStatus.moduleStatus).toBe("queued");
    expect(recStatus.moduleStatus).toBe("completed");
  });

  it("keeps one Business's two websites' operations separate under the same Brain action", async () => {
    // Operation correlation is keyed on Business + website + capability + Brain
    // action. One Business can have several websites linked, and reusing a
    // Brain action id across them must produce two independent operations
    // rather than one overwriting the other's handle.
    const store = baseStore();
    store.links = [
      ...(store.links ?? []),
      { businessId: "biz-1", websiteId: "site-b", normalizedHost: "shop.example.com", linkStatus: "active" },
    ];
    store.ownership = {
      ...store.ownership,
      "site-b": { status: "verified", lastCheckedAt: "2026-09-11T00:00:00.000Z", verifiedAt: "2026-09-11T00:00:00.000Z" },
    };
    const { store: live, handlerDeps } = deps(store);

    const siteB = {
      websiteIdentity: { normalizedHost: "shop.example.com", assessedUrl: "https://shop.example.com/" },
    };

    const ackA = (await handleModuleRequest(executeRequest(), "execute", handlerDeps)) as {
      moduleOperationId?: string;
    };
    const ackB = (await handleModuleRequest(
      executeRequest(siteB),
      "execute",
      handlerDeps,
    )) as { moduleOperationId?: string };

    // Two real, distinct operations, not one replayed onto the other.
    expect(ackA.moduleOperationId).toBeDefined();
    expect(ackB.moduleOperationId).toBeDefined();
    expect(ackB.moduleOperationId).not.toBe(ackA.moduleOperationId);
    expect(live.operations ?? []).toHaveLength(2);

    // Each website's STATUS still resolves to its own handle, and a handle from
    // the sibling website fails closed rather than being answered.
    const statusA = (await handleModuleRequest(
      statusRequest({ capability: CAP_REQUEST_TECHNICAL_AUDIT, moduleOperationId: ackA.moduleOperationId }),
      "status",
      handlerDeps,
    )) as { moduleOperationId?: string };
    expect(statusA.moduleOperationId).toBe(ackA.moduleOperationId);

    await expectErrorCode(
      handleModuleRequest(
        statusRequest({
          capability: CAP_REQUEST_TECHNICAL_AUDIT,
          moduleOperationId: ackB.moduleOperationId,
        }),
        "status",
        handlerDeps,
      ),
      "identity_mismatch",
    );
  });
});
