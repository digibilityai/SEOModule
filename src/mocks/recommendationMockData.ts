import type {
  ActionType,
  OwnerType,
  RecommendationArea,
  SeoIssue,
  SeoIssueCategory,
  SeoRecommendation,
  SeoWebsite,
} from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const STORAGE_KEY = "recommendations";

const [siteA, siteB] = MOCK_WEBSITES_CONTEXT;

const seedRecommendations: SeoRecommendation[] = [
  {
    id: "rec_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T10:00:00.000Z",
    updated_at: "2026-07-01T10:00:00.000Z",
    issue_id: "iss_mock_001",
    area: "technical",
    title: "Compress and lazy-load homepage hero image",
    suggested_change: "Compress hero image and enable lazy loading.",
    why_it_helps: "Reduces mobile load time, improving both visitor experience and search ranking.",
    action_type: "approval_required",
    impact: "high",
    effort: "medium",
    risk: "low",
    confidence_percentage: 85,
    status: "needs_review",
  },
  {
    id: "rec_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T10:00:00.000Z",
    updated_at: "2026-07-03T10:00:00.000Z",
    issue_id: "iss_mock_002",
    area: "technical",
    title: "Update robots.txt to unblock service pages",
    suggested_change: "Remove the disallow rule blocking /services so it can be indexed.",
    why_it_helps: "Lets search engines crawl and rank your service pages again.",
    action_type: "expert_review",
    impact: "high",
    effort: "low",
    risk: "medium",
    confidence_percentage: 87,
    status: "expert_review_requested",
  },
];

export const mockRecommendations: SeoRecommendation[] = loadMockCollection(
  STORAGE_KEY,
  seedRecommendations,
);

function persist(): void {
  saveMockCollection(STORAGE_KEY, mockRecommendations);
}

export function listRecommendations(websiteId: string): SeoRecommendation[] {
  return mockRecommendations.filter((r) => r.website_id === websiteId);
}

export function getRecommendationById(id: string): SeoRecommendation | null {
  return mockRecommendations.find((r) => r.id === id) ?? null;
}

const ON_PAGE_AREAS: RecommendationArea[] = [
  "title",
  "meta_description",
  "h1",
  "faq",
  "schema",
  "internal_links",
  "content",
];

export function listOnPageRecommendations(websiteId: string): SeoRecommendation[] {
  return listRecommendations(websiteId).filter((r) => ON_PAGE_AREAS.includes(r.area));
}

const CATEGORY_TO_AREA: Record<SeoIssueCategory, RecommendationArea> = {
  crawl: "technical",
  indexability: "technical",
  speed: "technical",
  mobile: "technical",
  schema: "schema",
  duplicate_content: "content",
  broken_links: "technical",
  sitemap: "technical",
  robots_txt: "technical",
  canonical: "technical",
  redirects: "technical",
};

const ACTION_TYPE_BY_FIX_OWNER: Record<OwnerType, ActionType> = {
  client_action: "manual_support",
  developer_needed: "approval_required",
  digibility_expert: "expert_review",
  system_suggestion: "auto_suggest",
};

function recommendationsFromIssues(issues: SeoIssue[]): SeoRecommendation[] {
  const now = new Date().toISOString();
  return issues.map((issue) => ({
    id: `rec_mock_${issue.id}`,
    workspace_id: issue.workspace_id,
    website_id: issue.website_id,
    website_url: issue.website_url,
    user_id: issue.user_id,
    created_by: issue.user_id,
    created_at: now,
    updated_at: now,
    issue_id: issue.id,
    area: CATEGORY_TO_AREA[issue.category],
    title: issue.title,
    suggested_change: issue.suggested_next_action,
    why_it_helps: issue.why_it_matters,
    action_type: ACTION_TYPE_BY_FIX_OWNER[issue.fix_owner],
    impact: issue.impact,
    effort: issue.effort,
    risk: issue.risk,
    confidence_percentage: issue.confidence_percentage,
    status: "suggested",
  }));
}

interface OnPageTemplate {
  area: RecommendationArea;
  title: string;
  current_value?: string;
  buildSuggestedChange: (website: SeoWebsite) => string;
  why_it_helps: string;
  action_type: ActionType;
  impact: SeoRecommendation["impact"];
  effort: SeoRecommendation["effort"];
  risk: SeoRecommendation["risk"];
  confidence_percentage: number;
}

