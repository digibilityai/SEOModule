# Phase 16H / Crawler 1F — Authenticated Crawl Request, Status, Freshness & Published-Result UI

**Status: `FULLY ACCEPTED ON TEST — PRODUCTION READINESS NOT STARTED` (2026-07-15).**
Implementation **complete**; automated verification **complete**; operator
acceptance **complete** (all 7 scenarios PASS; Scenario 7 accepted with three
low-risk, documentation-only evidence-capture notes — see §10). Confirmed:
temporary Scenario 6 objects removed; **no recommendation generation**; **no
audit-score generation**; previous published results preserved after
failed/cancelled attempts; Page Inventory preservation confirmed; production
**untouched**. This acceptance is scoped to the **TEST** project (`Digi_SEO_Test`)
— the crawler is **not deployed / not customer-operational**, and
**production-readiness planning has not started**. No implementation defect found;
no code change required.**
A customer-facing crawl workflow on the existing Audit surface: an authorized user
can request an audit-backed crawl (receiving both ids directly via
`seo_crawl_request_audit`), watch the lifecycle, see safe progress + freshness,
cancel when legal, and open the published Audit + Page Inventory results — all
against Supabase as the single authoritative source. **No new backend, no polling
source other than Supabase, no DB change, no recommendation write, and production
untouched.** During Scenario 1 operator acceptance, one reproduced refresh race was
fixed in the locked Page Performance Tracker after explicit human approval; the
change was limited to query/fallback timing in
`src/pages/seo/PagePerformancePage.tsx`. **Date:** 2026-07-14.

## 1. Scope & exclusions
**In:** frontend crawl service/hooks/components + integration into `/seo/audit`;
role-gated Start Crawl with explicit confirmation; customer-safe status model +
terminal-aware polling; honest freshness; cancellation UI; partial-result
handling; published-result links; mock-mode preview; operator acceptance docs.
**Out (unchanged, deferred):** worker production deployment; scheduled/auto
recrawl; customer retry RPC; recommendations; AI explanations; audit scoring;
GSC/GA4/AI-visibility; subscription/usage enforcement; new issue rules or
severity/category mapping changes; Page Performance writes; Stage 6 changes;
parent SSO; production migration/deploy; visual redesigns.

## 2. Customer journey
Login → select active website → `/seo/audit` → **Start crawl** (confirm) →
`seo_crawl_request_audit` returns `(audit_run_id, crawl_job_id, job_status)` →
UI renders the queued job → polls Supabase for lifecycle → shows progress + safe
events + freshness → cancel while legal → worker processes → publishing completes
transactionally → **View audit results** / **Open Page Inventory** → refresh
persists. The UI **never queries for "the latest audit run"** after requesting —
the job's explicit `audit_run_id` association is used.

## 3. Role matrix (frontend affordance; RPC + RLS authoritative)
| Role | Request | View status | Cancel | View results |
|---|---|---|---|---|
| owner / admin / team_member | Yes | Yes | Yes | Yes |
| client | No (disabled + role tooltip; no RPC) | Yes | No | Yes |
| global_admin | Per RPC capability | Yes | Per RPC | Yes |
| non-member / anonymous | No (route guard) | No | No | No |
Gate roles = `CRAWL_REQUEST_ROLES = [owner, admin, team_member]`, read via the
existing RLS-backed `getCurrentSeoRole(workspaceId)`; gating is active only in
Supabase mode (mock has no real role, matching Stage 6 UX).

## 4. UI implementation
- **Service dispatcher** `crawlService.ts` (`runWithServiceAdapter`, `fallbackToMockOnError:false` — Supabase errors surface, never masked with mock success).
- **Supabase impl** `seoCrawlSupabaseService.ts` — `requestAuditCrawl` (RPC), `fetchLatestCrawl` (customer-safe columns only — **no** lease token/worker id/correlation id/config), `fetchCrawlPublication`, `cancelCrawl` (RPC). No direct crawler-table writes.
- **Mock** `crawlMockData.ts` — deterministic, clearly labelled preview; no Supabase call.
- **Hooks** `useWebsiteCrawl.ts` — `useWebsiteCrawlStatus` (terminal-aware polling), `useCrawlPublication`, `useCrawlRequestPermission` (role gate), `useRequestWebsiteCrawl`, `useCancelWebsiteCrawl`. Query keys are user + website scoped; SessionSync clears cache on user change.
- **Components** `audit/crawl/` — `CrawlPanel` (orchestrator + mock banner + empty/error states + publish invalidation), `StartCrawlControl` (role gate + two-step accessible confirm + double-submit prevention + active-job disable), `CrawlStatusCard` (safe fields + freshness + cancel + result links), `CrawlStatusBadge` (dot + label; status never colour-only).
- **Integration:** `WebsiteAuditPage.tsx` renders `<CrawlPanel>` above an `#audit-results` anchor; no locked file touched. Pure helpers in `lib/crawlStatus.ts`.

