import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { PagePerformanceFilterKey, SeoWebsite } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { fetchWebsiteById } from "@/services/websiteService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { fetchLatestAudit, fetchIssuesForAudit } from "@/services/auditService";
import { fetchRecommendations } from "@/services/recommendationService";
import {
  fetchPagePerformance,
  fetchPerformanceSummary,
  generateMockPerformanceRefresh,
} from "@/services/performanceService";
import { findAccessibleWebsiteWithPerformanceData } from "@/services/supabase/seoPagePerformanceSupabaseService";
import { filterPagesByStatus, searchPages } from "@/lib/pagePerformanceFilters";
import { PERFORMANCE_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { PerformanceHeader } from "./performance/PerformanceHeader";
import { PerformanceSummaryCards } from "./performance/PerformanceSummaryCards";
import { PerformanceFiltersBar } from "./performance/PerformanceFiltersBar";
import { PagePerformanceCard } from "./performance/PagePerformanceCard";

export function PagePerformancePage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [filter, setFilter] = useState<PagePerformanceFilterKey>("all");
  const [search, setSearch] = useState("");
  const [hasSearchedForPerformanceWebsite, setHasSearchedForPerformanceWebsite] = useState(false);
  const [performanceOverrideWebsite, setPerformanceOverrideWebsite] = useState<SeoWebsite | null>(null);

  // The website this page actually displays. Normally the app-wide active
  // website, but overridden (Supabase mode only, see effect below) when that
  // website has zero performance rows while a DIFFERENT accessible website —
  // possibly in another workspace entirely — has real seeded data.
  // useResolvedActiveWebsite's own website list only ever covers a single
  // resolved workspace (see fetchSupabaseWebsites), so it can't represent a
  // cross-workspace switch; calling its setActiveWebsiteId with a foreign
  // website id would just get reverted on the next render. Keeping a
  // page-local override avoids touching that shared hook.
  const displayWebsite = performanceOverrideWebsite ?? activeWebsite;

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", displayWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(displayWebsite!.id),
    enabled: !!displayWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const {
    data: pages = [],
    isLoading: isLoadingPages,
    isFetched: hasFetchedPages,
  } = useQuery({
    queryKey: ["seo-page-performance", displayWebsite?.id],
    queryFn: () => fetchPagePerformance(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  // Supabase-mode-only safety net: the auto-selected active website can
  // legitimately have zero Stage 4 rows while a DIFFERENT website — possibly
  // in an entirely different accessible workspace, e.g. a disposable smoke
  // test workspace vs. the intended seeded one — has real data. Search every
  // workspace/website the current user can access instead of showing an
  // empty state for what's likely just the wrong website. Runs at most once
  // per page mount; never touches mock mode, where a website with zero pages
  // can be an intentional empty-state demo.
  useEffect(() => {
    if (!isSupabaseMode()) return;
    if (
      isLoadingWebsite ||
      isLoadingOnboarding ||
      !isOnboardingComplete ||
      isLoadingPages ||
      !hasFetchedPages ||
      hasSearchedForPerformanceWebsite
    ) {
      return;
    }
    if (!activeWebsite || pages.length > 0) return;

    setHasSearchedForPerformanceWebsite(true);
    findAccessibleWebsiteWithPerformanceData().then(async (found) => {
      if (!found || found.websiteId === activeWebsite.id) return;
      const website = await fetchWebsiteById(found.websiteId);
      if (website) setPerformanceOverrideWebsite(website);
    });
  }, [
    isLoadingWebsite,
    isLoadingOnboarding,
    isOnboardingComplete,
    isLoadingPages,
    hasFetchedPages,
    hasSearchedForPerformanceWebsite,
    activeWebsite,
    pages.length,
  ]);

  const { data: summary } = useQuery({
    queryKey: ["seo-performance-summary", displayWebsite?.id, pages.length],
    queryFn: () => fetchPerformanceSummary(displayWebsite!.id, displayWebsite!.website_url),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: latestAudit } = useQuery({
    queryKey: ["seo-audits-latest", displayWebsite?.id],
    queryFn: () => fetchLatestAudit(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: issues = [] } = useQuery({
    queryKey: ["seo-issues", latestAudit?.id],
    queryFn: () => fetchIssuesForAudit(latestAudit!.id),
    enabled: !!latestAudit && latestAudit.status === "completed",
  });

  const { data: recommendations = [] } = useQuery({
    queryKey: ["seo-recommendations", displayWebsite?.id],
    queryFn: () => fetchRecommendations(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const generateMutation = useMutation({
    mutationFn: () => generateMockPerformanceRefresh(displayWebsite!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["seo-page-performance", displayWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-performance-summary", displayWebsite?.id] });
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
            Page performance tracking is tied to a website. Add a website to get started.
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
            Page performance tracking uses your business context to explain what matters most.
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

  if (isLoadingPages) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (pages.length === 0) {
    // "Generate performance data" writes to local mock storage only — never
    // show it as the primary action in Supabase mode, where it wouldn't
    // create anything in Supabase and would be misleading. Real Stage 4
    // data is seeded/imported separately (see
    // SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md). By this
    // point the cross-workspace search above has already run (or doesn't
    // apply in mock mode), so this is a genuine "nothing found anywhere
    // accessible" empty state, not just the wrong website.
    const supabaseMode = isSupabaseMode();
    return (
      <Card>
        <CardHeader>
          <CardTitle>No performance data yet</CardTitle>
          <CardDescription>
            {supabaseMode
              ? `No tracked pages found for ${displayWebsite.name}, and no other accessible website has Page Performance data yet. Page performance data is seeded or imported separately — check back once pages and keywords have been added.`
              : `Generate mock page performance data for ${displayWebsite.name} to see how this will look once real GSC/GA4/rank tracking data is connected.`}
          </CardDescription>
        </CardHeader>
        {!supabaseMode && (
          <CardContent>
            <Button onClick={() => generateMutation.mutate()} disabled={generateMutation.isPending}>
              {generateMutation.isPending ? "Generating..." : "Generate performance data"}
            </Button>
          </CardContent>
        )}
      </Card>
    );
  }

  const filteredPages = searchPages(filterPagesByStatus(pages, filter), search);

  return (
    <div className="space-y-4">
      {summary && <PerformanceHeader website={displayWebsite} summary={summary} />}
      <SafetyNotice text={PERFORMANCE_SAFETY_NOTICE} />
      {summary && <PerformanceSummaryCards summary={summary} />}

      <PerformanceFiltersBar active={filter} onChange={setFilter} search={search} onSearchChange={setSearch} />

      {filteredPages.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            No pages match this filter.
          </CardContent>
        </Card>
      )}

      <div className="space-y-3">
        {filteredPages.map((page) => {
          const relatedIssue = issues.find((i) => i.affected_page_url === page.page_url);
          const relatedRecommendation = recommendations.find(
            (r) => relatedIssue && r.issue_id === relatedIssue.id,
          );
          return (
            <PagePerformanceCard
              key={page.id}
              page={page}
              relatedIssueTitle={relatedIssue?.title}
              relatedRecommendationTitle={relatedRecommendation?.title}
            />
          );
        })}
      </div>
    </div>
  );
}
