# SEO Context Handover — START HERE (new ChatGPT / Claude session)

**This is the primary entry point for any new thread.** Read this first, then
follow the reading order in §2. It supersedes `CHATGPT_CONTEXT_HANDOVER.md` and
the general handover role of `BACKEND_MILESTONE_HANDOFF.md` (both retained as
historical — see `PROJECT_DOCUMENTATION_INDEX.md`).

**Created / last reconciled:** 2026-07-24 (documentation consolidation after
Reports v1 lock + Competitor Benchmarking Stage 1 commit/push).

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

## 3. Current branch / HEAD / working-tree state

- **Branch:** `main`. **HEAD:** `e00caa21f837b892777117538bb6a3dd9343d1de`
  (`feat(seo): add competitor benchmarking read path`).
- **Working tree is CLEAN; local `main` = `origin/main` (pushed).** The project
  is now committed history — recent commits: `e00caa2` (Competitor Stage 1),
  `b976340` (Reports v1 complete + locked), `420f9ca` (cloudbuild), `e1a918a`
  (SSO), `2b9537b` (SEO Intelligence module import). Use normal Git hygiene:
  branch before non-trivial work; commit/push only when a task instructs it.
- **Cross-project SSO is intentionally DEFERRED:** migration `20260720121000`
  (`seo_cross_project_identity_bridge`) is present in the repo but **pending /
  unapplied on `Digi_SEO_Test`** and must not be applied without a separate,
  explicit SSO task (see `SEO_DECISIONS.md` A14).

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
- **Reports v1 (Stages 1–3) — COMPLETE + LOCKED (2026-07-20; committed
  `b976340`, pushed).** Persisted Supabase-backed read path (Stage 1, migration
  `20260720120035`, `public.seo_reports` + workspace/website-scoped RLS) + guarded
  `SECURITY DEFINER` generation RPC `seo_report_generate` (Stage 2, migrations
  `20260720120036`/`…037`; server-derived workspace/period/actor; six live areas
  aggregated; three unavailable areas truthful via `data_provenance`; advisory
  lock + canonical upsert) + read-only role-gated `seo_report_export_data` RPC
  with **client-side jsPDF** rendering that never regenerates (Stage 3, migration
  `20260720120038`). Full SQL/authz/idempotency verification, true two-session
  advisory-lock concurrency proof, and authenticated operator browser acceptance
  all PASS on `Digi_SEO_Test`; tsc/build clean. Deferred/out-of-scope (not
  defects): CSV export, history, scheduling, email delivery, public/secure
  sharing, period comparison. Full chronology + evidence:
  `SEO_IMPLEMENTATION_STATUS.md` §1 (Reports rows) + §7; `SEO_DECISIONS.md`
  A9–A12; `docs/markdown/MODULE_LOCKS.md` (Reports v1 entry).
- **Latest activity (2026-07-20):** **Competitor Benchmarking — Stage 1
  (persisted read path)** implemented + backend-verified. New additive table
  `public.seo_competitors` (migration `20260720123000`; workspace/website-scoped
  RLS — member SELECT incl. client read-only, owner/admin/team_member write) with
  **truthful `data_provenance='estimated'`** (heuristic estimates — **no external
  competitor-data provider integrated**). Reads wired through
  `runWithServiceAdapter` (no silent mock fallback in Supabase mode); Generate/
  Refresh disabled in Supabase mode (generation is Stage 2, deferred). SQL/RLS
  verification PASS (owner=1/client=1/nonmember=0/anon=0; uniqueness; client
  write-denied; 0 residue); vitest 20/20; tsc/build clean; mock-mode
  backward-compat verified in browser. **Migration RECORDED on TEST (2026-07-20):**
  DDL applied via isolated `db query` (not `db push`, to avoid the unrelated
  pending SSO migration `20260720121000`), live schema proven byte-equivalent to
  the migration, then `20260720123000` marked applied via `supabase migration
  repair` — recorded once; **SSO `20260720121000` remains pending/untouched.**
  **Supabase-mode reachability + route protection verified in-browser** (temporary,
  since-restored `public/runtime-config.js` override; the tracked file forces
  `SEO_DATA_MODE:"mock"`). **Authenticated Supabase-mode read-path matrix
  OPERATOR-VERIFIED PASS (2026-07-22)** — signed-in owner on `digibility.ai`
  confirmed empty state with no mock fallback, persisted `estimated` rows read
  back + ordered, Generate/Refresh disabled with deferred-reason copy, refresh
  persistence, website isolation, and no write-on-read (client read-only role
  re-confirmed via SQL/RLS). Temporary runtime-config override restored
  byte-for-byte (hash-verified); disposable acceptance fixture deleted with 0
  residue. **Truthful-wording fix:** `COMPETITOR_SAFETY_NOTICE` "based on mock
  data" → "based on estimated benchmarking" (accurate in Supabase mode; consistent
  with A13). **COMMITTED + PUSHED (2026-07-24, HEAD `e00caa2`).** Competitor
  Benchmarking is **NOT locked / NOT complete** (generation = Stage 2).
