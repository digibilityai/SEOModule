# ADR — Crawler Runtime Architecture (Phase 16A)

**Status:** Approved; **control-plane DATABASE CONTRACT implemented (Phase 16C,
2026-07-13)** — job/attempt/event tables + guarded request/cancel RPCs + the
service-role-only worker-claim function, TEST-verified (see
`CRAWLER_PHASE_1A_DATA_CONTRACT.md`). The **worker SKELETON + secure job-lifecycle contract are now implemented +
TEST-verified (Phase 16D / Crawler 1B, 2026-07-14)** — a Node/TS worker in
`crawler-worker/` that claims/leases/heartbeats/terminally-transitions jobs
through service-role-only lifecycle functions with a lease-token ownership model
(see `CRAWLER_PHASE_1B_WORKER_SKELETON.md`). The **secure page-DISCOVERY engine is now implemented + TEST-verified (Phase
16E / Crawler 1C, 2026-07-14)** — SSRF + connection-time DNS-rebinding-safe
fetching, robots.txt (RFC 9309), XXE-safe sitemap parsing, `<a>`-only same-origin
HTML link discovery, budgeted BFS, and worker-only discovery persistence
(`crawler-worker/src/discovery/`, migration `20260714120027`). See
`CRAWLER_PHASE_1C_DISCOVERY_ENGINE.md`. The **extraction + deterministic issue-detection layer is now implemented +
TEST-verified (Phase 16F / Crawler 1D, 2026-07-14)** — bounded HTML fact
extraction (no second fetch), a versioned issue-rule registry, site-level
duplicate detection, and worker-only extraction persistence (migration
`20260714120028`); see `CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`.
The **controlled Audit / Page-Inventory PUBLISHING layer is now implemented +
TEST-verified (Phase 16G / Crawler 1E, 2026-07-14)** — an explicit crawl-job→
audit-run association + one service-role-only transactional publish RPC
(migration `20260714120029`) that reads crawler-domain records server-side and
additively/idempotently populates the existing `seo_page_inventory` +
`seo_audit_issues` contracts, with provenance, stale-job protection and manual-
record preservation; **no `seo_recommendations` write, no scoring, no customer
crawl UI**. See `CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`.
The **customer crawl UI is now implemented + automated-verified (Phase 16H /
Crawler 1F, 2026-07-14; operator acceptance pending)** — a request/status/
freshness/cancel/published-result workflow on `/seo/audit` with **Supabase as the
single authoritative status source** (no second backend), using
`seo_crawl_request_audit` (both ids returned) + `seo_crawl_cancel`; no DB change.
See `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`.
**Recommendation generation, production crawler deployment, ownership
verification and usage-limit enforcement remain NOT implemented and the crawler
is NOT customer-operational**; the worker is not deployed, and real-public-network crawling was
not live-tested (deterministic + fixture coverage only, documented). Node/TS was chosen over Python for repository alignment
(supabase-js/npm/ESM/Node v24). No existing object altered destructively; customer
RLS + locked modules preserved; production untouched. **Original decision date:**
2026-07-13.
**Related:** `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` (Option B; crawler is the
first P1 real-data source), `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md`,
`CRAWLER_PHASE_1_IMPLEMENTATION_PLAN.md`, `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`
(no-BFF, Supabase-direct, RLS-authoritative, §G plan/usage).

## Context / repository evidence

- **No backend/worker/queue/Edge-Function infra exists** (`supabase/functions`
  absent; no job/queue pattern in `src/` or `supabase/`).
- **The crawler is a confirmed dependency, not speculation:** `seo_run_audit`
  only creates a `status='running'` run and "**stays running until a future
  service-role/crawler backend completes it and writes real issues**"
  (`seoAuditSupabaseService.ts`). Page inventory / audit issues are empty of
  real data without a crawler.
- **Frontend must never hold service-role credentials**; RLS + guarded
  `SECURITY DEFINER` RPCs own authorization. Mock mode is permanent.
- Subscription/usage tables (`seo_subscriptions`, `seo_plan_limits`,
  `seo_usage_events`) exist but are **schema-only** (referenced only in
  `supabaseTypes.ts`; no enforcement wired).

## Decision

**Adopt Option C — Hybrid control plane + dedicated background worker.**

1. **Frontend** requests a crawl (RLS-scoped; no service role).
2. A **guarded control plane** — a `SECURITY DEFINER` RPC (optionally fronted by
   a thin Edge Function for input validation) — verifies auth + SEO module
   access + website ownership + plan/usage limits and **atomically enqueues** a
   crawl job row. The Edge Function/RPC is a **thin control plane only**, never
   the crawler runtime.
