# ChatGPT Context Handover — Digibility SEO Intelligence Module

**Purpose:** a compact, self-contained brief so a fresh ChatGPT development-oversight
thread can recover this project without reading the whole documentation library.
**Last updated:** 2026-07-18 (P1a **authenticated browser role matrix — COMPLETE = PASS**
(owner/admin/team_member/client + sign-out/session isolation); see §9/§13. Step 2B + Step 3
SQL regressions re-run on TEST — **RESULT: ALL PASS** (prior update, retained below)).
**Authoritative status source:** `CURRENT_PROJECT_STATUS.md`
(this file summarizes it; if they ever disagree, that file wins and this one is stale).
**This file is documentation only — it changed no code/DB/config/test/production.**

---

## 1. Product & repository overview
The **Digibility SEO Intelligence Module** is a standalone SEO product being built to
later plug into the existing Digibility platform. Frontend: **Vite + React + TypeScript**
(TanStack Query, shadcn/Radix UI, Tailwind). Data: **Supabase Postgres** with **RLS +
`SECURITY DEFINER` RPCs**, accessed **directly from the browser via the anon key**. A
permanent **mock data mode** (`VITE_SEO_DATA_MODE=mock`) mirrors every service for
preview/testing. Current working dir is the SEO module repo:
`/Users/amitguptaamit/gitrepo/user_guide/Digibility-SEO-Module`.

## 2. Repositories / projects involved & how they connect
- **SEO module frontend** (`src/**`) — browser app; talks **directly to Supabase**
  (reads via RLS; writes via guarded RPCs); never holds service-role credentials.
- **`crawler-worker/**`** — a **separate Node/TS package** in the same repo tree; a
  dedicated **service-role background ingestion worker** (crawl + DNS-TXT ownership
  `verify-once`). Runs **outside the browser/frontend**; not customer-callable.
- **Supabase project `Digi_SEO_Test`** (ref `snyzotgwwfomgafrsvfm`) — the **TEST**
  database. All migrations/verification run here. **Production is a separate, untouched
  project.**
- **Existing Digibility app** (reference only, not in this repo) — source of
  architecture/UI/auth conventions; **must not be modified**; future integration target.

## 3. Confirmed architecture & security boundaries
- **Browser → Supabase directly.** Authorization is owned by **RLS + `SECURITY DEFINER`
  RPCs**; the frontend gates are accessible affordances only (never authoritative).
- **Service-role key lives only in `crawler-worker` runtime** — never in the frontend,
  never in an anon-callable path. The worker **trusts the already-authorized job/claim
  row** and adds execution-safety guardrails (SSRF/DNS-rebind/robots/budgets).
- **Data minimization:** customer reads expose only customer-safe columns; internal
  claim/lease/worker-diagnostic fields are global-admin-only; the worker never logs raw
  challenge/lease tokens.
- **Mock mode is permanent** and must never call Supabase.

## 4. BFF requirements & the one narrowly-scoped exception
- **Current confirmed model = NO customer-facing BFF.** The SEO module is
  **Supabase-direct / RLS-authoritative** (`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`
  §B/§F/§G/§L). There is no app-server/BFF between browser and data today.
- **The crawler worker is a deliberate trusted-server exception, not a BFF.** Per
  `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md` (Option C, lines 79–81, 92–95): the frontend
  still talks to Supabase directly for all reads and the guarded enqueue RPC; the worker
  is an **internal ingestion process, not a frontend API layer**. The crawler "does not
  break the 'no BFF' rule, but it requires a runtime host"
  (`MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md:166`).
- **Future parent-Digibility "BFF integration" is DEFERRED, additive, and out of current
  scope** (`MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` lines 333/342; `MODULE_LOCKS.md:155`).
  When the module later plugs into the parent platform, an identity-adapter / BFF seam
  may be introduced additively — it does **not** govern today's build and does **not**
  contradict the no-BFF-today model.
- **Resolution:** the ADR's "no-BFF" is scoped consistently with the module-wide
  Supabase-direct model; browser/application traffic stays behind RLS + guarded RPCs, the
  worker is the only trusted-server component, and any BFF is future integration work.
  **No authoritative document is contradictory; no doc edit was required.**

