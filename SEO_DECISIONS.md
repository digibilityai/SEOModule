# SEO Decisions — Authoritative (Current Confirmed Decisions Only)

**Role:** the current, confirmed architectural / security / process decisions for
the SEO module. Part of the four-file authoritative package. Obsolete or
contradicted decisions appear **only** in §9 ("Rejected or superseded"). Full
narrative rationale lives in the retained ADRs (`ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`,
`ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md`) and per-module sign-offs.

**Created:** 2026-07-20. Dates given where known.

---

## 1. Architectural decisions (current)

- **A1. Direct browser → Supabase; no Node BFF for the MVP.** The trusted
  boundary is Supabase's **RLS + guarded `SECURITY DEFINER` RPC** layer. Frontend
  sends the anon key only. (A future wider-Digibility BFF integration is deferred.)
- **A2. Permanent mock mode** (`VITE_SEO_DATA_MODE`). Every service has a mock
  adapter; mock is the safe default and must never be removed or used to mask a
  real backend failure.
- **A3. Standalone module first, integrate later.** Build/test SEO independently;
  keep architecture compatible with the existing Digibility platform; never
  modify the reference app.
- **A4. Reuse Digibility auth (login-only for MVP).** No separate SEO auth
  system. (Phase 16B; `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md`, 2026-07-13.)
- **A5. Isolated service-role worker** (`crawler-worker/**`) for crawl +
  DNS-TXT `verify-once`; never customer-callable; only claims work
  (`FOR UPDATE SKIP LOCKED` + lease). (`ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`,
  Phase 16A/16C.)
- **A6. Single authoritative crawl-enqueue boundary:** `public.seo_crawl_request`
  is the only production `INSERT INTO seo_crawl_jobs`.
- **A7. Cloud Run static frontend container** (multi-stage Docker → nginx
  serving the compiled SPA); env vars are build-time `VITE_*` (Cloud Run runtime
  env vars do NOT reach a built SPA). Prepared, not deployed. (2026-07-19/20.)
- **A8. Navigation IA:** SEO is one collapsible top-level module with 7 logical
  collapsible groups; SEO Dashboard is the first link. Config-driven via
  `src/registry/navigationGroups.ts` (additive). (2026-07-20.)
- **A9. Reports persistence model = scalar columns + version-tolerant `summary`
  jsonb.** The canonical persisted report (`public.seo_reports`, migration
  `20260720120035`, Reports Stage 1) stores tenancy/period/status/generation
  metadata as indexed scalar columns and the wide cross-module rollup as a
  single `summary` jsonb, so the schema stays stable as upstream rollup fields
  evolve. Reads use **workspace/website-scoped RLS SELECT** (member read;
  owner/admin/team_member write reserved for a later generation stage) and are
  wired through `runWithServiceAdapter` with **no silent mock fallback in
  Supabase mode** (read errors surface). Generation, exports, history,
  scheduling, delivery, and sharing are deferred to later Reports stages. Chosen
  deliberately (operator-confirmed) over per-field wide columns. (2026-07-20;
  TEST-applied + backend-verified, browser acceptance pending — NOT locked.)
- **A10. Report generation = server-side authoritative aggregation via a guarded
  RPC** (Reports Stage 2, migration `20260720120036`; anon-deny corrective
  `20260720120037`). `public.seo_report_generate(p_website_id, p_period_key)` is
  `SECURITY DEFINER` / `search_path=public` / `authenticated`-only; it derives
  workspace/website-url/period/actor/timestamps **server-side** (no client-supplied
  metrics, identity, dates, title or summary), authorizes owner/admin/team_member
  (client/anon/nonmember/cross-tenant denied with one non-leaking message),
  aggregates the six live areas from their tables, and upserts the single canonical
  `seo_reports` row under a transaction-scoped `pg_advisory_xact_lock` keyed by
  (website, report_type, period) + `INSERT … ON CONFLICT DO UPDATE`. Synchronous
  (no async worker). DB-native status semantics: content-completed = `archived`,
  authority-avoided = `avoided`, approvals pending = `suggested|needs_review`,
  fixed = `completed`, audit latest/previous = completed by `COALESCE(completed_at,
  started_at) DESC`. (2026-07-20; TEST-applied + backend-verified; true two-session
  concurrency + browser acceptance pending — NOT locked.)
