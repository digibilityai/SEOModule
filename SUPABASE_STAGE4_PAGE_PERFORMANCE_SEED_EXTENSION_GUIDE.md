# Supabase Stage 4 Page Performance — UI Seed Extension Guide

**Script:** `supabase/test/seo_seed_stage4_page_performance_ui_extension.sql`

> **TEST DATA ONLY. DO NOT RUN ON PRODUCTION.** This guide and the script it
> documents target the **test** Supabase project only — the same one Stage
> 1-4 migrations, all three smoke tests, and the base UI seed dataset were
> already applied and verified against (see `BACKEND_MILESTONE_HANDOFF.md`
> and `SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md`).

---

## 1. Purpose

Stage 4 (Page Performance Tracker — `seo_page_inventory`, `seo_page_keywords`,
`seo_page_performance_snapshots`, `seo_page_performance_latest` view) is
written, applied, and smoke-tested on the test Supabase project (see
`SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`), but the base UI
test dataset seed (`seo_seed_ui_test_dataset.sql`) predates Stage 4 and has
no Page Performance rows. This script adds realistic page inventory, mapped
keywords, and performance snapshot data **under that same seeded workspace
and website**, so that once Page Performance frontend service wiring lands
(a separate, later task — not part of this script), Supabase-mode UI has
non-empty data to render instead of empty states.

This is a **plain data seed**, not a correctness/RLS test — see
`supabase/test/seo_stage4_page_performance_smoke_test.sql` for that.

## 2. What This Seed Extension Creates

Attaches to the base seed's existing workspace (`44444444-0000-0000-0001-000000000001`,
"UI Seed Workspace") and website (`44444444-0000-0000-0002-000000000001`,
`https://ui-seed-digibility.example`) — it does **not** create a new
workspace or website of its own.

| Area | What's created |
|---|---|
| Page inventory | 7 pages: homepage, services, blog listing, a flagship blog post ("SEO Checklist for Small Business Websites" — matches the Content Studio seed topic), a local SEO landing page, a contact page, and a pricing page. Varied `page_type`, `indexability_status`, `content_status`, `priority`, and a mix of `is_tracked` true/false. |
| Mapped keywords | 13 keywords across the 5 tracked pages, covering all 6 `keyword_type` values (primary/secondary/semantic/question/branded/local), all 3 `device` values, all 4 `search_engine` values, and a mix of `target_location` (Austin TX / United States / untargeted). |
| Performance snapshots | 20 snapshot rows: 8 page-or-keyword combinations get an older (14 days ago) + newer (today) snapshot pair so real period-over-period movement shows (deltas, `previous_*` fields), plus 4 single-snapshot combinations for newly-launched (`new`) and not-yet-tracked (`no_data`) pages. All 5 `movement_status` values are represented in the resulting "latest" rows: **improving, stable, declining, new, no_data**. |
| `seo_page_performance_latest` view | Automatically reflects 12 rows (one per distinct page/keyword combination) once the snapshots above are seeded — no separate insert needed, since it's a read-only view over the snapshots table. |

**Source is always `manual_seed`** — no real GSC/GA4 data, no crawler, no
external API call anywhere in this script.

