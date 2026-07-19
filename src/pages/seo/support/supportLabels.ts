import type { RelatedModule, SupportMode, SupportRequestType, SupportStatus, SupportUrgency } from "@/types";

export const REQUEST_TYPE_LABEL: Record<SupportRequestType, string> = {
  technical_seo_fix: "Technical SEO fix",
  content_review: "Content review",
  onpage_seo_review: "On-page SEO review",
  offpage_authority_support: "Off-page authority support",
  pr_mention_support: "PR / mention support",
  publishing_help: "Publishing help",
  strategy_review: "Strategy review",
  developer_support: "Developer support",
  ai_visibility_review: "AI visibility review",
  other: "Other",
};

export const SUPPORT_MODE_LABEL: Record<SupportMode, string> = {
  expert_review: "Expert review",
  developer_needed: "Developer needed",
  manual_execution: "Manual execution",
  strategy_call: "Strategy call",
};

export const SUPPORT_STATUS_LABEL: Record<SupportStatus, string> = {
  submitted: "Submitted",
  in_review: "In review",
  assigned: "Assigned",
  waiting_for_client: "Waiting for client",
  in_progress: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
};

export const SUPPORT_STATUS_VARIANT: Record<
  SupportStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  submitted: "outline",
  in_review: "secondary",
  assigned: "secondary",
  waiting_for_client: "secondary",
  in_progress: "default",
  completed: "default",
  cancelled: "destructive",
};

export const SUPPORT_URGENCY_VARIANT: Record<SupportUrgency, "destructive" | "outline"> = {
  urgent: "destructive",
  normal: "outline",
};

export const RELATED_MODULE_LABEL: Record<RelatedModule, string> = {
  audit: "Technical SEO Audit",
  approval_queue: "Approval Queue",
  content_studio: "Content Studio",
  offpage_authority: "Off-Page Authority Builder",
  ai_visibility: "AI Visibility / GEO Engine",
  page_performance: "Page Performance Tracker",
  decline_diagnosis: "Decline Diagnosis",
  competitor_benchmarking: "Competitor Benchmarking",
  roadmap: "90-Day Roadmap",
  reports: "Progress Reports",
  expert_support: "Expert Support",
  other: "Other",
};

export const RELATED_MODULE_OPTIONS: RelatedModule[] = [
  "audit",
  "approval_queue",
  "content_studio",
  "page_performance",
  "decline_diagnosis",
  "offpage_authority",
  "ai_visibility",
  "competitor_benchmarking",
  "roadmap",
  "reports",
  "other",
];
