import type { SeoBaseRecord, ImpactLevel, EffortLevel, RiskLevel, OwnerType, RelatedModule } from "./common";

export type RoadmapSource =
  | "audit_issue"
  | "recommendation"
  | "content_gap"
  | "performance_decline"
  | "offpage_opportunity"
  | "ai_visibility_gap"
  | "competitor_gap"
  | "manual_strategy";

export type RoadmapStatus = "planned" | "in_progress" | "blocked" | "completed" | "skipped";

export type RoadmapDuePeriod =
  | "week_1"
  | "week_2"
  | "week_3"
  | "week_4"
  | "week_5"
  | "week_6"
  | "week_7"
  | "week_8"
  | "week_9"
  | "week_10"
  | "week_11"
  | "week_12";

export interface RoadmapItem extends SeoBaseRecord {
  week_number: number;
  month_number: 1 | 2 | 3;
  due_period: RoadmapDuePeriod;
  title: string;
  explanation: string;
  related_module: RelatedModule;
  source: RoadmapSource;
  priority: ImpactLevel;
  expected_impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  owner: OwnerType;
  status: RoadmapStatus;
}

export interface RoadmapSummary {
  website_id: string;
  website_url: string;
  total_actions: number;
  completed_actions: number;
  pending_actions: number;
  high_priority_actions: number;
  expert_support_actions: number;
  health_summary: string;
  last_generated: string | null;
}

export type RoadmapFilterKey =
  | "all"
  | "month_1"
  | "month_2"
  | "month_3"
  | "high_priority"
  | "expert_support"
  | "completed"
  | "pending";
