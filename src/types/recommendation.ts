import type { SeoBaseRecord, ImpactLevel, EffortLevel, RiskLevel, ActionType } from "./common";

export type RecommendationArea =
  | "title"
  | "meta_description"
  | "h1"
  | "faq"
  | "schema"
  | "internal_links"
  | "content"
  | "technical";

export type RecommendationStatus =
  | "suggested"
  | "needs_review"
  | "approved"
  | "rejected"
  | "expert_review_requested"
  | "developer_needed"
  | "ready_to_publish"
  | "completed";

export interface SeoRecommendation extends SeoBaseRecord {
  issue_id?: string;
  area: RecommendationArea;
  title: string;
  current_value?: string;
  suggested_change: string;
  why_it_helps: string;
  action_type: ActionType;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  status: RecommendationStatus;
}
