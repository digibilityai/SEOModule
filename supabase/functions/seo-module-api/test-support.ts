/**
 * Test doubles for the machine boundary.
 *
 * `FakeSeoDataPort` re-implements, in memory, the resolution rules that
 * migration 20260920120100's public.seo_brain_resolve_target implements in SQL:
 * exact (business_id, normalized_host) match, active links only, the website's
 * current URL must still normalize to the linked host, and inactive websites do
 * not resolve. Keeping the two in step is a review obligation, and the SQL side
 * is separately exercised by
 * supabase/test/seo_brain_module_boundary_verification.sql.
 *
 * The fake deliberately holds several websites across several workspaces, so a
 * test that asserts "no sibling substitution" is asserting against a store that
 * genuinely contains a tempting neighbour to substitute.
 */

import { normalizeWebsiteHost } from "./normalize-host.ts";
import type {
  CrawlFinding,
  CrawlFindingsPage,
  DelegatedExecuteArgs,
  DelegatedOperation,
  DelegatedStatusArgs,
  OwnershipStatus,
  Recommendation,
  RecommendationsPage,
  ResolvedTarget,
  SeoDataPort,
  TargetResolutionCode,
} from "./port.ts";

export interface FakeWebsite {
  websiteId: string;
  workspaceId: string;
  websiteUrl: string;
  isActive?: boolean;
}

export interface FakeLink {
  businessId: string;
  websiteId: string;
  /** Canonical host captured when the link was authorized. */
  normalizedHost: string;
  linkStatus: "active" | "revoked";
  linkedAt?: string;
}

/** A human-authorized Brain actor to SEO user mapping. */
export interface FakeActorLink {
  brainActorId: string;
  seoUserId: string;
  linkStatus: "active" | "revoked";
}

/** Existing SEO workspace membership. The actor link never creates one. */
export interface FakeMember {
  workspaceId: string;
  userId: string;
  role: "owner" | "admin" | "team_member" | "client";
}

export interface FakeOperation {
  businessId: string;
  capability: string;
  brainActionId: string;
  websiteId: string;
  moduleOperationId: string;
  moduleStatus: string;
  actedAsUserId: string;
}

export interface FakeStore {
  websites: FakeWebsite[];
  links: FakeLink[];
  actorLinks?: FakeActorLink[];
  members?: FakeMember[];
  /** SEO user ids holding active user_module_access for 'seo'. */
  moduleAccess?: string[];
  ownership?: Record<string, Partial<OwnershipStatus>>;
  audits?: Record<string, { auditRunId: string; completedAt: string } | null>;
  findings?: Record<string, CrawlFinding[]>;
  recommendations?: Record<string, Recommendation[]>;
  operations?: FakeOperation[];
  /** jobId -> live crawl job state, the source of truth for STATUS. */
  crawlJobs?: Record<string, { websiteId: string; status: string }>;
  /** Stored generation_method that generation would report back. */
  storedGenerationMethod?: string;
}

export class FakeSeoDataPort implements SeoDataPort {
  readonly calls: Array<{ method: string; businessId: string; normalizedHost: string }> = [];

  constructor(private readonly store: FakeStore) {}

  private resolve(businessId: string, normalizedHost: string): ResolvedTarget {
    const miss = (resolution: TargetResolutionCode): ResolvedTarget => ({
      resolution,
      websiteId: null,
      workspaceId: null,
      normalizedHost: null,
      websiteUrl: null,
      linkedAt: null,
    });

    if (!businessId.trim() || !normalizedHost.trim()) return miss("invalid_target");

    // Exact match on both columns. No name matching, no host inference, no
    // "most recent workspace", no neighbour.
    const candidates = this.store.links.filter(
      (link) => link.businessId === businessId && link.normalizedHost === normalizedHost,
    );
    if (candidates.length === 0) return miss("not_linked");

    const link = candidates.find((entry) => entry.linkStatus === "active");
    if (!link) return miss("revoked");

    const website = this.store.websites.find((entry) => entry.websiteId === link.websiteId);
    if (!website) return miss("website_missing");

    if (normalizeWebsiteHost(website.websiteUrl) !== link.normalizedHost) {
      return miss("host_changed");
    }
    if (website.isActive === false) return miss("website_inactive");

    return {
      resolution: "resolved",
      websiteId: website.websiteId,
      workspaceId: website.workspaceId,
      normalizedHost: link.normalizedHost,
      websiteUrl: website.websiteUrl,
      linkedAt: link.linkedAt ?? "2026-09-01T00:00:00.000Z",
    };
  }

