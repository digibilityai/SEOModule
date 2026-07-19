import type { ClaimedJob, JobMeta } from "./jobGateway.js";
import type { WorkerConfig } from "./config.js";
import { CancellationRequestedError, NonRetryableExecutionError } from "./errors.js";

export interface ProcessResult {
  pagesCrawled: number;
  pagesDiscovered: number;
}

/**
 * Phase 1B SKELETON — performs NO crawling: no HTTP, no sitemap/robots, no HTML
 * parsing, no page-inventory/audit writes. It only exercises the job lifecycle.
 *
 * Safety: a real customer job must never be falsely "processed". Unless the
 * explicit dev flag `allowNonTestJobs` is set, the processor refuses any job
 * that is not a tagged TEST job (idempotency key prefix). This is why polling
 * mode is gated (see index.ts).
 */
export class SkeletonProcessor {
  constructor(private readonly cfg: WorkerConfig) {}

  isTestJob(meta: JobMeta): boolean {
    return meta.idempotencyKey.startsWith(this.cfg.testJobPrefix);
  }

  async process(
    _job: ClaimedJob,
    meta: JobMeta,
    isCancelledNow: () => Promise<boolean>,
  ): Promise<ProcessResult> {
    if (!this.isTestJob(meta) && !this.cfg.allowNonTestJobs) {
      throw new NonRetryableExecutionError(
        "crawler_not_implemented",
        "Crawling is not yet available for this website.",
        "SkeletonProcessor refused a non-test job (no dev flag).",
      );
    }
    // A single safe cancellation checkpoint stands in for real crawl work.
    if (await isCancelledNow()) throw new CancellationRequestedError();
    return { pagesCrawled: 0, pagesDiscovered: 0 };
  }
}
