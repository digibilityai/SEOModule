// CLI entry point. Modes:
//   --mode=dry-run     validate config + connectivity + worker RPC availability; no claim/mutation
//   --mode=one-shot    claim + process ONE crawl job (test jobs only unless dev flag), then exit
//   --mode=poll        production-shaped crawl loop; REFUSES to run unless the dev flag is set
//                      (no real crawler processor exists yet)
//   --mode=verify-once claim + resolve ONE DNS-TXT ownership-verification item, then exit
//                      (P1a Step 3; fully independent of the crawl processor)
import { loadConfig, redactConfig } from "./config.js";
import { Logger } from "./logger.js";
import { createWorkerSupabase } from "./supabaseClient.js";
import { JobGateway } from "./jobGateway.js";
import { Worker } from "./worker.js";
import { parseMode } from "./modes.js";
import { VerificationGateway } from "./verification/verificationGateway.js";
import { NodeDnsTxtResolver, FixtureDnsTxtResolver, type DnsTxtResolver } from "./verification/dns.js";
import { runVerificationOnce } from "./verification/runner.js";

async function main(): Promise<number> {
  const mode = parseMode(process.argv.slice(2));
  const cfg = loadConfig();
  const log = new Logger(cfg.logLevel, { workerId: cfg.workerId, environment: cfg.environment });
  log.info("worker starting", { action: "startup", mode, config: redactConfig(cfg) });

  const db = createWorkerSupabase(cfg);

  // P1a Step 3 — ownership verification. Handled BEFORE the crawl JobGateway is
  // constructed so verify-once never touches the crawl control plane, processor,
  // health check, or stale-recovery. No crawl object is referenced in this path.
  if (mode === "verify-once") {
    const resolver: DnsTxtResolver = cfg.verificationFixtureDnsPath
      ? new FixtureDnsTxtResolver(cfg.verificationFixtureDnsPath)
      : new NodeDnsTxtResolver();
    const vgateway = new VerificationGateway(db);
    let stopRequested = false;
    const onSignal = (sig: string) => {
      log.warn("shutdown signal received", { action: "shutdown", outcome: sig });
      stopRequested = true;
    };
    process.on("SIGINT", () => onSignal("SIGINT"));
    process.on("SIGTERM", () => onSignal("SIGTERM"));
    const res = await runVerificationOnce({
      gateway: vgateway,
      resolver,
      log,
      workerId: cfg.workerId,
      leaseSeconds: cfg.verificationLeaseSeconds ?? 120,
      timeoutMs: 5000,
      isStopRequested: () => stopRequested,
    });
    log.info("verify-once complete", { action: "verify_once", outcome: res.outcome, verificationId: res.verificationId });
    return 0;
  }

  const gateway = new JobGateway(db);

  // Connectivity + service-role permission + worker-RPC availability (non-mutating).
  await gateway.healthCheck();
  log.info("health check ok", { action: "health" });

  if (mode === "dry-run") {
    log.info("dry-run complete — no job claimed, no mutation", { action: "dry_run", outcome: "ok" });
    return 0;
  }

  // Startup stale-lease recovery (safe, idempotent).
  const recovered = await gateway.recoverStale(100);
  if (recovered > 0) log.info("recovered stale jobs at startup", { action: "recover", outcome: String(recovered) });

  const worker = new Worker(cfg, gateway, log);

  // Graceful shutdown: stop claiming; rely on lease expiry + stale recovery for
  // anything still in flight; never falsely mark a job completed.
  const shutdown = (sig: string) => {
    log.warn("shutdown signal received", { action: "shutdown", outcome: sig });
    worker.requestStop();
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));

  if (mode === "one-shot") {
    const result = await worker.runOnce();
    if (!result) log.info("one-shot: no eligible job", { action: "one_shot", outcome: "no_work" });
    else log.info("one-shot complete", { action: "one_shot", jobId: result.jobId, outcome: result.outcome });
    return 0;
  }

  // poll
  if (!cfg.allowNonTestJobs) {
    log.error(
      "poll mode is disabled: no real crawler processor exists yet. Set CRAWLER_ALLOW_NON_TEST_JOBS=true only in a safe dev/TEST context, or use --mode=one-shot with a tagged TEST job.",
      { action: "poll_refused", outcome: "blocked" },
    );
    return 2;
  }
  await worker.runPoll();
  return 0;
}

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    // Fail-safe: never print secrets; config/contract failures exit non-zero.
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(JSON.stringify({ ts: new Date().toISOString(), level: "error", msg: "worker fatal", detail: msg }) + "\n");
    process.exit(1);
  });
