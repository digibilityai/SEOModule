import type { PagePerformance, PagePerformanceStatus, PageType } from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import {
  requireAuthenticatedUser,
  requireValidUuid,
  safeList,
  safeSingle,
} from "@/services/supabase/supabaseServiceUtils";
import { listAccessibleSeoWorkspaces } from "@/services/supabase/seoWorkspaceService";
import { fetchSupabaseWebsitesForWorkspace } from "@/services/supabase/seoWebsiteSupabaseService";

// =============================================================================
// Phase 14A.2 — Page Performance Tracker (Stage 4, read-only).
//
// The app's existing PagePerformance shape (src/types/performance.ts) is a
// flat "one row per page, one primary keyword" model — a holdover from the
// mock adapter. Stage 4's backend is normalized (seo_page_inventory /
// seo_page_keywords / seo_page_performance_snapshots, see
// SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md). This file reads the
// normalized tables and flattens them back into the app's existing
// PagePerformance shape, so no UI component or type changes are needed —
// only performanceService.ts's two adapter-facing functions change.
//
// Read-only this phase: no INSERT/UPDATE/DELETE anywhere below. No GSC/GA4
// call, no crawler — `source` on every seeded snapshot is 'manual_seed'.
// =============================================================================

interface SeoPageInventoryRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  page_url: string;
  normalized_page_path: string | null;
  page_title: string | null;
  meta_description: string | null;
  page_type: PageType;
  indexability_status: string;
  canonical_url: string | null;
  last_seen_at: string | null;
  first_seen_at: string;
  content_status: string;
  priority: string | null;
  is_tracked: boolean;
  is_active: boolean;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoPageKeywordRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  page_id: string;
  page_url: string;
  keyword: string;
  keyword_type: string;
  search_intent: string | null;
  target_location: string | null;
  device: string;
  search_engine: string;
  priority: string | null;
  is_primary: boolean;
  is_tracked: boolean;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoPagePerformanceSnapshotRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  page_id: string;
  page_keyword_id: string | null;
  page_url: string;
  keyword: string | null;
  snapshot_date: string;
  period_start: string;
  period_end: string;
  source: string;
  clicks: number;
  impressions: number;
  ctr: number | null;
  average_position: number | null;
  previous_clicks: number | null;
  previous_impressions: number | null;
  previous_ctr: number | null;
  previous_average_position: number | null;
  clicks_delta: number | null;
  impressions_delta: number | null;
  ctr_delta: number | null;
  position_delta: number | null;
  movement_status: string;
  diagnosis_hint: string | null;
  imported_at: string | null;
  created_by: string | null;
  created_at: string;
}

// seo_page_performance_latest (migration 13) is a DISTINCT ON view over the
// snapshots table above, and its SELECT list deliberately omits created_by
// (see 20260711120013_seo_stage4_performance_latest_view.sql) — querying it
// with a column list that includes created_by fails with PostgREST's
// "column ... does not exist". Give the view its own row type/column list
// instead of sharing SNAPSHOT_COLUMNS with the raw table.
type SeoPagePerformanceLatestRow = Omit<SeoPagePerformanceSnapshotRow, "created_by">;

const PAGE_INVENTORY_COLUMNS =
  "id, workspace_id, website_id, website_url, page_url, normalized_page_path, page_title, meta_description, page_type, indexability_status, canonical_url, last_seen_at, first_seen_at, content_status, priority, is_tracked, is_active, created_by, created_at, updated_at";

const PAGE_KEYWORD_COLUMNS =
  "id, workspace_id, website_id, website_url, page_id, page_url, keyword, keyword_type, search_intent, target_location, device, search_engine, priority, is_primary, is_tracked, created_by, created_at, updated_at";

// Raw seo_page_performance_snapshots table — has created_by.
const SNAPSHOT_COLUMNS =
  "id, workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, keyword, snapshot_date, period_start, period_end, source, clicks, impressions, ctr, average_position, previous_clicks, previous_impressions, previous_ctr, previous_average_position, clicks_delta, impressions_delta, ctr_delta, position_delta, movement_status, diagnosis_hint, imported_at, created_by, created_at";

// seo_page_performance_latest view — same columns minus created_by (the
// view's own SELECT list has no created_by; see migration 13).
const LATEST_VIEW_COLUMNS =
  "id, workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, keyword, snapshot_date, period_start, period_end, source, clicks, impressions, ctr, average_position, previous_clicks, previous_impressions, previous_ctr, previous_average_position, clicks_delta, impressions_delta, ctr_delta, position_delta, movement_status, diagnosis_hint, imported_at, created_at";

