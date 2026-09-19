# SEO Local Database Setup — Docker-based Supabase CLI Stack

**Classification:** operational setup guide (not an authority/status document —
current project state lives in `SEO_CONTEXT_HANDOVER.md` §0).

**Purpose:** the reproducible procedure for standing up a genuinely local
Postgres/Supabase environment for this repo, so backend verification never
has to fall back to `Digi_SEO_Test` or production.

**Status:** local-only. Nothing here targets `Digi_SEO_Test` or production.
Never run `supabase link` or pass `--linked` while following this document.
Every command below was executed for real against a genuine local stack on
2026-07-24 (see the verification record at the end); the 2026-09-19
reconciliation of this file was documentation-only and did **not** re-run them.

**Provenance / reconciliation (2026-09-19).** This file did not exist in Git
before Recommendation Generation Stage 2 (earlier documents cited a same-named
file that had never been committed). The base of this version is the Stage 2
version committed on `main` (a genuinely clean-reset-derived procedure that
includes the privilege bootstrap). Still-correct material from the earlier,
uncommitted local-verification version was merged in — the bare-Homebrew-Postgres
warning, local ports, the isolation-check guidance, the never-run list, the
two-session concurrency script, the shared fixture UUIDs and the troubleshooting
list — while its obsolete parts were left out (the "Docker missing" framing, the
assumption that no privilege bootstrap is needed, the minimal `auth.users`
insert that cannot sign in through the browser, and the older init command).
Section numbers §1–§12 are stable — other documents cite them.

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

### Why a bare Homebrew/system PostgreSQL is not a substitute

Do **not** point verification at a plain `brew install postgresql` server, even
though it needs no Docker. This repo's guarded RPCs and RLS policies are written
against Supabase's `auth` schema (`auth.uid()`, `auth.users` foreign keys) and
the `authenticated`/`anon` roles that Supabase's Postgres image provisions.
A bare server has none of that; hand-rebuilding `auth.uid()`, `auth.users` and
those roles risks silently testing against a materially different environment.
`supabase start`'s local Postgres image replicates the schema/roles/extensions
that `Digi_SEO_Test` runs, so it is the only faithful local option.

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
(`project_id` is only a Docker container-naming label, not a security boundary.)

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

**Important:** on first boot `supabase start` applies **every** file in
`supabase/migrations/` unconditionally — including the deferred SSO migration.
If you are starting from nothing, hold the SSO file out of the directory for the
first boot exactly as described in §4 ("Baseline rule"), or run the §4 reset
procedure straight after start.

Check status / retrieve the local anon key, URLs, etc.:

```bash
supabase status
```

**Local services (defaults observed 2026-07-24; confirm with `supabase status`,
since assigned ports can differ):**

| Service | Local address |
|---|---|
| API / gateway (Kong) | `http://127.0.0.1:54321` |
| Postgres (direct) | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Studio | `http://127.0.0.1:54323` |
| Inbucket / Mailpit (local email capture) | `http://127.0.0.1:54324` |
| Postgres server version | `17.6` (same major version as `Digi_SEO_Test`) |

Containers are named `supabase_<service>_<project_id>` (e.g.
`supabase_db_wt-recommendation-stage1`) — used below for `docker exec`, and as
an isolation signal (never a hosted project ref).

Stop (only when you are fully done — containers otherwise persist and can
be reattached to in a later session, see §2):

```bash
supabase stop
```

Add `--no-backup` only if you deliberately want to discard the local database
volume; normally omit it.

## 4. Reset procedure (deferred-SSO-safe)

`supabase db reset` runs `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`
then replays every file in `supabase/migrations/` in filename order, plus
resets `auth`/`storage`/other platform schemas to their initial state. This
means **a reset wipes `auth.users` too**, not just `public` tables. It only ever
touches the local containerised database.

### Baseline rule: the deferred SSO migration

Migration `20260720121000_seo_cross_project_identity_bridge.sql` is
intentionally deferred / not recorded on `Digi_SEO_Test` (`SEO_DECISIONS.md`
A14), so **the local baseline must also exclude it**, to match TEST's deferral
of it. (The other migration TEST lacks, `20260724130000` Recommendation
Generation, **is** applied locally — local is where that feature is verified.)