3. A **dedicated background worker** (service-role, runs outside the browser and
   outside the frontend) **atomically claims** queued jobs, performs the crawl
   within a budget, and writes **normalized** results to Supabase.
4. **Frontend observes** status, freshness, and results through **RLS-scoped
   reads only**.
5. **Service-role credentials live only in the worker runtime** — never in the
   frontend, never in an anon-callable path.

This is **not** a customer-facing BFF: the frontend still talks to Supabase
directly for all reads and for the guarded enqueue RPC; the worker is an
internal ingestion process, not a frontend API layer.

### Rejected alternatives

- **Option A — Edge Function crawler:** rejected as the crawl *runtime*.
  Supabase Edge Functions (Deno) have short wall-clock/CPU limits, constrained
  memory, no durable long-running/headless-browser execution, and weak fit for
  multi-minute budgeted crawls with retries/scheduling. *(Validate exact current
  limits against official Supabase docs at implementation time.)* An Edge
  Function is acceptable **only** as the thin validate-and-enqueue control plane
  in Option C.
- **Option B — worker only (frontend calls the worker):** rejected — it would
  make the worker a customer-facing API (a BFF) and/or require exposing an
  authenticated ingress that duplicates RLS/authz. Keeping enqueue inside a
  guarded RPC preserves the no-BFF, RLS-authoritative model.
- **Option C — hybrid (chosen):** best fit — durable worker for the crawl,
  Supabase as job/status/ownership/result store, guarded RPC as the single
  authorization choke point, RLS-scoped reads for the UI.

## Security & compliance requirements (design constraints for later build)

- **Website ownership/authorization:** a crawl may only be enqueued for a
  website the caller's workspace owns/controls; ownership/verification checked in
  the guarded RPC (reusing/extending `seo_websites` + `seo_connection_status`).
- **URL/host validation + SSRF prevention:** allowlist scheme (http/https only);
  resolve and **block private/internal/link-local/loopback/metadata ranges**
  (RFC1918, 127/8, 169.254/16, ::1, cloud metadata IPs); re-validate **after DNS
  resolution and on every redirect hop**; no arbitrary internal-network requests
  — ever.
- **Redirect validation:** cap redirect count; re-run host/SSRF checks per hop;
  never follow to a disallowed host.
- **robots.txt:** fetch + honor (respect disallow + crawl-delay) unless a
  documented, owner-verified override policy applies.
- **Budgets:** crawl-rate limit, crawl-delay, max depth, max pages, per-request
  timeout, max response size, MIME-type allowlist (HTML/text; skip binaries).
- **Identity:** a stable, identifiable crawler user-agent.
- **Normalization:** canonical/duplicate-URL normalization; respect `rel=canonical`.
- **Credential-protected sites:** out of scope for MVP (no stored site creds).
- **Consent + data:** record customer consent to crawl; define retention +
  deletion of crawl results; **audit-log** crawl requests and outcomes.
- **Credential handling:** service-role key only in the worker's secure runtime
  config; never shipped to the frontend, never in an anon RPC path.

## Data-contract impact (existing tables)

