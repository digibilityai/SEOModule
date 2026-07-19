import type {
  AiContentGap,
  BrandMentionSummary,
  CompetitorMentionSummary,
  ImpactLevel,
  PromptTrackingRecord,
  PromptVisibilityStatus,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { requireAuthenticatedUser, requireValidUuid, safeList } from "@/services/supabase/supabaseServiceUtils";
import { listAccessibleSeoWorkspaces } from "@/services/supabase/seoWorkspaceService";
import { fetchSupabaseWebsitesForWorkspace } from "@/services/supabase/seoWebsiteSupabaseService";

// =============================================================================
// Phase 15A — AI Visibility / GEO (Stage 6, read-only this phase).
//
// The app's existing PromptTrackingRecord / AiContentGap types
// (src/types/aiVisibility.ts) map almost 1:1 onto Stage 6's
// seo_ai_prompt_tracking / seo_ai_content_gaps tables. Brand/competitor
// mention summaries are different: the MOCK adapter derives them by
// re-parsing each prompt's brand_mentioned/competitors_mentioned[] arrays,
// but Stage 6 also ships a normalized seo_ai_mentions table (D2 — "the
// stored, queryable source that feeds brand/competitor summaries... replacing
// the mock's derive-from-prompt-arrays approach"). Per the task's mapping
// requirement, this file PREFERS seo_ai_mentions when normalized rows exist
// for an entity, and falls back to the prompt-array derivation (same shape as
// the mock) only when a website has prompt data but no mention rows yet —
// see fetchSupabaseBrandMentionSummary / fetchSupabaseCompetitorMentionSummaries.
//
// prompt_tracking is intentionally TIME-SERIES (Stage 6 D4 — the same
// prompt_text may be re-observed on a later observed_on date; there is no
// uniqueness on prompt_text). Each observation stays its own row/card in the
// UI (the frontend type has no notion of "the same prompt" beyond its id), so
// this file does not deduplicate — it returns every row, newest observation
// first (observed_on DESC, then created_at DESC as a tiebreak).
//
// READ-ONLY this phase: no INSERT/UPDATE/DELETE anywhere below. AI Visibility
// writes are plain-RLS (no transition RPC, per Stage 6's design — this is
// observed/reporting data, not external-facing execution), but the current
// UI does not call updateAiVisibilityItemStatus from any button (verified in
// AiVisibilityPage.tsx), so there is no live write path to wire yet — see
// PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md §7. No real
// LLM/scraper/crawler/external-API behavior is implied anywhere in this file
// — every row is manual/imported observation data (source column).
// =============================================================================

export interface SeoAiPromptTrackingRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  prompt_text: string;
  topic: string;
  observed_on: string;
  visibility_status: string;
  brand_mentioned: boolean;
  brand_position: number | null;
  competitors_mentioned: string[];
  citation_sources: string[];
  our_site_cited: boolean;
  gap_summary: string;
  recommended_next_step: string;
  source: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoAiContentGapRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  related_prompt_id: string | null;
  topic: string;
  missing_answer_angle: string;
  suggested_content_type: string;
  related_keyword_or_question: string;
  gap_type: string | null;
  priority: string;
  recommended_next_action: string;
  status: string;
  source: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface SeoAiMentionRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  prompt_tracking_id: string | null;
  mention_type: string;
  entity_name: string;
  entity_url: string | null;
  citation_url: string | null;
  is_our_site: boolean;
  mention_position: number | null;
  sentiment: string | null;
  prominence: string | null;
  where_appears: string | null;
  notes: string | null;
  source: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const PROMPT_COLUMNS =
  "id, workspace_id, website_id, website_url, prompt_text, topic, observed_on, visibility_status, brand_mentioned, brand_position, competitors_mentioned, citation_sources, our_site_cited, gap_summary, recommended_next_step, source, created_by, created_at, updated_at";

const CONTENT_GAP_COLUMNS =
  "id, workspace_id, website_id, website_url, related_prompt_id, topic, missing_answer_angle, suggested_content_type, related_keyword_or_question, gap_type, priority, recommended_next_action, status, source, created_by, created_at, updated_at";

const MENTION_COLUMNS =
  "id, workspace_id, website_id, website_url, prompt_tracking_id, mention_type, entity_name, entity_url, citation_url, is_our_site, mention_position, sentiment, prominence, where_appears, notes, source, created_by, created_at, updated_at";

// -----------------------------------------------------------------------------
// Mapping helpers — validated pass-through with a safe fallback, never a
// throw, matching the same pattern as every other Stage 4/5/6 Supabase
// service in this app.
// -----------------------------------------------------------------------------

const VALID_VISIBILITY_STATUSES: ReadonlySet<string> = new Set([
  "visible",
  "partially_visible",
  "not_visible",
  "unknown",
]);
const DEFAULT_VISIBILITY_STATUS: PromptVisibilityStatus = "unknown";
function mapVisibilityStatus(value: string): PromptVisibilityStatus {
  return VALID_VISIBILITY_STATUSES.has(value)
    ? (value as PromptVisibilityStatus)
    : DEFAULT_VISIBILITY_STATUS;
}

const VALID_PRIORITIES: ReadonlySet<string> = new Set(["low", "medium", "high"]);
function mapPriority(value: string): ImpactLevel {
  return VALID_PRIORITIES.has(value) ? (value as ImpactLevel) : "medium";
}

function mapToPromptTrackingRecord(row: SeoAiPromptTrackingRow): PromptTrackingRecord {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    prompt_text: row.prompt_text,
    topic: row.topic,
    brand_mentioned: row.brand_mentioned,
    competitors_mentioned: row.competitors_mentioned ?? [],
    citation_sources: row.citation_sources ?? [],
    our_site_cited: row.our_site_cited,
    visibility_status: mapVisibilityStatus(row.visibility_status),
    gap_summary: row.gap_summary,
    recommended_next_step: row.recommended_next_step,
  };
}

