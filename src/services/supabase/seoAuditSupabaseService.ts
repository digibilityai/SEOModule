import type {
  AuditFrequency,
  AuditStatus,
  EffortLevel,
  ImpactLevel,
  OwnerType,
  RiskLevel,
  SeoAudit,
  SeoIssue,
  SeoIssueCategory,
  SeoIssueStatus,
  SeverityLevel,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { requireAuthenticatedUser, safeList, safeSingle } from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

// Row shapes as stored (Stage 2 migration 4, seo_audit_runs + seo_audit_issues).
interface SeoAuditRunRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  frequency: AuditFrequency;
  status: AuditStatus;
  overall_visibility_score: number;
  technical_health_score: number;
  onpage_score: number;
  authority_score: number;
  ai_discovery_score: number;
  issue_count: number;
  is_latest: boolean;
  started_at: string;
  completed_at: string | null;
  error_message: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoAuditIssueRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  audit_run_id: string;
  category: SeoIssueCategory;
  severity: SeverityLevel;
  title: string;
  simple_explanation: string;
  why_it_matters: string;
  technical_explanation: string;
  affected_page_url: string;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  fix_owner: OwnerType;
  suggested_next_action: string;
  status: SeoIssueStatus;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

function mapToSeoAudit(row: SeoAuditRunRow): SeoAudit {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    frequency: row.frequency,
    status: row.status,
    overall_visibility_score: row.overall_visibility_score,
    technical_health_score: row.technical_health_score,
    onpage_score: row.onpage_score,
    authority_score: row.authority_score,
    ai_discovery_score: row.ai_discovery_score,
    issue_count: row.issue_count,
    started_at: row.started_at,
    completed_at: row.completed_at ?? undefined,
  };
}

function mapToSeoIssue(row: SeoAuditIssueRow): SeoIssue {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    audit_id: row.audit_run_id,
    category: row.category,
    severity: row.severity,
    title: row.title,
    simple_explanation: row.simple_explanation,
    why_it_matters: row.why_it_matters,
    technical_explanation: row.technical_explanation,
    affected_page_url: row.affected_page_url,
    impact: row.impact,
    effort: row.effort,
    risk: row.risk,
    confidence_percentage: row.confidence_percentage,
    fix_owner: row.fix_owner,
    suggested_next_action: row.suggested_next_action,
    status: row.status,
  };
}

/** Lists all audit runs for a website (history preserved — every run is a row). */
export async function fetchSupabaseAudits(websiteId: string): Promise<SeoAudit[]> {
  await requireAuthenticatedUser("seoAuditSupabaseService.fetchSupabaseAudits");
  const rows = await safeList<SeoAuditRunRow>(
    "seoAuditSupabaseService.fetchSupabaseAudits",
    supabase
      .from(SEO_TABLES.auditRuns)
      .select("*")
      .eq("website_id", websiteId)
      .order("started_at", { ascending: false }),
  );
  return rows.map(mapToSeoAudit);
}

/** Reads the single `is_latest=true` run for a website. Null (not an error) when none exists yet. */
export async function fetchSupabaseLatestAudit(websiteId: string): Promise<SeoAudit | null> {
  await requireAuthenticatedUser("seoAuditSupabaseService.fetchSupabaseLatestAudit");
  const row = await safeSingle<SeoAuditRunRow>(
    "seoAuditSupabaseService.fetchSupabaseLatestAudit",
    supabase
      .from(SEO_TABLES.auditRuns)
      .select("*")
      .eq("website_id", websiteId)
      .eq("is_latest", true)
      .maybeSingle(),
  );
  return row ? mapToSeoAudit(row) : null;
}

export async function fetchSupabaseAuditById(id: string): Promise<SeoAudit | null> {
  await requireAuthenticatedUser("seoAuditSupabaseService.fetchSupabaseAuditById");
  const row = await safeSingle<SeoAuditRunRow>(
    "seoAuditSupabaseService.fetchSupabaseAuditById",
    supabase.from(SEO_TABLES.auditRuns).select("*").eq("id", id).maybeSingle(),
  );
  return row ? mapToSeoAudit(row) : null;
}

/** Lists issues for a specific audit run. Empty array (not an error) when none exist yet. */
export async function fetchSupabaseIssuesForAudit(auditId: string): Promise<SeoIssue[]> {
  await requireAuthenticatedUser("seoAuditSupabaseService.fetchSupabaseIssuesForAudit");
  const rows = await safeList<SeoAuditIssueRow>(
    "seoAuditSupabaseService.fetchSupabaseIssuesForAudit",
    supabase
      .from(SEO_TABLES.auditIssues)
      .select("*")
      .eq("audit_run_id", auditId)
      .order("created_at", { ascending: true }),
  );
  return rows.map(mapToSeoIssue);
}

/**
 * Triggers a new audit run via the Stage 2 `seo_run_audit(uuid)` RPC. This
 * ONLY creates the run row (status='running', all scores 0, is_latest=true) —
 * Stage 2 has no real crawler, so this never fabricates a "completed" audit
 * or synthesizes issues client-side. The run stays "running" until a future
 * service-role/crawler backend completes it and writes real issues.
 */
export async function runSupabaseAudit(
  websiteId: string,
): Promise<{ audit: SeoAudit; issues: SeoIssue[] }> {
  await requireAuthenticatedUser("seoAuditSupabaseService.runSupabaseAudit");

  const { data, error } = await supabase.rpc(SEO_RPCS.runAudit, { p_website_id: websiteId });
  if (error) {
    throw new Error(
      `seoAuditSupabaseService.runSupabaseAudit: ${normalizeSupabaseError(error).message}`,
    );
  }

  const resultRow = Array.isArray(data) ? data[0] : data;
  const auditRunId = resultRow?.audit_run_id as string | undefined;
  if (!auditRunId) {
    throw new Error("seoAuditSupabaseService.runSupabaseAudit: RPC returned no audit_run_id.");
  }

  const audit = await fetchSupabaseAuditById(auditRunId);
  if (!audit) {
    throw new Error(
      "seoAuditSupabaseService.runSupabaseAudit: could not read back the created audit run.",
    );
  }

  return { audit, issues: [] };
}
