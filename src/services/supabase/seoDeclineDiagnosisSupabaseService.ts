import type { DeclineCause, DeclineDiagnosis, ImpactLevel, OwnerType } from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { requireAuthenticatedUser, requireValidUuid, safeList } from "@/services/supabase/supabaseServiceUtils";
import { listAccessibleSeoWorkspaces } from "@/services/supabase/seoWorkspaceService";
import { fetchSupabaseWebsitesForWorkspace } from "@/services/supabase/seoWebsiteSupabaseService";

// =============================================================================
// Phase 14B.2 — Decline Diagnosis Engine (Stage 5, read-only).
//
// The app's existing DeclineDiagnosis shape (src/types/performance.ts) is a
// flat, single-cause model — a holdover from the mock adapter, same as
// PagePerformance was before Phase 14A.2. Stage 5's backend is richer
// (diagnosis_type/severity/priority/status/suggested_owner plus a separate
// evidence table — see SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md).
// This file reads Stage 5 and maps it down into the app's existing
// DeclineDiagnosis shape, so no UI component or type changes are needed —
// only performanceService.ts's two diagnosis-facing functions change.
//
// `page_performance_id` on the mapped result is the Stage 4 page inventory
// id (seo_decline_diagnoses.page_id), which is exactly what
// seoPagePerformanceSupabaseService's PagePerformance.id already is (see
// mapToPagePerformance) — this is what makes
// `pages.find((p) => p.id === diagnosis.page_performance_id)` in
// DeclineDiagnosisPage.tsx keep working unchanged.
//
// Read-only this phase: no INSERT/UPDATE/DELETE anywhere below, and the
// seo_create_decline_diagnosis_from_snapshot RPC is intentionally NOT called
// here — nothing in the current UI writes a diagnosis, so wiring a write path
// would be unused surface area (see PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md).
// =============================================================================

interface SeoDeclineDiagnosisRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  page_id: string;
  page_url: string;
  page_keyword_id: string | null;
  keyword: string | null;
  performance_snapshot_id: string | null;
  diagnosis_type: string;
  severity: string;
  confidence_percentage: number | null;
  movement_status: string | null;
  business_summary: string;
  likely_cause: string;
  technical_explanation: string | null;
  recommended_next_action: string;
  suggested_owner: string;
  priority: string;
  status: string;
  linked_recommendation_id: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

// seo_decline_diagnoses_current (migration 16) is a superset of the base
// table's columns plus page context + latest Stage 4 performance context
// (see 20260711120016_seo_stage5_decline_diagnosis_current_view.sql) and is
// already filtered to live statuses (open/in_review/action_planned) — the
// view's own WHERE clause, not something this file needs to re-filter.
interface SeoDeclineDiagnosisCurrentRow extends SeoDeclineDiagnosisRow {
  page_title: string | null;
  page_type: string | null;
  content_status: string | null;
  indexability_status: string | null;
  latest_snapshot_date: string | null;
  latest_clicks: number | null;
  latest_impressions: number | null;
  latest_ctr: number | null;
  latest_average_position: number | null;
  latest_movement_status: string | null;
}

export interface SeoDeclineDiagnosisEvidenceRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  diagnosis_id: string;
  evidence_type: string;
  metric_name: string;
  current_value: string | null;
  previous_value: string | null;
  delta_value: string | null;
  evidence_summary: string;
  source: string;
  created_at: string;
  created_by: string | null;
}

const DIAGNOSIS_COLUMNS =
  "id, workspace_id, website_id, website_url, page_id, page_url, page_keyword_id, keyword, performance_snapshot_id, diagnosis_type, severity, confidence_percentage, movement_status, business_summary, likely_cause, technical_explanation, recommended_next_action, suggested_owner, priority, status, linked_recommendation_id, created_by, created_at, updated_at";

// Superset of DIAGNOSIS_COLUMNS — the view's own SELECT list (migration 16)
// adds page context + latest-performance context on top of every base column.
const CURRENT_VIEW_COLUMNS =
  "id, workspace_id, website_id, website_url, page_id, page_url, page_keyword_id, keyword, performance_snapshot_id, diagnosis_type, severity, confidence_percentage, movement_status, business_summary, likely_cause, technical_explanation, recommended_next_action, suggested_owner, priority, status, linked_recommendation_id, created_by, created_at, updated_at, page_title, page_type, content_status, indexability_status, latest_snapshot_date, latest_clicks, latest_impressions, latest_ctr, latest_average_position, latest_movement_status";

