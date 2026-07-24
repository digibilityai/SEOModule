# SEO Local Database Setup — Docker-based Supabase CLI Stack

**Purpose:** the reproducible procedure for standing up a genuinely local
Postgres/Supabase environment for this repo, so backend verification never
has to fall back to `Digi_SEO_Test` or production. This document did not
previously exist in the repository despite being cited as an existing file
by `SEO_IMPLEMENTATION_STATUS.md` and `SEO_DECISIONS.md` (A17) — those
citations describe real findings from earlier local-verification sessions,
but the file itself was never committed. This version is written from a
genuine, freshly-reproduced clean-reset session (Recommendation Generation
Stage 2 acceptance-gap closure) and supersedes any prior informal notes.

**Status:** local-only. Nothing here targets `Digi_SEO_Test` or production.
Never run `supabase link` or pass `--linked` while following this document.

---

## 1. Prerequisites

- Docker Desktop (or an equivalent local Docker daemon) installed and running
  — `docker info` must succeed.
- Supabase CLI installed (`supabase --version`; this repo has been verified
  against CLI `2.109.1`).
- This repository checked out in a **dedicated worktree**, not the operator's
  primary working directory (see the project's worktree-isolation
  convention). Every command below assumes your shell's working directory is
  that worktree's repo root.

## 2. `supabase init`

