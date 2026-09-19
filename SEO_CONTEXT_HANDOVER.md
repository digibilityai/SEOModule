# SEO Context Handover — START HERE (new ChatGPT / Claude session)

**This is the primary entry point for any new thread.** Read this first, then
follow the reading order in §2. It supersedes `CHATGPT_CONTEXT_HANDOVER.md` and
the general handover role of `BACKEND_MILESTONE_HANDOFF.md` (both retained as
historical — see `PROJECT_DOCUMENTATION_INDEX.md`).

**Created:** 2026-07-20. **Last reconciled:** 2026-09-19 (authoritative
resynchronisation against canonical `main` `9cb3676` — see §0). The
2026-07-24 consolidation and every dated "Latest activity" entry in §4 are
retained as a chronological record; where they conflict with §0, §0 wins.

---

## 0. CURRENT AUTHORITATIVE STATE (reconciled 2026-09-19) — read this first

> **This section overrides any older wording** — in this file, in the rest of
> the authority package, and in per-feature verification/lock records — that
> calls Recommendation Generation Stage 2 "not pushed" / "not merged", names an
> older HEAD, or calls the working tree clean. Those statements were true when
> they were written and are kept as history; the table below is true now.

| Item | Current state |
|---|---|
| **Canonical `main`** | **Code/migration baseline: `9cb3676e52235a2012a0435ce568c8faab4c4347`** (`docs(seo): accept and lock recommendation generation stage 2`), fast-forwarded from `c1de7fe5400d88189d1b826d884ef31779ab2290` on 2026-09-19 (normal push; no force, no merge commit). `main` was exactly `9cb3676` immediately before this documentation reconciliation was integrated; the integration then added **only documentation commits** on top (`eb7a366`, then `docs(seo): finalize authoritative resync`). The current tip is therefore a docs-only descendant of `9cb3676` — find it with `git fetch origin && git rev-parse origin/main`. Source, migrations, test SQL and configuration are identical to `9cb3676`. |
| **Commits Stage 2 added to `main`** | Exactly two, linear: `36d32af2a3841267d19a7911ad7e693e6e10f81d` (`feat(seo): integrate recommendation generation workflow`) then `9cb3676` (`docs(seo): accept and lock recommendation generation stage 2`). |
| **`origin/release`** | `c9d840b7a1b26ff473408e1ccde2b90d52f32966` — a merge commit (PR #1) that brought the Stage 2 branch into `release`. It is **not** in `main`. At `9cb3676` its tree was identical to `main`'s (tree `912308d5f3b8f7423014da4b9ff637f00626a0f7`); after the docs integration `main` differs from `release` **only by documentation files**. `release` is **non-canonical** and was not modified. |
| **Recommendation Generation Stage 1 (backend)** | **Complete, accepted, MODULE-LOCKED**, on `main` (`808d54d`, `e7b1fbe`, `c1de7fe`). |
| **Recommendation Generation Stage 2 (frontend integration)** | **Complete, accepted, MODULE-LOCKED, and merged into canonical `main`** at `9cb3676`. |
| **Roadmap Backend** | **DESIGN ONLY — NOT IMPLEMENTED.** The approved architecture is **plans → periods → items**, which **supersedes** the earlier flat single-table (`seo_roadmap_items`) design still preserved, marked superseded, in `SEO_ROADMAP_BACKEND_ARCHITECTURE.md`; the three-level details beyond the hierarchy are **TBD** there, and the detailed backend architecture still requires reconstruction and review before any implementation. **No Roadmap migration, RPC, table or Supabase service exists in Git.** The Roadmap frontend (`/seo/roadmap` page + `roadmapService.ts`) exists **only as a mock-backed UI/service** — no `runWithServiceAdapter`, no Supabase call, in every data mode. |
| **`Digi_SEO_Test` (TEST)** | Restored and **`ACTIVE_HEALTHY`**. **41 of 42** repository migrations are recorded in migration history; the latest recorded is `20260724130000` (Recommendation Generation). |
| **Repository migrations** | **42** files in `supabase/migrations/`. |
| **Repo migration NOT recorded on TEST** | `20260720121000` (SSO identity bridge). **Physical state:** its objects are already present on `Digi_SEO_Test` and semantically match the canonical migration. **Migration history:** unrecorded. SSO state was not changed by the Recommendation Generation promotion. It is not established who applied it or how, and this documentation does not claim to know. Migration history reconciliation is a separate, unresolved follow-up: not started, and not the automatic next task. |
| **Recommendation Generation on TEST** | Migration `20260724130000` is **applied, recorded and verified** on `Digi_SEO_Test` on 2026-09-19 (after its 2026-07-24 rollback). TEST end to end **backend** readiness is confirmed (evidence: `SEO_IMPLEMENTATION_STATUS.md` §5). **Optional live frontend write verification (the Generate button against TEST) was not performed** and is not recorded as done. |
| **Production** | **No SEO production Supabase project exists / has been identified**, and **no production rollout of any kind has occurred.** |

**Evidence for the above.** The Git facts were verified directly against the
remote on 2026-09-19 (fresh fetch; ancestry, tree equality and the pushed
fast-forward all confirmed). At the canonical tip `9cb3676` (verified in a
clean detached worktree): root `tsc` clean, `npm run build` clean, `vitest`
**48/48**, crawler-worker suite **74/74**. The TEST facts (ACTIVE_HEALTHY, 40
recorded migrations before the promotion) came from the read-only 2026-09-19
migration-history audit reported by the operator. The TEST state after the 2026-09-19 promotion (41 of 42
recorded; Recommendation Generation promoted and verified; SSO physically present
but unrecorded) comes from the promotion's verified execution evidence. The
documentation tasks that wrote this section **did not contact Supabase**.

**TEST readiness note.** The Stage 2 frontend on `main` calls `seo_recommendation_generate`, which now exists on TEST (migration promoted and verified, backend only). No live browser write through the real UI against TEST has been performed, so frontend to TEST generation has not been observed end to end. Older text elsewhere saying the RPC is absent from TEST, or that 40 migrations are recorded, describes the state before the promotion.

**Historical status headers that this section overrides.** The two **locked**
evidence records `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md` (header:
"Not pushed or merged to `main`") and `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`
(header: "`PENDING PUSH/MERGE` … Not yet pushed, not yet merged") are preserved
**unedited** as historical evidence. Their push/merge headers describe 2026-07-24;
**the current status is the table above.**

**Which documents are authoritative vs. historical/planning** is defined in
`docs/markdown/PROJECT_DOCUMENTATION_INDEX.md` (classification column). In
short: the four files named in §2 are authority; the Recommendation Generation
and Roadmap architecture documents, the release roadmap and the production
promotion plan are **design / planning / reference only**.

---

## 1. Concise project summary

Digibility SEO Intelligence is a standalone, paid SEO module (browser React/Vite
SPA + Supabase RLS/`SECURITY DEFINER` RPCs, accessed directly from the browser —
no BFF server — plus an isolated service-role `crawler-worker`). It converts SEO
insights into approvable actions and is built to later plug into the existing
Digibility platform. Permanent mock mode (`VITE_SEO_DATA_MODE`) mirrors every
service. TEST project = `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`);
**no SEO production Supabase project exists or has been identified, and no
production rollout has occurred.** Full product/architecture detail:
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

