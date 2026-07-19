import type { RelatedModule, RoadmapSource, RoadmapStatus } from "@/types";

export const ROADMAP_STATUS_LABEL: Record<RoadmapStatus, string> = {
  planned: "Planned",
  in_progress: "In progress",
  blocked: "Blocked",
  completed: "Completed",
  skipped: "Skipped",
};

export const ROADMAP_STATUS_VARIANT: Record<
  RoadmapStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  planned: "outline",
  in_progress: "secondary",
  blocked: "destructive",
  completed: "default",
  skipped: "outline",
};

export const ROADMAP_SOURCE_LABEL: Record<RoadmapSource, string> = {
  audit_issue: "Audit issue",
  recommendation: "Recommendation",
  content_gap: "Content gap",
  performance_decline: "Performance decline",
  offpage_opportunity: "Off-page opportunity",
  ai_visibility_gap: "AI visibility gap",
  competitor_gap: "Competitor gap",
  manual_strategy: "Manual strategy",
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

export const RELATED_MODULE_ROUTE: Partial<Record<RelatedModule, string>> = {
  audit: "/seo/audit",
  approval_queue: "/seo/approvals",
  content_studio: "/seo/content-studio",
  offpage_authority: "/seo/off-page",
  ai_visibility: "/seo/ai-visibility",
  page_performance: "/seo/page-performance",
  decline_diagnosis: "/seo/decline-diagnosis",
  competitor_benchmarking: "/seo/competitor-analysis",
  roadmap: "/seo/roadmap",
  reports: "/seo/reports",
  expert_support: "/seo/support",
};

export const FIX_OWNER_LABEL: Record<string, string> = {
  client_action: "Client action",
  developer_needed: "Developer needed",
  digibility_expert: "Digibility expert",
  system_suggestion: "System suggestion",
};
