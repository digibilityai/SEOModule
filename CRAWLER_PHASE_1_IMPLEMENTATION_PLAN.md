# Crawler Phase 1 — Implementation Plan (Phase 16A output; not started)

**Status:** Planning only — **no implementation, no migrations, no worker/Edge
code, no production change.** Awaiting operator approval of
`ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md` (Option C) and
`ADR_CRAWLER_RUNTIME_ARCHITECTURE.md` (Option C hybrid) plus the decision gates
listed in both ADRs. **Date:** 2026-07-13.

**Guiding rules (all phases):** additive migrations only; applied migrations
immutable; RLS + guarded RPCs remain the authoritative authorization; frontend
never holds the service-role key; existing read services keep their current
shapes; locked modules (Page Performance Tracker; Stage 6 Off-Page + AI
Visibility) are not modified — only additively fed where noted. The order below
follows the task's expected sequence, which repository evidence supports (no
`ProtectedRoute` yet; the crawler depends on an authenticated, ownership-scoped
job contract).

---

### Phase 1 — Customer authentication + route protection  *(the exact next task)*
- **Objective:** replace the dev-only auth entry with customer login + a
  `ProtectedRoute` gate for `/seo/*`; dev routes become dev-only.
- **Layer ownership:** Frontend (navigation/UX) — RLS/RPC stay authoritative.
- **Files likely affected:** `src/routes/SeoRoutes.tsx` (gate + dev-only), a new
  `ProtectedRoute` wrapper + login page, reuse `supabaseDevAuthService`/Supabase
  client, `getCurrentSeoRole`, `has_seo_module_access`, `useResolvedActiveWebsite`.
- **DB:** none. **API/RPC:** none (reuse existing). **Frontend:** additive.
- **Permissions:** aligns UI with existing RLS; no role-string change.
- **Backward-compat:** mock mode unchanged (gate is a no-op); locked modules
  untouched.
- **Tests:** authed vs unauthed route access; no-module-access / no-workspace /
  no-active-website states; deep-link restore; mock-mode still open.
- **Migration:** none. **Rollback:** remove the wrapper/login; restore prior
  routing. **Locked modules touched:** none.

### Phase 2 — Crawl-job data contract (additive migrations) — ✅ DONE (Phase 16C, 2026-07-13)
Delivered together with Phases 3 + 9's contract surface in one coherent additive
migration `20260713120025`: `seo_crawl_jobs` + `seo_crawl_attempts` (internal) +
append-only `seo_crawl_events`, RLS (member reads; no customer writes; internal
attempts admin-only), guarded `seo_crawl_request`/`seo_crawl_cancel` RPCs, and the
service-role-only `seo_crawl_claim_job`. TEST-verified (ALL PASS). Deferred to
1B/1C: worker, heartbeat/terminal/reaper, customer retry, plan/usage enforcement,
domain-ownership verification. See `CRAWLER_PHASE_1A_DATA_CONTRACT.md`.

- **Objective:** additive `seo_crawl_jobs` (+ staging as needed) with status,
  lease/heartbeat, ownership scope, idempotency key, RLS (workspace-scoped
  reads; writes via service-role/guarded RPC only).
