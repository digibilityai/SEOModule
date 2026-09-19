# Recommendation Generation Stage 1 — Backend Verification Record

> **Reconciliation note (dated 2026-09-19, added after the TEST promotion; the original record below is unchanged).**
> Statements in this record that `Digi_SEO_Test` "remains rolled back" or carries none of this feature
> (the top update notice, §4 and §5) describe the state on 2026-07-24. Migration `20260724130000` was
> **promoted, recorded and verified on `Digi_SEO_Test`** on 2026-09-19: targeted application; history repair
> recorded only that version; backend verification script exit success; two session advisory lock
> proof with 8 current rows, 8 distinct identities and 0 duplicates; fixtures removed with zero
> residue; the 8 legacy recommendation rows unchanged. The "Not pushed or merged to `main`" wording
> is also historical: Stage 1 is on canonical `main` (`808d54d`, `e7b1fbe`). Current state:
> `SEO_IMPLEMENTATION_STATUS.md` §0 and §5.

> **UPDATE (2026-07-24, later same day): GENUINE LOCAL VERIFICATION
> COMPLETE — STAGE 1 ACCEPTED AND MODULE-LOCKED.** §6 below records a full
> pass of the SQL verification suite and the live two-session concurrency
> proof against a genuine local Supabase stack (Docker-based, `project_id =
> wt-recommendation-stage1`), run twice for repeatability, with independent
> residue confirmation — **not** `Digi_SEO_Test`, not production. This
> satisfied the local-verification gate the notice below describes as
> missing. **Stage 1 acceptance review is now complete and approved** —
> implementation committed to `feat/seo-recommendation-generate-stage1`
> (based on `origin/main` `71ac8fd`), formally MODULE-LOCKED (see
> `docs/markdown/MODULE_LOCKS.md`). **Not pushed or merged to `main`.**
> `Digi_SEO_Test` remains rolled back and untouched; production untouched.
> This lock is backend-only — Stage 2 (frontend) remains unbuilt and
> explicitly deferred/unlocked.

> **ENVIRONMENT-CONTROL NOTICE (added 2026-07-24, reconciliation task —
> historical; see the update above for current status).**
> The governing delivery sequence for this project is: **local development →
> full local verification → `Digi_SEO_Test` → production.** Everything
> recorded in §1–§2 below describes database behavior that was proven
> against **`Digi_SEO_Test`**, applied there **before** the intended
> TEST-promotion gate — i.e. before any local-verification step, because no
> local Postgres environment was available in the implementing session and
> the operator approval to use `Digi_SEO_Test` as a substitute was given
> interactively in that session, not recorded in the controlling ChatGPT
> instruction trail that governs this project. This was identified as a
> process violation in a subsequent reconciliation task. **The
> `Digi_SEO_Test` migration was subsequently rolled back** (see §4,
> "Environment-Control Reconciliation" below) — nothing described in §1–§2
> is currently live on any database. **§1–§2 remain historical evidence
> only, superseded as the acceptance basis by §6's genuine local
> verification** — they are retained, unedited, purely as a record of what
> was directly observed on `Digi_SEO_Test` during the (out-of-sequence) TEST
> run.

**Scope:** database-level verification of the additive schema and the guarded
`public.seo_recommendation_generate(p_website_id uuid)` RPC (migration
`20260724130000_seo_recommendation_generate.sql`). Backend only — no
frontend page, orchestration, or approval-queue change is included in this
stage.

**Environment (historical — see notice above):** applied and verified in
isolation against **Digi_SEO_Test** (`snyzotgwwfomgafrsvfm`) via `supabase
db query --linked -f` + `supabase migration repair --status applied`, the
same isolated procedure used for every prior guarded-RPC stage in this repo
(Reports Stage 2, Competitor Stage 2A). This environment has no Docker/local
Postgres/`psql`, so a literal separate "local development database" was not
reachable at the time; Digi_SEO_Test was used as a substitute on the
strength of an in-session operator approval that was **not** recorded in the
controlling ChatGPT instruction trail — this is the process gap this
document's §4 addendum reconciles. Production was never connected to. The
pre-existing pending SSO migration (`20260720121000`) was left untouched
throughout, including through the rollback in §4.

**Base commit:** `origin/main` `71ac8fd0fd6087bb5435bea4cca865025bc27967`,
implemented from a temporary worktree/branch built from that commit (not the
stale local `feat/seo-competitor-generate-stage2a` HEAD).

## 1. SQL verification suite

