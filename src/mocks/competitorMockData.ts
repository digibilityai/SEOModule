import type { Competitor } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const COMPETITORS_KEY = "competitors";

export const COMPETITOR_DATA_SOURCE_STATUS =
  "Mock competitor benchmarking data for local testing. Real competitor analysis integrations will come later.";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has seeded competitor benchmark data — siteB intentionally has
// none so the "no benchmark data" / "no competitors added" empty states have
// something to demonstrate.
const seedCompetitors: Competitor[] = [
  {
    id: "cmp_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-06T09:00:00.000Z",
    updated_at: "2026-07-06T09:00:00.000Z",
    competitor_name: "QuickFix Plumbing Co",
    competitor_url: "https://www.quickfixplumbing.com",
    business_category: "Plumbing services",
    target_location: "Austin, TX",
    content_strength_score: 65,
    technical_health_score: 78,
    authority_score: 60,
    ai_visibility_score: 40,
    review_strength_score: 88,
    overall_strength_score: 66,
    status: "stronger",
    what_they_do_better: [
      "More Google reviews and higher review volume",
      "Deeper, more detailed service pages",
    ],
    what_they_are_missing: [
      "Weaker technical health / mobile speed",
      "Low AI visibility — rarely cited in AI answers",
    ],
    content_opportunities: [
      "Publish a more detailed drain cleaning guide with pricing",
      "Add a local FAQ section to top service pages",
    ],
    authority_opportunities: [
      "Match their review request cadence",
      "Pursue a similar local citation footprint",
    ],
    ai_visibility_opportunities: [
      "Add clear pricing and trust signals so AI tools are more likely to cite you",
    ],
    suggested_next_action:
      "Focus on closing the review-count gap and adding pricing detail to your top service pages.",
  },
  {
    id: "cmp_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-06T09:00:00.000Z",
    updated_at: "2026-07-06T09:00:00.000Z",
    competitor_name: "Austin Rapid Plumbers",
    competitor_url: "https://www.austinrapidplumbers.example",
    business_category: "Plumbing services",
    target_location: "Austin, TX",
    content_strength_score: 55,
    technical_health_score: 60,
    authority_score: 50,
    ai_visibility_score: 58,
    review_strength_score: 62,
    overall_strength_score: 57,
    status: "similar",
    what_they_do_better: ["Structured FAQ content that AI answer engines can quote directly"],
    what_they_are_missing: ["Fewer reviews than average", "Thinner service page content"],
    content_opportunities: ["Add clear FAQ blocks to your top service pages"],
    authority_opportunities: ["No major authority advantage here — low risk to compete"],
    ai_visibility_opportunities: [
      "Structure content in question-and-answer format to compete for AI citations",
    ],
    suggested_next_action:
      "Add structured FAQ content to compete for the same AI visibility this competitor is winning.",
  },
];

// Guards against stale localStorage from before the Phase 9 schema rewrite
// (old CompetitorSnapshot shape had no `what_they_do_better` array).
export const mockCompetitors: Competitor[] = loadMockCollection(
  COMPETITORS_KEY,
  seedCompetitors,
  (item) => Array.isArray(item.what_they_do_better),
);

function persist(): void {
  saveMockCollection(COMPETITORS_KEY, mockCompetitors);
}

export function listCompetitors(websiteId: string): Competitor[] {
  return mockCompetitors.filter((c) => c.website_id === websiteId);
}

export function getCompetitorById(id: string): Competitor | null {
  return mockCompetitors.find((c) => c.id === id) ?? null;
}

function hashStringToRange(value: string, min: number, max: number): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.charCodeAt(i)) % 1000;
  }
  return min + (hash % (max - min));
}

function clampScore(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)));
}

// Deterministic-ish mock scoring so a given competitor URL always lands in a
// plausible range, with a small nudge on regenerate — real competitor
// analysis integrations will replace this entirely.
function scoreForCompetitor(url: string, dimension: string, previous?: number): number {
  if (previous !== undefined) {
    return clampScore(previous + (Math.random() * 10 - 5));
  }
  return clampScore(hashStringToRange(`${url}:${dimension}`, 35, 90));
}

export function generateCompetitorBenchmarkData(
  websiteId: string,
  workspaceId: string,
  websiteUrl: string,
  userId: string,
  competitorUrls: string[],
): Competitor[] {
  const now = new Date().toISOString();
  const existingForWebsite = listCompetitors(websiteId);

  const updated: Competitor[] = competitorUrls.map((url) => {
    const existing = existingForWebsite.find((c) => c.competitor_url === url);

    const content_strength_score = scoreForCompetitor(url, "content", existing?.content_strength_score);
    const technical_health_score = scoreForCompetitor(url, "technical", existing?.technical_health_score);
    const authority_score = scoreForCompetitor(url, "authority", existing?.authority_score);
    const ai_visibility_score = scoreForCompetitor(url, "ai", existing?.ai_visibility_score);
    const review_strength_score = scoreForCompetitor(url, "review", existing?.review_strength_score);
    const overall_strength_score = clampScore(
      (content_strength_score + technical_health_score + authority_score + ai_visibility_score + review_strength_score) /
        5,
    );

    let hostname = url;
    try {
      hostname = new URL(url).hostname.replace("www.", "");
    } catch {
      // Not a full URL — fall back to the raw string as the display name.
    }

    return {
      id: existing?.id ?? `cmp_mock_gen_${websiteId}_${hostname}`,
      workspace_id: workspaceId,
      website_id: websiteId,
      website_url: websiteUrl,
      user_id: userId,
      created_by: userId,
      created_at: existing?.created_at ?? now,
      updated_at: now,
      competitor_name: existing?.competitor_name ?? hostname,
      competitor_url: url,
      business_category: existing?.business_category ?? "General business",
      target_location: existing?.target_location,
      content_strength_score,
      technical_health_score,
      authority_score,
      ai_visibility_score,
      review_strength_score,
      overall_strength_score,
      status: existing?.status ?? "unknown",
      what_they_do_better: existing?.what_they_do_better ?? [
        "Not enough data yet to know specifics — check back after the next benchmark refresh.",
      ],
      what_they_are_missing: existing?.what_they_are_missing ?? [],
      content_opportunities: existing?.content_opportunities ?? [],
      authority_opportunities: existing?.authority_opportunities ?? [],
      ai_visibility_opportunities: existing?.ai_visibility_opportunities ?? [],
      suggested_next_action:
        existing?.suggested_next_action ?? "Review this competitor's strengths once more data is available.",
    };
  });

  const remaining = mockCompetitors.filter((c) => c.website_id !== websiteId);
  mockCompetitors.length = 0;
  mockCompetitors.push(...remaining, ...updated);
  persist();
  return updated;
}

// Recomputes each competitor's status relative to our overall score — called
// after generation, once the caller has our audit-derived score in hand.
export function applyCompetitorStrengthStatus(websiteId: string, ourOverallScore: number): Competitor[] {
  mockCompetitors.forEach((c, index) => {
    if (c.website_id !== websiteId) return;
    const diff = c.overall_strength_score - ourOverallScore;
    const status: Competitor["status"] = diff > 5 ? "stronger" : diff < -5 ? "weaker" : "similar";
    mockCompetitors[index] = { ...c, status };
  });
  persist();
  return listCompetitors(websiteId);
}
