# Cross-Project Digibility → SEO Single Sign-On

**Status (2026-07-20): IMPLEMENTED IN SOURCE — NOT DEPLOYED OR LIVE-TESTED.**
Production remains untouched. The additive migrations have not been applied,
the `seo-bridge` Edge Function has not been deployed, and no production secrets
were configured in this task.

## Architecture

- Digibility Core Supabase remains the canonical identity, profile, purchase,
  suspension, and module-entitlement system.
- SEO uses a separate Supabase project for all SEO data and downstream SEO
  sessions.
- A customer signs in only at Digibility. Entitled users launch SEO from the
  Digibility header. **Current entitlement policy: all users** (existing users
  backfilled + new signups auto-granted; see
  `20260720122000_seo_grant_all_users.sql`). The entitlement mechanism still
  supports purchase-gating if that decision changes — see step 7 below.
- The Core Edge Function creates a 60-second, single-use launch code. On redeem,
  it rechecks entitlement, provisions the SEO Auth user with the same UUID,
  mirrors minimum identity/access data, and creates an admin magic-link token
  without sending email.
- The SEO bridge page exchanges that token through `verifyOtp`, producing a
  normal SEO Supabase session with refresh-token support. Existing `auth.uid()`
  RLS, workspace membership, roles, RPCs, crawler behavior, and mock mode remain
  unchanged.

## Source changes

### Digibility UI Kit

- `supabase/migrations/20260720120000_module_entitlements_seo_bridge.sql`
  adds `user_module_access`, `has_module_access`, a service-role-only billing
  hook (`set_user_module_access`), the private launch-code ledger, and atomic
  code claim RPC.
- `supabase/migrations/20260720122000_seo_grant_all_users.sql` implements the
  current all-users policy: backfills every existing user and adds a
  signup-safe `auth.users` trigger (`grant_seo_module_on_signup`) that
  auto-grants SEO to new accounts. Failure never blocks signup; fully
  reversible back to purchase-gating.
- `supabase/functions/seo-bridge/index.ts` implements `launch` and `redeem`.
- `src/components/layout/SeoModuleLauncher.tsx` adds the entitlement-gated SEO
  header switch. Missing migration/function/access fails closed and does not
  affect Visibility.
- `src/lib/seoModuleLaunch*.ts` provides launch, safe-return-path, and
  post-login intent handling.
- `LoginPage.tsx` and Google `AuthCallbackPage.tsx` resume an SEO deep link
  after the canonical Digibility login; bridge failure falls back to the
  existing Digibility route. Auto-launch requires a fresh `seoReturnTo` intent
  (session flag) so stale pending paths cannot re-open SEO after logout.
- Linked logout: Digibility `/logout` clears Core session + pending SEO intent,
  then cascades to SEO `/seo/auth/logout` when `SEO_APP_URL` is set (DEV
  default `http://localhost:8090`). SEO Sign out clears the SEO session and
  cascades to Digibility `/logout?source=seo` (never `seoReturnTo`), stopping
  the previous re-login loop.

### SEO module

- `supabase/migrations/20260720121000_seo_cross_project_identity_bridge.sql`
  adds the minimum `seo_identity_profiles` mirror and extends
  `seo_is_global_admin` without removing its existing shared/test-project path.
- `src/pages/seo/SeoBridgePage.tsx` redeems one-time codes and establishes the
  downstream session.
- Production bridge configuration redirects `/seo/login` to Digibility.
  Existing password login remains available only as a non-breaking TEST/local
  fallback when bridge configuration is absent. Mock mode remains unchanged.
- The SEO header includes a Visibility switch when the Digibility URL is
  configured.

## Localhost verification (development)

Use this path to exercise the full Digibility → SEO handoff on a developer
machine without touching production origins.

Ports: Digibility UI `http://localhost:8080`, SEO UI `http://localhost:8090`.

1. Apply Digibility migrations
   `20260720120000_module_entitlements_seo_bridge.sql` and
   `20260720122000_seo_grant_all_users.sql` to the **DevApp** project (or a
   local linked Supabase stack).
2. Apply SEO migrations including
   `20260720121000_seo_cross_project_identity_bridge.sql` to the dedicated
   SEO TEST/Dev project.
3. No per-user grant needed — `20260720122000_seo_grant_all_users.sql`
   backfills every existing user and auto-grants new signups. (Only if you
   have NOT applied that migration, grant one user manually with
   `select public.set_user_module_access('<your-user-uuid>', 'seo', true, '{}'::jsonb);`.)
4. Serve the bridge locally from the Digibility UI repo:
   ```bash
   cp supabase/functions/seo-bridge/.env.local.example supabase/functions/seo-bridge/.env.local
   # fill SEO_SUPABASE_* (+ Core keys if not injected by the CLI)
   supabase functions serve seo-bridge --env-file supabase/functions/seo-bridge/.env.local
   ```
   Origin secrets may be comma-separated, e.g.
   `DIGIBILITY_APP_ORIGIN=http://localhost:8080,http://127.0.0.1:8080` and
   `SEO_APP_ORIGIN=http://localhost:8090,http://127.0.0.1:8090`.
   Loopback host aliases are expanded automatically. When Digibility’s
   `Origin` is localhost, launch redirects to the localhost SEO origin.
