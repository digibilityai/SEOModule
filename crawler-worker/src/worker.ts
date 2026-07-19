import type { WorkerConfig } from "./config.js";
import type { Logger } from "./logger.js";
import { JobGateway, type ClaimedJob } from "./jobGateway.js";
import { DiscoveryProcessor } from "./discovery/discoveryProcessor.js";
import {
  CancellationRequestedError, LeaseLostError, WorkerError, classifyUnknown,
} from "./errors.js";
import { computeRetryAfter } from "./util.js";

export type JobOutcome =
  | "completed" | "partially_completed" | "failed" | "retry_wait"
  | "cancelled" | "lease_lost" | "no_terminal";

export class Worker {
  private stopping = false;
  private readonly processor: DiscoveryProcessor;

  constructor(
    private readonly cfg: WorkerConfig,
    private readonly gateway: JobGateway,
    private readonly log: Logger,
  ) {
    this.processor = new DiscoveryProcessor(cfg, gateway);
  }

  requestStop(): void { this.stopping = true; }

  /** One safe claim+process cycle. Returns null when there is no work. */
  async runOnce(): Promise<{ jobId: string; outcome: JobOutcome } | null> {
    const job = await this.gateway.claim(this.cfg.workerId, this.cfg.leaseSeconds);
    if (!job) return null;
    const outcome = await this.processClaimed(job);
    return { jobId: job.jobId, outcome };
  }

  /** Poll loop, bounded by maxJobs + graceful stop. */
  async runPoll(): Promise<void> {
    let processed = 0;
    while (!this.stopping && processed < this.cfg.maxJobs) {
      const result = await this.runOnce();
      if (!result) {
        // idle backoff
        await new Promise((r) => setTimeout(r, this.cfg.pollIntervalSeconds * 1000));
        continue;
      }
      processed += 1;
    }
    this.log.info("poll loop stopped", { outcome: this.stopping ? "graceful_stop" : "max_jobs", action: "poll_end" });
  }

  private async processClaimed(job: ClaimedJob): Promise<JobOutcome> {
    const jobLog = this.log.child({
      jobId: job.jobId, attemptNumber: job.attemptNumber, action: "process",
    });
    const started = Date.now();
    let leaseToken = job.leaseToken;
    let leaseLost = false;

    // Heartbeat timer — on lease loss, stop trusting ownership.
    const heartbeatMs = this.cfg.heartbeatSeconds * 1000;
    const timer = setInterval(() => {
      void this.gateway
        .heartbeat(job.jobId, this.cfg.workerId, leaseToken, this.cfg.leaseSeconds)
        .catch((e) => {
          leaseLost = true;
          jobLog.warn("heartbeat failed — lease may be lost, stopping", {
            action: "heartbeat", outcome: "lost", detail: e instanceof Error ? e.message : String(e),
          });
        });
    }, heartbeatMs);

    const isCancelledNow = async (): Promise<boolean> => {
      const meta = await this.gateway.getMeta(job.jobId);
      return meta.status === "cancellation_requested";
    };

    try {
      const meta = await this.gateway.getMeta(job.jobId);
      const boundLog = this.log.child({ jobId: job.jobId, attemptNumber: job.attemptNumber, correlationId: meta.correlationId });

      // Already cancelled before start.
      if (meta.status === "cancellation_requested") {
        await this.gateway.acknowledgeCancellation(job.jobId, this.cfg.workerId, leaseToken);
        boundLog.info("acknowledged cancellation before start", { action: "cancel_ack", outcome: "cancelled" });
        return "cancelled";
      }

      // At least one explicit heartbeat so short skeleton work still renews the lease.
      leaseToken = job.leaseToken;
      await this.gateway.heartbeat(job.jobId, this.cfg.workerId, leaseToken, this.cfg.leaseSeconds);
      boundLog.info("started", { action: "start" });

      const result = await this.processor.process(job, meta, isCancelledNow);

      if (leaseLost) throw new LeaseLostError();

      // Re-check cancellation at the safe checkpoint after "work".
      if (await isCancelledNow()) {
        await this.gateway.acknowledgeCancellation(job.jobId, this.cfg.workerId, leaseToken);
        boundLog.info("acknowledged cancellation after work", { action: "cancel_ack", outcome: "cancelled" });
        return "cancelled";
      }

      if (result.partial) {
        await this.gateway.partial(job.jobId, this.cfg.workerId, leaseToken, result.pagesCrawled);
        boundLog.info("partially completed", { action: "partial", outcome: "partially_completed", durationMs: Date.now() - started });
        return "partially_completed";
      }
      await this.gateway.complete(job.jobId, this.cfg.workerId, leaseToken, result.pagesCrawled);
      boundLog.info("completed", { action: "complete", outcome: "completed", durationMs: Date.now() - started });
      return "completed";
    } catch (err) {
      return await this.handleError(job, leaseToken, jobLog, classifyUnknown(err), leaseLost);
    } finally {
      clearInterval(timer);
    }
  }

  private async handleError(
    job: ClaimedJob, leaseToken: string, jobLog: ReturnType<Logger["child"]>, e: WorkerError, leaseLost: boolean,
  ): Promise<JobOutcome> {
    // Lease lost → ownership gone: never write a terminal state (stale recovery
    // will reclaim/retry the job). Internal detail stays in logs.
    if (e instanceof LeaseLostError || leaseLost) {
      jobLog.warn("lease lost — leaving job for stale recovery", { action: "lease_lost", outcome: "lease_lost" });
      return "lease_lost";
    }
    if (e instanceof CancellationRequestedError) {
      try {
        await this.gateway.acknowledgeCancellation(job.jobId, this.cfg.workerId, leaseToken);
        return "cancelled";
      } catch {
        jobLog.warn("cancellation ack failed (likely lease lost)", { action: "cancel_ack", outcome: "no_terminal" });
        return "no_terminal";
      }
    }
    if (e.retryable && job.attemptNumber < 999) {
      const retryAfter = computeRetryAfter(job.attemptNumber);
      const code = "code" in e ? String((e as { code?: string }).code) : "retryable_error";
      const status = await this.gateway.scheduleRetry(
        job.jobId, this.cfg.workerId, leaseToken, retryAfter, code, e.customerSafeMessage, e.message,
      );
      jobLog.warn("scheduled retry / terminal", { action: "retry", outcome: status });
      return status === "failed" ? "failed" : "retry_wait";
    }
    // Non-retryable → fail with a customer-safe message; internal detail to logs only.
    const code = "code" in e ? String((e as { code?: string }).code) : "non_retryable_error";
    await this.gateway.fail(job.jobId, this.cfg.workerId, leaseToken, code, e.customerSafeMessage, "non_retryable", e.message);
    jobLog.warn("job failed (non-retryable)", { action: "fail", outcome: "failed" });
    return "failed";
  }
}