`supabase start` and `supabase db reset` apply every migration file
unconditionally — there is no CLI flag to skip one, and because the SSO file
sits chronologically *before* several later wanted migrations, the directory
cannot simply be cut off at a date. The rationale for keeping it out is
scope control (A14), not a safety problem in the SQL: read in full, it is
purely additive (a new empty `seo_identity_profiles` table and a
backward-compatible `CREATE OR REPLACE` of `seo_is_global_admin()` that only adds
a fallback path). The proven, fully reversible local-only mechanism is to hold
the file out for the duration of the reset, then restore it:

```bash
mkdir -p /tmp/sso-migration-holding
mv supabase/migrations/20260720121000_seo_cross_project_identity_bridge.sql /tmp/sso-migration-holding/
supabase db reset
mv /tmp/sso-migration-holding/20260720121000_seo_cross_project_identity_bridge.sql supabase/migrations/
git status --short supabase/migrations/   # must be empty — file restored unchanged
```

The running local database is unaffected by moving the file back (Postgres does
not rescan the directory outside an explicit `start`/`reset`), so the tracked
file can safely live in `supabase/migrations/` while the live local database
correctly has it un-applied. This has been reproduced cleanly repeatedly (two
consecutive resets gave an identical schema: **53 `public` tables**, SSO table
absent, Recommendation Generation present).

Do **not** apply the SSO migration locally outside this documented exclusion
pattern unless a future, separate, explicitly-approved SSO task says otherwise.

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
see the verification record for the reproduction and classification evidence.

Symptom if you skip it: a REST/app request returns `401` with
`"code":"42501","message":"permission denied for table <name>"` (before RLS is
even evaluated).

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

Before trusting any local result — and before applying or running anything —
confirm the target is genuinely local and is not `Digi_SEO_Test`, production or
`Digi_Visi`:

```bash
docker ps --format '{{.Names}}'
# every container is supabase_<service>_<your local project_id>; none contains a hosted project ref

docker inspect <local-db-container-name> --format '{{json .Config.Labels}}'
# expect com.supabase.cli.project == your local project_id, never a hosted ref

supabase status
# API_URL / DB_URL must read 127.0.0.1, never a *.supabase.co hostname

supabase db query --db-url postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  "select current_database(), current_user, version(), inet_server_addr(), inet_server_port();"
# a single-statement query works fine via --db-url/--local
```

Expected values (observed 2026-07-24): `current_database` = `postgres`,
`current_user` = `postgres`, `version()` = `PostgreSQL 17.6 …`, and
`inet_server_addr` a private Docker-bridge address (e.g. `172.18.0.2`) with the
container-internal port `5432` (published on the host as `54322`) —
categorically not a routable/public host.

