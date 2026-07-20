# SEO Backend — Stage 4 Migration Plan: Page Performance Tracker (Phase 14A.1)

**Status: Design plan — now implemented and test-verified.** The four
migration files this document describes were dry-run clean, applied to the
fresh test Supabase project, structurally verified (3 tables, RLS enabled on
all 3, 1 view, 6 policies), and smoke-tested successfully. This document
remains as the design rationale (why each table/policy shape was chosen);
see `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md` for the actual
`✅ Test Verification Checkpoint`, what was created, and next steps.
**Production has not been touched.**

---

## 1. Purpose

Page Performance Tracker is the next SEO module after Content Studio
(Phases 12C-12G backend, 13A-13F frontend wiring, all complete and
test-verified — see `BACKEND_MILESTONE_HANDOFF.md`). Today it exists only as
a flat mock (`src/mocks/performanceMockData.ts`, `src/types/performance.ts`)
combining page + single-primary-keyword + metrics into one row per page.

Phase 14A.1 designs a normalized Stage 4 backend so the eventual real product
can:
- track a website's pages as first-class inventory, independent of any one
  keyword,
- map **multiple** keywords per page (not just one primary keyword, as the
  current mock does),
- store **periodic** performance snapshots (clicks, impressions, CTR,
  average position, and period-over-period deltas) so ranking movement is a
  real time series, not a single before/after pair,