**Not created:** a new workspace/website (reuses the base seed's), any
`seo_decline_diagnoses` rows (that module doesn't exist yet — `diagnosis_hint`
on a few snapshot rows is just descriptive free text, not a diagnosis
record), any Storage/asset row, any change to Stage 1-3 seed data.

## 3. Prerequisites

Before running this script, confirm on the **test** Supabase project:

1. Stage 1-4 migrations are applied (`20260711120001` through `20260711120013`
   — see `BACKEND_MILESTONE_HANDOFF.md` §3-4 for the checkpoint).
2. The base UI seed dataset is already applied
   (`supabase/test/seo_seed_ui_test_dataset.sql` — see
   `SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md`). This script's SECTION 0.5
   dependency guard checks for the base seed's workspace/website and raises
   a clear exception (`"Base UI seed dataset must be applied before this
   Stage 4 extension."`) if either is missing — it will not proceed and
   will not create a workspace/website of its own.
3. At least two test `auth.users` already exist on the test project (an
   owner-role and a team_member-role user). Reusing the same two users the
   base UI seed used is recommended but not required.

## 4. Where to Get UUIDs

Same lookup as the base UI seed guide — run this in the Supabase SQL Editor
(test project) if you don't already have the UUIDs handy:

```sql
select id, email
from auth.users
where email in (
  'owner-test@example.com',
  'team-test@example.com'
)
order by email;
```

Replace the two email addresses with your actual test users' emails. Copy
each returned `id` (a UUID) into the matching placeholder described in §5.

## 5. How to Replace Placeholders

Open `supabase/test/seo_seed_stage4_page_performance_ui_extension.sql` and
find **SECTION 0** near the top:

```sql
SELECT set_config('seoseed4.owner_user_id', 'REPLACE_WITH_OWNER_USER_UUID', false);
SELECT set_config('seoseed4.team_user_id',  'REPLACE_WITH_TEAM_USER_UUID',  false);
```

Replace each `'REPLACE_WITH_..._UUID'` string with a real UUID from §4, for
example:

```sql
SELECT set_config('seoseed4.owner_user_id', '48c479db-aedf-452e-af43-05ed1180baaa', false);
```

**Paste a UUID, never an email.** The script's guard block checks the value
is UUID-shaped and raises a clear exception (naming exactly which variable
is wrong) if you leave a placeholder in place or paste an email by mistake.

## 6. How to Run in Supabase SQL Editor

1. Confirm your Supabase Dashboard is pointed at the **test** project.
2. Confirm the prerequisites in §3 are met (Stage 1-4 applied, base UI seed
   already run).
3. Open **SQL Editor** in the Supabase Dashboard.
4. Copy the full contents of
   `supabase/test/seo_seed_stage4_page_performance_ui_extension.sql`.
5. Paste into a new SQL Editor query.
6. Replace the two placeholders per §5.
7. Click **Run**.
8. Read the **Results/Notices** pane — the last result set is a compact
   verification-count table (see §7). If the placeholder guard or the base
   UI seed dependency guard raised an exception instead, fix the named
   issue and re-run — nothing is partially applied.

Re-running the whole script is always safe — every insert is
`ON CONFLICT (id) DO NOTHING`, so running it twice does not create
duplicates or error out.

## 7. Expected Verification Counts

The script's final `SELECT` prints one row per entity, scoped to the base
seed's workspace and this extension's `66666666-` rows only:

| entity | count |
|---|---|
| page inventory rows | 7 |
| page keywords | 13 |
| performance snapshots | 20 |
| latest view rows | 12 |
| latest: improving | 4 |
| latest: stable | 2 |
| latest: declining | 2 |
| latest: new | 2 |
| latest: no_data | 2 |

If any count is `0` where a non-zero value is expected, check the Notices
pane for an earlier raised exception (Postgres stops running remaining
statements after an unhandled exception in a pasted multi-statement script).

## 8. How to Test in the UI

**Page Performance frontend service wiring is complete (Phase 14A.2, live-tested)**
— `src/services/performanceService.ts` reads Stage 4 behind the mock/Supabase
adapter. To exercise this seed data in the UI:

1. Set `.env.local` (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`,
   `VITE_SEO_DATA_MODE=supabase`) and restart `npm run dev`.
2. Sign in at `/seo/dev/auth-test` as one of the base UI seed's test users.
3. Use that page's dev-harness "Test Page Performance Service" button (plus
   "Test Page Performance Latest View" / "Test Page Performance History") to
   confirm non-zero counts.
4. Visit `/seo/page-performance` directly and confirm the 7 seeded pages,
   their mapped keywords, and their improving/stable/declining/new/no_data
   status labels render.

This data is also inspectable via the Supabase Table Editor or the
verification `SELECT` in this script.

## 9. Warnings

- **Test only.** This script only ever runs against whatever project you
  paste it into — always double-check the Dashboard's project name/URL
  before running.
- **Production is never touched.**
- **No real GSC/GA4 integration.** `source` is always `'manual_seed'` on
  every row this script inserts — no external API call, no OAuth, no
  credentials anywhere in this script.
- **No real crawler.** Page inventory rows are hand-written seed data, not
  the output of an actual site crawl.
- **No Supabase Auth users are created.** The script requires two existing
  `auth.users` UUIDs and fails fast with a clear error if either is missing
  or malformed.
- **No service role key is used, required, or referenced anywhere** in this
  script or this guide.

## 10. Optional Teardown

The bottom of the script has three commented-out `DELETE` statements that
remove only this extension's rows (identified by the `66666666-` UUID
prefix) — it does **not** touch the base UI seed's workspace, website,
onboarding, audit, approval, or content data, and does not touch any other
seed or smoke test's rows. Uncomment and run manually only if you want to
remove this extension's data from the test project.
