import type { ProgressReport, ReportPeriodKey, ReportSection, SeoWebsite } from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { fetchAudits } from "@/services/auditService";
import { fetchApprovalQueue } from "@/services/approvalService";
import { fetchContentOpportunities } from "@/services/contentStudioService";
import { fetchPagePerformance } from "@/services/performanceService";
import { fetchAuthorityOpportunities } from "@/services/offPageService";
import { fetchAiContentGaps } from "@/services/aiVisibilityService";
import { fetchCompetitorGaps } from "@/services/competitorService";
import { fetchRoadmapItems } from "@/services/roadmapService";
import { fetchSupportRequests } from "@/services/supportService";
import { getLatestReport, listReports, upsertReport } from "@/mocks/reportMockData";

export async function fetchProgressReports(websiteId: string): Promise<ProgressReport[]> {
  return toAsync(listReports(websiteId));
}

export async function fetchLatestProgressReport(websiteId: string): Promise<ProgressReport | null> {
  return toAsync(getLatestReport(websiteId));
}

export async function fetchReportForPeriod(
  websiteId: string,
  periodKey: ReportPeriodKey,
): Promise<ProgressReport | null> {
  const reports = await fetchProgressReports(websiteId);
  return reports.find((r) => r.period_key === periodKey) ?? null;
}

function periodRange(periodKey: ReportPeriodKey): { start: Date; end: Date; label: string } {
  const now = new Date();
  const startOfMonth = (d: Date) => new Date(d.getFullYear(), d.getMonth(), 1);
  const monthLabel = (d: Date) => d.toLocaleDateString(undefined, { month: "long", year: "numeric" });

  if (periodKey === "current_month") {
    return { start: startOfMonth(now), end: now, label: monthLabel(now) };
  }
  if (periodKey === "last_month") {
    const lastMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const end = new Date(now.getFullYear(), now.getMonth(), 0);
    return { start: lastMonthDate, end, label: monthLabel(lastMonthDate) };
  }
  const start = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
  const fmt = (d: Date) => d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return { start, end: now, label: `${fmt(start)} – ${fmt(now)}, ${now.getFullYear()}` };
}

