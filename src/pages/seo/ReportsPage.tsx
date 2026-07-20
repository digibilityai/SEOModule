import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { ReportPeriodKey } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import {
  fetchReportForPeriod,
  fetchReportSections,
  generateProgressReport,
} from "@/services/reportService";
import { REPORTS_SAFETY_NOTICE } from "@/lib/safetyRules";
import { HELP_ROUTES } from "@/help/routes";
import { SafetyNotice } from "./shared/SafetyNotice";
import { ReportPeriodSelector } from "./reports/ReportPeriodSelector";
import { ReportHeader } from "./reports/ReportHeader";
import { ReportKeyStats } from "./reports/ReportKeyStats";
import { ReportSectionCard } from "./reports/ReportSectionCard";
import { ReportExportActions } from "./reports/ReportExportActions";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

export function ReportsPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [period, setPeriod] = useState<ReportPeriodKey>("last_month");

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const {
    data: report,
    isLoading: isLoadingReport,
    isError: isReportError,
    refetch: refetchReport,
    isFetching: isRefetchingReport,
  } = useQuery({
    queryKey: ["seo-report", activeWebsite?.id, period],
    queryFn: () => fetchReportForPeriod(activeWebsite!.id, period),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: sections = [] } = useQuery({
    queryKey: ["seo-report-sections", report?.id, report?.updated_at],
    queryFn: () => fetchReportSections(report!),
    enabled: !!report,
  });

  const generateMutation = useMutation({
    mutationFn: () => generateProgressReport(activeWebsite!, period),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["seo-report", activeWebsite?.id, period] });
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
          <CardDescription>Progress reports are tied to a website. Add a website to get started.</CardDescription>
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
          <CardDescription>Reports summarize progress using your business context.</CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/onboarding">Complete business onboarding</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Progress Reports</CardTitle>
          <CardDescription>
            Here is what improved, what was done, what is pending, and what happens next.
          </CardDescription>
          <Link to={HELP_ROUTES.DIGIBILITY_OPERATING_MODEL} className={HELP_LINK_CLASSNAME}>
            How this report is put together
          </Link>
        </CardHeader>
        <CardContent>
          <ReportPeriodSelector active={period} onChange={setPeriod} />
        </CardContent>
      </Card>

      {isLoadingReport && <p className="text-sm text-muted-foreground">Loading...</p>}

      {!isLoadingReport && isReportError && (
        <Card>
          <CardHeader>
            <CardTitle>Couldn't load this report</CardTitle>
            <CardDescription>
              Something went wrong fetching the report for {activeWebsite.name}. Please try again.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button variant="outline" onClick={() => refetchReport()} disabled={isRefetchingReport}>
              {isRefetchingReport ? "Retrying..." : "Retry"}
            </Button>
          </CardContent>
        </Card>
      )}

      {!isLoadingReport && !isReportError && !report && (
        <Card>
          <CardHeader>
            <CardTitle>No report yet for this period</CardTitle>
            <CardDescription>
              Generate a report for {activeWebsite.name} using your current audit, content, performance,
              off-page and AI visibility data.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            <Button onClick={() => generateMutation.mutate()} disabled={generateMutation.isPending}>
              {generateMutation.isPending ? "Generating..." : "Generate / Refresh Report"}
            </Button>
            {generateMutation.isError && (
              <p className="text-sm text-destructive">
                Couldn't generate the report just now. Please try again.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {report && (
        <>
          <ReportHeader
            website={activeWebsite}
            report={report}
            onGenerate={() => generateMutation.mutate()}
            isGenerating={generateMutation.isPending}
          />
          {generateMutation.isError && (
            <p className="text-sm text-destructive">Couldn't refresh the report just now. Please try again.</p>
          )}
          <SafetyNotice text={REPORTS_SAFETY_NOTICE} />
          <ReportKeyStats report={report} />

          <div className="grid gap-4 sm:grid-cols-2">
            {sections.map((section) => (
              <ReportSectionCard key={section.key} section={section} />
            ))}
          </div>

          <ReportExportActions website={activeWebsite} period={period} />
        </>
      )}
    </div>
  );
}
