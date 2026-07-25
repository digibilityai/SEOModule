import type { Competitor, CompetitorStrengthStatus } from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import { requireAuthenticatedUser, requireValidUuid, safeList, safeSingle } from "@/services/supabase/supabaseServiceUtils";

// =============================================================================
// Competitor Benchmarking Stage 1 — real-data READ path (read-only).
//
// Reads public.seo_competitors (RLS: workspace-member SELECT) and flattens each
// row into the app's existing Competitor shape, so no UI/type change is needed
// beyond the optional data_provenance/generation_method fields. No INSERT/
// UPDATE/DELETE, no RPC, no generation: rows are produced by a future Stage 2
// generation path (or, in TEST, by the read-path fixtures).
//
// Provenance is truthful: scores are heuristic ESTIMATES (data_provenance =
// 'estimated'), never external measured competitor intelligence.
// =============================================================================

export interface SeoCompetitorRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  competitor_name: string;
  competitor_url: string;
  normalized_competitor_url: string;
  business_category: string | null;
  target_location: string | null;
  content_strength_score: number;
  technical_health_score: number;
  authority_score: number;
  ai_visibility_score: number;
  review_strength_score: number;
  overall_strength_score: number;
  status: CompetitorStrengthStatus;
  what_they_do_better: string[] | null;
  what_they_are_missing: string[] | null;
  content_opportunities: string[] | null;
  authority_opportunities: string[] | null;
  ai_visibility_opportunities: string[] | null;
  suggested_next_action: string;
  data_provenance: string;
  generation_method: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const COMPETITOR_COLUMNS =
  "id, workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url, business_category, target_location, content_strength_score, technical_health_score, authority_score, ai_visibility_score, review_strength_score, overall_strength_score, status, what_they_do_better, what_they_are_missing, content_opportunities, authority_opportunities, ai_visibility_opportunities, suggested_next_action, data_provenance, generation_method, created_by, created_at, updated_at";

export function mapRowToCompetitor(row: SeoCompetitorRow): Competitor {
  const actor = row.created_by ?? "";
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: actor,
    created_by: actor,
    created_at: row.created_at,
    updated_at: row.updated_at,
    competitor_name: row.competitor_name,
    competitor_url: row.competitor_url,
    business_category: row.business_category ?? "",
    target_location: row.target_location ?? undefined,
    content_strength_score: row.content_strength_score,
    technical_health_score: row.technical_health_score,
    authority_score: row.authority_score,
    ai_visibility_score: row.ai_visibility_score,
    review_strength_score: row.review_strength_score,
    overall_strength_score: row.overall_strength_score,
    status: row.status,
    what_they_do_better: row.what_they_do_better ?? [],
    what_they_are_missing: row.what_they_are_missing ?? [],
    content_opportunities: row.content_opportunities ?? [],
    authority_opportunities: row.authority_opportunities ?? [],
    ai_visibility_opportunities: row.ai_visibility_opportunities ?? [],
    suggested_next_action: row.suggested_next_action,
    data_provenance: row.data_provenance,
    generation_method: row.generation_method ?? undefined,
  };
}

/** All persisted competitors for a website (highest overall strength first). Read-only. */
export async function fetchSupabaseCompetitors(websiteId: string): Promise<Competitor[]> {
  await requireAuthenticatedUser("seoCompetitorSupabaseService.fetchSupabaseCompetitors");
  requireValidUuid("seoCompetitorSupabaseService.fetchSupabaseCompetitors", websiteId, "websiteId");

  const rows = await safeList<SeoCompetitorRow>(
    "seoCompetitorSupabaseService.fetchSupabaseCompetitors",
    supabase
      .from(SEO_TABLES.competitors)
      .select(COMPETITOR_COLUMNS)
      .eq("website_id", websiteId)
      .order("overall_strength_score", { ascending: false })
      .order("id", { ascending: true }),
  );
  return rows.map(mapRowToCompetitor);
}

/** A single persisted competitor by id, or null. Read-only. */
export async function fetchSupabaseCompetitorDetail(id: string): Promise<Competitor | null> {
  await requireAuthenticatedUser("seoCompetitorSupabaseService.fetchSupabaseCompetitorDetail");
  requireValidUuid("seoCompetitorSupabaseService.fetchSupabaseCompetitorDetail", id, "id");

  const row = await safeSingle<SeoCompetitorRow>(
    "seoCompetitorSupabaseService.fetchSupabaseCompetitorDetail",
    supabase.from(SEO_TABLES.competitors).select(COMPETITOR_COLUMNS).eq("id", id).maybeSingle(),
  );
  return row ? mapRowToCompetitor(row) : null;
}

/**
 * Competitor Benchmarking Stage 2A — guarded generation. Calls the SECURITY
 * DEFINER `seo_competitor_generate` RPC (server-side authorization + the
 * repo's deterministic heuristic scoring + replace-to-match upsert), then
 * reads the persisted canonical set back through the Stage 1 read path — the
 * heuristic itself is never reproduced in the frontend. Sends only the
 * website id; the RPC accepts no workspace, actor, scores, provenance,
 * timestamps, or role data from the client.
 */
export async function generateSupabaseCompetitors(websiteId: string): Promise<Competitor[]> {
  const label = "seoCompetitorSupabaseService.generateSupabaseCompetitors";
  await requireAuthenticatedUser(label);
  requireValidUuid(label, websiteId, "websiteId");

  const { data, error } = await supabase.rpc(SEO_RPCS.competitorGenerate, {
    p_website_id: websiteId,
  });
  if (error) {
    throw new Error(`${label}: ${normalizeSupabaseError(error).message}`);
  }
  if (typeof data !== "number" || !Number.isFinite(data)) {
    throw new Error(`${label}: unexpected RPC response (expected a numeric count, got ${JSON.stringify(data)}).`);
  }

  return fetchSupabaseCompetitors(websiteId);
}
