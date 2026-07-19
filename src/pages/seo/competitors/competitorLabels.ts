import type { CompetitorStrengthStatus, GapLevel, RelatedModule } from "@/types";

export const STRENGTH_STATUS_LABEL: Record<CompetitorStrengthStatus, string> = {
  stronger: "Stronger than you",
  similar: "Similar to you",
  weaker: "Weaker than you",
  unknown: "Not enough data",
};

export const STRENGTH_STATUS_VARIANT: Record<
  CompetitorStrengthStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  stronger: "destructive",
  similar: "secondary",
  weaker: "default",
  unknown: "outline",
};

export const GAP_LEVEL_VARIANT: Record<GapLevel, "default" | "secondary" | "destructive"> = {
  high: "destructive",
  medium: "default",
  low: "secondary",
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
