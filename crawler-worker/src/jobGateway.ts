import type { SupabaseClient } from "@supabase/supabase-js";
import { ContractError } from "./errors.js";

// All job state changes go through the guarded, service-role-only worker RPCs
// (migrations 25/26). The worker never updates seo_crawl_* tables directly.

export interface ClaimedJob {
  jobId: string;
  websiteId: string;
  websiteUrl: string;
  workspaceId: string;
  attemptNumber: number;
  config: Record<string, unknown>;
  leaseExpiresAt: string;
  leaseToken: string;
}

export interface JobMeta {
  status: string;
  idempotencyKey: string;
  correlationId: string;
}

export class JobGateway {
  constructor(private readonly db: SupabaseClient) {}

  /** Non-mutating connectivity + permission + function-availability probe. */
  async healthCheck(): Promise<void> {
    const { error } = await this.db.rpc("seo_crawl_recover_stale_jobs", { p_now: new Date().toISOString(), p_limit: 0 });
    if (error) throw new ContractError(`worker RPC contract check failed: ${error.message}`);
  }

  async claim(workerId: string, leaseSeconds: number): Promise<ClaimedJob | null> {
    const { data, error } = await this.db.rpc("seo_crawl_claim_job", {
      p_worker_id: workerId,
      p_lease_seconds: leaseSeconds,
    });
    if (error) throw new ContractError(`claim failed: ${error.message}`);
    const rows = (data as unknown[]) ?? [];
    if (rows.length === 0) return null;
    const r = rows[0] as Record<string, unknown>;
    const job: ClaimedJob = {
      jobId: String(r.job_id),
      websiteId: String(r.website_id),
      websiteUrl: String(r.website_url),
      workspaceId: String(r.workspace_id),
      attemptNumber: Number(r.attempt_number),
      config: (r.config as Record<string, unknown>) ?? {},
      leaseExpiresAt: String(r.lease_expires_at),
      leaseToken: String(r.lease_token),
    };
    // Validate required fields returned by the contract.
    if (!job.jobId || !job.leaseToken || !job.websiteUrl || !Number.isInteger(job.attemptNumber)) {
      throw new ContractError("claim returned an incomplete job row");
    }
    return job;
  }

  async getMeta(jobId: string): Promise<JobMeta> {
    const { data, error } = await this.db
      .from("seo_crawl_jobs")
      .select("status, idempotency_key, correlation_id")
      .eq("id", jobId)
      .single();
    if (error) throw new ContractError(`getMeta failed: ${error.message}`);
    return {
      status: String(data.status),
      idempotencyKey: String(data.idempotency_key),
      correlationId: String(data.correlation_id),
    };
  }