function mapToAiContentGap(row: SeoAiContentGapRow): AiContentGap {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    topic: row.topic,
    missing_answer_angle: row.missing_answer_angle,
    suggested_content_type: row.suggested_content_type,
    related_keyword_or_question: row.related_keyword_or_question,
    priority: mapPriority(row.priority),
    recommended_next_action: row.recommended_next_action,
  };
}

/**
 * Raw seo_ai_prompt_tracking rows for a website, newest observation first
 * (observed_on DESC, created_at DESC tiebreak) — time-series data, not
 * deduplicated by prompt_text (Stage 6 D4). Read-only.
 */
export async function fetchSupabasePromptTrackingRows(websiteId: string): Promise<SeoAiPromptTrackingRow[]> {
  await requireAuthenticatedUser("seoAiVisibilitySupabaseService.fetchSupabasePromptTrackingRows");
  requireValidUuid("seoAiVisibilitySupabaseService.fetchSupabasePromptTrackingRows", websiteId, "websiteId");

  return safeList<SeoAiPromptTrackingRow>(
    "seoAiVisibilitySupabaseService.fetchSupabasePromptTrackingRows",
    supabase
      .from(SEO_TABLES.aiPromptTracking)
      .select(PROMPT_COLUMNS)
      .eq("website_id", websiteId)
      .order("observed_on", { ascending: false })
      .order("created_at", { ascending: false }),
  );
}

/**
 * Main app-facing read: all prompt-tracking observations for a website,
 * mapped into the app's existing PromptTrackingRecord[] shape. Matches
 * AiVisibilityPage.tsx's "prompts" list.
 */
export async function fetchSupabasePromptTrackingRecords(websiteId: string): Promise<PromptTrackingRecord[]> {
  const rows = await fetchSupabasePromptTrackingRows(websiteId);
  return rows.map(mapToPromptTrackingRecord);
}

/**
 * Raw seo_ai_content_gaps rows for a website. Read-only, dev-harness use.
 */
