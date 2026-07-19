import type {
  ActionType,
  EffortLevel,
  ImpactLevel,
  PendingApprovalsSummary,
  PriorityFixStatus,
  RecommendationStatus,
  RiskLevel,
  TopPriorityFix,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { requireAuthenticatedUser, safeList } from "@/services/supabase/supabaseServiceUtils";

// =============================================================================
// Phase 13F — Dashboard summary reads (Stage 1-3, read-only).
//
// Only two dashboardService.ts functions need a Supabase path: everything
// else on /seo/dashboard (visibility scores, setup checklist, recommended
// next step) is built from data the page already gets via already-wired
// services (auditService, businessOnboardingService) or is a pure function
// with no I/O — no separate wiring needed there. Page Performance / Off-Page
// / AI Visibility / Competitor / Roadmap / Support / Reports widgets on the
// same page stay mock-only (their services are untouched, out of scope).
// =============================================================================

interface SeoRecommendationSummaryRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  issue_id: string | null;
  title: string;
  suggested_change: string;
  why_it_helps: string;
  action_type: ActionType;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  status: RecommendationStatus;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const RECOMMENDATION_SUMMARY_COLUMNS =
  "id, workspace_id, website_id, website_url, issue_id, title, suggested_change, why_it_helps, action_type, impact, effort, risk, confidence_percentage, status, created_by, created_at, updated_at";

const IMPACT_WEIGHT: Record<ImpactLevel, number> = { high: 3, medium: 2, low: 1 };
const MAX_TOP_FIXES = 5;

// Recommendation → priority-fix status. Stage 2 has no direct "in_progress"
// concept, so anything past "suggested/needs_review" but not yet
// completed/rejected is treated as in_progress.
const STATUS_TO_FIX_STATUS: Record<RecommendationStatus, PriorityFixStatus> = {
  suggested: "open",
  needs_review: "open",
  approved: "in_progress",
  developer_needed: "in_progress",
  expert_review_requested: "in_progress",
  ready_to_publish: "in_progress",
  rejected: "dismissed",
  completed: "resolved",
};

function mapToTopPriorityFix(row: SeoRecommendationSummaryRow): TopPriorityFix {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    title: row.title,
    simple_explanation: row.why_it_helps,
    impact: row.impact,
    effort: row.effort,
    risk: row.risk,
    confidence_percentage: row.confidence_percentage,
    recommended_next_action: row.suggested_change,
    action_type: row.action_type,
    status: STATUS_TO_FIX_STATUS[row.status] ?? "open",
    source_issue_id: row.issue_id ?? undefined,
    source_recommendation_id: row.id,
  };
}

/**
 * Derives "Top Priority Fixes" from Stage 2 seo_recommendations
 * (`is_current=true`) — there is no dedicated fixes table. Ranks by the
 * same impact/confidence weighting the mock adapter uses and caps at 5.
 * Read-only; no writes, no RPC calls.
 */
export async function fetchSupabaseTopPriorityFixes(websiteId: string): Promise<TopPriorityFix[]> {
  await requireAuthenticatedUser("seoDashboardSupabaseService.fetchSupabaseTopPriorityFixes");
  const rows = await safeList<SeoRecommendationSummaryRow>(
    "seoDashboardSupabaseService.fetchSupabaseTopPriorityFixes",
    supabase
      .from(SEO_TABLES.recommendations)
      .select(RECOMMENDATION_SUMMARY_COLUMNS)
      .eq("website_id", websiteId)
      .eq("is_current", true),
  );
  const sorted = [...rows].sort(
    (a, b) =>
      IMPACT_WEIGHT[b.impact] - IMPACT_WEIGHT[a.impact] || b.confidence_percentage - a.confidence_percentage,
  );
  return sorted.slice(0, MAX_TOP_FIXES).map(mapToTopPriorityFix);
}

/** Summarizes Stage 2 seo_approval_items counts for a website. Read-only; no writes. */
export async function fetchSupabasePendingApprovalsSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<PendingApprovalsSummary> {
  await requireAuthenticatedUser("seoDashboardSupabaseService.fetchSupabasePendingApprovalsSummary");
  const rows = await safeList<{ status: string; fix_owner: string }>(
    "seoDashboardSupabaseService.fetchSupabasePendingApprovalsSummary",
    supabase.from(SEO_TABLES.approvalItems).select("status, fix_owner").eq("website_id", websiteId),
  );
  const pending = rows.filter((row) => row.status === "suggested" || row.status === "needs_review").length;
  const expertReview = rows.filter((row) => row.status === "expert_review_requested").length;
  const developerNeeded = rows.filter(
    (row) => row.fix_owner === "developer_needed" || row.status === "developer_needed",
  ).length;

  return {
    website_id: websiteId,
    website_url: websiteUrl,
    pending_count: pending,
    expert_review_count: expertReview,
    developer_needed_count: developerNeeded,
  };
}
