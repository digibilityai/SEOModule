import type {
  ConnectionStatus,
  NewSeoWebsiteInput,
  SeoPlanTier,
  SeoWebsite,
  WebsiteType,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { getCurrentUserId, safeList, safeSingle } from "@/services/supabase/supabaseServiceUtils";
import { getOrCreateDefaultSeoWorkspace } from "@/services/supabase/seoWorkspaceService";

// Row shapes as stored (Stage 1 migration 3, seo_websites + seo_connection_status).
// The two tables are 1:1 per website; the app's SeoWebsite type combines them
// into one flat object, so reads join them in memory here.
interface SeoWebsiteRow {
  id: string;
  workspace_id: string;
  website_url: string;
  website_name: string;
  business_name: string;
  industry: string | null;
  target_location: string | null;
  website_type: WebsiteType;
  plan_snapshot: string | null;
  is_high_risk_industry: boolean;
  is_active: boolean;
  archived_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoConnectionStatusRow {
  website_id: string;
  website_reachable: ConnectionStatus;
  sitemap_status: ConnectionStatus;
  robots_status: ConnectionStatus;
  gsc_status: ConnectionStatus;
  ga4_status: ConnectionStatus;
  cms_status: ConnectionStatus;
  gbp_status: ConnectionStatus;
}

const CONNECTION_COLUMNS =
  "website_id, website_reachable, sitemap_status, robots_status, gsc_status, ga4_status, cms_status, gbp_status";

// Matches the seo_connection_status column defaults exactly (Stage 1
// migration 3) — used only when a website somehow has no status row yet.
const DEFAULT_CONNECTION: Omit<SeoConnectionStatusRow, "website_id"> = {
  website_reachable: "pending",
  sitemap_status: "not_connected",
  robots_status: "not_connected",
  gsc_status: "not_connected",
  ga4_status: "not_connected",
  cms_status: "not_connected",
  gbp_status: "not_connected",
};

function resolveWebsiteStatus(row: SeoWebsiteRow): SeoWebsite["status"] {
  if (!row.is_active) {
    return row.archived_at ? "archived" : "inactive";
  }
  return "active";
}

function mapToSeoWebsite(
  row: SeoWebsiteRow,
  connection: SeoConnectionStatusRow | undefined,
): SeoWebsite {
  const conn = connection ?? DEFAULT_CONNECTION;
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    user_id: row.created_by ?? "",
    website_url: row.website_url,
    name: row.website_name,
    business_name: row.business_name,
    industry: row.industry ?? undefined,
    target_location: row.target_location ?? undefined,
    website_type: row.website_type,
    plan: (row.plan_snapshot as SeoPlanTier | null) ?? "basic",
    is_high_risk_industry: row.is_high_risk_industry,
    reachable_status: conn.website_reachable,
    sitemap_status: conn.sitemap_status,
    robots_status: conn.robots_status,
    gsc_status: conn.gsc_status,
    ga4_status: conn.ga4_status,
    cms_status: conn.cms_status,
    gbp_status: conn.gbp_status,
    status: resolveWebsiteStatus(row),
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

/**
 * Lists websites in the authenticated user's SEO workspace. The
 * `workspaceId` param used by the mock adapter is intentionally not used
 * here — Supabase mode resolves the real workspace from the authenticated
 * session (see seoWorkspaceService), since a caller-supplied mock workspace
 * id would not correspond to a real row. Throws on failure so the calling
 * service's adapter can fall back to mock with a clear warning.
 */
export async function fetchSupabaseWebsites(): Promise<SeoWebsite[]> {
  const { workspace, reason } = await getOrCreateDefaultSeoWorkspace();
  if (!workspace) {
    throw new Error(reason ?? "No SEO workspace available for this Supabase user.");
  }

  const websiteRows = await safeList<SeoWebsiteRow>(
    "seoWebsiteSupabaseService.fetchSupabaseWebsites",
    supabase
      .from(SEO_TABLES.websites)
      .select("*")
      .eq("workspace_id", workspace.id)
      .order("created_at", { ascending: false }),
  );

  if (websiteRows.length === 0) return [];

  const connectionRows = await safeList<SeoConnectionStatusRow>(
    "seoWebsiteSupabaseService.fetchSupabaseWebsites (connection status)",
    supabase
      .from(SEO_TABLES.connectionStatus)
      .select(CONNECTION_COLUMNS)
      .in(
        "website_id",
        websiteRows.map((row) => row.id),
      ),
  );
  const connectionByWebsiteId = new Map(connectionRows.map((row) => [row.website_id, row]));

  return websiteRows.map((row) => mapToSeoWebsite(row, connectionByWebsiteId.get(row.id)));
}

export interface SeoWebsiteSummary {
  id: string;
  website_url: string;
  name: string;
}

/**
 * Lightweight website list for an EXPLICIT workspace id — unlike
 * `fetchSupabaseWebsites()`, this does not resolve/default to "the
 * current" workspace, so it can list websites for any workspace the caller
 * already knows the user is a member of (e.g. from
 * `listAccessibleSeoWorkspaces()`). No connection-status join, since
 * callers of this function only need id/url/name. Read-only.
 */
export async function fetchSupabaseWebsitesForWorkspace(workspaceId: string): Promise<SeoWebsiteSummary[]> {
  const rows = await safeList<{ id: string; website_url: string; website_name: string }>(
    "seoWebsiteSupabaseService.fetchSupabaseWebsitesForWorkspace",
    supabase
      .from(SEO_TABLES.websites)
      .select("id, website_url, website_name")
      .eq("workspace_id", workspaceId)
      .eq("is_active", true),
  );
  return rows.map((row) => ({ id: row.id, website_url: row.website_url, name: row.website_name }));
}

/** Fetches a single website by id, joined with its connection-status row. */
export async function fetchSupabaseWebsiteById(id: string): Promise<SeoWebsite | null> {
  const row = await safeSingle<SeoWebsiteRow>(
    "seoWebsiteSupabaseService.fetchSupabaseWebsiteById",
    supabase.from(SEO_TABLES.websites).select("*").eq("id", id).maybeSingle(),
  );
  if (!row) return null;

  const connectionRow = await safeSingle<SeoConnectionStatusRow>(
    "seoWebsiteSupabaseService.fetchSupabaseWebsiteById (connection status)",
    supabase.from(SEO_TABLES.connectionStatus).select(CONNECTION_COLUMNS).eq("website_id", id).maybeSingle(),
  );

  return mapToSeoWebsite(row, connectionRow ?? undefined);
}

/**
 * Creates a website in the authenticated user's SEO workspace (creating the
 * workspace itself on first use — see getOrCreateDefaultSeoWorkspace), plus
 * a matching seo_connection_status row using the same "just added" defaults
 * the mock adapter uses (reachable=pending, everything else not_connected).
 *
 * No real crawler, sitemap fetch, robots check, or GSC/GA4/CMS/GBP
 * connection is performed — these remain status placeholders, same as mock
 * mode, until a later phase builds real integrations.
 */
export async function addSupabaseWebsite(input: NewSeoWebsiteInput): Promise<SeoWebsite> {
  const { workspace, reason } = await getOrCreateDefaultSeoWorkspace();
  if (!workspace) {
    throw new Error(reason ?? "No SEO workspace available for this Supabase user.");
  }

  const userId = await getCurrentUserId();

  const insertedRow = await safeSingle<SeoWebsiteRow>(
    "seoWebsiteSupabaseService.addSupabaseWebsite",
    supabase
      .from(SEO_TABLES.websites)
      .insert({
        workspace_id: workspace.id,
        website_url: input.website_url,
        website_name: input.name,
        business_name: input.business_name,
        industry: input.industry || null,
        target_location: input.target_location || null,
        website_type: input.website_type,
        plan_snapshot: input.plan,
        created_by: userId,
      })
      .select("*")
      .single(),
  );

  if (!insertedRow) {
    throw new Error("seoWebsiteSupabaseService.addSupabaseWebsite: insert returned no row.");
  }

  // Seed the 1:1 connection-status row. Column defaults (Stage 1 migration 3)
  // already match DEFAULT_CONNECTION above, so no explicit values are needed.
  await safeSingle(
    "seoWebsiteSupabaseService.addSupabaseWebsite (seed connection status)",
    supabase
      .from(SEO_TABLES.connectionStatus)
      .insert({
        website_id: insertedRow.id,
        website_url: insertedRow.website_url,
        workspace_id: workspace.id,
      })
      .select("website_id")
      .single(),
  );

  return mapToSeoWebsite(insertedRow, undefined);
}
