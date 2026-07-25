import { afterEach, describe, expect, it, vi } from "vitest";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS } from "@/services/supabase/supabaseTypes";
import { generateSupabaseRecommendations } from "./seoRecommendationSupabaseService";

// Recommendation Generation Stage 2 — generation RPC wiring. Mocks only
// `supabase.auth.getSession` / `.rpc` / `.from` (no network); proves the
// exact call shape, response validation, and that a successful generation
// reads the persisted canonical set back rather than trusting the RPC's own
// payload — same discipline as seoCompetitorSupabaseService.test.ts.

type QueryChainResult = { data: unknown; error: unknown };

function makeQueryChain(result: QueryChainResult) {
  const chain: Record<string, unknown> = {};
  chain.select = vi.fn(() => chain);
  chain.eq = vi.fn(() => chain);
  chain.order = vi.fn(() => chain);
  chain.then = (resolve: (value: QueryChainResult) => unknown, reject?: (reason: unknown) => unknown) =>
    Promise.resolve(result).then(resolve, reject);
  return chain;
}

function mockAuthenticatedSession(userId = "user-1") {
  vi.spyOn(supabase.auth, "getSession").mockResolvedValue({
    data: { session: { user: { id: userId } } as never },
    error: null,
  } as never);
}

const WEBSITE_ID = "33333333-3333-3333-3333-333333333333";

const canonicalRow = {
  id: "11111111-1111-1111-1111-111111111111",
  workspace_id: "22222222-2222-2222-2222-222222222222",
  website_id: WEBSITE_ID,
  website_url: "https://example.com",
  issue_id: null,
  area: "schema",
  title: "Business structured data is missing",
  current_value: "Not present",
  suggested_change: "Add LocalBusiness structured data.",
  why_it_helps: "Helps rich results.",
  action_type: "auto_suggest",
  impact: "medium",
  effort: "low",
  risk: "low",
  confidence_percentage: 85,
  status: "suggested",
  created_by: "44444444-4444-4444-4444-444444444444",
  created_at: "2026-07-24T09:00:00.000Z",
  updated_at: "2026-07-24T09:00:00.000Z",
};

describe("generateSupabaseRecommendations", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("calls seo_recommendation_generate with only the website id — no tenancy/actor/content metadata", async () => {
    mockAuthenticatedSession();
    const rpcSpy = vi.spyOn(supabase, "rpc").mockResolvedValue({ data: [canonicalRow], error: null } as never);
    vi.spyOn(supabase, "from").mockReturnValue(makeQueryChain({ data: [], error: null }) as never);

    await generateSupabaseRecommendations(WEBSITE_ID);

    expect(rpcSpy).toHaveBeenCalledTimes(1);
    expect(rpcSpy).toHaveBeenCalledWith(SEO_RPCS.recommendationGenerate, { p_website_id: WEBSITE_ID });
    const [, sentArgs] = rpcSpy.mock.calls[0]!;
    expect(Object.keys(sentArgs as object)).toEqual(["p_website_id"]);
  });

  it("throws the RPC's error and never falls back to mock data", async () => {
    mockAuthenticatedSession();
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: null,
      error: { message: "Not authorized to generate recommendations for this website." },
    } as never);
    const fromSpy = vi.spyOn(supabase, "from");

    await expect(generateSupabaseRecommendations(WEBSITE_ID)).rejects.toThrow(
      /Not authorized to generate recommendations/,
    );
    // no read-back / no other Supabase call attempted after the RPC error
    expect(fromSpy).not.toHaveBeenCalled();
  });

  it("validates the RPC response is an array before trusting it", async () => {
    mockAuthenticatedSession();
    vi.spyOn(supabase, "rpc").mockResolvedValue({ data: "not-an-array", error: null } as never);

    await expect(generateSupabaseRecommendations(WEBSITE_ID)).rejects.toThrow(/unexpected RPC response/);
  });

  it("rejects a non-UUID website id before ever calling the RPC", async () => {
    mockAuthenticatedSession();
    const rpcSpy = vi.spyOn(supabase, "rpc");

    await expect(generateSupabaseRecommendations("web_mock_001")).rejects.toThrow(/not a valid Supabase UUID/);
    expect(rpcSpy).not.toHaveBeenCalled();
  });

  it("re-reads the persisted canonical set after a successful generation (not the RPC's raw payload)", async () => {
    mockAuthenticatedSession();
    // The RPC's own response deliberately differs from the read-back row, so
    // the assertion below can only pass if the function actually re-reads.
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: [{ ...canonicalRow, title: "STALE — must not be trusted" }],
      error: null,
    } as never);
    const fromSpy = vi
      .spyOn(supabase, "from")
      .mockReturnValue(makeQueryChain({ data: [canonicalRow], error: null }) as never);

    const result = await generateSupabaseRecommendations(WEBSITE_ID);

    expect(fromSpy).toHaveBeenCalledWith("seo_recommendations");
    expect(result).toHaveLength(1);
    expect(result[0]!.id).toBe(canonicalRow.id);
    expect(result[0]!.title).toBe("Business structured data is missing");
  });

  it("treats an empty RPC array as a valid, non-error response and still re-reads (e.g. no completed audit yet)", async () => {
    mockAuthenticatedSession();
    vi.spyOn(supabase, "rpc").mockResolvedValue({ data: [], error: null } as never);
    const fromSpy = vi
      .spyOn(supabase, "from")
      .mockReturnValue(makeQueryChain({ data: [], error: null }) as never);

    const result = await generateSupabaseRecommendations(WEBSITE_ID);

    expect(fromSpy).toHaveBeenCalled();
    expect(result).toEqual([]);
  });
});
