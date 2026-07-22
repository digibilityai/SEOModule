import type { SeoBaseRecord, ImpactLevel, OwnerType, RelatedModule } from "./common";

export type CompetitorStrengthStatus = "stronger" | "similar" | "weaker" | "unknown";

export interface Competitor extends SeoBaseRecord {
  competitor_name: string;
  competitor_url: string;
  business_category: string;
  target_location?: string;
  content_strength_score: number;
  technical_health_score: number;
  authority_score: number;
  ai_visibility_score: number;
  review_strength_score: number;
  overall_strength_score: number;
  status: CompetitorStrengthStatus;
  what_they_do_better: string[];
  what_they_are_missing: string[];
  content_opportunities: string[];
  authority_opportunities: string[];
  ai_visibility_opportunities: string[];
  suggested_next_action: string;
  // Optional source provenance for persisted (Supabase) competitor rows.
  // Always "estimated" today — these scores are heuristic estimates, never
  // externally measured data. Absent on mock rows. (Competitor Stage 1.)
  data_provenance?: string;
  generation_method?: string;
}

export type BenchmarkDimension =
  | "technical_health"
  | "content_depth"
  | "keyword_coverage"
  | "authority_signals"
  | "reviews_trust"
  | "ai_visibility"
  | "page_quality"
  | "local_visibility";

export type GapLevel = "low" | "medium" | "high";

export interface BenchmarkComparison {
  dimension: BenchmarkDimension;
  label: string;
  our_score: number;
  competitor_average: number;
  strongest_competitor_name: string;
  strongest_competitor_score: number;
  gap_level: GapLevel;
  explanation: string;
  recommended_next_step: string;
}

export type CompetitorGapType =
  | "missing_content_topics"
  | "weak_page_types"
  | "weak_keyword_coverage"
  | "low_authority_signals"
  | "review_trust_gap"
  | "ai_visibility_gap"
  | "technical_disadvantage";

export interface CompetitorGap extends SeoBaseRecord {
  gap_type: CompetitorGapType;
  title: string;
  why_it_matters: string;
  recommended_action: string;
  priority: ImpactLevel;
  suggested_owner: OwnerType;
  related_module: RelatedModule;
}

export interface CompetitorOverview {
  website_id: string;
  website_url: string;
  competitor_count: number;
  benchmark_score: number;
  last_updated: string | null;
  data_source_status: string;
}
