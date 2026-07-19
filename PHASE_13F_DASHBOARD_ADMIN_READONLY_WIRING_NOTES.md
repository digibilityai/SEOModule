# Phase 13F — Dashboard Summary + Admin Preview Read-Only Wiring Notes

Phase 13F is **read-only only**. No write actions, no RPC calls, no admin
writes (role management, billing, module access), no production wiring, and
no change to which service the actual `/seo/admin-preview` page reads from.
This phase adds two narrow reads and one small composition service, all
behind the existing mock/Supabase data-mode adapter established in Phase
13A and used by every phase since.

## 1. Files Changed

| File | Change |
|---|---|
| `src/services/supabase/seoDashboardSupabaseService.ts` | **New.** `fetchSupabaseTopPriorityFixes()`, `fetchSupabasePendingApprovalsSummary()`. Read-only. |
| `src/services/dashboardService.ts` | `fetchTopPriorityFixes` and `fetchPendingApprovalsSummary` now go through `runWithServiceAdapter()`, calling the two functions above in Supabase mode. `fetchRecentActivity`, `logRecentActivity`, and the three pure functions (`buildVisibilityScoreCards`, `buildSetupChecklist`, `resolveRecommendedNextStep`) are unchanged. |
| `src/services/adminPreviewSummaryService.ts` | **New.** `fetchAdminPreviewSummary()` — composes already-wired service calls into a read-only `AdminPreviewSummary`. No direct Supabase queries. |
| `src/pages/seo/dev/SupabaseAuthTestPage.tsx` | Added "Test Dashboard Summary Service" and "Test Admin Preview Read Service" buttons + supporting state/handlers, under a new "Phase 13F — Dashboard + Admin Preview (read-only)" section. Reset in `handleSignOut`. |
| `SERVICE_LAYER_WIRING_PLAN.md` | Title bumped to include 13F; new intro paragraph; §5 file inventory; §6 wiring order marked complete; new §13 status section. |

**Not changed:** `src/pages/seo/SeoDashboardPage.tsx`, `src/pages/seo/SeoAdminPreviewPage.tsx`, `src/modules/seo-admin/SeoAdminShell.tsx`, `src/services/seoAdminService.ts`, any `src/mocks/*` file, any migration SQL.

## 2. Services Wired

| Function | Mock mode | Supabase mode | Notes |
|---|---|---|---|
| `dashboardService.fetchTopPriorityFixes(websiteId)` | `listTopPriorityFixes()` (unchanged) | Derives from Stage 2 `seo_recommendations` where `is_current=true`, sorted by impact weight + confidence, capped at 5 | No dedicated "fixes" table exists; this is a read-only derivation, same heuristic the mock uses. |
| `dashboardService.fetchPendingApprovalsSummary(websiteId, websiteUrl)` | `listApprovalQueue()`-derived counts (unchanged) | Stage 2 `seo_approval_items` status/fix_owner counts | Read-only; the actual `approvalService.fetchApprovalQueue` was not reused here — this reads only the columns needed for counts. |
| `adminPreviewSummaryService.fetchAdminPreviewSummary()` | N/A — always composes already-wired calls, which independently pick mock or Supabase | Same | Pure composition of `fetchWebsites`, `fetchAudits`, `fetchRecommendations`, `fetchApprovalQueue`, `fetchContentOpportunities`. No new adapter code; correctness is inherited from those already-wired functions. |

**Not wired this phase (unchanged, mock-only or out of scope):**
`dashboardService.fetchRecentActivity` / `logRecentActivity` (no allowed activity table this phase), Page Performance, Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, Reports, and the existing `seoAdminService.ts` (already benefits transitively from prior-phase wiring via its own composition, but was not itself modified).

## 3. Supabase Tables Used

- `seo_recommendations` (read-only, `is_current=true` filter) — Stage 2
- `seo_approval_items` (read-only, `status`/`fix_owner` columns only) — Stage 2
- Indirectly, via already-wired composed calls inside `adminPreviewSummaryService`: `seo_websites`, `seo_audit_runs`, `seo_recommendations`, `seo_approval_items`, `seo_content_opportunities` (all already wired in Phase 13B/13C/13D/13E — no new table access patterns introduced here).

