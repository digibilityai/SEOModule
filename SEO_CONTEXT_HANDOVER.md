# SEO Context Handover — START HERE (new ChatGPT / Claude session)

**This is the primary entry point for any new thread.** Read this first, then
follow the reading order in §2. It supersedes `CHATGPT_CONTEXT_HANDOVER.md` and
the general handover role of `BACKEND_MILESTONE_HANDOFF.md` (both retained as
historical — see `PROJECT_DOCUMENTATION_INDEX.md`).

**Created / last reconciled:** 2026-07-20 (documentation consolidation).

---

## 1. Concise project summary

Digibility SEO Intelligence is a standalone, paid SEO module (browser React/Vite
SPA + Supabase RLS/`SECURITY DEFINER` RPCs, accessed directly from the browser —
no BFF server — plus an isolated service-role `crawler-worker`). It converts SEO
insights into approvable actions and is built to later plug into the existing
Digibility platform. Permanent mock mode (`VITE_SEO_DATA_MODE`) mirrors every
service. TEST project = `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`);
**production is separate and untouched.** Full product/architecture detail:
`SEO_PROJECT_CONTEXT.md`.

## 2. Authoritative-document reading order

1. **`SEO_CONTEXT_HANDOVER.md`** (this file) — entry point, current stage, next step.
2. **`SEO_IMPLEMENTATION_STATUS.md`** — concise current implementation + lock + TEST/prod state.
3. **`SEO_PROJECT_CONTEXT.md`** — product, architecture, BFF/boundaries, conventions.
4. **`SEO_DECISIONS.md`** — current confirmed decisions + rejected alternatives.
5. **`MODULE_LOCKS.md`** — the lock registry (protected scope + unlock procedure).
6. **Module sign-off / verification evidence** — `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`,
   `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`, `STAGE_6_FINAL_REGRESSION_SIGNOFF.md`,
   `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md`, `P1B_CONCURRENCY_VERIFICATION_GUIDE.md`,
   and the migration/verification/rollback SQL under `supabase/`.
7. **`CURRENT_PROJECT_STATUS.md`** — the detailed dated status ledger (deep history).
8. **Historical / archive** — everything else in `PROJECT_DOCUMENTATION_INDEX.md` §Archive.

`DOCUMENTATION_WORKFLOW_RULES.md` still governs the docs-preflight + docs-in-sync
discipline for every task.

## 3. Current branch / HEAD / working-tree caveat

- **Branch:** `main`. **HEAD:** `0017e83` ("Initial import").
- **IMPORTANT:** essentially the entire project (P1a, 16C–16H, P1b, Help Center,
  navigation IA, Cloud Run readiness, all docs) exists as **uncommitted
  working-tree changes** on top of that single import commit. **Preserve this
  uncommitted work.** Do not `git reset`, `git checkout --`, discard, stage, or
  commit unless a task explicitly instructs it. A new session must not assume a
  clean tree means nothing was done — read the status files, not just `git log`.

## 4. Completed work (see `SEO_IMPLEMENTATION_STATUS.md` for evidence)

- **Backend crawler stack — LOCKED:** P1a Domain Ownership Verification (DNS-TXT);
  Crawler Phases 16C–16H (customer crawl UI + crawl/audit/publishing contracts);
  P1b Verified-only Crawl Enqueue Enforcement (worker regression **74 pass / 0
  fail / 0 skip**; live two-session `FOR SHARE` concurrency proof). All
  TEST-verified on `Digi_SEO_Test`; production untouched.
- **Earlier stages — Page Performance (LOCKED), Stage 6 Off-Page + AI Visibility
  (LOCKED)**, service wiring for stages 1–6, customer auth (Phase 16B).
- **Frontend product work (not locked, additive):** Help Center
  **DEVELOPMENT-COMPLETE** (public foundation + contextual-help Waves 2B/2B.5/2C/3);
  Collapsible SEO Navigation IA; Cloud Run frontend container **readiness
  prepared (not deployed / not runtime-verified)**.
