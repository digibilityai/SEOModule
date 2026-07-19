# Phase 13C — Technical Audit + SEO Recommendation Service Wiring

Wires `auditService` and `recommendationService` to real Supabase (Stage 2) tables behind the Phase 13A mock/Supabase data-mode switch. In mock mode the app behaves exactly as before. In Supabase mode, both services attempt a real Supabase read (and, for triggering a new audit, a real RPC call) and gracefully fall back to mock on any failure (missing config, no session, RLS denial, network error), logging one dev-facing console warning.

**Approval Queue is not wired.** **Content Studio is not wired.** Audit generation remains Stage 2 RPC/mock-safe only — no real crawler exists yet. Production remains untouched.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/seoAuditSupabaseService.ts` — `fetchSupabaseAudits()`, `fetchSupabaseLatestAudit()`, `fetchSupabaseAuditById()`, `fetchSupabaseIssuesForAudit()`, `runSupabaseAudit()`.
- `src/services/supabase/seoRecommendationSupabaseService.ts` — `fetchSupabaseRecommendations()`, `fetchSupabaseOnPageRecommendations()`, `fetchSupabaseRecommendationById()`.
- `PHASE_13C_AUDIT_RECOMMENDATION_WIRING_NOTES.md` — this file.

**Changed:**
- `src/services/auditService.ts` — `fetchAudits`, `fetchLatestAudit`, `fetchAuditById`, `fetchIssuesForAudit`, `runAudit` now call `runWithServiceAdapter()`. Same function signatures and return types as before.
- `src/services/recommendationService.ts` — `fetchRecommendations`, `fetchOnPageRecommendations`, `fetchRecommendationById` wired the same way. `generateRecommendationsFromAudit` is unchanged (still mock-only, by design — see §4).
- `src/pages/seo/dev/SupabaseAuthTestPage.tsx` — added "Test audit service", "Test recommendation service", and "Run test audit" dev-only buttons/results.
- `SERVICE_LAYER_WIRING_PLAN.md` — status update (§10).

**Not changed:** `src/services/approvalService.ts`, `src/services/contentStudioService.ts`, any `src/mocks/*` file, any page/component beyond the dev harness, any type, any migration, the reference Digibility app.

---

## 2. Services Wired

| Service function | Mock path | Supabase path (new) |
|---|---|---|
| `auditService.fetchAudits(websiteId)` | `listAudits()` | `fetchSupabaseAudits(websiteId)` — all runs for the website, newest first |
| `auditService.fetchLatestAudit(websiteId)` | `getLatestAudit()` | `fetchSupabaseLatestAudit(websiteId)` — reads the `is_latest=true` row; `null` if none yet |
| `auditService.fetchAuditById(id)` | `getAuditById()` | `fetchSupabaseAuditById(id)` |
| `auditService.fetchIssuesForAudit(auditId)` | `listIssuesForAudit()` | `fetchSupabaseIssuesForAudit(auditId)` |
| `auditService.runAudit(websiteId, websiteUrl)` | Simulated crawl + occasional failure | `runSupabaseAudit(websiteId)` — calls the Stage 2 `seo_run_audit(uuid)` RPC, then reads back the created row |
| `recommendationService.fetchRecommendations(websiteId)` | `listRecommendations()` | `fetchSupabaseRecommendations(websiteId)` — `is_current=true` only |
| `recommendationService.fetchOnPageRecommendations(websiteId)` | `listOnPageRecommendations()` | `fetchSupabaseOnPageRecommendations(websiteId)` — same, filtered to on-page areas |
| `recommendationService.fetchRecommendationById(id)` | `getRecommendationById()` | `fetchSupabaseRecommendationById(id)` |
| `recommendationService.generateRecommendationsFromAudit(website, issues)` | Regenerates the website's recommendation set | **Not wired — stays mock-only in every data mode** (see §4) |

---

## 3. Supabase Tables/RPCs Used

Stage 2 only, all previously test-verified (see `BACKEND_MILESTONE_HANDOFF.md`):
- `seo_audit_runs` (read; `is_latest` used for "latest audit")
- `seo_audit_issues` (read only — never inserted from the frontend)
- `seo_recommendations` (read only, filtered to `is_current=true` — never inserted from the frontend)
- `seo_run_audit(uuid)` RPC (called to trigger a new audit run)

Not used this phase: `seo_approval_items`, `seo_approval_comments`, `seo_approval_activity`, `seo_supersede_recommendation`, `seo_approval_transition`, `seo_role_of` — all Approval Queue territory, out of scope.

---

## 4. Mock Fallback Behavior

All Supabase calls go through `runWithServiceAdapter()` (Phase 13A), same pattern as Phase 13B:

1. **Mock mode** → Supabase code never runs.
2. **Supabase mode requested but config missing/invalid** → falls back to mock (`runtimeConfig.ts`/`dataMode.ts`, unchanged).
3. **Supabase mode + config present but no session** → every Supabase function in this phase calls `requireAuthenticatedUser()` first, which throws a clear "no authenticated Supabase user" error → the adapter catches it, logs one console warning, and falls back to mock. This is deliberate: without this check, Stage 2 RLS would just silently return **zero rows** for an unauthenticated caller, which would look like "no audits" instead of "not signed in" — the explicit auth check makes the fallback trigger correctly instead of showing a misleading empty state.
4. **Supabase mode + authenticated but no Stage 2 data yet** → reads return an empty array / `null`, exactly like a legitimate "nothing here yet" state in mock mode. Not an error, no fallback triggered — this is the honest, expected state for a freshly test-created website.
5. **Supabase mode + authenticated + RLS/DB error** (e.g. workspace membership denies read) → same graceful fallback path as #3.
6. **`runAudit` specifically:** the Supabase path always creates a `status: "running"` row (Stage 2 has no crawler) — it never simulates a "completed" audit or issues. If the RPC call itself fails (e.g. website exists only in mock data, not in `seo_websites`), the adapter falls back to the full simulated mock audit (including its own occasional simulated failure).

No raw Supabase error is ever shown to the end user.

---

## 5. Manual Test Steps — Mock Mode

1. No `.env` needed (or `VITE_SEO_DATA_MODE=mock`).
2. `npm run dev`, visit `/seo/audit` and `/seo/page-optimizer`.
3. Confirm identical behavior to before Phase 13C: seeded audit history, "Run audit" simulates a crawl (~1.4s) with an occasional failure, on-page recommendations list renders.

---

## 6. Manual Test Steps — Supabase Mode via `/seo/dev/auth-test`

**Prerequisite:** `.env` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (test project), `VITE_SEO_DATA_MODE=supabase`; Stage 1 + Stage 2 applied on that project.

1. Visit `/seo/dev/auth-test`, sign in with a test-project user that has `user_module_access(module='seo')` granted (see `PHASE_13B1_DEV_AUTH_TEST_NOTES.md` §6 for how to grant it).
2. Click **"Test website service"** first — needed to get a real website id (creates a default workspace + reports `0 website(s) found` on a brand-new project). Click **"Create test website"** if none exist yet, then **"Test website service"** again.
3. Click **"Test audit service"** — expect `0 audit run(s) found — latest status: (none yet)` on a fresh website. Not a failure.
4. Click **"Test recommendation service"** — expect `0 current recommendation(s) found`. Not a failure.
5. Click **"Run test audit"** (dev-only, clearly labeled) — expect a result like `Audit run status: running (id: ..., issues: 0).` No external crawling occurs; this only creates a Stage 2 `seo_audit_runs` row via the RPC.
6. Click **"Test audit service"** again — expect `1 audit run(s) found — latest status: running`.
7. Sign out — all test-panel results reset.

To see a **completed** audit with real issues/recommendations in Supabase mode, a service-role/system process must populate `seo_audit_issues` + `seo_recommendations` for that run directly in the test project (matches Stage 2's design — see §7 below). This is expected and not something the frontend does.

---

## 7. Known Limitations

- **No real crawler.** `seo_run_audit` only creates the run row; it never completes it. A completed audit with real issues in Supabase mode requires a future crawler/service-role backend (or manual test-data insertion via the Supabase SQL editor) — this phase does not add one, by design.
- **`generateRecommendationsFromAudit` stays mock-only in every mode.** Stage 2 RLS excludes clients from writing `seo_recommendations`; recommendations are system/service-role generated. In practice this function is never reached in Supabase mode anyway, since its only caller (`WebsiteAuditPage`) gates it behind `audit.status === "completed"`, and the Supabase `runAudit()` path always returns `"running"`.
- **Approval Queue reads recommendations but doesn't write them here.** `ApprovalQueuePage` and `PagePerformancePage` already call the now-wired `fetchLatestAudit`/`fetchIssuesForAudit`/`fetchRecommendations`, so they will show real Supabase data once available — but any approve/reject/status-change action still goes through the untouched, mock-only `approvalService.ts`. That's expected: this phase wires **reads**, not the approval workflow.
- **`is_current` filtering.** Reads only return `is_current=true` recommendations (the "live" version per Stage 2's versioning design); superseded rows are intentionally excluded, matching how the mock adapter has no history concept to begin with.
- Same auth/session prerequisites as Phase 13B — no in-app login UI exists yet; use `/seo/dev/auth-test` to establish a session for testing.

---

## 8. Recommended Next Phase

**Phase 13D: wire `approvalService`** against Stage 2's `seo_approval_items` / `seo_approval_comments` / `seo_approval_activity` and the `seo_approval_transition` RPC, now that audit/recommendation reads are in place to link against. Continue down the order in `SERVICE_LAYER_WIRING_PLAN.md` §6.
