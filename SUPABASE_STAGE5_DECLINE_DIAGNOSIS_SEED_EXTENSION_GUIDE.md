# Supabase Stage 5 Decline Diagnosis — UI Seed Extension Guide

Companion guide for
`supabase/test/seo_seed_stage5_decline_diagnosis_ui_extension.sql`. Read this
before running the script.

⚠️ **TEST DATA ONLY. Run only on a disposable TEST Supabase project. Never
run on production.**

> **Status:** this extension has been **applied and verified on the TEST
> project** — verified counts **8 decline diagnoses / 20 evidence rows /
> 6 current-view rows** (see §6). The Decline Diagnosis service layer is wired
> (Phase 14B.2, live-tested), so this data is now visible in the UI at
> `/seo/decline-diagnosis` in Supabase mode. Production untouched.

---

## 1. Purpose

This script seeds realistic **Decline Diagnosis Engine** data — decline
diagnoses and their supporting evidence — under the existing UI seed
workspace/website, tied to the Stage 4 Page Performance seed extension's
page/keyword/snapshot rows. It exists so Supabase-mode UI has non-empty
Decline Diagnosis data to show once the Decline Diagnosis service layer is
wired (a later phase — **not** part of this script).

It is a **data seed**, not a correctness/RLS test. RLS and the
`seo_create_decline_diagnosis_from_snapshot` RPC are already exercised by
`supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql` — this script
instead inserts rows directly (same pattern as every other UI seed script) so
the demo narrative and classification values are precisely controlled.

---

## 2. Prerequisites

Before running this script, confirm on the target TEST Supabase project:

1. **Stage 1-5 migrations applied** — `20260711120001` through
   `20260711120016` (Stage 5 = `…120014`, `…120015`, `…120016`; see
   `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md`).
2. **Base UI seed dataset applied** —
   `supabase/test/seo_seed_ui_test_dataset.sql` (see
   `SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md`). This script checks for that
   seed's workspace (`44444444-0000-0000-0001-000000000001`) and website
   (`44444444-0000-0000-0002-000000000001`) and will refuse to run with a
   clear error if either is missing.
3. **Stage 4 Page Performance seed extension applied** —
   `supabase/test/seo_seed_stage4_page_performance_ui_extension.sql` (see
   `SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md`). This script
   checks for Stage 4 page inventory + performance snapshot rows on the base
   website and will refuse to run with a clear error if either is missing.
4. **Test auth users exist** — at least one (ideally two, for
   owner/team-member variety) real Supabase Auth users already created on the
   TEST project (Dashboard → Authentication → Users). This script does
   **not** create users.

---

## 3. Where to get UUIDs

Two `auth.users` UUIDs are needed (only to stamp `created_by` on the rows
this script inserts — reusing the same test users from the base seed and
Stage 4 extension is recommended for consistency).

- **Dashboard:** Supabase project → Authentication → Users → copy the `UID`
  column for each user.
- **SQL lookup** (run separately, read-only): 
  ```sql
  SELECT id, email FROM auth.users ORDER BY created_at;
  ```

---

## 4. How to replace placeholders

Open `supabase/test/seo_seed_stage5_decline_diagnosis_ui_extension.sql` and
edit **SECTION 0** near the top:

```sql
SELECT set_config('seoseed5.owner_user_id', 'REPLACE_WITH_OWNER_USER_UUID', false);
SELECT set_config('seoseed5.team_user_id',  'REPLACE_WITH_TEAM_USER_UUID',  false);
```

Replace both `REPLACE_WITH_...` strings with real UUIDs (not emails). A guard
at the top of the script raises a clear exception naming exactly which value
is still a placeholder, or is not UUID-shaped, before any insert runs.

---

## 5. How to run in Supabase SQL Editor

1. Open the TEST project's Supabase Dashboard → SQL Editor.
2. Paste the full contents of
   `supabase/test/seo_seed_stage5_decline_diagnosis_ui_extension.sql`
   (after editing SECTION 0 per §4).
3. Run it. The SQL Editor runs as a privileged Postgres role on your own
   project — no key of any kind is entered into the script.