  async resolveTarget(businessId: string, normalizedHost: string): Promise<ResolvedTarget> {
    this.calls.push({ method: "resolveTarget", businessId, normalizedHost });
    return this.resolve(businessId, normalizedHost);
  }

  async ownershipStatus(businessId: string, normalizedHost: string): Promise<OwnershipStatus> {
    this.calls.push({ method: "ownershipStatus", businessId, normalizedHost });
    const target = this.resolve(businessId, normalizedHost);
    const empty: OwnershipStatus = {
      resolution: target.resolution,
      websiteId: target.websiteId,
      verificationHost: null,
      method: null,
      ownershipSource: null,
      status: null,
      verifiedAt: null,
      lastCheckedAt: null,
      failureReason: null,
    };
    if (target.resolution !== "resolved") return empty;
    return {
      ...empty,
      status: "not_started",
      ...(this.store.ownership?.[target.websiteId as string] ?? {}),
      resolution: "resolved",
      websiteId: target.websiteId,
    };
  }

  async crawlFindings(businessId: string, normalizedHost: string): Promise<CrawlFindingsPage> {
    this.calls.push({ method: "crawlFindings", businessId, normalizedHost });
    const target = this.resolve(businessId, normalizedHost);
    if (target.resolution !== "resolved") {
      return {
        resolution: target.resolution,
        websiteId: null,
        auditRunId: null,
        auditCompletedAt: null,
        findings: [],
      };
    }
    const websiteId = target.websiteId as string;
    const audit = this.store.audits?.[websiteId] ?? null;
    if (!audit) {
      return {
        resolution: "no_completed_audit",
        websiteId,
        auditRunId: null,
        auditCompletedAt: null,
        findings: [],
      };
    }
    return {
      resolution: "resolved",
      websiteId,
      auditRunId: audit.auditRunId,
      auditCompletedAt: audit.completedAt,
      findings: this.store.findings?.[websiteId] ?? [],
    };
  }

  async currentRecommendations(
    businessId: string,
    normalizedHost: string,
  ): Promise<RecommendationsPage> {
    this.calls.push({ method: "currentRecommendations", businessId, normalizedHost });
    const target = this.resolve(businessId, normalizedHost);
    if (target.resolution !== "resolved") {
      return { resolution: target.resolution, websiteId: null, recommendations: [] };
    }
    return {
      resolution: "resolved",
      websiteId: target.websiteId,
      recommendations: this.store.recommendations?.[target.websiteId as string] ?? [],
    };
  }
  // -------------------------------------------------------------------------
  // Delegated write and status, mirroring migration 20260920120300.
  // -------------------------------------------------------------------------

  /**
   * Mirrors public.seo_brain_authorize_delegated: the target and the actor are
   * resolved independently, and the actor mapping contributes NOTHING to
   * authorization. A mapped user with no membership resolves and is then
   * refused by the role check, exactly as in SQL.
   */
  private authorizeDelegated(
    businessId: string,
    normalizedHost: string,
    brainActorId: string,
  ): { resolution: TargetResolutionCode; websiteId: string | null; workspaceId: string | null; userId: string | null } {
    const target = this.resolve(businessId, normalizedHost);
    if (target.resolution !== "resolved") {
      return { resolution: target.resolution, websiteId: null, workspaceId: null, userId: null };
    }
    if (!brainActorId.trim()) {
      return { resolution: "actor_required", websiteId: target.websiteId, workspaceId: target.workspaceId, userId: null };
    }

    const link = (this.store.actorLinks ?? []).find(
      (entry) => entry.brainActorId === brainActorId && entry.linkStatus === "active",
    );
    if (!link) {
      return { resolution: "actor_not_linked", websiteId: target.websiteId, workspaceId: target.workspaceId, userId: null };
    }

    const hasModuleAccess = (this.store.moduleAccess ?? []).includes(link.seoUserId);
    const membership = (this.store.members ?? []).find(
      (entry) => entry.workspaceId === target.workspaceId && entry.userId === link.seoUserId,
    );
    const permitted =
      hasModuleAccess &&
      membership !== undefined &&
      ["owner", "admin", "team_member"].includes(membership.role);

    if (!permitted) {
      return {
        resolution: "actor_unauthorized",
        websiteId: target.websiteId,
        workspaceId: target.workspaceId,
        userId: null,
      };
    }

    return {
      resolution: "resolved",
      websiteId: target.websiteId,
      workspaceId: target.workspaceId,
      userId: link.seoUserId,
    };
  }