## 5. Backward-compatibility requirements
All new work is **additive** and must preserve: existing routes/URLs, Supabase
users/IDs, workspace memberships, SEO role strings, existing RPCs + signatures, service
read-shape types, status/action enum values, existing records, permanent mock mode, and
**both module locks** (Page Performance Tracker; Stage 6). No applied migration is edited;
read services keep their current shapes while real data flows underneath.

## 6. Documentation source-of-truth hierarchy
1. **`CURRENT_PROJECT_STATUS.md`** — single source of truth for *current status* (top
   line is authoritative; older lines are historical "Prior line —" chain).
2. **`PROJECT_DOCUMENTATION_INDEX.md`** — the map: which doc to read for what.
3. **`DOCUMENTATION_WORKFLOW_RULES.md`** — how docs are maintained; if any doc disagrees
   with `CURRENT_PROJECT_STATUS.md`, treat that file as authoritative and flag the other
   as stale.
4. Domain docs (architecture plan, ADRs, `MODULE_LOCKS.md`, per-phase/step records) are
   authoritative for their own scope.

## 7. Overall development plan & current release phase
Per `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` (**Option B — Minimum Customer-Usable
MVP**): customer auth + route protection → **real-data ingestion** (crawler → GSC/GA4) →
subscription/usage enforcement, all additive over the locked foundations.
**Current phase:** **Production Readiness A → P1a Domain Ownership Verification** —
implementation complete; **operator acceptance in progress**. Next planned milestone
(separately approved, additive to locked crawler 16C–16H): **P1b — verified-only crawl
enqueue enforcement** (not started).

## 8. Completed & locked modules
- **Locked (implemented-scope locks; see `MODULE_LOCKS.md`):**
  **Page Performance Tracker** and **Stage 6 — Off-Page Authority workflows + AI
  Visibility reads**. Shared files may receive only separately-authorized, additive,
  backward-compatible changes that re-run the relevant regression.
- **Completed & TEST-verified (not all customer-operational):** Stages 1–6 backend;
  service wiring through Phase 15; customer auth + route protection (Phase 16B); the
  **crawler control-plane → worker → discovery → extraction → publishing → customer UI**
  (Phases 16C–16H, **fully accepted on TEST**, worker not deployed).
- **P1a Steps 1–6** (DNS-TXT domain ownership verification) implemented + TEST-verified
  (see §9). **P1a is NOT module-locked yet.**

## 9. Current P1a Domain Ownership Verification status  *(latest confirmed facts)*
- **Step 2.8 authenticated UI acceptance = PASS** under the final **AT-1..AT-4** criteria.
- **Final double-submit guard** in `src/pages/seo/websites/OwnershipVerificationPanel.tsx`:
  per-action state machine **`idle → in_flight → cooldown → idle`**.
  - First click **fires immediately**.
  - A **synchronous per-action phase ref (`phaseRef`)** blocks concurrent/same-frame
    duplicate submissions (before `disabled` re-renders).
  - The button stays **visibly disabled through the mutation + refetch lifecycle + a
    fixed 3000 ms cooldown** (`disabled = anyPending || lockedActions[action]`).
  - **No keep-alive / no timer rescheduling.**
  - A **deliberate click after re-enable is a valid new request.**
  - Temporary `[OVP]` diagnostics fully removed.
- **Retired as unsound:** the "**exactly one RPC across an arbitrarily long manual
  burst**" criterion — a pause longer than any finite cooldown is indistinguishable from
  a deliberate later recheck. **Earlier long-burst runs are invalid tests, NOT failures.**
- **A3 DB integrity proof (TEST):** `digibility.ai`
  (`website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`, `method=dns_txt`) = **exactly one
  row** (`row_count=1`), `status=pending`, `2026-07-17 16:25:18.663042+00`.
