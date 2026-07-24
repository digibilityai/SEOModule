import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { getCurrentSeoRole } from "@/services/supabase/seoWorkspaceService";
import {
  canGenerateCompetitorBenchmarks,
  fetchBenchmarkComparisons,
  fetchCompetitorGaps,
  fetchCompetitorOverview,
  fetchCompetitors,
  generateCompetitorBenchmarkData,
} from "@/services/competitorService";
import { COMPETITOR_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { CompetitorOverviewHeader } from "./competitors/CompetitorOverviewHeader";
import { CompetitorGapSummary } from "./competitors/CompetitorGapSummary";
import { BenchmarkComparisonSection } from "./competitors/BenchmarkComparisonSection";
import { CompetitorCard } from "./competitors/CompetitorCard";

// Competitor Benchmarking Stage 2B — the role-gate denial reason shown when
// signed in as a role the seo_competitor_generate RPC does not permit
// (client, or no active membership). Matches the established wording used for
// the Stage 6 role-gated controls (CampaignBuilder/CampaignList/OpportunityCard).
const GENERATION_ROLE_DENIED_REASON = "Requires the owner, admin, or team member role.";

export function CompetitorAnalysisPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const supabaseMode = isSupabaseMode();

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  // The signed-in user's REAL seo_workspace_members.seo_role for this
  // website's workspace — the actual authorization source
  // seo_competitor_generate checks server-side. Supabase mode only: mock mode
  // has no seo_workspace_members rows, so role gating is skipped there
  // entirely (see canGenerateCompetitorBenchmarks) and generation stays
  // enabled, unchanged from the app's pre-existing mock behaviour.
  const { data: currentSeoRole } = useQuery({
    queryKey: ["seo-current-role", activeWebsite?.workspace_id],
    queryFn: () => getCurrentSeoRole(activeWebsite!.workspace_id),
    enabled: !!activeWebsite && supabaseMode,
  });
  const generatePermitted = canGenerateCompetitorBenchmarks(currentSeoRole ?? null, supabaseMode);

  const { data: competitors = [], isLoading: isLoadingCompetitors } = useQuery({
    queryKey: ["seo-competitors", activeWebsite?.id],
    queryFn: () => fetchCompetitors(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: overview } = useQuery({
    queryKey: ["seo-competitor-overview", activeWebsite?.id, competitors.length],
    queryFn: () => fetchCompetitorOverview(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete && competitors.length > 0,
  });

  const { data: comparisons = [] } = useQuery({
    queryKey: ["seo-benchmark-comparisons", activeWebsite?.id, competitors.length],
    queryFn: () => fetchBenchmarkComparisons(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete && competitors.length > 0,
  });

  const { data: gaps = [] } = useQuery({
    queryKey: ["seo-competitor-gaps", activeWebsite?.id, competitors.length],
    queryFn: () => fetchCompetitorGaps(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete && competitors.length > 0,
  });

  const generateMutation = useMutation({
    mutationFn: () => generateCompetitorBenchmarkData(activeWebsite!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["seo-competitors", activeWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-competitor-overview", activeWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-benchmark-comparisons", activeWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-competitor-gaps", activeWebsite?.id] });
    },
  });

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>
            Competitor benchmarking is tied to a website. Add a website to get started.
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
            Competitor benchmarking uses the competitors you listed during onboarding.
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

  if (isLoadingCompetitors) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (onboarding.competitors.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No competitors added yet</CardTitle>
          <CardDescription>
            Add a competitor URL or two in business onboarding so Digibility knows who to benchmark
            against.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/onboarding">Add competitors in onboarding</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (competitors.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No benchmark data yet</CardTitle>
          <CardDescription>
            Generate benchmark data for the competitors you listed in onboarding to see how{" "}
            {activeWebsite.name} compares.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          <Button
            onClick={() => generateMutation.mutate()}
            disabled={generateMutation.isPending || !generatePermitted}
            title={!generatePermitted ? GENERATION_ROLE_DENIED_REASON : undefined}
          >
            {generateMutation.isPending ? "Generating..." : "Generate benchmark data"}
          </Button>
          {generateMutation.isError && (
            <p className="text-sm text-destructive">
              Couldn't generate benchmark data just now. Please try again.
            </p>
          )}
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {overview && (
        <CompetitorOverviewHeader
          website={activeWebsite}
          overview={overview}
          onRefresh={() => generateMutation.mutate()}
          isRefreshing={generateMutation.isPending}
          refreshDisabled={!generatePermitted}
          refreshDisabledReason={GENERATION_ROLE_DENIED_REASON}
        />
      )}
      {generateMutation.isError && (
        <p className="text-sm text-destructive">Couldn't refresh benchmark data just now. Please try again.</p>
      )}
      <SafetyNotice text={COMPETITOR_SAFETY_NOTICE} />

      <CompetitorGapSummary gaps={gaps} />
      <BenchmarkComparisonSection comparisons={comparisons} />

      <h2 className="text-sm font-medium text-muted-foreground">Competitors</h2>
      <div className="space-y-3">
        {competitors.map((c) => (
          <CompetitorCard key={c.id} competitor={c} />
        ))}
      </div>
    </div>
  );
}
