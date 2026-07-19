# Crawler Phase 1A — Job Control-Plane Data Contract (Phase 16C)

**Status: Implemented + TEST-verified on `Digi_SEO_Test`.** This is the
**database contract only** — a guarded, RLS-scoped crawler job/status/event/
attempt schema plus request/cancel/worker-claim functions. **No crawler runs:**
no worker, Edge Function, sitemap, HTML fetch, robots.txt, URL extraction, issue
detection, audit/page-inventory writes, scheduling, or GSC/GA4/LLM integration
is built (Phase 1B+). **No existing object was altered; production untouched.**
**Date:** 2026-07-13. **Migration:** `20260713120025_seo_phase16c_crawl_control_plane.sql`.

Architecture: ADR Option C hybrid — frontend → guarded RPC → job row; a future
service-role worker claims + executes; RLS-scoped customer reads; no BFF;
service-role key only in the future worker runtime.

## Final schema (all additive, `public`)

### `seo_crawl_jobs` (customer-facing, RLS-scoped)
`id`, `workspace_id`→seo_workspaces, `website_id`→seo_websites, `website_url`
(snapshot), `requested_by`→auth.users (SET NULL on user delete),
`requested_role_snapshot` (owner/admin/team_member/global_admin),
`status` (see model), `trigger_source` (manual/scheduled/system),
`idempotency_key`, `config` jsonb (immutable request-time budget snapshot),
`attempt_count`, `max_attempts`, `pages_discovered`, `pages_crawled`,
`requested_at`, `queued_at`, `claimed_at`, `started_at`, `heartbeat_at`,
`lease_expires_at`, `retry_after`, `completed_at`, `cancellation_requested_at`,
`cancelled_at`, `error_code` (customer-safe), `error_message` (customer-safe),
`correlation_id` (trace), `created_at`, `updated_at`.
Constraints: status/trigger/role CHECKs, non-negative counters, `max_attempts>0`,
`config` is a JSON object, `UNIQUE(workspace_id, idempotency_key)`, and a
**partial unique index on `website_id` WHERE status ∈ active** (dedup).
No secrets/credentials/authorization headers are ever stored.

### `seo_crawl_attempts` (INTERNAL diagnostics; worker-only)
`id`, `job_id`→jobs (CASCADE), `workspace_id`, `attempt_number`,
`worker_id`, `lease_expires_at`, `started_at`, `finished_at`, `outcome`
(succeeded/partial/failed/cancelled/lease_expired), `retry_class`
(retryable/non_retryable), `internal_error_code`, `internal_error_detail`
(internal — never customer-safe), `pages_crawled`, `http_requests`,
`created_at`. `UNIQUE(job_id, attempt_number)`.

### `seo_crawl_events` (append-only lifecycle history; customer-safe)
`id`, `job_id`→jobs (CASCADE), `workspace_id`, `website_id`, `event_type`
(queued/claimed/started/progress/retry_scheduled/cancellation_requested/
completed/partially_completed/failed/cancelled/lease_expired), `from_status`,
`to_status`, `actor` (customer/worker/system), `actor_user_id`,
`actor_role_snapshot`, `note` (customer-safe only), `created_at`.
Append-only: only a SELECT policy exists — no UPDATE/DELETE.

## Status model

`queued` → `claimed`/`running` → terminal. (`requested` collapses into `queued`:
the request RPC validates eligibility synchronously.) For each: allowed actor,
legal next states, terminal?, required timestamps, customer-visible, retryable,
required event.