File: `supabase/test/seo_recommendation_generate_verification.sql`.
Self-contained, self-seeding, single implicit transaction (multi-statement
batch auto-commits only if every assertion passes; any `RAISE EXCEPTION`
aborts and rolls back the whole batch — net-nothing on failure).

Two consecutive full runs both completed with exit code 0 and no error.
Zero residue confirmed directly afterward via a standalone count query
against every fixture id prefix (`ws=0, sites=0, runs=0, issues=0, recs=0,
leftover_fn=0`).

Covers:

- **Contract**: `SECURITY DEFINER`, `search_path=public`, `SETOF
  seo_recommendations` return type, `authenticated` EXECUTE granted,
  `anon` EXECUTE denied, `pg_advisory_xact_lock` present, both new columns
  and both new partial unique indexes present.
- **Authorization matrix**: owner/admin/team_member allowed (idempotent
  11-row result each time); client, pure non-member, and cross-tenant owner
  all denied with the identical non-leaking message
  (`"Not authorized to generate recommendations for this website."`); a
  missing website (`ghost` id) raises the same message under an authorized
  caller — existence never leaks; `anon` denied at the grant level.
- **Mapping**: `schema/system_suggestion → area=schema, action_type=
  auto_suggest`; `duplicate_content/client_action → area=content,
  action_type=manual_support`; `canonical/developer_needed → area=technical,
  action_type=approval_required` — all read directly from persisted rows.
- **Eligibility**: a `status='fixed'` issue produces no recommendation; an
  issue with `source_issue_fingerprint IS NULL` produces no recommendation.
- **On-page templates**: all 7 areas generated with `issue_id IS NULL`;
  business-context interpolation verified exactly
  (`"Acme Plumbing - Plumbing in Austin, TX"`).
- **RPC return value**: the rows returned directly by the function call are
  set-equal to the table's `is_current=true` rows for that website
  immediately afterward — proving the RPC returns the canonical current set,
  not a transient/summary payload.
- **Idempotency**: a no-op regeneration against unchanged inputs leaves
  `updated_at` on an untouched row **exactly unchanged** (`pg_sleep(1)`
  between calls to make any spurious write detectable) and leaves the
  current-row count unchanged (11).
- **Regeneration-safety (the full three-way matrix, both issue-derived and
  on-page)**, using a second completed audit run with changed/removed
  issues and changed business context:
  - **Supersede** — an issue's mapped content changed while its
    recommendation was still `suggested`: old row retired
    (`is_current=false`, `superseded_by`→new id), new row inserted
    `suggested` with the updated content. Proven for both an issue-derived
    row (`schema`) and two on-page rows (`h1`, whose interpolated content
    changed when `business_name` changed).
  - **No write** — an issue's mapped content was unchanged
    (`duplicate_content`): exactly one row for that identity, before and
    after, no second/superseded row ever created.
  - **Retire** — an issue no longer appeared in the latest run while its
    recommendation was still `suggested` (`canonical`): retired
    (`is_current=false`, `superseded_by IS NULL`).
  - **Preserve (issue-derived)** — an issue no longer appeared in the latest
    run, but its recommendation had already been human-acted-on
    (`status='approved'`, simulating an operator decision via direct update,
    equivalent to what `seo_approval_transition` would do in the real
    workflow): left completely untouched — still current, still `approved`,
    `superseded_by` still `NULL`.
  - **Preserve (on-page)** — the `title` template's interpolated content
    changed (`business_name` changed) but its recommendation had already
    reached `ready_to_publish`: left completely untouched (content, status,
    `is_current` all unchanged); no second `title` row was inserted
    alongside it.
- **Dedup index enforcement**: a manual duplicate `INSERT` of a second
  `is_current=true` row sharing an existing current row's
  `source_issue_fingerprint` is rejected with `unique_violation`; same for a
  second `is_current=true` on-page row sharing an existing `area` (both
  partial unique indexes proven to actually reject duplicates, not merely
  present in the schema).
- **Isolation**: a sibling website in the same workspace and a website in a
  different workspace both remain untouched (zero rows) throughout.
