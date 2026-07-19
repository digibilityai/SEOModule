// Phase 16H / Crawler 1F — customer-facing crawl types. Customer-SAFE only:
// never lease tokens, worker ids, correlation ids, raw config, or internal
// diagnostics. Mirrors the Phase 16C–16G contracts (statuses unchanged).

export type CrawlJobStatus =
  | "queued"
  | "claimed"
  | "running"
  | "retry_wait"
  | "cancellation_requested"
  | "completed"
  | "partially_completed"
  | "failed"
  | "cancelled";

/** A customer-safe projection of one crawl job. */
export interface CrawlJobView {
  id: string;
  status: CrawlJobStatus;
  auditRunId: string | null;
  requestedAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  /** Last worker heartbeat — used only as a freshness hint. */
  heartbeatAt: string | null;
  cancellationRequestedAt: string | null;
  cancelledAt: string | null;
  attemptCount: number;
  pagesDiscovered: number;
  pagesCrawled: number;
  /** From extraction_stats when present; null when not yet populated. */
  pagesExtracted: number | null;
  issuesDetected: number | null;
  /** Customer-safe fields only. */
  errorCode: string | null;
  errorMessage: string | null;
}

export type CrawlPublicationStatus = "running" | "published" | "failed";

/** Customer-safe projection of the publication evidence for a crawl. */
export interface CrawlPublicationView {
  status: CrawlPublicationStatus;
  pagesEligible: number;
  pagesPublished: number;
  issuesEligible: number;
  issuesPublished: number;
  crawlPartial: boolean;
  publishedAt: string | null;
}

/** Direct result of the orchestration RPC — both ids, no "latest" guess. */
export interface RequestCrawlResult {
  auditRunId: string;
  crawlJobId: string;
  jobStatus: CrawlJobStatus;
}
