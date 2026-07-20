import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { fetchAudits } from "@/services/auditService";
import {
  buildSetupChecklist,
  buildVisibilityScoreCards,
  fetchPendingApprovalsSummary,
  fetchRecentActivity,
  fetchTopPriorityFixes,
  resolveRecommendedNextStep,
} from "@/services/dashboardService";
import { fetchPerformanceSummary } from "@/services/performanceService";
import { fetchAuthorityOverview } from "@/services/offPageService";
import { fetchAiVisibilityOverview } from "@/services/aiVisibilityService";
import { fetchCompetitorGaps } from "@/services/competitorService";
import { fetchRoadmapSummary } from "@/services/roadmapService";
import { fetchSupportSummary } from "@/services/supportService";
import { fetchLatestProgressReport } from "@/services/reportService";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { HELP_ROUTES } from "@/help/routes";
import { DashboardHeader } from "./dashboard/DashboardHeader";
import { RecommendedNextStepCard } from "./dashboard/RecommendedNextStepCard";
import { VisibilityScoreCards } from "./dashboard/VisibilityScoreCards";
import { TopPriorityFixes } from "./dashboard/TopPriorityFixes";
import { PendingApprovalsCard } from "./dashboard/PendingApprovalsCard";
import { RecentActivityList } from "./dashboard/RecentActivityList";
import { SetupChecklistCard } from "./dashboard/SetupChecklistCard";
import { PagePerformanceSummaryCard } from "./dashboard/PagePerformanceSummaryCard";
import { AuthorityAiVisibilitySummaryCard } from "./dashboard/AuthorityAiVisibilitySummaryCard";
import { CompetitorRoadmapSummaryCard } from "./dashboard/CompetitorRoadmapSummaryCard";
import { SupportReportsSummaryCard } from "./dashboard/SupportReportsSummaryCard";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

export function SeoDashboardPage() {
  const { websites, activeWebsite, isLoading: isLoadingWebsites } = useResolvedActiveWebsite();

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  const isOnboardingComplete = onboarding?.status === "completed";

  const { data: audits = [] } = useQuery({
    queryKey: ["seo-audits", activeWebsite?.id],
    queryFn: () => fetchAudits(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: fixes = [] } = useQuery({
    queryKey: ["seo-priority-fixes", activeWebsite?.id],
    queryFn: () => fetchTopPriorityFixes(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: approvalsSummary } = useQuery({
    queryKey: ["seo-approvals-summary", activeWebsite?.id],
    queryFn: () => fetchPendingApprovalsSummary(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: activity = [] } = useQuery({
    queryKey: ["seo-recent-activity", activeWebsite?.id],
    queryFn: () => fetchRecentActivity(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: performanceSummary } = useQuery({
    queryKey: ["seo-performance-summary", activeWebsite?.id],
    queryFn: () => fetchPerformanceSummary(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: authorityOverview } = useQuery({
    queryKey: ["seo-authority-overview", activeWebsite?.id],
    queryFn: () => fetchAuthorityOverview(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: aiVisibilityOverview } = useQuery({
    queryKey: ["seo-ai-visibility-overview", activeWebsite?.id],
    queryFn: () => fetchAiVisibilityOverview(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: competitorGaps = [] } = useQuery({
    queryKey: ["seo-competitor-gaps", activeWebsite?.id],
    queryFn: () => fetchCompetitorGaps(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: roadmapSummary } = useQuery({
    queryKey: ["seo-roadmap-summary", activeWebsite?.id],
    queryFn: () => fetchRoadmapSummary(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: supportSummary } = useQuery({
    queryKey: ["seo-support-summary", activeWebsite?.id],
    queryFn: () => fetchSupportSummary(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: latestReport } = useQuery({
    queryKey: ["seo-latest-report", activeWebsite?.id],
    queryFn: () => fetchLatestProgressReport(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  if (isLoadingWebsites) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (websites.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Welcome to Digibility SEO Intelligence</CardTitle>
          <CardDescription>Add your website to start SEO setup.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <Button asChild>
            <Link to="/seo/websites">Add your website</Link>
          </Button>
          <div>
            <Link to={HELP_ROUTES.GETTING_STARTED} className={HELP_LINK_CLASSNAME}>
              New here? Read the getting-started guide
            </Link>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (isLoadingOnboarding) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite || !isOnboardingComplete) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Almost there</CardTitle>
          <CardDescription>
            Complete business onboarding for {activeWebsite?.business_name} so SEO
            recommendations aren't generic.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {onboarding && (
            <p className="text-sm text-muted-foreground">
              {onboarding.completion_percentage}% complete
            </p>
          )}
          <Button asChild>
            <Link to="/seo/onboarding">Complete business onboarding</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  const latestAudit =
    [...audits]
      .filter((a) => a.status === "completed")
      .sort(
        (a, b) =>
          new Date(b.completed_at ?? b.started_at).getTime() -
          new Date(a.completed_at ?? a.started_at).getTime(),
      )[0] ?? null;

  const scoreCards = latestAudit ? buildVisibilityScoreCards(latestAudit) : [];
  const checklist = buildSetupChecklist(activeWebsite, isOnboardingComplete);
  const nextStep = resolveRecommendedNextStep({
    hasWebsite: true,
    isOnboardingComplete,
    hasCompletedAudit: !!latestAudit,
    hasPriorityFixes: fixes.length > 0,
  });

  return (
    <div className="space-y-6">
      <DashboardHeader website={activeWebsite} onboarding={onboarding ?? null} latestAudit={latestAudit} />
      <RecommendedNextStepCard step={nextStep} />
      <VisibilityScoreCards cards={scoreCards} />

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <TopPriorityFixes fixes={fixes} />
          <RecentActivityList items={activity} />
        </div>
        <div className="space-y-4">
          {approvalsSummary && <PendingApprovalsCard summary={approvalsSummary} />}
          {performanceSummary && performanceSummary.tracked_pages_count > 0 && (
            <PagePerformanceSummaryCard summary={performanceSummary} />
          )}
          {((authorityOverview?.opportunity_count ?? 0) > 0 ||
            (aiVisibilityOverview?.content_gap_count ?? 0) + (aiVisibilityOverview?.citation_gap_count ?? 0) >
              0) && (
            <AuthorityAiVisibilitySummaryCard
              authorityOverview={authorityOverview}
              aiVisibilityOverview={aiVisibilityOverview}
            />
          )}
          {(competitorGaps.length > 0 || (roadmapSummary?.total_actions ?? 0) > 0) && (
            <CompetitorRoadmapSummaryCard
              competitorGapCount={competitorGaps.length}
              roadmapSummary={roadmapSummary}
            />
          )}
          {((supportSummary?.open_requests_count ?? 0) > 0 || !!latestReport) && (
            <SupportReportsSummaryCard supportSummary={supportSummary} latestReport={latestReport} />
          )}
          <SetupChecklistCard items={checklist} />
        </div>
      </div>
    </div>
  );
}