- **Non-destructive empty case**: an audit-less website still generates all
  7 on-page recommendations (business-context templates do not depend on an
  audit existing) and zero issue-derived rows, with no error. (See §3 for
  why this is a deliberate interpretation, not a literal reading of the
  design doc's "no completed run → returns 0" note.)

## 2. Live two-session concurrency proof

Method identical to `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`: two
independent `supabase db query --linked -f` invocations (confirmed, as
before, to each hold one real transaction/session), staggered ~1.5s apart,
against a shared durable fixture website
(`cc900000-0000-0000-0002-000000000001`), with a third polling query against
`pg_stat_activity`.

- **Session A** (pid `1546640`, `query_start` `09:17:06.947747+00`):
  `BEGIN; SELECT ... FROM seo_recommendation_generate(website); SELECT
  pg_sleep(10); COMMIT;` — acquires the advisory lock inside the RPC, then
  holds the transaction open via `pg_sleep(10)`.
- **Session B** (pid `1546643`, `query_start` `09:17:08.309465+00`, ~1.36s
  after A): `BEGIN; SELECT ... FROM seo_recommendation_generate(website);
  COMMIT;` — calls the same RPC against the same website.
- **Poll #1** (T+3.5s) and **Poll #2** (T+6.5s), both against
  `pg_stat_activity`, show the **same** two rows at both timestamps:
  - A: `state=active, wait_event_type=Timeout, wait_event=PgSleep` (holding).
  - B: `state=active, wait_event_type=Lock, wait_event=advisory` (genuinely
    blocked on the advisory lock, not merely slow).
- B's call completed at `09:17:16.983053+00` — ~8.03s after B's own
  `query_start`, and essentially exactly when A's `pg_sleep(10)` (started at
  `09:17:06.95`) would release the lock — direct evidence B was blocked for
  the whole wait, not coincidentally slow.
- **Post-race state**: exactly **8 current rows** for the fixture website
  (1 issue-derived + 7 on-page), **8 distinct identities**, **0
  duplicates** — the concurrent race converged to the same canonical set the
  serialized case would have produced.
- Fixtures deleted afterward; zero residue confirmed by a direct follow-up
  count query.

## 3. One interpretation flagged during implementation

`SEO_RECOMMENDATION_GENERATION_ARCHITECTURE.md` §4.3 states that "if no
completed run exists, the RPC returns 0 without error" — written against
that document's original `RETURNS integer` shape. The current task
explicitly overrides the return shape to "the canonical current
recommendation set" (`SETOF seo_recommendations`), and §4.4 separately lists
the 7 on-page templates as part of "the desired set" unconditionally,
matching the existing mock's actual behavior (`onPageRecommendationsForWebsite`
runs regardless of whether any issues exist). Implemented interpretation:
**on-page templates are always generated** (they depend only on
website/business-context fields, which always exist); **only the
issue-derived half of the desired set is empty when no completed audit run
exists.** This is a clarification of an internal tension between two parts
of the design doc, not a deviation from any explicit requirement in either
document — flagged here per the "stop and report a conflict" instruction,
though it did not rise to a blocking conflict since a safe, mock-consistent,
non-destructive interpretation was directly available.

## 4. Environment-Control Reconciliation (2026-07-24)

**What happened:** the Stage 1 backend (§1–§2 above) was verified directly
against `Digi_SEO_Test`, ahead of the intended TEST-promotion gate in the
governing local → local-verification → TEST → production sequence. The
implementing session had no Docker/local Postgres/`psql` available (§5), and
proceeded to use `Digi_SEO_Test` on the strength of an interactive
in-session operator approval. That approval was real, but it was **not**
recorded in the controlling ChatGPT instruction trail that governs this
project — meaning, from the perspective of that authoritative trail, the
TEST application was unapproved. This was flagged and reconciled in a
follow-up task.

**Read-only audit performed before any change** (full detail: the
reconciliation task's own "TEST State Before Reconciliation" /
"Fixture Residue Audit" report): migration `20260724130000` was recorded as
applied; both new columns, both new partial unique indexes, and the RPC all
existed exactly as authored (owner `postgres`, `SECURITY DEFINER`,
`search_path=public`, `authenticated` EXECUTE granted / `anon` denied); zero
recommendation rows anywhere on `Digi_SEO_Test` had a non-null
`source_issue_fingerprint` or `generation_method` (the 8 pre-existing
recommendation rows all pre-date this work by 15 days, created 2026-07-09,
and were never touched — confirmed by an unchanged row-signature hash before
and after rollback); zero fixtures remained from either the SQL verification
suite or the live concurrency test; zero other functions, views, or
constraints depended on the RPC or the two new indexes; the SSO migration
`20260720121000` remained pending throughout.

**Rollback safety was proven** (all six required conditions held) and
`ROLLBACK NOT PROVEN SAFE` was **not** triggered.

