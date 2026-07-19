import type {
  BusinessOnboarding,
  ContentTone,
  MainSeoGoal,
  NewBusinessOnboardingInput,
  OnboardingStatus,
  SensitiveIndustry,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import {
  getCurrentUserId,
  requireAuthenticatedUser,
  requireValidUuid,
  safeSingle,
} from "@/services/supabase/supabaseServiceUtils";
import { getOrCreateDefaultSeoWorkspace } from "@/services/supabase/seoWorkspaceService";

// Row shape as stored (Stage 1 migration 3, seo_business_onboarding). Several
// text columns are nullable in the DB even though the app form always
// supplies a value on save — mapped defensively on read below.
interface SeoBusinessOnboardingRow {
  id: string;
  website_id: string;
  website_url: string;
  workspace_id: string;
  services_products: string | null;
  target_audience: string | null;
  main_seo_goal: string | null;
  target_locations: string[] | null;
  competitors: string[] | null;
  proof_trust_signals: string | null;
  important_pages: string[] | null;
  preferred_content_tone: string | null;
  sensitive_industry: string;
  notes: string | null;
  onboarding_status: OnboardingStatus;
  completion_percentage: number;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

function mapToBusinessOnboarding(
  row: SeoBusinessOnboardingRow,
  fallbackUserId: string | null,
): BusinessOnboarding {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? fallbackUserId ?? "",
    created_by: row.created_by ?? fallbackUserId ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    services_products: row.services_products ?? "",
    target_audience: row.target_audience ?? "",
    main_seo_goal: (row.main_seo_goal as MainSeoGoal | null) ?? "other",
    target_locations: row.target_locations ?? [],
    competitors: row.competitors ?? [],
    proof_trust_signals: row.proof_trust_signals ?? undefined,
    important_pages: row.important_pages ?? [],
    preferred_content_tone: (row.preferred_content_tone as ContentTone | null) ?? "other",
    sensitive_industry: (row.sensitive_industry as SensitiveIndustry) ?? "none",
    notes: row.notes ?? undefined,
    status: row.onboarding_status,
    completion_percentage: row.completion_percentage,
  };
}

/** Loads the 1:1 onboarding record for a website, or null if none exists yet. */
export async function fetchSupabaseOnboardingByWebsiteId(
  websiteId: string,
): Promise<BusinessOnboarding | null> {
  await requireAuthenticatedUser("seoBusinessOnboardingSupabaseService.fetchSupabaseOnboardingByWebsiteId");
  requireValidUuid(
    "seoBusinessOnboardingSupabaseService.fetchSupabaseOnboardingByWebsiteId",
    websiteId,
    "websiteId",
  );

  const row = await safeSingle<SeoBusinessOnboardingRow>(
    "seoBusinessOnboardingSupabaseService.fetchSupabaseOnboardingByWebsiteId",
    supabase
      .from(SEO_TABLES.businessOnboarding)
      .select("*")
      .eq("website_id", websiteId)
      .maybeSingle(),
  );
  if (!row) return null;
  return mapToBusinessOnboarding(row, await getCurrentUserId());
}

/**
 * Creates or updates the 1:1 onboarding record for a website (matches the
 * mock adapter's upsert-by-website_id behavior). No external scraping, no
 * LLM calls, no competitor enrichment — this only persists exactly what the
 * onboarding form submits.
 */
export async function saveSupabaseOnboarding(
  input: NewBusinessOnboardingInput,
): Promise<BusinessOnboarding> {
  await requireAuthenticatedUser("seoBusinessOnboardingSupabaseService.saveSupabaseOnboarding");
  requireValidUuid(
    "seoBusinessOnboardingSupabaseService.saveSupabaseOnboarding",
    input.website_id,
    "website_id",
  );

  const { workspace, reason } = await getOrCreateDefaultSeoWorkspace();
  if (!workspace) {
    throw new Error(reason ?? "No SEO workspace available for this Supabase user.");
  }

  const userId = await getCurrentUserId();

  const existing = await safeSingle<{ id: string }>(
    "seoBusinessOnboardingSupabaseService.saveSupabaseOnboarding (lookup)",
    supabase
      .from(SEO_TABLES.businessOnboarding)
      .select("id")
      .eq("website_id", input.website_id)
      .maybeSingle(),
  );

  const payload = {
    website_id: input.website_id,
    website_url: input.website_url,
    workspace_id: workspace.id,
    services_products: input.services_products || null,
    target_audience: input.target_audience || null,
    main_seo_goal: input.main_seo_goal,
    target_locations: input.target_locations,
    competitors: input.competitors,
    proof_trust_signals: input.proof_trust_signals || null,
    important_pages: input.important_pages,
    preferred_content_tone: input.preferred_content_tone,
    sensitive_industry: input.sensitive_industry,
    notes: input.notes || null,
    onboarding_status: input.status,
    completion_percentage: input.completion_percentage,
  };

  // Preserve the original created_by on update rather than a blanket upsert,
  // which would otherwise overwrite it with the current editor every save.
  const row = existing
    ? await safeSingle<SeoBusinessOnboardingRow>(
        "seoBusinessOnboardingSupabaseService.saveSupabaseOnboarding (update)",
        supabase
          .from(SEO_TABLES.businessOnboarding)
          .update(payload)
          .eq("id", existing.id)
          .select("*")
          .single(),
      )
    : await safeSingle<SeoBusinessOnboardingRow>(
        "seoBusinessOnboardingSupabaseService.saveSupabaseOnboarding (insert)",
        supabase
          .from(SEO_TABLES.businessOnboarding)
          .insert({ ...payload, created_by: userId })
          .select("*")
          .single(),
      );

  if (!row) {
    throw new Error("seoBusinessOnboardingSupabaseService.saveSupabaseOnboarding: no row returned.");
  }

  return mapToBusinessOnboarding(row, userId);
}
