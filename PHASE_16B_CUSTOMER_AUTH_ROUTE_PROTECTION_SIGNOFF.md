# Phase 16B — Customer Authentication & Route Protection Sign-Off

**Status: Implemented and TEST-validated.** Customer-facing login + `/seo/*`
route protection are wired on the existing Supabase Auth, workspace,
module-access and website-resolution primitives. **RLS + guarded RPCs remain the
authoritative authorization layer;** route protection is navigation/UX security
only. **No database, migration, RLS, or RPC change; production untouched.**
**Date:** 2026-07-13. **TEST project:** `Digi_SEO_Test` (`snyzotgwwfomgafrsvfm`).

## Approved architecture

Hybrid transition auth (Phase 16A, `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md`):
standalone Supabase Auth for the MVP + `ProtectedRoute`; a future parent-identity
adapter remains additive; no separate identity DB; no parent integration; SEO
role strings unchanged. Crawler implementation was **not** started.

## Scope (login only)

Sign-in for existing Supabase users. **Not** in scope (clearly messaged on the
login page): self-service signup, password reset, email verification, user
creation/reset, billing, invitations.

## Route classification (implemented in `SeoRoutes.tsx`)

- **Public + chromeless:** `/seo/login` (customer sign-in; rendered outside the
  app shell; not the dev harness).
- **Development-only** (`import.meta.env.DEV` only; excluded from production
  builds, preserved for dev workflows): `/seo/dev/auth-test`,
  `/seo/dev/supabase-readiness`.
- **Setup (auth + module access; no workspace/website prerequisite,
  `allowSetup`):** `/seo/onboarding`, `/seo/websites`.
- **Auth-only feature routes:** `/seo/dashboard`, `/seo/approvals`,
  `/seo/support`, `/seo/settings`.
- **Website-scoped (`requireWebsite`):** `/seo/audit`, `/seo/keyword-research`,
  `/seo/competitor-analysis`, `/seo/content-gaps`, `/seo/blog-briefs`,
  `/seo/content-studio`, `/seo/page-optimizer`, `/seo/page-performance`,
  `/seo/decline-diagnosis`, `/seo/off-page`, `/seo/ai-visibility`,
  `/seo/roadmap`, `/seo/reports`.
- **Admin (`requireGlobalAdmin`):** `/seo/admin-preview` (gated by
  `seo_is_global_admin` RPC; final destination is the parent Admin Panel,
  deferred).

## Session-resolution design

One centralized resolver `useSeoAccess()` composes the existing `AuthContext`
session, the `has_seo_module_access` RPC, and `getCurrentSeoWorkspace()` into a
single derived status: `loading | no-session | no-module-access | no-workspace |
error | ready`. It deliberately does **not** resolve/gate on `seo_role` — role
and action gating stay in the pages/components + RLS/RPC (locked Stage 6 logic is
not duplicated). It exposes only non-secret state (user id, safe email, module
access, workspace id); **no tokens/refresh-tokens/session objects/cookies/
passwords are logged or exposed.** Session persistence + token refresh use
Supabase's own `getSession` + `onAuthStateChange` (existing `AuthContext`).

**Cross-user safety:** `SessionSync` clears all cached TanStack Query data and
the active-website selection whenever the authenticated user changes to a
different user (or signs out); first-load / same-user refresh does not clear, so
legitimate selections persist. The `seo_active_website_id` storage key is
**unchanged** (not renamed).

## Protected-route states

Loading (branded skeleton, no protected-content flash, no premature redirect) →
no-session (redirect to login, safe `returnTo` preserved) → no-module-access
(access-required state + sign-out + retry, no page content) → no-workspace
(setup routes render; others → `/seo/onboarding`) → no-active-website
(website-scoped routes → `/seo/websites`; setup routes reachable) → ready
(render; existing role-based action behaviour preserved) → recoverable error
(retry, sign-out; never a silent sign-out or mock false-success).

## Module / workspace / website behaviour

- **Module access:** existing `has_seo_module_access` RPC only (no duplicated
  frontend logic); cached per session, invalidated on user change / sign-out /
  explicit retry (query key includes the user id).
- **Workspace/website:** reuses `getCurrentSeoWorkspace()` (deterministic) and
  `useResolvedActiveWebsite()` (auto-selects the first accessible website and
  re-validates a stored selection). No second resolution algorithm; no DB record
  changed. A website inaccessible to the new user is cleared/re-resolved.

## Deep-link security

`sanitizeReturnPath()` accepts only internal `/seo/...` paths; rejects absolute
URLs, protocol-relative (`//`), `://`, backslashes, `..` traversal, and the login
path itself (loop prevention); preserves query + hash when safe. Post-login
navigates to the sanitized `returnTo`; if that route's prerequisites are missing,
its `ProtectedRoute` routes to the appropriate setup page. No credentials/session
values are ever placed in the URL.

## Sign-out behaviour

`useSeoSignOut()` calls Supabase sign-out, then clears user-scoped query cache +
active-website selection and navigates to `/seo/login`. It treats the known
global-revocation `ERR_ABORTED` as success when the local session is actually
cleared (verified via `getSession`), and reports a genuine failure only if the
local session persists. It never inspects/prints session storage. Wired into the
existing `Header` (no shell redesign).

