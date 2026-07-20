# SEO Project Context — Authoritative

**Role:** stable product + architecture + conventions reference for the Digibility
SEO Intelligence module. Part of the four-file authoritative context package
(see `SEO_CONTEXT_HANDOVER.md` for the reading order and the current frontier).
This file changes rarely; live status lives in `SEO_IMPLEMENTATION_STATUS.md`.

**Created:** 2026-07-20 (documentation consolidation task). Supersedes the
scattered product/architecture narrative previously spread across
`PROJECT_CONTEXT.md`, `PROJECT_BOOTSTRAP.md`, `SEO_PRODUCT_BLUEPRINT_REAL_APP.md`,
`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`, and the two legacy handovers — those
files are retained as historical/reference (see `PROJECT_DOCUMENTATION_INDEX.md`).

---

## 1. Product purpose and scope

Digibility SEO Intelligence is a **standalone, paid SEO module** built to run on
its own AND to later plug into the existing Digibility Visibility Management
platform without changing the core architecture, tech stack, auth, UI system, or
database principles. It converts SEO insights into clear, approvable actions for
founders, businesses, agencies, team members, and clients.

Non-negotiable product rules (from `PROJECT_CONTEXT.md` / `CLAUDE.md`):
- SEO is a paid add-on; a user may register for SEO only, or use both modules.
- **No separate authentication system** — SEO reuses Digibility's auth.
- Team members can access SEO; clients can view reports and run allowed actions.
- **Every SEO record must be linked to a website URL.**
- Same UI/UX design language as Digibility; must not look pasted-in.
- Build and test SEO independently first; integrate once mature.
- **Visibility is a SEPARATE Digibility module** — "Visibility" must never be used
  as a synonym for SEO (this drove the "Visibility Dashboard" → "SEO Dashboard"
  rename; see `SEO_DECISIONS.md`).

## 2. Overall architecture relevant to SEO

- **Frontend:** Vite + React + TypeScript (TanStack Query, shadcn/Radix
  primitives, Tailwind). Single-page app.
- **Data:** **Supabase Postgres** with **Row-Level Security (RLS)** + guarded
  **`SECURITY DEFINER` RPCs**, accessed **directly from the browser via the anon
  key**. There is **no separate BFF/API server** for the MVP — see §4.
- **Permanent mock mode:** `VITE_SEO_DATA_MODE` (`mock` default | `supabase`).
  Mock mode mirrors every service with local adapters (browser `localStorage`
  via `src/lib/localMockStore.ts`), requires no Supabase connection, and never
  throws on missing config. Mock mode must never be removed.
- **Crawler worker:** `crawler-worker/**` — a **separate Node/TS package** in the
  same repo tree; a **service-role background ingestion worker** (crawl + DNS-TXT
  ownership `verify-once`). Runs **outside the browser**; **never customer-callable**.
- **Container / hosting:** a repo-root `Dockerfile` + `docker/nginx.conf.template`
  serve the compiled frontend as a static SPA on **Google Cloud Run** (readiness
  prepared; **not deployed, not runtime-verified** — deferred to the TEST
  promotion gate).
- **TEST Supabase project:** `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`). **All**
  migrations/verification run here. **Production is a separate, untouched project.**
- **Reference app (not in this repo):** the existing Digibility app is a
  read-only source of architecture/UI/auth conventions; **must not be modified**;
  future integration target.

## 3. Repositories / components involved

| Component | Path / location | Role |
|---|---|---|
| SEO frontend | `src/**` | Browser SPA; talks directly to Supabase (RLS reads, guarded-RPC writes); never holds service-role. |
| Crawler + verification worker | `crawler-worker/**` | Service-role background worker; crawl pipeline + `verify-once` DNS-TXT ownership mode. |
| Supabase schema/migrations | `supabase/migrations/**` | Applied, immutable, additive-only DB history. |
| Supabase TEST-only scripts | `supabase/test/**` | Verification + rollback SQL (TEST only; not production). |
| Container config | `Dockerfile`, `.dockerignore`, `docker/**` | Cloud Run static-serving of the compiled SPA. |
| Help Center | `src/help/**`, `src/pages/help/**` | Public, auth-free documentation surface (`/help*`). |

## 4. Frontend → service → Supabase RPC trusted-boundary (BFF) model

There is **no Node BFF server**. The **trusted boundary is inside Supabase**:

1. **Frontend service layer** (`src/services/*.ts` + `src/services/supabase/*`)
   dispatches through `runWithServiceAdapter` / `isSupabaseMode()`
   (`src/config/runtimeConfig.ts`, `src/services/serviceAdapter.ts`). It sends
   the **anon key only** and **never** service-role credentials.
2. **Reads** go through **RLS** (workspace-member-scoped SELECT policies).
3. **Writes** go through **guarded `SECURITY DEFINER` RPCs** (`SET search_path =
   public`, explicit `GRANT`/`REVOKE`, `authenticated`-only unless intentionally
   `service_role`-only) that authorize **owner/admin/team/client** server-side,
   resolve workspace/website/role server-side, and write append-only audit rows.
   Genuine RPC errors are surfaced verbatim, never masked by mock.
4. **Service-role-only surface** (worker RPCs: crawl claim/lifecycle, ownership
   claim/result) is **denied to `authenticated`/`anon`** and only callable by the
   worker's service-role client, which lives entirely outside the browser.

The RPC + RLS layer therefore **is** the BFF/trusted boundary. A future wider
Digibility BFF integration is explicitly deferred.

## 5. Domain boundaries (workspace / website / membership / role / RLS / worker / crawl / publishing / ownership)

