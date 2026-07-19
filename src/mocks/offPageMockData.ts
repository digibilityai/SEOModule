import type { AuthorityCampaign, NewAuthorityCampaignInput, OffPageOpportunity, SeoWebsite } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const OPPORTUNITIES_KEY = "authority_opportunities";
const CAMPAIGNS_KEY = "authority_campaigns";

export const AUTHORITY_DATA_SOURCE_STATUS =
  "Mock authority data for local testing. Real backlink/mention/review tracking integration will come later.";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has seeded opportunities — siteB intentionally has none so the
// "no authority opportunities" empty state has something to demonstrate.
const seedOpportunities: OffPageOpportunity[] = [
  {
    id: "opp_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:00:00.000Z",
    updated_at: "2026-07-05T09:00:00.000Z",
    opportunity_type: "backlink",
    title: "Guest post on a local home services blog",
    source_platform: "AustinHomeServicesBlog.com",
    target_url: "https://www.austinhomeservicesblog.com",
    suggested_action: "Pitch a short guest post on drain maintenance tips with a link back to your services page.",
    why_it_matters: "A relevant, local guest post can build trust signals and send a small amount of referral traffic.",
    expected_authority_impact: "medium",
    effort: "medium",
    risk: "low",
    confidence_percentage: 68,
    requires_approval: true,
    fix_owner: "client_action",
    status: "suggested",
    spam_risk_flags: [],
  },
  {
    id: "opp_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:05:00.000Z",
    updated_at: "2026-07-05T09:05:00.000Z",
    opportunity_type: "backlink",
    title: "Directory offering paid backlink packages",
    source_platform: "cheap-links-directory.net",
    target_url: "https://cheap-links-directory.net",
    suggested_action: "Do not participate — this is a paid link scheme, not a genuine directory listing.",
    why_it_matters:
      "Paid, irrelevant links can trigger a search engine penalty instead of helping your rankings.",
    expected_authority_impact: "low",
    effort: "low",
    risk: "high",
    confidence_percentage: 91,
    requires_approval: true,
    fix_owner: "system_suggestion",
    status: "avoided",
    spam_risk_flags: ["paid_link_risk", "low_trust", "irrelevant_directory"],
  },
  {
    id: "opp_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:10:00.000Z",
    updated_at: "2026-07-05T09:10:00.000Z",
    opportunity_type: "mention",
    title: "Local news article mentions your business without a link",
    source_platform: "Austin Community News",
    target_url: "https://www.austincommunitynews.example/plumbing-tips",
    suggested_action: "Ask the publisher to add a link alongside the existing mention.",
    why_it_matters: "Turning an unlinked mention into a link is usually a quick, low-risk trust signal win.",
    expected_authority_impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 74,
    requires_approval: true,
    fix_owner: "client_action",
    status: "shortlisted",
    spam_risk_flags: [],
  },
  {
    id: "opp_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:15:00.000Z",
    updated_at: "2026-07-05T09:15:00.000Z",
    opportunity_type: "citation",
    title: "Business listing is missing on HomeAdvisor",
    source_platform: "HomeAdvisor",
    suggested_action: "Create or claim your HomeAdvisor business listing with matching name, address and phone.",
    why_it_matters: "Consistent citations across trusted directories reinforce your business as legitimate and local.",
    expected_authority_impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 82,
    requires_approval: false,
    fix_owner: "client_action",
    status: "shortlisted",
    spam_risk_flags: [],
  },
  {
    id: "opp_mock_005",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:20:00.000Z",
    updated_at: "2026-07-05T09:20:00.000Z",
    opportunity_type: "review",
    title: "Ask recent customers for Google reviews",
    source_platform: "Google Business Profile",
    suggested_action: "Send a review request link to your last 10 completed jobs.",
    why_it_matters: "More recent, genuine reviews improve trust and can influence local rankings.",
    expected_authority_impact: "high",
    effort: "low",
    risk: "low",
    confidence_percentage: 80,
    requires_approval: false,
    fix_owner: "client_action",
    status: "in_progress",
    spam_risk_flags: [],
  },
  {
    id: "opp_mock_006",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:25:00.000Z",
    updated_at: "2026-07-05T09:25:00.000Z",
    opportunity_type: "review",
    title: "Third-party service offering to \"boost\" your review count",
    source_platform: "reviewboost-service.example",
    suggested_action: "Do not use this service — reviews must come from real customers.",
    why_it_matters: "Fake reviews violate platform policies and can get your business profile suspended.",
    expected_authority_impact: "low",
    effort: "low",
    risk: "high",
    confidence_percentage: 93,
    requires_approval: true,
    fix_owner: "system_suggestion",
    status: "avoided",
    spam_risk_flags: ["fake_review_risk", "mass_outreach_risk"],
  },
  {
    id: "opp_mock_007",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:30:00.000Z",
    updated_at: "2026-07-05T09:30:00.000Z",
    opportunity_type: "pr",
    title: "Press release about your new emergency service line",
    source_platform: "Local PR wire",
    suggested_action: "Draft a short press release and route it through expert review before distribution.",
    why_it_matters: "A well-placed press release can earn coverage and a handful of relevant mentions.",
    expected_authority_impact: "medium",
    effort: "high",
    risk: "medium",
    confidence_percentage: 60,
    requires_approval: true,
    fix_owner: "digibility_expert",
    status: "expert_review_requested",
    spam_risk_flags: [],
  },
  {
    id: "opp_mock_008",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:35:00.000Z",
    updated_at: "2026-07-05T09:35:00.000Z",
    opportunity_type: "social_community",
    title: "Answer plumbing questions in a local Facebook community group",
    source_platform: "Facebook — Austin Homeowners Group",
    suggested_action: "Answer 2-3 genuine questions per month, mentioning your business only when relevant.",
    why_it_matters: "Helpful, non-spammy participation builds brand familiarity in the local community.",
    expected_authority_impact: "low",
    effort: "low",
    risk: "low",
    confidence_percentage: 65,
    requires_approval: false,
    fix_owner: "client_action",
    status: "suggested",
    spam_risk_flags: [],
  },
  {
    id: "opp_mock_009",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:40:00.000Z",
    updated_at: "2026-07-05T09:40:00.000Z",
    opportunity_type: "partnership",
    title: "Cross-promotion with a complementary local electrician",
    source_platform: "Direct partnership",
    suggested_action: "Propose linking to each other's site from a \"trusted partners\" page.",
    why_it_matters: "A relevant, reciprocal partnership link is a natural trust signal, not a link scheme.",
    expected_authority_impact: "low",
    effort: "low",
    risk: "low",
    confidence_percentage: 62,
    requires_approval: true,
    fix_owner: "client_action",
    status: "suggested",
    spam_risk_flags: [],
  },
];

