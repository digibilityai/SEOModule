import type { SeoBaseRecord, ImpactLevel, OwnerType } from "./common";

export type PageType =
  | "homepage"
  | "service_page"
  | "blog"
  | "product_page"
  | "category_page"
  | "location_page"
  | "landing_page"
  | "other";

export type PagePerformanceStatus =
  | "improving"
  | "stable"
  | "declining"
  | "needs_refresh"
  | "not_enough_data";

export interface PagePerformance extends SeoBaseRecord {
  page_title: string;
  page_url: string;
  page_type: PageType;
  primary_keyword: string;
  secondary_keywords: string[];
  clicks: number;
  impressions: number;
  ctr: number;
  avg_position: number;
  previous_avg_position: number;
  ranking_movement: number;
  clicks_previous_period: number;
  impressions_previous_period: number;
  previous_ctr: number;
  traffic_movement_percentage: number;
  performance_status: PagePerformanceStatus;
  main_seo_issue?: string;
  recommended_next_action?: string;
}

export interface PerformanceSummary {
  website_id: string;
  website_url: string;
  tracked_pages_count: number;
  tracked_keywords_count: number;
  improving_count: number;
  stable_count: number;
  declining_count: number;
  needs_refresh_count: number;
  not_enough_data_count: number;
  total_clicks: number;
  total_impressions: number;
  average_ctr: number;
  average_position: number;
  data_source_status: string;
  last_updated: string | null;
}

export type DeclineCause =
  | "ctr_drop"
  | "ranking_loss"
  | "freshness_issue"
  | "indexing_issue"
  | "cannibalization"
  | "intent_mismatch"
  | "weak_title_meta"
  | "competitor_improvement"
  | "technical_issue"
  | "content_depth_gap";

export interface DeclineDiagnosis extends SeoBaseRecord {
  page_performance_id: string;
  page_url: string;
  related_keyword?: string;
  likely_cause: DeclineCause;
  confidence_percentage: number;
  business_explanation: string;
  technical_explanation: string;
  recommended_fix: string;
  priority: ImpactLevel;
  fix_owner: OwnerType;
  needs_expert_support: boolean;
}

export interface RefreshRecommendation extends SeoBaseRecord {
  page_performance_id: string;
  page_url: string;
  refresh_angle: string;
  what_to_update: string[];
  what_to_add: string[];
  what_to_remove: string[];
  suggested_cta_improvement?: string;
  use_content_studio: boolean;
}

export type PagePerformanceFilterKey =
  | "all"
  | "improving"
  | "stable"
  | "declining"
  | "needs_refresh"
  | "not_enough_data";
