import type {
  SeoBaseRecord,
  ImpactLevel,
  EffortLevel,
  RiskLevel,
  ActionType,
  OwnerType,
} from "./common";
import type { RecommendationStatus } from "./recommendation";
import type { SeoUserRole } from "./role";

export interface ApprovalComment {
  id: string;
  author_role: SeoUserRole;
  comment_text: string;
  created_at: string;
}

export interface ApprovalItem extends SeoBaseRecord {
  recommendation_id: string;
  issue_id?: string;
  title: string;
  page_url?: string;
  simple_explanation: string;
  suggested_change: string;
  action_type: ActionType;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  fix_owner: OwnerType;
  // True when the underlying issue touches URLs, redirects, canonical tags,
  // noindex tags, robots.txt or sitemap rules — these always require
  // owner/admin (or expert) sign-off regardless of the stated risk level.
  is_high_risk_category: boolean;
  status: RecommendationStatus;
  comments: ApprovalComment[];
}
