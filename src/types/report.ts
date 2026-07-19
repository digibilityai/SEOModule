import type { SeoBaseRecord } from "./common";

export type ReportPeriodKey = "current_month" | "last_month" | "last_90_days";

export type ReportStatus = "not_generated" | "generated" | "stale";

export interface ProgressReport extends SeoBaseRecord {
  period_key: ReportPeriodKey;
  period_label: string;
  period_start: string;
  period_end: string;
  status: ReportStatus;
  generated_at: string;

  overall_score_current: number;
  overall_score_previous: number;
  overall_score_movement: number;

  technical_summary: string;
  issues_found_count: number;
  issues_fixed_count: number;

  pending_approvals_count: number;

  content_summary: string;
  content_pieces_planned: number;
  content_pieces_completed: number;

  performance_summary: string;
  declining_pages_count: number;
  improving_pages_count: number;

  offpage_summary: string;
  authority_opportunities_count: number;

  ai_visibility_summary: string;
  ai_content_gaps_count: number;

  competitor_summary: string;
  competitor_gaps_count: number;

  roadmap_summary: string;
  roadmap_completed_count: number;
  roadmap_total_count: number;

  expert_support_summary: string;
  open_support_requests_count: number;

  next_actions: string[];
}

export type ReportSectionKey =
  | "what_improved"
  | "what_was_fixed"
  | "what_needs_approval"
  | "what_needs_support"
  | "what_content"
  | "what_pages"
  | "what_next";

export interface ReportSection {
  key: ReportSectionKey;
  title: string;
  body: string[];
}