4. Watch the Messages/Notices/Results output:
   - Placeholder or dependency guard failures raise immediately with a clear
     message (fix and re-run).
   - On success, Section 3's verification `SELECT`s print row counts and
     breakdowns (see §6 below).
5. Safe to re-run: every insert is `ON CONFLICT (id) DO NOTHING`, so running
   the script again makes no changes and creates no duplicates.

---

## 6. Expected verification counts

After a successful run, Section 3 prints:

| Check | Expected |
| --- | --- |
| decline diagnoses | 8 |
| diagnosis evidence rows | 20 |
| current-view rows (open/in_review/action_planned only) | 6 |

**By `diagnosis_type`** (8 distinct types, 1 row each): `clicks_decline`,
`content_freshness`, `ctr_drop`, `impressions_decline`, `indexing_issue`,
`intent_mismatch`, `ranking_decline`, `technical_performance`.

**By `severity`:** `low` ×2, `medium` ×4, `high` ×1, `critical` ×1.

**By `status`:** `open` ×2, `in_review` ×2, `action_planned` ×2, `resolved`
×1, `dismissed` ×1. (The current view excludes the `resolved` and
`dismissed` rows, which is why it shows 6 of the 8.)

**By `suggested_owner`:** `client_action` ×2, `digibility_expert` ×2,
`system_suggestion` ×2, `developer_needed` ×2.

If any count is off, re-check that the script wasn't partially interrupted,
and that no other script has inserted rows with an `88888888-` id prefix.

---

## 7. How to test in UI after frontend wiring

This script does **not** wire any frontend service — the Decline Diagnosis
page/mock/service remain untouched (see
`SERVICE_LAYER_WIRING_PLAN.md`'s Phase 14B.1 backend note). Once a future
phase wires `declineDiagnosisSupabaseService` (with a
`diagnosis_type ↔ DeclineCause` mapping) behind the standard adapter:

1. Set `.env` to Supabase test mode (see
   `SERVICE_LAYER_WIRING_PLAN.md` §3) and sign in as one of the test users
   from §3 who is a member of workspace
   `44444444-0000-0000-0001-000000000001`.
2. Navigate to the Decline Diagnosis page for the seeded website
   (`https://ui-seed-digibility.example`).
3. Expect to see the 6 live diagnoses (open/in_review/action_planned) across
   the homepage, blog listing, and pricing pages, each with its
   business-friendly summary, likely cause, recommended next action, and
   2-4 evidence lines.
4. The `resolved` and `dismissed` diagnoses (2 more) should **not** appear in
   any "current/open" list view, matching `seo_decline_diagnoses_current`'s
   filter — but should still be readable via a full-history / all-statuses
   view if one exists.

---

## 8. Warnings

- **Test data only.** Every row uses fixed `88888888-` prefixed UUIDs and is
  meant for local/test-project UI development, not real customer data.
- **Production untouched.** This script targets the TEST Supabase project
  only; it never references or connects to production.
- **No real crawler.** Page/content signals (`content_status`,
  `indexability_status`) referenced in evidence come from the Stage 4 seed
  extension's manually-seeded page inventory, not a real crawl.
- **No real GSC/GA4.** All performance numbers referenced come from the
  Stage 4 seed extension's `source='manual_seed'` snapshots.
- **No real LLM.** Every diagnosis narrative (business summary, likely
  cause, technical explanation, recommended action) was hand-written for this
  seed — no AI-generated classification or heuristic engine is involved.
- **Diagnoses are demo/manual_seed rows**, inserted directly (not via the
  `seo_create_decline_diagnosis_from_snapshot` RPC), so they do not exercise
  the RPC path — that path is covered separately by the Stage 5 smoke test.

---

## 9. Optional teardown

At the bottom of the script, a commented-out teardown deletes only this
script's own rows (identified by the `88888888-` prefix):

```sql
-- DELETE FROM public.seo_decline_diagnosis_evidence WHERE id::text LIKE '88888888-%';
-- DELETE FROM public.seo_decline_diagnoses WHERE id::text LIKE '88888888-%';
```

It does **not** touch the base UI seed, the Stage 4 extension, or any other
seed/smoke test. Uncomment and run manually only if you want to remove this
extension's data from the test project.