## 3. Repository state (reconciled 2026-09-19)

- **Canonical Git state = `origin/main`** — code/migration baseline `9cb3676`, plus the
  documentation-only commits of the 2026-09-19 integration (see §0). Any individual
  clone's checked-out branch, local HEAD or uncommitted files are a working copy,
  **not** project state — do not infer project status from a clone's `git status`.
- **Canonical history, newest first:** `9cb3676` (Rec Gen Stage 2 docs + lock) ·
  `36d32af` (Rec Gen Stage 2 implementation) · `c1de7fe` (Rec Gen Stage 1 lock
  reconciliation) · `e7b1fbe` (Rec Gen Stage 1 lock) · `808d54d` (Rec Gen Stage 1
  backend) · `71ac8fd` (Competitor lock) · `a594d1d` (Competitor Stage 2B) ·
  `2d5ff89` (Competitor Stage 2A) · `e00caa2` (Competitor Stage 1) · `b976340`
  (Reports v1 complete + locked) · `420f9ca` (cloudbuild) · `e1a918a` (SSO) ·
  `2b9537b` (SEO module import) · `0017e83` (initial import).
- **`origin/release`** is a separate branch (`c9d840b`): it was tree-identical to
  `9cb3676` (now differing from `main` only by documentation files) and carries an
  extra merge commit that is not in `main` (§0). Do not treat
  `release` as canonical, and do not merge or realign it without an explicit task.