// Stage 4's movement_status (improving/stable/declining/new/no_data) is a
// distinct, newer enum from the app's PagePerformanceStatus
// (improving/stable/declining/needs_refresh/not_enough_data) — see
// SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md §5. "new" and
// "no_data" both mean "not enough history yet" from the app's perspective.
const MOVEMENT_TO_APP_STATUS: Record<string, PagePerformanceStatus> = {
  improving: "improving",
  stable: "stable",
  declining: "declining",
  new: "not_enough_data",
  no_data: "not_enough_data",
};

// content_status ('aging'/'stale') takes priority over the raw movement
// number — "needs a refresh" is fundamentally a content-freshness signal in
// the app, and Stage 4 tracks that on the page row, not the snapshot.
function resolvePerformanceStatus(movementStatus: string, contentStatus: string): PagePerformanceStatus {
  if (contentStatus === "aging" || contentStatus === "stale") {
    return "needs_refresh";
  }
  return MOVEMENT_TO_APP_STATUS[movementStatus] ?? "not_enough_data";
}

function computeTrafficMovementPercentage(clicks: number, previousClicks: number | null): number {
  if (!previousClicks) return 0;
  return ((clicks - previousClicks) / previousClicks) * 100;
}

function pickLatestSnapshotForPage(
  snapshots: SeoPagePerformanceLatestRow[],
  pageId: string,
  primaryKeywordId: string | null,
): SeoPagePerformanceLatestRow | null {
  const forPage = snapshots.filter((s) => s.page_id === pageId);
  // Prefer the primary keyword's own snapshot; fall back to the page-level
  // aggregate (page_keyword_id IS NULL); fall back to any other keyword's
  // snapshot for this page as a last resort, so a page is never dropped
  // just because its primary keyword happens to lack a snapshot.
  return (
    (primaryKeywordId && forPage.find((s) => s.page_keyword_id === primaryKeywordId)) ||
    forPage.find((s) => s.page_keyword_id === null) ||
    forPage[0] ||
    null
  );
}

function mapToPagePerformance(
  page: SeoPageInventoryRow,
  primaryKeyword: SeoPageKeywordRow | null,
  secondaryKeywords: SeoPageKeywordRow[],
  latestSnapshot: SeoPagePerformanceLatestRow | null,
): PagePerformance {
  const rawAvgPosition = latestSnapshot?.average_position ?? null;
  const rawPreviousAvgPosition = latestSnapshot?.previous_average_position ?? null;
  const rankingMovement =
    rawAvgPosition !== null && rawPreviousAvgPosition !== null ? rawPreviousAvgPosition - rawAvgPosition : 0;

  return {
    id: page.id,
    workspace_id: page.workspace_id,
    website_id: page.website_id,
    website_url: page.website_url,
    user_id: page.created_by ?? "",
    created_by: page.created_by ?? "",
    created_at: page.created_at,
    updated_at: latestSnapshot?.created_at ?? page.updated_at,
    page_title: page.page_title ?? page.page_url,
    page_url: page.page_url,
    page_type: page.page_type,
    primary_keyword: primaryKeyword?.keyword ?? "",
    secondary_keywords: secondaryKeywords.map((k) => k.keyword),
    clicks: latestSnapshot?.clicks ?? 0,
    impressions: latestSnapshot?.impressions ?? 0,
    ctr: latestSnapshot?.ctr ?? 0,
    avg_position: rawAvgPosition ?? 0,
    previous_avg_position: rawPreviousAvgPosition ?? 0,
    ranking_movement: rankingMovement,
    clicks_previous_period: latestSnapshot?.previous_clicks ?? 0,
    impressions_previous_period: latestSnapshot?.previous_impressions ?? 0,
    previous_ctr: latestSnapshot?.previous_ctr ?? 0,
    traffic_movement_percentage: computeTrafficMovementPercentage(
      latestSnapshot?.clicks ?? 0,
      latestSnapshot?.previous_clicks ?? null,
    ),
    performance_status: resolvePerformanceStatus(latestSnapshot?.movement_status ?? "no_data", page.content_status),
    main_seo_issue: latestSnapshot?.diagnosis_hint ?? undefined,
    recommended_next_action: undefined,
  };
}

