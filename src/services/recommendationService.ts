import type { SeoIssue, SeoRecommendation, SeoWebsite } from "@/types";
import { toAsync } from "@/lib/mockAsync";
import {
  listRecommendations,
  getRecommendationById,
  listOnPageRecommendations,
  regenerateRecommendationsForWebsite,
} from "@/mocks/recommendationMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  fetchSupabaseOnPageRecommendations,
  fetchSupabaseRecommendationById,
  fetchSupabaseRecommendations,
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

// Stays mock-only in every data mode, by design — Stage 2 recommendations
// are system/service-role generated (no crawler/LLM yet, and RLS excludes
// clients from writing seo_recommendations directly). In practice this is
// never reached in Supabase mode anyway: its only caller (WebsiteAuditPage)
// gates it behind `audit.status === "completed"`, and the Supabase
// `runAudit()` path in auditService.ts always returns "running".
export async function generateRecommendationsFromAudit(
  website: SeoWebsite,
  issues: SeoIssue[],
): Promise<SeoRecommendation[]> {
  return toAsync(regenerateRecommendationsForWebsite(website, issues));
}
