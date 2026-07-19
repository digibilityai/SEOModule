import type { SeoBaseRecord, ImpactLevel } from "./common";

export type PromptVisibilityStatus = "visible" | "partially_visible" | "not_visible" | "unknown";

export interface PromptTrackingRecord extends SeoBaseRecord {
  prompt_text: string;
  topic: string;
  brand_mentioned: boolean;
  competitors_mentioned: string[];
  citation_sources: string[];
  our_site_cited: boolean;
  visibility_status: PromptVisibilityStatus;
  gap_summary: string;
  recommended_next_step: string;
}

export interface BrandMentionSummary {
  website_id: string;
  website_url: string;
  total_prompts_tracked: number;
  brand_mention_count: number;
  mention_rate_percentage: number;
  where_brand_appears: string[];
}

export interface CompetitorMentionSummary {
  website_id: string;
  website_url: string;
  competitor_name: string;
  mention_count: number;
  where_competitor_appears: string[];
  what_competitor_does_better: string;
  recommended_next_step: string;
}

export interface AiContentGap extends SeoBaseRecord {
  topic: string;
  missing_answer_angle: string;
  suggested_content_type: string;
  related_keyword_or_question: string;
  priority: ImpactLevel;
  recommended_next_action: string;
}

export interface AiVisibilityOverview {
  website_id: string;
  website_url: string;
  ai_discovery_score: number;
  brand_mention_count: number;
  competitor_mention_count: number;
  citation_gap_count: number;
  content_gap_count: number;
  prompt_tracking_status: string;
  data_source_status: string;
}