/** Raw page inventory rows for a website (active pages only). Read-only. */
export async function fetchSupabasePageInventory(websiteId: string): Promise<SeoPageInventoryRow[]> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.fetchSupabasePageInventory");
  requireValidUuid("seoPagePerformanceSupabaseService.fetchSupabasePageInventory", websiteId, "websiteId");

  return safeList<SeoPageInventoryRow>(
    "seoPagePerformanceSupabaseService.fetchSupabasePageInventory",
    supabase
      .from(SEO_TABLES.pageInventory)
      .select(PAGE_INVENTORY_COLUMNS)
      .eq("website_id", websiteId)
      .eq("is_active", true)
      .order("page_url", { ascending: true }),
  );
}

/** Raw mapped-keyword rows for a single page. Read-only. */
export async function fetchSupabasePageKeywords(pageId: string): Promise<SeoPageKeywordRow[]> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.fetchSupabasePageKeywords");
  requireValidUuid("seoPagePerformanceSupabaseService.fetchSupabasePageKeywords", pageId, "pageId");

  return safeList<SeoPageKeywordRow>(
    "seoPagePerformanceSupabaseService.fetchSupabasePageKeywords",
    supabase.from(SEO_TABLES.pageKeywords).select(PAGE_KEYWORD_COLUMNS).eq("page_id", pageId),
  );
}

/** Raw seo_page_performance_latest rows for a website (one per page/keyword). Read-only. */
export async function fetchSupabaseLatestPerformance(websiteId: string): Promise<SeoPagePerformanceLatestRow[]> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.fetchSupabaseLatestPerformance");
  requireValidUuid("seoPagePerformanceSupabaseService.fetchSupabaseLatestPerformance", websiteId, "websiteId");

  return safeList<SeoPagePerformanceLatestRow>(
    "seoPagePerformanceSupabaseService.fetchSupabaseLatestPerformance",
    supabase.from(SEO_TABLES.pagePerformanceLatestView).select(LATEST_VIEW_COLUMNS).eq("website_id", websiteId),
  );
}

/**
 * Full snapshot history for a page (or a specific page+keyword, when
 * `pageKeywordId` is given), newest first. `pageKeywordId` omitted/undefined
 * returns the page-level aggregate history (page_keyword_id IS NULL).
 * Read-only.
 */
export async function fetchSupabasePerformanceHistory(
  pageId: string,
  pageKeywordId?: string | null,
): Promise<SeoPagePerformanceSnapshotRow[]> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.fetchSupabasePerformanceHistory");
  requireValidUuid("seoPagePerformanceSupabaseService.fetchSupabasePerformanceHistory", pageId, "pageId");
  if (pageKeywordId) {
    requireValidUuid(
      "seoPagePerformanceSupabaseService.fetchSupabasePerformanceHistory",
      pageKeywordId,
      "pageKeywordId",
    );
  }

  const query = supabase.from(SEO_TABLES.pagePerformanceSnapshots).select(SNAPSHOT_COLUMNS).eq("page_id", pageId);
  const scoped = pageKeywordId ? query.eq("page_keyword_id", pageKeywordId) : query.is("page_keyword_id", null);

  return safeList<SeoPagePerformanceSnapshotRow>(
    "seoPagePerformanceSupabaseService.fetchSupabasePerformanceHistory",
    scoped.order("snapshot_date", { ascending: false }),
  );
}

/**
 * Business-friendly page/keyword/metric counts by movement_status, derived
 * from the latest view. Read-only; safe empty-state ({} counts) when a
 * website has no Stage 4 data yet.
 */
export async function fetchSupabaseMovementSummary(websiteId: string): Promise<Record<string, number>> {
  const rows = await fetchSupabaseLatestPerformance(websiteId);
  return rows.reduce<Record<string, number>>((acc, row) => {
    acc[row.movement_status] = (acc[row.movement_status] ?? 0) + 1;
    return acc;
  }, {});
}

/**
 * Main app-facing read: flattens Stage 4's normalized page/keyword/snapshot
 * tables into the app's existing PagePerformance[] shape (one row per
 * active, tracked page, with its primary/secondary keywords and latest
 * metrics folded in). Tolerates a page with no keywords yet or no snapshot
 * yet — returns safe defaults, never throws for sparse data.
 */