const EVIDENCE_COLUMNS =
  "id, workspace_id, website_id, website_url, diagnosis_id, evidence_type, metric_name, current_value, previous_value, delta_value, evidence_summary, source, created_at, created_by";

// -----------------------------------------------------------------------------
// Mapping: Stage 5 backend CHECK values -> the app's existing frontend domain
// values (DeclineCause / ImpactLevel / OwnerType — all defined pre-Stage-5 in
// src/types). None of these lookups can throw: every branch has a safe
// fallback, so an unrecognized/future backend value degrades to a generic
// label instead of crashing the page (per the Phase 14B.2 requirement — see
// PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md "Mapping").
// -----------------------------------------------------------------------------

// diagnosis_type (Stage 5, migration 14 CHECK) -> DeclineCause (frontend,
// pre-existing). Where Stage 5 has more granularity than the frontend model
// (e.g. clicks_decline / impressions_decline both being "visibility is
// dropping"), several backend values intentionally collapse onto the same
// frontend cause rather than inventing a new frontend label.
const DIAGNOSIS_TYPE_TO_CAUSE: Record<string, DeclineCause> = {
  ctr_drop: "ctr_drop",
  ranking_decline: "ranking_loss",
  clicks_decline: "ranking_loss",
  impressions_decline: "ranking_loss",
  content_freshness: "freshness_issue",
  indexing_issue: "indexing_issue",
  cannibalization_risk: "cannibalization",
  intent_mismatch: "intent_mismatch",
  competitor_improvement: "competitor_improvement",
  technical_performance: "technical_issue",
};
// "no_data" / "mixed_signals" (Stage 5) mean "not enough/ambiguous evidence
// yet" — the frontend DeclineCause union has no equivalent value. Falling
// back to "technical_issue" is a deliberately neutral, non-alarming choice
// (it does not assert a specific content/keyword/competitor claim that may
// not be true) rather than a precise diagnosis. Also the fallback for any
// future/unrecognized diagnosis_type this file doesn't yet know about.
const DEFAULT_DECLINE_CAUSE: DeclineCause = "technical_issue";

function mapDiagnosisTypeToCause(diagnosisType: string): DeclineCause {
  return DIAGNOSIS_TYPE_TO_CAUSE[diagnosisType] ?? DEFAULT_DECLINE_CAUSE;
}

// priority (Stage 5: low/medium/high) already shares the frontend's
// ImpactLevel domain 1:1. severity (Stage 5: low/medium/high/critical) has no
// frontend field of its own — a "critical" severity is folded into
// priority="high" so the most urgent items are never under-prioritized in the
// existing UI, which only understands a 3-value priority.
const VALID_IMPACT_LEVELS: ReadonlySet<string> = new Set(["low", "medium", "high"]);
function mapPriority(priority: string, severity: string): ImpactLevel {
  if (severity === "critical") return "high";
  return VALID_IMPACT_LEVELS.has(priority) ? (priority as ImpactLevel) : "medium";
}

// suggested_owner (Stage 5) shares the frontend's OwnerType domain 1:1 by
// design (both were defined against the same product spec) — validated
// rather than blindly cast, so a future/unrecognized value falls back safely
// instead of producing an invalid OwnerType the UI's label lookup can't render.
const VALID_OWNER_TYPES: ReadonlySet<string> = new Set([
  "client_action",
  "developer_needed",
  "digibility_expert",
  "system_suggestion",
]);
const DEFAULT_OWNER: OwnerType = "system_suggestion";
function mapOwner(owner: string): OwnerType {
  return VALID_OWNER_TYPES.has(owner) ? (owner as OwnerType) : DEFAULT_OWNER;
}