- **A11. Deterministic page-performance Branch 3 + truthful unavailable-section
  provenance.** The report's improving/declining counts reuse the exact
  `resolvePerformanceStatus` rules (content aging/stale → needs_refresh overrides
  movement; movement mapping otherwise) with snapshot selection primary-keyword →
  page-level → **deterministic fallback `ORDER BY snapshot_date DESC,
  page_keyword_id ASC LIMIT 1`** → no-snapshot. This is exact parity with the
  TypeScript for all deterministic branches plus a deterministic resolution of the
  branch that is non-deterministic in the current TS (unordered `forPage[0]`) —
  **not** byte-identical TS parity for that branch. The three areas with no
  Supabase source (competitor, roadmap, expert-support) are represented as
  **truthful "not connected" + 0**, with a `summary.data_provenance` map marking
  each area `live`/`unavailable` so a 0 is never read as a measured 0 (no
  fabrication). (2026-07-20; TEST-verified via every-branch fixtures.)
- **A12. PDF export = client-side rendering behind a read-only role-gated RPC**
  (Reports Stage 3, migration `20260720120038`). Because there is no BFF/edge
  function (A1), the PDF is rendered **in the browser with `jsPDF`** from the
  already-persisted `seo_reports` row — it **never regenerates or recomputes**.
  The export ACTION is authorized server-side by the `STABLE` `SECURITY DEFINER`
  RPC `seo_report_export_data(website_id, period)` — owner/admin/team_member only
  (client/anon/nonmember/cross-tenant denied, anon EXECUTE revoked), returning the
  canonical stored row unchanged (a workflow gate: clients may VIEW on-screen via
  Stage 1 RLS but may not EXPORT, mirroring who may generate). Unavailable areas
  (`data_provenance='unavailable'`) render **"Not connected"**, never fabricated.
  `jsPDF` (MIT) is a new frontend dependency; CSV/email/sharing/history/scheduling
  remain deferred. Chosen over an edge-function/server renderer (which would need
  new infra + deployment, out of scope). (2026-07-20; TEST-verified +
  browser-accepted.)
- **A13. Competitor Benchmarking persists truthful `estimated` provenance**
  (Competitor Stage 1, migration `20260720123000`, table `public.seo_competitors`).
  Competitor scores are **synthetic heuristic estimates generated locally** — they
  are NOT sourced from SEMrush / Ahrefs / GSC or any external intelligence
  provider. The `data_provenance` column is **CHECK-constrained to `'estimated'`**
  so a persisted row can never be mislabelled `live`/`measured`/`verified`/
  `observed`/`external`; `generation_method` (e.g. `heuristic_v1`) optionally
  identifies the estimate model. Workspace/website-scoped RLS (member SELECT incl.
  client read-only; owner/admin/team_member write), unique on
  `(website_id, normalized_competitor_url)`, read-only from the frontend in Stage 1
  (no silent mock fallback in Supabase mode; Generate/Refresh disabled in Supabase
  mode). Generation is a separate later stage. Any future real-provider integration
  must add a new allowed provenance value via an additive migration — never relabel
  estimated data. **User-facing copy must match this contract:** the
  `COMPETITOR_SAFETY_NOTICE` was corrected from "based on mock data" to "based on
  estimated benchmarking" (2026-07-22) so the notice stays truthful in Supabase
  mode. (2026-07-20; TEST-verified; authenticated Supabase-mode read-path
  OPERATOR-VERIFIED PASS 2026-07-22; NOT locked — generation = Stage 2, deferred.)

## 2. Security & concurrency decisions (current)

- **S1. Verified-ownership precondition for crawl enqueue (P1b).** Enforced
  inside `seo_crawl_request`, **after** authentication/module-access/workspace/
  role authorization and **before** website eligibility/config validation and the
  INSERT — so existing authorization-error precedence is preserved and ownership
  state does not leak to unauthorized callers. (2026-07-19; LOCKED.)
- **S2. `FOR SHARE` lock on the ownership row** is required for verified-at-**write**-time
  correctness (plain READ COMMITTED MVCC gives check-time only). **`FOR KEY
  SHARE` is insufficient** — it does not conflict with a non-key `status`
  UPDATE. No deadlock. **Do not remove `FOR SHARE` later.** Proven with a live
  two-session race. (2026-07-19.)
- **S3. Plain `RAISE EXCEPTION` with default SQLSTATE `P0001`; no custom
  SQLSTATE.** The repo has zero custom SQLSTATEs across ~181 `RAISE EXCEPTION`s;
  P1b keeps that convention. Message: `Domain ownership must be verified before
  this website can be crawled.`
- **S4. Ownership source of truth = `seo_ownership_verifications`** (`method=
  'dns_txt'`, `status='verified'`); absence/pending/failed/revoked/superseded →
  blocked. **No mirror onto `seo_websites`.**
- **S5. Service-role surface is denied to `authenticated`/`anon`.** Lease tokens,
  worker ids, challenge/DNS tokens, and internal diagnostics are never
  customer-readable and never printed in logs.
- **S6. Append-only audit + published-result preservation.** Crawl/ownership
  history is append-only; failed/cancelled attempts never delete or overwrite a
  completed historical audit/published result.

