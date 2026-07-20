# Supabase Migration — Stage 5: Decline Diagnosis Engine (Notes)

Phase 14B.1 — implementation notes for the Stage 5 migrations. These files are
additive and have been **dry-run, applied, structurally verified, and
smoke-tested on the disposable TEST Supabase project only** (see §12 —
Verification checkpoint). They have **not** been applied to production. No
frontend wiring, no service changes, no mock removal.

---

## 1. What was created

| File | Contents |
| --- | --- |
| `supabase/migrations/20260711120014_seo_stage5_decline_diagnoses.sql` | `seo_decline_diagnoses` table + indexes + unique index + `updated_at` trigger + RLS |
| `supabase/migrations/20260711120015_seo_stage5_decline_diagnosis_evidence.sql` | `seo_decline_diagnosis_evidence` table + indexes + unique index + RLS |
| `supabase/migrations/20260711120016_seo_stage5_decline_diagnosis_current_view.sql` | `seo_decline_diagnoses_current` view + `seo_create_decline_diagnosis_from_snapshot(...)` RPC |
| `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql` | Draft smoke test (UUID prefix `77777777-`) |
| `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_PLAN.md` | Design/plan doc |
| `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` | This file |

Timestamps continue the sequence (Stage 4 ended at `…120013`).

---

## 2. Tables

### `seo_decline_diagnoses`
- Snapshot columns: `workspace_id`, `website_id`, `website_url`, `page_id`,
  `page_url`, `page_keyword_id` (nullable), `keyword` (nullable),
  `performance_snapshot_id` (nullable).
- Classification: `diagnosis_type` (12 values), `severity`
  (low/medium/high/critical), `confidence_percentage` (nullable, 0–100),
  `movement_status` (nullable, matches Stage 4), `priority` (low/medium/high),
  `status` (open/in_review/action_planned/resolved/dismissed),
  `suggested_owner` (client_action/developer_needed/digibility_expert/system_suggestion).
- Narrative: `business_summary`, `likely_cause` (both `NOT NULL`),
  `technical_explanation` (nullable), `recommended_next_action` (`NOT NULL`).
- Seams: `linked_recommendation_id` (nullable FK → `seo_recommendations`,
  `ON DELETE SET NULL`), `created_by`, `created_at`, `updated_at`.
- FK delete behavior: `workspace_id`/`website_id`/`page_id` → `CASCADE`;
  `page_keyword_id`/`performance_snapshot_id`/`linked_recommendation_id` →
  `SET NULL` (optional links must never delete a diagnosis);
  `created_by` → `SET NULL`.

### `seo_decline_diagnosis_evidence`
- `diagnosis_id` FK → `seo_decline_diagnoses` `ON DELETE CASCADE`.
- `evidence_type` (10 values), `metric_name`, `current_value`/`previous_value`/
  `delta_value` (text), `evidence_summary` (`NOT NULL`), `source` (6 values,
  default `performance_snapshot`).
- Immutable: no `updated_at` column/trigger (same rationale as Stage 4
  snapshots).

---

## 3. Views / functions

