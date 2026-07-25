import type {
  BenchmarkComparison,
  BenchmarkDimension,
  Competitor,
  CompetitorGap,
  CompetitorGapType,
  CompetitorOverview,
  GapLevel,
  RelatedModule,
  SeoUserRole,
  SeoWebsite,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { fetchLatestAudit } from "@/services/auditService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  fetchSupabaseCompetitorDetail,
  fetchSupabaseCompetitors,
  generateSupabaseCompetitors,
} from "@/services/supabase/seoCompetitorSupabaseService";
import {
  applyCompetitorStrengthStatus,
  COMPETITOR_DATA_SOURCE_STATUS,
  generateCompetitorBenchmarkData as generateCompetitorBenchmarkDataRecord,
  getCompetitorById,
  listCompetitors,
} from "@/mocks/competitorMockData";

// Competitor Benchmarking Stage 2A — roles permitted to trigger generation,
// mirrors the seo_competitor_generate RPC's server-side owner/admin/
// team_member gate. Presentation-only (the RPC remains the authoritative
// check) — same convention as offpage/CampaignList.tsx's CAMPAIGN_SUBMIT_ROLES.
export const COMPETITOR_GENERATE_ROLES: SeoUserRole[] = ["owner", "admin", "team_member"];

/**
 * Whether the current UI should offer the Generate/Refresh control. Mock mode
 * has no real seo_workspace_members row, so generation stays enabled there
 * (unchanged mock-mode behaviour, matches AuthorityBuilderPage's
 * createRolePermitted pattern). In Supabase mode, only owner/admin/team_member
 * see it enabled — client and any other role see it disabled. This is a
 * usability layer only; the RPC re-enforces the same gate server-side.
 */
export function canGenerateCompetitorBenchmarks(
  role: SeoUserRole | null,
  supabaseMode: boolean,
): boolean {
  if (!supabaseMode) return true;
  return role !== null && COMPETITOR_GENERATE_ROLES.includes(role);
}

// Competitor Benchmarking Stage 1 — real-data read path. In Supabase mode these
// read persisted `seo_competitors` rows (RLS); in mock mode the local store.
// No silent mock fallback in Supabase mode.
export async function fetchCompetitors(websiteId: string): Promise<Competitor[]> {
  return runWithServiceAdapter({
    label: "competitorService.fetchCompetitors",
    mock: () => toAsync(listCompetitors(websiteId)),
    supabase: () => fetchSupabaseCompetitors(websiteId),
    fallbackToMockOnError: false,
  });
}

export async function fetchCompetitorDetail(id: string): Promise<Competitor | null> {
  return runWithServiceAdapter({
    label: "competitorService.fetchCompetitorDetail",
    mock: () => toAsync(getCompetitorById(id)),
    supabase: () => fetchSupabaseCompetitorDetail(id),
    fallbackToMockOnError: false,
  });
}

export async function fetchCompetitorOverview(
  websiteId: string,
  websiteUrl: string,
): Promise<CompetitorOverview> {
  const competitors = await fetchCompetitors(websiteId);
  const lastUpdated = competitors.reduce<string | null>((latest, c) => {
    if (!latest) return c.updated_at;
    return new Date(c.updated_at).getTime() > new Date(latest).getTime() ? c.updated_at : latest;
  }, null);

  // Truthful provenance: persisted rows are heuristic estimates, never external
  // measured intelligence. Mock rows keep the mock-testing notice.
  const isEstimated = competitors.some((c) => c.data_provenance === "estimated");
  const dataSourceStatus = isEstimated
    ? "Estimated competitor benchmarking from a heuristic model. No external competitor-data provider is integrated."
    : COMPETITOR_DATA_SOURCE_STATUS;

  return {
    website_id: websiteId,
    website_url: websiteUrl,
    competitor_count: competitors.length,
    benchmark_score:
      competitors.length > 0
        ? Math.round(competitors.reduce((sum, c) => sum + c.overall_strength_score, 0) / competitors.length)
        : 0,
    last_updated: lastUpdated,
    data_source_status: dataSourceStatus,
  };
}

