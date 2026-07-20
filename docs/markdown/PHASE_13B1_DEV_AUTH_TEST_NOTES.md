# Phase 13B.1 — Dev-Only Supabase Auth Test Harness

Adds a hidden developer page that signs in against the configured **test** Supabase project with a real email/password, so the Phase 13B Website Setup + Business Onboarding Supabase wiring can be exercised under real authenticated RLS — not just the graceful-fallback path. No customer-facing auth UI, no fake auth, no user creation, no service role key.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/supabaseDevAuthService.ts` — `getDevAuthState()`, `signInDevUser()`, `signOutDevUser()`, `refreshDevSession()`, `checkSeoAccessForCurrentUser()`, `checkWorkspaceAccessForCurrentUser()`.
- `src/pages/seo/dev/SupabaseAuthTestPage.tsx` — the dev-only page, route `/seo/dev/auth-test`.
- `PHASE_13B1_DEV_AUTH_TEST_NOTES.md` — this file.

**Changed:**
- `src/services/supabase/supabaseTypes.ts` — added `SEO_RPCS.hasSeoModuleAccess = "has_seo_module_access"` (the Stage 1 helper name); no other entries changed.
- `src/routes/SeoRoutes.tsx` — registered the new route (not added to any nav/sidebar list).
- `src/pages/seo/dev/SupabaseReadinessPage.tsx` — added one link to `/seo/dev/auth-test` in the description text (no other change).
- `SERVICE_LAYER_WIRING_PLAN.md` — status update (§9).

**Not changed:** any mock adapter, any customer-facing page, any migration, any auth context/provider, the reference Digibility app.

---

## 2. What the Dev Auth Harness Does

- Signs in / signs out a real Supabase Auth user via `supabase.auth.signInWithPassword()` / `supabase.auth.signOut()`, using the same anon Supabase client (`src/integrations/supabase/client.ts`) as every other frontend call.
- Shows current data mode, whether Supabase config is present, whether a session exists, and the current user's id/email.
- Checks SEO module access for the signed-in user:
  1. Tries `supabase.rpc("has_seo_module_access")` — the same `SECURITY DEFINER` helper Stage 1 RLS policies use internally.
  2. If that RPC call fails for any reason (e.g. not exposed on a given project), falls back to a direct `user_module_access` table read, which Stage 1 RLS explicitly permits for a user's own row (`user_module_access_select` policy).
- Checks workspace access via the existing `seoWorkspaceService.getCurrentSeoWorkspace()` (read-only — does not create anything).
- Lets a developer manually trigger the already-wired `websiteService.fetchWebsites`, `businessOnboardingService.fetchOnboardingByWebsiteId`, and `websiteService.addWebsite` to confirm the real Supabase read/write path (vs. the mock fallback) once signed in.
- Every check/action returns a plain result object with an optional `warning` string — nothing throws uncaught, nothing crashes the page.

---

## 3. What It Does NOT Do

- Does not create Supabase Auth users. A test user must already exist in the target project.
- Does not grant `user_module_access` or create/modify `seo_workspace_members` rows directly — those remain either pre-existing (test-project setup) or created only via the pre-existing `getOrCreateDefaultSeoWorkspace()` path inside the already-wired `websiteService`.
- Does not use the service role key anywhere.
- Does not store, cache, or log the entered password — it exists only as a local `useState` value cleared immediately after submit, passed straight into `supabase.auth.signInWithPassword()`.
- Does not add any customer-facing login/auth UI, role management UI, or navigation entry.
- Does not wire `auditService`, `recommendationService`, `approvalService`, or `contentStudioService`.
- Does not perform storage uploads or any real crawler/GSC/GA4/CMS/GBP check.
- Does not touch production — targets whatever `.env` points at (must be a test project).

---

## 4. How to Test Mock Mode

1. No `.env` needed (or `VITE_SEO_DATA_MODE=mock`).
2. `npm run dev`, visit `/seo/dev/auth-test`.
3. Expect: `Data mode: mock`, a warning that data mode is not "supabase", session/access rows show "(sign in first)" / not applicable. Page renders without error. Sign-in form is still usable if Supabase config happens to be present (mode and Supabase auth are independent — see §6), but "Test website/onboarding service" buttons will still use mock data regardless of sign-in state, since `VITE_SEO_DATA_MODE` — not sign-in state — controls the adapter.

---

## 5. How to Test Supabase Mode With Test Users

**Prerequisite:** `.env` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (test project), `VITE_SEO_DATA_MODE=supabase`.

1. Visit `/seo/dev/auth-test`. Expect `configured: yes`, `hasSession: no`, no crash.
2. **Invalid login:** enter a bogus email/password, click Sign in. Expect a friendly `Sign-in failed: ...` message, no raw stack trace, password field is empty again.
3. **Valid login, no SEO access yet:** sign in with a real test-project user that has no `user_module_access` row. Expect session/user id/email to populate; `SEO module access: no (via rpc|table)`; `Workspace access: no workspace yet`. No crash.
4. **Grant SEO access (test project only, via Supabase SQL editor — never from the frontend):**
   ```sql
   insert into public.user_module_access (user_id, module_name, is_active)
   values ('<user-id>', 'seo', true)
   on conflict (user_id, module_name) do nothing;
   ```
5. Click "Refresh / check". Expect `SEO module access: yes`.
6. Click "Test website service" — first call creates a default workspace (Stage 1 owner-membership trigger fires) and reports `0 website(s) found`. Click "Create test website" (URL defaults to `https://example-dev-seo-test.local`, editable) — then "Test website service" again to confirm `1 website(s) found`.
7. Click "Test onboarding service" — expect "No onboarding record yet... (not a failure)".
8. Click "Sign out" — session clears, test results reset.