### View `seo_decline_diagnoses_current`
- `security_invoker = true` (inherits base-table RLS; Postgres 15+, same as
  Stage 4's `seo_page_performance_latest`).
- Filters to live statuses (`open`/`in_review`/`action_planned`).
- LEFT JOIN `seo_page_inventory` (page context) + LEFT JOIN
  `seo_page_performance_latest` on `page_id` +
  `page_keyword_id IS NOT DISTINCT FROM` (exactly one latest row per diagnosis;
  no row fan-out). `GRANT SELECT … TO authenticated`.

### Function `seo_create_decline_diagnosis_from_snapshot(...)`
- Signature: `(p_snapshot_id uuid, p_diagnosis_type text, p_severity text,
  p_priority text, p_suggested_owner text, p_business_summary text,
  p_likely_cause text, p_recommended_next_action text,
  p_confidence_percentage integer DEFAULT NULL,
  p_technical_explanation text DEFAULT NULL) RETURNS uuid`.
- `SECURITY DEFINER`, `SET search_path = public`. Reads the snapshot, enforces
  `owner/admin/team_member` (or global admin) on the snapshot's workspace
  (raises otherwise), inserts the diagnosis (`created_by = auth.uid()`,
  `performance_snapshot_id = p_snapshot_id`, movement/page/keyword/url copied
  from the snapshot), then inserts up to 4 evidence rows (clicks→traffic,
  impressions→impressions, ctr→ctr, average_position→ranking) **only where a
  previous value exists**, using `delta = COALESCE(stored *_delta, current −
  previous)`. `ON CONFLICT (diagnosis_id, evidence_type, metric_name) DO
  NOTHING`. Returns the new diagnosis id. `EXECUTE` granted to `authenticated`
  (client/non-member rejected by the in-function role check).
- **No** external API, LLM, crawler, or heuristic classification.

> Signature note: the task's illustrative signature was single-argument
> (`snapshot_id` only). A single-argument version cannot be deterministic for
> the narrative/classification fields without heuristics, so the signature was
> widened to accept the caller-decided classification while SQL only snapshots
> immutable facts and copies stored metrics. Rationale documented in the plan
> doc §7.

---

## 4. RLS policies

Both tables: RLS **enabled**, reusing Stage 1 helpers.

| Policy | Table | Command | Predicate |
| --- | --- | --- | --- |
| `seo_decline_diagnoses_select` | diagnoses | SELECT | `is_seo_workspace_member(workspace_id) OR seo_is_global_admin()` |
| `seo_decline_diagnoses_write` | diagnoses | ALL | `seo_role_in(workspace_id, {owner,admin,team_member}) OR seo_is_global_admin()` (USING + WITH CHECK) |
| `seo_decline_diagnosis_evidence_select` | evidence | SELECT | member/global-admin |
| `seo_decline_diagnosis_evidence_write` | evidence | ALL | manager/global-admin |

No `profiles.role`, no service-role dependency, no new auth system.

---

## 5. Constraints

- CHECKs: `diagnosis_type` (12), `severity` (4), `priority` (3), `status` (5),
  `suggested_owner` (4), `movement_status` (nullable, 5),
  `confidence_percentage` (nullable, 0–100) on diagnoses; `evidence_type` (10),
  `source` (6) on evidence.
- Partial unique index `uq_seo_decline_diag_active_combo` on
  `(page_id, COALESCE(page_keyword_id, nil), diagnosis_type,
  COALESCE(performance_snapshot_id, nil))` **WHERE status IN
  ('open','in_review','action_planned')` — at most one *live* diagnosis per
  page+keyword+type+snapshot; resolved/dismissed never block a fresh one.
- Unique index `uq_seo_decline_evidence_metric` on
  `(diagnosis_id, evidence_type, metric_name)` — no duplicate evidence lines;
  also what makes the RPC re-runnable via `ON CONFLICT DO NOTHING`.
- Indexes on every FK/filter column named in the task (workspace, website,
  page, keyword, snapshot, recommendation, type, severity, status, priority,
  created_at; evidence: diagnosis_id, type, source) plus a
  `(website_id, status)` composite for the common listing.

---

## 6. How it connects to Stage 4 Page Performance

- `performance_snapshot_id` → `seo_page_performance_snapshots(id)`.
- `movement_status` mirrors the Stage 4 snapshot's value set.
- The current view surfaces `seo_page_performance_latest` metrics next to each
  open diagnosis.
- The RPC derives evidence purely from a Stage 4 snapshot's stored metrics —
  Stage 4 stays the numeric source of truth.

---

## 7. What remains unwired

- No service-layer functions, no `runWithServiceAdapter` entries, no React
  Query hooks, no UI. The app's existing Decline Diagnosis page/mock/service
  (`src/pages/seo/DeclineDiagnosisPage.tsx`, `src/mocks/performanceMockData.ts`,
  `src/services/performanceService.ts`) are untouched and still 100% mock.
- No `diagnosis_type` ↔ `DeclineCause` mapping yet (that's the later wiring
  phase; see plan doc §4).
- No diagnosis→recommendation / diagnosis→support conversion.
- No Stage 5 UI seed extension.

---

## 8. Test checklist

Run `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql` on a fresh test
project (after Stages 1/2/4/5). Expect `PASS` for:

- [ ] team_member inserts a diagnosis; admin inserts evidence.
- [ ] RPC creates a diagnosis with 4 auto-derived evidence rows and
      auto-snapshotted workspace/page.
- [ ] duplicate active (page+keyword+type+snapshot) diagnosis rejected.
- [ ] owner/admin/team/client can read diagnoses(2)/evidence(5)/current-view(2).
- [ ] non-member sees 0/0/0.
- [ ] client blocked from insert (diagnosis + evidence), from update (0 rows),
      and from the RPC.
- [ ] invalid `diagnosis_type`/`severity`/`status`/`suggested_owner`/
      `confidence_percentage`/evidence `source` all rejected.
- [ ] current view drops a dismissed diagnosis (2 → 1, rolled back).

---

## 9. Dry-run instructions

There is no local Postgres in this repo, so validation was **static** (see the
task output's "Validation performed"). To dry-run against a disposable test DB
without persisting objects, wrap the migration bodies in a transaction:

```sql
BEGIN;
\i supabase/migrations/20260711120014_seo_stage5_decline_diagnoses.sql
\i supabase/migrations/20260711120015_seo_stage5_decline_diagnosis_evidence.sql
\i supabase/migrations/20260711120016_seo_stage5_decline_diagnosis_current_view.sql
-- inspect: \d+ public.seo_decline_diagnoses  etc.
ROLLBACK;   -- discards everything; nothing is applied
```

(Stages 1/2/4 must already exist in that DB for the FKs/helpers to resolve.)

---

## 10. Apply instructions (TEST project only)

1. Confirm the target is a **disposable TEST** Supabase project — never
   production.
2. Ensure Stages 1 (`…120001–120003`), 2 (`…120004–120006`), and 4
   (`…120010–120013`) are already applied.
3. Apply, in order:
   `…120014_seo_stage5_decline_diagnoses.sql`,
   `…120015_seo_stage5_decline_diagnosis_evidence.sql`,
   `…120016_seo_stage5_decline_diagnosis_current_view.sql`
   (via `supabase db push`/migration tooling or by pasting each into the SQL
   Editor in order).
4. Create the five test auth users (Dashboard → Authentication → Users), paste
   their UUIDs into the smoke test's `SELECT set_config('seo5.*', …)` block,
   and run the smoke test. Read the Messages/Notices tab for `PASS`/`FAIL`.
5. Do **not** insert into `auth.users` and do **not** use a service-role key.

---

## 11. Production warning

⚠️ **Do not apply to production.** Additive and non-destructive, but production
apply is gated on explicit review/approval per `BACKEND_MILESTONE_HANDOFF.md`.
The verification below was performed on a disposable TEST Supabase project only.

---

## 12. Verification checkpoint (TEST project)

Stage 5 was carried through the same verification pipeline as Stages 1–4, on
the disposable TEST Supabase project:

- [x] **Pre-apply safety review passed** — SECURITY DEFINER RPC reviewed and
      accepted; no files changed by the review; no migration defect found.
- [x] **Dry-run passed** (transaction-wrapped `BEGIN; … ROLLBACK;`, clean).
- [x] **Applied to the TEST Supabase project** (migrations `…120014`,
      `…120015`, `…120016`, in order).
- [x] **2 Stage 5 tables visible:** `seo_decline_diagnoses`,
      `seo_decline_diagnosis_evidence`.
- [x] **RLS enabled (true) on both tables.**
- [x] **1 view visible:** `seo_decline_diagnoses_current`.
- [x] **1 RPC visible:** `seo_create_decline_diagnosis_from_snapshot`.
- [x] **4 policies visible:** `seo_decline_diagnoses_select`,
      `seo_decline_diagnoses_write`, `seo_decline_diagnosis_evidence_select`,
      `seo_decline_diagnosis_evidence_write`.
- [x] **Smoke test passed** — reached
      `=== STAGE 5 SMOKE TEST COMPLETE — check the Messages/Notices tab for
      PASS/FAIL ===` with no red ERROR popup. The initial run failed only on a
      **smoke-test call-signature defect** (the RPC was called with 11
      arguments instead of its correct 10-argument signature); the smoke-test
      file was corrected to the 10-argument call with explicit `::uuid`/`::text`
      casts and re-run successfully. **This was a smoke-test defect only — not a
      migration/RPC defect;** migration `…120016` was not changed.
- [x] **Production has not been touched.**
- [ ] **Stage 5 frontend service wiring — not started.**
- [ ] **Stage 5 UI seed extension — not created.**

**Status: Stage 5 backend is test-verified only.** Production apply remains
gated on target-project confirmation, backup/branch strategy, final migration
review, and technical-owner sign-off (per `BACKEND_MILESTONE_HANDOFF.md` §5).

**Next recommended step:** create the Stage 5 UI seed extension, then wire the
Decline Diagnosis service layer (`declineDiagnosisSupabaseService` + adapter,
plus the `diagnosis_type ↔ DeclineCause` mapping — see plan doc §4).