No RPC calls. No writes. No `seo_business_onboarding`, `seo_content_drafts`, or storage bucket access added this phase (composition reuses what earlier phases already wired).

## 4. Mock Fallback Behavior

Both new dashboard functions call `requireAuthenticatedUser(...)` as the first step of their Supabase path. With no Supabase session, this throws immediately — **no network request is ever issued** — and `runWithServiceAdapter()` catches the error, logs one dev-facing console warning (`[SEO data mode] ... falling back to mock.`, deduplicated once per session across all services, per existing Phase 13A behavior), and returns the mock result. `adminPreviewSummaryService.fetchAdminPreviewSummary()` has no fallback logic of its own — each nested already-wired call resolves its own mock/Supabase behavior independently, so the composed summary is correct in either mode automatically.

## 5. Manual Test Steps — Mock Mode

1. Set `.env.local` `VITE_SEO_DATA_MODE=mock` (or leave `.env.local` absent/blank) and start the dev server.
2. Visit `/seo/dashboard` — "Top Priority Fixes" and "Pending Approvals" cards render exactly as before.
3. Visit `/seo/admin-preview` — overview cards, website list, and admin operations sections render exactly as before (unchanged `seoAdminService.ts` path).
4. Visit `/seo/dev/auth-test`, click "Test website service", then "Test Dashboard Summary Service" and "Test Admin Preview Read Service" — both report sensible counts, no warnings.
5. Confirm the browser console has no `[SEO data mode]` warnings in mock mode.

## 6. Manual Test Steps — Supabase Mode (via Dev Harness)

1. Set `.env.local` to a **test** Supabase project's `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` and `VITE_SEO_DATA_MODE=supabase`. Restart the dev server (Vite only reads env at startup).
2. **No session:** visit `/seo/dashboard` and `/seo/admin-preview` directly — both render using the mock-fallback path with no crash (one console warning logged, deduplicated). Visit `/seo/dev/auth-test`, run "Test website service" then the two new Phase 13F buttons — both report counts via fallback, no raw errors shown.
3. **With session:** on `/seo/dev/auth-test`, sign in with a real test-project user (`supabase.auth.signInWithPassword()`). Run "Test website service" to get a real website id, then "Test Dashboard Summary Service" — attempts real reads against `seo_recommendations` / `seo_approval_items` for that website; "Test Admin Preview Read Service" composes real reads across all already-wired services. Empty results (e.g. 0 recommendations on a fresh test site with no crawler) are a legitimate empty state, not a failure.
4. Confirm no write requests appear in the Network tab for either new button — reads only.

## 7. Known Limitations

- "Top Priority Fixes" is a **derived view** of `seo_recommendations`, not a dedicated table — if Stage 2's recommendation status model changes, the `STATUS_TO_FIX_STATUS` mapping in `seoDashboardSupabaseService.ts` will need revisiting.
- `fetchRecentActivity` remains mock-only in every data mode — no Stage 1-3 table was in this phase's allowed list, and merging Stage 2's `seo_approval_activity` with Stage 3's content activity into one unified feed is a larger scope than a read-only dashboard summary.
- The admin preview summary intentionally does **not** reuse `seoAdminService.ts` — that file spans every SEO module (including several explicitly out of scope this phase) and is tied to the eventual real admin panel. `adminPreviewSummaryService.ts` is a smaller, separate, purpose-built read-only summary for the dev harness and the temporary preview route only.
- `/seo/admin-preview` is **not** the final Digibility Admin Panel integration. It remains a temporary, standalone, dev-only preview route (see the existing in-app banner on that page, unchanged this phase). No role management, billing, or module-access data is exposed anywhere in this phase's new code.
- Page Performance, Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, and Reports remain mock-only/unwired — untouched this phase, per the explicit scope boundary.

## 8. Recommended Next Phase

With Dashboard summaries and Admin Preview reads now wired, the remaining mock-only modules (Page Performance, Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, Reports) have no Stage 1-3 backend tables to wire against yet — they would need their own backend design/migration phase before any frontend wiring is possible. In the meantime, a reasonable next step is validating the Phase 13B-13F wiring end-to-end against a seeded test Supabase project (real websites, audits, recommendations, approvals, and content opportunities created via the SQL editor) to exercise the full non-empty-state UI, rather than only the currently-empty-state Supabase paths this phase's testing exercised.
