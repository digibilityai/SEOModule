# SEO Stage 3 — Content Studio Verification Guide (TEST PROJECT ONLY)

How to verify the Stage 3 **Content Studio** backend (opportunities / plan / wireframe / drafts / comments / activity / assets + the `seo_content_transition` workflow RPC + private Storage bucket) on a **fresh Supabase TEST project** after Stage 1 + Stage 2 + Stage 3 migrations are applied. **Never run on production.** No app code is involved.

Script: `supabase/test/seo_stage3_content_studio_smoke_test.sql` (TEST ONLY, non-destructive to Core data).

## ✅ Execution record

- [x] Stage 1 (`…120001`–`…120003`) + Stage 2 (`…120004`–`…120006`) applied to a fresh test project — verified earlier (see the Stage 1/2 notes + `SUPABASE_STAGE_2_VERIFICATION_GUIDE.md`).
- [x] Stage 3 (`…120007`–`…120009`) applied on top — dry-run passed, then applied to the fresh test Supabase project.
- [x] **11 Content Studio tables visible**: `seo_content_opportunities`, `seo_content_keyword_plans`, `seo_content_competitor_summaries`, `seo_content_wireframes`, `seo_content_format_inputs`, `seo_content_drafts`, `seo_content_draft_sections`, `seo_content_section_revisions`, `seo_content_comments`, `seo_content_activity`, `seo_content_assets`.
- [x] **RLS = `true` for all 11 tables.**
- [x] **3 functions visible**: `seo_content_assert_same_workspace()`, `seo_content_client_can_see_draft()`, `seo_content_transition(uuid,text,text)`.
- [x] **Private `seo-content-assets` bucket visible** (`public=false`, 20 MB limit, 5-MIME allowlist).
- [x] **Stage 3 table policies visible** on all 11 tables.
- [x] **Stage 3 triggers visible** (`updated_at` + same-workspace guard triggers).
- [x] **Storage object policies visible** (`seo_content_assets_obj_select`, `seo_content_assets_obj_insert`).
- [x] `seo_stage3_content_studio_smoke_test.sql` executed on the test project — **all assertions reported `PASS`, no known `FAIL` lines** (a few `SKIP` lines are expected/acceptable only in §7g — the optional best-effort `storage.objects` insert test, see below).
- [x] **Production has NOT been touched.** Stage 1, Stage 2, and Stage 3 are **test-verified only**; no production apply.

**Production status:** Production apply should happen only after: (1) confirming the target project is the correct shared Digibility Supabase project, (2) a backup/branch strategy is in place, and (3) a final review/sign-off. **Service-layer wiring** (replacing mock adapters with these tables/RPC/bucket) remains a separate later phase.

---

## Prerequisites

1. A **fresh/disposable Supabase test project** with, applied in order:
   `…120001–120003` (Stage 1), `…120004–120006` (Stage 2), `…120007–120009` (Stage 3).
2. Run the script from the **SQL Editor as `postgres`** (the default). It uses `SET LOCAL ROLE authenticated` to simulate end users, which requires a role that can `SET ROLE authenticated` — `postgres` can.
3. **The same 5 test users** as the Stage-2 test (real `auth.users` rows are required; do **not** insert into `auth.users` by hand). If they already exist from Stage 2, reuse their UUIDs:
   - Dashboard → **Authentication → Users → Add user** (email + password, "Auto Confirm").
   - Roles: **owner**, **admin**, **team_member**, **client**, **nonmember**.
   - Copy each user's **UUID** (the `id` column).

### Optional — global-admin inspection
To also confirm a Digibility global admin can read all content across workspaces, on the test project run once:
```sql
UPDATE public.profiles SET role = 'admin' WHERE id = '<that-user-uuid>';
```
(`seo_is_global_admin` reads `profiles.role`.)

---

## How to run

1. Open `supabase/test/seo_stage3_content_studio_smoke_test.sql`.
2. Replace the 5 `REPLACE_WITH_*` placeholders at the top with the real user UUIDs.
3. Paste the **entire** script into the SQL Editor and run it **as one execution** (the top `set_config(...)` GUCs are session-scoped and must persist through the whole run).
4. Read results in the **Messages / Notices** tab: every check prints `PASS: …`. Any `FAIL:` (or an unexpected error) **raises and stops** — that is a real defect to investigate. `SKIP:` may appear only in §7g (optional Storage-object test) and is not a failure.

The script drops its two test-only helpers (`public._seo3_login`, `public._seo3_ct`) at the end and leaves the two Stage-3 test workspaces in place (see Teardown). It is **re-runnable**: all workflow/permission checks run inside `BEGIN;…ROLLBACK;`, so the seeded opportunity stays committed at status `idea`.

---

## What it verifies (maps to the request)

