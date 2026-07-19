import type { RoadmapItem, SeoWebsite } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const ROADMAP_KEY = "roadmap_items";

const [siteA] = MOCK_WEBSITES_CONTEXT;

function weekToDuePeriod(week: number): RoadmapItem["due_period"] {
  return `week_${week}` as RoadmapItem["due_period"];
}

// Only siteA has a seeded roadmap — siteB intentionally has none so the "no
// roadmap yet" empty state has something to demonstrate.
const seedRoadmapItems: RoadmapItem[] = [
  {
    id: "rmp_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-06T09:00:00.000Z",
    updated_at: "2026-07-06T09:00:00.000Z",
    week_number: 1,
    month_number: 1,
    due_period: weekToDuePeriod(1),
    title: "Fix homepage mobile speed",
    explanation: "Compress the hero image and enable lazy loading so mobile visitors don't bounce before the page loads.",
    related_module: "audit",
    source: "audit_issue",
    priority: "high",
    expected_impact: "high",
    effort: "medium",
    risk: "low",
    owner: "developer_needed",
    status: "planned",
  },
];

// Guards against stale localStorage from before the Phase 9 schema rewrite
// (old shape had no `related_module` field or `due_period`).
export const mockRoadmapItems: RoadmapItem[] = loadMockCollection(
  ROADMAP_KEY,
  seedRoadmapItems,
  (item) => typeof item.related_module === "string" && typeof item.due_period === "string",
);

function persist(): void {
  saveMockCollection(ROADMAP_KEY, mockRoadmapItems);
}

export function listRoadmapItems(websiteId: string): RoadmapItem[] {
  return mockRoadmapItems.filter((r) => r.website_id === websiteId);
}

export function getRoadmapItemById(id: string): RoadmapItem | null {
  return mockRoadmapItems.find((r) => r.id === id) ?? null;
}

export function listRoadmapItemsByMonth(websiteId: string, month: 1 | 2 | 3): RoadmapItem[] {
  return listRoadmapItems(websiteId).filter((r) => r.month_number === month);
}

export function listHighPriorityRoadmapItems(websiteId: string): RoadmapItem[] {
  return listRoadmapItems(websiteId).filter((r) => r.priority === "high");
}

export function updateRoadmapItemStatus(
  id: string,
  status: RoadmapItem["status"],
): RoadmapItem | null {
  const index = mockRoadmapItems.findIndex((r) => r.id === id);
  if (index === -1) return null;
  const updated: RoadmapItem = { ...mockRoadmapItems[index], status, updated_at: new Date().toISOString() };
  mockRoadmapItems[index] = updated;
  persist();
  return updated;
}

// Replaces the full roadmap for a website — used when the user generates or
// refreshes the 90-day plan. Preserves the status of any item whose title
// and week still match an item from the previous roadmap, so re-running the
// generator doesn't silently discard progress already marked complete.
export function replaceRoadmapForWebsite(website: SeoWebsite, items: RoadmapItem[]): RoadmapItem[] {
  const previous = listRoadmapItems(website.id);
  const now = new Date().toISOString();

  const merged = items.map((item, index) => {
    const match = previous.find((p) => p.title === item.title && p.week_number === item.week_number);
    return {
      ...item,
      id: match?.id ?? `rmp_mock_gen_${website.id}_${index + 1}_${Date.now()}`,
      created_at: match?.created_at ?? now,
      updated_at: now,
      status: match?.status ?? item.status,
    };
  });

  const remaining = mockRoadmapItems.filter((r) => r.website_id !== website.id);
  mockRoadmapItems.length = 0;
  mockRoadmapItems.push(...remaining, ...merged);
  persist();
  return listRoadmapItems(website.id);
}
