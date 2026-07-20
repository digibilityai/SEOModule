# Phase 13B — Website Setup + Business Onboarding Service Wiring

Wires `websiteService` and `businessOnboardingService` to real Supabase (Stage 1) tables behind the Phase 13A mock/Supabase data-mode switch. In mock mode the app behaves exactly as before. In Supabase mode, both services attempt a real Supabase read/write and gracefully fall back to mock on any failure (missing config, no session, RLS denial, network error), logging one dev-facing console warning.

No audit, recommendation, approval, or Content Studio service was touched.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/seoWorkspaceService.ts` — `getCurrentSeoWorkspace()`, `getOrCreateDefaultSeoWorkspace()`
- `src/services/supabase/seoWebsiteSupabaseService.ts` — `fetchSupabaseWebsites()`, `fetchSupabaseWebsiteById()`, `addSupabaseWebsite()`
- `src/services/supabase/seoBusinessOnboardingSupabaseService.ts` — `fetchSupabaseOnboardingByWebsiteId()`, `saveSupabaseOnboarding()`

**Changed:**
- `src/services/websiteService.ts` — `fetchWebsites`, `fetchWebsiteById`, `addWebsite` now call `runWithServiceAdapter()` instead of calling the mock adapter directly. Same function signatures and return types as before.
- `src/services/businessOnboardingService.ts` — `fetchOnboardingByWebsiteId`, `saveOnboarding` wired the same way. `calculateCompletionPercentage`/`resolveOnboardingStatus` and the `RequiredOnboardingFields` type are unchanged.
- `SERVICE_LAYER_WIRING_PLAN.md` — status update (§8).

**Not changed:** any `src/mocks/*` file, any page/component, any type, any migration, the reference Digibility app.

---

## 2. Services Wired

| Service function | Mock path | Supabase path (new) |
|---|---|---|
| `websiteService.fetchWebsites(workspaceId)` | `listWebsites()` (mock data) | `fetchSupabaseWebsites()` — ignores `workspaceId`, resolves the real workspace from the session instead |
| `websiteService.fetchWebsiteById(id)` | `getWebsiteById()` | `fetchSupabaseWebsiteById(id)` |
| `websiteService.addWebsite(input)` | `createWebsite()` | `addSupabaseWebsite(input)` |
| `businessOnboardingService.fetchOnboardingByWebsiteId(websiteId)` | `getOnboardingByWebsiteId()` | `fetchSupabaseOnboardingByWebsiteId(websiteId)` |
| `businessOnboardingService.saveOnboarding(input)` | `upsertOnboarding()` | `saveSupabaseOnboarding(input)` |

**Why `workspaceId` is ignored in Supabase mode:** the UI currently always passes the hardcoded mock constant `MOCK_WORKSPACE_ID` (a non-UUID string). That has no counterpart in a real Supabase project, so the Supabase path instead resolves the authenticated user's own workspace via `seoWorkspaceService`. This keeps the existing call sites/signatures unchanged (no UI rewrite) while still being correct against real data.

---

## 3. Supabase Tables Used

Stage 1 only, all previously test-verified (see `BACKEND_MILESTONE_HANDOFF.md`):
- `seo_workspaces` (read; insert only when the user has no workspace yet)
- `seo_workspace_members` (read only — membership creation is left entirely to the Stage 1 `seo_workspace_add_owner_member` trigger, never inserted into directly here)
- `seo_websites` (read, insert)
- `seo_connection_status` (read, insert — one row seeded per new website, defaults only)
- `seo_business_onboarding` (read, insert, update)

No Stage 2/3 table, RPC, or Storage bucket is touched.

---

## 4. Fallback Behavior

All Supabase calls go through `runWithServiceAdapter()` (Phase 13A):

1. **Mock mode** (`VITE_SEO_DATA_MODE` unset or `mock`) → Supabase code never runs.
2. **Supabase mode requested but config missing/invalid** → `requireSupabaseOrFallback()` returns false → mock runs. (Already handled by `runtimeConfig.ts`/`dataMode.ts`, no Phase 13B change.)
3. **Supabase mode + config present but no session** → `seoWorkspaceService.getCurrentSeoWorkspace()` returns `{ workspace: null, reason: "No authenticated Supabase user..." }` → the Supabase service function throws that reason → the adapter catches it, logs one console warning, and falls back to mock.
4. **Supabase mode + session but no `user_module_access` grant (or any other RLS/DB error)** → the workspace-create insert fails under RLS → same graceful fallback path as #3, with the actual Postgres/RLS message in the console warning.
5. **Supabase mode + authenticated + workspace resolved** → real read/write against `seo_websites` / `seo_business_onboarding` / `seo_connection_status`.

No raw Supabase error is ever shown to the end user — the UI only ever sees the resolved mock data (or, on a fully successful Supabase call, the real data in the exact same shape).

---

## 5. Manual Test Steps

**A. Mock mode (default / no `.env` needed)**
1. `npm run dev`, visit `/seo/websites` and `/seo/onboarding`.
2. Confirm identical behavior to before Phase 13B: seeded websites list, "Add website" works, onboarding form loads/saves.

**B. Supabase mode, no session**
1. Set `.env`: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (test project), `VITE_SEO_DATA_MODE=supabase`.
2. `npm run dev` with no logged-in user (no auth UI exists yet, so this is the default state).
3. Visit `/seo/websites` — page still renders the mock websites list (no crash, no blank screen). Console shows one `[SEO data mode] websiteService.fetchWebsites Supabase call failed (...); falling back to mock.` warning.
4. Visit `/seo/dev/supabase-readiness` to confirm `mode: supabase`, `configured: true`, `hasSession: false`.

**C. Supabase mode, authenticated session**
1. Same `.env` as B.
2. Sign in a real Supabase Auth user against the test project (e.g. via the Supabase dashboard's magic-link/password test tools, since no in-app login UI exists yet — set the session via `supabase.auth.setSession(...)` in the browser console, or sign in through another app pointed at the same project).
3. Grant that user SEO module access once, directly in the test project (service-role/SQL editor only — never from the frontend):
   ```sql
   insert into public.user_module_access (user_id, module_name, is_active)
   values ('<user-id>', 'seo', true)
   on conflict (user_id, module_name) do nothing;
   ```
4. Reload `/seo/websites`. First load creates a default `seo_workspaces` row (owner-membership auto-added by the Stage 1 trigger) with zero websites; "Add website" now inserts into `seo_websites` + `seo_connection_status` for real.
5. Visit `/seo/onboarding`, fill in the form, save — confirm the row appears in `seo_business_onboarding` in the Supabase dashboard, and reloading the page loads it back.
6. Without the `user_module_access` grant from step 3, confirm step 4 instead falls back to mock with a console warning (RLS denial on the workspace insert) — this proves the graceful-fallback path, not just the happy path.

---

## 6. Known Limitations

- No auth UI exists yet — Supabase-mode testing requires manually establishing a session (see §5C). This is expected; wiring a login flow is out of scope for Phase 13B.
- `getOrCreateDefaultSeoWorkspace()` only ever creates **one** simple default workspace per user and never lets the UI choose among multiple existing workspaces — sufficient for this phase, revisit once multi-workspace UI exists.
- Several `seo_business_onboarding` text columns are nullable in the DB (e.g. `preferred_content_tone`) even though the form always supplies a value on save; reads default a null to a safe fallback (`"other"`/`"none"`) rather than crashing.
- `SeoWebsite.user_id` has no direct DB counterpart (Stage 1 `seo_websites` only stores `created_by`); the Supabase mapping reuses `created_by` for both fields. Informational only — not used for authorization anywhere (RLS is the actual authorization boundary).
- No crawler, sitemap fetch, robots check, or real GSC/GA4/CMS/GBP integration — connection status stays a placeholder in both modes.
- Storage-object cleanup, audit/recommendation/approval/content-studio wiring, dashboard wiring, and admin-preview wiring are all explicitly out of scope for this phase.
- **Fixed post-13F (small cleanup):** `fetchSupabaseOnboardingByWebsiteId` originally issued its Supabase query without an auth/UUID gate, so in Supabase mode with no session (or with a mock-mode website id from an earlier fallback) it could still hit PostgREST and get a benign 400 back before falling back to mock. Both onboarding functions now call `requireAuthenticatedUser()` and `requireValidUuid()` (new helpers in `supabaseServiceUtils.ts`) before any table query, matching the gating already used by every other wired service (audit, recommendation, approval, content studio, dashboard).

---

## 7. Next Recommended Phase

**Phase 13C: wire `auditService` + `recommendationService`** against Stage 2 (`seo_audit_runs`, `seo_audit_issues`, `seo_recommendations`), using the same adapter pattern and the now-proven `seoWorkspaceService` workspace resolution. Continue down the order in `SERVICE_LAYER_WIRING_PLAN.md` §6.