  private miss(resolution: TargetResolutionCode): DelegatedOperation {
    return {
      resolution,
      websiteId: null,
      moduleOperationId: null,
      moduleStatus: null,
      auditRunId: null,
      generationMethod: null,
      generatedCount: null,
      actedAsUserId: null,
      replayed: false,
      detail: null,
    };
  }

  private findOperation(capability: string, args: { businessId: string; brainActionId: string; websiteId: string }) {
    return (this.store.operations ?? []).find(
      (entry) =>
        entry.capability === capability &&
        entry.businessId === args.businessId &&
        entry.brainActionId === args.brainActionId &&
        entry.websiteId === args.websiteId,
    );
  }

  async requestTechnicalAudit(args: DelegatedExecuteArgs): Promise<DelegatedOperation> {
    this.calls.push({
      method: "requestTechnicalAudit",
      businessId: args.businessId,
      normalizedHost: args.normalizedHost,
    });
    const auth = this.authorizeDelegated(args.businessId, args.normalizedHost, args.brainActorId);
    if (auth.resolution !== "resolved") return this.miss(auth.resolution);
    const websiteId = auth.websiteId as string;

    const existing = this.findOperation("execute.technical_audit", {
      businessId: args.businessId,
      brainActionId: args.brainActionId,
      websiteId,
    });
    if (existing) {
      return {
        ...this.miss("resolved"),
        websiteId,
        moduleOperationId: existing.moduleOperationId,
        moduleStatus: this.store.crawlJobs?.[existing.moduleOperationId]?.status ?? existing.moduleStatus,
        actedAsUserId: existing.actedAsUserId,
        replayed: true,
      };
    }

    // The verified-ownership requirement is preserved, not bypassed.
    const ownership = this.store.ownership?.[websiteId]?.status ?? "not_started";
    if (ownership !== "verified") {
      return { ...this.miss("ownership_not_verified"), websiteId };
    }

    // The genuine enqueue path produces a real crawl job id.
    const jobId = `job-${websiteId}-${args.brainActionId}`;
    this.store.crawlJobs = { ...(this.store.crawlJobs ?? {}), [jobId]: { websiteId, status: "queued" } };
    this.store.operations = [
      ...(this.store.operations ?? []),
      {
        businessId: args.businessId,
        capability: "execute.technical_audit",
        brainActionId: args.brainActionId,
        websiteId,
        moduleOperationId: jobId,
        moduleStatus: "queued",
        actedAsUserId: auth.userId as string,
      },
    ];

    return {
      ...this.miss("resolved"),
      websiteId,
      moduleOperationId: jobId,
      moduleStatus: "queued",
      auditRunId: `run-${websiteId}`,
      actedAsUserId: auth.userId,
    };
  }

  async technicalAuditStatus(args: DelegatedStatusArgs): Promise<DelegatedOperation> {
    this.calls.push({
      method: "technicalAuditStatus",
      businessId: args.businessId,
      normalizedHost: args.normalizedHost,
    });
    const target = this.resolve(args.businessId, args.normalizedHost);
    if (target.resolution !== "resolved") return this.miss(target.resolution);
    const websiteId = target.websiteId as string;

    const op = this.findOperation("execute.technical_audit", {
      businessId: args.businessId,
      brainActionId: args.brainActionId,
      websiteId,
    });
    if (!op) return this.miss("operation_not_found");

    if (args.moduleOperationId && args.moduleOperationId !== op.moduleOperationId) {
      return this.miss("operation_mismatch");
    }

    const job = this.store.crawlJobs?.[op.moduleOperationId];
    if (!job || job.websiteId !== websiteId) return this.miss("operation_not_found");

    return {
      ...this.miss("resolved"),
      websiteId,
      moduleOperationId: op.moduleOperationId,
      moduleStatus: job.status,
      actedAsUserId: op.actedAsUserId,
    };
  }

