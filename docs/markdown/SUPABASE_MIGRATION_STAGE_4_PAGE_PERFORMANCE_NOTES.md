# SEO Backend — Stage 4 Migration Notes: Page Performance Tracker (Phase 14A.1)

**Status: SQL written, self-reviewed, dry-run clean, applied to the fresh
test Supabase project, structurally verified, and smoke-tested.** Matches
the same test-verified bar Stage 1-3 met before being marked complete in
`BACKEND_MILESTONE_HANDOFF.md` — see the checkpoint below. **Production has
NOT been touched.**

## ✅ Test Verification Checkpoint (fresh test Supabase project)

- [x] Dry-run passed
- [x] Applied to fresh test Supabase project (`…120010` → `…120013`, after Stage 1)
- [x] 3 Stage 4 tables visible: `seo_page_inventory`, `seo_page_keywords`, `seo_page_performance_snapshots`
- [x] RLS = `true` for all 3 tables
- [x] 1 view visible: `seo_page_performance_latest`
- [x] 6 policies visible: `seo_page_inventory_select`, `seo_page_inventory_write`,
      `seo_page_keywords_select`, `seo_page_keywords_write`,
      `seo_page_performance_snapshots_select`, `seo_page_performance_snapshots_write`
- [x] Smoke test (`supabase/test/seo_stage4_page_performance_smoke_test.sql`) run to
      completion — `=== STAGE 4 SMOKE TEST COMPLETE — check the Messages/Notices tab
      for PASS/FAIL ===`, no red `ERROR` popup. An initial run failed on the
      non-member isolation check; diagnosed as a **smoke-test simulation defect
      only** (the RLS-read assertions weren't switching the session to the
      `authenticated` role, so they ran under the Supabase SQL Editor's
      `postgres`/`BYPASSRLS` connection instead of genuinely exercising RLS —
      no migration or policy defect). Fixed by wrapping each role check in an
      explicit `BEGIN; ... SET LOCAL ROLE authenticated; ... ROLLBACK;`
      transaction, matching the pattern already proven in the Stage 2/3 smoke
      tests. Re-run completed with no `FAIL`.

**Production status:** These migrations are **test-verified but not
production-applied**. Production apply should happen only after: (1)
confirming the target is the correct shared Digibility Supabase project, (2)
a backup/branch strategy is in place, and (3) a final review/sign-off — see
§10 and `BACKEND_MILESTONE_HANDOFF.md` §5.

**Not yet started (separate, later work):** Stage 4 frontend service wiring
(`src/services/performanceService.ts` is untouched; the mock adapter
`performanceMockData.ts` is untouched; no UI component changed) and a Stage 4
UI test dataset seed extension (`supabase/test/seo_seed_ui_test_dataset.sql`
is untouched). See §9 for the recommended order.

---

## 1. What Was Created

Four new additive migration files (Stage 4, migrations 10-13 in the existing
timestamp sequence) plus a plan document, this notes document, and a smoke
test — all now applied and exercised against the fresh test Supabase
project. Nothing else changed — no app code, no existing migration, no
Core/reference-app file.

## 2. Tables

| Table | Migration | Rows represent |
|---|---|---|
| `seo_page_inventory` | `20260711120010_seo_stage4_page_inventory.sql` | One discovered/tracked page per website |
| `seo_page_keywords` | `20260711120011_seo_stage4_page_keywords.sql` | One keyword mapped/tracked against a specific page |
| `seo_page_performance_snapshots` | `20260711120012_seo_stage4_performance_snapshots.sql` | One periodic performance data point for a page (or page+keyword) from one data source |

All three carry the standard `website_id` (FK, source of truth) +
`website_url` (text snapshot) pair already used on every Stage 1-3
operational table, plus `workspace_id` (FK) for RLS scoping. `seo_page_keywords`
and `seo_page_performance_snapshots` also carry `page_url` (and, on
snapshots, `keyword`) as denormalized snapshots of their parent, mirroring
how Stage 2's `seo_audit_issues`/`seo_recommendations` snapshot `website_url`.

**Full column lists, CHECK constraints, and indexes** are in the migration
files themselves (each column is commented where its purpose isn't obvious
from the name alone) — this notes file summarizes rather than repeats them.

## 3. Views

| View | Migration | Purpose |
|---|---|---|
| `seo_page_performance_latest` | `20260711120013_seo_stage4_performance_latest_view.sql` | One row per `(page_id, page_keyword_id)` — the newest `seo_page_performance_snapshots` row for that pair, by `snapshot_date` then `created_at` |

Declared `WITH (security_invoker = true)` — **this requires Postgres 15 or
newer**. This is not a new requirement introduced by Stage 4; Supabase's
managed Postgres has shipped 15+ for all new projects for a long time, and
nothing about the already-applied Stage 1-3 migrations would have worked
differently on an older version, so this assumption is consistent with the
project's existing test instance. `security_invoker = true` means the view
is evaluated with the **querying user's own privileges**, so it inherits
`seo_page_performance_snapshots`' RLS policies exactly instead of running as
the (RLS-bypassing) view owner — no duplicated policy logic, no accidental
RLS bypass via the view. An explicit `GRANT SELECT ... TO authenticated` is
included since views need their own grant independent of the underlying
table's grant; RLS still applies per-row on top of that grant.