## 5. Status & freshness
Statuses mapped to customer labels: Queued / Preparing / Crawling / Waiting to
retry / Cancelling / Completed / Partially completed / Failed / Cancelled.
**Progress source = Supabase only** (TanStack Query polling at 4s while active;
stops at terminal via `refetchInterval → false`; pauses on hidden tab via default
`refetchIntervalInBackground:false`; reconciles on refresh). No local fake
progress, no dual polling. On a published terminal state the panel invalidates the
existing Audit + Page-Inventory queries once. **Freshness** is derived only from
real timestamps (requested/started/finished/heartbeat/published) — never the
browser clock; missing counters are omitted, not fabricated.

## 6. Cancellation & partial outcomes
Cancel uses `seo_crawl_cancel` and appears only in `{queued, claimed, running,
retry_wait}` (its legal states); queued/retry_wait → immediate Cancelled,
claimed/running → honest Cancelling (`cancellation_requested`) until the worker
acknowledges → final Cancelled. Idempotent; double-click disabled; never a direct
status update; clients never see an enabled cancel. **Partial completion** renders
"Partially completed" with an explanation, keeps usable Audit/Page-Inventory
links, and never represents omitted pages as removed.

## 7. Published results
Reuses the **existing** Audit + Page Inventory (`/seo/page-performance`) surfaces
and services — the customer pages read the product tables, not crawler-domain
tables. Site-level issues already render through the existing Audit service
(`affected_page_url` = website URL, `issue_scope='site'`; no fake page). No
existing UI assumption blocked a legitimate site-level issue, so **no display fix
was required**.

## 8. Mock mode
Permanent mock mode preserved: no session required, no real crawl RPC, a
clearly-labelled deterministic **Preview** progression, no TEST writes. Existing
Off-Page + AI Visibility mock behaviour untouched. The mock UI needs no worker.

## 9. Tests
- **Static:** frontend `tsc --noEmit -p tsconfig.app.json` clean; `npm run build` OK. Worker `tsc` clean; **worker tests 47/47**; `npm audit` 0 vulns.
- **SQL regression:** Phase 16C / 16D / 16E / 16F / 16G verifications all **ALL PASS** (no residual fixtures; seed Page-Inventory/Audit 7/7; recommendations + Page-Performance unchanged).
- **Frontend unit tests:** the repo has **no test framework** (none in `package.json`); a large framework was intentionally not introduced. Logic was instead isolated into pure, review-verifiable helpers (`lib/crawlStatus.ts`) covering status labels/tone, terminal + cancellable predicates, role gate, and freshness formatting.
- **Browser validation:** deferred to operator (see below) — the live customer-login flow needs TEST-user credentials and a running Supabase-mode session + worker; the dev port was in use during implementation.

## 10. Operator acceptance
`OPERATOR_USER_ACCEPTANCE_TEST_GUIDE.md` (environment startup, secret-safe worker
one-shot command, roles-not-passwords, 7 scenarios, evidence template) +
`OPERATOR_TEST_RESULTS.md` (per-scenario results). Current state:
**`OPERATOR-ACCEPTED — COMPLETE WITH ADMINISTRATIVE NOTES`.**

**Operator progress — 2026-07-14:** Scenario 1 (owner complete journey) **PASS**
after one approved Page Performance refresh-race fix. Crawl completion, Audit
publishing, Page Inventory publishing, freshness timestamps, no-recommendation
behaviour, navigation persistence and hard-refresh persistence were manually
verified.

**Operator acceptance — 2026-07-15 (all scenarios PASS):**
- **Scenarios 2–5 PASS** (operator, browser): team-member request + queued cancellation (2); client read-only + prior published-result visibility, after the approved Page-Performance fix (3); active cancellation + worker acknowledgement (4); partial result + inventory preservation (5).
- **Scenario 6 summary — 6A/6B/6C PASS** (controlled DB-level lifecycle proof, real one-shot worker + a temporary job-scoped fault trigger removed after each): 6A retryable persistence failure → `retry_wait` (audit stays running, +30 s, customer-safe error, 0 publish); 6B recovery on attempt 2 → `completed` + exactly one publication, audit `completed`, user-owned Page-Inventory fields preserved, no recommendation/score/Page-Performance write; 6C max-attempts (3) exhausted → terminal `failed` + linked audit `failed` (2 `retry_scheduled` + 1 `failed` event), prior completed audits + Page Inventory preserved. No source/migration change; all temporary objects removed and verified absent.
- **Scenario 7 summary — PASS with administrative notes** (owner User A + client User B): active crawl restored from Supabase after hard refresh; sign-out redirect + protected-content removal; legal UI cancellation → `Cancelled`; cancelled terminal restored after refresh; **client** login → published Audit/Page-Inventory read-only, Start crawl **disabled**, no internal worker data. DB correlation: Scenario-7 crawl `2e5c10f2…` = `cancelled`, linked audit `5e2998ab…` = `failed`, single-active invariant intact, prior completed audits/Page-Inventory preserved, worker RPCs service-role-only. **Administrative notes (documentation only, no security concern, no code change):** the Start-crawl tooltip screenshot, a hydration-flash recording, and a timed polling-stop network window were observed but not saved as artifacts; all three are supported by confirmed code paths (`SessionSync` cache clear, `StartCrawlControl` role gate, `refetchInterval → false` at terminal).

