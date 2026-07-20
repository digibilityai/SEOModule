import type { ProgressReport, ReportPeriodKey, ReportStatus } from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import { requireAuthenticatedUser, requireValidUuid, safeList, safeSingle } from "@/services/supabase/supabaseServiceUtils";

// =============================================================================
// Reports Stage 1 — real-data READ path (read-only).
//
// Reads public.seo_reports (RLS: workspace-member SELECT) and flattens each row
// — canonical scalar columns + the `summary` jsonb rollup — back into the app's
// existing ProgressReport shape, so no UI/type change is needed. No INSERT/
// UPDATE/DELETE, no RPC, no generation: report rows are produced by the service
// role / a future generation stage (or, in TEST, by the read-path fixtures).
// =============================================================================

interface SeoReportRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  report_type: string;
  period_key: ReportPeriodKey;
  period_label: string;
  period_start: string;
  period_end: string;
  title: string;
  status: ReportStatus;
  summary: Record<string, unknown> | null;
  generated_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const REPORT_COLUMNS =
  "id, workspace_id, website_id, website_url, report_type, period_key, period_label, period_start, period_end, title, status, summary, generated_at, created_by, created_at, updated_at";

const REPORT_TYPE = "progress";

function num(summary: Record<string, unknown> | null, key: string): number {
  const v = summary?.[key];
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

function str(summary: Record<string, unknown> | null, key: string): string {
  const v = summary?.[key];
  return typeof v === "string" ? v : "";
}

function strArray(summary: Record<string, unknown> | null, key: string): string[] {
  const v = summary?.[key];
  return Array.isArray(v) ? v.filter((item): item is string => typeof item === "string") : [];
}

// Maps a persisted seo_reports row (scalar columns + summary jsonb) into the
// app's ProgressReport read shape. Missing summary keys coerce to safe defaults
// so a sparse/older row never throws in the UI.
function mapRowToProgressReport(row: SeoReportRow): ProgressReport {
  const actor = row.created_by ?? "";
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: actor,
    created_by: actor,
    created_at: row.created_at,
    updated_at: row.updated_at,
    period_key: row.period_key,
    period_label: row.period_label,
    period_start: row.period_start,
    period_end: row.period_end,
    status: row.status,
    generated_at: row.generated_at ?? row.created_at,
    overall_score_current: num(row.summary, "overall_score_current"),
    overall_score_previous: num(row.summary, "overall_score_previous"),
    overall_score_movement: num(row.summary, "overall_score_movement"),
    technical_summary: str(row.summary, "technical_summary"),
    issues_found_count: num(row.summary, "issues_found_count"),
    issues_fixed_count: num(row.summary, "issues_fixed_count"),
    pending_approvals_count: num(row.summary, "pending_approvals_count"),
    content_summary: str(row.summary, "content_summary"),
    content_pieces_planned: num(row.summary, "content_pieces_planned"),
    content_pieces_completed: num(row.summary, "content_pieces_completed"),
    performance_summary: str(row.summary, "performance_summary"),
    declining_pages_count: num(row.summary, "declining_pages_count"),
    improving_pages_count: num(row.summary, "improving_pages_count"),
    offpage_summary: str(row.summary, "offpage_summary"),
    authority_opportunities_count: num(row.summary, "authority_opportunities_count"),
    ai_visibility_summary: str(row.summary, "ai_visibility_summary"),
    ai_content_gaps_count: num(row.summary, "ai_content_gaps_count"),
    competitor_summary: str(row.summary, "competitor_summary"),
    competitor_gaps_count: num(row.summary, "competitor_gaps_count"),
    roadmap_summary: str(row.summary, "roadmap_summary"),
    roadmap_completed_count: num(row.summary, "roadmap_completed_count"),
    roadmap_total_count: num(row.summary, "roadmap_total_count"),
    expert_support_summary: str(row.summary, "expert_support_summary"),
    open_support_requests_count: num(row.summary, "open_support_requests_count"),
    next_actions: strArray(row.summary, "next_actions"),
    data_provenance: provenance(row.summary),
  };
}

function provenance(summary: Record<string, unknown> | null): Record<string, string> | undefined {
  const v = summary?.["data_provenance"];
  if (!v || typeof v !== "object") return undefined;
  const out: Record<string, string> = {};
  for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
    if (typeof val === "string") out[k] = val;
  }
  return Object.keys(out).length > 0 ? out : undefined;
}