| Status | Set by | Legal next | Terminal | Customer-visible |
|---|---|---|---|---|
| `queued` | request RPC | claimed/running, cancelled, cancellation_requested | no | yes |
| `claimed` | worker claim | running, cancellation_requested, retry_wait, failed | no | yes |
| `running` | worker | completed, partially_completed, failed, retry_wait, cancellation_requested, cancelled | no | yes |
| `retry_wait` | worker | queued/claimed (retry), failed, cancelled | no | yes |
| `cancellation_requested` | cancel RPC (on claimed/running) | cancelled, completed, partially_completed, failed | no | yes |
| `completed` | worker | — | yes | yes |
| `partially_completed` | worker | — | yes | yes |
| `failed` | worker | — | yes | yes |
| `cancelled` | cancel RPC / worker | — | yes | yes |

Worker-side transitions (heartbeat/complete/fail/finalize-cancel) are **Phase 1B**
functions; this contract implements request → queue, cancel, and claim → running.

## Role & permission matrix

| Actor | request | cancel | read jobs/events | read attempts | claim (worker) | direct writes |
|---|---|---|---|---|---|---|
| owner | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| admin | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| team_member | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **client** | **❌** | **❌** | ✅ (member) | ❌ | ❌ | ❌ |
| global_admin | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| non-member | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| worker (service_role) | — | — | (bypasses RLS) | (bypasses RLS) | ✅ | via functions |

**Role decision (documented):** crawl request + cancel = owner/admin/team_member
or global admin; **client is denied** (mirrors campaign-create; no product rule
grants clients crawl-trigger rights). Reads follow the existing workspace-member
rule, so clients (as members) may read customer-safe jobs/events.

## RPC contracts

