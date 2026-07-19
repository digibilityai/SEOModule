// Worker error taxonomy. Each error separates a CUSTOMER-SAFE message (safe to
// persist in seo_crawl_jobs.error_message) from internal diagnostics (kept in
// logs + the internal attempt record). No crawling-specific HTTP classes yet.

export type ErrorKind =
  | "config"
  | "contract"
  | "lease_lost"
  | "cancellation_requested"
  | "retryable"
  | "non_retryable"
  | "internal";

export abstract class WorkerError extends Error {
  abstract readonly kind: ErrorKind;
  /** Safe to store in a customer-visible field. Never contains secrets/stack. */
  abstract readonly customerSafeMessage: string;
  /** Whether the job should be retried (worker retry contract). */
  abstract readonly retryable: boolean;
}

export class ContractError extends WorkerError {
  readonly kind = "contract" as const;
  readonly customerSafeMessage = "The crawl service is misconfigured.";
  readonly retryable = false;
  constructor(message: string) { super(message); this.name = "ContractError"; }
}

export class LeaseLostError extends WorkerError {
  readonly kind = "lease_lost" as const;
  readonly customerSafeMessage = "The crawl lease was lost.";
  readonly retryable = false; // do NOT write a terminal state — ownership is gone
  constructor(message = "Lease lost or reassigned") { super(message); this.name = "LeaseLostError"; }
}

export class CancellationRequestedError extends WorkerError {
  readonly kind = "cancellation_requested" as const;
  readonly customerSafeMessage = "The crawl was cancelled.";
  readonly retryable = false;
  constructor(message = "Cancellation requested") { super(message); this.name = "CancellationRequestedError"; }
}

export class RetryableExecutionError extends WorkerError {
  readonly kind = "retryable" as const;
  readonly retryable = true;
  readonly customerSafeMessage: string;
  readonly code: string;
  constructor(code: string, customerSafeMessage: string, internal?: string) {
    super(internal ?? customerSafeMessage);
    this.name = "RetryableExecutionError";
    this.code = code;
    this.customerSafeMessage = customerSafeMessage;
  }
}

export class NonRetryableExecutionError extends WorkerError {
  readonly kind = "non_retryable" as const;
  readonly retryable = false;
  readonly customerSafeMessage: string;
  readonly code: string;
  constructor(code: string, customerSafeMessage: string, internal?: string) {
    super(internal ?? customerSafeMessage);
    this.name = "NonRetryableExecutionError";
    this.code = code;
    this.customerSafeMessage = customerSafeMessage;
  }
}

export class UnexpectedInternalError extends WorkerError {
  readonly kind = "internal" as const;
  readonly retryable = true;
  readonly customerSafeMessage = "The crawl could not be completed due to an internal error.";
  readonly code = "internal_error";
  constructor(message: string) { super(message); this.name = "UnexpectedInternalError"; }
}

export function classifyUnknown(err: unknown): WorkerError {
  if (err instanceof WorkerError) return err;
  const msg = err instanceof Error ? err.message : String(err);
  return new UnexpectedInternalError(msg);
}