- give a future Decline Diagnosis module (mentioned in
  `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §C as `seo_decline_diagnoses`) a
  simple, ready-made seam (`diagnosis_hint`) instead of needing a schema
  change later,
- keep GSC/GA4 as a **placeholder** data `source` value only — no real
  integration, no external API calls, no cron jobs ship in this phase.

This keeps Digibility's product philosophy: a simple execution cockpit where
business-friendly summaries ("this page is declining") come first and
technical detail (raw clicks/impressions/position deltas) comes second — the
schema separates the two so a future read layer can present either view
without re-querying differently.

## 2. Tables Proposed

| # | Table | Migration file |
|---|---|---|
| 1 | `seo_page_inventory` | `20260711120010_seo_stage4_page_inventory.sql` |
| 2 | `seo_page_keywords` | `20260711120011_seo_stage4_page_keywords.sql` |
| 3 | `seo_page_performance_snapshots` | `20260711120012_seo_stage4_performance_snapshots.sql` |
| — | `seo_page_performance_latest` (view, not a table) | `20260711120013_seo_stage4_performance_latest_view.sql` |

Three tables, one read-only view, four migration files — one concern per
file, matching the Stage 1-3 convention (e.g. Stage 2 split audit /
recommendations / approval into three separate additive migrations rather
than one large one).

## 3. Why Each Table Exists

- **`seo_page_inventory`** — the anchor. A page needs to exist independently
  of any keyword, because a page can have zero keywords mapped yet (freshly
  discovered), and because page-level fields (title, meta description, page
  type, indexability, canonical URL, content freshness) don't belong to any
  single keyword. Every keyword mapping and every snapshot references a
  `page_id`, mirroring how `seo_websites` anchors every other Stage 1-3
  module.
- **`seo_page_keywords`** — the current mock's `PagePerformance` interface
  has exactly one `primary_keyword` plus a `secondary_keywords: string[]`
  array on the page row itself. That flat shape can't express per-keyword
  metrics (device, search engine, target location, or per-keyword clicks/
  position), which the product intent explicitly asks for ("mapped keywords
  per page ... ranking movement"). A separate table lets each keyword carry
  its own targeting metadata and its own performance history via
  `seo_page_performance_snapshots.page_keyword_id`.
- **`seo_page_performance_snapshots`** — periodic, not a single current/
  previous pair. The mock's `clicks_previous_period` / `previous_avg_position`
  fields only ever hold **one** prior comparison point. A real snapshot table
  lets the product show an actual trend over many periods later, while still
  supporting today's simpler "current vs. previous" comparison via the two
  most recent rows for a page/keyword. `page_keyword_id` is nullable so a
  snapshot can be either page-level (aggregate, no specific keyword) or
  keyword-specific — both are legitimate views the product needs (a page's
  overall trend, and a specific keyword's ranking trend).
- **`seo_page_performance_latest`** (view) — nearly every read the frontend
  will eventually do ("show me this website's pages and their current
  status") wants only the newest snapshot per page/keyword, not the full
  history. A read-only view avoids every future service needing to
  hand-write the same `DISTINCT ON ... ORDER BY snapshot_date DESC` query,
  and avoids needing a maintained "latest" boolean column (which would need
  a trigger to keep in sync, unlike Stage 2's `is_latest` on audit runs,
  where only one run is ever "current" per website — here many
  page/keyword combinations are each independently "current").

## 4. RLS Model

RLS is enabled on all three new tables. The view uses
`security_invoker = true` so it inherits `seo_page_performance_snapshots`'
RLS at query time instead of needing its own duplicate policy — see
`SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md` §4 for the Postgres
version assumption this requires (15+, already implicitly relied on by this
project's Supabase test instance since all prior migrations already
applied there).

Every table follows the exact same two-policy shape already used for
`seo_audit_issues` / `seo_recommendations` in Stage 2 (system/service-layer
generated data, not client-authored):

- **`<table>_select`** — `is_seo_workspace_member(workspace_id) OR seo_is_global_admin()`.
  Any active workspace member (owner/admin/team_member/client) can read.
- **`<table>_write`** (`FOR ALL`, covers INSERT/UPDATE/DELETE) —
  `seo_role_in(workspace_id, ARRAY['owner','admin','team_member']) OR seo_is_global_admin()`.
  Clients are excluded from every write path — they read only.

No new helper functions are introduced. All three tables/the view reuse the
exact Stage 1 helpers already relied on everywhere else:
`is_seo_workspace_member(workspace_id)`, `seo_role_in(workspace_id, roles[])`,
`seo_is_global_admin()`. `can_manage_seo_workspace` is not needed here since
no delete-only distinction is required (see §6).

## 5. Role Access Model

| Role | Read | Insert/Update/Delete |
|---|---|---|
| owner | ✅ (workspace-scoped) | ✅ |
| admin | ✅ (workspace-scoped) | ✅ |
| team_member | ✅ (workspace-scoped) | ✅ |
| client | ✅ (workspace-scoped) | ❌ (RLS denies — matches the task's explicit requirement) |
| non-member | ❌ | ❌ |
| global admin | ✅ (all workspaces) | ✅ (all workspaces) |

This matches the exact same shape as Stage 2's `seo_audit_issues` /
`seo_recommendations` access model: page inventory, keyword mappings, and
performance numbers are system/service-layer/team-generated data that a
client views but never authors directly — consistent with the product's
"client cannot run the technical machinery, only reviews outcomes" rule
already enforced everywhere else in the schema (`BACKEND_MILESTONE_HANDOFF.md`
§7). Role source is `seo_workspace_members.seo_role`, never `profiles.role`
— no new/separate auth system, no service role required for normal reads or
manager writes.

## 6. What Is Not Included Yet

- **No real GSC/GA4/CMS integration.** `source` is a plain text column with
  `gsc`/`ga4`/`import` as allowed **placeholder** values — no external API
  call, no OAuth, no credentials, no edge function exists or is created in
  this phase.
- **No cron job / scheduled import.** Nothing in these migrations schedules
  anything. Snapshot rows only ever arrive via a normal INSERT (manual seed,
  a future service-role import job, or a future authenticated write) — never
  automatically.
- **No crawler.** `seo_page_inventory` rows are not discovered by crawling
  in this phase; a future job would populate them, exactly like Stage 2's
  audit issues are written by "the service role / system," never by a
  built-in crawler.
- **No Decline Diagnosis module.** `movement_status` and `diagnosis_hint` are
  simple fields a future `seo_decline_diagnoses` table (already named in
  `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §C) can read from — no diagnosis
  logic, no cause inference, no confidence scoring ships here.
- **No frontend wiring.** `src/services/performanceService.ts` is untouched;
  the mock adapter (`performanceMockData.ts`) is untouched; no UI component
  changes. This is backend-schema-only, matching the Stage 1-3 precedent
  where each stage's tables existed for a full phase before any service
  wired to them (Stage 1 in Phase 12C, wired in Phase 13B; Stage 2 in Phase
  12E, wired in Phase 13C/13D; Stage 3 in Phase 12G, wired in Phase 13E).