  async heartbeat(
    jobId: string,
    workerId: string,
    token: string,
    leaseSeconds: number,
    pagesCrawled?: number,
    pagesDiscovered?: number,
  ): Promise<string> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_heartbeat", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token,
      p_lease_seconds: leaseSeconds,
      p_pages_crawled: pagesCrawled ?? null, p_pages_discovered: pagesDiscovered ?? null,
    });
    if (error) throw new ContractError(`heartbeat failed: ${error.message}`);
    return String(data);
  }

  async complete(jobId: string, workerId: string, token: string, pagesCrawled: number): Promise<string> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_complete", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token, p_pages_crawled: pagesCrawled,
    });
    if (error) throw new ContractError(`complete failed: ${error.message}`);
    return String(data);
  }

  async partial(jobId: string, workerId: string, token: string, pagesCrawled: number, errorCode?: string, customerMessage?: string): Promise<string> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_partial", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token, p_pages_crawled: pagesCrawled,
      p_error_code: errorCode ?? null, p_error_message: customerMessage ?? null,
    });
    if (error) throw new ContractError(`partial failed: ${error.message}`);
    return String(data);
  }

  async fail(
    jobId: string, workerId: string, token: string,
    errorCode: string, customerMessage: string, retryClass: "retryable" | "non_retryable", internal?: string,
  ): Promise<string> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_fail", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token,
      p_error_code: errorCode, p_error_message: customerMessage, p_retry_class: retryClass,
      p_internal_detail: internal ?? null,
    });
    if (error) throw new ContractError(`fail failed: ${error.message}`);
    return String(data);
  }

  async scheduleRetry(
    jobId: string, workerId: string, token: string,
    retryAfterIso: string, errorCode: string, customerMessage: string, internal?: string,
  ): Promise<string> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_schedule_retry", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token,
      p_retry_after: retryAfterIso, p_error_code: errorCode, p_error_message: customerMessage,
      p_internal_detail: internal ?? null,
    });
    if (error) throw new ContractError(`scheduleRetry failed: ${error.message}`);
    return String(data);
  }

  async acknowledgeCancellation(jobId: string, workerId: string, token: string): Promise<string> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_acknowledge_cancellation", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token,
    });
    if (error) throw new ContractError(`ackCancellation failed: ${error.message}`);
    return String(data);
  }

  // Phase 1C — bulk-record discovered pages + sitemaps (worker-only RPC; the RPC
  // validates ownership + derives workspace/website server-side).
  async recordDiscovery(
    jobId: string, workerId: string, token: string, pages: unknown[], sitemaps: unknown[],
  ): Promise<number> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_record_discovery", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token,
      p_pages: pages, p_sitemaps: sitemaps,
    });
    if (error) throw new ContractError(`recordDiscovery failed: ${error.message}`);
    return Number(data);
  }

  // Phase 1D — extraction persistence (worker-only RPCs).
  async recordSnapshots(jobId: string, workerId: string, token: string, snapshots: unknown[]): Promise<number> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_record_snapshots", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token, p_snapshots: snapshots,
    });
    if (error) throw new ContractError(`recordSnapshots failed: ${error.message}`);
    return Number(data);
  }

  async recordIssues(jobId: string, workerId: string, token: string, issues: unknown[], pageSnapshotId: string | null): Promise<number> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_record_issues", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token, p_issues: issues, p_page_snapshot_id: pageSnapshotId,
    });
    if (error) throw new ContractError(`recordIssues failed: ${error.message}`);
    return Number(data);
  }

  async updateExtractionProgress(jobId: string, workerId: string, token: string, stats: unknown): Promise<void> {
    const { error } = await this.db.rpc("seo_crawl_worker_update_extraction_progress", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token, p_stats: stats,
    });
    if (error) throw new ContractError(`updateExtractionProgress failed: ${error.message}`);
  }

  /** Resolve snapshot ids for page-level issue persistence (service-role read). */
  async getSnapshotIds(jobId: string): Promise<Map<string, string>> {
    const { data, error } = await this.db
      .from("seo_crawl_page_snapshots").select("id, requested_url").eq("job_id", jobId);
    if (error) throw new ContractError(`getSnapshotIds failed: ${error.message}`);
    const map = new Map<string, string>();
    for (const row of (data ?? []) as Array<{ id: string; requested_url: string }>) map.set(row.requested_url, row.id);
    return map;
  }

  async updateDiscoveryProgress(jobId: string, workerId: string, token: string, stats: unknown): Promise<void> {
    const { error } = await this.db.rpc("seo_crawl_worker_update_discovery_progress", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token, p_stats: stats,
    });
    if (error) throw new ContractError(`updateDiscoveryProgress failed: ${error.message}`);
  }

  // Phase 1E — one transactional publish into Page Inventory + Audit Issues.
  // The RPC reads the persisted crawler-domain records server-side and derives
  // the audit run from the job's explicit association; the worker sends NO page/
  // issue payload, NO status and NO counts. Returns the RPC's raw result object.
  async publishResults(
    jobId: string, workerId: string, token: string, publicationVersion: number,
  ): Promise<Record<string, unknown>> {
    const { data, error } = await this.db.rpc("seo_crawl_worker_publish_results", {
      p_job_id: jobId, p_worker_id: workerId, p_lease_token: token,
      p_publication_version: publicationVersion,
    });
    if (error) throw new ContractError(`publishResults failed: ${error.message}`);
    return (data as Record<string, unknown>) ?? {};
  }

  async recoverStale(limit = 100): Promise<number> {
    const { data, error } = await this.db.rpc("seo_crawl_recover_stale_jobs", {
      p_now: new Date().toISOString(), p_limit: limit,
    });
    if (error) throw new ContractError(`recoverStale failed: ${error.message}`);
    return Number(data);
  }
}