// status (open/in_review/action_planned/resolved/dismissed) has no frontend
// field either — instead of mapping it, the "live" list read
// (fetchSupabaseDeclineDiagnoses) queries seo_decline_diagnoses_current,
// whose own WHERE clause already excludes resolved/dismissed rows, so a
// resolved/dismissed diagnosis simply never reaches the mapper. The
// page/history read (fetchSupabaseDiagnosesForPage) queries the base table
// directly and can surface all statuses, matching the task's "full/
// detail/history" requirement.
//
// movement_status, evidence_type, and source are read (movement_status on
// the diagnosis row; evidence_type/source on evidence rows) but not mapped
// into DeclineDiagnosis — there is no frontend field for any of them yet.
// They pass through unmapped in the raw row types below for the dev harness
// and any future evidence UI, exactly as Stage 4's dev harness already does
// for movement_status on raw snapshot rows.

function mapToDeclineDiagnosis(row: SeoDeclineDiagnosisRow): DeclineDiagnosis {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    page_performance_id: row.page_id,
    page_url: row.page_url,
    related_keyword: row.keyword ?? undefined,
    likely_cause: mapDiagnosisTypeToCause(row.diagnosis_type),
    confidence_percentage: row.confidence_percentage ?? 0,
    business_explanation: row.business_summary,
    technical_explanation: row.technical_explanation ?? "",
    recommended_fix: row.recommended_next_action,
    priority: mapPriority(row.priority, row.severity),
    fix_owner: mapOwner(row.suggested_owner),
    needs_expert_support: row.suggested_owner === "digibility_expert",
  };
}

/**
 * Raw seo_decline_diagnoses_current rows for a website (live statuses only —
 * open/in_review/action_planned, per the view's own filter). Read-only.
 * Exposed separately from fetchSupabaseDeclineDiagnoses so dev/diagnostic UI
 * can inspect the full backend shape (severity, status, latest performance
 * context, etc.) that the flattened DeclineDiagnosis type doesn't carry.
 */
