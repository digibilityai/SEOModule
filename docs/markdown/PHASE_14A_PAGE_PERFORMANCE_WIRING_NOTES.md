# Phase 14A.2 — Page Performance Tracker Service Wiring

Wires `performanceService.fetchPagePerformance` and `fetchPageDetail` to real
Supabase Stage 4 tables (`seo_page_inventory`, `seo_page_keywords`,
`seo_page_performance_snapshots`, `seo_page_performance_latest` view) behind
the existing Phase 13A mock/Supabase data-mode adapter. In mock mode the app
behaves exactly as before. In Supabase mode, both functions attempt a real
Supabase read and gracefully fall back to mock on any failure (missing
config, no session, RLS denial, network error), logging one dev-facing
console warning.

**Decline Diagnosis was not wired in this phase (Phase 14A.2).** No writes
anywhere in this phase. No real GSC/GA4 integration, no real crawler — every
Stage 4 row currently on the test project was written by the Phase 14A.1 UI
seed extension with `source = 'manual_seed'`. Production remains untouched.
*(Decline Diagnosis was subsequently backed by Stage 5 and service-wired in
Phase 14B — see `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md`.)*

---

## Approved fix note — 2026-07-14 (hard-refresh race)

During **Phase 16H Scenario 1** operator acceptance, a reproduced **hard-refresh
race** was fixed in `src/pages/seo/PagePerformancePage.tsx` (a Page Performance
Tracker locked file) with explicit human approval. Symptom: on a hard refresh the
**cross-workspace fallback** could evaluate **before** the current website's
onboarding/page query completed, and incorrectly replace the valid active website
with a fallback selection.

