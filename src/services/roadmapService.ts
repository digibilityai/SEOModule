import type {
  ActionType,
  EffortLevel,
  ImpactLevel,
  OwnerType,
  RelatedModule,
  RiskLevel,
  RoadmapItem,
  RoadmapSource,
  RoadmapSummary,
  SeoWebsite,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { fetchIssuesForAudit, fetchLatestAudit } from "@/services/auditService";
import { fetchOnPageRecommendations } from "@/services/recommendationService";
import { fetchDeclineDiagnoses } from "@/services/performanceService";
import { fetchAuthorityOpportunities } from "@/services/offPageService";
import { fetchAiContentGaps } from "@/services/aiVisibilityService";
import { fetchCompetitorGaps } from "@/services/competitorService";
import {
  getRoadmapItemById,
  listHighPriorityRoadmapItems,
  listRoadmapItems,
  listRoadmapItemsByMonth,
  replaceRoadmapForWebsite,
  updateRoadmapItemStatus as updateRoadmapItemStatusRecord,
} from "@/mocks/roadmapMockData";

export async function fetchRoadmapItems(websiteId: string): Promise<RoadmapItem[]> {
  return toAsync(listRoadmapItems(websiteId));
}

export async function fetchRoadmapItemById(id: string): Promise<RoadmapItem | null> {
  return toAsync(getRoadmapItemById(id));
}

export async function fetchRoadmapItemsByMonth(websiteId: string, month: 1 | 2 | 3): Promise<RoadmapItem[]> {
  return toAsync(listRoadmapItemsByMonth(websiteId, month));
}

export async function fetchHighPriorityRoadmapItems(websiteId: string): Promise<RoadmapItem[]> {
  return toAsync(listHighPriorityRoadmapItems(websiteId));
}

export async function updateRoadmapItemStatus(
  id: string,
  status: RoadmapItem["status"],
): Promise<RoadmapItem | null> {
  return toAsync(updateRoadmapItemStatusRecord(id, status));
}

export async function fetchRoadmapSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<RoadmapSummary> {
  const items = listRoadmapItems(websiteId);
  const completed = items.filter((i) => i.status === "completed").length;
  const pending = items.filter((i) => i.status === "planned" || i.status === "in_progress" || i.status === "blocked").length;
  const highPriority = items.filter((i) => i.priority === "high").length;
  const expertSupport = items.filter((i) => i.owner === "digibility_expert").length;
  const lastGenerated = items.reduce<string | null>((latest, i) => {
    if (!latest) return i.updated_at;
    return new Date(i.updated_at).getTime() > new Date(latest).getTime() ? i.updated_at : latest;
  }, null);

  let healthSummary = "No roadmap yet — generate one to turn your findings into a 90-day plan.";
  if (items.length > 0) {
    healthSummary =
      completed === items.length
        ? "All planned actions for this roadmap are marked complete — nice work. Generate a fresh roadmap to keep going."
        : `${completed} of ${items.length} actions completed so far.`;
  }

  return toAsync({
    website_id: websiteId,
    website_url: websiteUrl,
    total_actions: items.length,
    completed_actions: completed,
    pending_actions: pending,
    high_priority_actions: highPriority,
    expert_support_actions: expertSupport,
    health_summary: healthSummary,
    last_generated: lastGenerated,
  });
}

type DraftRoadmapItem = Pick<
  RoadmapItem,
  "title" | "explanation" | "related_module" | "source" | "priority" | "expected_impact" | "effort" | "risk" | "owner"
>;

const ACTION_TYPE_OWNER: Record<ActionType, OwnerType> = {
  auto_suggest: "system_suggestion",
  approval_required: "developer_needed",
  manual_support: "client_action",
  expert_review: "digibility_expert",
  avoid: "system_suggestion",
};

const PRIORITY_WEIGHT: Record<ImpactLevel, number> = { high: 3, medium: 2, low: 1 };

function sortByPriorityDesc(items: DraftRoadmapItem[]): DraftRoadmapItem[] {
  return [...items].sort((a, b) => PRIORITY_WEIGHT[b.priority] - PRIORITY_WEIGHT[a.priority]);
}

function pathnameOf(url: string): string {
  try {
    return new URL(url).pathname || "/";
  } catch {
    return url;
  }
}

// Pulls findings from every other module and turns them into a simple,
// prioritized 90-day plan using deterministic rules (no AI strategy layer):
// Month 1 = audit issues (foundation/technical), Month 2 = on-page
// recommendations (content/on-page visibility), Month 3 = performance
// decline, off-page opportunities, AI visibility gaps and competitor gaps
// (authority/AI/performance improvement).
export async function generateRoadmapFromFindings(website: SeoWebsite): Promise<RoadmapItem[]> {
  const latestAudit = await fetchLatestAudit(website.id);
  const issues = latestAudit?.status === "completed" ? await fetchIssuesForAudit(latestAudit.id) : [];

  const month1: DraftRoadmapItem[] = sortByPriorityDesc(
    issues.map((issue) => ({
      title: issue.title,
      explanation: issue.simple_explanation,
      related_module: "audit" as RelatedModule,
      source: "audit_issue" as RoadmapSource,
      priority: issue.impact,
      expected_impact: issue.impact,
      effort: issue.effort,
      risk: issue.risk,
      owner: issue.fix_owner,
    })),
  ).slice(0, 4);

  const onPageRecs = await fetchOnPageRecommendations(website.id);
  const month2: DraftRoadmapItem[] = sortByPriorityDesc(
    onPageRecs.map((rec) => ({
      title: rec.title,
      explanation: rec.why_it_helps,
      related_module: "content_studio" as RelatedModule,
      source: "recommendation" as RoadmapSource,
      priority: rec.impact,
      expected_impact: rec.impact,
      effort: rec.effort,
      risk: rec.risk,
      owner: ACTION_TYPE_OWNER[rec.action_type],
    })),
  ).slice(0, 4);

  const [declineDiagnoses, offPageOpportunities, aiContentGaps, competitorGaps] = await Promise.all([
    fetchDeclineDiagnoses(website.id),
    fetchAuthorityOpportunities(website.id),
    fetchAiContentGaps(website.id),
    fetchCompetitorGaps(website.id),
  ]);

  const month3Pool: DraftRoadmapItem[] = [
    ...declineDiagnoses.map((d) => ({
      title: `Address ${d.likely_cause.replace(/_/g, " ")} on ${pathnameOf(d.page_url)}`,
      explanation: d.business_explanation,
      related_module: "page_performance" as RelatedModule,
      source: "performance_decline" as RoadmapSource,
      priority: d.priority,
      expected_impact: d.priority,
      effort: "medium" as EffortLevel,
      risk: "low" as RiskLevel,
      owner: d.fix_owner,
    })),
    ...offPageOpportunities
      .filter((o) => o.status !== "avoided" && o.status !== "rejected" && o.status !== "completed")
      .map((o) => ({
        title: o.title,
        explanation: o.why_it_matters,
        related_module: "offpage_authority" as RelatedModule,
        source: "offpage_opportunity" as RoadmapSource,
        priority: o.expected_authority_impact,
        expected_impact: o.expected_authority_impact,
        effort: o.effort,
        risk: o.risk,
        owner: o.fix_owner,
      })),
    ...aiContentGaps.map((g) => ({
      title: `Close AI content gap: ${g.topic}`,
      explanation: g.recommended_next_action,
      related_module: "ai_visibility" as RelatedModule,
      source: "ai_visibility_gap" as RoadmapSource,
      priority: g.priority,
      expected_impact: g.priority,
      effort: "medium" as EffortLevel,
      risk: "low" as RiskLevel,
      owner: "client_action" as OwnerType,
    })),
    ...competitorGaps.map((g) => ({
      title: g.title,
      explanation: g.recommended_action,
      related_module: g.related_module,
      source: "competitor_gap" as RoadmapSource,
      priority: g.priority,
      expected_impact: g.priority,
      effort: "medium" as EffortLevel,
      risk: "low" as RiskLevel,
      owner: g.suggested_owner,
    })),
  ];

  const month3 = sortByPriorityDesc(month3Pool).slice(0, 8);

  const now = new Date().toISOString();
  const assignWeeks = (drafts: DraftRoadmapItem[], weekRange: number[]): RoadmapItem[] =>
    drafts.map((draft, index) => {
      const week = weekRange[index % weekRange.length];
      return {
        id: `rmp_draft_${index}`,
        workspace_id: website.workspace_id,
        website_id: website.id,
        website_url: website.website_url,
        user_id: website.user_id,
        created_by: website.user_id,
        created_at: now,
        updated_at: now,
        week_number: week,
        month_number: (Math.ceil(week / 4) as 1 | 2 | 3),
        due_period: `week_${week}` as RoadmapItem["due_period"],
        status: "planned",
        ...draft,
      };
    });

  const items: RoadmapItem[] = [
    ...assignWeeks(month1, [1, 2, 3, 4]),
    ...assignWeeks(month2, [5, 6, 7, 8]),
    ...assignWeeks(month3, [9, 10, 11, 12]),
  ];

  return toAsync(replaceRoadmapForWebsite(website, items));
}