- **Latest activity (2026-07-24):** **Competitor Benchmarking Stage 2 — read-only
  design recovery** completed (design/recommendation only; **no code, no
  migration, no Git change**). Recommended architecture: one guarded
  `SECURITY DEFINER` `seo_competitor_generate(p_website_id)` RPC (server-derived
  workspace/actor, advisory lock, deterministic heuristic scoring,
  replace-to-match upsert, truthful `data_provenance='estimated'`, anon-revoke
  folded in; UI re-enables Generate/Refresh for owner/admin/team_member only).
  Details: `SEO_IMPLEMENTATION_STATUS.md` §1 (Competitor Stage 1 row) + §8.
- **Latest activity (2026-07-24):** **Competitor Benchmarking Stage 2A — guarded
  generation RPC** now **BACKEND-IMPLEMENTED + TEST-VERIFIED + CONCURRENCY-VERIFIED** (branch
  `feat/seo-competitor-generate-stage2a`; **not committed/pushed**). Additive
  migration `20260724120040_seo_competitor_generate.sql`:
  `public.seo_competitor_generate(p_website_id uuid) RETURNS integer`
  (`SECURITY DEFINER`, `search_path=public`, `authenticated` EXECUTE, anon +
  PUBLIC revoked) + internal `IMMUTABLE` helper `seo_competitor_heuristic_score`.
  Server-derives actor/workspace/website-url + the onboarding competitor list +
  the latest-audit comparison score (only `p_website_id` accepted); owner/admin/
  team_member allowed, client/anon/non-member/cross-tenant denied with one
  non-leaking message; deterministic heuristic (repo-confirmed hash rule, no
  random nudge → stable/idempotent); advisory-lock serialized; replace-to-match
  upsert; truthful `data_provenance='estimated'` + `generation_method='heuristic_v1'`.
  Applied in isolation on TEST (`db query --linked`, then `migration repair`);
  SQL verification ALL PASS + Stage 1 regression PASS; vitest 20/20; tsc/build
  clean; 0 residue; **SSO `20260720121000` still the only pending migration;
  production untouched.** **True two-session concurrency VERIFIED (2026-07-24)** —
  live race on `Digi_SEO_Test` (two concurrent `supabase db query --linked`
  sessions, same method as P1b/Reports): Session B directly observed blocked
  (`wait_event=advisory`) on the same advisory-lock key while Session A held it via
  `pg_sleep(8)`; after A committed, B unblocked; post-race state = exactly one
  canonical row per competitor (no duplicates), replace-to-match re-confirmed, 0
  fixture residue. Full evidence: `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`.
- **Latest activity (2026-07-24, same day):** **Competitor Benchmarking Stage 2B
  — frontend generation integration** now **FRONTEND-IMPLEMENTED + UNIT-TESTED +
  AUTHENTICATED OPERATOR-ACCEPTED** (branch `feat/seo-competitor-generate-stage2a`;
  **not committed/pushed**). New `generateSupabaseCompetitors` calls the Stage 2A
  RPC (only the website id) then re-reads the canonical set through the Stage 1
  read path — no heuristic logic duplicated client-side.
  `competitorService.generateCompetitorBenchmarkData` dispatches via
  `runWithServiceAdapter` (`fallbackToMockOnError:false`); mock mode unchanged
  (verbatim-extracted). Generate/Refresh role-gated in Supabase mode
  (owner/admin/team_member enabled; client/non-member disabled with the
  established "Requires the owner, admin, or team member role." tooltip) via
  the real `seo_workspace_members.seo_role` (`getCurrentSeoRole`) — a usability
  layer only; the RPC remains authoritative. 16 new unit tests (33/33 total);
  tsc/build clean. **Authenticated operator acceptance ALL PASS (real TEST
  accounts + real browser sessions on `Digi_SEO_Test`):** owner/admin/
  team_member each successfully generated/refreshed via the real
  `seo_competitor_generate` RPC (network-observed `POST … → 200` + canonical
  `GET seo_competitors` reload; 3 distinct competitors, no duplicates across
  repeated refresh; DB-confirmed `data_provenance='estimated'` +
  `generation_method='heuristic_v1'`); client correctly denied in the UI
  (disabled control + tooltip) and at the backend (direct RPC attempt →
  `P0001` "Not authorized…", 0 tokens exposed); a simulated backend failure
  (reversible client-side fetch intercept, no DB/authorization change) showed
  an actionable error with **no mock fallback** and left the persisted data
  intact; desktop + mobile layouts and an unrelated page (`/seo/dashboard`)
  regressed cleanly. **No defects found.** `runtime-config.js` restored
  byte-for-byte (hash-verified, 0 residue). **Stage 2B is ready for commit.**
  **Competitor module remains NOT locked** — a lock requires separate explicit
  approval/review of this evidence. Details: `SEO_IMPLEMENTATION_STATUS.md`
  §1 (Competitor Stage 2B row) + §8; `SEO_DECISIONS.md` A16.

## 5. Current development stage

