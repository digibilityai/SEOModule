// Phase 1E — controlled publishing coordinator.
//
// Ownership split: the DATABASE owns the final product-table mapping + integrity
// (one transactional service-role RPC). The WORKER only orchestrates the call,
// validates the returned counts/status, logs safe metrics, and classifies
// failures for the existing lifecycle. The worker NEVER:
//   - sends page/issue payloads, statuses or counts to the RPC,
//   - inserts directly into seo_page_inventory / seo_audit_issues,
//   - guesses an audit run (the RPC derives it from the job's explicit link).
import type { JobGateway } from "../jobGateway.js";
import {
  LeaseLostError, CancellationRequestedError,
  RetryableExecutionError, NonRetryableExecutionError,
} from "../errors.js";

// One publication-contract version. A future mapping/severity/provenance change
// must bump this rather than silently reinterpret historical publications.
export const PUBLICATION_VERSION = 1;

export type PublishStatus = "published" | "skipped_no_association" | "no_results";

export interface PublishOutcome {
  status: PublishStatus;
  pagesEligible: number;
  pagesPublished: number;
  issuesEligible: number;
  issuesPublished: number;
  auditRunId: string | null;
  publicationId: string | null;
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Validate + normalize the RPC result. Throws on an incoherent contract reply. */
export function parsePublicationResult(raw: Record<string, unknown>): PublishOutcome {
  const status = String(raw.status ?? "");
  if (status !== "published" && status !== "skipped_no_association" && status !== "no_results") {
    throw new NonRetryableExecutionError("publish_contract", "The crawl results could not be published.", `unexpected publish status: ${status}`);
  }
  const out: PublishOutcome = {
    status: status as PublishStatus,
    pagesEligible: num(raw.pagesEligible),
    pagesPublished: num(raw.pagesPublished),
    issuesEligible: num(raw.issuesEligible),
    issuesPublished: num(raw.issuesPublished),
    auditRunId: raw.auditRunId == null ? null : String(raw.auditRunId),
    publicationId: raw.publicationId == null ? null : String(raw.publicationId),
  };
  // A "published" reply must not claim to have written more than were eligible.
  if (out.status === "published" && out.pagesPublished > out.pagesEligible) {
    throw new NonRetryableExecutionError("publish_contract", "The crawl results could not be published.", "pagesPublished exceeds pagesEligible");
  }
  return out;
}

/** Map a raw RPC/database error to the worker error taxonomy. */
export function classifyPublishError(err: unknown): never {
  const msg = err instanceof Error ? err.message : String(err);
  if (/lease lost|reassigned/i.test(msg)) throw new LeaseLostError(msg);
  if (/status cancellation_requested|cancelled\/terminal/i.test(msg)) throw new CancellationRequestedError();
  // Deterministic contract violations are permanent (retrying will not help).
  if (/mismatch|unmapped crawler issue|different source|not in a publishable state|already finished/i.test(msg)) {
    throw new NonRetryableExecutionError("publish_contract", "The crawl results could not be published.", msg);
  }
  // Everything else (transient DB/connectivity) is retryable via the lifecycle.
  throw new RetryableExecutionError("publish_error", "The crawl results could not be saved.", msg);
}

/**
 * Invoke the transactional publishing RPC exactly once and interpret the result.
 * Idempotent replay returns "published" again with stable counts (treated as
 * success). "skipped_no_association" is the generic-crawl path (nothing to do).
 */
export async function publishJobResults(
  gateway: JobGateway, jobId: string, workerId: string, leaseToken: string,
): Promise<PublishOutcome> {
  let raw: Record<string, unknown>;
  try {
    raw = await gateway.publishResults(jobId, workerId, leaseToken, PUBLICATION_VERSION);
  } catch (err) {
    classifyPublishError(err);
  }
  return parsePublicationResult(raw!);
}