## Mock-mode behaviour

`ProtectedRoute` fully bypasses in mock mode (no hooks, unconditional render):
no session/module-access/workspace/role required; feature routes are directly
accessible; campaign selection + creation remain available; no login redirect.
The login route renders an explanatory "mock mode — sign-in not required" state
(non-mandatory). `.env.local` was not modified.

## Admin-preview handling

Gated by the existing `seo_is_global_admin` RPC (Stage 1 SECURITY DEFINER helper,
PostgREST-callable, reads `public.profiles`, defaults to `auth.uid()`) — **not**
inferred from `seo_workspace_members.seo_role` or a UI selector. A safe callable
capability check exists, so no gap/blocker.

## Static tests

- `npx tsc --noEmit -p tsconfig.app.json` → **PASS** (clean).
- `npm run build` → **PASS** (pre-existing chunk-size advisory only).
- Source invariants: no service-role key; no token/session logging; no hardcoded
  password; no direct Stage 6 status update; existing Stage 6 RPC wiring
  unchanged; no migration changed; no locked internal implementation changed;
  mock mode supported; dev routes gated behind `import.meta.env.DEV`.

## Browser tests (TEST, authenticated via the new customer login page)

- **Anonymous** deep link `/seo/off-page` → **redirect to `/seo/login?returnTo=
  %2Fseo%2Foff-page`**, login shown, no protected content leaked. ✅
- **Owner** sign-in via the customer login → session resolved → module access +
  workspace + website → **restored to the `/seo/off-page` deep link** →
  **refresh persists** → representative protected + locked routes
  (`page-performance`, `ai-visibility`, `dashboard`) render → **sign out** →
  `/seo/login` → protected route **inaccessible** afterward; 0 console errors. ✅
- **Client** sign-in → protected routes **readable** (9 opportunities) with the
  **locked Stage 6 client selection gate still disabled** (route protection
  granted **no new permissions**); 0 create requests. ✅
- **Admin-preview:** anonymous → login redirect; **owner and client (both
  non-global-admin) → denied** ("Admin access required"). ✅
- **Mock mode** (throwaway `:8091`, `.env.local` untouched): protected routes
  directly accessible, no login redirect, off-page works, campaign selection +
  **creation works**, AI Visibility mock renders, **0 Supabase writes**. ✅

## Known limitations (honest)

- **Global-admin ALLOW branch not live-tested:** none of the four TEST users are
  global admins (`seo_is_global_admin` = false for all), so the positive
  admin-preview branch is covered by code logic only (`if (!isGlobalAdmin) deny;
  else render`), not a live browser run. No user was created/promoted.
- **No-module-access / no-workspace / no-active-website states not live-tested:**
  the TEST users all have module access + a workspace + a website, and TEST data
  was intentionally not mutated to manufacture these states. They are covered by
  the `useSeoAccess`/`ProtectedRoute` state logic and reviewed for redirect-loop
  safety (setup routes stay reachable), but not exercised live.
- **No unit-test framework exists** in the repo; focused state coverage is via
  the browser matrix + code review rather than added unit tests (no framework
  was introduced).
- Pre-existing benign observations unchanged: favicon 404, sign-out global
  `ERR_ABORTED`, ~20px mobile overflow. The login page is mobile-responsive
  (centered, `max-w-sm`).

## Files changed

**Application (new):** `src/services/supabase/seoAccessService.ts`,
`src/routes/routeAccess.ts`, `src/hooks/useSeoAccess.ts`,
`src/hooks/useSeoSignOut.ts`, `src/components/auth/SessionSync.tsx`,
`src/components/auth/RouteStates.tsx`, `src/routes/ProtectedRoute.tsx`,
`src/pages/seo/SeoLoginPage.tsx`.
**Application (edited, additive):** `src/services/supabase/supabaseTypes.ts`
(added `seoIsGlobalAdmin` RPC constant), `src/components/layout/Header.tsx`
(customer sign-out), `src/App.tsx` (mount `SessionSync`), `src/routes/SeoRoutes.tsx`
(login route + shell layout route + `ProtectedRoute` wrappers + dev-only dev
routes).
**No locked-module internal file changed** (locked routes were only *wrapped*).
**No migration/SQL/test file changed** (no test framework exists).

## Database / API impact

**None.** No migration, RLS, RPC, table/column/index/trigger/constraint change;
no auth users created/reset; no TEST/production data change. Frontend additions
use existing Supabase contracts only (`signInWithPassword`, `getSession`,
`onAuthStateChange`, `signOut`, `has_seo_module_access`, `seo_is_global_admin`).

## Backward compatibility

Preserved: existing URLs (only `/seo/login` + protection wrappers added), Supabase
users/IDs, workspace memberships, roles, RPCs, service signatures, read-shape
types, status/action values, existing deep links, mock mode, and both module
locks. Locked Page Performance + Stage 6 behaviour verified unchanged (routes
render; client action restrictions intact).

## Production status

Production was never accessed or modified.

## Exact next milestone

`Crawler Phase 1 — crawl-job data contract and additive migration design`
(per `CRAWLER_PHASE_1_IMPLEMENTATION_PLAN.md`). **Not started in this task.**
