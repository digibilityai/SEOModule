import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { SeoWebsite } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { fetchWebsiteById } from "@/services/websiteService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import {
  fetchAiContentGaps,
  fetchAiVisibilityOverview,
  fetchBrandMentionSummary,
  fetchCompetitorMentionSummary,
  fetchPromptTrackingRecords,
  generateMockAiVisibilityRefresh,
} from "@/services/aiVisibilityService";
import { findAccessibleWebsiteWithAiVisibilityData } from "@/services/supabase/seoAiVisibilitySupabaseService";
import { AI_VISIBILITY_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { AiVisibilityHeader } from "./ai-visibility/AiVisibilityHeader";
import { PromptTrackingCard } from "./ai-visibility/PromptTrackingCard";
import { BrandMentionCard } from "./ai-visibility/BrandMentionCard";
import { CompetitorMentionCard } from "./ai-visibility/CompetitorMentionCard";
import { AiContentGapCard } from "./ai-visibility/AiContentGapCard";

export function AiVisibilityPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [hasSearchedForAiVisibilityWebsite, setHasSearchedForAiVisibilityWebsite] = useState(false);
  const [aiVisibilityOverrideWebsite, setAiVisibilityOverrideWebsite] = useState<SeoWebsite | null>(null);

  // The website this page actually displays. Normally the app-wide active
  // website, but overridden (Supabase mode only, see effect below) when that
  // website has zero AI Visibility prompt-tracking rows while a DIFFERENT
  // accessible website has real seeded data. Same page-local-override
  // pattern as DeclineDiagnosisPage.tsx's displayWebsite (Phase 14B.2).
  const displayWebsite = aiVisibilityOverrideWebsite ?? activeWebsite;

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", displayWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(displayWebsite!.id),
    enabled: !!displayWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const { data: prompts = [], isLoading: isLoadingPrompts } = useQuery({
    queryKey: ["seo-ai-prompts", displayWebsite?.id],
    queryFn: () => fetchPromptTrackingRecords(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: overview } = useQuery({
    queryKey: ["seo-ai-visibility-overview", displayWebsite?.id, prompts.length],
    queryFn: () => fetchAiVisibilityOverview(displayWebsite!.id, displayWebsite!.website_url),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: brandSummary } = useQuery({
    queryKey: ["seo-ai-brand-summary", displayWebsite?.id, prompts.length],
    queryFn: () => fetchBrandMentionSummary(displayWebsite!.id, displayWebsite!.website_url),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: competitorSummaries = [] } = useQuery({
    queryKey: ["seo-ai-competitor-summary", displayWebsite?.id, prompts.length],
    queryFn: () => fetchCompetitorMentionSummary(displayWebsite!.id, displayWebsite!.website_url),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: contentGaps = [] } = useQuery({
    queryKey: ["seo-ai-content-gaps", displayWebsite?.id],
    queryFn: () => fetchAiContentGaps(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  // Supabase-mode-only safety net — mirrors AuthorityBuilderPage.tsx's
  // effect (Phase 15A) and DeclineDiagnosisPage.tsx's corrected effect
  // (Phase 14B.2 §11): searches every accessible workspace/website for one
  // with AI Visibility data when the auto-selected active website has none,
  // triggered by either incomplete onboarding or a settled zero-prompt read.
  useEffect(() => {
    if (!isSupabaseMode()) return;
    if (isLoadingWebsite || isLoadingOnboarding || hasSearchedForAiVisibilityWebsite) return;
    if (!activeWebsite) return;
    if (isOnboardingComplete && (isLoadingPrompts || prompts.length > 0)) return;

    setHasSearchedForAiVisibilityWebsite(true);
    findAccessibleWebsiteWithAiVisibilityData().then(async (found) => {
      if (!found || found.websiteId === activeWebsite.id) return;
      const website = await fetchWebsiteById(found.websiteId);
      if (website) setAiVisibilityOverrideWebsite(website);
    });
  }, [
    isLoadingWebsite,
    isLoadingOnboarding,
    isOnboardingComplete,
    isLoadingPrompts,
    hasSearchedForAiVisibilityWebsite,
    activeWebsite,
    prompts.length,
  ]);

  const generateMutation = useMutation({
    mutationFn: () => generateMockAiVisibilityRefresh(displayWebsite!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["seo-ai-prompts", displayWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-ai-visibility-overview", displayWebsite?.id] });
    },
  });

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!displayWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>
            AI Visibility tracking is tied to a website. Add a website to get started.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/websites">Add your website</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (isLoadingOnboarding) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!onboarding || !isOnboardingComplete) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Complete business onboarding first</CardTitle>
          <CardDescription>
            AI Visibility uses your business context to explain gaps in plain language.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/onboarding">Complete business onboarding</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (isLoadingPrompts) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (prompts.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No AI visibility records yet</CardTitle>
          <CardDescription>
            Generate mock AI visibility data for {displayWebsite.name} to see how this will look once
            real AI answer tracking is connected.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button onClick={() => generateMutation.mutate()} disabled={generateMutation.isPending}>
            {generateMutation.isPending ? "Generating..." : "Generate AI visibility data"}
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {overview && <AiVisibilityHeader website={displayWebsite} overview={overview} />}
      <SafetyNotice text={AI_VISIBILITY_SAFETY_NOTICE} />

      <h2 className="text-sm font-medium text-muted-foreground">AI Prompt Tracking</h2>
      <div className="space-y-3">
        {prompts.map((p) => (
          <PromptTrackingCard key={p.id} record={p} />
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {brandSummary && <BrandMentionCard summary={brandSummary} />}
        <CompetitorMentionCard summaries={competitorSummaries} />
      </div>

      <h2 className="text-sm font-medium text-muted-foreground">AI Content Gap Opportunities</h2>
      {contentGaps.length === 0 ? (
        <Card>
          <CardContent className="py-6 text-center text-sm text-muted-foreground">
            No content gaps identified yet.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {contentGaps.map((gap) => (
            <AiContentGapCard key={gap.id} gap={gap} />
          ))}
        </div>
      )}
    </div>
  );
}
