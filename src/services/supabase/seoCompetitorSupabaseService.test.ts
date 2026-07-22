import { describe, expect, it } from "vitest";
import { mapRowToCompetitor, type SeoCompetitorRow } from "./seoCompetitorSupabaseService";

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