/** All progress reports for a website, newest first (generated_at DESC). Read-only. */
export async function fetchSupabaseReports(websiteId: string): Promise<ProgressReport[]> {
  await requireAuthenticatedUser("seoReportsSupabaseService.fetchSupabaseReports");
  requireValidUuid("seoReportsSupabaseService.fetchSupabaseReports", websiteId, "websiteId");

  const rows = await safeList<SeoReportRow>(
    "seoReportsSupabaseService.fetchSupabaseReports",
    supabase
      .from(SEO_TABLES.reports)
      .select(REPORT_COLUMNS)
      .eq("website_id", websiteId)
      .eq("report_type", REPORT_TYPE)
      .order("generated_at", { ascending: false })
      .order("id", { ascending: true }),
  );
  return rows.map(mapRowToProgressReport);
}

/** The single progress report for a website + period, or null. Read-only. */
export async function fetchSupabaseReportForPeriod(
  websiteId: string,
  periodKey: ReportPeriodKey,
): Promise<ProgressReport | null> {
  await requireAuthenticatedUser("seoReportsSupabaseService.fetchSupabaseReportForPeriod");
  requireValidUuid("seoReportsSupabaseService.fetchSupabaseReportForPeriod", websiteId, "websiteId");

  const row = await safeSingle<SeoReportRow>(
    "seoReportsSupabaseService.fetchSupabaseReportForPeriod",
    supabase
      .from(SEO_TABLES.reports)
      .select(REPORT_COLUMNS)
      .eq("website_id", websiteId)
      .eq("report_type", REPORT_TYPE)
      .eq("period_key", periodKey)
      .maybeSingle(),
  );
  return row ? mapRowToProgressReport(row) : null;
}

/**
 * Reports Stage 2 — guarded generation. Calls the SECURITY DEFINER
 * `seo_report_generate` RPC (server-side authorization + aggregation +
 * canonical upsert), then reads the persisted row back through the Stage 1
 * read path. Sends only the website id + period key — never a workspace,
 * dates, title or metric values.
 */
export async function generateSupabaseReport(
  websiteId: string,
  periodKey: ReportPeriodKey,
): Promise<ProgressReport> {
  const label = "seoReportsSupabaseService.generateSupabaseReport";
  await requireAuthenticatedUser(label);
  requireValidUuid(label, websiteId, "websiteId");

  const { error } = await supabase.rpc(SEO_RPCS.reportGenerate, {
    p_website_id: websiteId,
    p_period_key: periodKey,
  });
  if (error) {
    throw new Error(`${label}: ${normalizeSupabaseError(error).message}`);
  }

  const report = await fetchSupabaseReportForPeriod(websiteId, periodKey);
  if (!report) {
    throw new Error(`${label}: report generated but could not be read back.`);
  }
  return report;
}

/**
 * Reports Stage 3 — export authorization. Calls the read-only role-gated
 * `seo_report_export_data` RPC (owner/admin/team_member only) and returns the
 * canonical stored report for client-side PDF rendering. Never regenerates.
 * Throws the RPC's authorization error for client/anon/nonmember/cross-tenant.
 */
export async function fetchSupabaseReportForExport(
  websiteId: string,
  periodKey: ReportPeriodKey,
): Promise<ProgressReport | null> {
  const label = "seoReportsSupabaseService.fetchSupabaseReportForExport";
  await requireAuthenticatedUser(label);
  requireValidUuid(label, websiteId, "websiteId");

  const { data, error } = await supabase.rpc(SEO_RPCS.reportExportData, {
    p_website_id: websiteId,
    p_period_key: periodKey,
  });
  if (error) {
    throw new Error(`${label}: ${normalizeSupabaseError(error).message}`);
  }
  const rows = (data ?? []) as SeoReportRow[];
  const row = Array.isArray(rows) ? rows[0] : (rows as SeoReportRow | null);
  return row ? mapRowToProgressReport(row) : null;
}

/** The most recently generated progress report for a website, or null. Read-only. */
export async function fetchSupabaseLatestReport(websiteId: string): Promise<ProgressReport | null> {
  await requireAuthenticatedUser("seoReportsSupabaseService.fetchSupabaseLatestReport");
  requireValidUuid("seoReportsSupabaseService.fetchSupabaseLatestReport", websiteId, "websiteId");

  const row = await safeSingle<SeoReportRow>(
    "seoReportsSupabaseService.fetchSupabaseLatestReport",
    supabase
      .from(SEO_TABLES.reports)
      .select(REPORT_COLUMNS)
      .eq("website_id", websiteId)
      .eq("report_type", REPORT_TYPE)
      .order("generated_at", { ascending: false })
      .order("id", { ascending: true })
      .limit(1)
      .maybeSingle(),
  );
  return row ? mapRowToProgressReport(row) : null;
}
