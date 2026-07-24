import type {
  ActionType,
  EffortLevel,
  ImpactLevel,
  RecommendationArea,
  RecommendationStatus,
  RiskLevel,
  SeoRecommendation,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import {
  requireAuthenticatedUser,
  requireValidUuid,
  safeList,
  safeSingle,
} from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

// Row shape as stored (Stage 2 migration 5, seo_recommendations). Several
// Stage-2-only columns (audit_run_id, is_high_risk_category, is_current,
// superseded_by) are intentionally not part of the app's SeoRecommendation
// type yet — read here only where needed (is_current, for filtering).
interface SeoRecommendationRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  issue_id: string | null;
  area: RecommendationArea;
  title: string;
  current_value: string | null;
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

const RECOMMENDATION_COLUMNS =
  "id, workspace_id, website_id, website_url, issue_id, area, title, current_value, suggested_change, why_it_helps, action_type, impact, effort, risk, confidence_percentage, status, created_by, created_at, updated_at";

// Matches the mock adapter's ON_PAGE_AREAS set (src/mocks/recommendationMockData.ts)
// — every area except "technical", which is audit-issue-derived.
const ON_PAGE_AREAS: RecommendationArea[] = [
  "title",
  "meta_description",
  "h1",
  "faq",
  "schema",
  "internal_links",
  "content",
];

function mapToSeoRecommendation(row: SeoRecommendationRow): SeoRecommendation {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    issue_id: row.issue_id ?? undefined,
    area: row.area,
    title: row.title,
    current_value: row.current_value ?? undefined,
    suggested_change: row.suggested_change,
    why_it_helps: row.why_it_helps,
    action_type: row.action_type,
    impact: row.impact,
    effort: row.effort,
    risk: row.risk,
    confidence_percentage: row.confidence_percentage,
    status: row.status,
  };
}

/** Lists the current (is_current=true) recommendations for a website. Empty array when none exist. */
export async function fetchSupabaseRecommendations(websiteId: string): Promise<SeoRecommendation[]> {
  await requireAuthenticatedUser("seoRecommendationSupabaseService.fetchSupabaseRecommendations");
  const rows = await safeList<SeoRecommendationRow>(
    "seoRecommendationSupabaseService.fetchSupabaseRecommendations",
    supabase
      .from(SEO_TABLES.recommendations)
      .select(RECOMMENDATION_COLUMNS)
      .eq("website_id", websiteId)
      .eq("is_current", true)
      .order("created_at", { ascending: false }),
  );
  return rows.map(mapToSeoRecommendation);
}

/** Same as fetchSupabaseRecommendations, filtered to on-page areas (for the Page Optimizer). */
export async function fetchSupabaseOnPageRecommendations(
  websiteId: string,
): Promise<SeoRecommendation[]> {
  await requireAuthenticatedUser("seoRecommendationSupabaseService.fetchSupabaseOnPageRecommendations");
  const rows = await safeList<SeoRecommendationRow>(
    "seoRecommendationSupabaseService.fetchSupabaseOnPageRecommendations",
    supabase
      .from(SEO_TABLES.recommendations)
      .select(RECOMMENDATION_COLUMNS)
      .eq("website_id", websiteId)
      .eq("is_current", true)
      .in("area", ON_PAGE_AREAS)
      .order("created_at", { ascending: false }),
  );
  return rows.map(mapToSeoRecommendation);
}

export async function fetchSupabaseRecommendationById(id: string): Promise<SeoRecommendation | null> {
  await requireAuthenticatedUser("seoRecommendationSupabaseService.fetchSupabaseRecommendationById");
  const row = await safeSingle<SeoRecommendationRow>(
    "seoRecommendationSupabaseService.fetchSupabaseRecommendationById",
    supabase.from(SEO_TABLES.recommendations).select(RECOMMENDATION_COLUMNS).eq("id", id).maybeSingle(),
  );
  return row ? mapToSeoRecommendation(row) : null;
}

/**
 * Recommendation Generation Stage 1 — calls the guarded
 * `seo_recommendation_generate` RPC (only the website id; no client-supplied
 * workspace/actor/content/provenance — the backend derives all of that and
 * is the sole authoritative gate) then re-reads the persisted canonical
 * current set through the existing Stage-1-equivalent read path, mirroring
 * `generateSupabaseCompetitors`'s "RPC then re-read" shape so the backend's
 * mapping/replace-to-match logic is never reproduced client-side. The RPC
 * itself already returns the canonical current set (`RETURNS SETOF
 * seo_recommendations`) — the response is validated as an array (proving
 * the call succeeded) but its rows are not trusted directly, for the same
 * "read the persisted state, don't trust the write response" discipline
 * used by every prior guarded-generation service function in this repo.
 */
export async function generateSupabaseRecommendations(websiteId: string): Promise<SeoRecommendation[]> {
  const label = "seoRecommendationSupabaseService.generateSupabaseRecommendations";
  await requireAuthenticatedUser(label);
  requireValidUuid(label, websiteId, "websiteId");

  const { data, error } = await supabase.rpc(SEO_RPCS.recommendationGenerate, {
    p_website_id: websiteId,
  });
  if (error) {
    throw new Error(`${label}: ${normalizeSupabaseError(error).message}`);
  }
  if (!Array.isArray(data)) {
    throw new Error(`${label}: unexpected RPC response (expected an array of rows, got ${JSON.stringify(data)}).`);
  }

  return fetchSupabaseRecommendations(websiteId);
}