Backend crawler + ownership + enqueue-enforcement stack is **complete, locked,
and TEST-verified**. **Reports v1 (Stages 1–3) is COMPLETE and LOCKED**
(committed/pushed, `b976340`). **Competitor Benchmarking Stage 1 (persisted read
path) is COMPLETE, committed, and pushed** (`e00caa2`); **Stage 2A (guarded
generation RPC) is BACKEND-IMPLEMENTED + TEST-VERIFIED (2026-07-24, not
committed/pushed); Stage 2B (frontend integration) + operator acceptance remain
PENDING.** Frontend product surfaces (Help Center, navigation) are
development-complete. Two candidate next tracks (Competitor Stage 2B frontend
integration vs production-promotion planning) await operator selection — see §9.

## 6. Locked modules

Page Performance Tracker · Stage 6 (Off-Page Authority + AI Visibility) · Crawler
16C–16H · P1a Domain Ownership Verification · P1b Verified-only Crawl Enqueue
Enforcement · **Reports v1 (persisted read + guarded generation + PDF export,
Stages 1–3; LOCKED 2026-07-20).** (Details + unlock procedure: `MODULE_LOCKS.md`.)
Competitor Benchmarking Stage 1 is **complete but NOT locked** (module incomplete;
Stage 2 pending).

## 7. Production status

**UNTOUCHED.** No production migration/RPC/worker/config applied; Cloud Run not
deployed. Hard invariant until a separately-approved promotion task passes the
`BACKEND_MILESTONE_HANDOFF.md` §5 gates.

## 8. Current risks

- **Deferred SSO migration `20260720121000` is pending on TEST** (§3): do not let
  a `supabase db push` apply it as a side effect of an unrelated migration —
  apply new migrations in isolation + `migration repair`, as done for Competitor
  Stage 1.
- **Cloud Run container-runtime verification is still deferred** — do not treat
  the container as production-verified.
- **No frontend test/lint runner exists** — verification relies on `tsc`/build +
  `vitest` (unit) + the Help Center content validator + live browser checks.
- **Automation browser has no operator session** — authenticated Supabase-mode
  acceptance must be operator-guided (as for Reports v1 and Competitor Stage 1).

## 9. Exact next step

Two candidate tracks — **operator selects one**:

1. **Competitor Benchmarking Stage 2B — commit review.** **Stage 2A (backend
   RPC) is DONE — TEST-applied + concurrency-verified 2026-07-24; Stage 2B
   (frontend integration) is now FRONTEND-IMPLEMENTED + UNIT-TESTED +
   AUTHENTICATED OPERATOR-ACCEPTED 2026-07-24** (see §4 latest activity +
   `SEO_IMPLEMENTATION_STATUS.md` §1/§8): Supabase generate path wired through
   `runWithServiceAdapter` (no silent fallback), role-gated Generate/Refresh
   (owner/admin/team_member; client/non-member disabled), mock mode unchanged,
   33/33 vitest, tsc/build clean. **Authenticated role-matrix acceptance ALL
   PASS** on `Digi_SEO_Test` with real TEST accounts: owner/admin/team_member
   generation + repeated-refresh stability + no duplicates + truthful
   `estimated` provenance all confirmed via real network calls and read-only DB
   inspection; client denied both in the UI and at the backend (`P0001`);
   error path shows an actionable message with no mock fallback; responsive +
   unrelated-page regression checks clean; no defects found. **Stage 2B is
   ready for commit** — the branch `feat/seo-competitor-generate-stage2a` has
   not yet been committed/pushed for this work; commit is a separate,
   explicitly-approved next action. SSO `20260720121000` stays deferred;
   **Competitor module stays NOT locked** — a lock requires separate explicit
   approval/review of this evidence.
2. **Production-promotion planning / preflight** for the crawler + P1a + P1b stack
   — a **planning-only** document (no DB action, no deploy) gating: production
   migration order + rollback for P1a/16C–16H/P1b/Reports v1; worker deployment
   runtime + secrets/service-role handling; Cloud Run deploy + the deferred
   container-runtime verification; usage/subscription enforcement; rate limits;
   monitoring/alerting; and the `BACKEND_MILESTONE_HANDOFF.md` §5 checklist.
   Requires explicit approval before any production action.

## 10. Files expected to be involved in the next step (planning-only)

- Read: `BACKEND_MILESTONE_HANDOFF.md` (§5 gates), `MODULE_LOCKS.md`, the P1a/P1b
  sign-offs, `supabase/migrations/**` (order), `supabase/test/**` (verification),
  `crawler-worker/**` (runtime), `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md`.
- Likely create: a new `PRODUCTION_PROMOTION_PREFLIGHT_PLAN.md` (planning-only).
- **No source/migration/SQL/worker/config edit** in the planning step.

## 11. Instructions for a new session

- **Do not repeat completed audits or re-verify locked modules.** P1a, 16C–16H,
  P1b, and **Reports v1** are done, locked, and TEST-verified. Trust the sign-offs;
  re-verify only if a task explicitly changes that scope.
- **Git state is committed + pushed** (§3); the tree is clean and synced with
  `origin/main`. Branch before non-trivial work; commit/push only when instructed.
- **Do not apply the deferred SSO migration `20260720121000`** without a separate
  explicit SSO task; apply new migrations in isolation to avoid pulling it in.
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
