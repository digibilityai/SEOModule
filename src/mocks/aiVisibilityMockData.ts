import type {
  AiContentGap,
  BrandMentionSummary,
  CompetitorMentionSummary,
  PromptTrackingRecord,
} from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const PROMPTS_KEY = "ai_prompt_tracking";
const CONTENT_GAPS_KEY = "ai_content_gaps";

export const AI_VISIBILITY_DATA_SOURCE_STATUS =
  "Mock AI visibility data for local testing. Real AI answer tracking will come later.";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has seeded AI visibility data — siteB intentionally has none so
// the "no AI visibility records yet" empty state has something to demonstrate.
const seedPromptTracking: PromptTrackingRecord[] = [
  {
    id: "prm_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:00:00.000Z",
    updated_at: "2026-07-05T11:00:00.000Z",
    prompt_text: "Who is the best emergency plumber in Austin?",
    topic: "Local service search",
    brand_mentioned: false,
    competitors_mentioned: ["QuickFix Plumbing", "Austin Rapid Plumbers"],
    citation_sources: ["Yelp", "Google Business Profile", "Angi"],
    our_site_cited: false,
    visibility_status: "not_visible",
    gap_summary: "The AI answer only cited competitors with more reviews and clearer FAQ content.",
    recommended_next_step: "Add more Google reviews and a clear FAQ section to your homepage.",
  },
  {
    id: "prm_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:05:00.000Z",
    updated_at: "2026-07-05T11:05:00.000Z",
    prompt_text: "How much does drain cleaning cost?",
    topic: "Pricing question",
    brand_mentioned: true,
    competitors_mentioned: ["QuickFix Plumbing"],
    citation_sources: [`${siteA.website_url}/services/drain-cleaning`, "QuickFix Plumbing site"],
    our_site_cited: true,
    visibility_status: "partially_visible",
    gap_summary: "Your page was mentioned but without a price range — the competitor listed clearer numbers.",
    recommended_next_step: "Add a clear price range to your drain cleaning page.",
  },
  {
    id: "prm_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:10:00.000Z",
    updated_at: "2026-07-05T11:10:00.000Z",
    prompt_text: "Is there a 24 hour plumber near me?",
    topic: "Urgency search",
    brand_mentioned: true,
    competitors_mentioned: [],
    citation_sources: [`${siteA.website_url}/`],
    our_site_cited: true,
    visibility_status: "visible",
    gap_summary: "Your homepage is being cited as a strong match for this question.",
    recommended_next_step: "Keep this page's content current so this holds.",
  },
  {
    id: "prm_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:15:00.000Z",
    updated_at: "2026-07-05T11:15:00.000Z",
    prompt_text: "Should I repair or replace my water heater?",
    topic: "Informational",
    brand_mentioned: false,
    competitors_mentioned: [],
    citation_sources: ["generic-home-tips.example"],
    our_site_cited: false,
    visibility_status: "unknown",
    gap_summary: "No clear answer source is being cited yet for this question — a content gap.",
    recommended_next_step: "Publish a simple guide comparing repair vs. replacement.",
  },
];

const seedContentGaps: AiContentGap[] = [
  {
    id: "gap_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:20:00.000Z",
    updated_at: "2026-07-05T11:20:00.000Z",
    topic: "Drain cleaning pricing",
    missing_answer_angle: "No clear price range is publicly listed on your site.",
    suggested_content_type: "Pricing guide / FAQ block",
    related_keyword_or_question: "how much does drain cleaning cost",
    priority: "high",
    recommended_next_action: "Add a transparent price range and FAQ to the drain cleaning page.",
  },
  {
    id: "gap_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:25:00.000Z",
    updated_at: "2026-07-05T11:25:00.000Z",
    topic: "Water heater repair vs. replace",
    missing_answer_angle: "No direct comparison content exists on your site.",
    suggested_content_type: "Comparison blog post",
    related_keyword_or_question: "water heater repair vs replace",
    priority: "medium",
    recommended_next_action: "Publish a short guide comparing repair vs. replacement cost and lifespan.",
  },
  {
    id: "gap_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T11:30:00.000Z",
    updated_at: "2026-07-05T11:30:00.000Z",
    topic: "Emergency plumber trust signals",
    missing_answer_angle: "AI tools favor sources that clearly show reviews and credentials.",
    suggested_content_type: "Trust/About content plus review widget",
    related_keyword_or_question: "best emergency plumber in Austin",
    priority: "high",
    recommended_next_action: "Highlight licensing, years in business and reviews prominently on your homepage.",
  },
];