5. Digibility `.env` (local):
   - existing DevApp `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`
   - `VITE_SEO_BRIDGE_URL=http://127.0.0.1:54321/functions/v1/seo-bridge`
     (optional override; leave blank to call a *deployed* DevApp function)
6. SEO `.env` (local):
   - SEO TEST project URL + anon key
   - `VITE_SEO_DATA_MODE=supabase`
   - `VITE_DIGIBILITY_APP_URL=http://localhost:8080`
   - `VITE_DIGIBILITY_BRIDGE_URL=http://127.0.0.1:54321/functions/v1/seo-bridge`
   - `VITE_DIGIBILITY_ANON_KEY=<Digibility DevApp anon key>`
7. Run Digibility (`npm run dev` → :8080) and SEO (`npm run dev` → :8090).
8. Sign in on Digibility, confirm the header **SEO** button appears, launch,
   and confirm `/seo/auth/bridge` establishes a refreshable SEO session.

HTTP launch URLs are accepted only for `localhost` / `127.0.0.1`. Non-loopback
HTTP launch URLs are rejected by the Digibility client.

## Required deployment order

1. Create the dedicated production SEO Supabase project.
2. Apply the existing SEO migrations in order, followed by
   `20260720121000_seo_cross_project_identity_bridge.sql`, using the normal
   production approval/backup gates.
3. Apply Digibility migrations
   `20260720120000_module_entitlements_seo_bridge.sql` and (for the current
   all-users policy) `20260720122000_seo_grant_all_users.sql`.
4. Deploy the Core `seo-bridge` Edge Function with `verify_jwt=false` (the
   function validates launch JWTs itself; redeem uses a single-use code).
5. Configure Edge Function secrets (comma-separated origins allowed):
   - `SEO_SUPABASE_URL`
   - `SEO_SUPABASE_SERVICE_ROLE_KEY`
   - `SEO_APP_ORIGIN=https://seo.digibility.com`  
     (optionally append `,http://localhost:8090` only on a **DevApp**
     function used for local testing — never on production)
   - `DIGIBILITY_APP_ORIGIN=https://app.digibility.com`  
     (same rule for optional localhost entries on DevApp only)
6. Build/deploy SEO with:
   - `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` = SEO project
   - `VITE_SEO_DATA_MODE=supabase`
   - `VITE_DIGIBILITY_APP_URL=https://app.digibility.com`
   - `VITE_DIGIBILITY_BRIDGE_URL=https://<core-ref>.supabase.co/functions/v1/seo-bridge`
   - `VITE_DIGIBILITY_ANON_KEY` = Core public anon/publishable key
7. Entitlement policy — current default is **all users** via
   `20260720122000_seo_grant_all_users.sql` (existing users backfilled, new
   signups auto-granted by a signup-safe trigger). No per-user action needed.
   To switch to **purchase-gated** later: drop the signup trigger + function,
   optionally deactivate the `source = 'auto_grant_all_users'` rows, and have
   the trusted billing backend call
   `set_user_module_access(user_id, 'seo', true, metadata)` on
   purchase/renewal and `false` on cancellation/refund/suspension. Full revert
   steps are documented in the migration header.
8. Run the acceptance matrix below before broader rollout.

## Security invariants

- Neither service-role key is shipped to either browser.
- Passwords and Digibility sessions are never copied to SEO.
- Launch codes are random, SHA-256 hashed at rest, one-time, and expire in 60s.
- Entitlement and account status are checked at launch and again at redeem.
- Return paths accept internal `/seo/*` paths only.
- The SEO user is created with the Digibility UUID through the supported Admin
  API; existing SEO foreign keys and RLS remain valid.
- The SEO module has no production public signup/login when bridge config is
  supplied.

## Verification completed locally

- SEO: 13 unit tests pass; TypeScript and production build pass.
- Digibility UI: 101 unit tests pass; TypeScript and production build pass.
- New URL/response tests cover open-redirect rejection, bridge-route loop
  rejection, malformed launch payloads, and safe deep-link preservation.
- Full-repo Digibility lint remains red because of the repository's large
  pre-existing lint backlog. No IDE diagnostics were introduced in changed
  files; the one new lint finding was fixed.

## Deployment acceptance still required

- Email/password Digibility login → SEO launch → refresh persistence.
- Google Digibility login → pending SEO launch → refresh persistence.
- Under the current all-users policy: every signed-in user sees the SEO switch
  and can launch; a newly signed-up user is auto-granted and can launch.
- SEO users launch successfully with the same UUID as Digibility.
- Digibility Log out → both apps require login again after reload (linked
  logout cascade via `/logout` → `/seo/auth/logout`).
- SEO Sign out → Digibility also signed out; reload of either app stays logged
  out; no auto-relaunch of SEO.
- Visibility header switch (SEO → Digibility) keeps Digibility session (app
  switch, not logout).
- Used/expired/tampered codes fail without creating a session.
- (Only if reverting to purchase-gating) deactivating entitlement through the
  billing hook denies a new launch; the header switch disappears.
- Owner/admin/team_member/client SEO RLS behavior and locked Stage 6/crawler
  regressions remain PASS against the dedicated SEO TEST/STAGING project.