- **Cross-project SSO remains a deferred, separate concern:** migration `20260720121000`
  (`seo_cross_project_identity_bridge`) is in the repo. On `Digi_SEO_Test` its objects
  are **physically present** and semantically match the canonical migration, but it is
  **unrecorded in migration history** (earlier documents that call it simply "pending" or
  "unapplied" are superseded on this point). Who applied it and how is not established.
  Do not alter SSO or repair its history without a separate, explicit SSO task
  (`SEO_DECISIONS.md` A14).
- **Recommendation Generation migration `20260724130000` is applied, recorded and
  verified on `Digi_SEO_Test`** (rolled back 2026-07-24, promoted and verified 2026-09-19; see §0 and
  `SEO_IMPLEMENTATION_STATUS.md` §5). It is committed and locked in Git.
- Use normal Git hygiene: branch before non-trivial work; commit/push only when a
  task instructs it.

## 4. Completed work (see `SEO_IMPLEMENTATION_STATUS.md` for evidence)

> **Reading note (2026-09-19).** The "Latest activity" entries below are a
> **dated chronological record** written on the day each event happened. Phrases
> such as "not committed/pushed", "pending push/merge", "Stage 2 not started",
> "`origin/main` HEAD is …" or "only pending migration" were accurate *at that
> time* and are intentionally preserved. **They do not describe the present.**
> The present state is §0.

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
  byte-for-byte (hash-verified, 0 residue). Details: `SEO_IMPLEMENTATION_STATUS.md`
  §1 (Competitor Stage 2B row) + §8; `SEO_DECISIONS.md` A16.
- **Latest activity (2026-07-24, same day):** **Competitor Benchmarking commit,
  merge, and formal module lock.** Stage 2A committed (`2d5ff89` `feat(seo): add
  guarded competitor benchmark generation`) and Stage 2B committed (`a594d1d`
  `feat(seo): integrate competitor benchmark generation`) on
  `feat/seo-competitor-generate-stage2a`, pushed to `origin`, then
  fast-forwarded onto `main` (`git merge --ff-only`, no merge commit) and
  pushed as `origin/main`. Post-merge verification (fresh worktree, `npm ci`):
  vitest 33/33, `tsc` clean, `npm run build` clean. **Competitor Benchmarking
  (Stages 1–2) is now formally MODULE-LOCKED (2026-07-24)** — see the new
  Competitor Benchmarking entry in `docs/markdown/MODULE_LOCKS.md` for the full
  locked scope, protected contracts, locked files, and the unlock/
  additive-extension procedure. Details: `SEO_IMPLEMENTATION_STATUS.md` §1/§7/§8;
  `SEO_DECISIONS.md` A13/A15/A16.

- **Latest activity (2026-07-24, same day):** **Recommendation Generation —
  Stage 1 backend** now **BACKEND-IMPLEMENTED + SQL-VERIFIED +
  CONCURRENCY-VERIFIED** (temporary worktree/branch
  `feat/seo-recommendation-generate-stage1`, built from `origin/main`
  `71ac8fd0fd6087bb5435bea4cca865025bc27967`; **not committed/pushed**).
  Closes the previously-identified gap (`SEO_RELEASE_ROADMAP.md` §4.1): real
  crawler-detected `seo_audit_issues` never populated `seo_recommendations`.
  Additive migration `20260724130000_seo_recommendation_generate.sql` adds
  `source_issue_fingerprint` + `generation_method` to `seo_recommendations`
  plus two partial unique indexes (`WHERE is_current`), and one guarded
  `SECURITY DEFINER` RPC `public.seo_recommendation_generate(p_website_id
  uuid) RETURNS SETOF seo_recommendations` (`search_path=public`,
  `authenticated` EXECUTE, anon + PUBLIC revoked). Server-derives
  workspace/actor from `seo_websites`; authorizes owner/admin/team_member or
  global admin (client/anon/non-member/cross-tenant denied, one non-leaking
  message); reproduces the existing mock's `CATEGORY_TO_AREA` /
  `ACTION_TYPE_BY_FIX_OWNER` mapping and 7 on-page templates server-side —
  no AI/LLM, no new categories. **First real consumer of the existing
  `is_current`/`superseded_by` versioning:** three-way replace-to-match
  (insert-new / no-write-if-unchanged / supersede-if-changed-and-untouched /
  leave-alone-if-a-human-already-acted / retire-if-resolved-and-untouched) —
  proven for both an issue-derived row and an on-page row. Returns the
  canonical current recommendation set (not a transient count). SQL
  verification ALL PASS (contract, full authz matrix + no-leak, mapping,
  eligibility, on-page interpolation, RPC-return-equals-canonical-set,
  idempotency, the full regeneration-safety matrix, dedup-index enforcement,
  isolation, non-destructive no-audit case; 0 residue across two consecutive
  runs). **True two-session concurrency VERIFIED** — Session B directly
  observed `wait_event=advisory` (genuinely blocked) while Session A held the
  lock via `pg_sleep(10)`; post-race state = 8 current rows / 8 distinct
  identities / 0 duplicates. Applied in isolation to `Digi_SEO_Test` (`db
  query --linked`, then `migration repair`); SSO `20260720121000` still the
  only pending migration; production untouched. Full evidence:
  `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md`. **Backend only —
  no frontend, no approval-queue/roadmap change, no crawler change, not
  locked.** Details: `SEO_IMPLEMENTATION_STATUS.md` §1/§7; `SEO_DECISIONS.md`
  A17.
