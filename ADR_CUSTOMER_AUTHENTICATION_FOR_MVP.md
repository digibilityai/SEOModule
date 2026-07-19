# ADR — Customer Authentication & Route Protection for the MVP (Phase 16A)

**Status:** **Approved + IMPLEMENTED (Phase 16B, 2026-07-13).** The Option C
hybrid decision below was approved and the login-only customer authentication +
`/seo/*` route protection are implemented and TEST-validated — see
`PHASE_16B_CUSTOMER_AUTH_ROUTE_PROTECTION_SIGNOFF.md`. RLS + guarded RPCs remain
authoritative; no DB/RPC/RLS change; production untouched. The auth
implementation is **not module-locked** (deferred). **Original decision date:**
2026-07-13.
**Scope:** the standalone Digibility SEO module
(`/Users/amitguptaamit/gitrepo/user_guide/Digibility-SEO-Module`).
**Related:** `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` (Option B),
`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` (§B, §F, §G, §L — no-BFF, Supabase-direct,
RLS-authoritative), `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`,
`CRAWLER_PHASE_1_IMPLEMENTATION_PLAN.md`.

## Context / repository evidence

- **No `ProtectedRoute` exists** — `src/routes/SeoRoutes.tsx` mounts every
  `/seo/*` route unguarded, with a comment that auth/role gating "will be added
  once the login flow is wired up in a later phase."
- **No customer login UI** — the only sign-in path is the dev harness
  `src/pages/seo/dev/SupabaseAuthTestPage.tsx` (`signInWithPassword` via
  `supabaseDevAuthService.ts`).
- **Session/role/access primitives already exist:** `getCurrentSeoRole()`
  (`seoWorkspaceService.ts`, uses `requireAuthenticatedUser` +
  `seo_workspace_members.seo_role`), the `has_seo_module_access` RPC,
  `useResolvedActiveWebsite()` hook, and `seo_active_website_id` (localStorage).
- **Authorization already lives in the data layer** — RLS + `SECURITY DEFINER`
  RPCs are authoritative (validated by the Stage 6 SQL scripts + Phase 15C/15D).
- **Mock mode is permanent** — role gating is skipped when `roleGatingActive`
  is false (mock has no real `seo_role`).
- **Parent-Digibility identity/session contract is NOT confirmed** in this repo
  (no cross-app token/session integration present).

## Decision

**Adopt Option C — Hybrid transition authentication.**

- Ship **standalone Supabase Auth** for the MVP: a customer-facing login using
  the existing Supabase client + `signInWithPassword` (and the existing
  password-reset/session primitives), replacing the dev-only harness as the
  entry point.
- Add **route-level `ProtectedRoute`** as navigation/UX security **on top of**
  (never instead of) RLS + guarded RPCs, which remain the authoritative
  authorization layer.
- Define, but do not yet build, a **thin identity adapter seam** so a future
  parent-Digibility SSO / shared session can be introduced **additively**
  without changing SEO user IDs, `seo_workspace_members`, roles, or RLS.
- **No separate custom identity database.** **No change to SEO role strings**
  (`owner`/`admin`/`team_member`/`client`).

### Rejected alternatives

- **Option A (standalone only, no future seam):** rejected — leaves parent
  integration as an unplanned rework; the adapter seam costs almost nothing now
  and de-risks later SSO.
- **Option B (parent Digibility auth immediately):** **rejected for MVP** — the
  cross-application session/token contract is **not confirmed** in-repo, so
  adopting it now risks duplicate users / conflicting workspace identities. Per
  the task, parent integration is not recommended until the identity+session
  contract is confirmed. It remains the **future additive** path enabled by the
  Option C adapter seam.

### Per-criterion assessment (summary)

