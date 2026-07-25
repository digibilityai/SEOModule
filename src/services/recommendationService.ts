import type { SeoIssue, SeoRecommendation, SeoUserRole, SeoWebsite } from "@/types";
import { toAsync } from "@/lib/mockAsync";
import {
  listRecommendations,
  getRecommendationById,
  listOnPageRecommendations,
  regenerateRecommendationsForWebsite,
} from "@/mocks/recommendationMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { fetchLatestAudit, fetchIssuesForAudit } from "@/services/auditService";
import {
  fetchSupabaseOnPageRecommendations,
  fetchSupabaseRecommendationById,
  fetchSupabaseRecommendations,
  generateSupabaseRecommendations,
} from "@/services/supabase/seoRecommendationSupabaseService";

export async function fetchRecommendations(websiteId: string): Promise<SeoRecommendation[]> {
  return runWithServiceAdapter({
    label: "recommendationService.fetchRecommendations",
    mock: () => toAsync(listRecommendations(websiteId)),
    supabase: () => fetchSupabaseRecommendations(websiteId),
  });
}

export async function fetchOnPageRecommendations(websiteId: string): Promise<SeoRecommendation[]> {
  return runWithServiceAdapter({
    label: "recommendationService.fetchOnPageRecommendations",
    mock: () => toAsync(listOnPageRecommendations(websiteId)),
    supabase: () => fetchSupabaseOnPageRecommendations(websiteId),
  });
}

export async function fetchRecommendationById(id: string): Promise<SeoRecommendation | null> {
  return runWithServiceAdapter({
    label: "recommendationService.fetchRecommendationById",
    mock: () => toAsync(getRecommendationById(id)),
    supabase: () => fetchSupabaseRecommendationById(id),
  });
}

// Stays mock-only in every data mode, by design — this is the automatic
// generation that WebsiteAuditPage's mock "Run Audit" flow triggers as soon
// as a (synchronous, mock) audit completes. In practice this is never
// reached in Supabase mode: its only caller gates it behind
// `audit.status === "completed"`, and the Supabase `runAudit()` path in
// auditService.ts always returns "running" (real audits complete
// asynchronously via the crawler). Recommendation Generation Stage 1 adds a
// separate, explicit, manually-triggered path for Supabase mode below
// (`generateRecommendations`) rather than changing this auto-trigger.
export async function generateRecommendationsFromAudit(
  website: SeoWebsite,
  issues: SeoIssue[],
): Promise<SeoRecommendation[]> {
  return toAsync(regenerateRecommendationsForWebsite(website, issues));
}

// Recommendation Generation Stage 2 — roles permitted to trigger generation,
// mirrors the seo_recommendation_generate RPC's server-side owner/admin/
// team_member gate. Presentation-only (the RPC remains the authoritative
// check) — same convention as COMPETITOR_GENERATE_ROLES.
export const RECOMMENDATION_GENERATE_ROLES: SeoUserRole[] = ["owner", "admin", "team_member"];

/**
 * Whether the current UI should offer the "Generate Recommendations"
 * control. Mock mode has no real seo_workspace_members row, so generation
 * stays enabled there (unchanged mock-mode behaviour, matches
 * canGenerateCompetitorBenchmarks). In Supabase mode, only owner/admin/
 * team_member see it enabled — client and any other role see it disabled.
 * This is a usability layer only; the RPC re-enforces the same gate
 * server-side.
 */
export function canGenerateRecommendations(role: SeoUserRole | null, supabaseMode: boolean): boolean {
  if (!supabaseMode) return true;
  return role !== null && RECOMMENDATION_GENERATE_ROLES.includes(role);
}

/**
 * Recommendation Generation Stage 1/2 — manually triggered generation from
 * the latest completed audit's real findings. In Supabase mode this calls
 * the guarded `seo_recommendation_generate` RPC (server-derived workspace/
 * actor/business-context, deterministic mapping, replace-to-match, no
 * client-supplied content) and re-reads the canonical persisted set — the
 * backend's mapping/heuristic logic is never reproduced here. In mock mode
 * this reuses the existing local generator unchanged (same function
 * `generateRecommendationsFromAudit` already calls), driven by the latest
 * completed mock audit's own issues rather than requiring the caller to
 * pass them, so this function's signature matches the established
 * `generate<X>(website)` shape used by Competitor/Reports Stage 2.
 */
export async function generateRecommendations(website: SeoWebsite): Promise<SeoRecommendation[]> {
  return runWithServiceAdapter({
    label: "recommendationService.generateRecommendations",
    mock: () => generateMockRecommendations(website),
    supabase: () => generateSupabaseRecommendations(website.id),
    fallbackToMockOnError: false,
  });
}

async function generateMockRecommendations(website: SeoWebsite): Promise<SeoRecommendation[]> {
  const latestAudit = await fetchLatestAudit(website.id);
  const issues = latestAudit?.status === "completed" ? await fetchIssuesForAudit(latestAudit.id) : [];
  return toAsync(regenerateRecommendationsForWebsite(website, issues));
}
