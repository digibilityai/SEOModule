# Crawler Phase 1B — Worker Skeleton & Secure Job Lifecycle (Phase 16D)

**Status: Implemented + TEST-verified.** A dedicated background-worker foundation
that securely claims, leases, heartbeats, and terminally transitions crawl jobs
through guarded service-role-only functions — plus the additive DB lifecycle
contract (lease token + worker functions). **It performs NO crawling** (no HTTP,
sitemap, robots.txt, link extraction, HTML parsing, issue detection, page/audit
writes). **Not deployed. Crawling not operational. Production untouched.**
**Date:** 2026-07-14.

## Runtime / language decision — Node/TypeScript

Chosen because the repository is uniformly Node/TS/ESM with
`@supabase/supabase-js@^2.50.3`, npm + `package-lock.json`, Node v24, and strict
`tsconfig`. Python would introduce an unaligned toolchain with zero repo
evidence. The worker is a **separate package in `crawler-worker/`** (outside the
React `src/`), with its own `package.json`/`tsconfig`/tests, run via `tsx`.

## Directory structure

```
crawler-worker/
  package.json  tsconfig.json  Dockerfile  .dockerignore  .env.example
  src/  config.ts logger.ts errors.ts util.ts supabaseClient.ts
        jobGateway.ts processor.ts worker.ts index.ts
  test/ worker.test.ts
```

## Worker architecture

Internal execution service — **not** a customer-facing BFF. It reads/writes jobs
**only** through the approved worker RPCs, never exposes a public API, never
accepts external URLs, never makes customer authorization decisions, and trusts
only jobs already authorized + persisted by `seo_crawl_request`. Process modes
(CLI `--mode=`): **dry-run** (validate config + connectivity + worker-RPC
availability; no claim/mutation), **one-shot** (claim + process ONE job, then
exit), **poll** (production-shaped loop; **refuses to run** unless
`CRAWLER_ALLOW_NON_TEST_JOBS=true`, since no real processor exists). Layer
ownership: RLS + guarded RPCs own authorization; the worker owns execution via
service-role lifecycle functions only.

## Secure configuration