function toDateOnly(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// Pulls a snapshot from every other module and turns it into a single,
// client-friendly report using simple deterministic rules (no analytics
// engine) — real BI/reporting integrations will replace this later.
export async function generateProgressReport(
  website: SeoWebsite,
  periodKey: ReportPeriodKey,
): Promise<ProgressReport> {
  const range = periodRange(periodKey);

  const audits = (await fetchAudits(website.id))
    .filter((a) => a.status === "completed")
    .sort((a, b) => new Date(b.completed_at ?? b.started_at).getTime() - new Date(a.completed_at ?? a.started_at).getTime());
  const latestAudit = audits[0] ?? null;
  const previousAudit = audits[1] ?? null;

  const overallCurrent = latestAudit?.overall_visibility_score ?? 0;
  const overallPrevious = previousAudit?.overall_visibility_score ?? overallCurrent;

  const approvalQueue = await fetchApprovalQueue(website.id);
  const pendingApprovals = approvalQueue.filter((a) => a.status === "suggested" || a.status === "needs_review").length;
  const completedApprovals = approvalQueue.filter((a) => a.status === "completed").length;

  const contentOpportunities = await fetchContentOpportunities(website.id);
  const completedContent = contentOpportunities.filter((c) => c.status === "completed").length;

  const pages = await fetchPagePerformance(website.id);
  const decliningPages = pages.filter((p) => p.performance_status === "declining").length;
  const improvingPages = pages.filter((p) => p.performance_status === "improving").length;

  const authorityOpportunities = await fetchAuthorityOpportunities(website.id);
  const avoidedOpportunities = authorityOpportunities.filter((o) => o.status === "avoided").length;

  const aiContentGaps = await fetchAiContentGaps(website.id);
  const competitorGaps = await fetchCompetitorGaps(website.id);

  const roadmapItems = await fetchRoadmapItems(website.id);
  const roadmapCompleted = roadmapItems.filter((r) => r.status === "completed").length;

  const supportRequests = await fetchSupportRequests(website.id);
  const openSupportRequests = supportRequests.filter((s) => s.status !== "completed" && s.status !== "cancelled").length;

  const nextActions: string[] = [];
  if (pendingApprovals > 0) {
    nextActions.push(
      `Review the ${pendingApprovals} pending approval${pendingApprovals === 1 ? "" : "s"} in the Approval Queue.`,
    );
  }
  if (decliningPages > 0) {
    nextActions.push(`Check the ${decliningPages} declining page${decliningPages === 1 ? "" : "s"} in Page Performance.`);
  }
  if (competitorGaps.length > 0) {
    nextActions.push(competitorGaps[0].recommended_action);
  }
  if (openSupportRequests > 0) {
    nextActions.push("Follow up on your open Expert Support requests.");
  }
  if (nextActions.length === 0) {
    nextActions.push("No urgent actions right now — keep monitoring your visibility score.");
  }

  const report = upsertReport(website, periodKey, {
    period_label: range.label,
    period_start: toDateOnly(range.start),
    period_end: toDateOnly(range.end),
    status: "generated",
    generated_at: new Date().toISOString(),
    overall_score_current: overallCurrent,
    overall_score_previous: overallPrevious,
    overall_score_movement: overallCurrent - overallPrevious,
    technical_summary: latestAudit
      ? `${latestAudit.issue_count} technical issue${latestAudit.issue_count === 1 ? "" : "s"} found in the latest audit.`
      : "No completed audit yet for this period.",
    issues_found_count: latestAudit?.issue_count ?? 0,
    issues_fixed_count: completedApprovals,
    pending_approvals_count: pendingApprovals,
    content_summary:
      contentOpportunities.length > 0
        ? `${contentOpportunities.length} content opportunit${contentOpportunities.length === 1 ? "y" : "ies"} identified, ${completedContent} completed.`
        : "No content opportunities identified yet.",
    content_pieces_planned: contentOpportunities.length,
    content_pieces_completed: completedContent,
    performance_summary:
      pages.length > 0
        ? `${improvingPages} page${improvingPages === 1 ? "" : "s"} improving, ${decliningPages} declining.`
        : "No page performance data tracked yet.",
    declining_pages_count: decliningPages,
    improving_pages_count: improvingPages,
    offpage_summary:
      authorityOpportunities.length > 0
        ? `${authorityOpportunities.length} authority opportunit${authorityOpportunities.length === 1 ? "y" : "ies"} identified, ${avoidedOpportunities} flagged as risky and avoided.`
        : "No authority opportunities identified yet.",
    authority_opportunities_count: authorityOpportunities.length,
    ai_visibility_summary:
      aiContentGaps.length > 0
        ? `${aiContentGaps.length} AI content gap${aiContentGaps.length === 1 ? "" : "s"} identified.`
        : "No AI visibility gaps identified yet.",
    ai_content_gaps_count: aiContentGaps.length,
    competitor_summary:
      competitorGaps.length > 0
        ? `${competitorGaps.length} competitor gap${competitorGaps.length === 1 ? "" : "s"} identified.`
        : "No significant competitor gaps right now.",
    competitor_gaps_count: competitorGaps.length,
    roadmap_summary:
      roadmapItems.length > 0
        ? `${roadmapCompleted} of ${roadmapItems.length} roadmap actions completed.`
        : "No roadmap generated yet.",
    roadmap_completed_count: roadmapCompleted,
    roadmap_total_count: roadmapItems.length,
    expert_support_summary:
      openSupportRequests > 0
        ? `${openSupportRequests} open support request${openSupportRequests === 1 ? "" : "s"}.`
        : "No open support requests.",
    open_support_requests_count: openSupportRequests,
    next_actions: nextActions,
  });

  return toAsync(report);
}

export async function fetchReportSummary(
  websiteId: string,
  periodKey: ReportPeriodKey,
): Promise<ProgressReport | null> {
  return fetchReportForPeriod(websiteId, periodKey);
}

export async function fetchReportSections(report: ProgressReport): Promise<ReportSection[]> {
  const sections: ReportSection[] = [
    {
      key: "what_improved",
      title: "What improved",
      body: [
        report.overall_score_movement > 0
          ? `Overall visibility score is up ${report.overall_score_movement} points (${report.overall_score_previous} → ${report.overall_score_current}).`
          : report.overall_score_movement < 0
            ? `Overall visibility score is down ${Math.abs(report.overall_score_movement)} points — needs review.`
            : "Overall visibility score is steady this period.",
        report.improving_pages_count > 0
          ? `${report.improving_pages_count} page(s) trending up in Page Performance.`
          : "No pages trending up yet.",
      ],
    },
    {
      key: "what_was_fixed",
      title: "What was fixed",
      body:
        report.issues_fixed_count > 0
          ? [`${report.issues_fixed_count} issue(s) marked completed this period.`, report.technical_summary]
          : ["No completed fixes yet.", report.technical_summary],
    },
    {
      key: "what_needs_approval",
      title: "What needs approval",
      body:
        report.pending_approvals_count > 0
          ? [`${report.pending_approvals_count} item(s) waiting in the Approval Queue — needs review.`]
          : ["Nothing waiting on your approval right now."],
    },
    {
      key: "what_needs_support",
      title: "What needs expert/developer support",
      body: [report.expert_support_summary, "Expert review recommended for higher-risk items."],
    },
    {
      key: "what_content",
      title: "What content was planned/created",
      body: [report.content_summary],
    },
    {
      key: "what_pages",
      title: "What pages need attention",
      body:
        report.declining_pages_count > 0
          ? [`${report.declining_pages_count} page(s) declining — may improve visibility once addressed.`, report.performance_summary]
          : ["No pages need attention right now.", report.performance_summary],
    },
    {
      key: "what_next",
      title: "What to do next",
      body: report.next_actions,
    },
  ];

  return toAsync(sections);
}
