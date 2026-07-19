// Phase 16H / Crawler 1F — deterministic MOCK crawl progression for mock mode.
// Never calls Supabase, never claims to be a real crawl. Time-based so the UI
// can demonstrate the lifecycle without a worker. In-memory only (per session).
import type {
  CrawlJobStatus,
  CrawlJobView,
  CrawlPublicationView,
  RequestCrawlResult,
} from "@/types/crawl";

interface MockCrawl {
  jobId: string;
  auditRunId: string;
  websiteId: string;
  startedMs: number;
  cancelled: boolean;
}

const store = new Map<string, MockCrawl>();

function uuidish(prefix: string): string {
  return `${prefix}-${Math.random().toString(16).slice(2, 10)}-${Date.now().toString(16)}`;
}

export function mockRequestAuditCrawl(websiteId: string): RequestCrawlResult {
  const crawl: MockCrawl = {
    jobId: uuidish("mockjob"),
    auditRunId: uuidish("mockrun"),
    websiteId,
    startedMs: Date.now(),
    cancelled: false,
  };
  store.set(websiteId, crawl);
  return { auditRunId: crawl.auditRunId, crawlJobId: crawl.jobId, jobStatus: "queued" };
}

function elapsedStatus(crawl: MockCrawl): CrawlJobStatus {
  if (crawl.cancelled) return "cancelled";
  const s = (Date.now() - crawl.startedMs) / 1000;
  if (s < 2) return "queued";
  if (s < 4) return "claimed";
  if (s < 7) return "running";
  return "completed";
}

export function mockFetchLatestCrawl(websiteId: string): CrawlJobView | null {
  const crawl = store.get(websiteId);
  if (!crawl) return null;
  const status = elapsedStatus(crawl);
  const done = status === "completed";
  return {
    id: crawl.jobId,
    status,
    auditRunId: crawl.auditRunId,
    requestedAt: new Date(crawl.startedMs).toISOString(),
    startedAt: status === "queued" ? null : new Date(crawl.startedMs + 2000).toISOString(),
    completedAt: done ? new Date(crawl.startedMs + 7000).toISOString() : null,
    heartbeatAt: done ? null : new Date().toISOString(),
    cancellationRequestedAt: null,
    cancelledAt: crawl.cancelled ? new Date().toISOString() : null,
    attemptCount: 1,
    pagesDiscovered: done ? 3 : status === "running" ? 2 : 0,
    pagesCrawled: done ? 3 : status === "running" ? 1 : 0,
    pagesExtracted: done ? 3 : null,
    issuesDetected: done ? 5 : null,
    errorCode: null,
    errorMessage: null,
  };
}

export function mockFetchCrawlPublication(jobId: string): CrawlPublicationView | null {
  for (const crawl of store.values()) {
    if (crawl.jobId !== jobId) continue;
    if (elapsedStatus(crawl) !== "completed") return null;
    return {
      status: "published",
      pagesEligible: 3,
      pagesPublished: 3,
      issuesEligible: 5,
      issuesPublished: 5,
      crawlPartial: false,
      publishedAt: new Date(crawl.startedMs + 7000).toISOString(),
    };
  }
  return null;
}

export function mockCancelCrawl(jobId: string): CrawlJobStatus {
  for (const crawl of store.values()) {
    if (crawl.jobId === jobId) {
      crawl.cancelled = true;
      return "cancelled";
    }
  }
  return "cancelled";
}
