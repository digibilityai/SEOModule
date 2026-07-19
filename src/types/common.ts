export interface SeoBaseRecord {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  user_id: string;
  created_by: string;
  created_at: string;
  updated_at: string;
}

export type ImpactLevel = "low" | "medium" | "high";
export type EffortLevel = "low" | "medium" | "high";
export type RiskLevel = "low" | "medium" | "high";
export type ConfidenceLevel = "low" | "medium" | "high";
export type SeverityLevel = "critical" | "high" | "medium" | "low";

export type OwnerType =
  | "client_action"
  | "developer_needed"
  | "digibility_expert"
  | "system_suggestion";

// Shared across audit-derived recommendations and dashboard priority fixes.
export type ActionType =
  | "auto_suggest"
  | "approval_required"
  | "manual_support"
  | "expert_review"
  | "avoid";

export type ConnectionStatus = "not_connected" | "pending" | "connected" | "error";

export type AuditFrequency = "monthly" | "weekly" | "weekly_plus_change_monitoring";

// Shared across competitor gaps, roadmap items and support requests — the
// module a finding or action is best resolved through.
export type RelatedModule =
  | "audit"
  | "approval_queue"
  | "content_studio"
  | "offpage_authority"
  | "ai_visibility"
  | "page_performance"
  | "decline_diagnosis"
  | "competitor_benchmarking"
  | "roadmap"
  | "reports"
  | "expert_support"
  | "other";
