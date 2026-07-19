import type {
  AiContentGap,
  AiVisibilityOverview,
  BrandMentionSummary,
  CompetitorMentionSummary,
  PromptTrackingRecord,
  SeoWebsite,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { fetchLatestAudit } from "@/services/auditService";
import {
  AI_VISIBILITY_DATA_SOURCE_STATUS,
  buildBrandMentionSummary,
  buildCompetitorMentionSummaries,
  generateAiVisibilityDataForWebsite,
  listAiContentGaps,
  listPromptTracking,
  updatePromptTrackingStatus as updatePromptTrackingStatusRecord,
} from "@/mocks/aiVisibilityMockData";
import {
  fetchSupabaseAiContentGaps,
  fetchSupabaseBrandMentionSummary,
  fetchSupabaseCompetitorMentionSummaries,
  fetchSupabasePromptTrackingRecords,
} from "@/services/supabase/seoAiVisibilitySupabaseService";

// Phase 15A: fetchPromptTrackingRecords / fetchBrandMentionSummary /
// fetchCompetitorMentionSummary / fetchAiContentGaps are wired via
// runWithServiceAdapter — mock mode is unchanged; Supabase mode reads Stage 6
// (seo_ai_prompt_tracking, seo_ai_content_gaps, seo_ai_mentions), mapped down
// into these same existing PromptTrackingRecord/AiContentGap/
// Brand-CompetitorMentionSummary shapes (see
// seoAiVisibilitySupabaseService.ts — mention summaries prefer the
// normalized seo_ai_mentions table over re-deriving from prompt arrays, per
// Stage 6 D2). No type or UI change.
//
// updateAiVisibilityItemStatus / generateMockAiVisibilityRefresh remain
// MOCK-ONLY in every data mode this phase. updateAiVisibilityItemStatus has
// no live caller in the current UI (AiVisibilityPage.tsx never calls it), so
// there is nothing to wire yet even though Stage 6 allows plain-RLS writes to
// seo_ai_prompt_tracking (no transition RPC needed for AI Visibility, unlike
// Off-Page). generateMockAiVisibilityRefresh is explicitly a mock-data
// generator by name/design (same precedent as
// performanceService.generateMockPerformanceRefresh, Phase 14A.2) and stays
// that way in every mode. See
// PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md §7.

export async function fetchPromptTrackingRecords(websiteId: string): Promise<PromptTrackingRecord[]> {
  return runWithServiceAdapter({
    label: "aiVisibilityService.fetchPromptTrackingRecords",
    mock: () => toAsync(listPromptTracking(websiteId)),
    supabase: () => fetchSupabasePromptTrackingRecords(websiteId),
  });
}

export async function updateAiVisibilityItemStatus(
  id: string,
  visibilityStatus: PromptTrackingRecord["visibility_status"],
): Promise<PromptTrackingRecord | null> {
  return toAsync(updatePromptTrackingStatusRecord(id, visibilityStatus));
}

export async function fetchBrandMentionSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<BrandMentionSummary> {
  return runWithServiceAdapter({
    label: "aiVisibilityService.fetchBrandMentionSummary",
    mock: () => toAsync(buildBrandMentionSummary(websiteId, websiteUrl)),
    supabase: () => fetchSupabaseBrandMentionSummary(websiteId, websiteUrl),
  });
}

export async function fetchCompetitorMentionSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<CompetitorMentionSummary[]> {
  return runWithServiceAdapter({
    label: "aiVisibilityService.fetchCompetitorMentionSummary",
    mock: () => toAsync(buildCompetitorMentionSummaries(websiteId, websiteUrl)),
    supabase: () => fetchSupabaseCompetitorMentionSummaries(websiteId, websiteUrl),
  });
}

export async function fetchAiContentGaps(websiteId: string): Promise<AiContentGap[]> {
  return runWithServiceAdapter({
    label: "aiVisibilityService.fetchAiContentGaps",
    mock: () => toAsync(listAiContentGaps(websiteId)),
    supabase: () => fetchSupabaseAiContentGaps(websiteId),
  });
}

export async function generateMockAiVisibilityRefresh(website: SeoWebsite): Promise<PromptTrackingRecord[]> {
  return toAsync(
    generateAiVisibilityDataForWebsite(
      website.id,
      website.workspace_id,
      website.website_url,
      website.user_id,
      website.business_name,
    ),
  );
}

// Derives from the now adapter-wired reads above, so this stays correct in
// both modes automatically — same "derive from the wired read" pattern as
// performanceService.fetchPerformanceSummary (Phase 14A.2) and
// offPageService.fetchAuthorityOverview (Phase 15A).
export async function fetchAiVisibilityOverview(
  websiteId: string,
  websiteUrl: string,
): Promise<AiVisibilityOverview> {
  const [prompts, contentGaps, competitorSummaries, brandSummary, latestAudit] = await Promise.all([
    fetchPromptTrackingRecords(websiteId),
    fetchAiContentGaps(websiteId),
    fetchCompetitorMentionSummary(websiteId, websiteUrl),
    fetchBrandMentionSummary(websiteId, websiteUrl),
    fetchLatestAudit(websiteId),
  ]);
  const citationGapCount = prompts.filter((p) => !p.our_site_cited).length;

  return toAsync({
    website_id: websiteId,
    website_url: websiteUrl,
    ai_discovery_score: latestAudit?.ai_discovery_score ?? 0,
    brand_mention_count: brandSummary.brand_mention_count,
    competitor_mention_count: competitorSummaries.length,
    citation_gap_count: citationGapCount,
    content_gap_count: contentGaps.length,
    prompt_tracking_status:
      prompts.length === 0
        ? "No prompts tracked yet."
        : `${prompts.length} prompt${prompts.length === 1 ? "" : "s"} tracked.`,
    data_source_status: AI_VISIBILITY_DATA_SOURCE_STATUS,
  });
}