Names below for **new** objects are **proposed candidates**, subject to the
repository's migration/naming/relationship conventions
(`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §D/§E) before any migration is written.
**No applied migration is edited; all new work is additive.**

| Table | Classification |
|---|---|
| `seo_websites` | Reuse (identity/scoping); ownership/verification via **additive column** or reuse `seo_connection_status`. |
| `seo_connection_status` | Safe to populate via worker (crawl/connection state). |
| `seo_audit_runs` | Safe to **populate/complete** via worker (run already created `running`; worker completes it). Read shape preserved. |
| `seo_audit_issues` | Safe to populate via worker (empty until real crawl). Read shape preserved. |
| `seo_recommendations` | Safe to populate via worker/service (derived from findings). Read shape preserved. |
| `seo_page_inventory` | Safe to populate via worker (page discovery). Read shape preserved. |
| `seo_page_keywords` | Safe to populate via worker, or **additive columns** if new fields are needed. |
| `seo_page_performance_snapshots` | **LOCKED (Page Performance Tracker).** Crawler does **not** write these — performance snapshots come from GSC/GA4 later, additively. Read contract untouched. |
| `seo_usage_events` | Safe to populate via the guarded RPC/worker (record crawl usage). |
| **New (additive):** `seo_crawl_jobs` (job/status/lease), `seo_crawl_pages`/staging (raw→normalized), ownership-verification if not on `seo_websites` | **New additive tables** — proposed, pending convention review. |

## Crawl lifecycle — layer ownership

| # | Step | Owner |
|---|---|---|
| 1 | Customer requests crawl | Frontend (RLS-scoped) |
| 2 | Auth + SEO module access verified | Guarded RPC (authoritative) — RLS enforces underneath |
| 3 | Website ownership + eligibility | Guarded RPC (+ DB constraints) |
| 4 | Usage/plan-limit check (+ reservation) | Guarded RPC (reads `seo_plan_limits`/`seo_usage_events`) |
| 5 | Crawl job created atomically | Guarded RPC → insert `seo_crawl_jobs` (`queued`) |
| 6 | Worker claims job atomically | Worker via claim RPC / `FOR UPDATE SKIP LOCKED` (service-role) |
| 7 | Sitemap / start-URL discovery | Worker |
| 8 | Crawl within budget | Worker |
| 9 | Normalize pages + findings | Worker |
| 10 | Feed audit/page-inventory (compatible shapes) | Worker → `seo_page_inventory`, `seo_audit_issues`, complete `seo_audit_runs` |
| 11 | Terminal state (completed / partial / failed / cancelled) | Worker (append-only status log) |
| 12 | Status / freshness / errors shown | Frontend via RLS-scoped reads |

**Single source of authorization:** the **guarded enqueue RPC + RLS** own
*customer* authorization (steps 2–4). The **worker uses service-role** (bypasses
RLS) but only to **claim + execute + write results**; it **trusts the job row it
claimed** (already authorized at creation) rather than re-implementing the
customer authz check — so authorization logic is **not duplicated** across
layers. The worker's own guardrails (SSRF/robots/budgets) are *execution safety*,
a distinct concern from customer authorization.

## Failure & retry model

- **Retryable:** network timeouts, DNS transients, 5xx, worker crash mid-job.
- **Non-retryable:** ownership/eligibility failure, plan-limit exceeded,
  invalid/blocked/SSRF URL, robots disallow-all, 4xx auth-required.
- **Attempts:** bounded max (e.g. 3) with exponential backoff + jitter.
- **Partial results:** persist crawled pages; terminal `partially_completed`
  with a reason.
- **Worker-crash / stale-job recovery:** job lease (`claimed_at` + heartbeat);
  a reaper requeues leases that expire.
- **Duplicate prevention / idempotency:** enqueue idempotency key; at most one
  active job per website (dedupe); atomic claim prevents double processing.
- **Cancellation:** `cancelled` flag checked between pages.
- **Errors:** customer-visible = friendly category + reason; internal =
  detailed diagnostics + a **correlation/trace ID** logged in the worker (never
  exposed to the client).

## Subscription & usage implications

- **Current state:** `seo_subscriptions` / `seo_plan_limits` / `seo_usage_events`
  are **schema-only** (not enforced anywhere).
- **MVP needs:** per-plan crawl frequency/quota (crawls per period, pages per
  crawl, concurrency); a **usage event** per crawl; a **reservation** at enqueue
  to prevent over-limit concurrent requests; failed jobs should **not** consume
  (or should refund) quota per a defined rule.
- **Enforcement point:** the guarded enqueue RPC (control plane) checks limits +
  writes usage; the worker adjusts on completion/failure.
- **Unknown:** exact plan tiers/limits (product decision). No billing
  integration is designed here.

## Locked-module boundaries

- **Page Performance Tracker (LOCKED):** crawler **must not** write performance
  snapshots or alter the read shape; page-inventory feeding is additive; perf
  data arrives later via GSC/GA4 (additive). Reads unchanged.
- **Off-Page Authority reads (LOCKED):** untouched in crawler Phase 1; any future
  crawler-driven opportunity discovery is a separate additive extension that
  preserves the Stage 6 read/workflow contracts.
- **AI Visibility reads (LOCKED):** untouched by the crawler.
- **Audit + Recommendations (not locked):** crawler **populates** them; their
  existing read shapes are preserved (services keep returning current shapes
  while real data flows underneath).

## Backward compatibility

Preserves existing URLs, Supabase users/IDs, workspace memberships, roles, RPCs,
service signatures, read-shape types, status/action values, mock mode, existing
records, and both locks. All crawler work is **additive**; existing read
services keep their current shape while consuming crawler-produced data.

## Assumptions / unknowns / approval gates

- **Gate:** worker **runtime host** (e.g. containerized worker on a chosen
  provider) and its secure service-role config — operator decision.
- **Gate:** whether a thin **Edge Function** fronts the enqueue RPC or the RPC is
  called directly (validate current Supabase limits at build time).
- **Gate:** crawl **budgets/limits** per plan, retention/deletion policy, and
  crawl **consent/robots-override** policy.
- **Gate:** proposed new table/column **names** vs migration conventions.
- **Unknown:** exact subscription tiers/limits.

**No implementation performed. No application, migration, worker, Edge Function,
DB, or production change in this ADR.**