const seedCampaigns: AuthorityCampaign[] = [
  {
    id: "cmp_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T10:00:00.000Z",
    updated_at: "2026-07-05T10:00:00.000Z",
    name: "Local Trust Building — Q3",
    goal: "Improve local trust signals and citation coverage",
    opportunity_ids: ["opp_mock_004", "opp_mock_005", "opp_mock_008"],
    tasks: [
      { id: "task_1", label: "Submit/update HomeAdvisor citation", is_complete: true },
      { id: "task_2", label: "Send review requests to last 10 customers", is_complete: false },
      { id: "task_3", label: "Post 2 helpful answers in the Facebook group", is_complete: false },
    ],
    approval_status: "approved",
    owner: "client_action",
    due_date: "2026-08-15",
    progress_percentage: 33,
  },
];

// Guards against stale localStorage from before the Phase 8 schema rewrite
// (old shape had no `spam_risk_flags` array).
export const mockOffPageOpportunities: OffPageOpportunity[] = loadMockCollection(
  OPPORTUNITIES_KEY,
  seedOpportunities,
  (item) => Array.isArray(item.spam_risk_flags),
);
export const mockAuthorityCampaigns: AuthorityCampaign[] = loadMockCollection(
  CAMPAIGNS_KEY,
  seedCampaigns,
);

function persistOpportunities(): void {
  saveMockCollection(OPPORTUNITIES_KEY, mockOffPageOpportunities);
}

function persistCampaigns(): void {
  saveMockCollection(CAMPAIGNS_KEY, mockAuthorityCampaigns);
}

export function listAuthorityOpportunities(websiteId: string): OffPageOpportunity[] {
  return mockOffPageOpportunities.filter((o) => o.website_id === websiteId);
}

export function getAuthorityOpportunityById(id: string): OffPageOpportunity | null {
  return mockOffPageOpportunities.find((o) => o.id === id) ?? null;
}

export function updateAuthorityOpportunityStatus(
  id: string,
  status: OffPageOpportunity["status"],
): OffPageOpportunity | null {
  const index = mockOffPageOpportunities.findIndex((o) => o.id === id);
  if (index === -1) return null;
  const updated: OffPageOpportunity = {
    ...mockOffPageOpportunities[index],
    status,
    updated_at: new Date().toISOString(),
  };
  mockOffPageOpportunities[index] = updated;
  persistOpportunities();
  return updated;
}

export function listAuthorityCampaigns(websiteId: string): AuthorityCampaign[] {
  return mockAuthorityCampaigns.filter((c) => c.website_id === websiteId);
}

// Phase 15D Step 2A: mirrors updateAuthorityOpportunityStatus's shape exactly,
// for the campaign side — keeps mock mode visibly equivalent to the real
// seo_authority_campaign_transition RPC for the same click. New addition;
// existing campaign functions (createAuthorityCampaign, listAuthorityCampaigns)
// are unchanged.
export function updateAuthorityCampaignStatus(
  id: string,
  approvalStatus: AuthorityCampaign["approval_status"],
): AuthorityCampaign | null {
  const index = mockAuthorityCampaigns.findIndex((c) => c.id === id);
  if (index === -1) return null;
  const updated: AuthorityCampaign = {
    ...mockAuthorityCampaigns[index],
    approval_status: approvalStatus,
    updated_at: new Date().toISOString(),
  };
  mockAuthorityCampaigns[index] = updated;
  persistCampaigns();
  return updated;
}

export function createAuthorityCampaign(
  website: SeoWebsite,
  input: NewAuthorityCampaignInput,
): AuthorityCampaign {
  const now = new Date().toISOString();
  const tasks = input.opportunity_ids
    .map((id) => getAuthorityOpportunityById(id))
    .filter((o): o is OffPageOpportunity => !!o)
    .map((o, index) => ({ id: `task_gen_${index + 1}`, label: o.suggested_action, is_complete: false }));

  const campaign: AuthorityCampaign = {
    id: `cmp_mock_${Date.now()}`,
    workspace_id: website.workspace_id,
    website_id: website.id,
    website_url: website.website_url,
    user_id: website.user_id,
    created_by: website.user_id,
    created_at: now,
    updated_at: now,
    name: input.name,
    goal: input.goal,
    opportunity_ids: input.opportunity_ids,
    tasks,
    approval_status: "pending_approval",
    owner: input.owner,
    due_date: input.due_date,
    progress_percentage: 0,
  };

  mockAuthorityCampaigns.push(campaign);
  persistCampaigns();
  return campaign;
}
