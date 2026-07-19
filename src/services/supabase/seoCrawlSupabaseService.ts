// Phase 16H / Crawler 1F — Supabase reads/writes for the customer crawl UI.
// Authoritative source is Supabase (RLS + guarded RPCs). This layer never:
//   - selects lease_token / worker id / correlation id / raw config,
//   - queries for "the latest audit run" (the orchestration RPC returns ids),
//   - directly updates crawler tables (only the guarded RPCs mutate them).
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES, SEO_RPCS } from "@/services/supabase/supabaseTypes";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import type {
  CrawlJobStatus,
  CrawlJobView,
  CrawlPublicationView,
  RequestCrawlResult,
} from "@/types/crawl";

// Customer-SAFE job columns only.
const JOB_COLUMNS =
  "id, status, audit_run_id, requested_at, started_at, completed_at, heartbeat_at, " +
  "cancellation_requested_at, cancelled_at, attempt_count, pages_discovered, pages_crawled, " +
  "extraction_stats, error_code, error_message";

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function optNum(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function toJobView(row: Record<string, unknown>): CrawlJobView {
  const stats = (row.extraction_stats as Record<string, unknown> | null) ?? null;
  return {
    id: String(row.id),
    status: String(row.status) as CrawlJobStatus,
    auditRunId: row.audit_run_id ? String(row.audit_run_id) : null,
    requestedAt: (row.requested_at as string) ?? null,
    startedAt: (row.started_at as string) ?? null,
    completedAt: (row.completed_at as string) ?? null,
    heartbeatAt: (row.heartbeat_at as string) ?? null,
    cancellationRequestedAt: (row.cancellation_requested_at as string) ?? null,
    cancelledAt: (row.cancelled_at as string) ?? null,
    attemptCount: num(row.attempt_count),
    pagesDiscovered: num(row.pages_discovered),
    pagesCrawled: num(row.pages_crawled),
    pagesExtracted: stats ? optNum(stats.pagesExtracted) : null,
    issuesDetected: stats ? optNum(stats.issuesDetected) : null,
    errorCode: (row.error_code as string) ?? null,
    errorMessage: (row.error_message as string) ?? null,
  };
}

/** Request an audit-backed crawl. Returns BOTH ids directly (no latest guess). */
export async function requestSupabaseAuditCrawl(websiteId: string): Promise<RequestCrawlResult> {
  const { data, error } = await supabase.rpc(SEO_RPCS.crawlRequestAudit, {
    p_website_id: websiteId,
    p_idempotency_key: null,
    p_config: {},
  });
  if (error) throw new Error(normalizeSupabaseError(error).message);
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
  if (!row?.audit_run_id || !row?.crawl_job_id) {
    throw new Error("Crawl request did not return the expected audit run / job ids.");
  }
  return {
    auditRunId: String(row.audit_run_id),
    crawlJobId: String(row.crawl_job_id),
    jobStatus: String(row.job_status) as CrawlJobStatus,
  };
}

/** The most recent crawl job for a website (customer-safe fields only). */
export async function fetchSupabaseLatestCrawl(websiteId: string): Promise<CrawlJobView | null> {
  const { data, error } = await supabase
    .from(SEO_TABLES.crawlJobs)
    .select(JOB_COLUMNS)
    .eq("website_id", websiteId)
    .order("requested_at", { ascending: false })
    .limit(1);
  if (error) throw new Error(normalizeSupabaseError(error).message);
  const row = ((data ?? []) as unknown[])[0] as Record<string, unknown> | undefined;
  return row ? toJobView(row) : null;
}

/** Publication evidence for a crawl job (customer-safe). */
export async function fetchSupabaseCrawlPublication(
  jobId: string,
): Promise<CrawlPublicationView | null> {
  const { data, error } = await supabase
    .from(SEO_TABLES.crawlPublications)
    .select("status, pages_eligible, pages_published, issues_eligible, issues_published, crawl_partial, published_at")
    .eq("job_id", jobId)
    .order("publication_version", { ascending: false })
    .limit(1);
  if (error) throw new Error(normalizeSupabaseError(error).message);
  const row = ((data ?? []) as unknown[])[0] as Record<string, unknown> | undefined;
  if (!row) return null;
  return {
    status: String(row.status) as CrawlPublicationView["status"],
    pagesEligible: num(row.pages_eligible),
    pagesPublished: num(row.pages_published),
    issuesEligible: num(row.issues_eligible),
    issuesPublished: num(row.issues_published),
    crawlPartial: Boolean(row.crawl_partial),
    publishedAt: (row.published_at as string) ?? null,
  };
}

/** Cancel a crawl. Idempotent; returns the resulting customer-safe status. */
export async function cancelSupabaseCrawl(jobId: string): Promise<CrawlJobStatus> {
  const { data, error } = await supabase.rpc(SEO_RPCS.crawlCancel, { p_job_id: jobId });
  if (error) throw new Error(normalizeSupabaseError(error).message);
  return String(data) as CrawlJobStatus;
}
