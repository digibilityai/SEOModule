# Supabase Migration — Stage 5: Decline Diagnosis Engine (Plan)

Phase 14B.1 — this document is the **design rationale** for the Stage 5
migration files. It was written when the migrations were drafts for review.

> **Status update (superseding the "drafts only" framing below):** Stage 5 has
> since been applied to the **TEST** Supabase project and verified, UI-seeded
> and verified (8 diagnoses / 20 evidence / 6 current-view rows), and
> service-wired in Phase 14B.2 (live-tested). It remains **TEST-only — never
> applied to production.** See `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md`
> §12, `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md`, and `CURRENT_PROJECT_STATUS.md`.
> The Phase 14B.1 framing (drafts, no wiring, no seed) is retained below as the
> original design record.

---

## 1. Purpose

The Decline Diagnosis Engine explains **why** a tracked page may be losing
ranking or traffic, in Digibility's "execution cockpit" voice:

1. **What changed** — a plain-language summary of the movement.
2. **Why it matters** — the likely cause, business-first.
3. **What to do next** — a single recommended next action.
4. **Who should do it** — a suggested owner (client / developer / Digibility
   expert / system suggestion), so risky or manual fixes can later be routed
   into the Approval Queue or Expert Support.

Stage 5 provides the **storage + access + safe-creation** layer for that. It
deliberately ships **no diagnosis heuristics in SQL** — "which cause is it"
is decided by the writer (service layer, a future engine, or a human seed),
not baked into the database. Stage 5 reads Stage 4 Page Performance data as
its evidence source.

Out of scope for Stage 5 (explicitly): real crawler, real GSC/GA4 import,
external API calls, LLM calls, cron jobs, and any frontend wiring.

---

## 2. Tables proposed

| Object | Kind | Migration |
| --- | --- | --- |
| `seo_decline_diagnoses` | table | `20260711120014_seo_stage5_decline_diagnoses.sql` |
| `seo_decline_diagnosis_evidence` | table | `20260711120015_seo_stage5_decline_diagnosis_evidence.sql` |
| `seo_decline_diagnoses_current` | view (`security_invoker`) | `20260711120016_seo_stage5_decline_diagnosis_current_view.sql` |
| `seo_create_decline_diagnosis_from_snapshot(...)` | function (RPC) | `20260711120016_…_current_view.sql` |

Timestamps continue the existing sequence: Stage 4 ended at `…120013`, so
Stage 5 is `…120014`, `…120015`, `…120016`.

### `seo_decline_diagnoses`
One diagnosis per page (optionally per page+keyword, optionally anchored to one
Stage 4 performance snapshot). Key fields: `diagnosis_type`, `severity`,
`confidence_percentage`, `movement_status`, `business_summary`, `likely_cause`,
`technical_explanation`, `recommended_next_action`, `suggested_owner`,
`priority`, `status`, plus a nullable `linked_recommendation_id` seam and the
usual workspace/website/page/keyword/url snapshot columns.

### `seo_decline_diagnosis_evidence`
Structured "why we think this happened" rows behind a diagnosis
(`ON DELETE CASCADE` from the diagnosis). Each row is one metric movement:
`evidence_type`, `metric_name`, `current_value` / `previous_value` /
`delta_value` (stored as text — mixed metric kinds; display-oriented), an
`evidence_summary`, and a `source`.

### `seo_decline_diagnoses_current` (view)
Read-only convenience: the still-live diagnoses (`open` / `in_review` /
`action_planned`) joined to page context (title/type/content/indexability) and
the latest Stage 4 performance row for that page+keyword. `security_invoker`,
so it inherits the base tables' RLS exactly.

### `seo_create_decline_diagnosis_from_snapshot(...)` (RPC)
A **deterministic, no-heuristic** creation helper. It snapshots
page/keyword/url/movement **from** a Stage 4 performance snapshot, inserts a
diagnosis the caller has already classified, and auto-derives evidence rows by
**copying** that snapshot's already-stored metrics. See §7 for why it was
included rather than skipped.