**Rollback executed:** `supabase/test/seo_recommendation_generate_rollback_TEST_ONLY.sql`
(revoke grants → `DROP FUNCTION` → `DROP INDEX` ×2 → `ALTER TABLE DROP
COLUMN` ×2, idempotent, self-verifying) applied via `supabase db query
--linked -f`, followed by `supabase migration repair --status reverted
20260724130000`.

**Post-rollback state, directly verified:** RPC, both indexes, and both
columns no longer exist; migration `20260724130000` no longer recorded as
applied (`remote: ""`, same shape as the still-pending SSO migration); every
other migration version (`20260711120001` through `20260724120040`)
unchanged; `20260720121000` (SSO) still pending; zero leftover fixtures or
temp helper objects of any kind; the 8 pre-existing, unrelated
`seo_recommendations` rows are **byte-for-byte identical** before and after
(row count 8, content+timestamp signature hash unchanged). `Digi_SEO_Test`
is now in the same state it was in before this feature's migration was ever
applied.

**Current state:** Stage 1 is **locally implemented** (migration, RPC, SQL
verification suite, this record, and the status-doc updates all still exist
in the temporary worktree `feat/seo-recommendation-generate-stage1`) but is
**not locally database-verified** — no local Postgres environment is
available in this session to run the SQL verification suite or the
concurrency proof against. The §1–§2 evidence above is retained for its
technical content (it demonstrates the design behaves as intended) but must
not be cited as satisfying the local-verification gate.

## 5. Local Verification Blocker

Exact missing capability, confirmed by direct tool checks in this
environment:

- `docker`: not found on `PATH`.
- Local Supabase stack (`supabase start`): not usable — it requires Docker
  to run its local Postgres/Auth/Storage containers, which is unavailable.
- Local PostgreSQL server/binaries (`postgres`, `pg_ctl`): not found.
- `psql`: not found.
- `brew` (which could otherwise install any of the above): not found.

**Minimum operator action needed to enable true local verification** (any
one of the following is sufficient):

1. Provide a Docker-compatible container runtime reachable from this
   environment (Docker Desktop/Engine, or a compatible alternative such as
   Colima/Podman configured as a Docker-API-compatible socket), so `supabase
   start` can run a local Postgres instance; **or**
2. Provide a reachable local/standalone PostgreSQL instance (connection
   string) that this session can point `supabase db query --db-url` at,
   separate from `Digi_SEO_Test` and production; **or**
3. Install `psql` (or the Postgres client tools) plus a running local
   Postgres server through whatever package manager is authorized for this
   machine.

No system software was installed in this task, and `Digi_SEO_Test` was not
used again as a substitute after the rollback.

## 6. Genuine Local Verification (2026-07-24, completed — the current acceptance basis)

Docker was installed by the operator, confirmed working from scratch (fresh
`docker --version`/`docker info`/`docker ps`, Docker Desktop, Server Version
`29.6.2`), and used to run a real local Supabase stack — full method now
recorded in `SEO_LOCAL_DATABASE_SETUP.md`.

**Isolation, proven before anything was applied:** local Postgres
`inet_server_addr` = `172.18.0.2` (private Docker-bridge address),
`current_database` = `postgres`, `version()` = PostgreSQL 17.6; all 12
containers named `supabase_<service>_wt-recommendation-stage1`; `.env.local`
directly confirmed to point `VITE_SUPABASE_URL` at `https://
snyzotgwwfomgafrsvfm.` — `Digi_SEO_Test`'s exact ref, categorically
different from the local addressing. **`TARGET IS LOCAL AND IS NOT
DIGI_SEO_TEST OR PRODUCTION`**, confirmed.

**Baseline conflict discovered and resolved:** `supabase start`'s first-boot
bootstrap applies every `.sql` file in `supabase/migrations/`
unconditionally, which included the intentionally-deferred SSO migration
(`20260720121000`). Read in full: the migration is purely additive/
non-destructive (a new, empty table plus a backward-compatible
`seo_is_global_admin()` fallback that adds, never removes, a check path) —
`SEO_DECISIONS.md` A14's rationale for deferring it is scope-control, not
safety. Resolved via the smallest safe local-only mechanism: temporarily
moved the migration file out of `supabase/migrations/`, ran `supabase db
reset` (rebuilding from every remaining migration), verified the result
(53 `public` tables, SSO table absent, Recommendation Stage 1 schema
present), ran a **second** `db reset` to prove reproducibility (identical
result both times), then moved the file back into `supabase/migrations/`
— the worktree's tracked file set is unchanged; only the running local
database's applied-migration state differs, exactly mirroring
`Digi_SEO_Test`'s own deferred state. Full method:
`SEO_LOCAL_DATABASE_SETUP.md` "Baseline rule: the deferred SSO migration."