---

## 6. Required Test Project Prerequisites

- A test/staging Supabase project with Stage 1 (`…120001`–`…120003`) applied — see `BACKEND_MILESTONE_HANDOFF.md`.
- `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` for that project in `.env`.
- At least one test user already created in that project's Supabase Auth (email + password) — create via the Supabase Dashboard, not from this app.
- A `user_module_access` row for that user with `module_name='seo'`, `is_active=true` — insert via the Supabase SQL editor/dashboard (service-role context), not from the frontend.
- No pre-existing `seo_workspaces`/`seo_workspace_members` rows are required — `getOrCreateDefaultSeoWorkspace()` (already built in Phase 13B) creates one on first use once module access is granted.

---

## 7. Known Limitations

- `VITE_SEO_DATA_MODE` and "am I signed in" are independent — the sign-in form works whenever Supabase is configured, even in `mock` mode, since the harness is meant to let a developer establish a session ahead of flipping the data mode. The page warns clearly when data mode isn't `supabase`.
- The RPC-first / table-fallback SEO-access check assumes `has_seo_module_access` still has its default Postgres `PUBLIC` execute grant on the target project (Stage 1 never issues an explicit `GRANT`/`REVOKE` for it). If a project has since revoked that, the harness transparently falls back to the direct table read.
- Only one workspace per user is supported (same limitation as Phase 13B's `getOrCreateDefaultSeoWorkspace()`).
- This page intentionally has no route guard beyond `import.meta.env.DEV` — it is not a security boundary, only a discoverability one (matches the existing `/seo/dev/supabase-readiness` pattern). Do not deploy a `DEV`-mode build to a public/shared URL.
- Session persistence follows whatever `supabase-js` defaults to (localStorage) — signing in here also affects any other page in the same browser tab using the same Supabase client, which is expected for testing purposes.

---

## 8. Next Recommended Phase

**Phase 13C: wire `auditService` + `recommendationService`** against Stage 2, now with a working way (this harness) to test them under real authenticated RLS from the start, rather than adding auth tooling retroactively. Continue down the order in `SERVICE_LAYER_WIRING_PLAN.md` §6.