- **Latest activity (2026-07-24, same day) — environment-control
  reconciliation:** the `Digi_SEO_Test` application above was **out of
  sequence.** The governing delivery sequence for this project is **local
  development → full local verification → `Digi_SEO_Test` → production**;
  this feature was applied to and exercised against `Digi_SEO_Test` before
  any local-verification step, because no local Postgres/Docker/`psql` was
  available and the interactive approval to substitute `Digi_SEO_Test` was
  **not** recorded in the controlling ChatGPT instruction trail. A read-only
  audit (recorded row-for-row in
  `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md` §4) proved rollback
  was safe — zero non-fixture rows used the new columns, zero objects
  depended on the RPC or the two new indexes, the 8 pre-existing unrelated
  `seo_recommendations` rows (created 2026-07-09, unrelated to this feature)
  were never touched. **The `Digi_SEO_Test` application was fully rolled
  back:** the RPC, both partial unique indexes, and both new columns were
  dropped; migration `20260724130000` is no longer recorded as applied;
  every other migration version and the still-pending SSO migration
  `20260720121000` are unchanged; the 8 pre-existing rows are verified
  byte-for-byte unchanged; 0 residue. `Digi_SEO_Test` now carries none of
  this feature. **Stage 1's SQL-verification and concurrency evidence (§4
  above) is retained as historical engineering evidence only — it does
  not satisfy the local-verification gate.** Correct current status:
  `IMPLEMENTED — NOT YET LOCALLY VERIFIED OR ACCEPTED`. Implementation
  (migration, RPC, SQL verification suite, rollback script) remains
  uncommitted in the temporary worktree. Details:
  `SEO_IMPLEMENTATION_STATUS.md` §1/§7; `SEO_DECISIONS.md` A17.
- **Latest activity (2026-07-24, later same day) — genuine local
  verification COMPLETE.** Following operator installation of Docker, a
  real local Supabase stack was started (isolation proven: private
  Docker-bridge address, container names distinct from any project ref,
  `.env.local`'s `VITE_SUPABASE_URL` directly confirmed to point at
  `Digi_SEO_Test`'s own ref, categorically different) —
  `TARGET IS LOCAL AND IS NOT DIGI_SEO_TEST OR PRODUCTION`, confirmed. The
  deferred SSO migration's first-boot auto-apply conflict (`supabase start`
  applies every migration file unconditionally) was identified and resolved
  via a proven, fully-reversible local-only mechanism — temporarily
  excluding the file during `db reset`, restoring it after, confirmed
  reproducible across two consecutive resets — producing a local baseline
  correctly consistent with `Digi_SEO_Test`'s deferred state. The RPC
  contract was re-verified directly on the local database (owner/`SECURITY
  DEFINER`/`search_path`/grants/return-type all match). **The full SQL
  verification suite passed twice** (every NOTICE checkpoint printed and
  confirmed, incl. `TEARDOWN ok — net-nothing`; 0 residue independently
  reconfirmed both times). **The live two-session concurrency proof passed
  against the local database** — Session B directly observed
  `wait_event_type=Lock, wait_event=advisory` at two poll points while
  Session A held the lock via `pg_sleep(10)`; post-race state = 8 current
  rows / 8 distinct identities / 0 duplicates. Two CLI-tooling corrections
  were discovered and documented (`db query --local/--db-url` cannot run
  multi-statement scripts — worked around via `docker exec ... psql`; the
  concurrency poll query needed broadening since each `psql` statement is
  its own `pg_stat_activity` row) — both recorded in
  `SEO_LOCAL_DATABASE_SETUP.md`, which was updated in place with the
  corrected, proven-working commands. **`Digi_SEO_Test` remains rolled back
  and untouched throughout; production untouched.** Correct current status
  at that point: `IMPLEMENTED — LOCALLY VERIFIED — PENDING ACCEPTANCE
  REVIEW`. Details: `SEO_IMPLEMENTATION_STATUS.md` §1/§7.