---

## 3. Why each table exists

- **`seo_decline_diagnoses`** — the cockpit needs a first-class, queryable
  "here's why this page is slipping and what to do" record, separate from raw
  performance numbers (Stage 4) and from prescriptive on-page fixes
  (`seo_recommendations`, Stage 2). A diagnosis is the *explanation* layer that
  sits between them.
- **`seo_decline_diagnosis_evidence`** — keeping evidence in its own child
  table (rather than a JSON blob on the diagnosis) lets the UI render clean
  "clicks 100 → 60", "position 6.2 → 8.5" lines, lets us index/count by
  `evidence_type`, and keeps the diagnosis row itself narrative-only. Evidence
  is immutable and cascade-deleted with its parent.

---

## 4. How it uses Stage 4 Page Performance data

- Every diagnosis may reference a `performance_snapshot_id`
  (`seo_page_performance_snapshots`, Stage 4 migration 12) and snapshots that
  row's `movement_status`.
- The `seo_decline_diagnoses_current` view LEFT JOINs
  `seo_page_performance_latest` (Stage 4 migration 13) on
  `page_id` + `page_keyword_id` (`IS NOT DISTINCT FROM`, so the page-level
  NULL-keyword case matches the aggregate row) to show current
  clicks/impressions/CTR/position alongside each open diagnosis.
- The creation RPC reads the snapshot's stored current/previous/delta metrics
  and turns them into evidence rows deterministically — **no recomputation, no
  external fetch.** Stage 4 remains the numeric source of truth; Stage 5
  evidence is a display-oriented copy.

Mapping seam for future frontend wiring: the app's current `DeclineCause` union
(`src/types/performance.ts`) uses slightly different labels (e.g.
`ranking_loss`, `freshness_issue`, `technical_issue`). The Stage 5
`diagnosis_type` set is the backend canonical list; the service layer will map
between them in the (later) wiring phase — not in this phase.

---

## 5. RLS model

RLS is **enabled** on both new tables. Policies reuse the existing Stage 1
helper functions — no new auth, no `profiles.role`, no service-role reliance:

- **SELECT** — `is_seo_workspace_member(workspace_id) OR seo_is_global_admin()`
  (any active member, including `client`, can read).
- **ALL (write)** —
  `seo_role_in(workspace_id, ARRAY['owner','admin','team_member']) OR seo_is_global_admin()`
  (clients can never insert/update/delete).

The `seo_decline_diagnoses_current` view is `security_invoker = true`, so it is
evaluated with the querying user's own privileges and inherits the above
policies with no duplicated logic and no bypass. This mirrors Stage 4's
`seo_page_performance_latest` exactly.

The RPC is `SECURITY DEFINER` but performs an explicit
`seo_role_in(owner/admin/team_member) OR seo_is_global_admin()` check on the
snapshot's workspace before writing, raising for anyone else — so a `client`
(or non-member) cannot create a diagnosis even though `EXECUTE` is granted to
`authenticated`. This is the same defense pattern as Stage 2's
`seo_supersede_recommendation`.

---

## 6. Role access model

| Role | Read diagnoses / evidence / current view | Insert / update diagnoses / evidence | Run creation RPC |
| --- | --- | --- | --- |
| `owner` | ✅ | ✅ | ✅ |
| `admin` | ✅ | ✅ | ✅ |
| `team_member` | ✅ | ✅ | ✅ |
| `client` | ✅ (read-only) | ❌ | ❌ |
| non-member | ❌ (0 rows) | ❌ | ❌ (raises) |
| global admin | ✅ | ✅ | ✅ |

No frontend delete path is needed; deletes are governed by the same manager
write policy plus FK cascades.

---

## 7. What is not included yet