- **No delete UI.** RLS technically permits owner/admin/team_member to
  delete rows (via the same `FOR ALL` policy shape Stage 2/3 already use for
  their manager-write tables) as a defense-in-depth backstop, but no service
  or UI in this phase calls delete on any of these tables.
- **No Stage 4 UI test dataset seed.** `supabase/test/seo_seed_ui_test_dataset.sql`
  is untouched per explicit instruction — a Stage 4 seed extension is a
  separate, later task now that these migrations are applied and
  smoke-tested (see `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md` §9).

## 7. Test Strategy

`supabase/test/seo_stage4_page_performance_smoke_test.sql` follows the exact
same structure as `seo_stage2_smoke_test.sql` / `seo_stage3_content_studio_smoke_test.sql`
and has now been run to completion against the test project (see the
`✅ Test Verification Checkpoint` in `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`):

1. Placeholder-guarded test user UUIDs (owner/admin/team/client/nonmember) —
   no `auth.users` insert, no email-as-UUID mistake (guard raises a clear
   exception if any placeholder is left unfilled).
2. A disposable test workspace + website + membership, seeded under the
   `55555555-` UUID prefix (distinct from Stage 2's `aaaaaaaa-`/`bbbbbbbb-`/
   etc., Stage 3's `33333333-`, and the UI dataset seed's `44444444-`, so
   this smoke test cannot collide with any of them).
3. Role-simulated (`_seo4_login()`/`SET LOCAL ROLE authenticated`) assertions
   inside `BEGIN ... ROLLBACK` blocks, exactly like both existing smoke
   tests, so nothing it inserts survives the test run except the initial
   disposable setup rows (which are themselves idempotent/re-runnable).
4. Coverage: owner/admin/team/client SELECT access; client INSERT/UPDATE
   denial; non-member isolation; page inventory / keyword / snapshot insert
   as a manager; the latest-snapshot view returns the expected row; CHECK
   constraints reject an invalid `ctr` (>1), invalid `movement_status`,
   invalid `device`, and invalid `source`.
5. `RAISE NOTICE 'PASS: ...'` / `RAISE EXCEPTION 'FAIL: ...'` style output,
   matching both existing smoke tests exactly, so it reads the same way in
   the Supabase SQL Editor's Notices pane.
6. Optional teardown (delete-only-this-test's-workspace) is commented out at
   the bottom, exactly like both existing smoke tests.

An initial run failed on the non-member isolation check; this was diagnosed
as a smoke-test simulation defect only (the check wasn't switching the
session to the `authenticated` role, so it ran under the SQL Editor's
`postgres`/`BYPASSRLS` connection instead of genuinely exercising RLS — not
a migration or policy defect). The smoke test was fixed and re-run to
completion with no `FAIL`. Full detail in
`SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`.

## 8. Production Gating Reminder

**Production has not been touched.** Everything in Phase 14A.1 — the four
migration files, the smoke test, dry-run, apply, and structural/smoke
verification — happened only against the disposable **test** Supabase
project:

1. Confirmed the target was the same disposable **test** Supabase project
   Stage 1-3 and both existing smoke tests already ran against (never a
   production project).
2. Dry-run (Supabase CLI migration diff) completed clean before `apply`.
3. Applied, then ran `seo_stage4_page_performance_smoke_test.sql` to
   completion with no `FAIL` — the same bar Stage 1-3 met before being
   marked test-verified in `BACKEND_MILESTONE_HANDOFF.md`.
4. **Recommended next steps** (separate, later tasks): extend the UI test
   dataset seed (see §6), then begin Page Performance frontend service
   wiring (`performanceService.ts` remains untouched by Stage 4).
5. **Production apply** still requires the same sign-off gate every prior
   stage required: target-project confirmation, backup/branch strategy,
   final migration review, and explicit developer/technical owner sign-off
   — see `BACKEND_MILESTONE_HANDOFF.md` §5. No production credentials, no
   production connection, no production apply has happened or is requested
   as part of Phase 14A.1 or any phase described in this document.
