# Project Bootstrap

**This is the single entry point for every new AI session** (Claude, ChatGPT,
Cursor, or any other coding assistant) working on this repository. Read this
file first, in full, before reading anything else or taking any action —
including in a brand-new session with no prior chat history.

This file does not duplicate other documentation. It orients you and tells you
where to go next.

---

## Project Overview

**Digibility** is an AI-powered visibility management platform for businesses
and agencies. It already has a Visibility Management module in production.
**Digibility SEO Intelligence** (this repository) is a new **paid add-on
module** — an SEO execution cockpit (audits → recommendations → approval →
content → performance → diagnosis → off-page → AI visibility), not a
keyword-research clone. See `PROJECT_CONTEXT.md` for full product scope and
business rules.

**High-level architecture:** a standalone Vite + React + TypeScript frontend,
built and tested **independently** of the main Digibility app, designed to plug
into it later without changing Core's architecture, auth, or design system. See
`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` for the approved backend architecture.

**Frontend/backend separation — there is no separate BFF (Backend-for-Frontend)
server.** The "backend" is a Supabase project (Postgres + PostgREST + Row Level
Security) that the frontend calls **directly** via the Supabase JS client using
the anon key — authorization is enforced entirely by Postgres RLS policies, not
by a middle-tier API. The abstraction boundary lives **inside the frontend**,
in the Service Adapter pattern (see below) — not a network-level BFF. The
existing `digibility-UI-Kit-small` app is a **read-only reference** for
architecture/UI/auth conventions — never modify it (see repository rules
below).

