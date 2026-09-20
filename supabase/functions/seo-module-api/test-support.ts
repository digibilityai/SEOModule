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

export interface FakeStore {
  websites: FakeWebsite[];
  links: FakeLink[];
  ownership?: Record<string, Partial<OwnershipStatus>>;
  audits?: Record<string, { auditRunId: string; completedAt: string } | null>;
  findings?: Record<string, CrawlFinding[]>;
  recommendations?: Record<string, Recommendation[]>;
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
    capability: "analyse.crawl_findings",
    requestId: "req-1",
    businessId: "biz-1",
    websiteIdentity: {
      normalizedHost: "example.com",
      assessedUrl: "https://www.example.com/",
    },
    ...overrides,
  };
}
