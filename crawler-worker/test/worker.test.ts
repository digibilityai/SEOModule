import { test } from "node:test";
import assert from "node:assert/strict";
import { loadConfig, redactConfig, ConfigError, type WorkerConfig } from "../src/config.js";
import { computeRetryAfter } from "../src/util.js";
import { _redactForTest } from "../src/logger.js";
import {
  RetryableExecutionError, NonRetryableExecutionError, LeaseLostError,
  CancellationRequestedError, classifyUnknown,
} from "../src/errors.js";
import { SkeletonProcessor } from "../src/processor.js";
import type { ClaimedJob, JobMeta } from "../src/jobGateway.js";

const BASE_ENV = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "eyTESTSERVICEROLEKEYvalue.aaa.bbb",
  CRAWLER_WORKER_ID: "w1",
} as NodeJS.ProcessEnv;

test("config: fails fast when the service-role key is missing", () => {
  assert.throws(() => loadConfig({ SUPABASE_URL: "https://x.supabase.co" } as NodeJS.ProcessEnv), ConfigError);
});

test("config: rejects heartbeat >= lease", () => {
  assert.throws(
    () => loadConfig({ ...BASE_ENV, CRAWLER_LEASE_SECONDS: "60", CRAWLER_HEARTBEAT_SECONDS: "60" }),
    ConfigError,
  );
});

test("config: redaction never exposes the service-role key", () => {
  const cfg = loadConfig(BASE_ENV);
  const red = redactConfig(cfg);
  assert.equal(red.serviceRoleKey, "[REDACTED]");
  assert.equal(JSON.stringify(red).includes(cfg.serviceRoleKey), false);
});

test("logger: redactor hides secrets, tokens and JWT-like values", () => {
  const out = _redactForTest("root", {
    service_role: "abc",
    lease_token: "plain",
    nested: { authorization: "Bearer x", ok: "visible" },
    keyish: "eyJhbGciOiJIUzI1NiJ9.payload.sig",
  }) as Record<string, any>;
  assert.equal(out.service_role, "[REDACTED]");
  assert.equal(out.nested.authorization, "[REDACTED]");
  assert.equal(out.nested.ok, "visible");
  assert.equal(out.keyish, "[REDACTED]"); // JWT-like value scrubbed
});

test("util: exponential backoff is bounded + deterministic", () => {
  const now = new Date("2026-07-14T00:00:00.000Z");
  assert.equal(computeRetryAfter(1, 30, 3600, now), "2026-07-14T00:00:30.000Z"); // 30s
  assert.equal(computeRetryAfter(2, 30, 3600, now), "2026-07-14T00:01:00.000Z"); // 60s
  assert.equal(computeRetryAfter(3, 30, 3600, now), "2026-07-14T00:02:00.000Z"); // 120s
  assert.equal(computeRetryAfter(20, 30, 3600, now), "2026-07-14T01:00:00.000Z"); // capped 3600s
});

test("errors: classification flags", () => {
  assert.equal(new RetryableExecutionError("x", "safe").retryable, true);
  assert.equal(new NonRetryableExecutionError("x", "safe").retryable, false);
  assert.equal(new LeaseLostError().retryable, false);
  assert.equal(classifyUnknown(new Error("boom")).kind, "internal");
  assert.equal(new NonRetryableExecutionError("x", "safe message").customerSafeMessage, "safe message");
});

const cfgWith = (over: Partial<WorkerConfig>): WorkerConfig => ({
  supabaseUrl: "https://x.supabase.co", serviceRoleKey: "eyk.a.b", workerId: "w1",
  pollIntervalSeconds: 5, leaseSeconds: 300, heartbeatSeconds: 60, maxJobs: 1,
  allowNonTestJobs: false, testJobPrefix: "PHASE16D-VERIFY-", logLevel: "info", environment: "test",
  ...over,
});
const job: ClaimedJob = {
  jobId: "j1", websiteId: "s1", websiteUrl: "https://x.example", workspaceId: "w",
  attemptNumber: 1, config: {}, leaseExpiresAt: "", leaseToken: "t",
};
const meta = (key: string): JobMeta => ({ status: "running", idempotencyKey: key, correlationId: "c1" });

test("processor: refuses a non-test job without the dev flag", async () => {
  const p = new SkeletonProcessor(cfgWith({}));
  await assert.rejects(
    () => p.process(job, meta("real-customer-job"), async () => false),
    (e: unknown) => e instanceof NonRetryableExecutionError && (e as NonRetryableExecutionError).code === "crawler_not_implemented",
  );
});

test("processor: processes a tagged TEST job (no crawling)", async () => {
  const p = new SkeletonProcessor(cfgWith({}));
  const res = await p.process(job, meta("PHASE16D-VERIFY-x"), async () => false);
  assert.deepEqual(res, { pagesCrawled: 0, pagesDiscovered: 0 });
});

test("processor: honours cancellation at the checkpoint", async () => {
  const p = new SkeletonProcessor(cfgWith({}));
  await assert.rejects(
    () => p.process(job, meta("PHASE16D-VERIFY-x"), async () => true),
    CancellationRequestedError,
  );
});

test("processor: allows a non-test job only with the explicit dev flag", async () => {
  const p = new SkeletonProcessor(cfgWith({ allowNonTestJobs: true }));
  const res = await p.process(job, meta("real-job"), async () => false);
  assert.equal(res.pagesCrawled, 0);
});