`.env.local` in an operator clone may legitimately point at `Digi_SEO_Test`
(its `VITE_SUPABASE_URL` begins with that project's ref `snyzotgwwfomgafrsvfm`).
That is exactly why this guide never uses `.env.local` to target the local stack:
the browser is pointed at the local stack only through the temporary
`runtime-config.js` override in §8. Compare any URL you are about to use against
the hosted refs — `Digi_SEO_Test` = `snyzotgwwfomgafrsvfm`, `Digi_Visi` =
`boclpogcwwnyvrtgabtt` — and do not proceed with any write if the check is
ambiguous. The statement to reach before applying anything:
**`TARGET IS LOCAL AND IS NOT DIGI_SEO_TEST OR PRODUCTION`**.

## 7. Fixture-user creation

A fresh reset wipes `auth.users`. GoTrue (Supabase local Auth) requires
every token column to be an **empty string, not `NULL`**, or sign-in fails
with a 500 `"Database error querying schema"` (`converting NULL to string
is unsupported` in `docker logs supabase_auth_<project_id>`). Passwords are
set via `pgcrypto`'s `crypt()`. Run this block once per fixture user, replacing
`<fixed-uuid>` and `<email>` (see the shared-UUID table below):

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
  '<email>', crypt('LocalTest123!', gen_salt('bf')), now(), now(), now(),
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

**Do not** use a minimal `auth.users` insert that leaves the token columns
`NULL`, uses a dummy password, or omits `auth.identities`: it is enough for
SQL-only checks but the app's real `signInWithPassword` will fail with the 500
above.

### Shared fixture UUIDs the test scripts require

The scripts under `supabase/test/` hard-code one shared set of user ids
(`seo_seed_ui_test_dataset.sql` §0 already contains the first four literally;
the verification scripts set them via `set_config`, e.g. `r1.owner`, `r1.cross`).
On `Digi_SEO_Test` these are real accounts; in a fresh local `auth.users` they do
not exist, so **use exactly these ids as `<fixed-uuid>` above** — the local rows
are separate, local-only, and grant nothing on TEST:

| Role in the scripts | `<fixed-uuid>` | Suggested local `<email>` |
|---|---|---|
| owner | `48c479db-aedf-452e-af43-05ed1180baaa` | `local-owner@example.test` |
| admin | `9830c4d7-167b-4d78-9179-37b60511bd73` | `local-admin@example.test` |
| team_member | `0723d21f-c02c-4725-851f-575f93f2f58c` | `local-team@example.test` |
| client | `6c7a04e0-9985-47c3-aad4-f2f0cc5e092c` | `local-client@example.test` |
| cross-tenant user | `8ae3b67e-6f00-4e10-905c-3a76281ffde9` | `local-cross@example.test` |

Create them once per fresh local database (again after any reset). If you skip
this, the first script run fails with `insert or update on table
"seo_workspaces" violates foreign key constraint "seo_workspaces_owner_user_id_fkey"`.
The cross-tenant user is needed by the verification scripts; the seed script only
needs the first four. (Combining the browser-compatible insert with these ids was
assembled from two separately proven forms; it was not re-executed during the
2026-09-19 reconciliation — confirm sign-in on first use.)

Every fixture user that should sign in through the app also needs a
`public.user_module_access` row (`module_name='seo', is_active=true`) — a
user-scoped module-access gate separate from workspace membership, checked by the
`has_seo_module_access` RPC. Without it, every SEO route redirects with "SEO
access required" even after a successful sign-in.

`supabase/test/seo_seed_ui_test_dataset.sql` seeds a realistic workspace/
website/onboarding/audit/recommendations/approvals dataset once the four
`auth.users` UUIDs exist (see the script's own header) — it already inserts the
matching `user_module_access` rows, so no separate step is needed after that.

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
docker exec -i <local-db-container-name> psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/test/<feature>_verification.sql
```

`supabase db query --local`/`--db-url` cannot execute a multi-statement
script (`error: cannot insert multiple commands into a prepared statement` — the
direct-connection extended query protocol allows one statement per prepared
statement, unlike the Management-API path `--linked` uses) — use
`docker exec -i ... psql ... < file.sql` instead, which is still fully local.
NOTICE-level checkpoints (e.g. `owner allowed ok`, `TEARDOWN ok — net-nothing`)
print straight to the terminal this way. A `WARNING: SET LOCAL can only be used
in transaction blocks` during a piped run is benign (`psql` autocommits outside an
explicit `BEGIN;`, so the role change falls back to session scope, which the
scripts' explicit `RESET`s already accommodate).

## 10. Two-session concurrency method

To prove a real (not mocked) lock-wait, use two separate `docker exec -i
<local-db-container-name> psql` sessions. In Session A, call the guarded RPC
inside an explicit transaction that then calls `pg_sleep(N)` before committing
(holding the advisory lock open). In Session B, call the same RPC against the same
key while Session A is still sleeping, and poll `pg_stat_activity` for
`wait_event_type='Lock', wait_event='advisory'` on Session B — this must show B
genuinely blocked, not just slow. B should complete almost immediately after A
commits. (`session_a.sql` / `session_b.sql` are your own per-run files, each a
`BEGIN; … COMMIT;` script; do not commit them.)

```bash
# Session A — acquires the lock, then holds the transaction open:
docker exec -i <local-db-container-name> psql -U postgres -d postgres -v ON_ERROR_STOP=1 < session_a.sql &
sleep 1.5
# Session B — staggered start; will block on the same advisory lock:
docker exec -i <local-db-container-name> psql -U postgres -d postgres -v ON_ERROR_STOP=1 < session_b.sql &
sleep 2
# Poll — filter broadly: each psql statement is its own pg_stat_activity row, and
# Session A's current statement while holding is `SELECT pg_sleep(N);`, not the RPC text:
docker exec <local-db-container-name> psql -U postgres -d postgres -c \
  "select pid, state, wait_event_type, wait_event, left(query,60) as q, query_start
   from pg_stat_activity
   where usename='postgres' and state='active' and pid <> pg_backend_pid()
     and query not ilike '%pg_stat_activity%'
   order by query_start;"
wait
```

Observed on 2026-07-24 for `seo_recommendation_generate`: two polls (T+3.5 s,
T+6.5 s) both showed Session A as `Timeout / PgSleep` (holding) and Session B as
`Lock / advisory` (genuinely blocked); B completed ~30 ms after A's `pg_sleep(10)`
released the lock; the post-race state was the correct canonical row count with
zero duplicates.

## 11. Cleanup

To remove fixture data without a full reset, delete rows in FK-safe order
(children before parents) for whatever fixture UUID prefix you used. To
guarantee a fully clean, reproducible baseline instead (recommended at the
end of an acceptance/verification session), just repeat §4 (reset) + §5
(bootstrap) — this is faster and more certain than manual row deletion, and
was the method used to close out this document's own verification pass (see the
verification record below): after the full loading-state and empty-state browser
proofs were captured, the stack was reset again and the bootstrap re-applied,
leaving `auth.users`, `seo_websites`, and `seo_recommendations` (and every
other public table) back at 0 rows with grants and RLS both intact.

**Need to start completely fresh?** `supabase stop`, then `supabase start`, then
the §4 reset with the SSO hold-out, then the §5 bootstrap, then re-create the §7
fixture users.

## 12. Commands that must never be used against this local setup

Never run any of these for a task that says "local only". Before running any
command, scan it for `--linked` / `--project-ref` and refuse if present.

- `supabase link` — never link this local worktree to any hosted project.
- Any `--linked` flag on a `supabase db` subcommand, in particular
  `supabase db query --linked` (queries the linked remote project) and
  `supabase migration repair --linked` (rewrites **remote** migration history; it
  has no meaning for local work — fix local state with a reset instead).
- `supabase db push` against a hosted project ref (with no explicit local
  target it pushes to whatever project was last linked — `Digi_SEO_Test`).
- Any command with `--project-ref <ref>` naming `snyzotgwwfomgafrsvfm`
  (`Digi_SEO_Test`), `boclpogcwwnyvrtgabtt` (`Digi_Visi`) or any production ref.
- Pointing `runtime-config.js` or `.env.local` at `Digi_SEO_Test` or
  production while also running local-only fixture/reset commands in the
  same session — keep local and TEST work in separate sessions.

## 13. Troubleshooting

- **`supabase start` errors immediately with a Docker-connection message** →
  the container runtime isn't running; `docker info` must succeed first.
- **"no such file: config.toml" or similar** → run `supabase init --workdir .`
  (§2).
- **`error: cannot insert multiple commands into a prepared statement`** →
  you ran a multi-statement script via `db query -f`; use `docker exec -i
  <local-db-container-name> psql … < file` (§9).
- **`401` / `42501` "permission denied for table …" from the API** → the
  privilege bootstrap wasn't applied after the last reset (§5).
- **Sign-in returns 500 "Database error querying schema"** → a fixture
  `auth.users` row has `NULL` token columns; recreate it with the §7 block.
- **`insert or update on table "seo_workspaces" violates foreign key constraint
  "seo_workspaces_owner_user_id_fkey"`** (or similar for any fixture id) → the
  shared fixture users haven't been created in this local database (§7).
- **`WARNING: SET LOCAL can only be used in transaction blocks`** → benign (§9).
- **Port already in use** → another process (or an unclean previous stop) holds
  `54321`–`54324`; `supabase stop` first, or check `lsof -i :54322`.
- **The deferred SSO migration got applied locally** → redo the §4 hold-out
  reset (then §5 and §7 again, since a reset wipes them).

---

## Verification record for this document (2026-07-24)

This document's commands were run for real during Recommendation
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

## Reconciliation record (2026-09-19)

Documentation-only. Base = the committed Stage 2 version on `main` (`9cb3676`).
Merged in from the earlier uncommitted local-verification version (2026-07-24,
backed up externally): the bare-Homebrew-Postgres warning, local ports/versions,
the isolation-check guidance, the "Baseline rule: the deferred SSO migration"
heading (this repairs the citation in
`SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md`, which names that section),
the shared fixture UUID table, the two-session script and observed result, the
never-run list (including `migration repair --linked` and `--project-ref`), and the
troubleshooting list. Deliberately **not** carried over: "Docker is the one missing
prerequisite" wording, the "no bootstrap needed" assumption, the minimal
`auth.users` insert (`encrypted_password = 'x'`, no token columns, no identities)
that cannot sign in via the browser, and `supabase init --yes`. No command was
re-executed in this reconciliation and no Supabase project was contacted.
