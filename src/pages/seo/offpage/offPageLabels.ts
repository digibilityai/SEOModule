import type { OffPageOpportunityStatus, OffPageOpportunityType, OwnerType, SpamRiskFlag } from "@/types";

export const OPPORTUNITY_TYPE_LABEL: Record<OffPageOpportunityType, string> = {
  backlink: "Backlink",
  mention: "Brand mention",
  citation: "Citation",
  review: "Review",
  pr: "PR",
  social_community: "Social/community",
  partnership: "Partnership",
};

export const OFFPAGE_FILTERS: { key: "all" | OffPageOpportunityType; label: string }[] = [
  { key: "all", label: "All opportunities" },
  { key: "backlink", label: "Backlink" },
  { key: "mention", label: "Brand mention" },
  { key: "citation", label: "Citation" },
  { key: "review", label: "Review" },
  { key: "pr", label: "PR" },
  { key: "social_community", label: "Social/community" },
  { key: "partnership", label: "Partnership" },
];

export const OPPORTUNITY_STATUS_LABEL: Record<OffPageOpportunityStatus, string> = {
  suggested: "Suggested",
  shortlisted: "Shortlisted",
  approval_required: "Approval required",
  in_progress: "In progress",
  expert_review_requested: "Expert review requested",
  completed: "Completed",
  rejected: "Rejected",
  avoided: "Avoided",
};

export const OPPORTUNITY_STATUS_VARIANT: Record<
  OffPageOpportunityStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  suggested: "outline",
  shortlisted: "secondary",
  approval_required: "secondary",
  in_progress: "default",
  expert_review_requested: "secondary",
  completed: "default",
  rejected: "destructive",
  avoided: "destructive",
};

export const SPAM_FLAG_LABEL: Record<SpamRiskFlag, string> = {
  paid_link_risk: "Paid link risk",
  irrelevant_directory: "Irrelevant directory",
  pbn_like_site: "PBN-like site",
  exact_match_anchor_manipulation: "Exact-match anchor manipulation",
  fake_review_risk: "Fake review risk",
  mass_outreach_risk: "Mass outreach risk",
  low_relevance: "Low relevance",
  low_trust: "Low trust",
};

export const FIX_OWNER_LABEL: Record<OwnerType, string> = {
  client_action: "Client action",
  developer_needed: "Developer needed",
  digibility_expert: "Digibility expert",
  system_suggestion: "System suggestion",
};
