import { afterEach, describe, expect, it, vi } from "vitest";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS } from "@/services/supabase/supabaseTypes";
import {
  generateSupabaseCompetitors,
  mapRowToCompetitor,
  type SeoCompetitorRow,
} from "./seoCompetitorSupabaseService";

// Competitor Benchmarking Stage 1 — adapter row-to-domain mapping + truthful
// provenance. Pure function; no network.

const baseRow: SeoCompetitorRow = {
  id: "11111111-1111-1111-1111-111111111111",
  workspace_id: "22222222-2222-2222-2222-222222222222",
  website_id: "33333333-3333-3333-3333-333333333333",
  website_url: "https://example.com",
  competitor_name: "Comp A",
  competitor_url: "https://www.compa.com/",
  normalized_competitor_url: "compa.com",
  business_category: "Plumbing",
  target_location: "Austin, TX",
  content_strength_score: 65,
  technical_health_score: 78,
  authority_score: 60,
  ai_visibility_score: 40,
  review_strength_score: 88,
  overall_strength_score: 66,
  status: "stronger",
  what_they_do_better: ["More reviews"],
  what_they_are_missing: ["Low AI visibility"],
  content_opportunities: ["Add pricing"],
  authority_opportunities: ["More citations"],
  ai_visibility_opportunities: ["Add trust signals"],
  suggested_next_action: "Close the review gap.",
  data_provenance: "estimated",
  generation_method: "heuristic_v1",
  created_by: "44444444-4444-4444-4444-444444444444",
  created_at: "2026-07-06T09:00:00.000Z",
  updated_at: "2026-07-06T09:00:00.000Z",
};

describe("mapRowToCompetitor", () => {
  it("maps a full row to the Competitor domain shape", () => {
    const c = mapRowToCompetitor(baseRow);
    expect(c.id).toBe(baseRow.id);
    expect(c.competitor_name).toBe("Comp A");
    expect(c.overall_strength_score).toBe(66);
    expect(c.status).toBe("stronger");
    expect(c.what_they_do_better).toEqual(["More reviews"]);
    expect(c.suggested_next_action).toBe("Close the review gap.");
    // created_by drives user_id (SeoBaseRecord)
    expect(c.user_id).toBe(baseRow.created_by);
    expect(c.created_by).toBe(baseRow.created_by);
  });

  it("preserves truthful 'estimated' provenance and generation method", () => {
    const c = mapRowToCompetitor(baseRow);
    expect(c.data_provenance).toBe("estimated");
    expect(c.generation_method).toBe("heuristic_v1");
    // never mislabelled as measured/external
    expect(["live", "measured", "verified", "observed", "external"]).not.toContain(c.data_provenance);
  });

  it("coerces null arrays/fields to safe defaults", () => {
    const sparse: SeoCompetitorRow = {
      ...baseRow,
      business_category: null,
      target_location: null,
      what_they_do_better: null,
      what_they_are_missing: null,
      content_opportunities: null,
      authority_opportunities: null,
      ai_visibility_opportunities: null,
      generation_method: null,
      created_by: null,
    };
    const c = mapRowToCompetitor(sparse);
    expect(c.business_category).toBe("");
    expect(c.target_location).toBeUndefined();
    expect(c.what_they_do_better).toEqual([]);
    expect(c.ai_visibility_opportunities).toEqual([]);
    expect(c.generation_method).toBeUndefined();
    expect(c.user_id).toBe("");
  });
});

// Competitor Benchmarking Stage 2A/2B — generation RPC wiring. Mocks only
// `supabase.auth.getSession` / `.rpc` / `.from` (no network); proves the exact
// call shape, response validation, and that a successful generation reads the
// persisted canonical set back rather than trusting the RPC's own payload.
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

describe("generateSupabaseCompetitors", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("calls seo_competitor_generate with only the website id — no tenancy/actor/score/provenance metadata", async () => {
    mockAuthenticatedSession();
    const rpcSpy = vi.spyOn(supabase, "rpc").mockResolvedValue({ data: 2, error: null } as never);
    vi.spyOn(supabase, "from").mockReturnValue(makeQueryChain({ data: [], error: null }) as never);

    await generateSupabaseCompetitors(baseRow.website_id);

    expect(rpcSpy).toHaveBeenCalledTimes(1);
    expect(rpcSpy).toHaveBeenCalledWith(SEO_RPCS.competitorGenerate, { p_website_id: baseRow.website_id });
    const [, sentArgs] = rpcSpy.mock.calls[0]!;
    expect(Object.keys(sentArgs as object)).toEqual(["p_website_id"]);
  });

  it("throws the RPC's error and never falls back to mock data", async () => {
    mockAuthenticatedSession();
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: null,
      error: { message: "Not authorized to generate competitor benchmarks for this website." },
    } as never);
    const fromSpy = vi.spyOn(supabase, "from");

    await expect(generateSupabaseCompetitors(baseRow.website_id)).rejects.toThrow(
      /Not authorized to generate competitor benchmarks/,
    );
    // no read-back / no other Supabase call attempted after the RPC error
    expect(fromSpy).not.toHaveBeenCalled();
  });

  it("validates the RPC response is a numeric count before trusting it", async () => {
    mockAuthenticatedSession();
    vi.spyOn(supabase, "rpc").mockResolvedValue({ data: "not-a-number", error: null } as never);

    await expect(generateSupabaseCompetitors(baseRow.website_id)).rejects.toThrow(/unexpected RPC response/);
  });

  it("re-reads the persisted canonical set after a successful generation (not the RPC's raw payload)", async () => {
    mockAuthenticatedSession();
    vi.spyOn(supabase, "rpc").mockResolvedValue({ data: 1, error: null } as never);
    const fromSpy = vi
      .spyOn(supabase, "from")
      .mockReturnValue(makeQueryChain({ data: [baseRow], error: null }) as never);

    const result = await generateSupabaseCompetitors(baseRow.website_id);

    expect(fromSpy).toHaveBeenCalledWith("seo_competitors");
    expect(result).toHaveLength(1);
    expect(result[0]!.id).toBe(baseRow.id);
    // truthful estimated provenance survives the post-generation read-back
    expect(result[0]!.data_provenance).toBe("estimated");
  });
});
