# Documentation Workflow Rules

**Purpose:** keep this repo's documentation accurate and prevent status drift.
These rules apply to every future task run by a human, Claude, Cursor, or any
other coding agent on the Digibility SEO module.

---

## 1. Every task starts with a Documentation Preflight

Before writing any plan or code, **read these two files first, every time:**

1. `PROJECT_DOCUMENTATION_INDEX.md` — the map of all documentation and what to
   read for which kind of task.
2. `CURRENT_PROJECT_STATUS.md` — the authoritative current state (backend
   stages, service wiring, seeds, live-test status, production status,
   limitations, next step).

Then read the task-type-specific docs below.

---

## 2. Task-type reading requirements

- **Backend / migration tasks:** also read `BACKEND_MILESTONE_HANDOFF.md`, the
  relevant `SUPABASE_MIGRATION_STAGE_*_PLAN.md` / `_NOTES.md`, and (for a stage
  being changed) the actual migration SQL headers. Never modify an
  already-applied migration file; add a new timestamped migration instead.
- **Service-wiring tasks:** also read `SERVICE_LAYER_WIRING_PLAN.md` and the
  relevant `PHASE_*_WIRING_NOTES.md` for adjacent/related services, plus the
  Supabase service file(s) you will touch under `src/services/supabase/`.
- **Seed / test-data tasks:** also read the relevant seed guide
  (`SUPABASE_*_SEED_EXTENSION_GUIDE.md` / `SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md`)
  and the header comment block of the seed SQL script itself.
- **UI / page tasks:** also read the relevant `PHASE_*_WIRING_NOTES.md` and,
  for fallback/website-selection behavior, `PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md`
  and `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` (the established
  cross-workspace fallback + onboarding-gate patterns).
- **Production-apply tasks:** also read `BACKEND_MILESTONE_HANDOFF.md` §5 (the
  production gating checklist). Do not proceed without all gates satisfied.

---

## 3. Every task must keep docs in sync

- If a task **changes implementation status** (applies a migration, wires a
  service, seeds data, live-tests a feature, fixes a documented behavior), it
  **must update the affected docs in the same task** — at minimum
  `CURRENT_PROJECT_STATUS.md`, plus the relevant stage/phase note and, if the
  set of docs changed, `PROJECT_DOCUMENTATION_INDEX.md`.
- Prefer **adding a dated status note / forward-reference** over rewriting a
  historical phase note's account of what that phase did. Historical notes are a
  record; keep them, but point forward when they become superseded.
- When you supersede a status claim, don't silently delete legitimate warnings
  (e.g. "do not apply to production", "test-only", "no real crawler/GSC/GA4/LLM").

---

## 4. Every task output must include a docs line

Every task's final output must state one of:

- **"Docs updated:"** followed by the list of documentation files changed and why, **or**
- **"Docs not changed and why:"** a one-line reason (e.g. "no implementation-status
  change; code-only refactor with no behavior change").

---

## 5. Do not overstate — precision rules

- If something is **not verified**, say *pending* or *not live-tested*.
- If something is **mock-only**, say *mock-only*.
- If something is **test-only** / applied only to the TEST Supabase project, say
  **TEST only**.
- **Never claim production was touched** unless production was actually applied
  to *and verified*, with the §5 gates satisfied and recorded. "Applied" with no
  environment qualifier is not allowed — always name the environment (TEST).
- Do not invent completed work, and do not create new product scope in a
  documentation task.

---

## 6. Stale-phrase guardrails

When editing docs, watch for and correct (only where genuinely stale) phrases
such as: "Stage 5 draft", "drafts for review", "not applied", "not wired",
"has not started", "not created yet", "Phase 14B pending", "test-verified only"
(where wiring/seeding has since happened), "29 tables" (now 31), "four stages"
(now five), "production applied". Leave them untouched where they remain
accurate for a historical phase's own account.

---

## 7. Hard prohibitions (unchanged across tasks)

Unless a task *explicitly* authorizes it: do not modify Supabase migrations, do
not modify seed SQL, do not connect to Supabase, do not apply anything to any
database, do not touch production, do not modify the reference Digibility app,
do not remove mock mode, do not expose service-role keys.
