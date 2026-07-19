import type { SeoBaseRecord, ImpactLevel, EffortLevel, RiskLevel, ActionType } from "./common";

export type VisibilityScoreKey =
  | "overall"
  | "technical_health"
  | "onpage"
  | "authority"
  | "ai_discovery";

export type VisibilityScoreLabel = "good" | "needs_attention" | "critical";

export interface VisibilityScoreCard {
  key: VisibilityScoreKey;
  label: string;
  score: number;
  status_label: VisibilityScoreLabel;
  explanation: string;
}

// Kept as a named alias so existing dashboard components can keep importing
// PriorityFixActionType — the values now live centrally in common.ts since
// audit-derived recommendations use the same vocabulary.
export type PriorityFixActionType = ActionType;

export type PriorityFixStatus = "open" | "in_progress" | "resolved" | "dismissed";

export interface TopPriorityFix extends SeoBaseRecord {
  title: string;
  simple_explanation: string;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  recommended_next_action: string;
  action_type: PriorityFixActionType;
  status: PriorityFixStatus;
  source_issue_id?: string;
  source_recommendation_id?: string;
}

export type RecentActivityType =
  | "website_added"
  | "audit_completed"
  | "recommendation_generated"
  | "onboarding_completed"
  | "report_generated"
  | "content_workflow_update";

export interface RecentActivityItem extends SeoBaseRecord {
  activity_type: RecentActivityType;
  summary: string;
  occurred_at: string;
}

export type SetupChecklistItemKey =
  | "website_added"
  | "sitemap_checked"
  | "robots_checked"
  | "onboarding_completed"
  | "gsc_connected"
  | "ga4_connected"
  | "cms_connected";

export interface SetupChecklistItem {
  key: SetupChecklistItemKey;
  label: string;
  is_complete: boolean;
  is_future_integration: boolean;
  status_label: string;
}

export interface PendingApprovalsSummary {
  website_id: string;
  website_url: string;
  pending_count: number;
  expert_review_count: number;
  developer_needed_count: number;
}

export type RecommendedNextStepType =
  | "add_website"
  | "complete_onboarding"
  | "run_first_audit"
  | "review_priority_fixes"
  | "request_expert_support";

export interface RecommendedNextStep {
  type: RecommendedNextStepType;
  label: string;
  description: string;
  route?: string;
}
