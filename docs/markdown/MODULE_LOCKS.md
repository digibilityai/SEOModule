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