// Derives our score for each benchmark dimension from the latest completed
// audit. Reviews/keyword-coverage/page-quality/local-visibility don't have a
// dedicated audit field yet, so they're simple, clearly-labeled proxies —
// real integrations (GSC, review platforms) will replace these later.
async function computeOurBenchmarkScores(websiteId: string): Promise<Record<BenchmarkDimension, number>> {
  const audit = await fetchLatestAudit(websiteId);
  const technical = audit?.technical_health_score ?? 0;
  const onpage = audit?.onpage_score ?? 0;
  const authority = audit?.authority_score ?? 0;
  const aiDiscovery = audit?.ai_discovery_score ?? 0;
  const clamp = (v: number) => Math.max(0, Math.min(100, Math.round(v)));

  return {
    technical_health: clamp(technical),
    content_depth: clamp(onpage),
    keyword_coverage: clamp(onpage - 5),
    authority_signals: clamp(authority),
    reviews_trust: clamp(authority - 10),
    ai_visibility: clamp(aiDiscovery),
    page_quality: clamp(onpage + 3),
    local_visibility: clamp(technical - 8),
  };
}

// Same proxy logic applied to each competitor so the 8-dimension comparison
// works even though Competitor only stores 5 explicit scores.
function competitorDimensionScore(competitor: Competitor, dimension: BenchmarkDimension): number {
  switch (dimension) {
    case "technical_health":
      return competitor.technical_health_score;
    case "content_depth":
      return competitor.content_strength_score;
    case "keyword_coverage":
      return Math.max(0, competitor.content_strength_score - 5);
    case "authority_signals":
      return competitor.authority_score;
    case "reviews_trust":
      return competitor.review_strength_score;
    case "ai_visibility":
      return competitor.ai_visibility_score;
    case "page_quality":
      return Math.min(100, competitor.content_strength_score + 3);
    case "local_visibility":
      return Math.max(0, competitor.technical_health_score - 8);
    default:
      return 0;
  }
}

const DIMENSION_LABEL: Record<BenchmarkDimension, string> = {
  technical_health: "Technical health",
  content_depth: "Content depth",
  keyword_coverage: "Keyword coverage",
  authority_signals: "Authority signals",
  reviews_trust: "Reviews/trust signals",
  ai_visibility: "AI visibility",
  page_quality: "Page quality",
  local_visibility: "Local visibility",
};

const ALL_DIMENSIONS: BenchmarkDimension[] = [
  "technical_health",
  "content_depth",
  "keyword_coverage",
  "authority_signals",
  "reviews_trust",
  "ai_visibility",
  "page_quality",
  "local_visibility",
];

function gapLevelFor(ourScore: number, competitorAverage: number): GapLevel {
  const gap = competitorAverage - ourScore;
  if (gap >= 15) return "high";
  if (gap >= 5) return "medium";
  return "low";
}

export async function fetchBenchmarkComparisons(websiteId: string): Promise<BenchmarkComparison[]> {
  const competitors = await fetchCompetitors(websiteId);
  const ourScores = await computeOurBenchmarkScores(websiteId);

  if (competitors.length === 0) return [];

  return ALL_DIMENSIONS.map((dimension) => {
    const ourScore = ourScores[dimension];
    const competitorScores = competitors.map((c) => ({
      name: c.competitor_name,
      score: competitorDimensionScore(c, dimension),
    }));
    const competitorAverage = Math.round(
      competitorScores.reduce((sum, c) => sum + c.score, 0) / competitorScores.length,
    );
    const strongest = competitorScores.reduce((max, c) => (c.score > max.score ? c : max), competitorScores[0]);
    const gapLevel = gapLevelFor(ourScore, competitorAverage);

    return {
      dimension,
      label: DIMENSION_LABEL[dimension],
      our_score: ourScore,
      competitor_average: competitorAverage,
      strongest_competitor_name: strongest.name,
      strongest_competitor_score: strongest.score,
      gap_level: gapLevel,
      explanation:
        gapLevel === "low"
          ? `You're holding your own on ${DIMENSION_LABEL[dimension].toLowerCase()} compared to competitors.`
          : `Competitors are ahead on ${DIMENSION_LABEL[dimension].toLowerCase()}, led by ${strongest.name}.`,
      recommended_next_step:
        gapLevel === "high"
          ? `This is a priority gap — review the recommended actions for ${DIMENSION_LABEL[dimension].toLowerCase()}.`
          : gapLevel === "medium"
            ? `Worth addressing when you have capacity — not urgent yet.`
            : `No action needed right now — keep monitoring.`,
    };
  });
}

const GAP_TYPE_BY_DIMENSION: Partial<Record<BenchmarkDimension, CompetitorGapType>> = {
  content_depth: "missing_content_topics",
  page_quality: "weak_page_types",
  keyword_coverage: "weak_keyword_coverage",
  authority_signals: "low_authority_signals",
  reviews_trust: "review_trust_gap",
  ai_visibility: "ai_visibility_gap",
  technical_health: "technical_disadvantage",
};