Typed, fail-fast (`config.ts`): `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
(secret), `CRAWLER_WORKER_ID`, `CRAWLER_POLL_INTERVAL_SECONDS`,
`CRAWLER_LEASE_SECONDS`, `CRAWLER_HEARTBEAT_SECONDS` (must be `< lease`),
`CRAWLER_MAX_JOBS`, `CRAWLER_ALLOW_NON_TEST_JOBS`, `CRAWLER_TEST_JOB_PREFIX`,
`CRAWLER_LOG_LEVEL`, `CRAWLER_ENV`. The service-role key is **redacted**
(`redactConfig`), never printed, never placed in exception text. `VITE_*` values
are rejected. `.env` is gitignored; only `.env.example` (names + descriptions) is
committed. The frontend never imports the worker (verified: no `crawler-worker`
import in `src/`; the built `dist/` contains no service-role name/JWT).

## Claim contract

Uses the existing `seo_crawl_claim_job(worker_id, lease_seconds)` (service-role
only) — never direct table select/update. Enhanced additively in migration 26 to
generate + return a **lease_token**. The worker claims one job, treats an empty
result as no work, validates required returned fields, binds all logs to the
job's `correlation_id`, and never claims a second job while one is unresolved
(one-job skeleton).

## Lease-token model

Each claim generates a random `lease_token`, stored on the job + attempt and
returned to the worker. **Every** lifecycle function requires
`(job_id, worker_id, lease_token)` and rejects a mismatched/cleared token
(`_seo_crawl_assert_owner`). A re-claim after lease expiry (via stale recovery)
issues a new token, so a stale earlier worker can no longer write — verified.

## Lifecycle functions (migration 20260714120026; service-role ONLY)

`seo_crawl_worker_heartbeat` (extends lease, no per-heartbeat event; only
claimed/running; rejects after cancellation/terminal), `…_complete`, `…_partial`,
`…_fail`, `…_schedule_retry` (retry_wait, or terminal `failed` at max attempts),
`…_acknowledge_cancellation` (cancellation_requested→cancelled), and
`seo_crawl_recover_stale_jobs` (idempotent, `SKIP LOCKED`). Each validates
ownership + current status, updates timestamps + the current attempt, records
**exactly one** lifecycle event, clears the lease at terminal/retry, keeps
customer-safe error fields on the job and internal diagnostics in the attempt,
and never accepts a caller-supplied workspace/role/user. All REVOKE
PUBLIC/anon/authenticated + GRANT service_role. Claim also service-role only.

## Heartbeat

`heartbeat` validates job + worker + lease token, permits only claimed/running,
extends `lease_expires_at` + `heartbeat_at`, optionally bumps bounded
(monotonic) progress counters, emits **no** event (avoids flooding), and rejects
after cancellation/terminal. The worker loop stops processing when heartbeat
renewal fails (ownership no longer trusted → `LeaseLostError`, no terminal write).

## Start & terminal transitions

Claim performs claim+start atomically (`queued/retry_wait → running`), so a
separate start RPC is unnecessary (documented). Terminal: `running → completed`
/ `partially_completed`; `running/claimed → failed`; `running/claimed →
retry_wait` (or `failed` at max attempts); `cancellation_requested → cancelled`.
No existing status string was changed.

## Retry

Uses Phase 16C fields (`attempt_count`, `max_attempts`, `retry_wait`,
`retry_after`). `computeRetryAfter` = deterministic bounded exponential backoff
(base 30s, cap 3600s), unit-tested. Terminal failure at max attempts. No
customer-triggered retry API. No plan limits hardcoded in the worker.

## Cancellation

The worker checks job status at safe checkpoints; on `cancellation_requested` it
stops, acknowledges via the worker-only RPC (`→ cancelled`), closes the attempt,
clears the lease, records one event, and never completes/fails or heartbeats
afterward. Verified at the DB level (before start + during) and end-to-end.

## Stale recovery

`seo_crawl_recover_stale_jobs` finds active jobs with an expired lease, closes
the abandoned attempt (`lease_expired`), moves the job to `retry_wait` (attempts
remain) or `failed`, clears lease ownership, records one `lease_expired` event,
is idempotent, and is concurrency-safe (`SKIP LOCKED`). Exposed as a worker
**startup recovery action** + a callable method (no scheduled infra this phase).

## Structured logging & graceful shutdown

JSON logs (`logger.ts`) with ts/level/env/workerId/jobId/attempt/correlationId/
action/outcome/duration; a redactor scrubs secret keys + JWT-like values. Never
logs the service-role key, tokens, auth headers, sessions, passwords, whole env
maps, or page content. Shutdown (SIGINT/SIGTERM) stops claiming, lets the current
op finish within grace, relies on lease expiry + stale recovery otherwise, and
never falsely marks a job completed.

## Container design

`Dockerfile` (node:22-slim, non-root `node` user, env-driven config, no secrets
in layers, `.dockerignore`, dry-run HEALTHCHECK, no frontend build, no
browser/crawling deps). **Not deployed** (no Cloud Run/K8s).

## Unit tests (`node:test`, 10 passing)

Config parse + fail-fast on missing secret + heartbeat<lease + redaction;
log-redactor (secrets/tokens/JWT-like); backoff determinism + cap; error
classification/flags; processor **refuses a non-test job** (and processes tagged
TEST jobs; honours cancellation; allows non-test only with the dev flag).

## Database verification (`seo_phase16d_worker_lifecycle_verification.sql`, ALL PASS)

Structure + service-role-only grants; happy path (claim→heartbeat→complete,
one completed event, attempt succeeded, idempotent complete, heartbeat rejected
after terminal); lease-token mismatch denied; **stale recovery invalidates the
old worker after reassignment**; retry scheduling + max-attempts terminal;
cancellation ack (+ idempotent, heartbeat rejected after cancellation);
existing customer RLS unchanged (member can't read internal attempts);
idempotent + self-cleaning.

## TEST integration evidence (server-side service-role, key never printed)

Disposable tagged job created via `seo_crawl_request`. **Dry-run:** no claim,
job stayed `queued`. **One-shot (happy):** claimed→started(+heartbeat)→
**completed**; attempt `succeeded`; events `queued,claimed,completed`;
**page-inventory + audit-issue counts unchanged (7/7) → no website request, no
page/audit data written**. **One-shot (refusal):** a non-test job was **failed**
with customer-safe `crawler_not_implemented` (internal code in the attempt).
**Poll mode refused** without the dev flag (exit 2). **No secret** appeared in
logs (config `[REDACTED]`, 0 JWT/service-role hits). All disposable jobs cleaned
up (0 residual); seed data unchanged; the `/tmp` env file was deleted.

## Security checks

No service-role key / hardcoded credential in `src/` or `crawler-worker/` (the
only `eyJ…` match is a **fake** JWT literal in the redaction unit test). Only
`.env.example` committed; `.env` gitignored. No worker import in the frontend;
`dist/` contains no worker secret name/JWT. No shell tracing; exceptions never
serialize secrets.

## Backward compatibility

Phase 16C RPC names + customer behaviour, customer RLS, job records, status
values, role matrix, frontend/service contracts, routes/auth, mock mode, and the
locked Page Performance + Stage 6 modules are all preserved (16C verification
still ALL PASS; frontend `tsc`/`build` clean). The claim function gained a
`lease_token` output column (additive; no existing consumer) — documented, not a
silent replacement.

## Known limitations

Worker is **not deployed**; **no crawling**; poll mode is intentionally gated;
plan/usage enforcement + external domain-ownership verification remain deferred
(Phase 16C notes); a real customer job claimed without the dev flag is failed
with "not available" (the worker must be run only against the TEST queue with
tagged jobs until Phase 1C).

## Rollback

- **Worker:** delete `crawler-worker/` + its container files; revert the
  `.gitignore` additions and the additive `supabaseTypes.ts` constants. No
  frontend behaviour depends on it.
- **Database:** `supabase/test/seo_phase16d_rollback_TEST_ONLY.sql` (drop worker
  functions + `_seo_crawl_assert_owner`, restore the pre-16D claim signature,
  drop the additive `lease_token` columns) — TEST-only; **do not execute unless
  instructed**. Preserves all Phase 16C objects; no customer data affected.
- **Docs:** revert the Phase 1B status/index references.

## Phase 1C boundary

**Update — Phase 16E / Crawler 1C (2026-07-14): the discovery engine is now
implemented + TEST-verified** — URL safety, SSRF + connection-time
DNS-rebinding-safe fetching, robots.txt (RFC 9309), XXE-safe sitemap parsing,
`<a>`-only same-origin HTML discovery, budgeted BFS, and worker-only discovery
persistence (migration `20260714120027`). It calls these lifecycle functions with
real progress + a new record RPC. It writes **no** page-inventory/audit data
(that stays Phase 1D behind locked-scope regression) and the crawler is not
customer-available. See `CRAWLER_PHASE_1C_DISCOVERY_ENGINE.md`. The Phase 1B
worker `DiscoveryProcessor` now drives discovery for tagged TEST jobs (still
refuses non-test jobs; real network only via the SSRF-safe transport). **Phase 1D
(16F) extended the processor pipeline** to run extraction + issue detection +
site-duplicate detection + worker-only persistence after discovery, using the
same lease/heartbeat/cancellation/terminal lifecycle RPCs — see
`CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`.
