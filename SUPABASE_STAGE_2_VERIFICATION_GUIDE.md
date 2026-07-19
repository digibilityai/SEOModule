# SEO Stage 2 — Verification Guide (TEST PROJECT ONLY)

How to verify the Stage 2 backend (audit / recommendations / approval) on a **fresh Supabase TEST project** after Stage 1 + Stage 2 migrations are applied. **Never run on production.** No app code is involved.

Script: `supabase/test/seo_stage2_smoke_test.sql` (TEST ONLY, non-destructive to Core data).

## ✅ Execution record

- [x] Stage 1 (`…120001`–`…120003`) applied to a fresh test Supabase project — dry-run passed, 9 tables + RLS + policies + 6 helper functions confirmed visible.
- [x] Stage 2 (`…120004`–`…120006`) applied on top — dry-run passed, 6 tables + RLS + policies + triggers + 5 functions confirmed visible.
- [x] `seo_stage2_smoke_test.sql` executed on the test project — **all assertions reported `PASS`, no known `FAIL` lines**.
- [x] **Production has NOT been touched.** These migrations are test-verified only, not production-applied. Production apply should happen only after confirming the target project, a backup/branch strategy, and a final review.

See `SUPABASE_MIGRATION_STAGE_1_NOTES.md` and `SUPABASE_MIGRATION_STAGE_2_NOTES.md` for the full per-object checkpoints.

---

## Prerequisites

1. A **fresh/disposable Supabase test project** with, applied in order:
   `…120001, …120002, …120003` (Stage 1) then `…120004, …120005, …120006` (Stage 2).
2. Run the script from the **SQL Editor as `postgres`** (the default). The script uses `SET LOCAL ROLE authenticated` to simulate end users, which requires a role that can `SET ROLE authenticated` — `postgres` can.
3. **Create 5 test users** (real `auth.users` rows are required because Stage 1/2 FKs reference `auth.users`; do **not** insert into `auth.users` by hand):
   - Supabase Dashboard → **Authentication → Users → Add user** (email + password, "Auto Confirm").
   - Create: **owner**, **admin**, **team_member**, **client**, **nonmember**.
   - Copy each user's **UUID** (the `id` column).
   - (Signup auto-creates a `public.profiles` row per user via Core's `handle_new_user`.)

### Optional — global-admin inspection
To also confirm a Digibility global admin can read all SEO data, pick any test user and run once:
```sql
UPDATE public.profiles SET role = 'admin' WHERE id = '<that-user-uuid>';
```
(Only on the test project; `seo_is_global_admin` reads `profiles.role`.)

---

## How to run

1. Open `supabase/test/seo_stage2_smoke_test.sql`.
2. Replace the 5 `REPLACE_WITH_*` placeholders at the top with the real user UUIDs.
3. Paste the **entire** script into the SQL Editor and run it **as one execution** (the top `set_config(...)` values are session-scoped and must persist through the whole run).
4. Read results in the **Messages / Notices** tab: every check prints `PASS: …`. Any `FAIL:` (or an unexpected error) **raises and stops** the script — that is a real defect to investigate.

The script drops its one test-only helper (`public._seo_test_login`) at the end and leaves the two test workspaces in place (see Teardown).

---

## What it verifies (maps to the request)

| # | Section | Checks |
|---|---|---|
| 1–3 | SETUP | Grants `user_module_access`; creates workspace W1 (owner auto-added via Stage-1 trigger), adds admin/team_member/client members, a website, plus a 2nd workspace/website for the cross-workspace test. |
| 4 | `seo_run_audit` | owner/admin/team_member/**client** can all trigger; it creates a **run only** (issue/rec counts unchanged); keeps **exactly one `is_latest`** per website; **non-member is rejected**. |
| 5 | Seed | Service-role-style insert of issues + recommendations + approval items (privileged role = the system/service path). |
| 6 | High-risk trigger | A `robots_txt` issue seeded with `is_high_risk_category=false` is **forced to `true`**; the linked approval item resolves `true`; a non-dangerous issue stays `false`; a recommendation pointing at a **different workspace's** issue **raises** (cross-workspace integrity). |
| 7 | Approval matrix (`seo_approval_transition`) | **team_member**: approve **low + medium** ✓, approve **high**/**dangerous** ✗, **completed** ✗. **client**: approve **low-simple** ✓, approve **high**/**dangerous** ✗, **completed** ✗, **direct edit** blocked by RLS (0 rows). **owner**: approve high, expert-review, developer-needed, completed all ✓. |
| 8 | Comments | Inserted via the RPC; **append-only** — direct UPDATE/DELETE affect 0 rows for everyone (incl. owner). |
| 9 | Activity | Every transition writes `seo_approval_activity`; `actor_role_snapshot` is stored (verified = `client`). |

### How authenticated users are simulated (safe)
Inside a transaction the script does `SELECT public._seo_test_login(<uuid>)` (sets `request.jwt.claim.sub` / `request.jwt.claims` so `auth.uid()` resolves to that user) **then** `SET LOCAL ROLE authenticated` (so RLS is enforced as a normal user, not the privileged editor). `SECURITY DEFINER` RPCs/helpers still see the simulated `auth.uid()`. Permission-only checks use `ROLLBACK` so approval items stay reusable across roles. Quick sanity check you can run manually inside such a block: `SELECT auth.uid();` should equal the test UUID.

---

## Manual teardown (optional, destructive — test project only)

Removes only the two test workspaces (cascades their audit/rec/approval rows). Kept **out** of the script body; paste manually if you want a clean project:
```sql
DELETE FROM public.seo_workspaces
WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002');
-- and, if desired, the seo module-access rows for the 5 test users.
```

---

## Risks / notes

- **Test-only.** Do not run on production. It seeds rows and (in teardown) can delete the test workspaces.
- **Real users required.** UUIDs must belong to real `auth.users` rows (Dashboard-created); arbitrary UUIDs fail FK checks. The script refuses to run while placeholders remain.
- **Single execution.** Run the whole script in one go — the top-of-file UUID GUCs are session-scoped.
- **Editor role.** Must be able to `SET ROLE authenticated` (default `postgres` works). If your editor runs as a restricted role, the role-simulation blocks won't switch and RLS assertions won't be meaningful.
- **Not a migration change.** Reviewing/running this does not modify any migration. If any `FAIL` appears, treat it as a real Stage-2 defect and fix the migration, not the test.
- The line-352 `DELETE` is an intentional **append-only assertion** (expects 0 rows, inside a `ROLLBACK`) — it deletes nothing.
