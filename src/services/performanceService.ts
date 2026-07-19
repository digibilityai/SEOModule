import type {
  DeclineDiagnosis,
  PagePerformance,
  PerformanceSummary,
  RefreshRecommendation,
  SeoWebsite,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import {
  DATA_SOURCE_STATUS_MESSAGE,
  generatePerformanceDataForWebsite,
  getPagePerformanceById,
  getRefreshRecommendationForPage,
  listDeclineDiagnoses,
  listDiagnosesForPage,
  listPagePerformance,
  listRefreshRecommendations,
} from "@/mocks/performanceMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  fetchSupabasePageDetail,
  fetchSupabasePagePerformance,
} from "@/services/supabase/seoPagePerformanceSupabaseService";
import {
  fetchSupabaseDeclineDiagnoses,
  fetchSupabaseDiagnosesForPage,
} from "@/services/supabase/seoDeclineDiagnosisSupabaseService";

export async function fetchPagePerformance(websiteId: string): Promise<PagePerformance[]> {
  return runWithServiceAdapter({
    label: "performanceService.fetchPagePerformance",
    mock: () => toAsync(listPagePerformance(websiteId)),
    supabase: () => fetchSupabasePagePerformance(websiteId),
  });
}

export async function fetchPageDetail(pageId: string): Promise<PagePerformance | null> {
  return runWithServiceAdapter({
    label: "performanceService.fetchPageDetail",
    mock: () => toAsync(getPagePerformanceById(pageId)),
    supabase: () => fetchSupabasePageDetail(pageId),
  });
}

// Derives from fetchPagePerformance (now adapter-wired above), so this stays
// correct in both modes automatically — no separate Supabase summary query
// needed. Aggregation logic is unchanged from before Phase 14A.2.
export async function fetchPerformanceSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<PerformanceSummary> {
  const pages = await fetchPagePerformance(websiteId);
  const keywordSet = new Set<string>();
  pages.forEach((p) => {
    keywordSet.add(p.primary_keyword);
    p.secondary_keywords.forEach((k) => keywordSet.add(k));
  });

  const totalClicks = pages.reduce((sum, p) => sum + p.clicks, 0);
  const totalImpressions = pages.reduce((sum, p) => sum + p.impressions, 0);
  const positionEligible = pages.filter((p) => p.performance_status !== "not_enough_data");

  const lastUpdated = pages.reduce<string | null>((latest, p) => {
    if (!latest) return p.updated_at;
    return new Date(p.updated_at).getTime() > new Date(latest).getTime() ? p.updated_at : latest;
  }, null);

  return toAsync({
    website_id: websiteId,
    website_url: websiteUrl,
    tracked_pages_count: pages.length,
    tracked_keywords_count: keywordSet.size,
    improving_count: pages.filter((p) => p.performance_status === "improving").length,
    stable_count: pages.filter((p) => p.performance_status === "stable").length,
    declining_count: pages.filter((p) => p.performance_status === "declining").length,
    needs_refresh_count: pages.filter((p) => p.performance_status === "needs_refresh").length,
    not_enough_data_count: pages.filter((p) => p.performance_status === "not_enough_data").length,
    total_clicks: totalClicks,
    total_impressions: totalImpressions,
    average_ctr: totalImpressions > 0 ? totalClicks / totalImpressions : 0,
    average_position:
      positionEligible.length > 0
        ? positionEligible.reduce((sum, p) => sum + p.avg_position, 0) / positionEligible.length
        : 0,
    data_source_status: DATA_SOURCE_STATUS_MESSAGE,
    last_updated: lastUpdated,
  });
}

// Phase 14B.2: Supabase mode reads seo_decline_diagnoses_current (live
// statuses only — open/in_review/action_planned), mapped down into the app's
// existing flat DeclineDiagnosis shape. See
// src/services/supabase/seoDeclineDiagnosisSupabaseService.ts for the mapping
// and PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md for detail. Mock mode is
// unchanged.
export async function fetchDeclineDiagnoses(websiteId: string): Promise<DeclineDiagnosis[]> {
  return runWithServiceAdapter({
    label: "performanceService.fetchDeclineDiagnoses",
    mock: () => toAsync(listDeclineDiagnoses(websiteId)),
    supabase: () => fetchSupabaseDeclineDiagnoses(websiteId),
  });
}

// Supabase mode reads the base seo_decline_diagnoses table directly (all
// statuses, not just live ones) — a page-level history read, distinct from
// fetchDeclineDiagnoses' website-level "current" read. Nothing in the
// current UI calls this yet (see wiring notes), but it is adapter-wired for
// when it is.
export async function fetchDiagnosisForPage(pageId: string): Promise<DeclineDiagnosis[]> {
  return runWithServiceAdapter({
    label: "performanceService.fetchDiagnosisForPage",
    mock: () => toAsync(listDiagnosesForPage(pageId)),
    supabase: () => fetchSupabaseDiagnosesForPage(pageId),
  });
}

export async function fetchRefreshRecommendationsForWebsite(
  websiteId: string,
): Promise<RefreshRecommendation[]> {
  return toAsync(listRefreshRecommendations(websiteId));
}

export async function fetchRefreshRecommendationForPage(
  pageId: string,
): Promise<RefreshRecommendation | null> {
  return toAsync(getRefreshRecommendationForPage(pageId));
}

export async function generateMockPerformanceRefresh(website: SeoWebsite): Promise<PagePerformance[]> {
  return toAsync(generatePerformanceDataForWebsite(website));
}