export async function fetchSupabaseCurrentDiagnosisRows(
  websiteId: string,
): Promise<SeoDeclineDiagnosisCurrentRow[]> {
  await requireAuthenticatedUser("seoDeclineDiagnosisSupabaseService.fetchSupabaseCurrentDiagnosisRows");
  requireValidUuid("seoDeclineDiagnosisSupabaseService.fetchSupabaseCurrentDiagnosisRows", websiteId, "websiteId");

  return safeList<SeoDeclineDiagnosisCurrentRow>(
    "seoDeclineDiagnosisSupabaseService.fetchSupabaseCurrentDiagnosisRows",
    supabase
      .from(SEO_TABLES.declineDiagnosesCurrentView)
      .select(CURRENT_VIEW_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
}

/**
 * Main app-facing read: live (open/in_review/action_planned) decline
 * diagnoses for a website, mapped into the app's existing DeclineDiagnosis[]
 * shape. Matches the "active/current diagnosis list" use in
 * DeclineDiagnosisPage.tsx and roadmapService.ts.
 */
export async function fetchSupabaseDeclineDiagnoses(websiteId: string): Promise<DeclineDiagnosis[]> {
  const rows = await fetchSupabaseCurrentDiagnosisRows(websiteId);
  return rows.map(mapToDeclineDiagnosis);
}

/**
 * All diagnoses for a single page (any status — open/in_review/
 * action_planned/resolved/dismissed), newest first, mapped into
 * DeclineDiagnosis[]. Reads the base table directly (not the current view),
 * so a full page-level history is available even though nothing in the
 * current UI calls this yet (see performanceService.fetchDiagnosisForPage).
 */
export async function fetchSupabaseDiagnosesForPage(pageId: string): Promise<DeclineDiagnosis[]> {
  await requireAuthenticatedUser("seoDeclineDiagnosisSupabaseService.fetchSupabaseDiagnosesForPage");
  requireValidUuid("seoDeclineDiagnosisSupabaseService.fetchSupabaseDiagnosesForPage", pageId, "pageId");

  const rows = await safeList<SeoDeclineDiagnosisRow>(
    "seoDeclineDiagnosisSupabaseService.fetchSupabaseDiagnosesForPage",
    supabase.from(SEO_TABLES.declineDiagnoses).select(DIAGNOSIS_COLUMNS).eq("page_id", pageId).order("created_at", {
      ascending: false,
    }),
  );
  return rows.map(mapToDeclineDiagnosis);
}

/**
 * Raw evidence rows for a single diagnosis, oldest first. Read-only. No
 * frontend domain type exists for evidence yet, so this returns the raw
 * Supabase row shape directly — same precedent as Stage 4's dev-harness
 * snapshot reads.
 */
export async function fetchSupabaseDiagnosisEvidence(
  diagnosisId: string,
): Promise<SeoDeclineDiagnosisEvidenceRow[]> {
  await requireAuthenticatedUser("seoDeclineDiagnosisSupabaseService.fetchSupabaseDiagnosisEvidence");
  requireValidUuid("seoDeclineDiagnosisSupabaseService.fetchSupabaseDiagnosisEvidence", diagnosisId, "diagnosisId");

  return safeList<SeoDeclineDiagnosisEvidenceRow>(
    "seoDeclineDiagnosisSupabaseService.fetchSupabaseDiagnosisEvidence",
    supabase
      .from(SEO_TABLES.declineDiagnosisEvidence)
      .select(EVIDENCE_COLUMNS)
      .eq("diagnosis_id", diagnosisId)
      .order("created_at", { ascending: true }),
  );
}

export interface WebsiteWithDeclineDiagnosisData {
  workspaceId: string;
  workspaceName: string;
  websiteId: string;
  websiteUrl: string;
  diagnosisCount: number;
  /** How many accessible websites had at least one live diagnosis (including the returned one) — dev-harness/debug context for why this candidate won. */
  candidateCount: number;
}

/**
 * Searches every SEO workspace the current user is a member of (not just
 * whichever one getCurrentSeoWorkspace defaults to), and every website within
 * each, for the one with the MOST live (open/in_review/action_planned)
 * decline diagnosis rows. `null` if none have any. Read-only, no writes.
 *
 * Does NOT stop at the first website with any data — a test user can
 * legitimately be a member of several workspaces that each have a handful of
 * diagnosis rows (e.g. a disposable Stage 5 smoke-test workspace alongside
 * the intentionally richer UI seed workspace), and "first found" previously
 * meant "whichever workspace happens to be newest" (listAccessibleSeoWorkspaces
 * orders created_at DESC), not "the one with the most real data." Every
 * accessible website is checked and ranked by its live diagnosis count,
 * highest first; ties fall back to the order candidates were discovered in,
 * which is itself workspace-created_at-DESC (from listAccessibleSeoWorkspaces)
 * then whatever order fetchSupabaseWebsitesForWorkspace returns within a
 * workspace — Array.prototype.sort is stable, so this ordering is preserved
 * without a second query or touching either shared helper.
 *
 * Does NOT hardcode any specific workspace/website id or name, and does NOT
 * special-case anything by name (e.g. "smoke") — ranking is purely by live
 * diagnosis count. Used by the `/seo/dev/auth-test` harness and as a
 * Supabase-mode-only fallback on DeclineDiagnosisPage when the auto-selected
 * active website has none.
 */
export async function findAccessibleWebsiteWithDeclineDiagnosisData(): Promise<WebsiteWithDeclineDiagnosisData | null> {
  await requireAuthenticatedUser("seoDeclineDiagnosisSupabaseService.findAccessibleWebsiteWithDeclineDiagnosisData");

  const workspaces = await listAccessibleSeoWorkspaces();
  const candidates: Omit<WebsiteWithDeclineDiagnosisData, "candidateCount">[] = [];

  for (const workspace of workspaces) {
    const websites = await fetchSupabaseWebsitesForWorkspace(workspace.id);
    for (const website of websites) {
      const rows = await fetchSupabaseCurrentDiagnosisRows(website.id);
      if (rows.length > 0) {
        candidates.push({
          workspaceId: workspace.id,
          workspaceName: workspace.name,
          websiteId: website.id,
          websiteUrl: website.website_url,
          diagnosisCount: rows.length,
        });
      }
    }
  }

  if (candidates.length === 0) return null;

  candidates.sort((a, b) => b.diagnosisCount - a.diagnosisCount);

  return { ...candidates[0], candidateCount: candidates.length };
}