- **Latest activity (2026-07-20):** **Reports Stage 1 — real-data read
  foundation** authored, **TEST-applied to `Digi_SEO_Test`, and backend-verified**
  (additive migration `20260720120035` adding `public.seo_reports` with
  workspace/website-scoped RLS; SQL/RLS read-path verification PASS —
  owner/client read, nonmember/anon denied; tsc/build clean). The Reports UI now
  reads live data via `runWithServiceAdapter` with no silent mock fallback in
  Supabase mode; generation/exports remain deferred (Generate disabled in
  Supabase mode). **Authenticated browser acceptance PASSED (2026-07-20)** via an
  operator-login session on `Digi_SEO_Test` (owner account; a TEST-only seeded
  `seo_reports` row, since removed): populated render + value match, Supabase read
  path 200, no mock fallback, Generate disabled, exports "coming soon",
  website-switch isolation, refresh/Back, no console errors. **Reports Stage 1 is
  now FULLY VERIFIED — but Reports remains NOT locked / NOT complete** (module-wide;
  next is Stage 2 — guarded generation/persistence). Details:
  `SEO_IMPLEMENTATION_STATUS.md` §1 (Reports Stage 1 row) + §7. (The earlier
  2026-07-20 read-only Reports capability audit — Reports was then
  frontend-only/mock — is superseded by this first backend increment.)
- **Latest activity (2026-07-20):** **Reports Stage 2 — guarded generation &
  persistence** authored, **TEST-applied to `Digi_SEO_Test`, and
  backend-verified**. New SECURITY DEFINER RPC `seo_report_generate` (migration
  `20260720120036` + corrective `20260720120037` denying anon EXECUTE) aggregates
  the six live areas server-side (audit/approvals/content/page-performance/
  authority/AI), marks the three unavailable areas truthfully via
  `data_provenance`, and upserts the canonical `seo_reports` row under an advisory
  lock; Generate is re-enabled in Supabase mode. SQL/authz/idempotency/
  page-performance-parity verification PASS; tsc/build clean. **Authenticated
  browser acceptance PASS (2026-07-20)** — operator-login matrix: real Generate →
  `POST /rpc/seo_report_generate` → report renders via the Stage 1 read path with
  values matching source, regenerate=same canonical row, period/website-switch
  isolation, no mock fallback, exports "coming soon". **Sole remaining item:** a
  true two-session advisory-lock concurrency run (needs a held-transaction DB
  session — no psql/DB password in the automation env; operator procedure
  provided). Reports remains **NOT locked / NOT complete**. Details:
  `SEO_IMPLEMENTATION_STATUS.md` §1 (Reports Stage 2 row) + §7; `SEO_DECISIONS.md`
  A10–A11.
- **Latest activity (2026-07-20):** **Reports final scope-completion gate.** The
  exported PDF was captured as a real `application/pdf` blob (via the live
  Generate→export flow) and inspected via its decoded content stream + layout
  coordinates (poppler unavailable for a raster render): valid 1-page A4, all
  sections, "Not connected" ×3, footer + version + page numbering, correct
  metadata, no garbage tokens, no overflow. Final Stage 1–3 regression (three SQL
  scripts + tsc + build) PASS; 0 TEST residue. **The Reports v1 scope lock is
  blocked solely on the Stage 2 operator two-session concurrency run** (still no
  held-transaction DB session / DB password available). **Reports is NOT locked.**
  See `SEO_IMPLEMENTATION_STATUS.md` §1 (Reports Stage 3 row) + §7.
- **Prior activity (2026-07-20):** **Reports Stage 3 — PDF export** implemented,
  **TEST-verified, and browser-accepted**. A read-only role-gated RPC
  `seo_report_export_data` (migration `20260720120038`; `STABLE` SECURITY DEFINER;
  owner/admin/team_member only, client/anon/nonmember/cross-tenant denied, anon
  revoked; returns the stored row unchanged) authorizes the export; the PDF is
  rendered **client-side with jsPDF** (there is no BFF/edge function) from the
  already-persisted report — **it never regenerates** (browser: Download PDF →
  `seo_report_export_data` → `application/pdf` blob, no generate call). Unavailable
  areas print "Not connected"; CSV/email/share stay disabled. SQL verification +
  browser acceptance PASS; tsc/build clean. Reports remains **NOT locked / NOT
  complete** (CSV/email/sharing/history/scheduling deferred; the Stage 2 operator
  two-session concurrency run also remains outstanding). Details:
  `SEO_IMPLEMENTATION_STATUS.md` §1 (Reports Stage 3 row) + §7; `SEO_DECISIONS.md`
  A12.

## 5. Current development stage

Backend crawler + ownership + enqueue-enforcement stack is **complete, locked,
and TEST-verified**; the module is **between "TEST-complete" and
"production-promotion planning."** Frontend product surfaces (Help Center,
navigation) are development-complete. No feature implementation is in flight.

## 6. Locked modules

Page Performance Tracker · Stage 6 (Off-Page Authority + AI Visibility) · Crawler
16C–16H · P1a Domain Ownership Verification · P1b Verified-only Crawl Enqueue
Enforcement. (Details + unlock procedure: `MODULE_LOCKS.md`.)

