import type { BusinessOnboarding, NewBusinessOnboardingInput } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const STORAGE_KEY = "business_onboarding";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has completed onboarding — siteB intentionally has none, so the
// dashboard's "complete business onboarding" empty state has something to show.
const seedBusinessOnboardings: BusinessOnboarding[] = [
  {
    id: "onb_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-06-02T09:00:00.000Z",
    updated_at: "2026-06-02T09:30:00.000Z",
    services_products: "Residential and commercial plumbing repair, drain cleaning, water heater installation.",
    target_audience: "Homeowners and small business owners in the local metro area.",
    main_seo_goal: "local_visibility",
    target_locations: ["Austin, TX", "Round Rock, TX"],
    competitors: ["https://www.quickfixplumbing.com"],
    proof_trust_signals: "15 years in business, licensed & insured, 4.8-star Google rating.",
    important_pages: [
      "https://www.acmeplumbing.com/",
      "https://www.acmeplumbing.com/services/drain-cleaning",
    ],
    preferred_content_tone: "friendly",
    sensitive_industry: "none",
    notes: "Focus messaging on fast emergency response.",
    status: "completed",
    completion_percentage: 100,
  },
];

// Hydrated from localStorage (if present) so records survive a browser
// refresh during local/mock-phase testing. Falls back to the seed above.
export const mockBusinessOnboardings: BusinessOnboarding[] = loadMockCollection(
  STORAGE_KEY,
  seedBusinessOnboardings,
);

function persist(): void {
  saveMockCollection(STORAGE_KEY, mockBusinessOnboardings);
}

export function getOnboardingByWebsiteId(websiteId: string): BusinessOnboarding | null {
  return mockBusinessOnboardings.find((o) => o.website_id === websiteId) ?? null;
}

export function upsertOnboarding(input: NewBusinessOnboardingInput): BusinessOnboarding {
  const now = new Date().toISOString();
  const existingIndex = mockBusinessOnboardings.findIndex(
    (o) => o.website_id === input.website_id,
  );

  let result: BusinessOnboarding;
  if (existingIndex >= 0) {
    result = {
      ...mockBusinessOnboardings[existingIndex],
      ...input,
      updated_at: now,
    };
    mockBusinessOnboardings[existingIndex] = result;
  } else {
    result = {
      id: `onb_mock_${String(mockBusinessOnboardings.length + 1).padStart(3, "0")}`,
      workspace_id: MOCK_WORKSPACE_ID,
      user_id: MOCK_USER_ID,
      created_by: MOCK_USER_ID,
      created_at: now,
      updated_at: now,
      ...input,
    };
    mockBusinessOnboardings.push(result);
  }

  persist();
  return result;
}