export async function fetchSupabasePagePerformance(websiteId: string): Promise<PagePerformance[]> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.fetchSupabasePagePerformance");
  requireValidUuid("seoPagePerformanceSupabaseService.fetchSupabasePagePerformance", websiteId, "websiteId");

  const pages = await safeList<SeoPageInventoryRow>(
    "seoPagePerformanceSupabaseService.fetchSupabasePagePerformance (pages)",
    supabase
      .from(SEO_TABLES.pageInventory)
      .select(PAGE_INVENTORY_COLUMNS)
      .eq("website_id", websiteId)
      .eq("is_active", true),
  );
  if (pages.length === 0) return [];

  const pageIds = pages.map((p) => p.id);

  const [keywords, latestSnapshots] = await Promise.all([
    safeList<SeoPageKeywordRow>(
      "seoPagePerformanceSupabaseService.fetchSupabasePagePerformance (keywords)",
      supabase.from(SEO_TABLES.pageKeywords).select(PAGE_KEYWORD_COLUMNS).in("page_id", pageIds),
    ),
    safeList<SeoPagePerformanceLatestRow>(
      "seoPagePerformanceSupabaseService.fetchSupabasePagePerformance (latest)",
      supabase.from(SEO_TABLES.pagePerformanceLatestView).select(LATEST_VIEW_COLUMNS).eq("website_id", websiteId),
    ),
  ]);

  return pages.map((page) => {
    const pageKeywords = keywords.filter((k) => k.page_id === page.id);
    const primaryKeyword = pageKeywords.find((k) => k.is_primary) ?? null;
    const secondaryKeywords = pageKeywords.filter((k) => !k.is_primary);
    const latestSnapshot = pickLatestSnapshotForPage(latestSnapshots, page.id, primaryKeyword?.id ?? null);

    return mapToPagePerformance(page, primaryKeyword, secondaryKeywords, latestSnapshot);
  });
}

/** Single-page version of fetchSupabasePagePerformance, by page inventory id. */
export async function fetchSupabasePageDetail(pageId: string): Promise<PagePerformance | null> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.fetchSupabasePageDetail");
  requireValidUuid("seoPagePerformanceSupabaseService.fetchSupabasePageDetail", pageId, "pageId");

  const page = await safeSingle<SeoPageInventoryRow>(
    "seoPagePerformanceSupabaseService.fetchSupabasePageDetail (page)",
    supabase.from(SEO_TABLES.pageInventory).select(PAGE_INVENTORY_COLUMNS).eq("id", pageId).maybeSingle(),
  );
  if (!page) return null;

  const [keywords, snapshots] = await Promise.all([
    safeList<SeoPageKeywordRow>(
      "seoPagePerformanceSupabaseService.fetchSupabasePageDetail (keywords)",
      supabase.from(SEO_TABLES.pageKeywords).select(PAGE_KEYWORD_COLUMNS).eq("page_id", pageId),
    ),
    safeList<SeoPagePerformanceLatestRow>(
      "seoPagePerformanceSupabaseService.fetchSupabasePageDetail (latest)",
      supabase.from(SEO_TABLES.pagePerformanceLatestView).select(LATEST_VIEW_COLUMNS).eq("page_id", pageId),
    ),
  ]);

  const primaryKeyword = keywords.find((k) => k.is_primary) ?? null;
  const secondaryKeywords = keywords.filter((k) => !k.is_primary);
  const latestSnapshot = pickLatestSnapshotForPage(snapshots, pageId, primaryKeyword?.id ?? null);

  return mapToPagePerformance(page, primaryKeyword, secondaryKeywords, latestSnapshot);
}

export interface WebsiteWithPerformanceData {
  workspaceId: string;
  workspaceName: string;
  websiteId: string;
  websiteUrl: string;
  latestRowCount: number;
}

/**
 * Searches every SEO workspace the current user is a member of (not just
 * whichever one `getCurrentSeoWorkspace` happens to default to), and every
 * website within each, for the first one that actually has Stage 4
 * performance rows. `null` if none of them do. Read-only, no writes.
 *
 * Does NOT hardcode any specific workspace/website id or name — the result
 * is entirely driven by which accessible workspace/website genuinely has
 * `seo_page_performance_latest` rows. Intended for dev/diagnostic use (the
 * `/seo/dev/auth-test` harness) and as a Supabase-mode-only fallback on
 * `PagePerformancePage` when the auto-selected active website has none.
 */
export async function findAccessibleWebsiteWithPerformanceData(): Promise<WebsiteWithPerformanceData | null> {
  await requireAuthenticatedUser("seoPagePerformanceSupabaseService.findAccessibleWebsiteWithPerformanceData");

  const workspaces = await listAccessibleSeoWorkspaces();
  for (const workspace of workspaces) {
    const websites = await fetchSupabaseWebsitesForWorkspace(workspace.id);
    for (const website of websites) {
      const latestRows = await fetchSupabaseLatestPerformance(website.id);
      if (latestRows.length > 0) {
        return {
          workspaceId: workspace.id,
          workspaceName: workspace.name,
          websiteId: website.id,
          websiteUrl: website.website_url,
          latestRowCount: latestRows.length,
        };
      }
    }
  }
  return null;
}
