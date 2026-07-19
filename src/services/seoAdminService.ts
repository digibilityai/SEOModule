import type {
  ApprovalItem,
  BusinessOnboarding,
  ContentOpportunity,
  ExpertSupportRequest,
  OffPageOpportunity,
  ProgressReport,
  SeoAdminOperationsSummary,
  SeoAdminOverview,
  SeoAdminWebsiteDetail,
  SeoAdminWebsiteRow,
  SeoAudit,
  SeoIssue,
  SeoPlanTier,
  SeoWebsite,
  SpamRiskReview,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { recommendationRequiresApproval } from "@/lib/safetyRules";
import { MOCK_WORKSPACE_ID } from "@/mocks/mockContext";
import { getAdminNote } from "@/mocks/seoAdminMockData";
import { fetchWebsites } from "@/services/websiteService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { fetchAudits, fetchIssuesForAudit } from "@/services/auditService";
import { fetchRecommendations } from "@/services/recommendationService";
import { fetchApprovalQueue } from "@/services/approvalService";
import { fetchContentOpportunities } from "@/services/contentStudioService";
import { fetchPerformanceSummary } from "@/services/performanceService";
import { fetchAuthorityOpportunities, fetchSpamRiskReview } from "@/services/offPageService";
import { fetchAiVisibilityOverview } from "@/services/aiVisibilityService";
import { fetchCompetitorGaps } from "@/services/competitorService";
import { fetchRoadmapSummary } from "@/services/roadmapService";
import { fetchSupportRequests } from "@/services/supportService";
import { fetchProgressReports } from "@/services/reportService";
import { fetchRecentActivity } from "@/services/dashboardService";

// Content statuses treated as "trust review" candidates for high-risk
// industries — there's no dedicated Content Trust Review module yet, so
// this is a simple derived heuristic, not a stored flag.
const TRUST_REVIEW_STATUSES = new Set(["draft_ready", "draft_in_review"]);

interface SiteAdminBundle {
  website: SeoWebsite;
  onboarding: BusinessOnboarding | null;
  audits: SeoAudit[];
  latestAudit: SeoAudit | null;
  latestAuditIssues: SeoIssue[];
  recommendations: Awaited<ReturnType<typeof fetchRecommendations>>;
  approvals: ApprovalItem[];
  contentOpportunities: ContentOpportunity[];
  supportRequests: ExpertSupportRequest[];
  reports: ProgressReport[];
  offpageOpportunities: OffPageOpportunity[];
  spamRiskReviews: SpamRiskReview[];
  aiVisibilityOverview: Awaited<ReturnType<typeof fetchAiVisibilityOverview>>;
  competitorGaps: Awaited<ReturnType<typeof fetchCompetitorGaps>>;
  roadmapSummary: Awaited<ReturnType<typeof fetchRoadmapSummary>>;
  performanceSummary: Awaited<ReturnType<typeof fetchPerformanceSummary>>;
  lastActivityAt: string | null;
}

async function buildSiteBundle(website: SeoWebsite): Promise<SiteAdminBundle> {
  const [
    onboarding,
    audits,
    recommendations,
    approvals,
    contentOpportunities,
    supportRequests,
    reports,
    offpageOpportunities,
    spamRiskReviews,
    aiVisibilityOverview,
    competitorGaps,
    roadmapSummary,
    performanceSummary,
    recentActivity,
  ] = await Promise.all([
    fetchOnboardingByWebsiteId(website.id),
    fetchAudits(website.id),
    fetchRecommendations(website.id),
    fetchApprovalQueue(website.id),
    fetchContentOpportunities(website.id),
    fetchSupportRequests(website.id),
    fetchProgressReports(website.id),
    fetchAuthorityOpportunities(website.id),
    fetchSpamRiskReview(website.id),
    fetchAiVisibilityOverview(website.id, website.website_url),
    fetchCompetitorGaps(website.id),
    fetchRoadmapSummary(website.id, website.website_url),
    fetchPerformanceSummary(website.id, website.website_url),
    fetchRecentActivity(website.id),
  ]);

  const latestAudit =
    [...audits]
      .filter((a) => a.status === "completed")
      .sort(
        (a, b) =>
          new Date(b.completed_at ?? b.started_at).getTime() -
          new Date(a.completed_at ?? a.started_at).getTime(),
      )[0] ?? null;
  const latestAuditIssues = latestAudit ? await fetchIssuesForAudit(latestAudit.id) : [];

  const lastActivityAt = recentActivity[0]?.occurred_at ?? website.updated_at;

  return {
    website,
    onboarding,
    audits,
    latestAudit,
    latestAuditIssues,
    recommendations,
    approvals,
    contentOpportunities,
    supportRequests,
    reports,
    offpageOpportunities,
    spamRiskReviews,
    aiVisibilityOverview,
    competitorGaps,
    roadmapSummary,
    performanceSummary,
    lastActivityAt,
  };
}

async function buildAllBundles(): Promise<SiteAdminBundle[]> {
  const websites = await fetchWebsites(MOCK_WORKSPACE_ID);
  return Promise.all(websites.map(buildSiteBundle));
}

function computeHealth(bundle: SiteAdminBundle): SeoAdminWebsiteRow["health"] {
  const { website, onboarding, latestAudit, approvals, recommendations, supportRequests } = bundle;

  if (website.status !== "active") return "inactive";

  const hasFailedLatestAudit = [...bundle.audits].sort(
    (a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime(),
  )[0]?.status === "failed";
  const highRiskRecommendations = recommendations.filter(recommendationRequiresApproval).length;

  if (hasFailedLatestAudit || highRiskRecommendations > 0) return "critical";

  const pendingApprovals = approvals.filter((a) => a.status === "suggested" || a.status === "needs_review").length;
  const openSupport = supportRequests.filter((s) => s.status !== "completed" && s.status !== "cancelled").length;
  const onboardingIncomplete = !onboarding || onboarding.status !== "completed";

  if (pendingApprovals > 0 || openSupport > 0 || onboardingIncomplete || !latestAudit) return "needs_attention";

  return "healthy";
}

function toRow(bundle: SiteAdminBundle): SeoAdminWebsiteRow {
  const pendingApprovals = bundle.approvals.filter(
    (a) => a.status === "suggested" || a.status === "needs_review",
  ).length;
  const openSupport = bundle.supportRequests.filter(
    (s) => s.status !== "completed" && s.status !== "cancelled",
  ).length;

  return {
    website_id: bundle.website.id,
    website_url: bundle.website.website_url,
    website_name: bundle.website.name,
    business_name: bundle.website.business_name,
    plan: bundle.website.plan,
    setup_status: bundle.website.reachable_status,
    onboarding_status: bundle.onboarding?.status ?? "not_started",
    latest_audit_status: bundle.latestAudit?.status ?? "none",
    visibility_score: bundle.latestAudit?.overall_visibility_score ?? 0,
    pending_approvals_count: pendingApprovals,
    open_support_requests_count: openSupport,
    last_activity_at: bundle.lastActivityAt,
    health: computeHealth(bundle),
  };
}

export async function fetchSeoAdminWebsites(): Promise<SeoAdminWebsiteRow[]> {
  const bundles = await buildAllBundles();
  return toAsync(bundles.map(toRow));
}

export async function fetchSeoAdminOverview(): Promise<SeoAdminOverview> {
  const bundles = await buildAllBundles();

  const completedAuditsWithScore = bundles
    .map((b) => b.latestAudit?.overall_visibility_score)
    .filter((v): v is number => typeof v === "number");

  return toAsync({
    total_websites: bundles.length,
    active_websites: bundles.filter((b) => b.website.status === "active").length,
    average_visibility_score:
      completedAuditsWithScore.length > 0
        ? Math.round(completedAuditsWithScore.reduce((sum, v) => sum + v, 0) / completedAuditsWithScore.length)
        : 0,
    open_support_requests: bundles.reduce(
      (sum, b) => sum + b.supportRequests.filter((s) => s.status !== "completed" && s.status !== "cancelled").length,
      0,
    ),
    pending_approvals: bundles.reduce(
      (sum, b) => sum + b.approvals.filter((a) => a.status === "suggested" || a.status === "needs_review").length,
      0,
    ),
    high_risk_recommendations: bundles.reduce(
      (sum, b) => sum + b.recommendations.filter(recommendationRequiresApproval).length,
      0,
    ),
    failed_audits: bundles.filter(
      (b) => [...b.audits].sort((a, c) => new Date(c.started_at).getTime() - new Date(a.started_at).getTime())[0]?.status === "failed",
    ).length,
    content_items_in_review: bundles.reduce(
      (sum, b) =>
        sum +
        b.contentOpportunities.filter(
          (c) => c.status === "wireframe_ready" || c.status === "draft_in_review" || c.status === "expert_review_requested",
        ).length,
      0,
    ),
    reports_generated: bundles.reduce((sum, b) => sum + b.reports.length, 0),
    ai_visibility_gaps: bundles.reduce((sum, b) => sum + b.aiVisibilityOverview.content_gap_count, 0),
    roadmap_actions_pending: bundles.reduce((sum, b) => sum + b.roadmapSummary.pending_actions, 0),
  });
}

export async function fetchSeoAdminOperationsSummary(): Promise<SeoAdminOperationsSummary> {
  const bundles = await buildAllBundles();

  const planDistribution: Record<SeoPlanTier, number> = { basic: 0, standard: 0, pro: 0 };
  bundles.forEach((b) => {
    planDistribution[b.website.plan] += 1;
  });

  const isTrustReviewCandidate = (b: SiteAdminBundle) =>
    b.website.is_high_risk_industry
      ? b.contentOpportunities.filter((c) => TRUST_REVIEW_STATUSES.has(c.status)).length
      : 0;

  return toAsync({
    audit_operations: {
      latest_runs_count: bundles.reduce((sum, b) => sum + b.audits.length, 0),
      failed_checks_count: bundles.reduce((sum, b) => sum + b.latestAuditIssues.length, 0),
      critical_issues_count: bundles.reduce(
        (sum, b) => sum + b.latestAuditIssues.filter((i) => i.severity === "critical").length,
        0,
      ),
    },
    recommendation_review: {
      pending_count: bundles.reduce(
        (sum, b) => sum + b.recommendations.filter((r) => r.status === "suggested" || r.status === "needs_review").length,
        0,
      ),
      high_risk_count: bundles.reduce(
        (sum, b) => sum + b.recommendations.filter(recommendationRequiresApproval).length,
        0,
      ),
      expert_review_count: bundles.reduce(
        (sum, b) =>
          sum + b.recommendations.filter((r) => r.action_type === "expert_review" || r.status === "expert_review_requested").length,
        0,
      ),
    },
    content_operations: {
      plans_started_count: bundles.reduce(
        (sum, b) => sum + b.contentOpportunities.filter((c) => c.status !== "idea_suggested").length,
        0,
      ),
      drafts_in_review_count: bundles.reduce(
        (sum, b) => sum + b.contentOpportunities.filter((c) => c.status === "draft_in_review").length,
        0,
      ),
      approved_drafts_count: bundles.reduce(
        (sum, b) => sum + b.contentOpportunities.filter((c) => c.status === "draft_approved").length,
        0,
      ),
      trust_review_needed_count: bundles.reduce((sum, b) => sum + isTrustReviewCandidate(b), 0),
    },
    support_tickets: {
      submitted_count: bundles.reduce((sum, b) => sum + b.supportRequests.filter((s) => s.status === "submitted").length, 0),
      in_review_count: bundles.reduce((sum, b) => sum + b.supportRequests.filter((s) => s.status === "in_review").length, 0),
      in_progress_count: bundles.reduce((sum, b) => sum + b.supportRequests.filter((s) => s.status === "in_progress").length, 0),
      waiting_for_client_count: bundles.reduce(
        (sum, b) => sum + b.supportRequests.filter((s) => s.status === "waiting_for_client").length,
        0,
      ),
      completed_count: bundles.reduce((sum, b) => sum + b.supportRequests.filter((s) => s.status === "completed").length, 0),
    },
    reports: {
      latest_generated_at: bundles.reduce<string | null>((latest, b) => {
        const siteLatest = b.reports.reduce<string | null>((l, r) => {
          if (!l) return r.generated_at;
          return new Date(r.generated_at).getTime() > new Date(l).getTime() ? r.generated_at : l;
        }, null);
        if (!siteLatest) return latest;
        if (!latest) return siteLatest;
        return new Date(siteLatest).getTime() > new Date(latest).getTime() ? siteLatest : latest;
      }, null),
      generated_count: bundles.reduce((sum, b) => sum + b.reports.length, 0),
    },
    plans_access: {
      plan_distribution: planDistribution,
    },
    ai_governance: {
      ai_requests_placeholder: null,
      estimated_cost_placeholder: null,
    },
    integration_health: {
      gsc_connected_count: bundles.filter((b) => b.website.gsc_status === "connected").length,
      ga4_connected_count: bundles.filter((b) => b.website.ga4_status === "connected").length,
      cms_connected_count: bundles.filter((b) => b.website.cms_status === "connected").length,
      gbp_connected_count: bundles.filter((b) => b.website.gbp_status === "connected").length,
      total_websites: bundles.length,
    },
    qa_review: {
      high_risk_changes_count: bundles.reduce((sum, b) => sum + b.approvals.filter((a) => a.is_high_risk_category).length, 0),
      content_trust_review_count: bundles.reduce((sum, b) => sum + isTrustReviewCandidate(b), 0),
      spam_risk_items_count: bundles.reduce((sum, b) => sum + b.spamRiskReviews.length, 0),
    },
  });
}

export async function fetchSeoAdminWebsiteDetail(websiteId: string): Promise<SeoAdminWebsiteDetail | null> {
  const bundles = await buildAllBundles();
  const bundle = bundles.find((b) => b.website.id === websiteId);
  if (!bundle) return null;

  const row = toRow(bundle);
  const pendingApprovals = row.pending_approvals_count;
  const highRiskRecommendations = bundle.recommendations.filter(recommendationRequiresApproval).length;
  const completedContent = bundle.contentOpportunities.filter((c) => c.status === "completed").length;
  const openSupport = row.open_support_requests_count;

  return toAsync({
    row,
    website_url: bundle.website.website_url,
    business_name: bundle.website.business_name,
    industry: bundle.website.industry,
    target_location: bundle.website.target_location,
    onboarding_summary: bundle.onboarding
      ? `${bundle.onboarding.status} (${bundle.onboarding.completion_percentage}% complete). Goal: ${bundle.onboarding.main_seo_goal}.`
      : "Onboarding not started.",
    connected_tools: {
      gsc_status: bundle.website.gsc_status,
      ga4_status: bundle.website.ga4_status,
      cms_status: bundle.website.cms_status,
      gbp_status: bundle.website.gbp_status,
    },
    audit_summary: bundle.latestAudit
      ? `Latest audit ${bundle.latestAudit.status}, overall score ${bundle.latestAudit.overall_visibility_score}/100, ${bundle.latestAuditIssues.length} issue(s) found.`
      : "No completed audit yet.",
    recommendation_summary: `${bundle.recommendations.length} recommendation(s), ${highRiskRecommendations} high-risk.`,
    approval_summary: `${pendingApprovals} pending approval(s) out of ${bundle.approvals.length} total.`,
    content_summary: `${bundle.contentOpportunities.length} content opportunit${bundle.contentOpportunities.length === 1 ? "y" : "ies"}, ${completedContent} completed.`,
    performance_summary:
      bundle.performanceSummary.tracked_pages_count > 0
        ? `${bundle.performanceSummary.tracked_pages_count} page(s) tracked — ${bundle.performanceSummary.declining_count} declining, ${bundle.performanceSummary.needs_refresh_count} need refresh.`
        : "No page performance data tracked yet.",
    offpage_summary: `${bundle.offpageOpportunities.length} authority opportunit${bundle.offpageOpportunities.length === 1 ? "y" : "ies"}, ${bundle.spamRiskReviews.length} flagged for risk.`,
    ai_visibility_summary: `AI discovery score ${bundle.aiVisibilityOverview.ai_discovery_score}/100, ${bundle.aiVisibilityOverview.content_gap_count} content gap(s).`,
    competitor_summary:
      bundle.competitorGaps.length > 0
        ? `${bundle.competitorGaps.length} competitor gap(s) identified.`
        : "No significant competitor gaps right now.",
    roadmap_summary: `${bundle.roadmapSummary.completed_actions}/${bundle.roadmapSummary.total_actions} roadmap actions completed.`,
    support_summary: `${openSupport} open support request(s).`,
    report_summary:
      bundle.reports.length > 0
        ? `${bundle.reports.length} report(s) generated. Latest: ${new Date(
            bundle.reports.reduce((latest, r) => (new Date(r.generated_at) > new Date(latest) ? r.generated_at : latest), bundle.reports[0].generated_at),
          ).toLocaleDateString()}.`
        : "No reports generated yet.",
    admin_notes: getAdminNote(websiteId),
  });
}