| # | Section | Checks |
|---|---|---|
| 1 | SETUP | Grants `user_module_access`; creates Stage-3 workspace **W1** (owner auto-added via Stage-1 trigger) + admin/team_member/client members + website; a 2nd workspace/website (**W2**) for the cross-workspace test; content **opportunity** (`idea`) with `workspace_id`+`website_id`+`website_url`; plan-layer children (keyword plan, competitor, wireframe, format input); a **draft** + 2 **sections** + 1 **revision** (service-role/system seed). Distinct `33333333-…` UUID prefix — no collision with the Stage-2 test. |
| 2 | Plan layer + integrity | Opportunity carries the anchor columns; owner/team_member **can** create plan rows; **client cannot** (RLS write = manager set); a W1 child pointing at the **W2** opportunity **raises** (same-workspace guard). |
| 3 | Internal workflow (`seo_content_transition`) | owner walks the full manager chain `idea→plan_ready→wireframe_in_progress→wireframe_internal_review→wireframe_approved→draft_in_progress→draft_internal_review→draft_approved→ready_for_manual_publish` (asserts each `new_status`); **every transition writes `seo_content_activity`** (count=8) with `actor_user_id`+`actor_role_snapshot`; also `send_*_client_review`, `request_*_changes`, `archive`; **invalid** transition and **unknown** action **raise**. No `published` status, no publish path. |
| 4 | Client actions | Client during `wireframe_client_review`: `client_approve_wireframe`, `client_reject_wireframe`, `request_team_review` (→ internal review), `request_expert_review` (activity only, no status change), `comment`. During `draft_client_review`: `client_approve_draft`, `client_reject_draft`. **Blocked** (all 9 manager-only actions rejected during client review); **comment rejected outside client review**; **client direct opportunity/status edit blocked** by RLS (0 rows). |
| 5 | Draft/section visibility | Client sees **no** draft/sections before a client-visible status (`idea` → 0); **manager sees them at all stages**; client **sees them during `draft_client_review`**; client **cannot** insert/update/delete drafts/sections/revisions; **revisions append-only for everyone** (owner update/delete → 0 rows). |
| 6 | Comments + activity | Append-only — direct UPDATE/DELETE affect **0 rows** for everyone (incl. owner); **client cannot forge** a direct activity insert (must use the RPC). Client comments only via the status-gated RPC (proven in §4). |
| 7 | Assets + Storage | Manager **can** insert asset metadata for **all 5 allowed MIME types**; **client cannot**; MIME CHECK **blocks** `svg`/`zip`/`x-msdownload`/`html`; workspace-scoped asset with NULL opportunity allowed; **soft-delete works, hard-delete blocked** (0 rows). Bucket `seo-content-assets` is **private** (`public=false`); **both** `storage.objects` policies present. §7g (optional, ROLLBACK): client `storage.objects` INSERT denied; owner allowed on a workspace-scoped path. |
| 8 | Non-member isolation | Non-member reads **0** opportunity/draft rows; **cannot** call the transition RPC (raises "Not a member"). |

### How authenticated users are simulated (safe)
Inside a transaction the script calls `public._seo3_login(<uuid>)` (sets `request.jwt.claim.sub` / `request.jwt.claims` so `auth.uid()` resolves to that user) with `SET LOCAL ROLE authenticated` (so RLS is enforced as a normal user, not the privileged editor). `SECURITY DEFINER` RPCs/helpers still see the simulated `auth.uid()`. Helper `public._seo3_ct(uid, opp, action, note)` logs in as `uid` and runs `seo_content_transition` — used to drive an opportunity through statuses and to switch actor (owner → client) within one rolled-back transaction. Because status changes are transactional, no committed status drift occurs.

### About the `DELETE`/`UPDATE` lines
Several `UPDATE`/`DELETE` statements are **append-only / RLS assertions** (they expect **0 rows** and run inside `ROLLBACK`). They mutate nothing. The only non-rolled-back writes are the §1 seed `INSERT … ON CONFLICT DO NOTHING` rows.

---

## Manual teardown (optional, destructive — test project only)

Removes only the two Stage-3 test workspaces (cascades their content rows). No Storage objects are created outside rolled-back tests, so none need cleanup. Kept **out** of the script body:
```sql
DELETE FROM public.seo_workspaces
WHERE id IN ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000002');
-- module-access rows are shared with the Stage-2 test — leave them.
```

---

## Risks / notes

- **Test-only.** Do not run on production. It seeds rows under two test workspaces; teardown (manual) can delete them.
- **Real users required.** UUIDs must belong to real `auth.users` rows (Dashboard-created). The script refuses to run while `REPLACE_WITH_*` placeholders remain.
- **Single execution.** Run the whole script in one go — the top-of-file UUID GUCs are session-scoped.
- **Editor role.** Must be able to `SET ROLE authenticated` (default `postgres` works). A restricted editor role would make the RLS-simulation blocks meaningless.
- **§7g is best-effort.** Directly inserting into `storage.objects` from SQL depends on the project's Storage grants. The client-denied assertion is authoritative; the owner-allowed path degrades to `SKIP` (never `FAIL`) if a table-grant difference — not the policy — blocks it. The bucket-privacy and policy-existence checks (§7f) are the definitive structural signals. Real binary uploads are **not** performed.
- **Not a migration change.** Running this does not modify any migration. If any `FAIL` appears, treat it as a real Stage-3 defect and fix the **migration**, not the test.
