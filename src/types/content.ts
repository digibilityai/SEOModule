import type { SeoBaseRecord } from "./common";
import type { SeoUserRole } from "./role";

export type SearchIntent = "informational" | "navigational" | "transactional" | "commercial";
export type FunnelStage = "awareness" | "consideration" | "conversion";
export type ContentDifficulty = "low" | "medium" | "high";

export type ContentWorkflowStatus =
  | "idea_suggested"
  | "plan_started"
  | "keyword_plan_ready"
  | "wireframe_ready"
  | "wireframe_approved"
  | "draft_ready"
  | "draft_in_review"
  | "draft_approved"
  | "expert_review_requested"
  | "ready_for_publish"
  | "completed"
  | "rejected";

export interface ContentFeedbackComment {
  id: string;
  author_role: SeoUserRole;
  comment_text: string;
  created_at: string;
}

export interface ContentOpportunity extends SeoBaseRecord {
  title: string;
  target_keyword: string;
  search_intent: SearchIntent;
  funnel_stage: FunnelStage;
  difficulty: ContentDifficulty;
  opportunity_score: number;
  reason: string;
  is_custom: boolean;
  status: ContentWorkflowStatus;
  comments: ContentFeedbackComment[];
}

export type NewCustomContentOpportunityInput = Pick<ContentOpportunity, "title" | "target_keyword">;

export interface KeywordPlan extends SeoBaseRecord {
  content_opportunity_id: string;
  primary_keyword: string;
  secondary_keywords: string[];
  semantic_keywords: string[];
  question_keywords: string[];
  intent: SearchIntent;
  difficulty: ContentDifficulty;
  business_relevance: string;
  why_it_matters: string;
}

export interface CompetitorContentSummary extends SeoBaseRecord {
  content_opportunity_id: string;
  competitor_title: string;
  competitor_url: string;
  what_they_covered: string;
  what_they_missed: string;
  our_opportunity: string;
  content_gap_angle: string;
}

export interface ContentWireframe extends SeoBaseRecord {
  content_opportunity_id: string;
  suggested_h1: string;
  intro_angle: string;
  section_outline: string[];
  faq_section: string[];
  cta_suggestion: string;
  internal_link_suggestions: string[];
  schema_suggestion?: string;
  is_approved: boolean;
  approved_at?: string;
}

export type ContentFormatType =
  | "default"
  | "url_reference"
  | "file_reference"
  | "match_brand_style"
  | "custom_instructions";

export interface ContentFormatInput extends SeoBaseRecord {
  content_opportunity_id: string;
  format_type: ContentFormatType;
  reference_url?: string;
  // Filename/metadata only — file contents are never processed in this phase.
  uploaded_file_name?: string;
  custom_instructions?: string;
}

export type DraftSectionStatus = "generated" | "approved" | "rejected" | "edited";
// "regenerate" is handled by its own dedicated regenerateDraftSection
// function/service, not this generic action set.
export type DraftSectionAction = "approve" | "reject" | "edit";

export interface DraftSection {
  id: string;
  heading: string;
  content: string;
  status: DraftSectionStatus;
  regeneration_count: number;
  updated_at: string;
}

export interface ContentDraft extends SeoBaseRecord {
  content_opportunity_id: string;
  title: string;
  sections: DraftSection[];
}
