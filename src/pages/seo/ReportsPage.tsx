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
import { SafetyNotice } from "./shared/SafetyNotice";
import { ReportPeriodSelector } from "./reports/ReportPeriodSelector";
import { ReportHeader } from "./reports/ReportHeader";
import { ReportKeyStats } from "./reports/ReportKeyStats";
import { ReportSectionCard } from "./reports/ReportSectionCard";
import { ReportExportActions } from "./reports/ReportExportActions";

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

  const { data: report, isLoading: isLoadingReport } = useQuery({
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
        </CardHeader>
        <CardContent>
          <ReportPeriodSelector active={period} onChange={setPeriod} />
        </CardContent>
      </Card>

      {isLoadingReport && <p className="text-sm text-muted-foreground">Loading...</p>}

      {!isLoadingReport && !report && (
        <Card>
          <CardHeader>
            <CardTitle>No report yet for this period</CardTitle>
            <CardDescription>
              Generate a report for {activeWebsite.name} using your current audit, content, performance,
              off-page, AI visibility, competitor, roadmap and support data.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button onClick={() => generateMutation.mutate()} disabled={generateMutation.isPending}>
              {generateMutation.isPending ? "Generating..." : "Generate / Refresh Report"}
            </Button>
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
          <SafetyNotice text={REPORTS_SAFETY_NOTICE} />
          <ReportKeyStats report={report} />

          <div className="grid gap-4 sm:grid-cols-2">
            {sections.map((section) => (
              <ReportSectionCard key={section.key} section={section} />
            ))}
          </div>

          <ReportExportActions />
        </>
      )}
    </div>
  );
}