- **Cleanup via authenticated customer revoke UI (not delete; append-only audit kept):**
  - `digibility.ai` → **revoked**, `updated_at=2026-07-17 16:33:13.804585+00`.
  - Stage-5 smoke fixture `stage5-smoke-test.example`
    (`website_id=77777777-0000-0000-0000-0000000000b1`, source
    `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql`; was `pending`,
    `has_open_claim=false`) → **revoked**, `updated_at=2026-07-17 16:43:24.935897+00`.
- **Step 2B + Step 3 SQL regressions — RE-RUN COMPLETE = PASS (2026-07-18).** A read-only
  eligibility diagnostic confirmed **0** `pending`/`failed` ownership-verification rows on
  `Digi_SEO_Test` before execution. `seo_p1a_step2b_ownership_verification_service_rpcs_verification.sql`
  returned `ALL PASS — seo_p1a_step2b service-role + global-admin ownership-verification
  verification complete`; `seo_p1a_step3_worker_dns_verification_integration.sql` returned
  `ALL PASS — seo_p1a_step3 worker DNS-verification TEST integration complete`. Both scripts'
  own teardown + locked-module isolation assertions passed; both are self-cleaning,
  single-transaction, net-nothing on success. No source/migration/SQL/worker/frontend/config
  change; production untouched.
- **Authenticated browser role matrix — COMPLETE = PASS (2026-07-18, `Digi_SEO_Test`).**
  Operator-executed logged-in click-through of the Step 5 UI against the real Supabase-mode
  app, each role followed by sign-out:
  - **Owner:** authenticated successfully; on `/seo/websites` saw `digibility.ai` with
    ownership controls enabled; **Verify ownership** issued exactly one
    `seo_ownership_verification_initiate` request (HTTP 200); UI changed to
    **Verification pending** and remained pending after a hard refresh; sign-out
    redirected to `/seo/login` and removed protected content.
  - **Admin:** authenticated successfully; saw the persisted **pending** status with
    **Check again / Re-verify / Revoke** enabled; **Check again** issued exactly one
    `seo_ownership_verification_recheck` request (HTTP 200); status remained **pending**;
    sign-out removed protected content.
  - **team_member:** authenticated successfully; saw **pending** status, **no** ownership
    action buttons, and the read-only role message; Network evidence confirmed **no**
    initiate/recheck/reverify/revoke request fired; sign-out removed protected content.
  - **client:** authenticated successfully; identical read-only affordance to team_member;
    Network evidence confirmed **no** write RPC fired; sign-out removed protected content.
  - **Cross-role/session isolation:** status read live from Supabase across every role
    switch (no stale/cached cross-user state); protected routes inaccessible after every
    sign-out. **No defect found; no file changed** during this browser acceptance.
- **Pending operator item (sole remaining P1a lock blocker):** real **`verify-once` worker
  binary** run against `Digi_SEO_Test` (needs `SUPABASE_SERVICE_ROLE_KEY`).
- **P1a is implemented but NOT module-locked. P1b has not started. Production untouched.**

## 10. Accepted implementation decisions
- Simple, predictable, **visible bounded post-action lock** over clever timing logic.
- Cooldown is legitimately part of the native `disabled` (the keep-alive design that
  required it *out* of `disabled` is retired).
- Fixed **3000 ms** cooldown — spans mutation+refetch, absorbs impatient bursts, and is
  negligible vs DNS-TXT propagation timelines (so it never blocks a legitimate recheck).
- Customer `recheck` is non-destructive (reuses the token, no new row) → a **UI-only**
  guard is sufficient; **no server-side rate limiting** added for P1a.