| Criterion | A (standalone) | B (parent now) | **C (hybrid) ✅** |
|---|---|---|---|
| Customer experience | good | best if contract exists | good; smooth later SSO |
| Time to MVP | fast | blocked on contract | **fast** |
| Security | RLS-authoritative | depends on contract | **RLS-authoritative** |
| Existing-data / user-ID / workspace compat | full | risk of dupes | **full** |
| RLS / API compat | unchanged | unchanged if IDs align | **unchanged** |
| Parent dependency | none | hard dependency | **none now, additive later** |
| Migration risk | low | high | **low** |
| Rollback | easy | hard | **easy** |
| Duplicate-identity risk | none | real | **none** |
| Future SSO path | rework | native | **designed-in (additive)** |

## Route-protection contract (behavioural spec — not implemented)

Frontend protection is **navigation + UX only**; RLS/RPC checks remain
authoritative (a bypass of the UI still hits RLS and fails safely).

- **Routes requiring authentication:** all `/seo/*` product routes (dashboard,
  websites, onboarding, approvals, audit, keyword-research, competitor-analysis,
  content-gaps, blog-briefs, content-studio, page-optimizer, page-performance,
  decline-diagnosis, off-page, ai-visibility, roadmap, support, reports,
  settings, admin-preview).
- **Dev routes** (`/seo/dev/*`): **development-only** — mounted only when a dev
  flag is set (e.g. `import.meta.env.DEV`); excluded from production builds/nav.
  The dev auth harness must not be the customer login.
- **No session:** redirect to the login route; **preserve the deep-link**
  (return-to path) and restore it after successful login.
- **Authenticated but no SEO module access** (`has_seo_module_access` false):
  show an "access required / request access" state; do not dump them into an
  empty product shell. (RLS already returns nothing.)
- **No SEO workspace:** show a "no workspace" state (or onboarding entry) —
  not a crash/empty grid.
- **No active website:** route to website selection / onboarding; the existing
  `useResolvedActiveWebsite` fallback continues to apply once a website exists.
- **Role-based visibility vs action:** page **visibility** may hide routes a
  role can never use, but **action permissions stay enforced by RLS/RPC +
  existing UI role gating** (e.g. `CampaignActionButton`, the campaign-create
  gate) — the locked Stage 6 behaviour is unchanged.
- **Loading (session resolving):** render a non-blocking loading state, never a
  flash of protected content and never a premature redirect.
- **Error/retry:** auth/network errors show a retry affordance; never a silent
  logout or a false-success.
- **Redirect + deep-link:** unauthenticated deep link → login → back to the
  original path.
- **Supabase mode:** full protection as above. **Mock mode:** unchanged —
  `roleGatingActive` is false, no real session required, product remains fully
  usable for development/demo (protection is a no-op gate in mock).
- **Admin preview** (`/seo/admin-preview`): remains a temporary internal
  read-only route; gate behind auth + an admin capability; final destination is
  the parent Digibility Admin Panel (deferred).

## Identity-adapter seam (future, additive)

Introduce a single indirection for "who is the current user + how did they
authenticate" (e.g. a `getCurrentIdentity()` provider) that today wraps Supabase
Auth and can later resolve a parent-Digibility session — **without** changing
`auth.users` IDs, `seo_workspace_members`, roles, RLS, or read-shape types. This
is a *design intention* recorded here; it is not built in this ADR.

## Impact

- **Database:** none now. Future auth work is additive (no schema change needed
  for standalone Supabase Auth; any profile/session mapping would be additive).
- **API / RPC / RLS:** none — RLS + existing RPCs are reused as-is.
- **Frontend:** future additive work only (`ProtectedRoute` wrapper + a login
  page + dev-route gating in `SeoRoutes.tsx`). No change to locked modules.
- **Backward compatibility:** existing Supabase users, user IDs, workspace
  memberships, roles, RPCs, service signatures, read-shape types, status/action
  values, mock mode, and locked behaviour all preserved.

## Assumptions / unknowns / approval gates

- **Assumption:** Supabase Auth remains the standalone identity provider for MVP.
- **Unknown / gate:** the parent-Digibility identity + session contract (blocks
  Option B; keeps it deferred).
- **Gate:** self-service signup vs invite-only for MVP; password-reset/email
  flows; admin-capability model for admin-preview.
- **Gate:** operator approval of Option C before the first implementation task.

**No implementation performed. No application, migration, DB, or production
change in this ADR.**