## 7. Production status

**UNTOUCHED.** No production migration/RPC/worker/config applied; Cloud Run not
deployed. Hard invariant until a separately-approved promotion task passes the
`BACKEND_MILESTONE_HANDOFF.md` §5 gates.

## 8. Current risks

- **Working-tree-only state** (§3): a careless `git` operation could discard the
  whole project. Preserve uncommitted work.
- **Reports is mock-only** but is user-visible; it lacks an explicit on-page
  "preview/mock data" label — small honesty-labeling gap, not a functional defect.
- **Cloud Run container-runtime verification is still deferred** — do not treat
  the container as production-verified.
- **No frontend test/lint runner exists** — verification relies on `tsc`/build +
  the Help Center content validator + live browser checks.

## 9. Exact next step

**Production-promotion planning / preflight** for the crawler + P1a + P1b stack —
a **planning-only** document (no DB action, no deploy) gating: production
migration order + rollback for P1a/16C–16H/P1b; worker deployment runtime +
secrets/service-role handling; Cloud Run deploy + the deferred container-runtime
verification; usage/subscription enforcement; rate limits; monitoring/alerting;
and the `BACKEND_MILESTONE_HANDOFF.md` §5 checklist. Requires explicit approval
before any production action. (A separate, feature-scoped alternative is **Reports
backend wiring**, per the Reports audit — but the crawler-stack promotion is the
recommended next major step.)

## 10. Files expected to be involved in the next step (planning-only)

- Read: `BACKEND_MILESTONE_HANDOFF.md` (§5 gates), `MODULE_LOCKS.md`, the P1a/P1b
  sign-offs, `supabase/migrations/**` (order), `supabase/test/**` (verification),
  `crawler-worker/**` (runtime), `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md`.
- Likely create: a new `PRODUCTION_PROMOTION_PREFLIGHT_PLAN.md` (planning-only).
- **No source/migration/SQL/worker/config edit** in the planning step.

## 11. Instructions for a new session

- **Do not repeat completed audits or re-verify locked modules.** P1a, 16C–16H,
  and P1b are done, locked, and TEST-verified; the Reports mock-only audit
  (2026-07-20) is complete — do not re-run it. Trust the sign-offs; re-verify only
  if a task explicitly changes that scope.
- **Preserve existing uncommitted work** (§3) — never discard/reset/stage/commit
  without explicit instruction.
- **Recommend the appropriate Claude model** in future prompts: use **Opus** for
  deep planning, architecture, security-sensitive or cross-cutting changes, and
  audits; **Sonnet** for well-scoped implementation/edits; **Haiku** for trivial
  mechanical edits. State the recommended model at the top of each task prompt.
- **Write token-efficient prompts:** reference the authoritative files by name
  ("per `SEO_IMPLEMENTATION_STATUS.md` §4 …") instead of re-pasting full context;
  name allowed files, stop conditions, and a required response format.
- **Respect the collaboration model:** ChatGPT plans + issues narrowly-scoped
  approvals; Claude executes exactly that scope, verifies, reports evidence, and
  stops. Approvals are per-action/per-session.
- **Honor the locks + additive-only + no-production + preserve-mock-mode +
  no-service-role-in-frontend invariants** (`SEO_DECISIONS.md` §4–6).

## 12. Latest Claude session reconciliation

- **Final P1b read-only reconciliation audit result: `CLEAN WITH NON-BLOCKING
  NOTES`.** P1b's applied RPC diff = guard only; rollback fidelity, fixture
  correctness, doc consistency, index/lock registration, and evidence
  consistency all verified; no blocking issue.
- **Non-blocking note — P1b plan wording:**
  `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_PLAN.md`'s "Implementation-artifacts note"
  contained historical pre-execution wording ("P1b not locked / next action is
  approval to apply + run on TEST"). Its top banner and §1 already state the final
  `P1b COMPLETE — TEST-APPLIED, VERIFIED, MODULE-LOCKED` status. **During this
  consolidation task, that stale note was explicitly labelled SUPERSEDED**
  (additive; the historical text is preserved for traceability, not deleted). No
  active document says P1b is pending, unexecuted, or unlocked.
- **Also reconciled this task:** the four authoritative files were created; the
  documentation index was restructured to name them as the authority hierarchy;
  the legacy `CHATGPT_CONTEXT_HANDOVER.md` received a top redirect banner pointing
  here (its historical body retained). No runtime/source/migration/SQL/test/config
  file was modified; no database was contacted; nothing was staged, committed, or
  pushed.