## 11. Rejected / superseded approaches
- **Synchronous in-flight latch only** (blocked overlap but not spaced clicks) — superseded.
- **Leading-edge throttle + keep-alive cooldown** (proved correct on a single persistent
  instance; still couldn't satisfy the unsound "one-RPC-per-arbitrary-burst" goal) — retired.
- **The "one RPC across an arbitrarily long burst" acceptance criterion itself** — retired
  as technically unsound.
- **Increasing the cooldown blindly / trailing debounce / delayed first click /
  module-global guard / DB-server rate limiting** — explicitly not adopted.

## 12. Completed verification & evidence
- Static: root `tsc --noEmit` clean; `npm run build` clean; one-file frontend scope for the
  fix; all `[OVP]` removed (grep = none); security sweep clean (no service-role/secret/env/
  direct-DB/console in the panel; Step 4 hooks only).
- Mock quantitative proof: recheck counted **directly via the mock store's
  `lastCheckedAt`** (not token rotation) → 8 rapid clicks = **exactly 1** accepted recheck;
  +1 deliberate after cooldown = 2 total; same guard confirmed for initiate/reverify/revoke;
  no console errors; **zero Supabase calls** in mock.
- Authenticated operator: **AT-1** rapid double/triple click → exactly 1 recheck POST (200);
  **AT-2** disabled ≈3.5 s then re-enables; **AT-3** deliberate click after re-enable → 1
  new POST (200); **AT-4** no overlapping duplicates; UI stayed `Verification pending`.
- Regression baseline (from Step 6): P1a Steps 1/2A/2B SQL + Step 3 integration SQL;
  locked crawler 16C–16H; Stage 6 smoke/create/transition; worker suite 74/74; backend role
  matrix (SQL) — **all PASS**.
- **Regression re-run (2026-07-18):** P1a Step 2B SQL + Step 3 integration SQL re-executed
  on TEST after the A3/revoke cleanup — **both ALL PASS** (explicit sentinels; locked-module
  isolation counts unchanged; self-cleaning). See §9.
- **Authenticated browser role matrix (2026-07-18):** owner/admin/team_member/client
  click-through on `Digi_SEO_Test` — **PASS** (see §9 for full per-role evidence).

## 13. Remaining blockers & unresolved verification
1. Real **`verify-once` worker binary** vs `Digi_SEO_Test` — needs
   `SUPABASE_SERVICE_ROLE_KEY` in the worker env. **(Sole remaining P1a lock blocker.)**
2. Legacy Stage 2–5 psql-style smokes — tooling limitation (documented; not a defect).

## 14. Production / test environment status
All work is on **`Digi_SEO_Test`** only. **Production is untouched** (no migration, code,
RPC, RLS, worker, config, or data change in production at any point). The crawler worker is
**not deployed**; the module is not customer-operational.

## 15. Exact next step
The P1a Step 2B + Step 3 SQL regressions are **re-run and PASS**, and the authenticated
**browser role matrix is COMPLETE — PASS** (§9, 2026-07-18). The **sole remaining
operator-acceptance item** (§13) is the real **`verify-once` worker binary** run against
`Digi_SEO_Test`. P1b — verified-only crawl enqueue enforcement — is the separately-approved
milestone after that item passes, and remains not started.

## 16. Actions that must NOT be taken yet
Do **not**: start P1b; mark P1a accepted/locked; deploy the worker; touch production;
modify locked modules without explicit authorization; edit applied migrations; delete
operator/fixture data by direct SQL (use the customer revoke path); commit or push; expose
any credential/token.

## 17. ChatGPT ↔ Claude working protocol
- **ChatGPT owns:** planning, sequencing, risk review, acceptance-criteria interpretation,
  and generating the prompts given to Claude.
- **Claude (Claude Code) owns:** repository inspection and approved implementation/
  documentation execution in this repo.
- **Prompt discipline:** prompts must be **token-efficient** — refer to confirmed
  architecture/docs (by repo-relative path) instead of restating the whole project.
- **Claude must:** inspect before editing; **list expected files + module-lock
  implications before implementing**; preserve **BFF boundaries** (browser→Supabase direct;
  service-role only in the worker) and **backward compatibility**; **not modify locked
  modules without explicit authorization**; after an accepted checkpoint, **update all
  relevant authoritative docs** and **identify/reconcile stale or contradictory docs**; and
  **not commit, push, touch production, or expose credentials** unless explicitly instructed.
- **Operator actions** (shell/DB/browser steps) are given **one step at a time**, waiting
  for evidence, **unless a complete runbook is explicitly requested**.
- **Review loop:** after **every** Claude response, ChatGPT reviews the returned evidence
  before issuing the next prompt.

## 18. Required Claude model-selection protocol
ChatGPT must **recommend exactly one model for every Claude prompt**, chosen from:
**Opus 4.8, Opus 4.7, Opus 4.6, Sonnet 5, Sonnet 4.6, Fable 5, Haiku 4.5**.
Guidance:
- **Opus 4.8 / 4.7** — hard architecture/root-cause/security/acceptance-risk reasoning,
  ambiguous multi-file changes, anything touching locked-module boundaries.
- **Opus 4.6** — solid deep reasoning when 4.8/4.7 are unavailable.
- **Sonnet 5** — routine, well-specified implementation and verification with clear scope.
- **Sonnet 4.6** — lighter well-specified edits / mid-size doc reconciliation.
- **Fable 5 / Haiku 4.5** — mechanical/low-ambiguity doc or status edits, greps, quick
  inspections. Prefer **Haiku 4.5** for the cheapest fast passes.
State the recommended model **with a one-line reason** at the top of each Claude prompt.

## 19. Minimum files to upload into a fresh ChatGPT thread
1. `CHATGPT_CONTEXT_HANDOVER.md`  *(this file — start here)*
2. `CURRENT_PROJECT_STATUS.md`  *(authoritative current status)*
3. `PROJECT_CONTEXT.md`  *(product goals, non-negotiable rules, build constraints)*
4. `MODULE_LOCKS.md`  *(what is locked and the additive-extension procedure)*
5. `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`  *(P1a verdict + acceptance log §10)*
6. `P1A_STEP5_DOUBLE_SUBMIT_FIX.md`  *(final guard §9 + A3/cleanup §10)*

Optional next reads if deeper context is needed: `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`,
`ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`, `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md`,
`BACKEND_MILESTONE_HANDOFF.md`, `PROJECT_DOCUMENTATION_INDEX.md`.

## 20. Repository-relative paths for every referenced document/artifact
- `CHATGPT_CONTEXT_HANDOVER.md` — this handover.
- `CURRENT_PROJECT_STATUS.md` — authoritative status.
- `PROJECT_CONTEXT.md` — product/build context + non-negotiable rules.
- `PROJECT_DOCUMENTATION_INDEX.md` — documentation map.
- `DOCUMENTATION_WORKFLOW_RULES.md` — doc maintenance rules.
- `MODULE_LOCKS.md` — locked modules + additive-extension procedure.
- `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` — no-BFF / Supabase-direct / RLS-authoritative.
- `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md` — crawler worker = trusted-server exception.
- `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md` — auth approach.
- `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` — Option B plan; BFF/parent-integration deferred.
- `BACKEND_MILESTONE_HANDOFF.md` — backend-state addendum + 2026-07-17 checkpoint.
- `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` — P1a sign-off + acceptance log (§10).
- `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` — final double-submit guard (§9) + A3/cleanup (§10).
- `P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md` — Step 5 UI record (final guard §6c).
- `P1A_STEP1_OWNERSHIP_VERIFICATION_DB_CONTRACT.md`,
  `P1A_STEP2A_OWNERSHIP_VERIFICATION_RPCS.md`,
  `P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`,
  `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`,
  `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md` — P1a step records.
- `src/pages/seo/websites/OwnershipVerificationPanel.tsx` — the guarded UI panel (final fix).
- `src/hooks/useOwnershipVerification.ts`, `src/services/ownershipVerificationService.ts`,
  `src/services/supabase/seoOwnershipVerificationSupabaseService.ts`,
  `src/mocks/ownershipVerificationMockData.ts` — P1a Step 4 service layer.
- `crawler-worker/src/verification/{dns,verificationGateway,runner}.ts`,
  `crawler-worker/src/modes.ts` — isolated `verify-once` worker module.
- `supabase/migrations/20260716120031…120033_*` — P1a Steps 1/2A/2B migrations (TEST).
- `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql` — Stage-5 smoke fixture.

---
*End of handover. Production untouched; no code/DB/config/test change was made to produce
this file.*