  async generateRecommendations(args: DelegatedExecuteArgs): Promise<DelegatedOperation> {
    this.calls.push({
      method: "generateRecommendations",
      businessId: args.businessId,
      normalizedHost: args.normalizedHost,
    });
    const auth = this.authorizeDelegated(args.businessId, args.normalizedHost, args.brainActorId);
    if (auth.resolution !== "resolved") return this.miss(auth.resolution);
    const websiteId = auth.websiteId as string;

    const existing = this.findOperation("execute.recommendations", {
      businessId: args.businessId,
      brainActionId: args.brainActionId,
      websiteId,
    });
    if (existing) {
      return {
        ...this.miss("resolved"),
        websiteId,
        moduleOperationId: existing.moduleOperationId,
        moduleStatus: existing.moduleStatus,
        actedAsUserId: existing.actedAsUserId,
        replayed: true,
      };
    }

    const audit = this.store.audits?.[websiteId] ?? null;
    if (!audit) return { ...this.miss("no_completed_audit"), websiteId };

    // Generation is refused unless the completed audit is genuine crawler
    // evidence, so a seeded audit can never produce a "genuine" result.
    const crawlerFindings = (this.store.findings?.[websiteId] ?? []).filter(
      (finding) => finding.source === "crawler",
    );
    if (crawlerFindings.length === 0) {
      return { ...this.miss("no_genuine_audit_evidence"), websiteId };
    }

    const opId = `recop-${websiteId}-${args.brainActionId}`;
    this.store.operations = [
      ...(this.store.operations ?? []),
      {
        businessId: args.businessId,
        capability: "execute.recommendations",
        brainActionId: args.brainActionId,
        websiteId,
        moduleOperationId: opId,
        moduleStatus: "completed",
        actedAsUserId: auth.userId as string,
      },
    ];

    return {
      ...this.miss("resolved"),
      websiteId,
      moduleOperationId: opId,
      moduleStatus: "completed",
      auditRunId: audit.auditRunId,
      generatedCount: crawlerFindings.length,
      // Read back from the stored rows, never asserted by the caller.
      generationMethod: this.store.storedGenerationMethod ?? "rule_based_v1",
      actedAsUserId: auth.userId,
    };
  }

  async recommendationStatus(args: DelegatedStatusArgs): Promise<DelegatedOperation> {
    this.calls.push({
      method: "recommendationStatus",
      businessId: args.businessId,
      normalizedHost: args.normalizedHost,
    });
    const target = this.resolve(args.businessId, args.normalizedHost);
    if (target.resolution !== "resolved") return this.miss(target.resolution);

    const op = this.findOperation("execute.recommendations", {
      businessId: args.businessId,
      brainActionId: args.brainActionId,
      websiteId: target.websiteId as string,
    });
    if (!op) return this.miss("operation_not_found");
    if (args.moduleOperationId && args.moduleOperationId !== op.moduleOperationId) {
      return this.miss("operation_mismatch");
    }

    return {
      ...this.miss("resolved"),
      websiteId: target.websiteId,
      moduleOperationId: op.moduleOperationId,
      moduleStatus: op.moduleStatus,
      actedAsUserId: op.actedAsUserId,
    };
  }
}

export function crawlerFinding(overrides: Partial<CrawlFinding> = {}): CrawlFinding {
  return {
    findingKey: "MISSING_TITLE::abc123",
    title: "Page is missing a title",
    observation: "This page has no <title> element.",
    recommendedAction: "Add a descriptive title to this page.",
    severity: "critical",
    category: "indexability",
    affectedPageUrl: "https://example.com/pricing",
    issueScope: "page",
    source: "crawler",
    crawlJobId: "job-1",
    sourceIssueFingerprint: "MISSING_TITLE::abc123",
    sourceRuleVersion: "crawler-rules-v1",
    ...overrides,
  };
}

export function generatedRecommendation(overrides: Partial<Recommendation> = {}): Recommendation {
  return {
    recommendationId: "rec-1",
    findingKey: "MISSING_TITLE::abc123",
    area: "title",
    title: "Add a page title",
    currentValue: null,
    suggestedChange: "Set the title to 'Pricing | Example'.",
    whyItHelps: "A descriptive title helps search engines understand the page.",
    actionType: "approval_required",
    impact: "high",
    effort: "low",
    risk: "low",
    status: "suggested",
    generationMethod: "rule_based_v1",
    sourceIssueFingerprint: "MISSING_TITLE::abc123",
    auditRunId: "run-1",
    updatedAt: "2026-09-10T00:00:00.000Z",
    ...overrides,
  };
}

