import type { DeclineCause, OwnerType, PagePerformanceStatus, PageType } from "@/types";

export const PAGE_TYPE_LABEL: Record<PageType, string> = {
  homepage: "Homepage",
  service_page: "Service page",
  blog: "Blog",
  product_page: "Product page",
  category_page: "Category page",
  location_page: "Location page",
  landing_page: "Landing page",
  other: "Other",
};

export const PERFORMANCE_STATUS_LABEL: Record<PagePerformanceStatus, string> = {
  improving: "Improving",
  stable: "Stable",
  declining: "Declining",
  needs_refresh: "Needs refresh",
  not_enough_data: "Not enough data",
};

export const PERFORMANCE_STATUS_VARIANT: Record<
  PagePerformanceStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  improving: "default",
  stable: "secondary",
  declining: "destructive",
  needs_refresh: "secondary",
  not_enough_data: "outline",
};

export const DECLINE_CAUSE_LABEL: Record<DeclineCause, string> = {
  ctr_drop: "Click-through rate drop",
  ranking_loss: "Ranking loss",
  freshness_issue: "Content freshness issue",
  indexing_issue: "Indexing issue",
  cannibalization: "Keyword cannibalization",
  intent_mismatch: "Search intent mismatch",
  weak_title_meta: "Weak title/meta",
  competitor_improvement: "Competitor improvement",
  technical_issue: "Technical issue",
  content_depth_gap: "Content depth gap",
};

export const FIX_OWNER_LABEL: Record<OwnerType, string> = {
  client_action: "Client action",
  developer_needed: "Developer needed",
  digibility_expert: "Digibility expert",
  system_suggestion: "System suggestion",
};

export function formatPercentage(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

export function formatPosition(value: number): string {
  return value > 0 ? value.toFixed(1) : "—";
}

export function formatSignedNumber(value: number, suffix = ""): string {
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(1)}${suffix}`;
}
