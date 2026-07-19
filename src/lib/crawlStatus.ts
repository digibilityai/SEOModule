// Phase 16H / Crawler 1F — pure, framework-free helpers for the customer crawl
// UI (status labels, terminal/cancellable predicates, freshness formatting).
// Kept pure so they are trivially correct + unit-testable if a test framework
// is later added (the repo has none today).
import type { CrawlJobStatus } from "@/types/crawl";

export type CrawlTone = "pending" | "active" | "success" | "warning" | "error" | "neutral";

interface CrawlStatusMeta {
  label: string;
  tone: CrawlTone;
}

// Customer-safe labels for the unchanged Phase 16C statuses. No internal detail.
const STATUS_META: Record<CrawlJobStatus, CrawlStatusMeta> = {
  queued: { label: "Queued", tone: "pending" },
  claimed: { label: "Preparing", tone: "active" },
  running: { label: "Crawling", tone: "active" },
  retry_wait: { label: "Waiting to retry", tone: "warning" },
  cancellation_requested: { label: "Cancelling", tone: "warning" },
  completed: { label: "Completed", tone: "success" },
  partially_completed: { label: "Partially completed", tone: "warning" },
  failed: { label: "Failed", tone: "error" },
  cancelled: { label: "Cancelled", tone: "neutral" },
};

export function crawlStatusLabel(status: CrawlJobStatus): string {
  return STATUS_META[status]?.label ?? "Unknown";
}

export function crawlStatusTone(status: CrawlJobStatus): CrawlTone {
  return STATUS_META[status]?.tone ?? "neutral";
}

const TERMINAL: ReadonlySet<CrawlJobStatus> = new Set<CrawlJobStatus>([
  "completed",
  "partially_completed",
  "failed",
  "cancelled",
]);

export function isTerminalCrawlStatus(status: CrawlJobStatus): boolean {
  return TERMINAL.has(status);
}

// Cancellation does something only in these states (matches seo_crawl_cancel:
// queued/retry_wait → cancelled; claimed/running → cancellation_requested;
// terminal/already-requested → idempotent no-op, so the button is hidden).
const CANCELLABLE: ReadonlySet<CrawlJobStatus> = new Set<CrawlJobStatus>([
  "queued",
  "claimed",
  "running",
  "retry_wait",
]);

export function isCancellableCrawlStatus(status: CrawlJobStatus): boolean {
  return CANCELLABLE.has(status);
}

/** A job is "active" (worth polling) while it has not reached a terminal state. */
export function isActiveCrawlStatus(status: CrawlJobStatus): boolean {
  return !isTerminalCrawlStatus(status);
}

// Roles allowed to REQUEST/CANCEL a crawl (frontend affordance only; the RPC +
// RLS remain authoritative). Clients are excluded.
export const CRAWL_REQUEST_ROLES = ["owner", "admin", "team_member"] as const;

/**
 * Honest freshness label from a real timestamp — never the current browser
 * clock as the source. Returns null when there is no timestamp.
 */
export function formatCrawledOn(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