**Overall acceptance recommendation:** Phase 16H customer-facing crawl UI is **FULLY ACCEPTED ON TEST — PRODUCTION READINESS NOT STARTED**: implementation + automated verification + operator acceptance all complete; no implementation defect; no code change required. The three un-saved Scenario 7 artifacts are optional follow-up captures and do not gate acceptance. The one non-blocking data-cleanliness observation (a terminal crawl retains prior retry error fields; not customer-visible for a `completed` job) is recorded as a backlog item, out of this phase's scope. **Not** in this acceptance: production deployment, domain-ownership verification, usage/subscription enforcement, live public-domain crawling — these are the **production-readiness planning** milestone (next). The standalone SEO module remains independent of the Visibility module; the wider SEO project is **not** production-ready and the future wider-Digibility BFF integration remains deferred.

## 11. Security & permissions
RLS + the guarded RPCs remain authoritative; the frontend gate is an accessible
affordance only. Verified (grep + review): no service-role key / lease token /
worker id / correlation id / raw config in frontend crawl code; **no "latest audit
run" query** (only negating comments); no direct crawler-table writes; no
recommendation / Page-Performance writes; no worker command string in the UI; no
fake success after a failed RPC (`fallbackToMockOnError:false`); user-scoped query
keys + SessionSync prevent cross-user cache leakage.

## 12. Backward compatibility
Auth + route protection, Phase 16C–16G contracts, existing Audit/Page-Inventory
service signatures and data contracts, roles/RLS, mock mode, and Stage 6 behaviour
remain preserved. No DB/migration change occurred. During operator Scenario 1, the
locked Page Performance page received one explicitly approved, backward-compatible
bug fix limited to waiting for completed onboarding and a completed current-website
page fetch before running its existing cross-workspace fallback.

## 13. Files changed
- **New (frontend):** `src/types/crawl.ts`, `src/lib/crawlStatus.ts`, `src/services/crawlService.ts`, `src/services/supabase/seoCrawlSupabaseService.ts`, `src/mocks/crawlMockData.ts`, `src/hooks/useWebsiteCrawl.ts`, `src/pages/seo/audit/crawl/{CrawlPanel,StartCrawlControl,CrawlStatusCard,CrawlStatusBadge}.tsx`.
- **Edited:** `src/pages/seo/WebsiteAuditPage.tsx` (render `<CrawlPanel>` + anchor).
- **Approved operator-found bug fix:** `src/pages/seo/PagePerformancePage.tsx`
  (wait for completed onboarding and a completed current-website page query before
  running the existing cross-workspace fallback).
- **Docs:** this file, `OPERATOR_USER_ACCEPTANCE_TEST_GUIDE.md`, `OPERATOR_TEST_RESULTS.md`, + updates to plan / 1E / ADR / status / MVP / wiring / index.
- **No DB migration.** The locked Page Performance file changed only under the
  proven-defect + explicit-approval procedure in `MODULE_LOCKS.md`.
  `supabaseTypes.ts` already carried the needed constants (Phase 16G).

## 14. Rollback
Frontend: delete `src/pages/seo/audit/crawl/*`, `src/hooks/useWebsiteCrawl.ts`,
`src/services/crawlService.ts`, `src/services/supabase/seoCrawlSupabaseService.ts`,
`src/mocks/crawlMockData.ts`, `src/lib/crawlStatus.ts`, `src/types/crawl.ts`; revert
the 2-line `WebsiteAuditPage.tsx` integration. Auth + Phase 16C–16G preserved.
Database: **none** (no migration). Docs: revert Phase 1F references. TEST data:
remove only tagged Phase 1F fixtures; preserve seed/manual + Phase 15 evidence;
never access production.

## 15. Known limitations
Worker not persistently deployed (a crawl stays honestly Queued until an operator
runs the one-shot command; the customer UI exposes no worker command); no customer
retry button (automatic retry only); no recommendations; no subscription
enforcement; no scheduled/auto recrawl. Scenario 1 browser acceptance passed;
Scenarios 2–7 remain operator-pending.

## 16. Next milestone
`Production crawler deployment, ownership verification and usage-limit enforcement`
— not started.