- **Layer:** DB + RLS. **Files:** new `supabase/migrations/…_seo_crawl_jobs.sql`
  (additive), name/shape per `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §D/§E.
- **DB:** additive tables/policies. **API:** none yet. **Frontend:** none.
- **Permissions:** RLS read for the owning workspace; no client writes.
- **Backward-compat:** additive only. **Tests:** RLS read/deny; append-only
  status log; TEST-only verification script (new). **Migration:** additive.
- **Rollback:** drop the additive objects. **Locked modules touched:** none.

### Phase 3 — Guarded crawl-request contract (control plane)
- **Objective:** a `SECURITY DEFINER` enqueue RPC (optionally a thin Edge
  Function for input validation) that verifies auth + module access + ownership +
  plan/usage, reserves usage, and atomically inserts a `queued` job.
- **Layer:** Guarded RPC (+ optional Edge Function). **Files:** new migration
  (RPC), `offPageService`-style non-masking client wrapper (new service method).
- **DB:** additive RPC. **API:** one additive RPC. **Frontend:** additive service
  call only. **Permissions:** `authenticated` execute; anon revoked.
- **Backward-compat:** additive. **Tests:** SQL verification of authz + ownership
  + limit rejection + atomic enqueue (new TEST script). **Migration:** additive.
- **Rollback:** drop RPC + wrapper. **Locked modules touched:** none.

### Phase 4 — Worker skeleton + secure configuration — ✅ DONE (Phase 16D, 2026-07-14)
Delivered with the worker lifecycle DB contract (migration `20260714120026`:
lease_token + service-role-only heartbeat/complete/partial/fail/schedule_retry/
acknowledge_cancellation/recover_stale_jobs; claim enhanced to issue the lease
token) and a Node/TS worker in `crawler-worker/` (config + redaction, structured
secret-safe logging, error taxonomy, RPC-only job gateway, no-crawl skeleton
processor that refuses non-test jobs, dry-run/one-shot/gated-poll modes, startup
stale-recovery, graceful shutdown, 10 unit tests, non-root Dockerfile — not
deployed). TEST-verified (`seo_phase16d_...` ALL PASS) + end-to-end integration
(claim→heartbeat→complete with no page/audit writes; non-test refusal; secret-safe
logs). No crawling. See `CRAWLER_PHASE_1B_WORKER_SKELETON.md`.

- **Objective:** a dedicated background worker (service-role) that atomically
  claims jobs (`FOR UPDATE SKIP LOCKED`/claim RPC), heartbeats, and updates
  terminal state; no crawling logic yet.
- **Layer:** Worker (outside repo frontend; runtime host per ADR gate).
- **Files:** new worker project/runtime (host TBD) — **not** in the frontend
  bundle. **DB:** none (uses Phase 2/3). **API:** none. **Frontend:** none.
- **Permissions:** service-role only in worker config. **Backward-compat:** n/a.
- **Tests:** claim atomicity; lease/stale reclaim; no double-processing.
- **Migration:** none. **Rollback:** stop/remove worker. **Locked:** none.

### Phases 5–7 — URL safety, sitemap/page discovery, extraction (discovery half) — ✅ DONE (Phase 16E, 2026-07-14)
Phase 1C delivered the **security + discovery** portion of Phases 5 (URL safety /
SSRF / DNS-rebinding / robots), 6 (sitemap + page discovery), and the *link*
extraction of Phase 7 (no on-page extraction/scoring yet). See
`CRAWLER_PHASE_1C_DISCOVERY_ENGINE.md`: `crawler-worker/src/discovery/*` +
migration `20260714120027` (discovered-pages/sitemaps + worker-only record/
progress RPCs). Verified (`seo_phase16e_...` ALL PASS, 22/22 unit tests,
fixture-transport integration). No page-inventory/audit writes; crawler not
customer-available. **On-page extraction + technical-SEO issue detection remain
Phase 1D.** (The original Phase 5–8 items below remain the reference outline.)

### Phase 5 — URL safety + ownership controls
- **Objective:** SSRF/private-range blocking, scheme allowlist, redirect
  re-validation, robots.txt, per-request timeout, max size, MIME allowlist,
  ownership enforcement.
- **Layer:** Worker (+ ownership already checked at enqueue). **Files:** worker.
- **DB/API/Frontend:** none. **Permissions:** execution-safety (not customer
  authz). **Tests:** SSRF/redirect/robots unit tests; private-range denial.
- **Migration:** none. **Rollback:** revert worker. **Locked:** none.

### Phase 6 — Sitemap + basic page discovery
- **Objective:** discover pages via sitemap and/or start URL within depth/page
  budget; write discovered pages to staging/`seo_page_inventory` (additive).
- **Layer:** Worker → DB. **Files:** worker; consumes Phase 2 tables.
- **DB:** populate existing `seo_page_inventory` (shape preserved) / staging.
  **API/Frontend:** none. **Tests:** discovery within budget; dedupe/canonical.
- **Migration:** none (or additive staging). **Rollback:** revert worker.
- **Locked modules touched:** none (page-inventory is not locked; Page
  Performance read shape untouched).

### Phase 7 — Page extraction + normalization
- **Objective:** extract metadata/content/links; normalize into the existing
  read shapes (`seo_page_inventory`, `seo_page_keywords` additively if needed).
- **Layer:** Worker → DB. **Files:** worker. **DB:** populate/additive columns.
  **API/Frontend:** none. **Tests:** normalization fixtures; shape conformance.
- **Migration:** additive if new columns. **Rollback:** revert worker/columns.
- **Locked:** none.

### Phases 7–8 — extraction + technical-issue detection (crawler-domain) — ✅ DONE (Phase 16F, 2026-07-14)
Extraction + deterministic issue detection + site-level duplicates are
implemented in `crawler-worker/src/extraction/*` + migration `20260714120028`
(page snapshots + issues, worker-only RPCs), TEST-verified (`seo_phase16f_...`
ALL PASS, 32/32 unit tests, fixture integration). See
`CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`.

### Phase 1E — controlled Page Inventory + Audit publishing — ✅ DONE (Phase 16G, 2026-07-14)
**Implemented + applied to TEST + verified; production untouched.** Additive
migration `20260714120029` adds `seo_crawl_jobs.audit_run_id` (explicit
crawl-job→audit-run association), a guarded orchestration RPC
`seo_crawl_request_audit` (both existing `seo_crawl_request`/`seo_run_audit`
unchanged), a deterministic 29-code `seo_crawl_issue_audit_map`, additive nullable
provenance on `seo_page_inventory` + `seo_audit_issues`, a `seo_crawl_publications`
evidence table, and one service-role-only transactional `seo_crawl_worker_publish_results`.
Publishing is idempotent, stale-job-safe, preserves manual/user-owned records, and
represents site issues without fabricated pages. Verified: `seo_phase16g_...` ALL
PASS; worker 47/47; 16C–16F all ALL PASS; E2E fixture publish (3 pages + 8 issues
incl. a site duplicate; audit run completed; **no recommendation / Page-Performance
write**; seed 7/7). **Page-Inventory publishing / Audit-Issue publishing are NOT
"the Audit/Page-Inventory module is complete"** — recommendations, customer crawl
UI, and production crawling remain deferred. See
`CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`.
### Phase 1F — authenticated crawl request/status/freshness/result UI — ✅ IMPLEMENTED + AUTOMATED-VERIFIED (Phase 16H, 2026-07-14); OPERATOR ACCEPTANCE PENDING
**No DB change.** New frontend crawl service/hooks/components on `/seo/audit`:
role-gated **Start crawl** → `seo_crawl_request_audit` (both ids returned, no
latest-run guess) → Supabase-only terminal-aware polling status + honest freshness
→ `seo_crawl_cancel` (legal states only) → links to the associated Audit +
Page Inventory. Clients read-only; permanent mock preview writes nothing.
Verified: frontend `tsc`/`build` clean; worker 47/47; 16C–16G all ALL PASS;
security sweep clean. **Browser/operator acceptance PENDING** (see
`OPERATOR_USER_ACCEPTANCE_TEST_GUIDE.md`). See
`PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`.
**Next milestone: `Production crawler deployment, ownership verification and
usage-limit enforcement`** (not started).

### Phase 8 — Basic technical-issue detection
- **Objective:** derive technical issues; write `seo_audit_issues` and complete
  the `seo_audit_runs` row (which today stays `running`).
- **Layer:** Worker → DB. **Files:** worker; reuses Stage 2 shapes.
- **DB:** populate `seo_audit_issues` + complete `seo_audit_runs` (shapes
  preserved). **API/Frontend:** none. **Tests:** issue-rule fixtures; run
  completion. **Migration:** none. **Rollback:** revert worker. **Locked:** none.

### Phase 9 — Audit / page-inventory service integration
- **Objective:** confirm the existing wired read services (`auditService`,
  `performanceService` page-inventory reads) return real crawler data **with no
  shape change**; add freshness fields if additive.
- **Layer:** Frontend service reads (existing). **Files:** existing read services
  (no signature change). **DB:** none/additive. **API:** none. **Frontend:**
  read-through only. **Permissions:** RLS unchanged.
- **Backward-compat:** existing shapes preserved. **Tests:** existing audit/
  page-performance reads against real data; **Page Performance locked-scope
  regression must still pass**. **Migration:** none. **Rollback:** revert
  additive fields. **Locked modules touched:** **Page Performance Tracker
  (read-only, additive) — regression required; no contract change.**

### Phase 10 — Frontend crawl status + freshness
- **Objective:** "Crawl now" affordance (calls the guarded enqueue RPC), job
  status, freshness, and error surfacing via RLS-scoped reads.
- **Layer:** Frontend. **Files:** new UI in the audit/websites area (additive).
  **DB/API:** none new. **Permissions:** RLS reads. **Backward-compat:** additive
  UI. **Tests:** status transitions; error/empty/loading; double-submit guard.
- **Migration:** none. **Rollback:** remove UI. **Locked:** none.

### Phase 11 — Verification + regression
- **Objective:** end-to-end crawl on TEST; new crawl SQL verification scripts;
  re-run Stage 6 + Page Performance locked-scope regression; auth/route-protection
  tests.
- **Layer:** all. **Files:** new `supabase/test/…` scripts + browser checks.
  **DB/API/Frontend:** none new. **Tests:** the above. **Migration:** none.
  **Rollback:** n/a. **Locked modules touched:** verified unchanged.

### Phase 12 — GSC integration (the following milestone, separate task)
- **Objective:** real Search Console performance feeding Page Performance +
  Decline Diagnosis (additive), after the crawler foundation is stable. Planned
  as a **separate** milestone with its own ADR/gates. Not part of crawler Phase 1.

---

## Exact next implementation task (one bounded task)

**Phase 1 — Customer authentication + route protection** (add a `ProtectedRoute`
+ a customer login page using existing Supabase Auth; make `/seo/dev/*`
development-only; wire session → module access → workspace → active-website
resolution with loading/redirect/deep-link/mock-mode behaviour). **No data-layer
change; RLS remains authoritative.** This must precede crawler migrations and the
worker, and is contingent on operator approval of the auth ADR + its gates.

## Approval gates before any implementation
Release-path Option B (already recommended); auth Option C; crawler Option C;
worker runtime host; Edge-Function-vs-direct-RPC; crawl budgets/retention/consent
policy; subscription tiers/limits; new table/column names vs conventions;
signup model (self-serve vs invite). See both ADRs for the full list.
