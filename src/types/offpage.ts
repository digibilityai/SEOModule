import type { SeoBaseRecord, ImpactLevel, EffortLevel, RiskLevel, OwnerType } from "./common";

export type OffPageOpportunityType =
  | "backlink"
  | "mention"
  | "citation"
  | "review"
  | "pr"
  | "social_community"
  | "partnership";

export type OffPageOpportunityStatus =
  | "suggested"
  | "shortlisted"
  | "approval_required"
  | "in_progress"
  | "expert_review_requested"
  | "completed"
  | "rejected"
  | "avoided";

export type SpamRiskFlag =
  | "paid_link_risk"
  | "irrelevant_directory"
  | "pbn_like_site"
  | "exact_match_anchor_manipulation"
  | "fake_review_risk"
  | "mass_outreach_risk"
  | "low_relevance"
  | "low_trust";

export interface OffPageOpportunity extends SeoBaseRecord {
  opportunity_type: OffPageOpportunityType;
  title: string;
  source_platform: string;
  target_url?: string;
  suggested_action: string;
  why_it_matters: string;
  expected_authority_impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  requires_approval: boolean;
  fix_owner: OwnerType;
  status: OffPageOpportunityStatus;
  spam_risk_flags: SpamRiskFlag[];
}

export interface SpamRiskReview {
  opportunity_id: string;
  opportunity_title: string;
  flags: SpamRiskFlag[];
  risk_level: RiskLevel;
  recommended_action: "avoid" | "expert_review";
  explanation: string;
}

export interface AuthorityOverview {
  website_id: string;
  website_url: string;
  authority_score: number;
  trust_signal_summary: string;
  opportunity_count: number;
  campaign_count: number;
  high_risk_count: number;
  data_source_status: string;
}

export type CampaignApprovalStatus = "draft" | "pending_approval" | "approved" | "rejected";

export interface CampaignTask {
  id: string;
  label: string;
  is_complete: boolean;
}

export interface AuthorityCampaign extends SeoBaseRecord {
  name: string;
  goal: string;
  opportunity_ids: string[];
  tasks: CampaignTask[];
  approval_status: CampaignApprovalStatus;
  owner: OwnerType;
  due_date?: string;
  progress_percentage: number;
}

export type OffPageFilterKey = "all" | OffPageOpportunityType;

export interface NewAuthorityCampaignInput {
  name: string;
  goal: string;
  opportunity_ids: string[];
  owner: OwnerType;
  due_date?: string;
}