// Guards against stale localStorage from before the Phase 8 schema rewrite
// (old shape had no `competitors_mentioned` array).
export const mockPromptTracking: PromptTrackingRecord[] = loadMockCollection(
  PROMPTS_KEY,
  seedPromptTracking,
  (item) => Array.isArray(item.competitors_mentioned),
);
export const mockAiContentGaps: AiContentGap[] = loadMockCollection(CONTENT_GAPS_KEY, seedContentGaps);

function persistPromptTracking(): void {
  saveMockCollection(PROMPTS_KEY, mockPromptTracking);
}

export function listPromptTracking(websiteId: string): PromptTrackingRecord[] {
  return mockPromptTracking.filter((p) => p.website_id === websiteId);
}

export function updatePromptTrackingStatus(
  id: string,
  visibility_status: PromptTrackingRecord["visibility_status"],
): PromptTrackingRecord | null {
  const index = mockPromptTracking.findIndex((p) => p.id === id);
  if (index === -1) return null;
  const updated: PromptTrackingRecord = {
    ...mockPromptTracking[index],
    visibility_status,
    updated_at: new Date().toISOString(),
  };
  mockPromptTracking[index] = updated;
  persistPromptTracking();
  return updated;
}

export function listAiContentGaps(websiteId: string): AiContentGap[] {
  return mockAiContentGaps.filter((g) => g.website_id === websiteId);
}

// Derived summaries — computed from the prompt tracking records above rather
// than stored as their own collection, since they're just aggregate views
// over data that's already persisted.
export function buildBrandMentionSummary(websiteId: string, websiteUrl: string): BrandMentionSummary {
  const prompts = listPromptTracking(websiteId);
  const mentionCount = prompts.filter((p) => p.brand_mentioned).length;

  return {
    website_id: websiteId,
    website_url: websiteUrl,
    total_prompts_tracked: prompts.length,
    brand_mention_count: mentionCount,
    mention_rate_percentage: prompts.length > 0 ? (mentionCount / prompts.length) * 100 : 0,
    where_brand_appears: prompts
      .filter((p) => p.brand_mentioned)
      .map((p) => `"${p.prompt_text}" (${p.visibility_status.replace("_", " ")})`),
  };
}

export function buildCompetitorMentionSummaries(
  websiteId: string,
  websiteUrl: string,
): CompetitorMentionSummary[] {
  const prompts = listPromptTracking(websiteId);
  const byCompetitor = new Map<string, PromptTrackingRecord[]>();

  prompts.forEach((p) => {
    p.competitors_mentioned.forEach((name) => {
      const existing = byCompetitor.get(name) ?? [];
      existing.push(p);
      byCompetitor.set(name, existing);
    });
  });

  return Array.from(byCompetitor.entries()).map(([competitor_name, records]) => ({
    website_id: websiteId,
    website_url: websiteUrl,
    competitor_name,
    mention_count: records.length,
    where_competitor_appears: records.map((r) => `"${r.prompt_text}"`),
    what_competitor_does_better: records[0]?.gap_summary ?? "Appears more consistently for this topic.",
    recommended_next_step:
      records[0]?.recommended_next_step ??
      "Strengthen your content and trust signals on this topic to close the gap.",
  }));
}

// A small, generic starter set used when a website has no AI visibility data
// yet. Deliberately simple — real AI answer tracking will replace this
// generator later.
export function generateAiVisibilityDataForWebsite(
  websiteId: string,
  workspaceId: string,
  websiteUrl: string,
  userId: string,
  businessName: string,
): PromptTrackingRecord[] {
  const existing = listPromptTracking(websiteId);
  if (existing.length > 0) return existing;

  const now = new Date().toISOString();
  const generated: PromptTrackingRecord[] = [
    {
      id: `prm_mock_gen_${websiteId}_1`,
      workspace_id: workspaceId,
      website_id: websiteId,
      website_url: websiteUrl,
      user_id: userId,
      created_by: userId,
      created_at: now,
      updated_at: now,
      prompt_text: `Who is a good option for ${businessName.toLowerCase()}?`,
      topic: "Brand awareness",
      brand_mentioned: false,
      competitors_mentioned: [],
      citation_sources: [],
      our_site_cited: false,
      visibility_status: "unknown",
      gap_summary: "Not enough tracked prompts yet to know how this business appears in AI answers.",
      recommended_next_step: "Track a few more prompts related to your core services.",
    },
  ];

  mockPromptTracking.push(...generated);
  persistPromptTracking();
  return generated;
}
