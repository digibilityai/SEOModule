import type { ImpactLevel, RelatedModule, SeoBaseRecord } from "./common";
import type { SeoUserRole } from "./role";

export type SupportRequestType =
  | "technical_seo_fix"
  | "content_review"
  | "onpage_seo_review"
  | "offpage_authority_support"
  | "pr_mention_support"
  | "publishing_help"
  | "strategy_review"
  | "developer_support"
  | "ai_visibility_review"
  | "other";

export type SupportUrgency = "normal" | "urgent";

export type SupportMode =
  | "expert_review"
  | "developer_needed"
  | "manual_execution"
  | "strategy_call";

export type SupportStatus =
  | "submitted"
  | "in_review"
  | "assigned"
  | "waiting_for_client"
  | "in_progress"
  | "completed"
  | "cancelled";

export interface SupportAttachment {
  file_name: string;
  uploaded_at: string;
}

export interface SupportComment {
  id: string;
  author_role: SeoUserRole;
  comment_text: string;
  created_at: string;
}

export type SupportActivityType =
  | "created"
  | "status_changed"
  | "comment_added"
  | "info_provided"
  | "cancelled"
  | "completed";

export interface SupportActivityEntry {
  id: string;
  activity_type: SupportActivityType;
  summary: string;
  created_at: string;
}

export interface ExpertSupportRequest extends SeoBaseRecord {
  request_type: SupportRequestType;
  title: string;
  description: string;
  related_module: RelatedModule;
  related_item_url?: string;
  priority: ImpactLevel;
  urgency: SupportUrgency;
  preferred_support_mode: SupportMode;
  attachment?: SupportAttachment;
  notes?: string;
  status: SupportStatus;
  assignee_placeholder?: string;
  comments: SupportComment[];
  activity: SupportActivityEntry[];
}

export interface SupportSummary {
  website_id: string;
  website_url: string;
  support_plan_status: string;
  open_requests_count: number;
  pending_expert_review_count: number;
  developer_needed_count: number;
  completed_requests_count: number;
}

export interface NewSupportRequestInput {
  request_type: SupportRequestType;
  title: string;
  description: string;
  related_module: RelatedModule;
  related_item_url?: string;
  priority: ImpactLevel;
  urgency: SupportUrgency;
  preferred_support_mode: SupportMode;
  attachment?: SupportAttachment;
  notes?: string;
}
