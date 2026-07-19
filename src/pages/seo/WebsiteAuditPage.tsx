import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchAudits, fetchIssuesForAudit, runAudit } from "@/services/auditService";
import { generateRecommendationsFromAudit } from "@/services/recommendationService";
import { AuditHeader } from "./audit/AuditHeader";
import { CrawlPanel } from "./audit/crawl/CrawlPanel";
import { IssueSeveritySummary } from "./audit/IssueSeveritySummary";
import { IssueCategorySummary } from "./audit/IssueCategorySummary";
import { IssueCard } from "./audit/IssueCard";
import { SafetyNotice } from "./shared/SafetyNotice";

export function WebsiteAuditPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [justFailed, setJustFailed] = useState(false);
  const isMockAuditMode = !isSupabaseMode();

  const { data: audits = [], isLoading: isLoadingAudits } = useQuery({
    queryKey: ["seo-audits", activeWebsite?.id],
    queryFn: () => fetchAudits(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  // Lifecycle and published results are intentionally separate:
  //
  // - The CrawlPanel owns the latest crawl attempt and its queued/running/
  //   cancelled/failed state.
  // - Customer-visible audit results use the latest completed audit, so a newer
  //   cancelled or failed attempt never hides previously published findings.
  // - Mock mode preserves the original latest-attempt behaviour.
  const auditsNewestFirst = [...audits].sort(
    (a, b) =>
      new Date(b.started_at ?? b.completed_at).getTime() -
      new Date(a.started_at ?? a.completed_at).getTime(),
  );

  const latestAuditAttempt = auditsNewestFirst[0] ?? null;

  const latestCompletedAudit =
    audits
      .filter((audit) => audit.status === "completed")
      .sort(
        (a, b) =>
          new Date(b.completed_at ?? b.started_at).getTime() -
          new Date(a.completed_at ?? a.started_at).getTime(),
      )[0] ?? null;

  const resultAudit = isMockAuditMode ? latestAuditAttempt : latestCompletedAudit;

  const { data: issues = [], isLoading: isLoadingIssues } = useQuery({
    queryKey: ["seo-issues", resultAudit?.id],
    queryFn: () => fetchIssuesForAudit(resultAudit!.id),
    enabled: !!resultAudit && resultAudit.status === "completed",
  });

  const runAuditMutation = useMutation({
    mutationFn: async () => {
      if (!activeWebsite) throw new Error("No active website");
      const result = await runAudit(activeWebsite.id, activeWebsite.website_url);
      if (result.audit.status === "completed") {
        await generateRecommendationsFromAudit(activeWebsite, result.issues);
      }
      return result;
    },
    onSuccess: (result) => {
      setJustFailed(result.audit.status === "failed");
      queryClient.invalidateQueries({ queryKey: ["seo-audits", activeWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-issues"] });
      queryClient.invalidateQueries({ queryKey: ["seo-recommendations", activeWebsite?.id] });
      queryClient.invalidateQueries({ queryKey: ["seo-onpage-recommendations", activeWebsite?.id] });
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
            Technical audits are tied to a website. Add a website to run your first audit.
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

  const isRunning = isMockAuditMode && runAuditMutation.isPending;

  return (
    <div className="space-y-4">
      <AuditHeader
        website={activeWebsite}
        latestAudit={resultAudit}
        isRunning={isRunning}
        isMockMode={isMockAuditMode}
        onRunAudit={() => runAuditMutation.mutate()}
      />

      <SafetyNotice />

      <CrawlPanel websiteId={activeWebsite.id} websiteUrl={activeWebsite.website_url} />

      <div id="audit-results" />

      {isLoadingAudits && <p className="text-sm text-muted-foreground">Loading audit history...</p>}

      {!isLoadingAudits && !isRunning && !resultAudit && (
        <Card>
          <CardContent className="space-y-3 py-8 text-center">
            <p className="text-sm text-muted-foreground">
              {isMockAuditMode
                ? "No audit yet. Run your first audit to see technical health, issues and recommendations."
                : "No published audit results yet. Start a website crawl to generate technical findings."}
            </p>
          </CardContent>
        </Card>
      )}

      {isMockAuditMode &&
        !isRunning &&
        justFailed &&
        latestAuditAttempt?.status === "failed" && (
          <Card>
            <CardContent className="space-y-3 py-6 text-center">
              <p className="text-sm text-muted-foreground">
                The last audit run didn't complete. This can happen occasionally during local testing —
                try running it again.
              </p>
              <Button onClick={() => runAuditMutation.mutate()}>Retry audit</Button>
            </CardContent>
          </Card>
        )}

      {!isRunning && resultAudit?.status === "completed" && (
        <>
          <div className="grid gap-4 md:grid-cols-2">
            <IssueSeveritySummary issues={issues} />
            <IssueCategorySummary issues={issues} />
          </div>

          {isLoadingIssues ? (
            <p className="text-sm text-muted-foreground">Loading issues...</p>
          ) : (
            <div className="space-y-3">
              {issues.map((issue) => (
                <IssueCard key={issue.id} issue={issue} />
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