- **Latest activity (2026-07-24, later same day) — ACCEPTED and
  integrated.** Stage 1 acceptance review is complete; the implementation
  (migration, RPC, SQL verification suite, rollback script, verification
  record) is committed to `feat/seo-recommendation-generate-stage1` (based
  on `origin/main` `71ac8fd`) — see §3 for the exact commit. Formally
  MODULE-LOCKED the same day (§6) — see `docs/markdown/MODULE_LOCKS.md` for
  the new entry. Full evidence:
  `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md` §6.
- **Latest activity (2026-07-24, later same day) — pushed and merged to
  `main`.** Pre-push validation passed (exactly the 2 expected commits;
  clean working tree; no secrets in the diff; no migration-timestamp
  collision; no local Supabase scaffolding committed). Feature branch
  `feat/seo-recommendation-generate-stage1` pushed to `origin` unchanged.
  `origin/main` re-confirmed unchanged at `71ac8fd` immediately before
  merging; fast-forward merge (`71ac8fd..e7b1fbe`, no merge commit, no
  conflicts, both commits preserved exactly) performed in a temporary
  worktree and pushed as `origin/main`. Post-merge verification confirmed
  all 9 changed files present on canonical `origin/main`, no scaffolding
  merged, and the tree byte-identical to the feature branch. **`origin/main`
  now carries Recommendation Generation Stage 1.** No database was contacted
  at any point in this task.

