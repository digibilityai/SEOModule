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