## 4. RLS Policies

Every one of the three tables gets exactly two policies, matching the exact
shape already used for `seo_audit_issues` in Stage 2 (system/service-layer
generated data — see `20260711120004_seo_stage2_audit.sql` for the
precedent this mirrors):

```sql
-- SELECT: any active workspace member (incl. client) + global admin
CREATE POLICY <table>_select ON public.<table>
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

-- ALL (insert/update/delete): owner/admin/team_member + global admin only
CREATE POLICY <table>_write ON public.<table>
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
```

No new helper functions were created — all three tables reuse the exact
Stage 1 helpers (`is_seo_workspace_member`, `seo_role_in`, `seo_is_global_admin`)
already relied on everywhere else in the schema. The view has no policies of
its own (views can't have RLS policies directly) — it inherits the
snapshots table's policies via `security_invoker`.

**Client access**: read-only across all three tables and the view. This
matches the task's explicit requirement and the existing product rule
(`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §F) that clients review outcomes
but don't author the technical machinery behind them.

## 5. Constraints

| Table | Column | Allowed values / rule |
|---|---|---|
| `seo_page_inventory` | `page_type` | `homepage, service_page, blog, product_page, category_page, location_page, landing_page, other` — deliberately identical to the app's existing `PageType` (`src/types/performance.ts`) to ease future frontend mapping |
| | `indexability_status` | `indexable, noindex, blocked, unknown` |
| | `content_status` | `fresh, aging, stale, unknown` — feeds a future Decline Diagnosis `freshness_issue` cause |
| | `priority` | `low, medium, high` |
| | *(unique)* | partial unique index `(website_id, page_url) WHERE is_active` — prevents duplicate active pages; an archived page (`is_active=false`) can be re-added as a fresh row without conflict |
| `seo_page_keywords` | `keyword_type` | `primary, secondary, semantic, question, branded, local` |
| | `search_intent` | `informational, navigational, transactional, commercial` — identical to Stage 3's `seo_content_keyword_plans.intent` |
| | `device` | `desktop, mobile, all` |
| | `search_engine` | `google, bing, ai_overview, other` |
| | `priority` | `low, medium, high` |
| | *(unique)* | partial unique index `(page_id, keyword, COALESCE(target_location, ''), device, search_engine) WHERE is_tracked` — see §6 note on the `COALESCE` technique |
| `seo_page_performance_snapshots` | `source` | `manual_seed, gsc, ga4, system, import` — `gsc`/`ga4` are **placeholder values only**, no integration exists |
| | `movement_status` | `improving, stable, declining, new, no_data` — a **new**, Stage-4-specific enum; intentionally not identical to the app mock's `PagePerformanceStatus` (`improving \| stable \| declining \| needs_refresh \| not_enough_data`) since `needs_refresh`/`not_enough_data` are presentation-layer conclusions a future Decline Diagnosis read layer derives, not raw backend facts |
| | `clicks`, `impressions`, `previous_clicks`, `previous_impressions` | `>= 0` |
| | `ctr`, `previous_ctr` | `NULL` or between `0` and `1` inclusive |
| | `average_position`, `previous_average_position` | `NULL` or `> 0` |
| | `period_end >= period_start` | table-level CHECK |
| | *(unique)* | unique index `(page_id, COALESCE(page_keyword_id, '00000000-...'::uuid), snapshot_date, source)` — see below |

**Nullable-column-in-unique-index technique**: both `seo_page_keywords`
(`target_location`) and `seo_page_performance_snapshots` (`page_keyword_id`)
need a unique constraint that treats repeated `NULL`s as duplicates, but a
plain Postgres unique index treats every `NULL` as distinct from every other
`NULL` (so two rows both lacking a `target_location`, or both being
page-level snapshots with no specific keyword, would silently NOT collide).
Both migrations use a `COALESCE(..., <sentinel>)` expression inside the
unique index instead — a portable technique that works on any Postgres
version (as opposed to `UNIQUE ... NULLS NOT DISTINCT`, a Postgres 15-only
syntax that would work but ties the constraint definition itself to a
version floor rather than just the summary view). This is a **new pattern**
for this codebase — no existing Stage 1-3 migration had this exact problem
(Stage 2/3's few nullable FK-in-unique-constraint cases didn't need it, e.g.
`seo_approval_items.recommendation_id UNIQUE` is `NOT NULL`).

## 6. What Remains Unwired

- No frontend service change. `src/services/performanceService.ts` and
  `src/mocks/performanceMockData.ts` are untouched.
- No real GSC/GA4 integration, no external API call, no cron job, no
  crawler — `source` only records where a row's numbers *would have* come
  from; nothing populates it automatically.
- No Decline Diagnosis logic — `movement_status` and `diagnosis_hint` are
  plain columns a future module can read/write; nothing computes them here.
- No Stage 4 UI test dataset seed — `supabase/test/seo_seed_ui_test_dataset.sql`
  is untouched, per explicit instruction. A Stage 4 seed extension is
  separate, later work (see §9).
- No frontend service wiring has started. Stage 4 backend is **test-verified
  only** — see the checkpoint at the top of this document.

## 7. Test Checklist

Everything below was exercised by `supabase/test/seo_stage4_page_performance_smoke_test.sql`
on the test project. Result: **completed with no `FAIL`** (see checkpoint
above for the one smoke-test-harness defect found and fixed along the way —
not a migration/RLS defect).

- [x] Apply Stage 1 then Stage 4 (010→011→012→013) on the test project; no
      errors; re-running the whole smoke test script is idempotent (workspace/
      website/module-access rows use `ON CONFLICT DO NOTHING`).
- [x] Page inventory insert as `team_member` succeeds (2 pages).
- [x] Duplicate active `(website_id, page_url)` rejected by the partial
      unique index.
- [x] Page keyword insert as `team_member` succeeds (primary + secondary
      keyword on the same page).
- [x] Performance snapshot insert as `team_member` succeeds — an older and a
      newer snapshot for the same page+keyword, plus a page-level aggregate
      snapshot (`page_keyword_id IS NULL`).
- [x] Duplicate `(page_id, page_keyword_id, snapshot_date, source)` snapshot
      rejected by the unique index.
- [x] `seo_page_performance_latest` resolves to the **newer** of the two
      same-page/keyword snapshots, and returns exactly one row per
      `(page_id, page_keyword_id)` group.
- [x] owner/admin/team_member/client can all `SELECT` from all three tables
      and the view for their workspace.
- [x] Non-member sees `0` rows across all three tables and the view for that
      workspace (RLS isolation, not an error) — this check required the
      smoke-test fix described in the checkpoint above; it now genuinely
      exercises RLS instead of running under `postgres`/`BYPASSRLS`.
- [x] Client `INSERT` on any of the three tables raises (RLS `WITH CHECK`
      violation); client direct `UPDATE` affects `0` rows (RLS `USING`
      violation, no exception — matches Stage 2's `seo_approval_items`
      client-edit-denial pattern).
- [x] Invalid `ctr` (`1.5`, out of `0..1`), invalid `movement_status`
      (`'skyrocketing'`), invalid `device` (`'tablet'`), and invalid `source`
      (`'web_scraper'`) are all rejected by their `CHECK` constraints.

## 8. Dry-Run Instructions (Completed)

1. Used the Supabase CLI's migration diff/dry-run tooling against the
   disposable **test** project — never production.
2. No errors, no unexpected diff beyond the 4 new Stage 4 files.
3. The 4 new migrations applied cleanly after Stage 1 (Stage 4 only depends
   on Stage 1's `seo_workspaces`/`seo_websites`/helper functions — Stage 2/3
   are not required, though applying in full numeric order is still
   recommended for consistency with how Stage 1-3 were rolled out).

## 9. Apply Instructions (Test Project Only — Completed)

1. Confirmed the target Supabase project was the same disposable **test**
   project Stage 1-3 already applied to.
2. Applied, in filename order:
   `20260711120010_seo_stage4_page_inventory.sql` →
   `20260711120011_seo_stage4_page_keywords.sql` →
   `20260711120012_seo_stage4_performance_snapshots.sql` →
   `20260711120013_seo_stage4_performance_latest_view.sql`.
3. Verified in the Dashboard: 3 new tables visible, RLS `true` on all 3, 1 new
   view visible, 6 policies visible across the 3 tables (Table Editor /
   `pg_policies`) — see checkpoint above.
4. Filled in the 5 placeholder UUIDs at the top of
   `supabase/test/seo_stage4_page_performance_smoke_test.sql` and ran it in
   the SQL Editor. First run failed on non-member isolation (smoke-test
   harness defect, not a migration defect — see checkpoint above); fixed the
   smoke test's role-switching and re-ran to completion with no `FAIL`.

**Recommended next step:** a Stage 4 UI test dataset seed extension (adding
realistic page/keyword/snapshot rows to
`supabase/test/seo_seed_ui_test_dataset.sql` under the existing
`44444444-` workspace so Supabase-mode UI has non-empty Page Performance
data), then Page Performance frontend service wiring
(`src/services/performanceService.ts`) — both separate, later tasks, in that
order.

## 10. Production Warning

**Production has not been touched.** No production migration, no production
data, no production connection, no service role key anywhere in these files
or in how they were applied (test project only). Stage 4 backend is
**test-verified only** — production apply, for Stage 4 or any stage,
requires the same gate every prior stage required: confirmed target project,
backup/branch strategy, final migration review, and explicit developer/
technical owner sign-off (`BACKEND_MILESTONE_HANDOFF.md` §5). Nothing in
Phase 14A.1 requests or performs that apply.
