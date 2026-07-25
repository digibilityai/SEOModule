import { afterEach, describe, expect, it, vi } from "vitest";
import type { SeoWebsite } from "@/types";
import { MOCK_USER_ID, MOCK_WEBSITES_CONTEXT, MOCK_WORKSPACE_ID } from "@/mocks/mockContext";

// Competitor Benchmarking Stage 2B — dispatch wiring + role-gating logic.
// `requireSupabaseOrFallback` is mocked so each test can force the mock or
// Supabase branch of `runWithServiceAdapter` deterministically; the low-level
// RPC call shape/response-validation/read-back behaviour is covered directly
// in seoCompetitorSupabaseService.test.ts, not re-tested here.
vi.mock("@/services/dataMode", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/services/dataMode")>();
  return { ...actual, requireSupabaseOrFallback: vi.fn() };
});

vi.mock("@/services/supabase/seoCompetitorSupabaseService", () => ({
  generateSupabaseCompetitors: vi.fn(),
  fetchSupabaseCompetitors: vi.fn(),
  fetchSupabaseCompetitorDetail: vi.fn(),
}));

import { requireSupabaseOrFallback } from "@/services/dataMode";
import { generateSupabaseCompetitors } from "@/services/supabase/seoCompetitorSupabaseService";
import {
  canGenerateCompetitorBenchmarks,
  COMPETITOR_GENERATE_ROLES,
  generateCompetitorBenchmarkData,
} from "./competitorService";

const mockRequireSupabaseOrFallback = vi.mocked(requireSupabaseOrFallback);
const mockGenerateSupabaseCompetitors = vi.mocked(generateSupabaseCompetitors);

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

describe("canGenerateCompetitorBenchmarks", () => {
  it("stays enabled in mock mode regardless of role (unchanged mock-mode behaviour)", () => {
    expect(canGenerateCompetitorBenchmarks(null, false)).toBe(true);
    expect(canGenerateCompetitorBenchmarks("client", false)).toBe(true);
  });

  it.each(COMPETITOR_GENERATE_ROLES)("allows %s in Supabase mode", (role) => {
    expect(canGenerateCompetitorBenchmarks(role, true)).toBe(true);
  });

  it("denies client in Supabase mode", () => {
    expect(canGenerateCompetitorBenchmarks("client", true)).toBe(false);
  });

  it("denies a null/no-membership role in Supabase mode", () => {
    expect(canGenerateCompetitorBenchmarks(null, true)).toBe(false);
  });
});

describe("generateCompetitorBenchmarkData dispatch", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("Supabase mode: calls generateSupabaseCompetitors with only the website id", async () => {
    mockRequireSupabaseOrFallback.mockReturnValue(true);
    mockGenerateSupabaseCompetitors.mockResolvedValue([]);

    const result = await generateCompetitorBenchmarkData(website);

    expect(mockGenerateSupabaseCompetitors).toHaveBeenCalledTimes(1);
    expect(mockGenerateSupabaseCompetitors).toHaveBeenCalledWith(website.id);
    expect(result).toEqual([]);
  });

  it("Supabase mode: a generation error propagates and is never masked by mock data", async () => {
    mockRequireSupabaseOrFallback.mockReturnValue(true);
    mockGenerateSupabaseCompetitors.mockRejectedValue(
      new Error("seoCompetitorSupabaseService.generateSupabaseCompetitors: Not authorized."),
    );

    await expect(generateCompetitorBenchmarkData(website)).rejects.toThrow(/Not authorized/);
  });

  it("mock mode: never calls the Supabase RPC path, and generation still functions locally", async () => {
    mockRequireSupabaseOrFallback.mockReturnValue(false);

    const result = await generateCompetitorBenchmarkData(website);

    expect(mockGenerateSupabaseCompetitors).not.toHaveBeenCalled();
    // siteA's seeded onboarding lists this competitor — proves the existing
    // local deterministic generation still runs, unchanged, in mock mode.
    expect(result.some((c) => c.competitor_url === "https://www.quickfixplumbing.com")).toBe(true);
    // mock-mode rows never claim the Stage 2A backend's truthful provenance
    // label — they are plainly mock, not a real 'estimated' heuristic run.
    expect(result.every((c) => c.data_provenance === undefined)).toBe(true);
  });
});