- **`seo_crawl_request(p_website_id uuid, p_idempotency_key text=NULL, p_config jsonb=NULL) → uuid`**
  SECURITY DEFINER, `search_path=public`. Requires `auth.uid()`; `has_seo_module_access`;
  resolves workspace + eligibility SERVER-SIDE from `website_id` (client
  workspace/url/role/status never trusted — they aren't parameters); role gate;
  eligibility (active + not archived); http(s) URL sanity; idempotency (same key →
  returns existing job); config validated/normalized (`seo_crawl_normalize_config`);
  atomic insert (`queued`) + one `queued` event; **partial unique index → clear
  conflict on a 2nd active job**. Grant: authenticated only (anon revoked).
- **`seo_crawl_cancel(p_job_id uuid) → text`** SECURITY DEFINER. Same role gate;
  idempotent; queued/retry_wait → `cancelled` immediately; claimed/running →
  `cancellation_requested` (worker finalizes); terminal/already-requested →
  no-op returning current status; exactly one event per real cancel. Grant:
  authenticated only.
- **`seo_crawl_claim_job(p_worker_id text, p_lease_seconds int=300) → TABLE(...)`**
  SECURITY DEFINER; **EXECUTE = service_role only** (authenticated/anon revoked).
  Atomic `FOR UPDATE SKIP LOCKED` claim of a `queued`/`retry_wait` (retry-ready)
  job; creates an attempt, assigns a lease, sets `running`, writes a `claimed`
  event; skips `cancellation_requested`/terminal; returns only worker-needed
  fields. (Heartbeat/complete/fail = Phase 1B.)
- **`seo_crawl_normalize_config(jsonb) → jsonb`** IMMUTABLE helper: allow-listed
  keys + bounded numerics/booleans; `respect_robots` cannot be disabled; unknown
  keys/types raise.

## RLS & security

Default-deny. `seo_crawl_jobs`/`seo_crawl_events`: SELECT for
`is_seo_workspace_member(workspace_id) OR seo_is_global_admin()`; **no
INSERT/UPDATE/DELETE policy** for authenticated (all customer writes denied —
verified). `seo_crawl_attempts`: SELECT for `seo_is_global_admin()` only
(internal diagnostics never exposed to customers — verified). Events append-only
(no UPDATE/DELETE). Writes happen only through the SECURITY DEFINER RPCs (customer)
and the service-role worker (execution). No hidden frontend control is treated as
authorization. Grants: request/cancel = authenticated (anon revoked); claim =
service_role only.

## Idempotency & concurrency

- `UNIQUE(workspace_id, idempotency_key)` — same key returns the existing job
  (network-retry safe); the RPC returns it rather than erroring.
- **Partial unique index** on `website_id` for active statuses — a second active
  job for the same website is rejected at the DB level (not a race-prone
  check-then-insert).
- Worker claim uses `FOR UPDATE SKIP LOCKED` — two workers never claim the same
  job (verified: second claim returns nothing).

## Lease, retry & cancellation

- **Lease:** `seo_crawl_claim_job` sets `lease_expires_at = now()+lease_seconds`
  (30..3600) + an attempt row + `heartbeat_at`. Heartbeat renewal + stale-lease
  reaper = **Phase 1B** (documented; no scheduled reaper created here).
- **Retry:** worker-owned automatic fields (`attempt_count`, `max_attempts`,
  `retry_wait` + `retry_after`); the claim filters retry-ready jobs. A
  **customer-triggered retry RPC is deferred** until the worker error model
  exists (no retry button/API without an implementation).
- **Cancellation:** guarded RPC; unclaimed → immediate `cancelled`; running →
  `cancellation_requested` (no false "terminated"); idempotent; audit event
  preserved; frontend never updates status directly.

## Usage & eligibility

- **Usage/plan limits: DEFERRED (documented follow-up).** `seo_plan_limits` has
  no crawl columns and `seo_usage_events` (append-only counter) cannot cleanly
  model reserve→start→complete→release, so this migration does **not** force a
  fragile usage model. Enforced now: the DB-level **duplicate-active-job** guard.
  Phase 1B/1C: additive crawl columns on `seo_plan_limits` (per-period count,
  max pages, max concurrency, min recrawl interval) + a reservation-aware usage
  kind/status; enforcement at the request RPC.
- **Eligibility (now):** website belongs to caller's workspace + `is_active` +
  `archived_at IS NULL` + http(s) URL. **External domain-ownership verification
  does NOT exist in the schema** and is a documented **prerequisite for live
  crawling** — this contract does not claim it.

## Index purposes

`uq_seo_crawl_jobs_active_per_website` (active-job dedup); workspace-recent;
website-history; `…_claimable` (worker eligible-job claim, partial on
queued/retry_wait); `…_lease` (lease-expired recovery, partial); `…_correlation`
(trace); attempts-by-job; unique (job, attempt_number); unique (workspace,
idempotency_key).

## Backward compatibility

Fully additive — no existing table/column/RPC/RLS/index/trigger/constraint
renamed or removed; existing Stage 1–6 audit/page-inventory/website/workspace
APIs, routes, service signatures, read-shape types, role/status/action values,
mock mode, and both module locks are unchanged. Locked Page Performance + Stage 6
contracts untouched. No applied migration edited.

## Migration order

Single coherent additive migration: (1) tables + constraints + indexes,
(2) triggers + RLS, (3) config helper + request/cancel/claim RPCs + grants —
all in `20260713120025_seo_phase16c_crawl_control_plane.sql`.

## Verification results

`supabase/test/seo_phase16c_crawl_control_plane_verification.sql` — **ALL PASS**,
idempotent, self-cleaning (0 residual rows; seed data unchanged). Covered:
structure (tables/RLS/policies/functions/indexes/grants/append-only); enqueue
(owner/admin/team allowed; client/non-member/anonymous/invalid/inactive-website
denied; correct snapshots; exactly one initial event; spoof-proof server-resolved
fields; config validation; duplicate-active rejection + idempotent same-key
return); direct-write RLS (authenticated cannot insert/update/delete jobs or
insert/update/delete events or insert/read attempts); cancellation (queued→
cancelled + one event; idempotent repeat; client/non-member denied; running→
cancellation_requested); worker claim (atomic; no double-claim; cancellation
respected; retry-ready filtering; attempt+lease correct); data isolation (member
reads, non-member 0, internal attempts hidden from non-admin).

## Security implications

RLS + guarded RPCs own authorization; server-side workspace resolution prevents
spoofing; internal diagnostics isolated from customers; worker claim is
service-role-only; no secrets stored; `respect_robots` cannot be disabled via the
contract. Deep SSRF/redirect/robots enforcement is the future worker's
execution-safety responsibility (documented in the ADR), not this DB gate.

## Rollback plan

TEST-only, additive → documented reverse-order SQL in
`supabase/test/seo_phase16c_rollback_TEST_ONLY.sql` (drop RPCs → helper/trigger
fn → policies (via table drop) → tables in dependency order). No existing table
is altered, so rollback touches no existing records. **Do not execute unless
instructed.**

## Deferred Phase 1B scope

**Update — Phase 16D / Crawler 1B (2026-07-14): the worker lifecycle contract is
now IMPLEMENTED + TEST-verified** (additive migration `20260714120026`) — see
`CRAWLER_PHASE_1B_WORKER_SKELETON.md`. It adds a **lease_token** (jobs +
attempts), enhances `seo_crawl_claim_job` to issue/return it, and adds
service-role-only `seo_crawl_worker_heartbeat`/`complete`/`partial`/`fail`/
`schedule_retry`/`acknowledge_cancellation` + `seo_crawl_recover_stale_jobs`
(each validates `(job_id, worker_id, lease_token)`, updates the attempt, writes
one append-only event, clears the lease at terminal/retry). A Node/TS worker
skeleton (`crawler-worker/`) drives them; it performs **no crawling**.

**Update — Phase 16E / Crawler 1C (2026-07-14): additive discovery storage +
worker persistence RPCs** (migration `20260714120027`) extend this contract —
`seo_crawl_discovered_pages` + `seo_crawl_sitemaps` (customer-read via workspace
RLS; no customer writes), an additive `seo_crawl_jobs.discovery_stats` column, and
service-role-only `seo_crawl_worker_record_discovery` / `…_update_discovery_progress`
(validate the lease_token; derive workspace/website server-side). See
`CRAWLER_PHASE_1C_DISCOVERY_ENGINE.md`. These do **not** touch Page Inventory /
Audit / locked tables.

**Update — Phase 16F / Crawler 1D (2026-07-14): additive extraction storage**
(migration `20260714120028`) — `seo_crawl_page_snapshots` + `seo_crawl_issues`
(customer-read via workspace RLS; no customer writes; data-minimized) +
`extraction_stats`, and service-role-only `seo_crawl_worker_record_snapshots`/
`record_issues`/`update_extraction_progress`. See
`CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`. No Page-Inventory/Audit/
locked-table writes.

**Update — Phase 16G / Crawler 1E (2026-07-14): additive publishing contract**
(migration `20260714120029`) — an additive nullable `seo_crawl_jobs.audit_run_id`
binds a crawl job to exactly one audit run (populated only by the guarded
orchestration RPC `seo_crawl_request_audit`; `seo_crawl_request`/`seo_run_audit`
unchanged). A `seo_crawl_publications` evidence table (unique per job+run+
publication_version) + a deterministic 29-code `seo_crawl_issue_audit_map` +
additive nullable provenance on `seo_page_inventory`/`seo_audit_issues` back a
single **service-role-only** transactional `seo_crawl_worker_publish_results`
(reads snapshots/issues server-side; idempotent; stale-job-safe; rule-version +
issue-fingerprint provenance preserved). See
`CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`. No `seo_recommendations`
write; no scoring; locked tables untouched.

Still deferred to Phase 1E+: publishing extraction facts/findings into
seo_page_inventory / seo_audit_issues / seo_recommendations (locked-scope regression required); plan/usage
enforcement (additive `seo_plan_limits` columns + reservation model); external
domain-ownership verification; scheduled stale-recovery infra; customer-triggered
retry RPC. **The crawler is not available to customers.**