The local CLI needs a `supabase/config.toml` naming the project and its
local ports. This repository does **not** commit `config.toml` (checked via
`git log --all` — no such file has ever existed in this repo's history), so
each session creates its own:

```bash
supabase init --workdir .
```

This generates `supabase/config.toml` (a fresh `project_id` derived from the
directory name) plus `supabase/.gitignore`. **Do not commit either file** —
they are local CLI state, consistent with this repo never tracking them.

If you are attaching to an **already-running** stack from a previous
session (Docker containers persist independently of the worktree directory
that started them — a prior worktree may since have been deleted while its
containers keep running), edit the generated `project_id` in
`supabase/config.toml` to match the running container set's compose project
name:

```bash
docker ps --format '{{.Names}}'   # e.g. supabase_db_wt-recommendation-stage1
# -> project_id is the suffix after "supabase_db_", e.g. "wt-recommendation-stage1"
```

Then edit `supabase/config.toml`'s `project_id = "..."` line to match, and
`supabase status` should return that stack's URLs/keys without starting new
containers.

## 3. Startup and shutdown

Start a fresh stack (only if one isn't already running for this project):

```bash
supabase start
```

Check status / retrieve the local anon key, URLs, etc.:

```bash
supabase status
```

Stop (only when you are fully done — containers otherwise persist and can
be reattached to in a later session, see §2):

```bash
supabase stop
```

## 4. Reset procedure (deferred-SSO-safe)

`supabase db reset` runs `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`
then replays every file in `supabase/migrations/` in filename order, plus
resets `auth`/`storage`/other platform schemas to their initial state. This
means **a reset wipes `auth.users` too**, not just `public` tables.

**Deferred SSO migration handling.** Migration
`20260720121000_seo_cross_project_identity_bridge.sql` is intentionally
deferred/unapplied on `Digi_SEO_Test` (`SEO_DECISIONS.md` A14) and must stay
that way locally too, so the local baseline matches TEST. `supabase db
reset` applies every migration file unconditionally — there is no
CLI flag to skip one file — so exclude it from the directory for the
duration of the reset, then restore it immediately after:

```bash
mkdir -p /tmp/sso-migration-holding
mv supabase/migrations/20260720121000_seo_cross_project_identity_bridge.sql /tmp/sso-migration-holding/
supabase db reset
mv /tmp/sso-migration-holding/20260720121000_seo_cross_project_identity_bridge.sql supabase/migrations/
git status --short supabase/migrations/   # must be empty — file restored unchanged
```

This has been run and reproduced cleanly (twice, including once during this
document's own verification pass — see §6).

## 5. Base table privilege bootstrap (required after every reset)

**Finding:** a hosted Supabase project (e.g. `Digi_SEO_Test`) provisions
base `SELECT/INSERT/UPDATE/DELETE` grants on every `public` table to the
`anon`/`authenticated` roles automatically, once, at the platform level —
outside of any migration file, and never lost because a real project's
`public` schema is never dropped. The local CLI's `supabase db reset`
performs `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` before
replaying migrations, which also destroys that grant/default-privilege
state. No migration in this repository re-establishes it (confirmed by
`grep -h GRANT supabase/migrations/*.sql` — every match is either
`GRANT EXECUTE ON FUNCTION` for an individual RPC, or a `GRANT SELECT`
on one of the two narrow read-only views that already carry an explicit
grant in their own migration; there is no `ALTER DEFAULT PRIVILEGES`
statement anywhere in the migration history). This is a genuine
**local-CLI-only reproducibility gap**, not a defect in any migration —
see §6 for the reproduction and classification evidence.

Fix — apply the local-only bootstrap script after every reset:

```bash
docker exec -i <local-db-container-name> psql -U postgres -d postgres \
  < supabase/test/local_supabase_privilege_bootstrap.sql
```

(`<local-db-container-name>` is `supabase_db_<project_id>`, e.g.
`supabase_db_wt-recommendation-stage1` — find it via `docker ps`.)

The script is idempotent (safe to re-run), grants nothing beyond the
standard `anon`/`authenticated` table-DML convention, never touches RLS,
and ends with a verification block that fails loudly
(`RAISE EXCEPTION`) if any table is still missing the grant or if RLS
was somehow left disabled on any table. Expected output ends with:

```
NOTICE:  local_supabase_privilege_bootstrap: ALL CHECKS PASSED — base grants restored, RLS unchanged
```

## 6. Isolation checks

Before trusting any local result, confirm the target is genuinely local:

```bash
docker inspect <local-db-container-name> --format '{{json .Config.Labels}}'
# expect com.supabase.cli.project == your local project_id, never a hosted ref

grep VITE_SUPABASE_URL .env.local 2>/dev/null
# must be absent or point somewhere unrelated to 127.0.0.1 — the app's
# runtime-config.js override (§8) is what actually targets the local stack
# for a browser session, not .env.local
```

`supabase status`'s `API_URL`/`DB_URL` must read `127.0.0.1`, never a
`*.supabase.co` hostname.

## 7. Fixture-user creation

A fresh reset wipes `auth.users`. GoTrue (Supabase local Auth) requires
every token column to be an **empty string, not `NULL`**, or sign-in fails
with a 500 `"Database error querying schema"` (`converting NULL to string
is unsupported"` in `docker logs supabase_auth_<project_id>`). Passwords are
set via `pgcrypto`'s `crypt()`:

```sql
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new,
  email_change_token_current, email_change, phone_change,
  phone_change_token, reauthentication_token,
  raw_app_meta_data, raw_user_meta_data
) values (
  '00000000-0000-0000-0000-000000000000', '<fixed-uuid>', 'authenticated', 'authenticated',
  'local-owner@example.test', crypt('LocalTest123!', gen_salt('bf')), now(), now(), now(),
  '', '', '', '', '', '', '', '', '{"provider":"email","providers":["email"]}', '{}'
) on conflict (id) do nothing;

insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), u.id::text, u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email),
  'email', now(), now(), now()
from auth.users u where u.id = '<fixed-uuid>'
on conflict do nothing;
```

Every fixture user also needs a `public.user_module_access` row
(`module_name='seo', is_active=true`) — a user-scoped module-access gate
separate from workspace membership, checked by the `has_seo_module_access`
RPC. Without it, every SEO route redirects with "SEO access required" even
after a successful sign-in.

`supabase/test/seo_seed_ui_test_dataset.sql` seeds a realistic workspace/
website/onboarding/audit/recommendations/approvals dataset once four such
`auth.users` UUIDs are pasted into its §0 (see the script's own header for
full instructions) — it already inserts the matching
`user_module_access` rows, so no separate step is needed once fixture users
exist.

## 8. Pointing the app at the local stack (browser verification)

`public/runtime-config.js` (tracked, must stay `SEO_DATA_MODE:"mock"` with
empty Supabase fields at rest) takes runtime priority over `.env`. To
browser-test against the local stack, temporarily set:

```js
window.RUNTIME_CONFIG = {
  SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_ANON_KEY: "<the ANON_KEY from `supabase status`>",
  SEO_DATA_MODE: "supabase",
  DIGIBILITY_APP_URL: "", DIGIBILITY_BRIDGE_URL: "", DIGIBILITY_ANON_KEY: "",
};
```

then revert it byte-for-byte afterward (`git diff` on this file must be
empty when you are done). The `ANON_KEY` printed by a fresh local
`supabase start`/`status` is the standard, publicly-documented Supabase CLI
demo key shared by every default local project — it is not a secret and
grants nothing beyond what RLS allows.

## 9. Verification-script execution

Run a feature's SQL verification suite directly against the local DB
(never `--linked`):

```bash
docker exec -i <local-db-container-name> psql -U postgres -d postgres \
  < supabase/test/<feature>_verification.sql
```

`supabase db query --local`/`--db-url` cannot execute a multi-statement
script (`cannot insert multiple commands into a prepared statement`) — use
`docker exec -i ... psql ... < file.sql` instead, which is still fully
local.

## 10. Two-session concurrency method

To prove a real (not mocked) lock-wait: open two separate `docker exec -i
<local-db-container-name> psql` sessions. In Session A, call the guarded RPC
inside an explicit transaction that then calls `pg_sleep(N)` before
committing (holding the advisory lock open). In Session B, call the same
RPC against the same key while Session A is still sleeping, and poll
`pg_stat_activity` for `wait_event_type='Lock', wait_event='advisory'` on
Session B's PID — this must show B genuinely blocked, not just slow. Session
B should complete almost immediately after Session A commits.

## 11. Cleanup

To remove fixture data without a full reset, delete rows in FK-safe order
(children before parents) for whatever fixture UUID prefix you used. To
guarantee a fully clean, reproducible baseline instead (recommended at the
end of an acceptance/verification session), just repeat §4 (reset) + §5
(bootstrap) — this is faster and more certain than manual row deletion, and
was the method used to close out this document's own verification pass (see
§6 below): after the full loading-state and empty-state browser proofs
were captured, the stack was reset again and the bootstrap re-applied,
leaving `auth.users`, `seo_websites`, and `seo_recommendations` (and every
other public table) back at 0 rows with grants and RLS both intact.

## 12. Commands that must never be used against this local setup

- `supabase link` — never link this local worktree to any hosted project.
- Any `--linked` flag on a `supabase db` subcommand.
- `supabase db push` against a hosted project ref.
- Pointing `runtime-config.js` or `.env.local` at `Digi_SEO_Test` or
  production while also running local-only fixture/reset commands in the
  same session — keep local and TEST work in separate sessions.

---

## Verification record for this document (2026-07-24)

This document's every command above was run for real during Recommendation
Generation Stage 2's acceptance-gap closure, against the pre-existing local
Docker stack from Stage 1 (`wt-recommendation-stage1`, reattached per §2
after its original worktree directory had been cleaned up):

- **§2 reattachment:** `supabase init` + `project_id` edit — confirmed
  `supabase status` returned the running stack's real URLs/keys with no new
  containers started.
- **§4 reset (deferred-SSO-safe):** run twice this session, both times
  applying every migration including `20260724130000_seo_recommendation_generate.sql`
  and correctly skipping `20260720121000`; the file was restored byte-exact
  both times (`git status --short supabase/migrations/` empty).
- **§5 privilege bootstrap — clean reproduction of the gap:** immediately
  after a fresh reset (before applying the bootstrap), `authenticated`/`anon`
  had only `REFERENCES/TRIGGER/TRUNCATE` on every table (no `SELECT`); a real
  anon-key REST request returned `401`, `code":"42501"`,
  `"message":"permission denied for table seo_recommendations"`, with
  PostgREST's own hint reading `"Grant the required privileges to the
  current role with: GRANT SELECT ON public.seo_recommendations TO anon;"`
  — captured with `curl` against the freshly-reset, unpatched database.
  RLS was independently confirmed still enabled on all 53 public tables
  (`0 tables without RLS`) at that same moment, proving this is a pre-RLS
  grant failure, not an RLS defect. Applying
  `supabase/test/local_supabase_privilege_bootstrap.sql` immediately fixed
  the same REST request to `200 OK`; re-running the bootstrap script a
  second time produced identical `ALL CHECKS PASSED` output (idempotency
  confirmed).
- **§7 fixture users + seed:** 4 fresh `auth.users` rows created, signed in
  successfully via the app's real `supabase.auth.signInWithPassword`; the
  UI seed script ran cleanly against the fresh database.
- **§8/§10 browser + concurrency:** browser-mode verification performed
  live this session (see `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`
  for the recommendation-generation-specific results); the two-session
  method in §10 is unchanged from the one already proven working for
  Recommendation Generation Stage 1's own concurrency proof.
- **§11 cleanup:** this session ended by repeating §4+§5 exactly as
  described, leaving `auth.users`/`seo_websites`/`seo_recommendations` (and
  every other public table) at 0 rows with grants and RLS both intact —
  itself a second, deliberate proof that the full documented procedure
  reproduces cleanly from scratch.

No command in this document was ever run with `--linked`, and
`supabase link` was never run.