- **No diagnosis heuristics in SQL.** The RPC does not decide `diagnosis_type`,
  `severity`, `likely_cause`, etc. — the caller supplies them. Auto-derived
  evidence is a straight copy of stored Stage 4 numbers.
- **No conversion flow.** `linked_recommendation_id` is a nullable seam only;
  turning a diagnosis into a recommendation or a support ticket is a later
  phase.
- **No real data ingestion** — no crawler, no GSC/GA4 import, no cron.
- **No frontend wiring, no service changes, no mock removal.**
- **No Stage 5 UI seed extension yet.** The existing UI dataset seeds
  (`seo_seed_ui_test_dataset.sql`,
  `seo_seed_stage4_page_performance_ui_extension.sql`) are **not** modified in
  this phase; a Stage 5 seed extension comes only after Stage 5 migrations are
  applied and smoke-tested on the test project.

**On including the RPC (design decision).** The task allowed skipping the RPC
if it could not be deterministic and safe. It can: by having the caller pass
the classification and letting SQL only (a) snapshot immutable facts from the
referenced Stage 4 row and (b) copy that row's stored metrics into evidence, it
is fully deterministic, has no external dependency, and enforces manager-only
writes. That is genuinely useful (one safe call instead of N inserts) without
smuggling an "engine" into the database, so it is included. If reviewers prefer
manual seeding for v1, migration 16 can be dropped without affecting migrations
14/15.

---

## 8. Test strategy

Draft smoke test: `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql`,
UUID prefix `77777777-`, runnable in the Supabase SQL Editor on a **fresh test
project** after Stages 1, 2, 4, and 5 are applied. It:

- seeds a disposable workspace/members/website + Stage 4 fixtures
  (page/keyword/snapshot),
- inserts a diagnosis (team_member) and an evidence row (admin) — positive,
- exercises the creation RPC (team_member) and asserts 4 auto-derived evidence
  rows + auto-snapshotted workspace/page,
- checks the active-combo unique index rejects a duplicate open diagnosis,
- verifies SELECT for owner/admin/team/client and **0 rows** for a non-member,
  each inside its own `BEGIN; SET LOCAL ROLE authenticated; … ROLLBACK;` so
  RLS is genuinely evaluated (the corrected Stage 4 pattern — a bare
  JWT-claim-only block runs as `postgres`/BYPASSRLS and would falsely pass),
- verifies client is blocked from insert/update **and** from the RPC,
- checks CHECK constraints reject invalid
  `diagnosis_type` / `severity` / `status` / `suggested_owner` /
  out-of-range `confidence_percentage` / evidence `source`,
- checks the current view excludes a dismissed diagnosis (inside a rolled-back
  transaction, so no committed state changes).

Prints `PASS`/`FAIL` notices; optional destructive teardown is commented out at
the bottom.

**Verification result (TEST project):** ✅ Pre-apply safety review passed →
dry-run passed → applied → structural verification (2 tables, RLS true on both,
1 view, 1 RPC, 4 policies) → smoke test passed. The smoke test's first run
failed only on a smoke-test call-signature defect (an 11-argument RPC call vs
the correct 10-argument signature), which was fixed in the smoke-test file with
explicit `::uuid`/`::text` casts and re-run successfully — not a migration/RPC
defect. Full checklist in
`SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` §12. Stage 5 backend is
**applied to TEST and verified**; the UI seed extension has since been created
and verified (8 diagnoses / 20 evidence / 6 current-view rows) and frontend
service wiring is complete (Phase 14B.2, live-tested) — see
`PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md`.

---

## 9. Production gating reminder

⚠️ **Do not apply to production.** Per `BACKEND_MILESTONE_HANDOFF.md`, backend
production apply requires explicit review and approval. These migrations are
additive and non-destructive, and have been applied and smoke-tested on a
**disposable TEST project** (never production). No Supabase connection, no SQL
execution, and no `.env`/service-role changes were part of the Phase 14B.1
design work itself.