const MODULE_BY_GAP_TYPE: Record<CompetitorGapType, RelatedModule> = {
  missing_content_topics: "content_studio",
  weak_page_types: "page_performance",
  weak_keyword_coverage: "content_studio",
  low_authority_signals: "offpage_authority",
  review_trust_gap: "offpage_authority",
  ai_visibility_gap: "ai_visibility",
  technical_disadvantage: "audit",
};

const GAP_TITLE_BY_TYPE: Record<CompetitorGapType, string> = {
  missing_content_topics: "Competitors cover topics your content doesn't",
  weak_page_types: "Your page quality is lagging behind competitors",
  weak_keyword_coverage: "Competitors cover more of your target keywords",
  low_authority_signals: "Competitors have stronger authority signals",
  review_trust_gap: "Competitors have a stronger review/trust profile",
  ai_visibility_gap: "Competitors are more visible in AI answers",
  technical_disadvantage: "Competitors have better technical health",
};

const OWNER_BY_GAP_TYPE: Record<CompetitorGapType, CompetitorGap["suggested_owner"]> = {
  missing_content_topics: "client_action",
  weak_page_types: "digibility_expert",
  weak_keyword_coverage: "client_action",
  low_authority_signals: "client_action",
  review_trust_gap: "client_action",
  ai_visibility_gap: "digibility_expert",
  technical_disadvantage: "developer_needed",
};

// Derived from the current benchmark comparisons rather than stored as its
// own collection — the underlying competitor scores are already persisted,
// so this stays in sync automatically whenever benchmark data is refreshed.
export async function fetchCompetitorGaps(websiteId: string): Promise<CompetitorGap[]> {
  const comparisons = await fetchBenchmarkComparisons(websiteId);
  const now = new Date().toISOString();
  const competitors = await fetchCompetitors(websiteId);
  if (competitors.length === 0) return [];
  // Any competitor record carries the same website/workspace/user context —
  // used here only to satisfy the shared SeoBaseRecord fields on the gap.
  const context = competitors[0];

  return comparisons
    .filter((c) => c.gap_level !== "low" && GAP_TYPE_BY_DIMENSION[c.dimension])
    .map((c) => {
      const gapType = GAP_TYPE_BY_DIMENSION[c.dimension]!;
      return {
        id: `gap_mock_${websiteId}_${gapType}`,
        workspace_id: context.workspace_id,
        website_id: websiteId,
        website_url: context.website_url,
        user_id: context.user_id,
        created_by: context.user_id,
        created_at: now,
        updated_at: now,
        gap_type: gapType,
        title: GAP_TITLE_BY_TYPE[gapType],
        why_it_matters: c.explanation,
        recommended_action: c.recommended_next_step,
        priority: c.gap_level === "high" ? "high" : "medium",
        suggested_owner: OWNER_BY_GAP_TYPE[gapType],
        related_module: MODULE_BY_GAP_TYPE[gapType],
      } satisfies CompetitorGap;
    });
}

// Generates (or refreshes) the competitor benchmark set for a website. In
// Supabase mode this calls the guarded `seo_competitor_generate` RPC
// (server-side authorization + deterministic heuristic scoring +
// replace-to-match persistence; Competitor Stage 2A) and reloads the
// persisted canonical rows — the heuristic is never reproduced client-side.
// In mock mode it runs the existing local deterministic generation, unchanged.
// No silent mock fallback in Supabase mode — a real generation error surfaces.
export async function generateCompetitorBenchmarkData(website: SeoWebsite): Promise<Competitor[]> {
  return runWithServiceAdapter({
    label: "competitorService.generateCompetitorBenchmarkData",
    mock: () => generateMockCompetitorBenchmarkData(website),
    supabase: () => generateSupabaseCompetitors(website.id),
    fallbackToMockOnError: false,
  });
}

// Mock-mode generation: unchanged from before Stage 2A.
async function generateMockCompetitorBenchmarkData(website: SeoWebsite): Promise<Competitor[]> {
  const onboarding = await fetchOnboardingByWebsiteId(website.id);
  const competitorUrls = onboarding?.competitors ?? [];
  if (competitorUrls.length === 0) return [];

  generateCompetitorBenchmarkDataRecord(
    website.id,
    website.workspace_id,
    website.website_url,
    website.user_id,
    competitorUrls,
  );

  const ourScores = await computeOurBenchmarkScores(website.id);
  const ourOverall = Math.round(
    ALL_DIMENSIONS.reduce((sum, d) => sum + ourScores[d], 0) / ALL_DIMENSIONS.length,
  );

  return toAsync(applyCompetitorStrengthStatus(website.id, ourOverall));
}