- **Latest activity (2026-07-24, same day) — Recommendation Generation
  Stage 2 (frontend integration) IMPLEMENTED + LOCALLY VERIFIED.** Built in
  a temporary worktree/branch (`feat/seo-recommendation-generate-stage2`,
  based on `origin/main` `c1de7fe5400d88189d1b826d884ef31779ab2290`); **not
  committed, not pushed.** Wires the locked Stage 1 RPC into
  `WebsiteAuditPage.tsx` via the same "RPC then re-read the canonical set"
  adapter pattern used by Reports/Competitor Stage 2: new
  `generateSupabaseRecommendations(websiteId)` calls `seo_recommendation_generate`
  with only the website id, then re-reads through the existing
  `fetchSupabaseRecommendations` read path — no backend mapping logic
  duplicated client-side. `recommendationService.generateRecommendations`
  dispatches via `runWithServiceAdapter` (`fallbackToMockOnError:false`);
  role gating (`RECOMMENDATION_GENERATE_ROLES=['owner','admin','team_member']`
  + `canGenerateRecommendations`) mirrors the Competitor Stage 2B pattern —
  a usability layer only, the RPC's own gate remains authoritative. New
  `RecommendationGenerationPanel.tsx` on the Technical Audit page: count
  badge, Approval Queue link, role-gated Generate/Refresh control,
  loading/error states, honest "does not auto-publish" copy.
  `ApprovalQueuePage.tsx` and its services were **not modified** — the
  existing idempotent queue-generation pipeline already consumes real rows
  once they exist. **15 new unit tests** (48/48 total, 0 regressions); `tsc`/
  build clean. **Genuine local-database verification** (Docker-based local
  Supabase stack, not `Digi_SEO_Test`, not production) found and fixed one
  further local-environment-only gap — missing base table GRANTs for
  `authenticated`/`anon` (RLS was correctly defined; PostgREST denies before
  RLS evaluation without the grant) — fixed via the standard Supabase
  default-privilege bootstrap, local-only, RLS re-confirmed unweakened. Real
  fixtures proved: persisted generation, no-reload UI refresh, idempotent
  repeat generation (0 duplicates), operator-approved rows surviving
  regeneration untouched, client denied at both UI and backend (a direct
  in-page bypass fetch using the client's real session token returned the
  RPC's own non-leaking denial). **Authenticated browser acceptance
  performed live** (owner + client walkthroughs, real sign-in). **No locked
  Stage 1 file touched; no defect found.** Full evidence:
  `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`. Details:
  `SEO_IMPLEMENTATION_STATUS.md` §1/§7/§8; `SEO_DECISIONS.md` A18.
- **Latest activity (2026-07-24, same day) — Recommendation Generation
  Stage 2 acceptance-gap closure (follow-up session, no implementation-code
  change).** Closed the two evidence gaps the prior session had flagged
  honestly rather than fabricated: (1) the local base-table-privilege
  bootstrap fix was re-derived from a genuinely clean `supabase db reset`
  (not a previously-patched database) — before the fix, a raw anon-key REST
  request against the fresh database returned `401`/`42501`/`"permission
  denied for table seo_recommendations"`, with PostgREST's own hint naming
  the exact missing `GRANT`; RLS was independently re-confirmed enabled on
  all 53 public tables at that moment; classified as a
  local-Supabase-CLI-only reproducibility gap (`db reset`'s schema drop
  destroys a one-time bootstrap that a hosted project like `Digi_SEO_Test`
  never loses) — **no change to the locked Stage 1 migration/RPC.** The fix
  is now a reproducible, idempotent, RLS-preserving script
  (`supabase/test/local_supabase_privilege_bootstrap.sql`, with its own
  verification block) and a new `SEO_LOCAL_DATABASE_SETUP.md` documenting
  the full local setup procedure end-to-end (this file did not previously
  exist in the repository despite being cited elsewhere — see that
  document's own note). (2) The loading state (button `disabled=true`,
  `"Generating..."`, exactly 1 RPC call, a second click while blocked
  producing 0 additional calls — proven via a manually-releasable
  in-browser `fetch` gate, never written to any file) and the
  no-eligible-findings state (a disposable second website with a completed
  audit and 0 issues correctly generating only the 7 fixed on-page
  templates, 0 issue-derived rows, 0 auto-created approval items, and
  stable on a repeat click) were both proven live in the real UI, not
  merely code-reviewed. Full regression re-run clean (`tsc`, 48/48 tests,
  build, secret scan, diff review); all temporary instrumentation
  (in-browser fetch patch, `runtime-config.js` override,
  `.claude/launch.json` temp entry, local `supabase/config.toml`) confirmed
  removed/reverted byte-exact; local database left at 0 rows across every
  table with grants and RLS intact. No commit, no push, no lock in this
  particular follow-up session. Full evidence:
  `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`,
  `SEO_LOCAL_DATABASE_SETUP.md`.
- **Latest activity (2026-07-24, same day) — Recommendation Generation
  Stage 2 formal acceptance, commit, and module lock.** A final acceptance
  review was performed against the actual current source (every
  changed/new file read in full — service contract, role behaviour, UI
  behaviour, state integrity, and local-setup criteria all confirmed, no
  material defect found), followed by a full re-run of `tsc`, the focused
  Stage 2 tests, the full suite (48/48), the production build, a secret
  scan, and a migration-directory integrity check (all clean). Committed
  as two commits on `feat/seo-recommendation-generate-stage2`:
  `36d32af2a3841267d19a7911ad7e693e6e10f81d`
  (`feat(seo): integrate recommendation generation workflow` — the
  implementation, tests, local-setup support, and the Stage 2 verification
  record) and a second commit (`docs(seo): accept and lock recommendation
  generation stage 2`) adding the new "Recommendation Generation — Stage 2
  frontend integration" entry to `docs/markdown/MODULE_LOCKS.md` alongside
  this document, `SEO_IMPLEMENTATION_STATUS.md`, `SEO_DECISIONS.md`, and
  `docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`. **Recommendation
  Generation Stage 2 is now formally MODULE-LOCKED.** The separate Stage 1
  backend lock was **not edited** — it remains exactly as it was. **This
  branch is committed locally only — it has not been pushed to `origin`
  and has not been merged to `main`.** Push/merge is a separate,
  explicitly-approved future step. Full evidence:
  `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`,
  `docs/markdown/MODULE_LOCKS.md` (new entry).

## 5. Current development stage

Backend crawler + ownership + enqueue-enforcement stack is **complete, locked,
and TEST-verified**. **Reports v1 (Stages 1–3) is COMPLETE and LOCKED**
(committed/pushed, `b976340`). **Competitor Benchmarking (Stages 1–2 — persisted
read path + guarded generation + frontend integration) is COMPLETE and LOCKED**
(2026-07-24; commits `2d5ff89`/`a594d1d`, fast-forwarded to `main`, pushed).
Frontend product surfaces (Help Center, navigation) are development-complete.
**Recommendation Generation Stage 1 (backend) is COMPLETE, ACCEPTED, and
MODULE-LOCKED (2026-07-24)** — locally verified against a real, isolated
local Supabase stack (Docker-based; full SQL suite + live two-session
concurrency proof both passed), committed as `808d54d`/`e7b1fbe`,
**fast-forwarded onto `main` and pushed** (`71ac8fd..e7b1fbe`).
**Recommendation Generation Stage 2 (frontend integration) is COMPLETE,
ACCEPTED, and MODULE-LOCKED (accepted + locked 2026-07-24)** — committed as
`36d32af2a3841267d19a7911ad7e693e6e10f81d` and `9cb3676`, and **merged into
canonical `main` at `9cb3676` on 2026-09-19** (fast-forward from `c1de7fe`).
**Roadmap Backend is DESIGN ONLY — not implemented** (§0).

## 6. Locked modules

Page Performance Tracker · Stage 6 (Off-Page Authority + AI Visibility) · Crawler
16C–16H · P1a Domain Ownership Verification · P1b Verified-only Crawl Enqueue
Enforcement · **Reports v1 (persisted read + guarded generation + PDF export,
Stages 1–3; LOCKED 2026-07-20)** · **Competitor Benchmarking (persisted read +
guarded generation + frontend integration, Stages 1–2; LOCKED 2026-07-24)** ·
**Recommendation Generation — Stage 1 backend only (additive schema + guarded
generation RPC; LOCKED 2026-07-24)** · **Recommendation Generation — Stage 2
frontend integration (LOCKED 2026-07-24; merged into canonical `main` at
`9cb3676` on 2026-09-19; the Stage 1 lock above remains separate and
unchanged).**
(Details + unlock procedure: `docs/markdown/MODULE_LOCKS.md`.)

## 7. Production status

**No SEO production Supabase project exists or has been identified**
(`Digi_SEO_Test` is the only SEO project; the 2026-07-24 read-only project
listing recorded in `SEO_PRODUCTION_PROMOTION_PLAN.md` §1.4 also showed
`Digi_Visi`, whose role is unknown and which this module has never touched). **No production rollout has occurred:** no production
migration/RPC/worker/config applied; Cloud Run not deployed. Hard invariant
until a separately-approved promotion task passes the
`BACKEND_MILESTONE_HANDOFF.md` §5 gates. `SEO_PRODUCTION_PROMOTION_PLAN.md` is a
future planning reference only — it does not reflect production readiness.

## 8. Current risks

- **SSO migration history is unreconciled:** `20260720121000` is physically present on TEST
  but unrecorded (§0/§3). Do not let a `supabase db push` treat it as unapplied, and do not run
  `migration repair` for it without a separate, explicit SSO task. Apply new migrations in
  isolation, as done for Competitor Stage 1 and Recommendation Generation.
- **Live frontend write verification is outstanding (optional):** the Recommendation Generation
  backend is verified on TEST, but the Generate button has not been exercised against TEST.
- **Cloud Run container-runtime verification is still deferred** — do not treat
  the container as production-verified.
- **No frontend test/lint runner exists** — verification relies on `tsc`/build +
  `vitest` (unit) + the Help Center content validator + live browser checks.
- **Automation browser has no operator session** — authenticated Supabase-mode
  acceptance must be operator-guided (as for Reports v1 and Competitor Stage 1).

## 9. Exact next step

**Competitor Benchmarking (Stages 1–2) is DONE and MODULE-LOCKED (2026-07-24)**
— not a pending item. Commits `2d5ff89` (Stage 2A backend) and `a594d1d`
(Stage 2B frontend integration) are fast-forwarded onto `main` and pushed;
formal lock entry added to `docs/markdown/MODULE_LOCKS.md`. See §4 latest
activity + `SEO_IMPLEMENTATION_STATUS.md` §1/§7/§8 for full evidence.

**Recommendation Generation Stage 1 is DONE, ACCEPTED, MODULE-LOCKED, and
MERGED TO `main` (2026-07-24)** — not a pending item. Local PostgreSQL/
Supabase environment provisioned; genuine local verification (full SQL
suite + live two-session concurrency proof) passed; Stage 1 reviewed and
accepted; committed as `808d54d`/`e7b1fbe` on
`feat/seo-recommendation-generate-stage1` (§3); formal lock entry added to
`docs/markdown/MODULE_LOCKS.md`; branch pushed to `origin`, fast-forwarded
onto `main`, and pushed as `origin/main` (`71ac8fd..e7b1fbe`). **No further
`Digi_SEO_Test` use is permitted for this feature without an approval
explicitly recorded in the controlling ChatGPT instruction trail.**

**Recommendation Generation Stage 2 (frontend integration) is DONE, ACCEPTED,
MODULE-LOCKED, and MERGED TO CANONICAL `main` (`9cb3676`, 2026-09-19)** — not a
pending item. Frontend service wiring, role-gated UI control, 15 new unit tests,
genuine local-database verification (incl. the base-table-GRANT local-environment
gap and its reusable script) and live authenticated browser acceptance are all
complete; evidence: `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`. The
Stage 1 backend lock's own entry was not edited.

**There is no pending Git step for Recommendation Generation.** Open decisions
(each needs its own explicit approval; none has been started):

1. Optional live frontend write verification of Recommendation Generation against TEST
   (not performed).
2. SSO `20260720121000` migration history reconciliation (physically present, unrecorded):
   a separate, unresolved follow-up. Not started and not the automatic next task.
3. Whether/how to realign `origin/release` with `main`.
4. Roadmap Backend implementation: **design only today; nothing is implemented.**
   The approved high level hierarchy is **plans → periods → items** (supersedes the older
   flat `seo_roadmap_items` design preserved in `SEO_ROADMAP_BACKEND_ARCHITECTURE.md`).
   That document's amendment lists what carries over and marks the three-level details
   **TBD**; the detailed backend architecture still requires reconstruction and review
   before any implementation.

Other candidate track (independent of the above):

- **Production-promotion planning / preflight** for the crawler + P1a + P1b stack
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
- **Canonical Git state is `origin/main`** (baseline `9cb3676` + docs-only commits; §0/§3). Do not infer it from
  any clone's local `git status`. Branch before non-trivial work; commit/push only
  when instructed.
- **Do not apply, alter or repair the history of SSO migration `20260720121000`** without a
  separate explicit SSO task; apply new migrations in isolation to avoid pulling it in.
- **Never treat design/planning documents as implementation authority:**
  `SEO_RECOMMENDATION_GENERATION_ARCHITECTURE.md` (historical design),
  `SEO_ROADMAP_BACKEND_ARCHITECTURE.md` (design only — not implemented),
  `SEO_RELEASE_ROADMAP.md` (planning snapshot) and
  `SEO_PRODUCTION_PROMOTION_PLAN.md` (future planning reference).
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

## 12. Prior Claude session reconciliation (2026-07, historical)

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

## 13. Authoritative documentation reconciliation (2026-09-19)

- Reconciled this authority package (`SEO_CONTEXT_HANDOVER.md`,
  `SEO_IMPLEMENTATION_STATUS.md`, `SEO_DECISIONS.md`,
  `docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`) against canonical `main`
  `9cb3676` and the 2026-09-19 audit. Added §0 as the single current-state
  table; fixed the stale current-state wording (HEAD, "clean tree", Stage 2
  "not pushed/merged", "production untouched" phrasing).
- `docs/markdown/MODULE_LOCKS.md` received an **additive** dated note only; no
  historical locked entry was rewritten.
- `SEO_LOCAL_DATABASE_SETUP.md` was reconciled (committed Stage 2 version as base
  plus still-correct material from the earlier local version).
- Four previously untracked documents were added with classification banners:
  `SEO_RECOMMENDATION_GENERATION_ARCHITECTURE.md` (historical design),
  `SEO_ROADMAP_BACKEND_ARCHITECTURE.md` (design only — not implemented),
  `SEO_RELEASE_ROADMAP.md` (planning snapshot),
  `SEO_PRODUCTION_PROMOTION_PLAN.md` (future planning reference).
- No product code, migration, test SQL, runtime config or crawler-worker file was
  modified; no database was contacted; nothing was pushed by that task.

**Finalization (2026-09-19, same day).** The three-level Roadmap architecture
(plans → periods → items) was recorded as approved and as superseding the flat
single-table design (design only; details TBD); `CURRENT_PROJECT_STATUS.md` was
labelled a historical ledger; the locked Stage 1/Stage 2 verification records were
deliberately left unedited; wording about `main`'s tip and `release`'s tree was
corrected for the docs-only integration. `docs/pages/markdown-index.html` is a
hand-maintained static page with no generator and remains stale (see the index).

## 14. Recommendation Generation TEST promotion reconciliation (2026-09-19)

Documentation only. Recommendation Generation migration `20260724130000` was promoted to
`Digi_SEO_Test` and verified on 2026-09-19 (evidence in `SEO_IMPLEMENTATION_STATUS.md` §5). TEST now records
41 of 42 repository migrations. SSO `20260720121000` is physically present but unrecorded
(unchanged by the promotion). Historical entries in §4 that say the migration is rolled back
or that 40 migrations are recorded were accurate when written and are preserved. Roadmap
Backend remains design only. `CURRENT_PROJECT_STATUS.md` remains a historical ledger.
