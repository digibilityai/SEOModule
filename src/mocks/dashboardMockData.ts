import type { RecentActivityItem, TopPriorityFix } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const RECENT_ACTIVITY_KEY = "recent_activity";

const [siteA, siteB] = MOCK_WEBSITES_CONTEXT;

export const mockTopPriorityFixes: TopPriorityFix[] = [
  {
    id: "fix_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T10:00:00.000Z",
    updated_at: "2026-07-01T10:00:00.000Z",
    title: "Speed up your homepage on mobile",
    simple_explanation:
      "Your homepage loads slowly on phones, which can lose visitors before they even see your services.",
    impact: "high",
    effort: "medium",
    risk: "low",
    confidence_percentage: 88,
    recommended_next_action: "Approve the image-compression fix so it can be applied.",
    action_type: "approval_required",
    status: "open",
    source_issue_id: "iss_mock_001",
    source_recommendation_id: "rec_mock_001",
  },
  {
    id: "fix_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T10:05:00.000Z",
    updated_at: "2026-07-01T10:05:00.000Z",
    title: "Fix duplicate page titles on service pages",
    simple_explanation:
      "Several service pages share the same title, which confuses search engines about which page to show.",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 76,
    recommended_next_action: "Review the suggested unique titles and publish them.",
    action_type: "auto_suggest",
    status: "open",
  },
  {
    id: "fix_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T10:10:00.000Z",
    updated_at: "2026-07-01T10:10:00.000Z",
    title: "Keep your drain cleaning page live",
    simple_explanation:
      "This page already ranks well. Removing or merging it would lose the rankings it has built.",
    impact: "high",
    effort: "low",
    risk: "high",
    confidence_percentage: 81,
    recommended_next_action: "Do not delete or redirect this page.",
    action_type: "avoid",
    status: "open",
  },
  {
    id: "fix_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T10:00:00.000Z",
    updated_at: "2026-07-03T10:00:00.000Z",
    title: "Unblock your services pages from search engines",
    simple_explanation:
      "Your robots.txt file is currently hiding key service pages from Google.",
    impact: "high",
    effort: "low",
    risk: "medium",
    confidence_percentage: 82,
    recommended_next_action: "Request expert review before editing robots.txt.",
    action_type: "expert_review",
    status: "open",
    source_issue_id: "iss_mock_002",
    source_recommendation_id: "rec_mock_002",
  },
  {
    id: "fix_mock_005",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T10:05:00.000Z",
    updated_at: "2026-07-03T10:05:00.000Z",
    title: "Add patient reviews and certifications",
    simple_explanation:
      "Trust signals are thin on your site. More reviews and credentials help both patients and search engines trust you.",
    impact: "medium",
    effort: "medium",
    risk: "low",
    confidence_percentage: 68,
    recommended_next_action: "Work with your team to gather and add 5 recent patient reviews.",
    action_type: "manual_support",
    status: "open",
  },
];

const seedRecentActivity: RecentActivityItem[] = [
  {
    id: "act_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-06-01T09:00:00.000Z",
    updated_at: "2026-06-01T09:00:00.000Z",
    activity_type: "website_added",
    summary: "Website added: Acme Plumbing",
    occurred_at: "2026-06-01T09:00:00.000Z",
  },
  {
    id: "act_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-06-02T09:30:00.000Z",
    updated_at: "2026-06-02T09:30:00.000Z",
    activity_type: "onboarding_completed",
    summary: "Business onboarding completed",
    occurred_at: "2026-06-02T09:30:00.000Z",
  },
  {
    id: "act_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T09:45:00.000Z",
    updated_at: "2026-07-01T09:45:00.000Z",
    activity_type: "audit_completed",
    summary: "Monthly SEO audit completed",
    occurred_at: "2026-07-01T09:45:00.000Z",
  },
  {
    id: "act_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T10:00:00.000Z",
    updated_at: "2026-07-01T10:00:00.000Z",
    activity_type: "recommendation_generated",
    summary: "New recommendation: compress and lazy-load homepage hero image",
    occurred_at: "2026-07-01T10:00:00.000Z",
  },
  {
    id: "act_mock_005",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:00:00.000Z",
    updated_at: "2026-07-05T09:00:00.000Z",
    activity_type: "report_generated",
    summary: "June progress report generated",
    occurred_at: "2026-07-05T09:00:00.000Z",
  },
  {
    id: "act_mock_006",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T09:40:00.000Z",
    updated_at: "2026-07-03T09:40:00.000Z",
    activity_type: "audit_completed",
    summary: "Weekly SEO audit completed",
    occurred_at: "2026-07-03T09:40:00.000Z",
  },
];

export const mockRecentActivity: RecentActivityItem[] = loadMockCollection(
  RECENT_ACTIVITY_KEY,
  seedRecentActivity,
);

function persistRecentActivity(): void {
  saveMockCollection(RECENT_ACTIVITY_KEY, mockRecentActivity);
}

export function listTopPriorityFixes(websiteId: string): TopPriorityFix[] {
  return mockTopPriorityFixes.filter((f) => f.website_id === websiteId);
}

export function listRecentActivity(websiteId: string): RecentActivityItem[] {
  return mockRecentActivity.filter((a) => a.website_id === websiteId);
}

export function addRecentActivity(
  entry: Pick<
    RecentActivityItem,
    "workspace_id" | "website_id" | "website_url" | "user_id" | "activity_type" | "summary"
  >,
): RecentActivityItem {
  const now = new Date().toISOString();
  const item: RecentActivityItem = {
    id: `act_mock_${Date.now()}`,
    created_by: entry.user_id,
    created_at: now,
    updated_at: now,
    occurred_at: now,
    ...entry,
  };
  mockRecentActivity.push(item);
  persistRecentActivity();
  return item;
}
