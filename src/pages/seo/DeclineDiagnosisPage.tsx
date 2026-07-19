import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import type { SeoWebsite } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { fetchWebsiteById } from "@/services/websiteService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import {
  fetchDeclineDiagnoses,
  fetchPagePerformance,
  fetchRefreshRecommendationsForWebsite,
} from "@/services/performanceService";
import { findAccessibleWebsiteWithDeclineDiagnosisData } from "@/services/supabase/seoDeclineDiagnosisSupabaseService";
import { DECLINE_DIAGNOSIS_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { DiagnosisCard } from "./decline-diagnosis/DiagnosisCard";
import { RefreshRecommendationCard } from "./decline-diagnosis/RefreshRecommendationCard";

export function DeclineDiagnosisPage() {
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [searchParams] = useSearchParams();
  const pageIdFilter = searchParams.get("pageId");
  const [hasSearchedForDiagnosisWebsite, setHasSearchedForDiagnosisWebsite] = useState(false);
  const [diagnosisOverrideWebsite, setDiagnosisOverrideWebsite] = useState<SeoWebsite | null>(null);

  // The website this page actually displays. Normally the app-wide active
  // website, but overridden (Supabase mode only, see effect below) when that
  // website has zero live decline diagnoses while a DIFFERENT accessible
  // website — possibly in another workspace entirely — has real seeded data.
  // Same page-local-override pattern as PagePerformancePage's
  // performanceOverrideWebsite — useResolvedActiveWebsite's own website list
  // only covers a single resolved workspace, so it can't represent a
  // cross-workspace switch (see PagePerformancePage.tsx for the full
  // rationale).
  const displayWebsite = diagnosisOverrideWebsite ?? activeWebsite;

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", displayWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(displayWebsite!.id),
    enabled: !!displayWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const { data: pages = [], isLoading: isLoadingPages } = useQuery({
    queryKey: ["seo-page-performance", displayWebsite?.id],
    queryFn: () => fetchPagePerformance(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: diagnoses = [], isLoading: isLoadingDiagnoses } = useQuery({
    queryKey: ["seo-decline-diagnoses", displayWebsite?.id],
    queryFn: () => fetchDeclineDiagnoses(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  // Supabase-mode-only safety net: the auto-selected active website can
  // legitimately have zero live decline diagnoses while a DIFFERENT website —
  // possibly in an entirely different accessible workspace, e.g. a disposable
  // smoke test workspace vs. the intended seeded one — has real data. Search
  // every workspace/website the current user can access instead of showing an
  // empty state (or an onboarding-incomplete block) for what's likely just
  // the wrong website. Runs at most once per page mount; never touches mock
  // mode, where a website with zero diagnoses can be an intentional
  // empty-state demo.
  //
  // Trigger conditions (either is enough to search): the auto-selected
  // website's onboarding is incomplete — a disposable smoke-test website
  // typically never gets onboarded, so its own diagnoses query never even
  // runs, and there is nothing further to wait for — OR onboarding is
  // complete but there are zero live diagnoses once that query has settled.
  // An earlier version of this effect required onboarding to already be
  // COMPLETE before searching at all, which meant it could never fire for
  // exactly the common case that needs it (the wrong, never-onboarded
  // website) — this is the fix for that.
  useEffect(() => {
    if (!isSupabaseMode()) return;
    if (isLoadingWebsite || isLoadingOnboarding || hasSearchedForDiagnosisWebsite) return;
    if (!activeWebsite) return;
    if (isOnboardingComplete && (isLoadingDiagnoses || diagnoses.length > 0)) return;

    setHasSearchedForDiagnosisWebsite(true);
    findAccessibleWebsiteWithDeclineDiagnosisData().then(async (found) => {
      if (!found || found.websiteId === activeWebsite.id) return;
      const website = await fetchWebsiteById(found.websiteId);
      if (website) setDiagnosisOverrideWebsite(website);
    });
  }, [
    isLoadingWebsite,
    isLoadingOnboarding,
    isOnboardingComplete,
    isLoadingDiagnoses,
    hasSearchedForDiagnosisWebsite,
    activeWebsite,
    diagnoses.length,
  ]);

  const { data: refreshRecommendations = [] } = useQuery({
    queryKey: ["seo-refresh-recommendations", displayWebsite?.id],
    queryFn: () => fetchRefreshRecommendationsForWebsite(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
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
            Decline diagnosis is tied to a website. Add a website to get started.
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
            Decline diagnosis uses your business context to explain issues in plain language.
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

  if (isLoadingPages || isLoadingDiagnoses) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (pages.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No page performance data yet</CardTitle>
          <CardDescription>
            Diagnosis is generated from your page performance data. Set that up first.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/page-performance">Go to Page Performance Tracker</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  const filteredDiagnoses = pageIdFilter
    ? diagnoses.filter((d) => d.page_performance_id === pageIdFilter)
    : diagnoses;

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <CardTitle>Decline Diagnosis</CardTitle>
              <CardDescription>
                Likely reasons behind declining or aging pages on {displayWebsite.name}, and what to do
                next.
              </CardDescription>
            </div>
            {pageIdFilter && (
              <Button asChild variant="outline" size="sm">
                <Link to="/seo/decline-diagnosis">View all diagnoses</Link>
              </Button>
            )}
          </div>
        </CardHeader>
      </Card>

      <SafetyNotice text={DECLINE_DIAGNOSIS_SAFETY_NOTICE} />

      {pageIdFilter && filteredDiagnoses.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            No diagnosis available for this page yet.{" "}
            <Link to="/seo/decline-diagnosis" className="underline">
              View all diagnoses
            </Link>
            .
          </CardContent>
        </Card>
      )}

      {!pageIdFilter && diagnoses.length === 0 && (
        <Card>
          <CardContent className="space-y-2 py-8 text-center">
            <p className="text-sm font-medium text-foreground">Nothing needs diagnosis right now</p>
            <p className="text-sm text-muted-foreground">
              No declining or aging pages were found. Check back after your next performance update.
            </p>
          </CardContent>
        </Card>
      )}

      <div className="space-y-4">
        {filteredDiagnoses.map((diagnosis) => {
          const page = pages.find((p) => p.id === diagnosis.page_performance_id);
          const refreshRecommendation = refreshRecommendations.find(
            (r) => r.page_performance_id === diagnosis.page_performance_id,
          );
          return (
            <div key={diagnosis.id} className="space-y-2">
              <DiagnosisCard diagnosis={diagnosis} pageTitle={page?.page_title} />
              {refreshRecommendation && <RefreshRecommendationCard recommendation={refreshRecommendation} />}
            </div>
          );
        })}
      </div>
    </div>
  );
}
