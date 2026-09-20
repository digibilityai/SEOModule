/**
 * The data boundary the machine path depends on.
 *
 * Every method maps one-to-one onto one delegated, service-role-only RPC from
 * migration 20260920120100. Nothing here accepts a workspace_id or a
 * website_id: the target is always (businessId, normalizedHost) and is always
 * resolved inside SQL through the human-authorized link table, so no caller,
 * including this function, can name a website it was not linked to.
 *
 * This interface is also the isolation seam that makes browser mock fallback
 * structurally unreachable. It has no dependency on src/, so
 * src/services/serviceAdapter.ts, src/services/dataMode.ts and src/mocks/ are
 * not in this module's import graph at all and cannot be reached from it.
 */

export const RESOLUTION_VALUES = [
  "resolved",
  "not_linked",
  "revoked",
  "host_changed",
  "website_inactive",
  "website_missing",
  "invalid_target",
  "no_completed_audit",
  // Delegated write and status resolutions.
  "actor_required",
  "actor_not_linked",
  "actor_unauthorized",
  "ownership_not_verified",
  "no_genuine_audit_evidence",
  "operation_not_found",
  "operation_mismatch",
  "execution_failed",
  "invalid_request",
] as const;
export type TargetResolutionCode = (typeof RESOLUTION_VALUES)[number];

export interface ResolvedTarget {
  resolution: TargetResolutionCode;
  websiteId: string | null;
  workspaceId: string | null;
  normalizedHost: string | null;
  websiteUrl: string | null;
  linkedAt: string | null;
}

export interface OwnershipStatus {
  resolution: TargetResolutionCode;
  websiteId: string | null;
  verificationHost: string | null;
  method: string | null;
  ownershipSource: string | null;
  status: string | null;
  verifiedAt: string | null;
  lastCheckedAt: string | null;
  failureReason: string | null;
}

export interface CrawlFinding {
  findingKey: string;
  title: string;
  observation: string;
  recommendedAction: string;
  /** SEO severity: critical | high | medium | low. Mapped, not passed through. */
  severity: string;
  category: string | null;
  affectedPageUrl: string | null;
  issueScope: string | null;
  source: string | null;
  crawlJobId: string | null;
  sourceIssueFingerprint: string | null;
  sourceRuleVersion: string | null;
}

export interface CrawlFindingsPage {
  resolution: TargetResolutionCode;
  websiteId: string | null;
  auditRunId: string | null;
  auditCompletedAt: string | null;
  findings: CrawlFinding[];
}

export interface Recommendation {
  recommendationId: string;
  findingKey: string;
  area: string;
  title: string;
  currentValue: string | null;
  suggestedChange: string;
  whyItHelps: string;
  actionType: string;
  /** SEO impact: high | medium | low. Mapped onto contract severity. */
  impact: string;
  effort: string;
  risk: string;
  status: string;
  generationMethod: string | null;
  sourceIssueFingerprint: string | null;
  auditRunId: string | null;
  updatedAt: string | null;
}

export interface RecommendationsPage {
  resolution: TargetResolutionCode;
  websiteId: string | null;
  recommendations: Recommendation[];
}

/**
 * The outcome of a delegated EXECUTE. `resolution` carries SEO's own reason;
 * the handler maps it onto either a Contract v1 error or an acknowledgement
 * with `accepted: false`.
 */
export interface DelegatedOperation {
  resolution: TargetResolutionCode;
  websiteId: string | null;
  /** The REAL crawl job id for a technical audit; the operation id otherwise. */
  moduleOperationId: string | null;
  /** SEO's own status vocabulary, carried unmapped to Brain. */
  moduleStatus: string | null;
  auditRunId: string | null;
  /** Present only for recommendation generation. */
  generationMethod: string | null;
  generatedCount: number | null;
  /** The SEO user the operation genuinely ran as. Attribution, not identity. */
  actedAsUserId: string | null;
  /** True when an earlier identical Brain action resolved to this operation. */
  replayed: boolean;
  /** SEO-side failure detail. Logged, never placed on the wire. */
  detail: string | null;
}

export interface SeoDataPort {
  resolveTarget(businessId: string, normalizedHost: string): Promise<ResolvedTarget>;
  ownershipStatus(businessId: string, normalizedHost: string): Promise<OwnershipStatus>;
  crawlFindings(businessId: string, normalizedHost: string): Promise<CrawlFindingsPage>;
  currentRecommendations(businessId: string, normalizedHost: string): Promise<RecommendationsPage>;

  requestTechnicalAudit(args: DelegatedExecuteArgs): Promise<DelegatedOperation>;
  technicalAuditStatus(args: DelegatedStatusArgs): Promise<DelegatedOperation>;
  generateRecommendations(args: DelegatedExecuteArgs): Promise<DelegatedOperation>;
  recommendationStatus(args: DelegatedStatusArgs): Promise<DelegatedOperation>;
}

export interface DelegatedExecuteArgs {
  businessId: string;
  normalizedHost: string;
  /** Digi Brain's actorId, opaque. Resolved to an SEO user inside SQL. */
  brainActorId: string;
  brainActionId: string;
  idempotencyKey: string;
}

export interface DelegatedStatusArgs {
  businessId: string;
  normalizedHost: string;
  brainActionId: string;
  moduleOperationId?: string;
}