const ON_PAGE_TEMPLATES: OnPageTemplate[] = [
  {
    area: "title",
    title: "Homepage title tag doesn't mention your service or location",
    current_value: "Home",
    buildSuggestedChange: (w) =>
      `${w.business_name} - ${w.industry ?? "Professional Services"}${w.target_location ? ` in ${w.target_location}` : ""}`,
    why_it_helps:
      "A descriptive title helps customers recognize your business in search results and can improve click-through rate.",
    action_type: "approval_required",
    impact: "high",
    effort: "low",
    risk: "low",
    confidence_percentage: 84,
  },
  {
    area: "meta_description",
    title: "Meta description is missing or generic",
    buildSuggestedChange: (w) =>
      `Looking for ${w.industry?.toLowerCase() ?? "trusted local services"}? ${w.business_name} offers reliable service${w.target_location ? ` in ${w.target_location}` : ""}. Contact us today.`,
    why_it_helps: "A clear meta description encourages more people to click through from search results.",
    action_type: "approval_required",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 80,
  },
  {
    area: "h1",
    title: "Homepage H1 is too generic",
    current_value: "Welcome",
    buildSuggestedChange: (w) => `${w.business_name}${w.target_location ? ` — Serving ${w.target_location}` : ""}`,
    why_it_helps: "Your H1 should tell visitors and search engines what the page is about at a glance.",
    action_type: "auto_suggest",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 82,
  },
  {
    area: "faq",
    title: "No FAQ section on key pages",
    buildSuggestedChange: () =>
      "Add an FAQ section answering the 4-5 questions customers ask most before booking.",
    why_it_helps:
      "FAQs can earn extra visibility in search results and address objections before customers call.",
    action_type: "manual_support",
    impact: "medium",
    effort: "medium",
    risk: "low",
    confidence_percentage: 70,
  },
  {
    area: "schema",
    title: "Business structured data is missing",
    current_value: "Not present",
    buildSuggestedChange: () => "Add LocalBusiness structured data with your name, address, phone and hours.",
    why_it_helps:
      "Structured data helps search engines display rich results like hours and reviews directly in search.",
    action_type: "auto_suggest",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 85,
  },
  {
    area: "internal_links",
    title: "Key pages aren't linked from the homepage or blog",
    buildSuggestedChange: () => "Link from your homepage and blog posts to your most important service pages.",
    why_it_helps: "Internal links help search engines find and prioritize your key pages.",
    action_type: "manual_support",
    impact: "low",
    effort: "low",
    risk: "low",
    confidence_percentage: 75,
  },
  {
    area: "content",
    title: "Service pages are thin on detail",
    buildSuggestedChange: () =>
      "Expand thin service pages with more detail on process, pricing range and what to expect.",
    why_it_helps: "More helpful, specific content tends to rank better and builds more trust with visitors.",
    action_type: "manual_support",
    impact: "medium",
    effort: "medium",
    risk: "low",
    confidence_percentage: 72,
  },
];

function onPageRecommendationsForWebsite(website: SeoWebsite): SeoRecommendation[] {
  const now = new Date().toISOString();
  return ON_PAGE_TEMPLATES.map((template, index) => ({
    id: `rec_mock_onpage_${website.id}_${index + 1}_${Date.now()}`,
    workspace_id: website.workspace_id,
    website_id: website.id,
    website_url: website.website_url,
    user_id: website.user_id,
    created_by: website.user_id,
    created_at: now,
    updated_at: now,
    area: template.area,
    title: template.title,
    current_value: template.current_value,
    suggested_change: template.buildSuggestedChange(website),
    why_it_helps: template.why_it_helps,
    action_type: template.action_type,
    impact: template.impact,
    effort: template.effort,
    risk: template.risk,
    confidence_percentage: template.confidence_percentage,
    status: "suggested",
  }));
}

// Replaces all recommendations for this website with a fresh set generated
// from the latest audit issues plus a standard on-page recommendation set.
export function regenerateRecommendationsForWebsite(
  website: SeoWebsite,
  issues: SeoIssue[],
): SeoRecommendation[] {
  const generated = [...recommendationsFromIssues(issues), ...onPageRecommendationsForWebsite(website)];
  const remaining = mockRecommendations.filter((r) => r.website_id !== website.id);
  mockRecommendations.length = 0;
  mockRecommendations.push(...remaining, ...generated);
  persist();
  return generated;
}