**RPC contract, directly re-verified on the local database:** owner
`postgres`, `SECURITY DEFINER = true`, `search_path = public`,
`authenticated` EXECUTE granted, `anon` EXECUTE denied, `RETURNS SETOF
seo_recommendations` — all confirmed by direct query, matching the original
design exactly.

**Tooling correction discovered:** `supabase db query --local -f
<multi-statement-script>` fails with `cannot insert multiple commands into
a prepared statement` — a real difference between the `--linked` (Supabase
Management API, accepts a full batch) and `--local`/`--db-url` (direct
Postgres connection, extended query protocol, one statement per prepared
statement) code paths, not a defect in any verification script. Worked
around by running the script via `psql` **inside** the local Postgres
container (`docker exec -i supabase_db_wt-recommendation-stage1 psql -U
postgres -d postgres -v ON_ERROR_STOP=1 < <file>`), which uses the simple
query protocol and has no such restriction — still fully local, never
leaves the container.

**Prerequisite discovered and satisfied:** the verification script's shared
UI-seed `auth.users` fixture ids (owner/admin/team_member/client/cross)
exist as real accounts on `Digi_SEO_Test` but not in a fresh local
database — seeded once via a direct `INSERT INTO auth.users` (id-only
requirement; no real credential created, since the scripts authenticate via
`request.jwt.claims`, never a real password). Documented in
`SEO_LOCAL_DATABASE_SETUP.md`.

**Full SQL verification suite (`supabase/test/seo_recommendation_generate_verification.sql`),
run twice, both exit code 0:** every NOTICE-level checkpoint printed and
passed explicitly (more directly visible than the `--linked` runs against
`Digi_SEO_Test` ever were, since NOTICE output wasn't surfaced by that code
path) — `CONTRACT ok`; `owner allowed ok (n=11)`; `admin allowed ok`;
`team_member allowed ok`; `client denied ok`; `non-member denied ok`;
`cross-tenant denied ok`; `no-leak (missing website == unauthorized) ok`;
`anon EXECUTE denial ok`; `mapping + fields + eligibility + on-page
interpolation ok`; `RPC return value equals canonical current set ok`;
`idempotency (no write on unchanged regeneration) ok`;
`regeneration-safety full matrix (supersede/no-write/retire/preserve x2)
ok`; `dedup index enforcement ok`; `isolation (other website + other
workspace) ok`; `no-completed-audit generation (on-page only,
non-destructive) ok`; `TEARDOWN ok — net-nothing`; `ALL RECOMMENDATION
GENERATION STAGE 1 CHECKS PASSED`. Independent residue confirmation after
both runs: zero rows across every fixture-touched table
(`ws=sites=runs=issues=recs=leftover_fn=0`).

**Live two-session concurrency proof, against the local database:** Session
A (`BEGIN; call the RPC; pg_sleep(10); COMMIT;`) acquired the advisory lock
and held it; Session B, staggered ~1.5s later, called the same RPC against
the same fixture website. Two polls (T+3.5s, T+6.5s) against
`pg_stat_activity` both showed, simultaneously: Session A —
`wait_event_type=Timeout, wait_event=PgSleep` (holding); Session B —
`wait_event_type=Lock, wait_event=advisory` (genuinely blocked, not merely
slow). Session B's call completed at essentially the exact moment Session
A's `pg_sleep(10)` would release the lock (~8.6s after B's own call
started, matching A's remaining sleep duration almost exactly). Post-race
state: exactly 8 current rows, 8 distinct identities, 0 duplicates — the
race converged cleanly. Fixtures deleted afterward; zero residue confirmed
directly.

**Conclusion:** every requirement the earlier environment-control
reconciliation identified as unmet — genuine local verification, not
`Digi_SEO_Test`, not mocked concurrency — was satisfied with direct
evidence. **Stage 1 acceptance review is complete; acceptance is approved.**
The implementation is committed to `feat/seo-recommendation-generate-stage1`
and formally MODULE-LOCKED (backend-only scope — see
`docs/markdown/MODULE_LOCKS.md`). It remains unpushed and unmerged to
`main`; Stage 2 (frontend) has not started.