**Major modules:** see [Module Map](#module-map) below.

---

## Repository Rules

- **Documentation-first.** Every task begins by reading the three files in
  [Mandatory Reading Order](#mandatory-reading-order) below before any plan or
  code.
- **Read-before-change.** Never modify a migration, service, or module without
  first reading its owner documentation (found via the Module Map below, or
  `PROJECT_DOCUMENTATION_INDEX.md` if you need help locating it) — and always
  check `MODULE_LOCKS.md` first (see [Module Lock Rule](#module-lock-rule)).
- **Documentation update requirement.** Any task that changes implementation
  status must update the affected docs *in the same task*, and every task's
  final output must state **"Docs updated"** or **"Docs not changed and why."**
  Full rules for this: `DOCUMENTATION_WORKFLOW_RULES.md` (read it for
  documentation-heavy or status-changing tasks).
- **Production safety.** Never touch production. Never claim production was
  applied unless it was actually applied *and* verified with all gates in
  `BACKEND_MILESTONE_HANDOFF.md` §5 satisfied.
- **TEST vs. production.** All backend work (migrations, dry-runs, applies,
  smoke tests, seeds) targets the disposable **TEST** Supabase project only.
  Always name the environment explicitly (**TEST**, never bare "applied").

---

## Mandatory Reading Order

Always read these **three** first, in order, at the start of every session:

1. `PROJECT_BOOTSTRAP.md` — this file.
2. `CURRENT_PROJECT_STATUS.md` — the authoritative current state.
3. `MODULE_LOCKS.md` — which modules/files are locked and what's required to
   touch them.

**After these three, read only the module-specific documents directly
relevant to the current task.** Do not read every document in the repository
before starting — locate what you need via the [Module Map](#module-map)
below.

**Optional supporting documents** (read only when relevant to the task at
hand, not on every task):
- `PROJECT_DOCUMENTATION_INDEX.md` — use to locate module-specific
  documentation when the Module Map below doesn't cover it.
- `DOCUMENTATION_WORKFLOW_RULES.md` — use for documentation-heavy tasks, or
  any task that changes implementation status (it has the full doc-sync rules
  and the "Docs updated" output requirement).

---

## Module Lock Rule

- Before changing code, read `MODULE_LOCKS.md`.
- Identify the module and files affected.
- If any file belongs to a **LOCKED** module, do not modify it unless:
  - the task contains a reproducible defect or an explicitly approved
    enhancement,
  - the exact files allowed to change are named,
  - human approval is explicit.
- If a locked file appears necessary but approval is missing, **stop and
  explain why**.
- Do not silently reinterpret, bypass, or remove a module lock.

---

## Locked Architectural Decisions

Details live in the authoritative documents below — this is a pointer, not a
restatement.

| Decision | Summary | Authoritative doc |
| --- | --- | --- |
| **No BFF layer** | Frontend calls Supabase directly via the anon key; authorization is Postgres RLS, not a middle-tier API. | `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §F (RLS Strategy) |
| **Service Adapter pattern** | Every service function routes through `runWithServiceAdapter()` — mock in mock mode, real Supabase call in Supabase mode, automatic fallback-to-mock on any Supabase error. | `SERVICE_LAYER_WIRING_PLAN.md` |
| **Mock/Supabase dual mode** | `VITE_SEO_DATA_MODE` (`mock` default, or `supabase`). Mock mode must never be removed; it is the permanent fallback, not a placeholder. | `SERVICE_LAYER_WIRING_PLAN.md` §1–§4 |
| **Documentation workflow** | Preflight, read-before-change, doc-sync-per-task, "Docs updated" output line. | `DOCUMENTATION_WORKFLOW_RULES.md` |
| **Production gating** | Production apply requires target-project confirmation + backup/branch strategy + final migration review + technical-owner sign-off — all four, every time. | `BACKEND_MILESTONE_HANDOFF.md` §5 |
| **Stage completion rules** | A backend "Stage" is a numbered, additive migration set with its own `_PLAN.md` (design) + `_NOTES.md` (implementation + TEST verification checkpoint) + a dedicated SQL smoke test. Nothing is "done" without a TEST-verified smoke-test pass recorded in its `_NOTES.md`. | Any `SUPABASE_MIGRATION_STAGE_*_NOTES.md` |
| **Testing workflow** | Fixed sequence per module: author migration SQL → dry-run (transaction + rollback) → apply to TEST → structural verify → smoke-test → UI-seed → service-wire (reads, then writes) → live-test signed-in in the browser. See [Module Completion Rules](#module-completion-rules). | `CURRENT_PROJECT_STATUS.md` (§1–§4 shows this applied to every stage so far) |

---

## Module Map

Purpose and status only — full detail lives in each module's owner
documentation. **Backend Stage** = Supabase migration set; **Phase** = frontend
service-wiring phase. For the live, authoritative status of every row below,
always defer to `CURRENT_PROJECT_STATUS.md` over this table.

| Module | Purpose | Owner documentation | Status |
| --- | --- | --- | --- |
| Website Setup + Business Onboarding | Add a website; collect business context | `PHASE_13B_SERVICE_WIRING_NOTES.md` | Backend Stage 1 — locked |
| Technical Audit + Recommendations | Crawl-style issue detection → recommendations | `PHASE_13C_AUDIT_RECOMMENDATION_WIRING_NOTES.md` | Backend Stage 2 — locked |
| Approval Queue | Approve/reject/route recommendations via guarded RPC | `PHASE_13D_APPROVAL_QUEUE_WIRING_NOTES.md` | Backend Stage 2 — locked |
| Content Studio | Content opportunities → keyword plan → wireframe → draft, via guarded RPC | `PHASE_13E_CONTENT_STUDIO_WIRING_NOTES.md` | Backend Stage 3 — locked |
| Dashboard + Admin Preview | Read-only summaries composed from already-wired services | `PHASE_13F_DASHBOARD_ADMIN_READONLY_WIRING_NOTES.md` | Read-only — locked |
| Page Performance Tracker | Page inventory, mapped keywords, click/impression/CTR snapshots | `PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md` | Backend Stage 4 — locked, live-tested |
| Decline Diagnosis Engine | Explains why a page is declining; likely cause + recommended fix | `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` | Backend Stage 5 — locked, live-tested |
| Off-Page Authority Builder | Backlink/mention/citation/review/PR opportunities + campaigns, guarded transition RPC workflow | `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md`, `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` | Backend Stage 6 — **reads wired + live-tested; writes still mock-only, NOT locked** |
| AI Visibility / GEO | Tracks how the business appears in AI-answer results; content gaps | same as above | Backend Stage 6 — **reads wired + live-tested; writes still mock-only, NOT locked** |
| Competitors, Roadmap, Reports | Not yet started | *(none yet — mock-only frontend)* | No backend stage — mock-only |
| SEO Admin Panel integration | Final mount into the existing Digibility Admin Panel | `BACKEND_MILESTONE_HANDOFF.md` §9 | Future work — `/seo/admin-preview` is a temporary stand-in |

---

## Module Completion Rules

Every module must pass through these steps, **in this order**, before it is
considered complete:

1. **Architecture** — a `_PLAN.md` design doc with locked decisions.
2. **Backend** — migration SQL authored, dry-run, applied to TEST.
3. **Services** — frontend Supabase-service functions written.
4. **Reads** — read functions wired behind the Service Adapter.
5. **Writes** — write/transition functions wired behind the Service Adapter
   (via guarded RPCs where the plan requires them, never a raw status UPDATE
   for gated workflows).
6. **Browser testing** — live-tested signed-in against TEST, in a real browser,
   not just `tsc`/`build`.
7. **Regression** — confirm no other module broke (mock mode still works;
   other pages unaffected).
8. **Documentation** — the module's `_NOTES.md` / `_WIRING_NOTES.md` records
   every step above with its result.
9. **Sign-off** — recorded in `CURRENT_PROJECT_STATUS.md`.

**No module is complete until all nine steps are checked.** Stage 6 (Off-Page
Authority + AI Visibility) is the current example of a module stopped partway
through: steps 1–4 and 6–8 are done for its read path, but step 5 (writes) is
not — so it is explicitly **not locked** (see Module Map above).

---

## Locked Modules

A module that has passed **all nine** Module Completion Rules becomes
**locked** — future work must not modify it unless a **proven defect** exists
(a reproducible bug, not a preference or a hypothetical edge case).

**`MODULE_LOCKS.md` is the authoritative per-module lock registry** — it has
the exact locked file list, what's allowed/not-allowed, and the evidence bar
required before touching a locked module. **Check it before modifying any
file belonging to a module in the Module Map above**, not just this summary.

To change a locked module:
- Meet the evidence bar in that module's `MODULE_LOCKS.md` entry (reproduction
  steps, expected vs. actual behavior, evidence, root-cause analysis, explicit
  human approval).
- Fix only what the defect requires — do not use a bug-fix task as cover for
  unrelated refactoring or scope expansion.
- Document the fix as a dated "Post-Launch Fix" section in the module's owner
  doc (see `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` §10–§11 for the
  established pattern), and update `CURRENT_PROJECT_STATUS.md` if the fix
  changes live-test status.

**Currently locked:** Website Setup, Business Onboarding, Technical Audit,
Recommendations, Approval Queue, Content Studio, Dashboard/Admin Preview,
Page Performance Tracker, Decline Diagnosis Engine (all Stage 1–5 modules — see
Module Map). **Not locked:** Off-Page Authority + AI Visibility (Stage 6 writes
incomplete, Phase 15C validation pending); Competitors/Roadmap/Reports (not
started). Only **Page Performance Tracker** and **Off-Page Authority —
Opportunity Workflow** have a formal, file-level entry in `MODULE_LOCKS.md` so
far — the rest are locked under this general rule pending a formal entry (see
`MODULE_LOCKS.md`'s "Other modules" section).

---

## AI Working Agreement

Every AI session, before writing any code, must:

1. **Read** the three mandatory docs above (`PROJECT_BOOTSTRAP.md`,
   `CURRENT_PROJECT_STATUS.md`, `MODULE_LOCKS.md`), then only the
   module-specific docs relevant to the task.
2. **Summarize understanding** of the current relevant state in a few
   sentences, so the human can catch a wrong premise early.
3. **Identify ambiguities** — anything the task doesn't specify that would
   change the approach.
4. **State assumptions** explicitly if proceeding without asking (per this
   session's own tool-use guidance on when to ask vs. proceed).
5. **Implement only the requested scope** — no drive-by refactors, no
   unrequested "improvements," no touching a locked module without a proven
   defect.
6. **Validate** — run the project's existing checks (typecheck/build; browser
   testing for UI changes; SQL smoke tests for backend changes) before calling
   anything done.
7. **Update documentation** in the same task if implementation status changed,
   and end the response with **"Docs updated"** or **"Docs not changed and
   why"** per `DOCUMENTATION_WORKFLOW_RULES.md` §4.

---

## Current Development Phase

**Do not edit this section manually.** It is a pointer only.

➡️ See `CURRENT_PROJECT_STATUS.md` for the current backend stage, service-wiring
phase, seed status, live-test status, production status, known limitations, and
the recommended next step. That file is the single source of truth for status;
this bootstrap file's job is orientation, not status-tracking.

---

## Starting Any New AI Session

Paste this into a brand-new Claude / ChatGPT / Cursor session before giving it
any task:

```
This is a continuation of the Digibility project.

Read:
1. PROJECT_BOOTSTRAP.md
2. CURRENT_PROJECT_STATUS.md
3. MODULE_LOCKS.md

Then read only the documents directly relevant to the current module and task.

Before changing code, state:
- module affected
- files expected to change
- whether any file belongs to a locked module

If a locked file is involved without explicit approval, stop.

Do not rely on previous chat history.
```
