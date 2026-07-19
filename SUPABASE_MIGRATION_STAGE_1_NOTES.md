# SEO Backend — Stage 1 Migration Notes (Phase 12C)

**Status:** SQL written + reviewed + **test-verified**. Applied and verified on a **fresh test Supabase project** (see checkpoint below). **Production has NOT been touched.**

## ✅ Test Verification Checkpoint (fresh test Supabase project)

- [x] Dry-run passed
- [x] Applied to fresh test Supabase project (`…120001` → `…120003`)
- [x] 9 tables visible: `user_module_access`, `seo_plan_limits`, `seo_subscriptions`, `seo_usage_events`, `seo_workspaces`, `seo_workspace_members`, `seo_websites`, `seo_business_onboarding`, `seo_connection_status`
- [x] Plan limits visible (basic/standard/pro rows in `seo_plan_limits`)
- [x] RLS = `true` for all 9 tables
- [x] Policies visible on all 9 tables (Table Editor / `pg_policies`)
- [x] 6 helper functions visible: `set_updated_at`, `seo_is_global_admin`, `has_seo_module_access`, `is_seo_workspace_member`, `seo_role_in`, `can_manage_seo_workspace` (plus the `seo_workspace_add_owner_member` trigger function)

**Production status:** These migrations are **test-verified but not production-applied**. Production apply should happen only after: (1) confirming the target project is the correct shared Digibility Supabase project, (2) a backup/branch strategy is in place, and (3) a final review/sign-off.

---

Migration files (in `supabase/migrations/`, run in order):
1. `20260711120001_seo_stage1_access_module.sql`
2. `20260711120002_seo_stage1_workspaces.sql`
3. `20260711120003_seo_stage1_websites.sql`

**Post-write review fixes (Phase 12C review):**
- **Owner bootstrap** — an `AFTER INSERT` SECURITY DEFINER trigger on `seo_workspaces` auto-creates the owner's `seo_workspace_members` row (role `owner`). Without it, a non-admin owner hit an RLS deadlock (couldn't add themselves as the first member). Mirrors Core's `handle_new_user()` convention. `seo_workspaces` SELECT also now includes `owner_user_id = auth.uid()`.
- **Subscription writes are global-admin-only in Stage 1** (was: any user could self-provision an arbitrary paid `plan_tier` — billing bypass). Self-serve/owner provisioning returns with the billing + service-role (webhook) flow, which bypasses RLS.

---

## What Stage 1 creates

**Tables (9)**
- Access/module: `user_module_access`, `seo_plan_limits` (seeded basic/standard/pro), `seo_subscriptions`, `seo_usage_events`.
- Workspace: `seo_workspaces` (+ nullable `core_workspace_id`/`core_profile_id` mapping seams), `seo_workspace_members` (roles: owner/admin/team_member/client).
- Website foundation: `seo_websites` (anchor), `seo_business_onboarding` (1:1), `seo_connection_status` (1:1).

**Helper functions (SECURITY DEFINER, `search_path=public`)**
- `set_updated_at()` (idempotent copy of Core's), `seo_is_global_admin(uid)` (reads `profiles.role`, guarded), `has_seo_module_access(uid)`, `is_seo_workspace_member(ws,uid)`, `seo_role_in(ws,roles[],uid)`, `can_manage_seo_workspace(ws,uid)`.

**Other:** `updated_at` triggers on all mutable tables; FKs (incl. forward-ref FKs added via idempotent `pg_constraint` guards); indexes on `user_id`/`workspace_id`/`website_id`/`website_url`/`module_name`/`status`; RLS enabled + policies on every table; safe plan-limit seed rows only.

## What Stage 1 intentionally does NOT create

- No auth tables (reuses Core `auth.users` + `profiles`).
- No audit/recommendation/approval, content studio, performance, off-page, AI, competitor, roadmap, support, report, or admin tables (Stages 2–10).
- No payment/gateway logic (`seo_subscriptions.external_ref`/`status` are manual/seed only).
- No real GSC/GA4/CMS/GBP integration (connection tables hold status placeholders).
- No production/customer seed data.
- No usage-enforcement RPC yet (events table + period fields exist; the enforce-on-write guard RPC lands with the metered features in later stages).
- No changes to any Core/reference table or migration.

## How it supports SEO-only users

Access gates on `user_module_access(module='seo', is_active)` + `has_seo_module_access()`, never on Visibility Management. A user with only an SEO row (and no VM row) gets full SEO access. `seo_subscriptions.is_addon=false` = standalone; `true` = SEO added onto a VM account. RLS uses SEO membership + SEO module access exclusively.

## How it supports future Digibility integration

- `seo_workspaces.core_workspace_id` / `core_profile_id` are nullable seams to map onto a future Core workspace/profile model with no data migration.
- Reuses Core `auth.users`, `profiles.role` (via `seo_is_global_admin`), and the `set_updated_at()` convention.
- Global admin (`super_admin`/`admin`) already sees all SEO data → SEO admin can mount inside the existing Digibility Admin Panel later.
- `website_id` = source of truth; `website_url` snapshot on child tables preserves history if a URL changes.

## Assumptions (confirm before applying)

1. Migrations run in the **shared Digibility Supabase project** where `auth.users` and `public.profiles` exist. (`seo_is_global_admin` is guarded to also survive a standalone project — returns `false` if `profiles` is absent.)
2. Core roles stay `super_admin`/`admin` for global admin; SEO roles are separate and live only in `seo_workspace_members`.
3. `user_module_access` does not already exist in Core with a different shape (found none). Created `IF NOT EXISTS`.
4. Timestamp prefix `20260711…` sorts after the latest Core migration (`20260710200000`).
5. SEO subscription is user-owned; workspace managers get read visibility only (Stage 1). Workspace-scoped billing management can be added later.

## Review checklist before applying

- [ ] Confirm target = shared Core Supabase project; `public.profiles` + `public.set_updated_at()` present (or accept guarded fallback).
- [ ] Confirm no existing `user_module_access` table with a conflicting shape.
- [ ] Confirm filename timestamps sort after all Core migrations.
- [ ] Review RLS: client can **read** website/onboarding/connection but cannot write setup, manage members, or manage subscriptions; team_member can create/update website setup + onboarding + connection; owner/admin manage workspace/members/websites; **subscription writes are global-admin-only in Stage 1** (owner/self-serve provisioning arrives with billing); global admin sees all.
- [ ] Confirm plan-limit seed values (`-1` = unlimited/priority) match the product plan registry.
- [ ] Confirm `ON DELETE` behavior (workspace delete cascades websites/onboarding/connection; subscription/usage FKs `SET NULL`).
- [ ] Dry-run against a scratch/branch database (Supabase migration diff) — **do not** apply to production in this phase.
- [ ] Verify helper functions are `SECURITY DEFINER` and `search_path=public` (prevents RLS recursion + search-path injection).

## Open items carried forward (non-blocking)

- Content Studio file uploads → Supabase Storage bucket (metadata-only in DB) — decide in the Content Studio stage.
- Usage-period reset uses `seo_subscriptions.period_start`/`period_end` (snapshotted onto `seo_usage_events`); the rollup/enforcement RPC is deferred to metered-feature stages.

## Next step

Stage 1 is test-verified (see checkpoint above) and Stage 2 has since been built on top of it. Remaining step: **production apply**, only after confirming target project, backup/branch strategy, and final review.