/** A store with two Businesses, two workspaces and three websites. */
export function baseStore(): FakeStore {
  return {
    websites: [
      { websiteId: "site-a", workspaceId: "ws-1", websiteUrl: "https://www.example.com" },
      // A tempting sibling: same workspace, has data, different host.
      { websiteId: "site-b", workspaceId: "ws-1", websiteUrl: "https://shop.example.com" },
      // A different tenant entirely.
      { websiteId: "site-c", workspaceId: "ws-2", websiteUrl: "https://other.test" },
    ],
    links: [
      { businessId: "biz-1", websiteId: "site-a", normalizedHost: "example.com", linkStatus: "active" },
      { businessId: "biz-2", websiteId: "site-c", normalizedHost: "other.test", linkStatus: "active" },
    ],
    actorLinks: [
      // A mapped human who really is a team_member of ws-1.
      { brainActorId: "brain-actor-1", seoUserId: "seo-user-1", linkStatus: "active" },
      // A mapped human with NO membership anywhere: identity resolves, and
      // authorization must still refuse.
      { brainActorId: "brain-actor-nomember", seoUserId: "seo-user-nomember", linkStatus: "active" },
      // A mapped human who is only a client of ws-1: a read role, not a
      // crawl-requesting role.
      { brainActorId: "brain-actor-client", seoUserId: "seo-user-client", linkStatus: "active" },
      // A mapped human belonging to the OTHER tenant's workspace only.
      { brainActorId: "brain-actor-other", seoUserId: "seo-user-other", linkStatus: "active" },
      { brainActorId: "brain-actor-revoked", seoUserId: "seo-user-revoked", linkStatus: "revoked" },
    ],
    members: [
      { workspaceId: "ws-1", userId: "seo-user-1", role: "team_member" },
      { workspaceId: "ws-1", userId: "seo-user-client", role: "client" },
      { workspaceId: "ws-2", userId: "seo-user-other", role: "owner" },
      { workspaceId: "ws-1", userId: "seo-user-revoked", role: "owner" },
    ],
    moduleAccess: [
      "seo-user-1",
      "seo-user-nomember",
      "seo-user-client",
      "seo-user-other",
      "seo-user-revoked",
    ],
    ownership: {
      // The linked website has genuinely verified DNS-TXT ownership.
      "site-a": { status: "verified", lastCheckedAt: "2026-09-10T00:00:00.000Z", verifiedAt: "2026-09-10T00:00:00.000Z" },
    },
    audits: {
      "site-a": { auditRunId: "run-1", completedAt: "2026-09-10T00:00:00.000Z" },
      "site-b": { auditRunId: "run-2", completedAt: "2026-09-11T00:00:00.000Z" },
      "site-c": { auditRunId: "run-3", completedAt: "2026-09-12T00:00:00.000Z" },
    },
    findings: {
      "site-a": [crawlerFinding()],
      "site-b": [crawlerFinding({ findingKey: "SIBLING::b", title: "Sibling finding" })],
      "site-c": [crawlerFinding({ findingKey: "TENANT::c", title: "Other tenant finding" })],
    },
    recommendations: {
      "site-a": [generatedRecommendation()],
      "site-b": [generatedRecommendation({ recommendationId: "rec-b", title: "Sibling rec" })],
    },
  };
}

export function moduleRequest(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    contractVersion: "module-contract.v1",
    moduleId: "seo",
    capability: "analyse.technical_audit",
    requestId: "req-1",
    businessId: "biz-1",
    websiteIdentity: {
      normalizedHost: "example.com",
      assessedUrl: "https://www.example.com/",
    },
    ...overrides,
  };
}

/** An EXECUTE envelope, with Brain's own derived idempotency key. */
export function executeRequest(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const capability = (overrides.capability as string) ?? "execute.technical_audit";
  const brainActionId = (overrides.brainActionId as string) ?? "brain-action-1";
  return {
    ...moduleRequest({ capability }),
    actorId: "brain-actor-1",
    brainActionId,
    // deriveModuleIdempotencyKey(brainActionId, capability) in Digi Brain.
    idempotencyKey: `${brainActionId}:${capability}`,
    parameters: {},
    ...overrides,
  };
}

/** A STATUS envelope, carrying the ORIGINATING execute.* capability key. */
export function statusRequest(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const capability = (overrides.capability as string) ?? "execute.technical_audit";
  return {
    ...moduleRequest({ capability }),
    actorId: "brain-actor-1",
    brainActionId: "brain-action-1",
    ...overrides,
  };
}