export async function fetchSupabaseContentGapRows(websiteId: string): Promise<SeoAiContentGapRow[]> {
  await requireAuthenticatedUser("seoAiVisibilitySupabaseService.fetchSupabaseContentGapRows");
  requireValidUuid("seoAiVisibilitySupabaseService.fetchSupabaseContentGapRows", websiteId, "websiteId");

  return safeList<SeoAiContentGapRow>(
    "seoAiVisibilitySupabaseService.fetchSupabaseContentGapRows",
    supabase
      .from(SEO_TABLES.aiContentGaps)
      .select(CONTENT_GAP_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
}

/** Main app-facing read: all AI content gaps for a website, mapped into AiContentGap[]. */
export async function fetchSupabaseAiContentGaps(websiteId: string): Promise<AiContentGap[]> {
  const rows = await fetchSupabaseContentGapRows(websiteId);
  return rows.map(mapToAiContentGap);
}

/**
 * Raw seo_ai_mentions rows for a website. Read-only. Exported (not just
 * internal) so dev/diagnostic UI can inspect the normalized mention rows
 * directly — no frontend "mention" type exists yet beyond the derived
 * Brand/CompetitorMentionSummary shapes below.
 */
export async function fetchSupabaseMentionRows(websiteId: string): Promise<SeoAiMentionRow[]> {
  await requireAuthenticatedUser("seoAiVisibilitySupabaseService.fetchSupabaseMentionRows");
  requireValidUuid("seoAiVisibilitySupabaseService.fetchSupabaseMentionRows", websiteId, "websiteId");

  return safeList<SeoAiMentionRow>(
    "seoAiVisibilitySupabaseService.fetchSupabaseMentionRows",
    supabase
      .from(SEO_TABLES.aiMentions)
      .select(MENTION_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
}

/**
 * Brand mention summary for a website. total_prompts_tracked/
 * brand_mention_count/mention_rate_percentage are computed from
 * seo_ai_prompt_tracking.brand_mentioned (the authoritative per-observation
 * flag — same math the mock adapter uses, now backed by real data).
 * where_brand_appears PREFERS normalized seo_ai_mentions rows
 * (mention_type='brand') per D2, enriched with the linked prompt's text/
 * visibility_status when available; falls back to deriving directly from
 * brand_mentioned prompt rows only if a website has prompts but no mention
 * rows yet (so this never silently returns empty for legitimate data).
 */
export async function fetchSupabaseBrandMentionSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<BrandMentionSummary> {
  const [promptRows, mentionRows] = await Promise.all([
    fetchSupabasePromptTrackingRows(websiteId),
    fetchSupabaseMentionRows(websiteId),
  ]);

  const totalPromptsTracked = promptRows.length;
  const brandMentionCount = promptRows.filter((p) => p.brand_mentioned).length;
  const mentionRatePercentage =
    totalPromptsTracked > 0 ? (brandMentionCount / totalPromptsTracked) * 100 : 0;

  const promptById = new Map(promptRows.map((p) => [p.id, p]));
  const brandMentions = mentionRows.filter((m) => m.mention_type === "brand");

  const whereBrandAppears =
    brandMentions.length > 0
      ? brandMentions.map((m) => {
          const linkedPrompt = m.prompt_tracking_id ? promptById.get(m.prompt_tracking_id) : undefined;
          return linkedPrompt
            ? `"${linkedPrompt.prompt_text}" (${linkedPrompt.visibility_status.replace("_", " ")})`
            : (m.where_appears ?? `Mentioned as "${m.entity_name}"`);
        })
      : promptRows
          .filter((p) => p.brand_mentioned)
          .map((p) => `"${p.prompt_text}" (${p.visibility_status.replace("_", " ")})`);

  return {
    website_id: websiteId,
    website_url: websiteUrl,
    total_prompts_tracked: totalPromptsTracked,
    brand_mention_count: brandMentionCount,
    mention_rate_percentage: mentionRatePercentage,
    where_brand_appears: whereBrandAppears,
  };
}

/**
 * Competitor mention summaries for a website, one per distinct competitor
 * entity_name. PREFERS normalized seo_ai_mentions rows (mention_type=
 * 'competitor') per D2, enriched with each mention's linked prompt (gap
 * summary / recommended next step) when available. Falls back to deriving
 * from seo_ai_prompt_tracking.competitors_mentioned[] (mirroring the mock
 * adapter's own derivation, same fallback copy) only when a website has
 * prompts but no competitor mention rows yet.
 */
export async function fetchSupabaseCompetitorMentionSummaries(
  websiteId: string,
  websiteUrl: string,
): Promise<CompetitorMentionSummary[]> {
  const [promptRows, mentionRows] = await Promise.all([
    fetchSupabasePromptTrackingRows(websiteId),
    fetchSupabaseMentionRows(websiteId),
  ]);

  const promptById = new Map(promptRows.map((p) => [p.id, p]));
  const competitorMentions = mentionRows.filter((m) => m.mention_type === "competitor");

  if (competitorMentions.length > 0) {
    const byEntity = new Map<string, SeoAiMentionRow[]>();
    competitorMentions.forEach((m) => {
      const list = byEntity.get(m.entity_name) ?? [];
      list.push(m);
      byEntity.set(m.entity_name, list);
    });

    return Array.from(byEntity.entries()).map(([competitor_name, mentions]) => {
      const whereCompetitorAppears = mentions.map((m) => {
        const linkedPrompt = m.prompt_tracking_id ? promptById.get(m.prompt_tracking_id) : undefined;
        return linkedPrompt ? `"${linkedPrompt.prompt_text}"` : (m.where_appears ?? competitor_name);
      });
      const firstLinkedPrompt = mentions
        .map((m) => (m.prompt_tracking_id ? promptById.get(m.prompt_tracking_id) : undefined))
        .find((p): p is SeoAiPromptTrackingRow => !!p);

      return {
        website_id: websiteId,
        website_url: websiteUrl,
        competitor_name,
        mention_count: mentions.length,
        where_competitor_appears: whereCompetitorAppears,
        what_competitor_does_better:
          firstLinkedPrompt?.gap_summary || mentions[0]?.notes || "Appears more consistently for this topic.",
        recommended_next_step:
          firstLinkedPrompt?.recommended_next_step ||
          "Strengthen your content and trust signals on this topic to close the gap.",
      };
    });
  }

  // Fallback: no normalized competitor mention rows yet — derive from the
  // prompt rows' own competitors_mentioned[] array (same shape/copy as
  // mockAiVisibilityMockData.buildCompetitorMentionSummaries).
  const byEntity = new Map<string, SeoAiPromptTrackingRow[]>();
  promptRows.forEach((p) => {
    (p.competitors_mentioned ?? []).forEach((name) => {
      const list = byEntity.get(name) ?? [];
      list.push(p);
      byEntity.set(name, list);
    });
  });

  return Array.from(byEntity.entries()).map(([competitor_name, records]) => ({
    website_id: websiteId,
    website_url: websiteUrl,
    competitor_name,
    mention_count: records.length,
    where_competitor_appears: records.map((r) => `"${r.prompt_text}"`),
    what_competitor_does_better: records[0]?.gap_summary || "Appears more consistently for this topic.",
    recommended_next_step:
      records[0]?.recommended_next_step ||
      "Strengthen your content and trust signals on this topic to close the gap.",
  }));
}

export interface WebsiteWithAiVisibilityData {
  workspaceId: string;
  workspaceName: string;
  websiteId: string;
  websiteUrl: string;
  promptCount: number;
  /** How many accessible websites had at least one prompt-tracking row (including the returned one) — dev-harness/debug context for why this candidate won. */
  candidateCount: number;
}

/**
 * Searches every SEO workspace the current user is a member of, and every
 * website within each, for the one with the MOST seo_ai_prompt_tracking
 * rows. `null` if none have any. Read-only, no writes. Same
 * rank-by-count-not-first-match shape as
 * findAccessibleWebsiteWithAuthorityData / findAccessibleWebsiteWithDeclineDiagnosisData.
 * Does NOT hardcode any workspace/website id, name, or URL.
 */
export async function findAccessibleWebsiteWithAiVisibilityData(): Promise<WebsiteWithAiVisibilityData | null> {
  await requireAuthenticatedUser("seoAiVisibilitySupabaseService.findAccessibleWebsiteWithAiVisibilityData");

  const workspaces = await listAccessibleSeoWorkspaces();
  const candidates: Omit<WebsiteWithAiVisibilityData, "candidateCount">[] = [];

  for (const workspace of workspaces) {
    const websites = await fetchSupabaseWebsitesForWorkspace(workspace.id);
    for (const website of websites) {
      const rows = await fetchSupabasePromptTrackingRows(website.id);
      if (rows.length > 0) {
        candidates.push({
          workspaceId: workspace.id,
          workspaceName: workspace.name,
          websiteId: website.id,
          websiteUrl: website.website_url,
          promptCount: rows.length,
        });
      }
    }
  }

  if (candidates.length === 0) return null;

  candidates.sort((a, b) => b.promptCount - a.promptCount);

  return { ...candidates[0], candidateCount: candidates.length };
}