## 3. BFF / trusted-boundary decisions (current)

- **B1.** The `SECURITY DEFINER` RPC + RLS layer **is** the BFF. No separate API
  server is introduced for the MVP.
- **B2.** All writes go through guarded RPCs that resolve workspace/website/role
  server-side and send only minimal parameters (e.g. ownership RPCs send **only**
  `p_website_id`); the frontend never authorizes writes on its own.
- **B3.** Reads use RLS-scoped SELECT on customer-safe columns only; internal
  claim/lease/diagnostic tables are never read by the frontend.

## 4. Backward-compatibility requirements (current)

- **C1. Additive migrations only; applied migrations are immutable.** New behavior
  = new timestamped migration (`CREATE OR REPLACE` where a contract must be
  preserved), never an edit to an applied file.
- **C2. Preserve every locked contract** (names/params/returns/grants, status
  strings, query keys, read-shape types, role behavior, idempotency,
  single-active-job, event creation).
- **C3. New frontend APIs are additive + typed;** omitted optional props render
  exactly as before (e.g. `PlaceholderPage` `helpRoute`/`helpLabel`).
- **C4. Never remove mock mode; never expose service-role in the frontend.**

## 5. Lock / change-control rules (current)

- **L1.** Locked modules: Page Performance Tracker; Stage 6 (Off-Page + AI
  Visibility); Crawler 16C–16H; P1a; P1b (all in `MODULE_LOCKS.md`).
- **L2.** Any change to a locked file/contract requires that lock's
  **additive-extension + evidence procedure** (reproduction or additive spec →
  expected/actual → evidence → additive-only design → **explicit approval** →
  additive migrations only), then targeted locked-scope regression + a dated
  owner-doc note.
- **L3.** Adding *only a link* into a locked file is still a change to that locked
  module and follows L2 (this is why locked-module contextual Help links are
  deferred to Wave 3).

## 6. Production-promotion rules (current)

- **P1. Production stays untouched** until a separately-approved promotion task
  satisfies the `BACKEND_MILESTONE_HANDOFF.md` §5 gates.
- **P2. Promotion is planned first** (planning-only doc, no DB action), then
  approved, then applied with a migration order + rollback plan, then verified,
  then signed off — mirroring the TEST plan→apply→verify→sign-off pattern.
- **P3.** Cloud Run container-runtime verification remains **deferred to the TEST
  promotion gate**; it must not be represented as done.

## 7. Deferred UI defense-in-depth decision (current)

- **D1.** Optional client-side pre-block of a crawl before the server rejects an
  unverified website is **explicitly deferred** and **non-blocking**, because
  P1b already enforces verified-only enqueue **server-side and mandatorily**. If
  built, it touches the **locked** crawl-UI and must follow the Crawler 16C–16H
  additive-extension procedure. Not approved for implementation.

## 8. Terminology decisions (current)

- **T1. "Visibility Dashboard" → "SEO Dashboard"** (user-facing). "Visibility" is
  a separate Digibility module and must never be used as a synonym for SEO. The
  internal registry id `visibility-dashboard` is **retained** for backward
  compatibility (not user-visible). Unrelated legitimate "visibility" usage —
  the "search visibility score" metric and "AI Visibility / GEO Engine" — is
  untouched. (2026-07-20.)

## 9. Rejected or superseded decisions (historical — NOT active)

- **R1. `FOR KEY SHARE` for the ownership lock** — rejected (S2): does not
  conflict with a non-key `status` UPDATE, so it would not guarantee
  verified-at-write-time correctness.
- **R2. A custom SQLSTATE for the P1b rejection** — rejected (S3): breaks the
  repo's zero-custom-SQLSTATE convention.
- **R3. Mirroring ownership status onto `seo_websites`** — rejected (S4): the
  verification table is the single source of truth.
- **R4. A separate SEO authentication system** — rejected (A4): SEO reuses
  Digibility auth.
- **R5. "One RPC across an arbitrarily long burst" as the ownership double-submit
  acceptance criterion** — retired during P1a Step 5 as unsound; the accepted
  guard is a per-action visible bounded post-action lock (idle→in_flight→cooldown).
- **R6. Reports as a live/production feature** — not a decision so much as a
  status correction: Reports is **mock-only** today (see
  `SEO_IMPLEMENTATION_STATUS.md` §7); any "reports are live" reading is superseded.
- **R7. Pre-execution P1b framing** ("P1b not locked / next action is approval to
  apply") in `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_PLAN.md`'s implementation-artifacts
  note — **superseded**; P1b is COMPLETE + LOCKED. The plan's §1 already states
  the final status; the stale note is labelled superseded in this consolidation.
