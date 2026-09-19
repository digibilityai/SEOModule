# Module Locks

**Purpose:** the authoritative, per-module lock registry for this repository.
`PROJECT_BOOTSTRAP.md`'s "Locked Modules" section defines *what* locking means
and the general rule (all nine Module Completion Rules passed → locked → no
changes without a proven defect); this file is *where that rule is applied per
module*, with the exact locked file list, what's allowed, and the evidence bar
required to touch it.

**How to use this file:**
- Before modifying any file listed under a `LOCKED` module below, you must have
  the "Evidence required before modification" for that module, and explicit
  human approval.
- Before starting a task that touches a listed file, check this file first —
  not just `PROJECT_BOOTSTRAP.md`'s summary table.
- When a module passes its ninth Module Completion Rule (Sign-off), add an
  entry here using the template in [Template for a new entry](#template-for-a-new-entry)
  — do not mark it locked in `PROJECT_BOOTSTRAP.md`'s table without a
  corresponding entry here.
- Entries are added/updated only when a module's lock status genuinely
  changes — this is not restated on every task.

---

## Stage 6 — Off-Page Authority Workflows and AI Visibility Reads

**Status:** LOCKED (**implemented scope only** — deferred Stage 6 work below
remains UNLOCKED and open for separately authorized additive implementation)
**Locked on:** 2026-07-13
**Owner documentation:** `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`,
`PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md`, `STAGE_6_FINAL_REGRESSION_SIGNOFF.md`

**Important:** this lock protects the *validated behaviour and contracts* of the
completed Stage 6 scope. It does **not** claim every conceivable Off-Page
Authority / AI Visibility feature is built. See "Deferred scope — remains
UNLOCKED" below; those exclusions are not defects in the locked scope.

### Locked scope (completed + regression-verified)

1. **Off-Page Authority reads** — Supabase-backed opportunity, campaign,
   spam-risk-review, and authority-overview reads; website/workspace scoping;
   mapping into `OffPageOpportunity`, `AuthorityCampaign`, `CampaignTask`.
2. **Opportunity workflow** — via `seo_authority_opportunity_transition` (never
   a direct status UPDATE): the legal state matrix, owner/admin-only `reject`,
   owner/admin/team_member for other actions, client read-only, append-only
   activity, correct `actor_role_snapshot`/`created_by`, non-masking RPC errors,
   status-conditional + role-gated UI.
3. **Campaign creation + approval workflow** — atomic creation via
   `seo_authority_campaign_create`; transitions via
   `seo_authority_campaign_transition`; no direct frontend `approval_status`
   update; no creation activity row; owner/admin-only approve+reject;
   owner/admin/team_member create/submit/return-to-draft; client read-only;
   `Return to Draft` UI-exposed **only** from `rejected`; junction + task
   integrity; append-only activity; non-masking behaviour; double-submit
   prevention; **campaign-create client role gating**; shared accessible
   `RoleGateTooltip`; mock-mode compatibility.
4. **AI Visibility — read-only implemented scope** — prompt-tracking, content-gap
   and mention reads; website scoping; loading/empty/error handling; existing
   mock-data behaviour; clear separation between seeded reads and the mock
   generation control; current data source represented as `manual_seed`.
   (AI Visibility **writes** and real LLM ingestion are **not** locked/implemented.)

### Protected contracts

- **Opportunity statuses:** `suggested`, `shortlisted`, `approval_required`,
  `in_progress`, `expert_review_requested`, `completed`, `rejected`, `avoided`.
- **Opportunity actions:** `shortlist`, `request_approval`,
  `request_expert_review`, `start`, `complete`, `reject`, `avoid`.
- **Campaign statuses:** `draft`, `pending_approval`, `approved`, `rejected`.
- **Campaign actions:** `submit_for_approval`, `approve`, `reject`,
  `return_to_draft`.
- **RPCs (names + parameter contracts):** `seo_authority_opportunity_transition`,
  `seo_authority_campaign_create`, `seo_authority_campaign_transition`.
- **Tables:** `seo_authority_opportunities`, `seo_authority_campaigns`,
  `seo_authority_campaign_opportunities`, `seo_authority_campaign_tasks`,
  `seo_authority_activity`, `seo_ai_prompt_tracking`, `seo_ai_content_gaps`,
  `seo_ai_mentions` — names, columns, constraints, RLS, and the append-only
  activity design.
- **Frontend/service contracts:** `offPageService` / `aiVisibilityService`
  public signatures; read-shape types `OffPageOpportunity`,
  `AuthorityCampaign`, `CampaignTask`; role values; env-var names.
- **Applied migrations** (`…120017`–`…120024`) are **immutable** regardless of
  this lock.

### Locked files

Locked **behaviour/contracts** live in these files. These are *shared* files
that may later receive separately-authorized additive extensions (see "Changes
allowed") — the lock protects the validated behaviour, not the file against all
future edits.

- `src/pages/seo/AuthorityBuilderPage.tsx`
- `src/pages/seo/offpage/OpportunityCard.tsx`
- `src/pages/seo/offpage/CampaignBuilder.tsx`
- `src/pages/seo/offpage/CampaignList.tsx`
- `src/pages/seo/offpage/RoleGateTooltip.tsx`
- `src/pages/seo/offpage/offPageLabels.ts`
- `src/pages/seo/offpage/AuthorityHeader.tsx`,
  `src/pages/seo/offpage/SpamRiskReviewSection.tsx`,
  `src/pages/seo/offpage/OffPageFiltersBar.tsx`
- `src/pages/seo/AiVisibilityPage.tsx` (read behaviour + mock-generation control)
- `src/services/offPageService.ts`
- `src/services/aiVisibilityService.ts` (reads)
- `src/services/supabase/seoOffPageAuthoritySupabaseService.ts`
- `src/services/supabase/seoAiVisibilitySupabaseService.ts` (reads)
- Applied migrations `supabase/migrations/20260711120017…`–`20260712120024…` (immutable)

### RPCs and tables

See "Protected contracts" — the three Stage 6 RPCs and eight Stage 6 tables.

### Verification evidence

- `STAGE_6_FINAL_REGRESSION_SIGNOFF.md` (2026-07-13) — the immediate lock
  evidence (static + SQL + authenticated browser matrix + mock mode +
  earlier-stage smoke, all PASS; 0 unintended writes; production untouched).
- `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`, `PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md`.
- Regression baseline SQL scripts (must remain PASS + idempotent):
  `supabase/test/seo_stage6_offpage_ai_visibility_smoke_test.sql`,
  `supabase/test/seo_stage6_authority_campaign_create_verification.sql`,
  `supabase/test/seo_stage6_authority_campaign_transition_verification.sql`.

### Changes allowed (separately-authorized, backward-compatible, additive only)

- Proven bug fixes to the locked behaviour.
- Security fixes.
- Additive extension points for **deferred** features (below), e.g. campaign
  task-completion controls/writes, AI Visibility writes, additional read
  fields, new additive service methods/RPCs — **only** where they preserve every
  locked contract and behaviour above.
- Required compatibility changes from an approved shared-dependency change.

A future task touching these shared files must: (1) state it touches this locked
module; (2) name the locked behaviour that must stay unchanged; (3) use additive
migrations only; (4) preserve API + frontend read-shape compatibility; (5) run
targeted locked-scope regression against the Phase 15C/15D + Stage 6 sign-offs;
(6) update documentation; (7) get explicit approval if a breaking change is
unavoidable. No unrelated refactoring while modifying a shared locked file.

### Not allowed (without an explicit unlock or approved additive extension)

- Rename/remove Stage 6 tables/columns or RPCs.
- Change status or action strings; change role permissions; bypass the
  transition RPCs; add a direct `approval_status`/opportunity-`status` update.
- Change append-only activity behaviour; remove mock mode; mask backend
  failures; change service signatures or read-shape types.
- Expose `pending_approval → draft` in the UI; re-enable client campaign
  creation; weaken campaign atomicity; remove role tooltips/handler guards.
- Modify applied migrations. Refactor-for-style/rename/move on locked behaviour.

### Deferred scope — remains UNLOCKED (open for separate additive work)

Campaign task-completion writes; AI Visibility write workflows; real
crawler/GSC/GA4 integration; real LLM ingestion; external ingestion/scheduled
jobs; parent-platform/BFF integration; production deployment; route-level
`ProtectedRoute`; Competitors/Roadmap/Reports backend wiring; mobile
horizontal-overflow remediation; benign favicon handling; the sign-out
global-revocation network observation. These are **not** part of the locked
scope and are **not** defects in it.

### Evidence required before modification (unlock / additive-extension procedure)

1. Reproduction steps (for a bug fix) or the additive feature spec.
2. Expected behaviour. 3. Actual behaviour (bug) or the extension's contract.
4. Evidence (screenshot, console error, failing test, DB result, or log).
5. Root-cause analysis (bug) or additive-only design confirmation.
6. Explicit human approval to modify the locked module.
7. Confirmation the change is additive and preserves every protected contract.

### Required after an approved change

- Targeted locked-scope regression passes (the three Stage 6 SQL scripts + the
  relevant authenticated browser checks) against the Phase 15C/15D + Stage 6
  sign-offs.
- Owner documentation receives a dated note.
- `CURRENT_PROJECT_STATUS.md` updated if status changed.

_Prior status history: Opportunity Workflow signed off 2026-07-12
(`PHASE_15C_…`); Campaign Workflow signed off + client create-gating fixed
2026-07-13 (`PHASE_15D_…`); Stage 6 final regression PASS 2026-07-13
(`STAGE_6_FINAL_REGRESSION_SIGNOFF.md`) — which is the basis for this lock._

---

## Page Performance Tracker

**Status:** LOCKED
**Locked on:** 2026-07-10
**Owner documentation:** PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md

### Locked files

- src/pages/seo/PagePerformancePage.tsx
- src/services/performanceService.ts
- src/services/supabase/seoPagePerformanceSupabaseService.ts
- src/pages/seo/page-performance/**

### Changes allowed

- Proven bug fixes
- Security fixes
- Explicitly approved product enhancements
- Required compatibility changes caused by an approved shared dependency change

### Not allowed

- Refactoring for style
- Renaming
- Moving files
- Changing public service signatures
- Replacing the adapter pattern
- Modifying mock behavior
- Changing fallback behavior without a reproduced defect

### Evidence required before modification

A task must include:

1. Reproduction steps
2. Expected behavior
3. Actual behavior
4. Evidence such as screenshot, console error, failing test, database result, or log
5. Root-cause analysis, or a narrowly scoped investigation task
6. Explicit human approval to modify the locked module

### Required after an approved change

- Relevant tests must pass
- Module regression checklist must pass
- Owner documentation must receive a dated fix note
- CURRENT_PROJECT_STATUS.md must be updated if status changed

### Approved-change log

- **2026-07-14 — proven bug fix (approved).** During Phase 16H Scenario 1 operator
  acceptance, a reproduced **refresh-race** was fixed in `PagePerformancePage.tsx`:
  the cross-workspace fallback could evaluate before the current website
  onboarding/page query completed and incorrectly replace the valid website. The
  change was narrow (fallback now waits for completed onboarding + a completed
  page fetch), **display/query-timing only** — no database, service signature,
  adapter, mock behaviour, fallback contract, or Stage 6 change; `npm run build`
  passed. This is an **allowed proven bug fix** under this lock; the lock remains
  in force. Detail in `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md` + (to be noted)
  `PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md`.

---

## Crawler customer UI + crawl/audit/publishing contracts (Phase 16C–16H implemented scope)

**Status:** LOCKED (**implemented scope only** — production-readiness work below
remains UNLOCKED)
**Locked on:** 2026-07-15
**Owner documentation:** `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`,
`CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`, `OPERATOR_TEST_RESULTS.md`

**Important:** this lock protects the *validated behaviour and contracts* of the
Phase 16C–16H implemented scope, accepted on TEST (all 7 operator scenarios PASS;
Scenario 7 accepted with administrative evidence notes). It does **not** claim the
crawler is production-ready or customer-operational — see "Deferred scope — remains
UNLOCKED" below; those exclusions are not defects in the locked scope.

### Locked scope (implemented + TEST-verified + operator-accepted)
1. **Customer crawl request/status/cancel UI** — `/seo/audit` "Website crawl" panel: role-gated Start crawl (owner/admin/team_member; client disabled + tooltip "Requires the owner, admin, or team member role."), two-step confirm, Supabase-only status polling (4 s while active, stops at terminal, hidden-tab pause), freshness from real timestamps, legal cancellation, published-result links.
2. **Crawler lifecycle status mappings** — the customer labels for `queued/claimed/running/retry_wait/cancellation_requested/completed/partially_completed/failed/cancelled` (Queued/Preparing/Crawling/Waiting to retry/Cancelling/Completed/Partially completed/Failed/Cancelled).
3. **Explicit crawl→audit association** — `seo_crawl_request_audit` returns both ids; no "latest audit" guessing; one audit run per crawl.
4. **Audit-finalization behaviour** — a linked **running** audit is finalized `failed` on crawl cancel/fail/retry-exhaustion/stale-recovery, and **never** overwrites a completed historical audit (migration `20260715120030`).
5. **Published-result preservation** — failed/cancelled attempts never delete or alter previously published Audit results; the newest **completed** audit remains the customer-visible result.
6. **Page Inventory publication-preservation rules** — publishing updates only crawler-owned technical facts (stale-job-safe, newer wins), preserves user-owned fields, never removes unseen pages, writes **no** recommendation and **no** audit score.

### Protected contracts
- **Statuses:** `seo_crawl_jobs` status set (above); audit-run statuses; publication statuses. **Do not rename or add customer-facing status strings without an approved additive change.**
- **RPC names + parameter contracts:** `seo_crawl_request`, `seo_crawl_cancel`, `seo_crawl_request_audit`, `seo_crawl_claim_job`, and the service-role-only worker lifecycle/discovery/extraction/publishing/finalization RPCs.
- **Frontend crawl contracts:** `crawlService` public methods; `useWebsiteCrawl` hooks; crawl query keys (`["seo-crawl-status", websiteId, userId]`, `["seo-crawl-publication", jobId, userId]`, `["seo-crawl-role", workspaceId, userId]`); customer-safe read columns (no lease token/worker id/correlation id/config); mock-mode preview; sign-out cache-clear + user-scoped isolation (`SessionSync`, `useSeoSignOut`).
- **Worker service-role-only boundary** — `authenticated`/`anon` denied on all worker RPCs.
- **Applied migrations `20260713120025`–`20260715120030` are immutable** regardless of this lock.

### Locked files (behaviour/contracts)
- `src/pages/seo/audit/crawl/{CrawlPanel,StartCrawlControl,CrawlStatusCard,CrawlStatusBadge}.tsx`, `src/hooks/useWebsiteCrawl.ts`, `src/services/crawlService.ts`, `src/services/supabase/seoCrawlSupabaseService.ts`, `src/mocks/crawlMockData.ts`, `src/lib/crawlStatus.ts`, `src/types/crawl.ts`, and the `<CrawlPanel>` integration in `src/pages/seo/WebsiteAuditPage.tsx`.
- `crawler-worker/**` (worker source + the discovery/extraction/publishing pipeline).
- Applied migrations `supabase/migrations/20260713120025…`–`20260715120030…` (immutable).

### Verification evidence
- `OPERATOR_TEST_RESULTS.md` (all 7 scenarios PASS), `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`.
- Worker unit tests 47/47; DB verifications `seo_phase16c/d/e/f/g` + `seo_phase16h_crawl_audit_finalization_verification.sql` (must remain PASS + idempotent); frontend `tsc`/build clean.

### Changes allowed (separately-authorized, backward-compatible, additive only)
Proven bug fixes; security fixes; additive extension points for the **deferred** production-readiness features below — only where every locked contract/behaviour above is preserved, using additive migrations only, with targeted locked-scope regression re-run and explicit approval for any unavoidable breaking change.

### Deferred scope — remains UNLOCKED (open for separate authorized work)
Production worker deployment/runtime; secrets management; **domain-ownership verification**; **usage/subscription enforcement**; rate limits; monitoring/alerting; scheduler/poll operation; production migration + rollback plans; recommendation generation; audit scoring; GSC/GA4/AI-visibility ingestion; live public-domain crawling; the future wider-Digibility BFF integration. These are **not** part of the locked scope and are **not** defects in it.

### Evidence required before modification / Required after an approved change
Same procedure as the Stage 6 entry (reproduction or additive spec → expected/actual → evidence → additive-only design → explicit approval → additive migrations only), then: targeted locked-scope regression (the crawler DB verifications + worker tests + relevant authenticated browser checks) passes; owner documentation gets a dated note; `CURRENT_PROJECT_STATUS.md` updated if status changed.

**Open (non-blocking) item:** a terminal crawl retains prior retry `error_code`/`error_message`; not customer-visible for a `completed` job. Candidate for a future tiny additive cleanup (does not affect the locked behaviour).

### Approved additive-extension log

- **2026-07-16 — P1a Step 3: isolated DNS-TXT ownership-verification worker module (approved additive extension).** Under explicit human approval, a new **isolated** ownership-verification runner was added inside `crawler-worker/**`. This is an **additive extension**, not a change to the locked crawler behaviour.
  - **Worker files added:** `crawler-worker/src/verification/{dns,verificationGateway,runner}.ts`, `crawler-worker/src/modes.ts`, `crawler-worker/test/ownershipVerification.test.ts`.
  - **Worker files edited (minimal, additive):** `crawler-worker/src/index.ts` (imports `parseMode` from the new `modes.ts`; adds a `verify-once` branch handled **before** any crawl `JobGateway`/health-check/stale-recovery is constructed) and `crawler-worker/src/config.ts` (**2 optional** additive fields: `verificationLeaseSeconds?`, `verificationFixtureDnsPath?` — no existing field/default changed).
  - **Locked crawl behaviours preserved:** crawl job claim, lease-token handling, heartbeats, retry scheduling, stale recovery, cancellation acknowledgement, discovery, robots, sitemap, extraction, issue detection, publishing, audit finalization, crawl statuses, the `dry-run`/`one-shot`/`poll` modes, `CRAWLER_ALLOW_NON_TEST_JOBS`, and all crawler RPC names/signatures/grants/return shapes — **all unchanged**. The verification module imports nothing from the crawl processor/worker/job gateway and never touches crawler jobs/attempts/events/leases/statuses.
  - **No crawl contract change; no DB change:** Step 3 created **no migration, no schema, no new RPC** — it reuses the Step 2B RPCs (`seo_ownership_verification_claim`/`record_result`). No crawler migration or RPC was modified.
  - **Regression evidence:** worker suite **74/74 pass, 0 fail**; standalone `seo_phase16c/d/e/f/g` + `seo_phase16h_crawl_audit_finalization` verifications **ALL PASS**; Step 1/2A/2B verifications **ALL PASS**; the Step 3 TEST integration (`seo_p1a_step3_worker_dns_verification_integration.sql`) **ALL PASS** with 0 crawl/audit/Page-Inventory/Page-Performance/recommendation/Stage-6 rows changed; root `tsc`/`build` clean; security sweep clean. See `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`.
  - **No production deployment:** the worker is not deployed; the `verify-once` mode is for controlled TEST execution only; no infrastructure/secret/scheduler change. The Crawler 16C–16H lock remains fully in force.
- **2026-07-16 — P1a Domain Ownership Verification: implemented, NOT yet locked (status note, no lock added).** Step 6 validation + full regression is complete with verdict **`P1A IMPLEMENTED — OPERATOR ACCEPTANCE PENDING`** (`P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`). All automated P1a + locked 16C–16H + Stage 6 regressions PASS; worker 74/74; security sweep 9/9; **no defect**. A **formal implemented-scope lock is deliberately withheld** because two operator-acceptance items could not be executed in this environment: the authenticated **browser** role matrix (no TEST-user credentials/session) and the real DNS **worker binary** `verify-once` run (no `SUPABASE_SERVICE_ROLE_KEY`). No P1a file/contract is added to any LOCKED list yet; add a formal Domain Ownership Verification lock entry only after those two items pass. **P1b (verified-only crawl enqueue enforcement) is NOT implemented** and, when built, is a separately-approved additive extension to the Crawler 16C–16H contracts.
- **2026-07-18 — P1a Domain Ownership Verification: authenticated browser role matrix COMPLETE — PASS (status note only, no lock added).** The authenticated browser role matrix referenced in the entry above has now been executed on `Digi_SEO_Test` and is **PASS** (owner/admin/team_member/client + sign-out/session isolation; full evidence in `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §3 + §10 2026-07-18 entry). **P1a is still NOT module-locked** — no entry is added to any LOCKED list here. The **sole remaining operator-acceptance item** is the real DNS **worker binary** `verify-once` run against `Digi_SEO_Test` (no `SUPABASE_SERVICE_ROLE_KEY` in this environment). P1b remains NOT implemented. Production untouched.

---

## P1a — Domain Ownership Verification (DNS-TXT)

**Status:** LOCKED (**implemented scope only** — P1b verified-only crawl enqueue
enforcement remains UNLOCKED/unimplemented, as does any future non-DNS-TXT
verification method or production deployment of `verify-once`)
**Locked on:** 2026-07-19
**Owner documentation:** `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`,
`P1A_STEP1_OWNERSHIP_VERIFICATION_DB_CONTRACT.md`,
`P1A_STEP2A_OWNERSHIP_VERIFICATION_RPCS.md`,
`P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`,
`P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`,
`P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md`,
`P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md`, `P1A_STEP5_DOUBLE_SUBMIT_FIX.md`

**Important:** this lock protects the *validated behaviour and contracts* of the
completed P1a scope (Steps 1–6), accepted on TEST across automated SQL, worker
unit/integration tests, the authenticated browser role matrix, and the real
`verify-once` worker-binary run. It does **not** claim the SEO module is
production-ready, that the worker is deployed/scheduled, or that crawl enqueue
is ownership-gated — that is **P1b**, which remains open (see "Deferred scope"
below); those exclusions are not defects in the locked scope.

### Locked scope (implemented + TEST-verified + operator-accepted)
1. **DB contract (Step 1)** — `seo_ownership_verifications` (one row per
   website+method; `UNIQUE(website_id, method)`; status
   `pending`/`verified`/`failed`/`revoked`; `method='dns_txt'` only; absence of a
   row = unverified) + append-only `seo_ownership_verification_events`;
   default-deny-write RLS (workspace-member SELECT only; no customer
   INSERT/UPDATE/DELETE).
2. **Guarded customer RPCs (Step 2A)** — `seo_ownership_verification_initiate` /
   `recheck` / `reverify` / `revoke`: `SECURITY DEFINER`, `authenticated`-only,
   owner/admin server-gated (team_member/client/non-member/anon denied),
   append-only audit, non-masking errors, no direct customer table write.
3. **Service-role claim/result + global-admin override (Step 2B)** — internal
   `seo_ownership_verification_claims` claim/lease ledger (global-admin-SELECT
   only; open-claim unique index); RPCs `seo_ownership_verification_claim` /
   `record_result` (**service_role only**) and
   `seo_ownership_verification_admin_override` (`authenticated`, internally
   `seo_is_global_admin`-gated, reason required, not exposed in the customer UI).
4. **Isolated DNS-TXT verification worker (Step 3)** — `crawler-worker/src/verification/**`
   (`verify-once` mode): claim ONE pending/failed item → resolve
   `_digibility-site-verification.<host>` via real Node DNS TXT (or the
   TEST-only fixture resolver) → exact case-sensitive challenge match →
   `verified`/`failed` via the Step 2B result RPC; **no auto-retry**; secret-safe
   logging (challenge/lease values never logged); fully independent of the crawl
   processor/job gateway/crawl-job lifecycle (imports nothing from them).
5. **Frontend service + hooks (Step 4)** — `ownershipVerificationService` public
   dispatcher, `seoOwnershipVerificationSupabaseService` (RLS read +
   Step-2A-RPC-only writes), the deterministic mock adapter, and the
   `useOwnershipVerification*` hooks; customer-safe read shape
   (`OwnershipVerificationView`); non-masking write error surfacing.
6. **Customer UI (Step 5)** — `OwnershipVerificationPanel` rendered in
   `WebsiteCard`: status + DNS-TXT instructions + copy controls, owner/admin
   actions, read-only affordance + accessible role tooltip for
   team_member/client, explicit two-step revoke confirmation, and the final
   double-submit guard — a per-action state machine
   **`idle → in_flight → cooldown → idle`** with a **fixed 3000 ms** post-settle
   cooldown (AT-1..AT-4 accepted criteria in `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §9).

### Protected contracts
- **Statuses:** `pending` / `verified` / `failed` / `revoked` (Step 1);
  `method='dns_txt'` is the only supported method today. **Do not rename or add
  customer-facing status/method strings without an approved additive change.**
- **RPC names + parameter contracts:** `seo_ownership_verification_initiate`,
  `recheck`, `reverify`, `revoke` (customer, `authenticated`-only, no
  global-admin override); `seo_ownership_verification_claim`, `record_result`
  (`service_role`-only); `seo_ownership_verification_admin_override`
  (`authenticated`, internally global-admin-gated).
- **DNS-TXT contract:** host name `_digibility-site-verification.<host>`; exact,
  case-sensitive match against multi-string-flattened TXT records; deterministic
  customer-safe failure reasons (`dns_not_found` / `dns_mismatch` / `dns_timeout`
  / `dns_temporary` / `dns_malformed` / `internal_error`) with the internal
  code/detail stored **only** on the admin-only claim row.
- **Frontend contracts:** `ownershipVerificationService` public function
  signatures; the `OwnershipVerificationView` / `OwnershipVerificationWriteError`
  read/write-error shapes; the
  `["seo-ownership-verification", websiteId, userId]` and
  `["seo-ownership-verification-role", workspaceId, userId]` query keys; the
  `idle → in_flight → cooldown → idle` double-submit guard and its fixed
  3000 ms cooldown.
- **Worker/security boundary:** the service-role key lives **only** in the
  `crawler-worker` runtime; `verify-once` never imports from or touches the
  crawl processor, `JobGateway`, or any crawler job/attempt/event/lease/status
  table; DNS-only (no HTTP → no new SSRF surface); the challenge value and
  lease token are **never logged**.
- **Applied migrations `20260716120031`–`20260716120033` are immutable**
  regardless of this lock.

### Locked files
- `src/pages/seo/websites/OwnershipVerificationPanel.tsx`, and its integration
  in `src/pages/seo/WebsiteCard.tsx`.
- `src/hooks/useOwnershipVerification.ts`,
  `src/services/ownershipVerificationService.ts`,
  `src/services/supabase/seoOwnershipVerificationSupabaseService.ts`,
  `src/lib/ownershipVerification.ts`, `src/types/ownershipVerification.ts`,
  `src/mocks/ownershipVerificationMockData.ts`.
- `crawler-worker/src/verification/{dns,verificationGateway,runner}.ts`,
  `crawler-worker/src/modes.ts` (the `verify-once` mode), and the additive
  `verify-once` branch in `crawler-worker/src/index.ts` + the 2 optional
  `verificationLeaseSeconds?`/`verificationFixtureDnsPath?` fields in
  `crawler-worker/src/config.ts` (shared with the Crawler 16C–16H lock; see
  that entry's approved-additive-extension log for the original grant).
- Applied migrations `supabase/migrations/20260716120031…`–`20260716120033…`
  (immutable).

### RPCs and tables
See "Protected contracts" above — the 7 P1a RPCs (4 customer + 2 service-role +
1 global-admin-override) and the 3 P1a tables (`seo_ownership_verifications`,
`seo_ownership_verification_events`, `seo_ownership_verification_claims`).

### Verification evidence
- `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` — final Verdict `P1A COMPLETE —
  MODULE-LOCKED`, with the full §3/§4/§10 acceptance log.
- Backend authorization matrix (SQL: owner/admin/team_member/client/non-member/
  global-admin, via the Step 2A/2B verification scripts) — **ALL PASS**.
- Authenticated **browser** role matrix (2026-07-18, `Digi_SEO_Test`) —
  owner/admin/team_member/client + sign-out/session isolation — **PASS**.
- Real **`verify-once` worker-binary** run (2026-07-19, `Digi_SEO_Test`) — see
  "Accepted lock-closing evidence" below — **PASS**.
- Worker unit/integration suite **74/74**; Step 1/2A/2B SQL + Step 3 TEST
  integration SQL — **ALL PASS** (idempotent, self-cleaning); static security
  sweep **9/9**; locked crawler 16C–16H + Stage 6 non-regression **ALL PASS**;
  root `tsc`/`build` clean.

### Accepted lock-closing evidence — real `verify-once` worker-binary run (2026-07-19)
Operator ran `npm start -- --mode=verify-once` from `crawler-worker/` against
`Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`), with `crawler-worker/.env`
exported into the shell (service-role key never printed; the startup log's
`serviceRoleKey` field appeared only as `[REDACTED]`); `environment=test`.
- Claimed verification `41d2a3e8-3c7e-4b55-a282-6682a8349b69` (website
  `fb98d59c-0f7d-4724-9f60-9db385bf2592`, host `digibility.ai`) — the only
  eligible `pending`/`failed` row at the time.
- Performed a **real Node DNS TXT lookup** (not the fixture resolver — no
  `CRAWLER_VERIFICATION_FIXTURE_DNS` set) against
  `_digibility-site-verification.digibility.ai` → no matching record found.
- Persisted the result via the real `seo_ownership_verification_record_result`
  RPC: `status=failed`, failure-reason code `dns_not_found`,
  `last_checked_at=updated_at=2026-07-19 05:18:27.369182+00`.
- One new `seo_ownership_verification_events` row: `event_type=failed`,
  `from_status=pending`, `to_status=failed`, `actor=worker`,
  `note="Ownership verification failed"`, `created_at=2026-07-19
  05:18:27.369182+00`.
- Worker logged `verify_once` completion (outcome=`failed`, matching
  `verificationId`) and **exited code 0**. **No challenge value, lease token, or
  service-role key was ever printed, logged, or otherwise exposed.**
- **The legitimate DNS business outcome — customer-safe `failed`/`dns_not_found`,
  because no TXT record is currently present at that host — is not a defect.**
  The lock is granted on the **trusted worker-binary path itself** (a real
  service-role client constructing and authenticating, a real
  `seo_ownership_verification_claim` RPC call, real Node DNS resolution, and a
  real `seo_ownership_verification_record_result` RPC call — none simulated,
  unlike all prior automated evidence which used either a fake Supabase client
  or a `postgres`-superuser SQL simulation), independent of whether the DNS
  business result is `verified` or a legitimate `failed`.
- **No source, migration, SQL, worker, config, crawl-contract, or production
  file was changed during this run.**

### Changes allowed (separately-authorized, backward-compatible, additive only)
- Proven bug fixes; security fixes.
- Additive extension points for **P1b** (verified-only crawl enqueue
  enforcement) and the other deferred scope below — only where every locked
  contract/behaviour above is preserved, using additive migrations only, with
  targeted locked-scope regression re-run and explicit approval for any
  unavoidable breaking change.
- Required compatibility changes from an approved shared-dependency change.

### Not allowed (without an explicit unlock or approved additive extension)
- Rename/remove the P1a tables/columns or RPCs; change status/method/
  failure-reason strings; bypass the Step 2A/2B RPCs with a direct
  `seo_ownership_verifications`/`seo_ownership_verification_claims` table write;
  expose the global-admin override in the customer UI; weaken or remove the
  `idle → in_flight → cooldown → idle` double-submit guard or change its fixed
  cooldown without a reproduced defect; log a challenge value or lease token;
  let `verify-once` import from or touch the crawl processor, `JobGateway`, or
  any crawler job/attempt/event/lease/status object; modify applied migrations
  `20260716120031`–`20260716120033`; refactor-for-style/rename/move on locked
  behaviour.

### Deferred scope — remains UNLOCKED (open for separate additive work)
**P1b — verified-only crawl enqueue enforcement** (the crawl enqueue RPCs
`seo_crawl_request`/`seo_crawl_request_audit` do not yet check ownership
status — confirmed by inspection); non-DNS-TXT verification methods; scheduled/
automatic re-verification (no cron/poll loop exists for `verify-once`);
production deployment or scheduler operation of the `verify-once` worker;
usage/subscription enforcement tied to verification status. These are **not**
part of the locked scope and are **not** defects in it.

### Evidence required before modification (unlock / additive-extension procedure)
1. Reproduction steps (for a bug fix) or the additive feature spec (e.g. the P1b design).
2. Expected behaviour. 3. Actual behaviour (bug) or the extension's contract.
4. Evidence (screenshot, console error, failing test, DB result, or log).
5. Root-cause analysis (bug) or additive-only design confirmation.
6. Explicit human approval to modify the locked module.
7. Confirmation the change is additive and preserves every protected contract
   above.

### Required after an approved change
- Targeted locked-scope regression passes: Step 1/2A/2B SQL verification +
  Step 3 worker TEST integration SQL + the worker unit/integration suite + the
  relevant authenticated browser checks, against this entry's baseline.
- Owner documentation receives a dated note.
- `CURRENT_PROJECT_STATUS.md` updated if status changed.

_Prior status history: implemented-but-not-locked 2026-07-16
(`P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`, two operator-acceptance items
outstanding); Step 2.8 double-submit acceptance PASS 2026-07-17
(`P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §9); A3 DB integrity proof + pending-record
cleanup COMPLETE 2026-07-17; Step 2B + Step 3 SQL regression re-run PASS
2026-07-18; authenticated browser role matrix PASS 2026-07-18; real
`verify-once` worker-binary run PASS 2026-07-19 — which is the basis for this
lock (see the dated notes in the Crawler 16C–16H entry's approved-additive-
extension log above for the running history)._

---

## P1b — Verified-only Crawl Enqueue Enforcement

**Status:** LOCKED (additive extension of the Crawler 16C–16H enqueue contract)
**Locked on:** 2026-07-19
**Owner documentation:** `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md`,
`P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_PLAN.md`, `P1B_CONCURRENCY_VERIFICATION_GUIDE.md`

**Important:** this lock protects the *validated behaviour* of the verified-only
crawl enqueue precondition, applied to TEST and fully verified (acceptance +
16C–16H regression + worker suite + live two-session concurrency). It does **not**
claim the crawler is production-ready or that the optional UI defense-in-depth is
built (see "Deferred scope"). P1b was implemented under the Crawler 16C–16H lock's
additive-extension procedure; that lock and the P1a lock remain fully in force.

### Locked scope (implemented + TEST-verified)
1. **Verified-only enqueue precondition** in `public.seo_crawl_request`: a crawl job
   is created only when the website's domain ownership is currently `verified` —
   `EXISTS` a `public.seo_ownership_verifications` row with `method='dns_txt'` and
   `status='verified'`. Absence / `pending` / `failed` / `revoked` / superseded →
   rejected.
2. **Placement** after authentication / SEO-module-access / workspace resolution /
   role authorization and **before** eligibility/config validation and the crawl-job
   INSERT (preserves existing authorization-error precedence; no ownership-state leak
   to unauthorized callers).
3. **Write-time atomicity** via `FOR SHARE` on the ownership row (serializes against a
   concurrent revoke/status update; proven live on TEST — revoke-wins rejects the
   enqueue, enqueue-wins commits the job).
4. **Coverage** of every enqueue path: the direct `seo_crawl_request` call and the
   `seo_crawl_request_audit` orchestration (which calls `seo_crawl_request`
   internally). The worker never enqueues.

### Protected contracts
- **The verified-ownership precondition itself**, its placement (after role-authz,
  before eligibility/INSERT), and its `FOR SHARE` write-time atomicity — do not remove
  the row lock or weaken it to `FOR KEY SHARE`.
- **Error contract:** plain `RAISE EXCEPTION 'Domain ownership must be verified before
  this website can be crawled.'` (default SQLSTATE `P0001`; **no custom SQLSTATE**).
- **Preserved `seo_crawl_request` contract** (unchanged by P1b): function name;
  parameters `p_website_id uuid, p_idempotency_key text, p_config jsonb`; `RETURNS uuid`;
  SECURITY DEFINER; `search_path=public`; grants (`authenticated`; `anon`/PUBLIC
  revoked); role matrix; active/archived eligibility; URL validation; idempotency;
  config normalization; single-active-job rule; crawl-job INSERT shape; append-only
  event.
- **`seo_crawl_request_audit` is unchanged** and must remain so (it inherits the guard
  via the internal call; a rejection rolls back the whole orchestration → no orphan
  audit run).

### Locked files
- `supabase/migrations/20260719120034_seo_p1b_verified_only_crawl_enqueue.sql` (applied
  to TEST; **immutable** — any change is a new additive migration).
- The verified-only guard behaviour in `public.seo_crawl_request` (do not revert or
  weaken via a later migration without the procedure below).

### Verification evidence
- `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md` (2026-07-19) — full results.
- Applied migration `20260719120034` (recorded once); deployed-RPC contract check on
  TEST (guard + `FOR SHARE` present; signature/return/security/search_path/grants
  unchanged; no custom SQLSTATE; audit RPC unchanged).
- `supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql` — **ALL PASS**.
- Phase 16C–16H DB verifications (with verified-ownership fixtures) — **ALL PASS**.
- Worker suite — **74/74**.
- Live two-session `FOR SHARE` concurrency — **PASS** (both scenarios;
  `P1B_CONCURRENCY_VERIFICATION_GUIDE.md`).

### Changes allowed (separately-authorized, backward-compatible, additive only)
- Proven bug fixes; security fixes.
- Additive extension points (e.g. additional verification methods beyond `dns_txt`,
  the optional UI defense-in-depth, or a future in-flight-revocation policy) — only
  where every protected contract above is preserved, using additive migrations only,
  with targeted locked-scope regression re-run and explicit approval.

### Not allowed (without an explicit unlock or approved additive extension)
- Remove or weaken the verified-only precondition; change its placement so
  authorization-error precedence or the no-leak property is lost; remove the
  `FOR SHARE` lock or downgrade it to `FOR KEY SHARE`; introduce a custom SQLSTATE or
  change the customer-safe message without approval; mirror ownership status onto
  `seo_websites`; add a second `seo_crawl_jobs` INSERT path that bypasses the guard;
  modify `seo_crawl_request_audit` to skip the internal `seo_crawl_request` call; edit
  the applied migration `20260719120034` (use a new additive migration).

### Deferred scope — remains UNLOCKED
Optional UI defense-in-depth (disable/explain Start-crawl + surface the RPC message —
touches the locked crawl-UI files, separate approval); a revocation policy for an
**in-flight** crawl; non-DNS-TXT verification methods; production deployment. Not part
of the locked scope; not defects in it.

### Evidence required before modification / Required after an approved change
Same procedure as the Crawler 16C–16H entry (reproduction or additive spec →
expected/actual → evidence → additive-only design → explicit approval → additive
migrations only), then: the P1b verification + the 16C–16H DB verifications + the
worker suite re-run and pass; the two-session concurrency re-checked if the lock/guard
is touched; owner documentation gets a dated note; `CURRENT_PROJECT_STATUS.md` updated
if status changed.

_Prior status history: architecture validated + authoritative plan 2026-07-19
(`P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_PLAN.md`); implementation artifacts created (TEST-only)
2026-07-19; TEST-applied + verified + concurrency-proven 2026-07-19 — the basis for this
lock (see the P1b notes in the Crawler 16C–16H entry's approved-additive-extension log
above)._

---

## Reports v1 — Persisted read + guarded generation + PDF export (Stages 1–3)

**Status:** LOCKED (Reports v1 approved scope; deferred Reports features remain UNLOCKED)
**Locked on:** 2026-07-20
**Owner documentation:** `SEO_IMPLEMENTATION_STATUS.md` (§1 Reports rows + §7),
`SEO_DECISIONS.md` A9–A12, `SEO_CONTEXT_HANDOVER.md` §4

**Important:** this lock protects the validated behaviour/contracts of the Reports
v1 scope (Stage 1 persistence + read path; Stage 2 guarded generation; Stage 3
role-gated PDF export), TEST-verified on `Digi_SEO_Test`. It does **not** claim
CSV/history/scheduling/email/sharing/period-comparison exist — those are deferred
and remain UNLOCKED (see "Deferred scope"); their absence is not a defect.

### Locked scope (implemented + TEST-verified)
1. **Stage 1 — persistence + read path.** `public.seo_reports` (indexed scalar
   columns + version-tolerant `summary` jsonb; `UNIQUE(website_id, report_type,
   period_key)`; workspace/website-scoped RLS — member SELECT, owner/admin/
   team_member write). Frontend reads via `runWithServiceAdapter` (RLS SELECT),
   **no silent mock fallback** in Supabase mode; mock mode preserved.
2. **Stage 2 — guarded generation.** `SECURITY DEFINER` `seo_report_generate(
   p_website_id uuid, p_period_key text) RETURNS uuid` — authenticated-only (anon
   EXECUTE revoked); owner/admin/team_member (client/anon/nonmember/cross-tenant
   denied, no leak); server-derived workspace/period/url/actor; six live areas
   aggregated server-side (documented DB-native semantics + deterministic
   page-performance Branch 3); the 3 unavailable areas truthful via
   `data_provenance`; transaction-scoped `pg_advisory_xact_lock` + `INSERT … ON
   CONFLICT DO UPDATE` (one canonical row). Synchronous; no client-supplied metrics.
3. **Stage 3 — PDF export.** Read-only `STABLE SECURITY DEFINER`
   `seo_report_export_data(p_website_id uuid, p_period_key text) RETURNS SETOF
   seo_reports` — same role gate (client/anon/nonmember/cross-tenant denied, anon
   revoked), returns the stored row unchanged, **never regenerates**. Client-side
   `jsPDF` rendering (no BFF/edge function; `SEO_DECISIONS` A1/A12); unavailable
   areas print "Not connected"; CSV/email/share remain disabled.

### Protected contracts
- RPC names/params/returns/grants: `seo_report_generate(uuid,text)`,
  `seo_report_export_data(uuid,text)` (authenticated-only, anon denied); the
  `seo_reports` table shape + unique key + RLS; the advisory-lock + ON-CONFLICT
  idempotency; the aggregation semantics (`SEO_DECISIONS` A10/A11); the export
  role gate; the truthful `data_provenance`/"Not connected" behaviour; client-side
  PDF rendering (A12). No client-supplied report content.
- Applied migrations `20260720120035`–`20260720120038` are **immutable**.

### Locked files
- Migrations `supabase/migrations/20260720120035_seo_reports_foundation.sql`,
  `…120036_seo_report_generate.sql`, `…120037_seo_report_generate_revoke_anon.sql`,
  `…120038_seo_report_export_data.sql` (immutable).
- `supabase/test/seo_reports_read_path_verification.sql`,
  `seo_report_generate_verification.sql`, `seo_report_export_data_verification.sql`
  (+ rollbacks + the browser fixture) — baselines; must remain PASS + self-cleaning.
- `src/services/supabase/seoReportsSupabaseService.ts`, `src/services/reportService.ts`,
  `src/services/supabase/supabaseTypes.ts` (report RPC/table names),
  `src/types/report.ts`, `src/pages/seo/ReportsPage.tsx`, and
  `src/pages/seo/reports/{ReportExportActions,reportPdf,ReportHeader,ReportKeyStats,ReportSectionCard,ReportPeriodSelector}.tsx`.

### Verification evidence (2026-07-20)
SQL verification (all 3 scripts) ALL PASS; authenticated browser acceptance PASS;
PDF export + content/layout inspection PASS ("Not connected" ×3, footer/version/
metadata, no garbage tokens, no overflow); **true two-session held-transaction
advisory-lock concurrency PASS** (two independent `pg` connections on
`Digi_SEO_Test`: Session B blocked while A held the lock — `pg_locks` advisory
waiter; B waited ~2.66 s, finished 91 ms after A committed; both returned the same
UUID; exactly one canonical row; isolated disposable workspace/website/membership;
0 residue); `tsc`/`build` clean. Production untouched.

### Changes allowed / not allowed / evidence required
Same additive-extension + evidence + explicit-approval procedure as the Crawler
16C–16H entry. **Allowed** (separately approved, additive): proven bug fixes;
security fixes; additive extension points for the deferred features below —
additive migrations only, preserve every protected contract, re-run the three
Reports verifications (+ the two-session concurrency if the guard is touched),
dated owner-doc note. **Not allowed** (without unlock/approval): weaken the role
gates or anon-deny; remove/weaken the advisory lock or unique key; add a second
`seo_reports` write path bypassing the guard; change the aggregation semantics or
the export contract; trust client-supplied report content; edit applied migrations
`…120035`–`…120038`; refactor-for-style on locked behaviour.

### Deferred scope — remains UNLOCKED (out of scope; not defects)
CSV export; report history; scheduling; email delivery; public/secure sharing;
period comparison; server-side/edge PDF rendering; generation for the mock-only
source areas (competitor / roadmap / expert-support).

---

## Competitor Benchmarking — Persisted read + guarded generation (Stages 1–2)

**Status:** LOCKED (Competitor Benchmarking approved scope; deferred features remain UNLOCKED)
**Locked on:** 2026-07-24
**Owner documentation:** `SEO_IMPLEMENTATION_STATUS.md` (§1 Competitor rows),
`SEO_DECISIONS.md` A13/A15/A16, `SEO_CONTEXT_HANDOVER.md` §4,
`COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`

**Merged `main` checkpoint:** `a594d1dbd0f67f71b218132b848ce9678c3cad17`, comprising
implementation commits `2d5ff8966842ea14e2176eee1f060cfc92cbf102` (Stage 2A
backend) and `a594d1dbd0f67f71b218132b848ce9678c3cad17` (Stage 2B frontend
integration), fast-forwarded onto `main` from `feat/seo-competitor-generate-stage2a`.

**Important:** this lock protects the validated behaviour/contracts of the
Competitor Benchmarking scope (Stage 1 persisted read path; Stage 2A guarded
generation RPC; Stage 2B frontend integration), TEST-verified on `Digi_SEO_Test`
and authenticated-operator-accepted. It does **not** claim a real external
competitor-data provider (SEMrush/Ahrefs/GSC) is integrated — every score is a
local heuristic **estimate**; see "Protected contracts". Roadmap and expert-support
integration for this area, and any real-provider integration, remain deferred
and UNLOCKED (see "Deferred scope"); their absence is not a defect.

### Locked scope (implemented + TEST-verified + operator-accepted)
1. **Stage 1 — persisted read path.** `public.seo_competitors` (migration
   `20260720123000`; workspace/website-scoped RLS — member SELECT incl. client
   read-only, owner/admin/team_member write; `UNIQUE(website_id,
   normalized_competitor_url)`; `data_provenance` CHECK-constrained to
   `'estimated'` only). Frontend reads via `runWithServiceAdapter`, **no silent
   mock fallback** in Supabase mode; mock mode preserved.
2. **Stage 2A — guarded generation.** `SECURITY DEFINER`
   `seo_competitor_generate(p_website_id uuid) RETURNS integer` — `search_path
   =public`; `authenticated`-only (anon EXECUTE revoked up-front, no corrective
   follow-up needed); owner/admin/team_member or global admin (client/anon/
   non-member/cross-tenant denied with one non-leaking message; a missing
   website is indistinguishable from unauthorized). Accepts **only**
   `p_website_id` — workspace/actor/website-url, the competitor URL list
   (`seo_business_onboarding.competitors`), and the comparison score (latest
   completed `seo_audit_runs`) are all server-derived. Deterministic local
   heuristic (`35 + hash(url:dimension) % 55`, no random regenerate nudge —
   repeated generation is stable/idempotent); persists only
   `data_provenance='estimated'` + `generation_method='heuristic_v1'`
   (**never** SEMrush/Ahrefs/GSC/measured/observed/verified/live). Normalizes
   competitor URLs to the Stage 1 host contract; transaction-scoped
   `pg_advisory_xact_lock` keyed to (website, generation op); **replace-to-match**
   persistence (`INSERT … ON CONFLICT DO UPDATE` for the canonical set + `DELETE`
   of stale rows for that website only — other websites/workspaces untouched;
   an empty onboarding list is non-destructive and returns `0`).
3. **Stage 2B — frontend integration.** `generateSupabaseCompetitors(websiteId)`
   calls the Stage 2A RPC (only the website id) then re-reads the persisted
   canonical set through the Stage 1 read path — the heuristic is never
   reproduced client-side. `competitorService.generateCompetitorBenchmarkData`
   dispatches via `runWithServiceAdapter` (`fallbackToMockOnError: false`); the
   pre-existing mock generation is preserved verbatim, unchanged. Role-gated
   Generate/Refresh (`canGenerateCompetitorBenchmarks` +
   `COMPETITOR_GENERATE_ROLES = ['owner','admin','team_member']`) is a
   **presentation-only usability layer** — the RPC's own role gate remains the
   sole authoritative check.

### Protected contracts
- RPC name/params/returns/grants: `seo_competitor_generate(uuid) RETURNS integer`
  (`authenticated`-only, anon denied up-front); the `seo_competitors` table
  shape + unique key + RLS + the `data_provenance='estimated'`-only CHECK; the
  advisory-lock + replace-to-match persistence semantics; the deterministic
  heuristic formula and its stability (no random nudge); the role-gate wiring
  as a usability layer only (never the authoritative check). No client-supplied
  workspace, actor, scores, provenance, timestamps, or generation metadata.
- Applied migrations `20260720123000`, `20260724120040` are **immutable**.

### Locked files
- Migrations `supabase/migrations/20260720123000_seo_competitors.sql`,
  `…20260724120040_seo_competitor_generate.sql` (immutable).
- `supabase/test/seo_competitors_read_path_verification.sql`,
  `seo_competitor_generate_verification.sql` (+ rollbacks) — baselines; must
  remain PASS + self-cleaning.
- `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md` — live two-session
  concurrency evidence baseline.
- `src/services/supabase/seoCompetitorSupabaseService.ts`,
  `src/services/competitorService.ts`, `src/services/supabase/supabaseTypes.ts`
  (competitor RPC/table names), `src/types/competitor.ts`,
  `src/pages/seo/CompetitorAnalysisPage.tsx`, and
  `src/pages/seo/competitors/{CompetitorOverviewHeader,CompetitorCard,CompetitorGapSummary,BenchmarkComparisonSection}.tsx`.

### Verification evidence (2026-07-24)
Stage 1 + Stage 2A SQL verification (both scripts) ALL PASS, 0 residue; **true
two-session held-transaction advisory-lock concurrency PASS** (`Digi_SEO_Test`:
Session B directly observed `wait_event_type=Lock, wait_event=advisory` while
Session A held the lock via `pg_sleep(8)`; B unblocked cleanly on A's commit;
exactly one canonical row per competitor, no duplicates; replace-to-match
re-verified post-race; 0 fixture residue — full detail in
`COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`); vitest 33/33; `tsc`/`build`
clean. **Authenticated operator acceptance ALL PASS** on `Digi_SEO_Test` (real
TEST accounts, real browser sessions): owner/admin/team_member each generated
successfully (network-observed RPC call + canonical reload, repeated-refresh
stability, no duplicates, `data_provenance='estimated'` + `generation_method=
'heuristic_v1'` DB-confirmed); client denied in the UI (disabled control +
accurate role tooltip) and at the backend (direct RPC attempt → `P0001`
non-leaking denial); a reversible client-side-only simulated backend failure
showed an actionable error with no mock fallback and left persisted data
intact; desktop/mobile responsive and an unrelated-page regression check both
clean. No defects found. Production untouched throughout; the deferred
cross-project SSO migration `20260720121000` remained pending/unapplied
(`SEO_DECISIONS.md` A14) — unaffected by this work.

### Changes allowed / not allowed / evidence required
Same additive-extension + evidence + explicit-approval procedure as the Reports
v1 entry. **Allowed** (separately approved, additive): proven bug fixes;
security fixes; additive extension points for the deferred features below —
additive migrations only, preserve every protected contract, re-run the Stage
1/2A SQL verifications (+ the two-session concurrency if the advisory lock is
touched) and the frontend unit tests, dated owner-doc note. **Not allowed**
(without unlock/approval): weaken the role gates or the anon-deny grant;
remove/weaken the advisory lock or the unique key; add a second
`seo_competitors` write path bypassing the guard; relabel a persisted row away
from `data_provenance='estimated'`; trust client-supplied generation content;
edit applied migrations `20260720123000`/`20260724120040`; refactor-for-style
on locked behaviour.

### Deferred scope — remains UNLOCKED (out of scope; not defects)
Real external competitor-data provider integration (SEMrush/Ahrefs/GSC or
similar — any future integration must add a new allowed `data_provenance`
value via an additive migration, never relabel estimated data); scheduled/
automatic regeneration; competitor-count/plan-tier limits; CSV/export of
competitor data; historical trend tracking across generations.

---

## Recommendation Generation — Stage 1 backend only (guarded generation RPC)

**Status:** LOCKED (Stage 1 backend-only approved scope; Stage 2 frontend
integration remains UNLOCKED — not yet built)
**Locked on:** 2026-07-24
**Owner documentation:** `SEO_IMPLEMENTATION_STATUS.md` (§1 Recommendation
Generation Stage 1 row), `SEO_DECISIONS.md` A17 (+ three amendments),
`SEO_CONTEXT_HANDOVER.md` §4,
`SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md`,
`SEO_RECOMMENDATION_GENERATION_ARCHITECTURE.md`

**Merged `main` checkpoint:** `e7b1fbebfc9d99fd69bbaceb93d277b4bea36c42`,
comprising implementation commits
`808d54d457ad9be713440ce2513bd65d6a0f11ea` (Stage 1 backend: migration +
guarded RPC) and `e7b1fbebfc9d99fd69bbaceb93d277b4bea36c42` (this lock's own
documentation), fast-forwarded onto `main` from
`feat/seo-recommendation-generate-stage1` (`71ac8fd..e7b1fbe`, no merge
commit) and pushed to `origin/main`.

**Important:** unlike every other entry in this registry, this lock covers
**Stage 1 backend only** — additive schema plus one guarded generation RPC,
genuinely verified against a local, Docker-based Supabase/Postgres stack
(not `Digi_SEO_Test`, not production — an earlier out-of-sequence
`Digi_SEO_Test` application was fully rolled back before this lock; see
`SEO_DECISIONS.md` A17's amendments). **No frontend integration, no unit
tests, and no authenticated operator/browser acceptance exist for this
feature yet.** Stage 2 (frontend service wiring, role-gated "Generate
Recommendations" UI control, unit tests, operator acceptance) is explicitly
deferred and UNLOCKED — its absence is not a defect, it has simply not been
built. This is a narrower verification bar than every prior lock in this
registry (all of which included frontend integration and real authenticated
operator acceptance); do not assume this lock means the feature is reachable
from any UI today — it is not.

### Locked scope (implemented + locally verified)
1. **Additive schema.** `seo_recommendations.source_issue_fingerprint`
   (text, nullable) + `generation_method` (text, nullable); two partial
   unique indexes scoped `WHERE is_current` —
   `uq_seo_recommendations_issue_fingerprint (website_id,
   source_issue_fingerprint)` and `uq_seo_recommendations_onpage_area
   (website_id, area) WHERE issue_id IS NULL`.
2. **Guarded generation RPC.** `SECURITY DEFINER`
   `seo_recommendation_generate(p_website_id uuid) RETURNS SETOF
   seo_recommendations` — `search_path=public`; `authenticated`-only (anon
   + PUBLIC EXECUTE revoked up-front, no corrective follow-up). Accepts
   **only** `p_website_id` — workspace/actor/business-context fields are all
   server-derived from `seo_websites`. Authorizes owner/admin/team_member or
   global admin (client/anon/non-member/cross-tenant denied with one
   non-leaking message; a missing website is indistinguishable from
   unauthorized). Deterministic rule-based reproduction of the existing mock
   heuristic (`CATEGORY_TO_AREA`, `ACTION_TYPE_BY_FIX_OWNER`,
   `ON_PAGE_TEMPLATES`) — no AI/LLM, no new categories. Candidate issues
   limited to `status IN ('open','in_review')` from the latest completed
   audit run. Transaction-scoped `pg_advisory_xact_lock` keyed to (website,
   generation op). **First real consumer of the existing
   `is_current`/`superseded_by` versioning:** three-way replace-to-match
   (insert-new / no-write-if-unchanged / supersede-if-changed-and-untouched
   / leave-alone-if-human-acted / retire-if-resolved-and-untouched). Returns
   the canonical current recommendation set (`SETOF`, not a transient
   count).

### Protected contracts
- RPC name/params/returns/grants: `seo_recommendation_generate(uuid)
  RETURNS SETOF seo_recommendations` (`authenticated`-only, anon+PUBLIC
  denied up-front); the two new columns + two partial unique indexes on
  `seo_recommendations`; the advisory-lock key; the three-way
  replace-to-match semantics (especially the terminal-status-protection
  rule — a human-acted recommendation, `status` not in
  `suggested`/`needs_review`, is never silently superseded or retired); the
  mock-heuristic mapping tables reproduced server-side. No client-supplied
  workspace, actor, content, or provenance.
- Migration `20260724130000_seo_recommendation_generate.sql` is
  **immutable**. It has been verified **locally only** — see "Important"
  above; it has never been applied to `Digi_SEO_Test` or production (an
  earlier out-of-sequence `Digi_SEO_Test` application was fully rolled back;
  `SEO_DECISIONS.md` A17 amendments).

### Locked files
- Migration `supabase/migrations/20260724130000_seo_recommendation_generate.sql`
  (immutable).
- `supabase/test/seo_recommendation_generate_verification.sql` (+
  `..._rollback_TEST_ONLY.sql`) — baseline; must remain PASS + self-cleaning.
- `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md` — local +
  historical-TEST verification evidence baseline.

### Verification evidence (2026-07-24)
Full SQL verification suite PASS **twice**, against a genuine local
Docker-based Supabase/Postgres stack (isolation proven — private
Docker-bridge server address, `.env.local`'s `VITE_SUPABASE_URL` directly
confirmed to point at `Digi_SEO_Test`'s distinct project ref); every
NOTICE-level checkpoint confirmed (contract; full authz matrix incl.
no-leak; category/fix_owner mapping; eligibility; on-page interpolation;
RPC-return-equals-canonical-set; idempotency with provable no-write; the
full regeneration-safety matrix — supersede/no-write/retire/preserve for
both an issue-derived and an on-page row; dedup-index enforcement;
isolation; non-destructive no-audit case); 0 fixture residue, independently
reconfirmed both runs. **True two-session advisory-lock concurrency PASS**
against the local database: Session B directly observed
`wait_event_type=Lock, wait_event=advisory` at two poll points while
Session A held the lock via `pg_sleep(10)`; unblocked cleanly on A's
completion; post-race state = 8 current rows / 8 distinct identities / 0
duplicates. Full detail: `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md`
§6. **Historical, out-of-sequence `Digi_SEO_Test` verification** (SQL suite
+ concurrency proof, same evidence bar) also passed prior to being rolled
back — retained as corroborating historical evidence only, not the
acceptance basis (§1–§2 of the same document). **No frontend unit tests and
no authenticated operator/browser acceptance exist** — Stage 2 has not been
built (see "Important" above). Production untouched throughout; the
deferred cross-project SSO migration `20260720121000` remained
pending/unapplied on `Digi_SEO_Test` throughout, and was resolved locally
via a proven, reversible exclusion mechanism rather than being applied
(`SEO_LOCAL_DATABASE_SETUP.md`).

### Changes allowed / not allowed / evidence required
Same additive-extension + evidence + explicit-approval procedure as every
other entry in this registry. **Allowed** (separately approved, additive):
Stage 2 frontend integration (see "Deferred scope" below); proven bug
fixes; security fixes — additive migrations only, preserve every protected
contract, re-run the SQL verification (+ the two-session concurrency if the
advisory lock is touched), dated owner-doc note. **Not allowed** (without
unlock/approval): weaken the role gate or the anon/PUBLIC-deny grants;
remove/weaken the advisory lock or either unique index; add a second
`seo_recommendations` generation write path bypassing the guard; change the
terminal-status-protection rule (silently overwriting a human-acted
recommendation); trust client-supplied generation content; edit the applied
migration `20260724130000`; refactor-for-style on locked behaviour; apply
this migration to `Digi_SEO_Test` or production without an approval
explicitly recorded in the controlling ChatGPT instruction trail
(`SEO_DECISIONS.md` A17 amendments).

### Deferred scope — remains UNLOCKED (out of scope; not defects)
**Stage 2 — frontend integration** (service wiring, role-gated "Generate
Recommendations" UI control, unit tests, authenticated operator acceptance)
— not started; see `SEO_RECOMMENDATION_GENERATION_ARCHITECTURE.md` §9–§10
for its planned shape. Any future `Digi_SEO_Test`/production application of
this migration. Roadmap Backend integration (Roadmap Month 2 generation
depends on real `seo_recommendations` rows existing, which requires Stage
2's UI to actually be used — see `SEO_ROADMAP_BACKEND_ARCHITECTURE.md`
§4.3).

_Note (2026-07-24, additive — this entry's own text above is retained
unedited): Stage 2 frontend integration described as "not started" above
has since been built, accepted, and separately locked — see the
"Recommendation Generation — Stage 2 frontend integration" entry below.
This Stage 1 entry's own locked scope, protected contracts, and evidence
remain exactly as written; only the "Stage 2 not started" framing is now a
historical snapshot, current status is in the Stage 2 entry._

---

## Recommendation Generation — Stage 2 frontend integration

**Status:** LOCKED (Stage 2 frontend-integration approved scope; deferred
features below remain UNLOCKED)
**Locked on:** 2026-07-24
**Owner documentation:** `SEO_IMPLEMENTATION_STATUS.md` (§1 Recommendation
Generation Stage 2 row), `SEO_DECISIONS.md` A18 (+ amendments),
`SEO_CONTEXT_HANDOVER.md` §4,
`SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`,
`SEO_LOCAL_DATABASE_SETUP.md`

**Implementation commit:** `36d32af2a3841267d19a7911ad7e693e6e10f81d`
(`feat(seo): integrate recommendation generation workflow`), on
`feat/seo-recommendation-generate-stage2` (based on `origin/main`
`c1de7fe5400d88189d1b826d884ef31779ab2290`, the same base as the locked
Stage 1 backend). **This branch is committed locally only — it has not
been pushed to `origin` and has not been merged to `main`.** This lock
entry reflects local acceptance; push/merge is a separate, later step.

**Important:** this lock protects the validated behaviour/contracts of the
Stage 2 frontend-integration scope, genuinely verified against a local,
Docker-based Supabase stack (not `Digi_SEO_Test`, not production) — real
fixtures, real authenticated sign-in, a deterministic live loading-state
proof, and a live no-eligible-findings proof, not code-review-only claims.
It does **not** claim Recommendation Generation is deployed to
`Digi_SEO_Test` or production, that Roadmap Backend integration exists, or
that automatic/scheduled publishing exists — see "Deferred scope"; those
exclusions are not defects.

### Locked scope (implemented + locally verified)
1. **Typed RPC service integration.**
   `seoRecommendationSupabaseService.generateSupabaseRecommendations(websiteId)`
   calls the locked Stage 1 RPC (`seo_recommendation_generate`) with
   **only** `p_website_id`, validates the response is an array, then
   **re-reads the canonical current set** through the pre-existing
   `fetchSupabaseRecommendations` read path rather than trusting the RPC's
   own returned rows — the backend's mapping/replace-to-match logic is
   never reproduced client-side.
2. **Service-adapter dispatch, no Supabase-to-mock fallback.**
   `recommendationService.generateRecommendations(website)` dispatches via
   `runWithServiceAdapter` with `fallbackToMockOnError:false` — a Supabase
   generation error is never masked by mock data. The pre-existing mock
   generator is reused unchanged (wrapped to self-derive the latest
   completed mock audit's issues, matching the established
   `generate<X>(website)` dispatch signature used by Competitor/Reports
   Stage 2).
3. **Role-gated Technical Audit UI.**
   `RECOMMENDATION_GENERATE_ROLES = ['owner','admin','team_member']` +
   `canGenerateRecommendations(role, supabaseMode)` — a **presentation-only
   usability layer** (mock mode always enabled; Supabase mode queries the
   real `seo_workspace_members.seo_role` via `getCurrentSeoRole`); the
   RPC's own server-side gate remains the sole authoritative check,
   re-confirmed via a direct in-page bypass fetch using a denied role's own
   session token. `RecommendationGenerationPanel.tsx`, rendered on
   `WebsiteAuditPage.tsx` only in Supabase mode on a completed audit.
4. **Loading, success, error, and empty-findings behaviour.** Button text
   `"Generating..."` + `disabled`/`aria-disabled` while the mutation is
   pending; a live current-count badge + "Review in Approval Queue" link on
   success; a generic destructive-text error message (never the raw
   backend error) on failure; an explicit no-eligible-findings note when
   the audit has zero open issues (generation still refreshes the 7 fixed
   on-page templates in that case).
5. **Duplicate-submit protection.** The same button that triggers the
   mutation is disabled for its duration
   (`disabled={isGenerating || !generatePermitted}`) — proven live via a
   deterministic in-browser fetch gate: a second click attempted while a
   request was held open produced zero additional RPC calls.
6. **Query invalidation and canonical refresh.** `onSuccess` invalidates
   `["seo-recommendations", websiteId]`, `["seo-onpage-recommendations",
   websiteId]`, and `["seo-approval-queue", websiteId]` — the UI reflects
   the canonical persisted state with no manual reload.
7. **Approval Queue downstream compatibility.** `ApprovalQueuePage.tsx`,
   `approvalService.ts`, and `seoApprovalSupabaseService.ts` were **not
   modified** — their pre-existing, already-idempotent
   `ensureApprovalQueueGenerated` pipeline consumes real
   `seo_recommendations` rows automatically once Stage 2 generation
   produces them.
8. **Stage 2 service tests (15 new, `.ts`-only — this repo's Vitest config
   does not collect `.tsx` component tests, a pre-existing, unrelated
   gap):** `seoRecommendationSupabaseService.test.ts` (6 — exact RPC
   args, error-no-fallback, response-type validation, UUID validation,
   read-back-not-raw-payload proof, empty-array-is-valid) and
   `recommendationService.test.ts` (9 — full role matrix, Supabase-branch
   dispatch args, error propagation unmasked, mock-branch still
   functions). Full suite 48/48 pass (was 33/33); `tsc`/`build` clean.
9. **Local browser/operator acceptance evidence.** Real authenticated
   sign-in (owner + client) against the real application; owner: 0→9→9
   recommendations across generate/repeat-generate with 0 duplicates
   (DB-confirmed), an operator-approved recommendation surviving a
   subsequent regeneration untouched; client: control disabled with the
   correct tooltip, 0 RPC calls for the disabled control, a direct backend
   bypass attempt denied with the RPC's own non-leaking message; a
   deterministic live loading-state proof (gate-based, not timing-based);
   a live no-eligible-findings proof (a disposable second website with a
   completed, issue-free audit correctly generating exactly the 7 on-page
   templates, 0 issue-derived rows, 0 auto-created approval items).
10. **Local Supabase privilege-bootstrap support and documentation.**
    `supabase/test/local_supabase_privilege_bootstrap.sql` — an idempotent,
    RLS-preserving script (never disables or bypasses RLS; only restores
    the standard `anon`/`authenticated` table-DML grant convention that a
    hosted Supabase project provisions automatically and that the local
    CLI's `db reset` destroys) — and `SEO_LOCAL_DATABASE_SETUP.md`, the
    reproducible end-to-end local setup procedure. Both are local-only:
    the script lives under `supabase/test/`, not `supabase/migrations/`,
    carries no timestamp-prefix filename, and cannot be auto-applied by
    `supabase db push`/`db reset` as a migration.

### Existing Stage 1 relationship
- The **Stage 1 backend lock** ("Recommendation Generation — Stage 1
  backend only", locked 2026-07-24, above) **remains separate and
  unchanged** by this entry — its locked scope, protected contracts,
  locked files, and evidence are untouched.
- Stage 2 **consumes** the locked Stage 1 RPC exactly as designed (only
  `p_website_id` sent; canonical set re-read afterward) — it does not call
  any other write path into `seo_recommendations`.
- Stage 2 **does not alter** Stage 1's authorization logic (role gate,
  anon/PUBLIC deny), its mapping tables (`CATEGORY_TO_AREA`/
  `ACTION_TYPE_BY_FIX_OWNER`/`ON_PAGE_TEMPLATES`), or its
  replace-to-match/versioning behaviour in any way — no Stage 1 file is
  part of this Stage 2 commit or lock.

### Protected contracts
- Frontend function signatures: `generateSupabaseRecommendations(websiteId:
  string): Promise<SeoRecommendation[]>`; `generateRecommendations(website:
  SeoWebsite): Promise<SeoRecommendation[]>`; `canGenerateRecommendations(role:
  SeoUserRole | null, supabaseMode: boolean): boolean`;
  `RECOMMENDATION_GENERATE_ROLES`.
- `RecommendationGenerationPanel` prop contract (`recommendationCount,
  issueCount, isGenerating, isError, generatePermitted, deniedReason,
  onGenerate`) and its rendered states (idle/generating/error/
  no-eligible-findings/success).
- React Query keys: `["seo-recommendations", websiteId]`,
  `["seo-onpage-recommendations", websiteId]`,
  `["seo-approval-queue", websiteId]`, `["seo-current-role", workspaceId]`.
- The "RPC then re-read the canonical set" service shape — never trust the
  RPC's own returned rows as the UI's source of truth.
- `fallbackToMockOnError:false` on the Supabase generation dispatch — never
  silently substitute mock data for a real Supabase error.
- The local privilege-bootstrap script's local-only, idempotent, RLS-
  preserving contract.

### Locked files
- `src/services/supabase/seoRecommendationSupabaseService.ts` (the
  `generateSupabaseRecommendations` addition; the pre-existing read
  functions were already unlocked/unowned by any prior lock).
- `src/services/recommendationService.ts` (the `generateRecommendations`,
  `canGenerateRecommendations`, `RECOMMENDATION_GENERATE_ROLES` additions).
- `src/pages/seo/audit/RecommendationGenerationPanel.tsx` (new file).
- The Stage 2 integration block in `src/pages/seo/WebsiteAuditPage.tsx`
  (the `currentSeoRole`/`recommendations` queries,
  `generateRecommendationsMutation`, `invalidateRecommendationData`, and
  the `<RecommendationGenerationPanel>` render — the pre-existing
  `<CrawlPanel>` integration and the rest of this file remain governed by
  the Crawler 16C–16H lock, unchanged by this entry).
- `src/services/supabase/supabaseTypes.ts` (the
  `SEO_RPCS.recommendationGenerate` constant).
- `src/services/recommendationService.test.ts`,
  `src/services/supabase/seoRecommendationSupabaseService.test.ts` —
  baselines; must remain PASS.
- `supabase/test/local_supabase_privilege_bootstrap.sql`,
  `SEO_LOCAL_DATABASE_SETUP.md` — baselines for local verification;
  must remain idempotent, RLS-preserving, and local-only.

### Verification evidence (2026-07-24)
Full acceptance review against the actual final source (every changed/new
file read in full) found no material defect. `tsc --noEmit` clean; focused
Stage 2 tests 15/15 pass; full suite 48/48 pass, 0 regressions; `npm run
build` clean (pre-existing chunk-size advisory only); secret scan 0 real
matches; migration-directory integrity confirmed (zero diff in
`supabase/migrations/`); full diff review confirmed only intentional
changes. Local database verification against a genuine local Docker-based
Supabase stack: a local-Supabase-CLI-only base-table-grant gap
(`authenticated`/`anon` missing `SELECT/INSERT/UPDATE/DELETE` after a
`db reset`, since the local CLI's schema-drop destroys a bootstrap a
hosted project never loses) was reproduced from a genuinely clean reset
(raw anon-key REST request returning `401`/`42501` with PostgREST's own
`GRANT` hint) and fixed with the idempotent, RLS-preserving bootstrap
script referenced above — RLS independently re-confirmed enabled on all 53
public tables both before and after the fix; **no change to the locked
Stage 1 migration/RPC was needed.** Real fixtures proved idempotent
generation (repeat clicks, 0 duplicates), operator-touched-row
preservation across regeneration, client denial at both the UI and backend
layers (direct bypass attempt), a deterministic live loading-state proof,
and a live no-eligible-findings proof (7 on-page-only rows, 0
issue-derived, 0 auto-created approval items). Full detail:
`SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`.

### Changes allowed / not allowed / evidence required
Same additive-extension + evidence + explicit-approval procedure as every
other entry in this registry. **Allowed** (separately approved, additive):
proven bug fixes; security fixes; additive UI/service extensions for the
deferred features below — preserve every protected contract above, re-run
the focused Stage 2 tests + full suite + `tsc`/build, dated owner-doc note.
**Not allowed** (without unlock/approval): call any RPC other than
`seo_recommendation_generate` to write `seo_recommendations`; send any
client-supplied field beyond `p_website_id`; trust the RPC's own returned
rows instead of re-reading the canonical set; add a silent mock fallback
on a Supabase error; weaken or remove the duplicate-submit guard; change
the role-gate roles without a corresponding, separately-approved Stage 1
RPC change; modify `ApprovalQueuePage.tsx`/`approvalService.ts`/
`seoApprovalSupabaseService.ts` under this lock (they are unmodified and
not owned by it); weaken the local privilege-bootstrap script's RLS
preservation or grant scope; place the bootstrap script under
`supabase/migrations/` or give it a timestamp-prefix filename; edit the
locked Stage 1 migration or RPC.

### Deferred scope — remains UNLOCKED (out of scope; not defects)
Roadmap Backend (Roadmap Month 2 generation depends on real
`seo_recommendations` rows existing, which Stage 2 now makes possible, but
the Roadmap Backend integration itself has not been built — see
`SEO_ROADMAP_BACKEND_ARCHITECTURE.md`); Roadmap frontend; automatic/
scheduled recommendation publishing (generation never auto-publishes or
auto-approves — every generated row is `suggested` and requires a separate
Approval Queue action); future recommendation-editing features; future
role-model changes; future audit-generation behaviour changes; production
rollout; `Digi_SEO_Test` rollout (this feature has never been applied to
either). The Stage 2 branch itself is **committed locally but not yet
pushed to `origin` or merged to `main`** — push/merge is a separate,
later, explicitly-approved step.

### Evidence required before modification (unlock / additive-extension procedure)
1. Reproduction steps (for a bug fix) or the additive feature spec.
2. Expected behaviour. 3. Actual behaviour (bug) or the extension's contract.
4. Evidence (screenshot, console error, failing test, DB result, or log).
5. Root-cause analysis (bug) or additive-only design confirmation.
6. Explicit human approval to modify the locked module.
7. Confirmation the change is additive and preserves every protected
   contract above, and does not touch the separate Stage 1 lock.

### Required after an approved change
- Focused Stage 2 tests + full `vitest run` + `tsc`/`build` pass.
- If the local privilege-bootstrap script is touched: re-run it against a
  genuinely clean `db reset` and confirm its own verification block still
  passes (grants restored, RLS unchanged).
- Owner documentation receives a dated note.
- `SEO_IMPLEMENTATION_STATUS.md` updated if status changed.

_Prior status history: implemented + locally verified, pending acceptance
review 2026-07-24 (`SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`,
initial version); two evidence gaps (privilege-bootstrap clean-reset
reproduction, live loading/no-eligible-findings proof) closed same day in a
follow-up session with no implementation-code change; formal acceptance
review, commit
(`36d32af2a3841267d19a7911ad7e693e6e10f81d`), and this lock all completed
2026-07-24 — the basis for this entry. **Not pushed, not merged to
`main`.**_

### Reconciliation note (2026-09-19, additive — the entry above is unedited)

_The Stage 2 entry above is a historical lock record, and its wording that
the branch is "not pushed / not merged to `main`" was true on 2026-07-24 and
is deliberately left as written. **Current state:** Recommendation Generation
Stage 2 was subsequently pushed and fast-forwarded into canonical `main` on
**2026-09-19**. `main` moved `c1de7fe5400d88189d1b826d884ef31779ab2290` →
`9cb3676e52235a2012a0435ce568c8faab4c4347` as a normal fast-forward (no force,
no merge commit), adding exactly two commits: `36d32af` (the implementation
commit named above) and `9cb3676` (this lock's own documentation commit).
The locked scope, protected contracts, locked files, and evidence bar above
are unchanged by the merge; the Stage 1 backend lock entry is likewise
unchanged._

_`origin/release` (`c9d840b7a1b26ff473408e1ccde2b90d52f32966`) had earlier
received the same Stage 2 work through a merge commit (PR #1). That merge
commit is **not** part of `main`. At `9cb3676` the `release` tree and the `main`
tree were identical (`912308d5f3b8f7423014da4b9ff637f00626a0f7`); after the
2026-09-19 documentation-only integration `main` differs from `release` only by
documentation files. `release` was not modified by this reconciliation._

_**Deployment caveat (as of the 2026-09-19 audit, before the promotion that day; superseded):** the Stage 2 frontend calls
`seo_recommendation_generate`, whose migration (`20260724130000_seo_recommendation_generate.sql`)
was then not recorded on `Digi_SEO_Test` (rolled back 2026-07-24)._

_**TEST promotion note (2026-09-19, additive):** migration `20260724130000` was promoted to
`Digi_SEO_Test` and verified on 2026-09-19 (targeted application, history repair recording only that version,
backend verification script and two session concurrency proof passed with 8 current rows, 8
distinct identities and 0 duplicates, zero residue, the 8 legacy rows unchanged, local regression
passed, implementation unchanged). TEST end to end backend readiness is confirmed; optional live
frontend write verification was not performed. Locked scope and protected contracts are
unchanged. Historical statements in the Stage 1 and Stage 2 entries above (for example that the
SSO migration "remained pending/unapplied") were accurate when written and are preserved; SSO
`20260720121000` is physically present on TEST but unrecorded in migration history. See
`SEO_CONTEXT_HANDOVER.md` §0 for the current state._

---

## Other modules marked locked in `PROJECT_BOOTSTRAP.md`

`PROJECT_BOOTSTRAP.md`'s Module Map currently lists the following as locked
based on having passed all nine Module Completion Rules, but they **do not yet
have a formal per-file entry in this registry** — treat them as locked under
the general rule in `PROJECT_BOOTSTRAP.md` (no changes without a proven
defect + explicit approval), but the specific locked-file list, allowed/
not-allowed changes, and evidence bar have not been formalized here yet. Add an
entry (using the template below) the next time one of these is touched or
reviewed, rather than inferring its file list from memory:

- Website Setup + Business Onboarding
- Technical Audit + Recommendations
- Approval Queue
- Content Studio
- Dashboard + Admin Preview
- Decline Diagnosis Engine

---

## Template for a new entry

Copy this structure when a module locks or its lock status changes:

```markdown
## <Module name>

**Status:** LOCKED | NOT LOCKED
**Locked on:** <YYYY-MM-DD>              (omit if NOT LOCKED)
**Owner documentation:** <file.md>       (omit if NOT LOCKED)
**Reason:** <why not locked yet>         (omit if LOCKED)

### Locked files
- <path>
- ...

### Changes allowed
- Proven bug fixes
- Security fixes
- Explicitly approved product enhancements
- Required compatibility changes caused by an approved shared dependency change

### Not allowed
- Refactoring for style
- Renaming
- Moving files
- Changing public service signatures
- Replacing the adapter pattern
- Modifying mock behavior
- Changing fallback behavior without a reproduced defect

### Evidence required before modification
1. Reproduction steps
2. Expected behavior
3. Actual behavior
4. Evidence such as screenshot, console error, failing test, database result, or log
5. Root-cause analysis, or a narrowly scoped investigation task
6. Explicit human approval to modify the locked module

### Required after an approved change
- Relevant tests must pass
- Module regression checklist must pass
- Owner documentation must receive a dated fix note
- CURRENT_PROJECT_STATUS.md must be updated if status changed
```
