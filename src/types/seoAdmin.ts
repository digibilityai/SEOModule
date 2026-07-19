import type { AuditStatus } from "./audit";
import type { OnboardingStatus } from "./onboarding";
import type { ConnectionStatus } from "./common";
import type { SeoPlanTier } from "./plan";

export type SeoAdminWebsiteHealth = "healthy" | "needs_attention" | "critical" | "inactive";

export type SeoAdminWebsiteFilterKey = "all" | SeoAdminWebsiteHealth;

export interface SeoAdminOverview {
  total_websites: number;
  active_websites: number;
  average_visibility_score: number;
  open_support_requests: number;
  pending_approvals: number;
  high_risk_recommendations: number;
  failed_audits: number;
  content_items_in_review: number;
  reports_generated: number;
  ai_visibility_gaps: number;
  roadmap_actions_pending: number;
}

export interface SeoAdminWebsiteRow {
  website_id: string;
  website_url: string;
  website_name: string;
  business_name: string;
  plan: SeoPlanTier;
  setup_status: ConnectionStatus;
  onboarding_status: OnboardingStatus;
  latest_audit_status: AuditStatus | "none";
  visibility_score: number;
  pending_approvals_count: number;
  open_support_requests_count: number;
  last_activity_at: string | null;
  health: SeoAdminWebsiteHealth;
}

export interface SeoAdminWebsiteDetail {
  row: SeoAdminWebsiteRow;
  website_url: string;
  business_name: string;
  industry?: string;
  target_location?: string;
  onboarding_summary: string;
  connected_tools: {
    gsc_status: ConnectionStatus;
    ga4_status: ConnectionStatus;
    cms_status: ConnectionStatus;
    gbp_status: ConnectionStatus;
  };
  audit_summary: string;
  recommendation_summary: string;
  approval_summary: string;
  content_summary: string;
  performance_summary: string;
  offpage_summary: string;
  ai_visibility_summary: string;
  competitor_summary: string;
  roadmap_summary: string;
  support_summary: string;
  report_summary: string;
  admin_notes: string;
}

export interface SeoAdminOperationsSummary {
  audit_operations: {
    latest_runs_count: number;
    failed_checks_count: number;
    critical_issues_count: number;
  };
  recommendation_review: {
    pending_count: number;
    high_risk_count: number;
    expert_review_count: number;
  };
  content_operations: {
    plans_started_count: number;
    drafts_in_review_count: number;
    approved_drafts_count: number;
    trust_review_needed_count: number;
  };
  support_tickets: {
    submitted_count: number;
    in_review_count: number;
    in_progress_count: number;
    waiting_for_client_count: number;
    completed_count: number;
  };
  reports: {
    latest_generated_at: string | null;
    generated_count: number;
  };
  plans_access: {
    plan_distribution: Record<SeoPlanTier, number>;
  };
  ai_governance: {
    ai_requests_placeholder: number | null;
    estimated_cost_placeholder: number | null;
  };
  integration_health: {
    gsc_connected_count: number;
    ga4_connected_count: number;
    cms_connected_count: number;
    gbp_connected_count: number;
    total_websites: number;
  };
  qa_review: {
    high_risk_changes_count: number;
    content_trust_review_count: number;
    spam_risk_items_count: number;
  };
}