**Narrow fix (display/query-timing only):** fallback evaluation now waits for a
**completed onboarding** query and a **completed page fetch** before it may run,
so it can no longer pre-empt the legitimate active website during hydration.
**No** database, service signature, adapter pattern, mock behaviour, fallback
contract, or Stage 6 change; `npm run build` passed. **Retest (PASS):** after the
fix, a hard refresh retained the correct website and all 3 published Page-Inventory
rows (Scenario 1 re-verified PASS). This is an **allowed proven bug fix** under the
Page Performance Tracker lock; the lock remains in force (logged in
`MODULE_LOCKS.md` → Approved-change log). Detail: `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`,
`OPERATOR_TEST_RESULTS.md` (Scenario 1). This is **not** a redesign — only the
fallback-timing guard changed.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/seoPagePerformanceSupabaseService.ts` — reads Stage
  4's normalized tables and flattens them into the app's existing flat
  `PagePerformance` shape. Exports `fetchSupabasePagePerformance()`,
  `fetchSupabasePageDetail()`, plus the smaller building-block reads
  `fetchSupabasePageInventory()`, `fetchSupabasePageKeywords()`,
  `fetchSupabaseLatestPerformance()`, `fetchSupabasePerformanceHistory()`,
  `fetchSupabaseMovementSummary()`.
- `PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md` — this file.

**Changed:**
- `src/services/performanceService.ts` — `fetchPagePerformance` and
  `fetchPageDetail` now call `runWithServiceAdapter()`. `fetchPerformanceSummary`
  now derives from `fetchPagePerformance` (awaited) instead of importing the
  mock adapter's `listPagePerformance` directly — its aggregation logic is
  otherwise byte-for-byte unchanged. Same function signatures and return
  types as before for all three.
- `src/services/supabase/supabaseTypes.ts` — added `pageInventory`,
  `pageKeywords`, `pagePerformanceSnapshots`, `pagePerformanceLatestView` to
  `SEO_TABLES`.
- `src/pages/seo/dev/SupabaseAuthTestPage.tsx` — added "Test Page
  Performance Service", "Test Page Performance Latest View", and "Test Page
  Performance History" dev-only buttons/results.
- `SERVICE_LAYER_WIRING_PLAN.md` — status update (§14); title and §5/§6
  updated to reflect Phase 14A.2.

**Not changed:** any Decline Diagnosis / Off-Page / AI Visibility /
Competitor / Roadmap / Reports / Admin service, `src/services/serviceAdapter.ts`,
any `src/mocks/*` file, any page/component beyond the dev harness, any type,
any migration, the reference Digibility app.

---

## 2. Services Wired

| Service function | Mock path | Supabase path (new) |
|---|---|---|
| `performanceService.fetchPagePerformance(websiteId)` | `listPagePerformance()` | `fetchSupabasePagePerformance(websiteId)` — flattens page inventory + keywords + latest snapshot per page |
| `performanceService.fetchPageDetail(pageId)` | `getPagePerformanceById()` | `fetchSupabasePageDetail(pageId)` — single-page version of the above |
| `performanceService.fetchPerformanceSummary(websiteId, websiteUrl)` | Unchanged aggregation, now over `fetchPagePerformance`'s result | Same aggregation, now over `fetchPagePerformance`'s (Supabase-sourced) result — **no separate Supabase query**, inherits correctness from the already-wired read above |

**Not wired this phase (unchanged, mock-only in every mode):**
`fetchDeclineDiagnoses`, `fetchDiagnosisForPage`,
`fetchRefreshRecommendationsForWebsite`, `fetchRefreshRecommendationForPage`,
`generateMockPerformanceRefresh` — Decline Diagnosis and the empty-state
mock-data generator are explicitly out of scope for Phase 14A.2.

---

## 3. Supabase Tables/View Used

Stage 4 only, all previously test-verified (see `BACKEND_MILESTONE_HANDOFF.md`,
`SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`):
- `seo_page_inventory` (read-only, `is_active=true` filter)
- `seo_page_keywords` (read-only)
- `seo_page_performance_snapshots` (read-only — used by
  `fetchSupabasePerformanceHistory` for raw history; not used by the main
  flattening path, which reads the view instead)
- `seo_page_performance_latest` view (read-only — the primary metrics
  source for the flattened `PagePerformance` shape; `security_invoker = true`,
  so it inherits the snapshots table's RLS automatically)

No RPC calls. No writes anywhere in this phase.

---

## 4. Mock Fallback Behavior

Both `fetchPagePerformance` and `fetchPageDetail` go through
`runWithServiceAdapter()` (Phase 13A), identical fallback semantics to every
prior phase:

1. **Mock mode** → Supabase code never runs.
2. **Supabase mode requested but config missing/invalid** → falls back to
   mock (`runtimeConfig.ts`/`dataMode.ts`, unchanged).
3. **Supabase mode + config present but no session** → both Supabase
   functions call `requireAuthenticatedUser()` first, which throws a clear
   "no authenticated Supabase user" error before any network request is
   even issued → the adapter catches it, logs one console warning
   (deduplicated once per session, matching every prior phase), and falls
   back to mock.
4. **Supabase mode + authenticated but a website has no Stage 4 rows yet** →
   `fetchSupabasePagePerformance` returns `[]` (not an error, not a crash) —
   the existing "No performance data yet" empty state on `PagePerformancePage`
   renders exactly as it already did for a mock website with no seeded data.
5. **Supabase mode + authenticated + RLS/DB error** → same graceful
   fallback path as #3.
6. **A page with no primary keyword, no keywords at all, or no snapshot
   yet** never throws — `primary_keyword` defaults to `""`,
   `secondary_keywords` to `[]`, all metrics default to `0`, and
   `performance_status` defaults to `"not_enough_data"`. This matches the
   two untracked pages (`/contact`, `/pricing`) in the Phase 14A.1 UI seed
   extension, which intentionally have no mapped keywords.

No raw Supabase error is ever shown to the end user. The two Supabase-only
dev-harness diagnostic buttons (§6 below) are the one place a raw-ish error
message can surface, and only on the dev-only `/seo/dev/auth-test` page —
even there, the message is our own clear string (e.g. "no authenticated
Supabase user (session missing)"), never a raw PostgREST/stack-trace dump.

---

## 5. Manual Test Steps — Mock Mode

1. No `.env` needed (or `VITE_SEO_DATA_MODE=mock`).
2. `npm run dev`, visit `/seo/page-performance`.
3. Confirm identical behavior to before Phase 14A.2: the 6 seeded mock
   pages for Acme Plumbing render with their existing improving/declining/
   needs-refresh/stable statuses, the summary cards show the same totals
   (6 tracked pages, 14 tracked keywords, 578 clicks, etc.), filters work,
   search works.
4. Visit `/seo/decline-diagnosis` — confirm it still renders (it also calls
   `fetchPagePerformance`, now wired, but stays on mock data in mock mode).
5. Visit `/seo/dashboard` — confirm `PagePerformanceSummaryCard` still shows
   the same improving/declining/needs-refresh counts as before.
6. Confirm the browser console has zero `[SEO data mode]` warnings in mock
   mode (live-verified — see §8 of this phase's implementation).

---

## 6. Manual Test Steps — Supabase Mode via `/seo/dev/auth-test`

**Prerequisite:** `.env` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
(test project), `VITE_SEO_DATA_MODE=supabase`; Stage 1 + Stage 4 applied;
the base UI seed dataset (`seo_seed_ui_test_dataset.sql`) and the Stage 4
seed extension (`seo_seed_stage4_page_performance_ui_extension.sql`) both
already applied.

1. Sign in with a test-project user that has `user_module_access(module='seo')`
   granted **and** is a member of the seeded workspace
   (`44444444-0000-0000-0001-000000000001`).
2. **"Test website service"** — confirms a real website id (use the seeded
   website `https://ui-seed-digibility.example`, id
   `44444444-0000-0000-0002-000000000001`, if it's the first one returned;
   otherwise any website you're a member of works, but only the seeded one
   has Stage 4 rows).
3. **"Test Page Performance Service"** — with the seeded website, expect
   `7 page(s) found` with a movement breakdown roughly matching the seed
   (see `SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md` §7:
   4 improving, 2 stable, 2 declining, 2 new/no-data collapse into
   `not_enough_data`, plus 2 pages get `needs_refresh` from `content_status`
   overriding their raw movement). On a non-seeded website, `0 page(s) found`
   is a legitimate empty state, not a failure.
4. **"Test Page Performance Latest View"** — expect `12 latest-view row(s)`
   for the seeded website, with a movement-count breakdown
   (`improving: 4, stable: 2, declining: 2, new: 2, no_data: 2`) matching
   the seed extension's documented counts exactly.
5. **"Test Page Performance History"** — uses the first page id from step 3;
   expect a small non-zero snapshot count for pages that have page-level
   aggregate history (most seeded pages have 1-2), or a graceful "0
   page-level snapshot(s)" for a page whose only history is keyword-specific
   rather than page-level.
6. Visit `/seo/page-performance` directly (same signed-in session) — confirm
   the 7 seeded pages render with real titles, page types, keywords, and
   movement-derived status badges instead of the mock Acme Plumbing data.
7. Visit `/seo/dashboard` — confirm `PagePerformanceSummaryCard` now shows
   counts derived from the real Stage 4 data (no separate wiring needed —
   composition).
8. Sign out — all test-panel results reset, including the three new ones.

---

## 7. Known Limitations

- **Read-only frontend wiring only.** No page inventory / keyword /
  snapshot INSERT/UPDATE/DELETE path exists anywhere in the frontend as of
  this phase — matches the task's explicit "prefer no writes" instruction.
- **No real GSC/GA4 integration.** `source` on every Stage 4 row currently
  on the test project is `'manual_seed'` — nothing in this phase (or Stage 4
  itself) calls an external search-console/analytics API.
- **No real crawler.** Page inventory is hand-seeded, not discovered.
- **Decline Diagnosis was not wired in this phase.** At Phase 14A.2,
  `DeclineDiagnosisPage` showed real Stage 4 page data (via the now-wired
  `fetchPagePerformance`) alongside mock decline-diagnosis/refresh-recommendation
  data — the correlation between them (matching by `page_url`) could look
  inconsistent on the seeded Stage 4 pages, since the mock diagnoses were
  written for the mock Acme Plumbing pages, not the Stage 4 seed's pages.
  *(This has since been addressed: Decline Diagnosis was backed by the Stage 5
  `seo_decline_diagnoses` tables and service-wired in Phase 14B — see
  `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md`. Refresh recommendations remain
  mock/demo.)*
- **`data_source_status` text is a pre-existing cosmetic inaccuracy.**
  `PerformanceSummary.data_source_status` always reads "Mock performance
  data for local testing..." regardless of actual data mode — this string
  was not made data-mode-aware in this phase (low-value cosmetic change,
  not required by the task; the underlying counts it accompanies are
  correctly Supabase-sourced).
- **Status-model approximation.** Stage 4's `movement_status` (5 values) and
  `content_status` (4 values) are combined into the app's single
  `PagePerformanceStatus` (5 values) via the mapping documented in
  `SERVICE_LAYER_WIRING_PLAN.md` §14 — a reasonable best-fit, not an exact
  1:1 model match (same caveat pattern as Phase 13E's content-status
  mapping).
- **`main_seo_issue` sourced from `diagnosis_hint`; `recommended_next_action`
  is always `undefined` in Supabase mode** — Stage 4 has no column
  equivalent to the mock's `recommended_next_action` string; inventing one
  would mean generating content not present in the seeded data.
- Same auth/session prerequisites as every prior phase — no in-app login UI
  exists yet; use `/seo/dev/auth-test` to establish a session for testing.
- **Not live-verified with a real signed-in Supabase session in this
  session** — the no-session graceful-fallback path (mock mode and
  Supabase-mode-without-session) was live-verified in the browser; the
  with-session Supabase-read path was verified by code review and the
  passing `tsc`/`build` checks, consistent with how prior phases without
  available live test credentials in-session were verified (see e.g. Phase
  13F's equivalent note).

---

## 8. Recommended Next Phase

With Page Performance reads now wired, remaining mock-only modules (Decline
Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, Reports)
have no Stage 1-4 backend tables to wire against yet — each would need its
own backend design/migration phase (Stage 5+) before any frontend wiring is
possible. A reasonable next step is either: (a) a live end-to-end
verification pass against the test Supabase project with a real signed-in
session (owner/admin/team_member/client) to confirm role-based reads render
correctly on `/seo/page-performance`, or (b) beginning the Stage 5 backend
design for Decline Diagnosis, which already has a documented seam
(`movement_status`, `diagnosis_hint` on `seo_page_performance_snapshots`)
ready to build on.

---

## 9. Approved Locked-Module Bug Fix — 2026-07-14

During Phase 16H / Crawler 1F operator acceptance, a browser hard refresh on
`/seo/page-performance` reproduced a race condition in the existing
cross-workspace fallback.

**Expected:** the active `https://digibility.ai` website, which had completed
business onboarding and 3 active published Page Inventory rows, remained selected
after refresh.

**Actual:** the fallback could run while the onboarding-dependent page query was
still disabled. Because the query's initial empty result was treated as a completed
zero-row result, the fallback could select the first other accessible website with
performance data. The page could then show an incorrect “Complete business
onboarding first” gate.

Database evidence confirmed that the original website and onboarding rows were
valid and shared the same workspace; onboarding was `completed` at 100%, and the
website had 3 active page rows.

After explicit human approval under `MODULE_LOCKS.md`, the narrowly scoped fix
changed only `src/pages/seo/PagePerformancePage.tsx`:

- track whether the page-performance query has actually fetched;
- wait until onboarding loading has finished;
- require completed onboarding;
- wait until the current website's page query has completed before considering the
  cross-workspace fallback.

No service signature, adapter pattern, mock behaviour, database contract, RPC, RLS,
or Stage 6 behaviour changed.

**Verification:**

- `npm run build` — PASS;
- hard refresh retained `https://digibility.ai`;
- tracked-page count remained 3;
- all three crawler-published Page Inventory cards remained visible;
- navigation back to Audit and another hard refresh retained the completed crawl,
  3 published pages and 3 published issues.

The earlier “No real crawler” limitation in this historical Phase 14A document
described the state at the time Phase 14A was delivered. Phase 16C–16H subsequently
added the crawler workflow; this dated note records only the approved compatibility
fix discovered during its operator acceptance.