- **Workspace / website / membership:** every record is workspace-scoped and
  website-scoped; membership + role are resolved server-side in RPCs, never
  invented in the frontend. `useResolvedActiveWebsite` selects the active website;
  website-scoped routes redirect to `/seo/websites` when none exists.
- **Roles:** owner / admin / team_member / client, plus a global-admin path.
  Per-role action gating lives in the pages/components AND is authoritatively
  enforced by RLS + guarded RPCs (frontend gating is UX only).
- **Worker boundary:** the worker only **claims** service-role work
  (`FOR UPDATE SKIP LOCKED` + lease model); it never enqueues crawl jobs and
  never touches customer auth. Lease tokens / worker ids / internal diagnostics
  are **never customer-readable**.
- **Crawl enqueue boundary:** `public.seo_crawl_request` is the **single
  authoritative crawl-job-creation boundary** (the only production `INSERT INTO
  seo_crawl_jobs`), reached by both the UI/`seo_crawl_request_audit` path and any
  direct authenticated call. As of **P1b**, it enforces a **verified-ownership
  precondition** (see §5 ownership, and `SEO_DECISIONS.md`).
- **Publishing boundary:** crawl publishing updates only crawler-owned technical
  facts (stale-job-safe, newer-wins), preserves user-owned fields, never removes
  unseen pages, and **never overwrites a completed historical audit** — failed/
  cancelled attempts never delete previously published results.
- **Ownership boundary (DNS-TXT):** `seo_ownership_verifications` (customer-safe,
  `method='dns_txt'`, status `pending`/`verified`/`failed`/`revoked`) is the
  source of truth; the isolated worker resolves DNS TXT and persists results via
  service-role RPCs; the customer UI (`OwnershipVerificationPanel`) uses only the
  frontend hooks. Verified ownership is the precondition P1b consumes.

## 6. Backward-compatibility rules

- **Additive migrations only.** Never edit an already-applied migration file —
  add a new timestamped migration. Applied migrations are **immutable**.
- Preserve every locked contract: RPC names/params/returns/grants, status
  strings, query keys, read-shape types, role behavior, idempotency,
  single-active-job rule, event creation.
- Never remove **mock mode**; never mask real backend failures with mock;
  never expose service-role keys in the frontend.
- New frontend APIs must be additive, typed, and backward compatible (omitted
  optional props render exactly as before).

## 7. TEST vs. production rules

- **TEST only:** all applied migrations and verification runs are on
  `Digi_SEO_Test`. Always name the environment ("TEST"); "applied" without an
  environment qualifier is not allowed.
- **Production is untouched** and must stay untouched until a separately-approved
  production-promotion task satisfies the promotion gates (see
  `SEO_IMPLEMENTATION_STATUS.md` + `BACKEND_MILESTONE_HANDOFF.md` §5).
- Do not connect to, or apply anything to, any database in a documentation or
  planning task.

## 8. Development & verification conventions

- **Documentation preflight** every task: read
  `PROJECT_DOCUMENTATION_INDEX.md` + the authoritative package (this file plus
  the other three) + `MODULE_LOCKS.md` before planning or coding
  (per `DOCUMENTATION_WORKFLOW_RULES.md`).
- **Verification toolchain:** `npx tsc --noEmit -p tsconfig.app.json`;
  `npm run build`; the dev-only Help Center content validator at
  `/help/dev/content-check`; worker suite `cd crawler-worker && npm test`;
  SQL verification scripts under `supabase/test/**` (single-transaction,
  self-cleaning, TEST-only). **No frontend test/lint runner exists** — verify via
  `tsc`/build + live browser checks.
- **Locked-module changes** require that lock's additive-extension + evidence
  procedure and explicit approval (see `MODULE_LOCKS.md`).
- **Precision:** say *mock-only* / *TEST-only* / *pending* accurately; never
  overstate; never claim production was touched.

## 9. How Claude and ChatGPT collaborate

- **ChatGPT** holds oversight: it plans, sequences, and issues **narrowly-scoped,
  explicitly-approved** task prompts (often naming allowed files, stop
  conditions, and a required response format).
- **Claude (this agent)** executes exactly that scope, verifies, and reports
  **evidence** (tsc/build/SQL/worker/browser results), then stops. Claude does
  not expand scope, begin the next stage, or stage/commit/push without explicit
  instruction.
- Approvals are **per-action and per-session**; one approval never generalizes to
  later actions.
- New sessions should be bootstrapped from `SEO_CONTEXT_HANDOVER.md` and should
  **reference the authoritative files rather than re-pasting full context**.

## 10. Documentation authority rules

- **Authority hierarchy** (highest first): `SEO_CONTEXT_HANDOVER.md` →
  `SEO_IMPLEMENTATION_STATUS.md` → `SEO_PROJECT_CONTEXT.md` (this file) →
  `SEO_DECISIONS.md` → `MODULE_LOCKS.md` → module-specific sign-off/verification
  evidence → historical/archive documents.
- `CURRENT_PROJECT_STATUS.md` remains the detailed dated status ledger and is
  retained; where it and the authoritative package differ on *current summary*,
  the package's `SEO_IMPLEMENTATION_STATUS.md` is the concise current truth and
  points back to the ledger for full dated evidence. The two must not contradict.
- Prefer **additive dated notes / forward-references** over rewriting historical
  records. Never silently delete legitimate warnings (test-only, mock-only, "do
  not apply to production").
- Every task states a **"Docs updated:"** or **"Docs not changed and why:"** line.
