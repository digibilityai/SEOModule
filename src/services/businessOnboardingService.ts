import type {
  BusinessOnboarding,
  ContentTone,
  MainSeoGoal,
  NewBusinessOnboardingInput,
  OnboardingStatus,
  SensitiveIndustry,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { getOnboardingByWebsiteId, upsertOnboarding } from "@/mocks/businessOnboardingMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  fetchSupabaseOnboardingByWebsiteId,
  saveSupabaseOnboarding,
} from "@/services/supabase/seoBusinessOnboardingSupabaseService";

export async function fetchOnboardingByWebsiteId(
  websiteId: string,
): Promise<BusinessOnboarding | null> {
  return runWithServiceAdapter({
    label: "businessOnboardingService.fetchOnboardingByWebsiteId",
    mock: () => toAsync(getOnboardingByWebsiteId(websiteId)),
    supabase: () => fetchSupabaseOnboardingByWebsiteId(websiteId),
  });
}

export async function saveOnboarding(
  input: NewBusinessOnboardingInput,
): Promise<BusinessOnboarding> {
  return runWithServiceAdapter({
    label: "businessOnboardingService.saveOnboarding",
    mock: () => toAsync(upsertOnboarding(input)),
    supabase: () => saveSupabaseOnboarding(input),
  });
}

// Only fields every business can realistically always provide count toward
// completion. target_locations, competitors, important_pages, proof_trust_signals
// and notes are useful context but shouldn't block onboarding from completing.
//
// The three select fields start on an empty placeholder ("Select...") rather
// than a real enum value, so a user must actively choose something before it
// counts — an untouched placeholder must not read as "filled".
export interface RequiredOnboardingFields {
  services_products: string;
  target_audience: string;
  main_seo_goal: MainSeoGoal | "";
  preferred_content_tone: ContentTone | "";
  sensitive_industry: SensitiveIndustry | "";
}

export function calculateCompletionPercentage(fields: RequiredOnboardingFields): number {
  const checks = [
    !!fields.services_products?.trim(),
    !!fields.target_audience?.trim(),
    !!fields.main_seo_goal,
    !!fields.preferred_content_tone,
    !!fields.sensitive_industry,
  ];
  const completed = checks.filter(Boolean).length;
  return Math.round((completed / checks.length) * 100);
}

export function resolveOnboardingStatus(completionPercentage: number): OnboardingStatus {
  if (completionPercentage >= 100) return "completed";
  if (completionPercentage > 0) return "in_progress";
  return "not_started";
}
