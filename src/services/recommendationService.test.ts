import { afterEach, describe, expect, it, vi } from "vitest";
import type { SeoWebsite } from "@/types";
import { MOCK_USER_ID, MOCK_WEBSITES_CONTEXT, MOCK_WORKSPACE_ID } from "@/mocks/mockContext";

// Recommendation Generation Stage 2 — dispatch wiring + role-gating logic.
// `requireSupabaseOrFallback` is mocked so each test can force the mock or
// Supabase branch of `runWithServiceAdapter` deterministically; the
// low-level RPC call shape/response-validation/read-back behaviour is
// covered directly in seoRecommendationSupabaseService.test.ts, not
// re-tested here — same split as competitorService.test.ts.
vi.mock("@/services/dataMode", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/services/dataMode")>();
  return { ...actual, requireSupabaseOrFallback: vi.fn() };
});

vi.mock("@/services/supabase/seoRecommendationSupabaseService", () => ({
  generateSupabaseRecommendations: vi.fn(),
  fetchSupabaseRecommendations: vi.fn(),
  fetchSupabaseOnPageRecommendations: vi.fn(),
  fetchSupabaseRecommendationById: vi.fn(),
}));

import { requireSupabaseOrFallback } from "@/services/dataMode";
import { generateSupabaseRecommendations } from "@/services/supabase/seoRecommendationSupabaseService";
import {
  canGenerateRecommendations,
  generateRecommendations,
  RECOMMENDATION_GENERATE_ROLES,
} from "./recommendationService";

const mockRequireSupabaseOrFallback = vi.mocked(requireSupabaseOrFallback);
const mockGenerateSupabaseRecommendations = vi.mocked(generateSupabaseRecommendations);

const [siteA] = MOCK_WEBSITES_CONTEXT;
const website: SeoWebsite = {
  id: siteA.id,
  workspace_id: MOCK_WORKSPACE_ID,
  user_id: MOCK_USER_ID,
  website_url: siteA.website_url,
  name: "Acme Plumbing",
  business_name: "Acme Plumbing",
  website_type: "local_business",
  plan: "standard",
  is_high_risk_industry: false,
  reachable_status: "connected",
  sitemap_status: "connected",
  robots_status: "connected",
  gsc_status: "not_connected",
  ga4_status: "not_connected",
  cms_status: "not_connected",
  gbp_status: "not_connected",
  status: "active",
  created_by: MOCK_USER_ID,
  created_at: "2026-07-06T09:00:00.000Z",
  updated_at: "2026-07-06T09:00:00.000Z",
};

describe("canGenerateRecommendations", () => {
  it("stays enabled in mock mode regardless of role (unchanged mock-mode behaviour)", () => {
    expect(canGenerateRecommendations(null, false)).toBe(true);
    expect(canGenerateRecommendations("client", false)).toBe(true);
  });

  it.each(RECOMMENDATION_GENERATE_ROLES)("allows %s in Supabase mode", (role) => {
    expect(canGenerateRecommendations(role, true)).toBe(true);
  });

  it("denies client in Supabase mode", () => {
    expect(canGenerateRecommendations("client", true)).toBe(false);
  });

  it("denies a null/no-membership role in Supabase mode", () => {
    expect(canGenerateRecommendations(null, true)).toBe(false);
  });
});

describe("generateRecommendations dispatch", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("Supabase mode: calls generateSupabaseRecommendations with only the website id", async () => {
    mockRequireSupabaseOrFallback.mockReturnValue(true);
    mockGenerateSupabaseRecommendations.mockResolvedValue([]);

    const result = await generateRecommendations(website);

    expect(mockGenerateSupabaseRecommendations).toHaveBeenCalledTimes(1);
    expect(mockGenerateSupabaseRecommendations).toHaveBeenCalledWith(website.id);
    expect(result).toEqual([]);
  });

  it("Supabase mode: a generation error propagates and is never masked by mock data", async () => {
    mockRequireSupabaseOrFallback.mockReturnValue(true);
    mockGenerateSupabaseRecommendations.mockRejectedValue(
      new Error("seoRecommendationSupabaseService.generateSupabaseRecommendations: Not authorized."),
    );

    await expect(generateRecommendations(website)).rejects.toThrow(/Not authorized/);
  });

  it("mock mode: never calls the Supabase RPC path, and generation still functions locally from the seeded audit", async () => {
    mockRequireSupabaseOrFallback.mockReturnValue(false);

    const result = await generateRecommendations(website);

    expect(mockGenerateSupabaseRecommendations).not.toHaveBeenCalled();
    // siteA has a seeded completed audit with issues (src/mocks/auditMockData.ts)
    // — proves the existing local generator still runs end-to-end, unchanged.
    expect(result.length).toBeGreaterThan(0);
    expect(result.every((r) => r.website_id === website.id)).toBe(true);
    // the 7 fixed on-page templates are always part of the mock's generated set
    expect(result.some((r) => r.area === "title")).toBe(true);
  });
});
