# P1b — Verified-only Crawl Enqueue Enforcement — Implementation Plan

**This document is a design specification. It contains NO executed migration, no
applied SQL, no code change. Illustrative SQL below is labelled as a design
specification only.** Authoritative current status lives in
`CURRENT_PROJECT_STATUS.md`; if that file ever disagrees with this one about
*status*, that file wins and this one is stale.

---

## 1. Status and authority

- **Status:** `P1b COMPLETE — TEST-APPLIED, VERIFIED, and MODULE-LOCKED on Digi_SEO_Test` (2026-07-19). Prior: `IMPLEMENTATION ARTIFACTS CREATED; NOT YET EXECUTED` then `ARCHITECTURE VALIDATED — AUTHORITATIVE PLAN` (both 2026-07-19). Full results + evidence: `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md`. Formal lock: `MODULE_LOCKS.md` ("P1b — Verified-only Crawl Enqueue Enforcement").
- **Implementation-artifacts note (2026-07-19) — ⚠️ SUPERSEDED (historical, pre-execution snapshot; retained for traceability only).** _This bullet describes the state BEFORE TEST execution. It is no longer current: the migration was subsequently APPLIED to `Digi_SEO_Test`, all verification + regression + concurrency proofs PASSED, and **P1b is now COMPLETE, TEST-APPLIED, VERIFIED, and MODULE-LOCKED** (see this section's §1 status line, `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md`, and the `MODULE_LOCKS.md` P1b entry). Read the phrases "No migration applied", "P1b not locked", and "The next action is explicit approval to apply" below as historical only._ — the approved build now exists in-repo and is statically reviewed — (1) additive migration `supabase/migrations/20260719120034_seo_p1b_verified_only_crawl_enqueue.sql` (`CREATE OR REPLACE seo_crawl_request` + the §8 guard; static diff vs applied 16C = guard only); (2) TEST-only rollback `supabase/test/seo_p1b_verified_only_crawl_enqueue_rollback_TEST_ONLY.sql` (restores the exact original); (3) the six 16C–16H verification scripts updated with token-marked verified-ownership fixtures (§14); (4) new `supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql` (§15 matrix); (5) companion `P1B_CONCURRENCY_VERIFICATION_GUIDE.md` (two-session FOR SHARE proof). **No migration applied; no verification run; no DB/production change; P1a untouched; P1b not locked.** The next action is explicit approval to apply + run on TEST (see §20 step 2–6). _(End of superseded historical note.)_
- **Authority chain:** `CURRENT_PROJECT_STATUS.md` (status) → `PROJECT_DOCUMENTATION_INDEX.md` (map) → `MODULE_LOCKS.md` (lock registry) → this plan (P1b design scope).
- **Predecessor:** P1a — Domain Ownership Verification — **COMPLETE and MODULE-LOCKED** (2026-07-19, `MODULE_LOCKS.md`). P1a is the source of the verified-ownership state P1b consumes. **P1a is not modified by P1b.**
- **Lock posture:** P1b is the explicitly deferred, currently **UNLOCKED** follow-on named in the Crawler 16C–16H lock's "Deferred scope" and the P1a lock's "Deferred scope". The enqueue RPC it changes (`seo_crawl_request`) is nevertheless a **locked contract** — implementation requires the Crawler lock's additive-extension + evidence procedure (see §18).
- **Production:** untouched. This plan authorizes no production action.

## 2. Objective

Ensure a website can enter the crawl workflow **only when its domain ownership is
currently `verified`**, enforced at the trusted server-side write boundary that
creates crawl work, while preserving the existing architecture, backward
compatibility, role model, workspace isolation, and every locked-module contract.

## 3. Scope

- Add a verified-ownership precondition to **new crawl-job creation** in
  `public.seo_crawl_request` (the single authoritative enqueue boundary).
- Enforcement is **server-side and mandatory**. It covers all runtime enqueue
  paths (UI, direct `seo_crawl_request_audit`, direct `seo_crawl_request`).
- Update the six Phase 16C–16H regression scripts with verified-ownership
  fixtures (§14) and add one new P1b acceptance script (§15).
- Optional, separately approved, defense-in-depth UI prevention (§16).

## 4. Non-goals

- **No** change to P1a ownership tables, RPCs, worker, UI, or semantics.
- **No** change to the crawler worker (`crawler-worker/**`) — it only claims
  existing jobs; it must remain untouched.
- **No** cancellation/halting of already queued, leased, running, retrying, or
  stale-recovering jobs; **no** change to crawl lifecycle, retry, or stale
  recovery (§12).
- **No** custom SQLSTATE, no error-taxonomy change, no new machine-readable code.
- **No** mirroring of ownership status onto `seo_websites`.
- **No** BFF introduction; browser → Supabase RPC direct remains the model.
- **No** production deployment; **no** usage/subscription enforcement.
- A revocation policy for an **in-flight** crawl is explicitly out of scope
  unless separately approved.

## 5. Confirmed current enqueue architecture

**Runtime paths (the only ones that exist):**

1. **UI:**
   `CrawlPanel` (`src/pages/seo/audit/crawl/CrawlPanel.tsx`)
   → `useRequestWebsiteCrawl` (`src/hooks/useWebsiteCrawl.ts`)
   → `crawlService.requestAuditCrawl` (`src/services/crawlService.ts`)
   → `requestSupabaseAuditCrawl` (`src/services/supabase/seoCrawlSupabaseService.ts`)
   → `rpc("seo_crawl_request_audit")`
   → **DB** `seo_crawl_request_audit`
   → **DB** `seo_crawl_request`.
2. **Authenticated direct invocation** of `seo_crawl_request_audit` (GRANTed to `authenticated`).
3. **Authenticated direct invocation** of `seo_crawl_request` (GRANTed to `authenticated`; the frontend never calls it directly, but it is independently reachable via the API).

**Confirmed by inspection:**

- `seo_crawl_request_audit` is the **only** database-internal caller of
  `seo_crawl_request` (`…phase16g_publishing.sql:213`), and it calls it **before**
  creating the audit run — so a rejection rolls the whole orchestration back.
- `seo_crawl_request` contains the **only** production `INSERT INTO
  public.seo_crawl_jobs` in the schema (`…phase16c_crawl_control_plane.sql:404`).
- The worker enqueues nothing — `crawler-worker/src/jobGateway.ts` calls only
  `seo_crawl_claim_job`.
- **No** cron, scheduler, automation, admin utility, seed script, or secondary
  API enqueue path currently exists.

## 6. Authoritative enforcement boundary

**`public.seo_crawl_request`.** It is the single job-creation choke point; both
customer entry points funnel through its one `INSERT`, and the worker never
creates jobs. A guard placed here covers 100% of enqueue paths (direct,
orchestrated, future) with the locked worker untouched.

**Placement within the function:** the guard runs **after** authentication,
SEO-module-access, workspace resolution, and role authorization, and **before**
website eligibility/config validation and the crawl-job INSERT. This ordering:

- preserves existing authorization-error precedence (unauthorized callers still
  receive the existing permission/authentication error first);
- avoids revealing ownership state to unauthorized users;
- ensures an authorized caller on an unverified site receives the ownership
  rejection before eligibility/config checks.

**Frontend-only enforcement is insufficient:** `canRequest`/`errorMessage` in the
crawl UI are affordances; a direct authenticated `rpc(...)` bypasses the UI, and
RLS cannot express a verified-only precondition for a `SECURITY DEFINER` RPC. The
check must live in the trusted RPC body.

## 7. Ownership source of truth

Table **`public.seo_ownership_verifications`** (P1a Step 1), with the predicate:

- `website_id = p_website_id`
- `method = 'dns_txt'`
- `status = 'verified'`

State handling (all resolve to "not verified" → blocked, except `verified`):

| Ownership state | Enqueue |
|---|---|
| `verified` | allowed (subject to existing role/eligibility/config checks) |
| `pending` | blocked |
| `failed` | blocked |
| `revoked` | blocked |
| **no row** (absence == unverified) | blocked |
| superseded (reverify → back to `pending`; admin invalidate → not `verified`) | blocked |

There is **no `expired` state** in P1a (no auto-expiry) — nothing to special-case.
**Do not** mirror or duplicate ownership status into `seo_websites`; the P1a
table remains the single source of truth.

## 8. Exact proposed database guard

> **DESIGN SPECIFICATION ONLY — NOT AN EXECUTED MIGRATION.** The following
> illustrates the guard to be added inside a later `CREATE OR REPLACE FUNCTION
> public.seo_crawl_request(...)`. It is shown for review; it has not been applied.

Inserted after the role-authorization block (the `v_role` resolution) and before
the website-eligibility (active/archived) check:

```sql
-- P1b: verified-only enqueue. Ownership must be CURRENTLY verified. FOR SHARE
-- serializes this check against a concurrent ownership revocation/status update
-- so the decision is correct at write/commit time, not merely at check time
-- (see plan §9 — do NOT remove this row lock as an "optimization").
PERFORM 1
  FROM public.seo_ownership_verifications
 WHERE website_id = p_website_id
   AND method     = 'dns_txt'
   AND status     = 'verified'
   FOR SHARE;
IF NOT FOUND THEN
  RAISE EXCEPTION 'Domain ownership must be verified before this website can be crawled.';
END IF;
```

Everything else in `seo_crawl_request` (signature, return type, grants, role
matrix, idempotency, single-active-job rule, event creation) is **unchanged**.

## 9. Concurrency and `FOR SHARE` rationale

**Requirement:** verified-at-**write/commit**-time correctness (acceptance
criterion: "verified→revoked race blocked at write time").

- **Plain READ COMMITTED MVCC is insufficient.** The `SELECT` and the `INSERT`
  are separate statements; a revoke that commits after the check's snapshot is
  not seen by the already-executed check, so a job could be created against a
  just-revoked website. MVCC gives verified-at-*check*-time only.
- **`FOR SHARE` provides write-time correctness:**
  - *Enqueue locks first* → the concurrent revoke `UPDATE` blocks until enqueue
    commits; the valid enqueue completes (revoke applies after). Acceptable.
  - *Revoke locks first* → enqueue's `FOR SHARE` blocks; after the revoke
    commits, READ COMMITTED **EvalPlanQual** re-evaluates the updated row against
    `WHERE status = 'verified'`; it no longer qualifies → `NOT FOUND` → enqueue
    **rejected**. Blocked at write time.
- **Lock-mode correctness:** a revoke `UPDATE` of the non-key `status` column
  takes a `FOR NO KEY UPDATE` tuple lock. **`FOR SHARE` conflicts with it**
  (serializes correctly). **`FOR KEY SHARE` is insufficient** because it does
  **not** conflict with a non-key status update, leaving the race open.
- **No deadlock:** the only shared lock target is the single ownership row.
  Enqueue then touches `seo_crawl_jobs` (which revoke never touches); revoke
  touches `seo_ownership_verification_events` (which enqueue never touches). No
  opposite-order acquisition of a second common resource → no cycle.
- **Cost:** one row lock for the microseconds of the function; contention only
  against a concurrent revoke/reverify/admin_override of the **same** website —
  vanishingly rare and correctly serialized.
- **Precedent:** P1a Step 2B's `seo_ownership_verification_claim` already uses
  explicit row locking (`FOR UPDATE SKIP LOCKED`); `FOR SHARE` here is idiomatic.

**Do not remove this row lock in a later refactor.** It is required for the
accepted write-time criterion, not a micro-optimization.

## 10. Error contract

- **Convention:** the repository uses plain `RAISE EXCEPTION 'message'`
  throughout (181 occurrences; **zero** custom SQLSTATEs). Errors are
  message-based; the frontend forwards `normalizeSupabaseError(error).message`
  and ignores `code`.
- **P1b error:** `RAISE EXCEPTION 'Domain ownership must be verified before this
  website can be crawled.'`
- **Effective SQLSTATE:** the existing default **`P0001`** (raise_exception). **No
  custom SQLSTATE is introduced** — a machine-readable taxonomy would be a
  separate cross-cutting decision, out of P1b scope.
- **Delivery:** identical to the five existing `seo_crawl_request` errors — surfaces
  through `seo_crawl_request_audit`, `requestSupabaseAuditCrawl`
  (`throw new Error(normalizeSupabaseError(error).message)`), and the mutation
  error in the hook. Backward-compatible: existing callers already handle a
  thrown message.

## 11. Backward-compatibility guarantees

Preserved unchanged in `seo_crawl_request` / `seo_crawl_request_audit`:

- exact function **name**;
- exact **parameter list** (`p_website_id uuid, p_idempotency_key text, p_config jsonb`);
- **return type / result contract** (`uuid` / `TABLE(audit_run_id, crawl_job_id, job_status)`);
- **grants** (`authenticated`; `anon`/PUBLIC revoked);
- **role behavior** (owner/admin/team_member/global_admin allowed; client denied);
- **idempotency** (same key in workspace returns the existing job);
- **single-active-job** rule (partial unique index);
- **crawl-event** creation (append-only `queued` event);
- `seo_crawl_request_audit` needs **no change** (inherits the guard; a rejection
  rolls back the whole orchestration → no orphan audit run).

**Intended behavior change (only this):** an authorized caller crawling a
**non-verified** website now receives a rejection where it previously succeeded.

## 12. Existing-job behavior

P1b applies **only to creation of new crawl jobs**. It must not:

- cancel already queued jobs;
- halt leased or running jobs;
- block worker retries of an existing job;
- alter stale-job recovery;
- change any crawl lifecycle behavior.

A job, once created against a then-verified website, proceeds through its normal
lifecycle even if ownership is later revoked. A revocation policy for an
in-flight crawl is **out of scope unless separately approved** (would touch
locked worker/lifecycle behavior).

## 13. Expected implementation change set

- **Database (core, new additive migration):** one new timestamped migration
  `…_seo_p1b_verified_only_crawl_enqueue.sql` that `CREATE OR REPLACE FUNCTION
  public.seo_crawl_request(...)` with the §8 guard. **Do NOT edit** the applied
  `20260713120025_seo_phase16c_crawl_control_plane.sql`. `seo_crawl_request_audit`
  unchanged. A P1b rollback script restoring the pre-P1b function body.
- **Frontend:** none required for the mandatory step (browser → RPC direct
  preserved). Optional defense-in-depth is a separate follow-up (§16).
- **Service/BFF:** none (no BFF exists).
- **Tests:** update the six Phase 16C–16H verification scripts (§14); add
  `supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql` (§15);
  re-run worker suite (expected unaffected).
- **Documentation:** this plan; plus the status/handover/handoff/index/lock notes
  (§19).
- **Explicitly untouched:** all P1a objects; the crawler worker; `seo_crawl_cancel`,
  `seo_crawl_claim_job`, and all worker lifecycle/discovery/extraction/publishing/
  finalization RPCs; applied migrations `…120025`–`…120033` (immutable).

## 14. Regression fixture update inventory

These six verification scripts currently create crawl jobs against fixture
websites with **no** verified ownership row and will require verified-ownership
fixtures during implementation:

- `supabase/test/seo_phase16c_crawl_control_plane_verification.sql`
- `supabase/test/seo_phase16d_worker_lifecycle_verification.sql`
- `supabase/test/seo_phase16e_crawl_discovery_verification.sql`
- `supabase/test/seo_phase16f_crawl_extraction_verification.sql`
- `supabase/test/seo_phase16g_publishing_verification.sql`
- `supabase/test/seo_phase16h_crawl_audit_finalization_verification.sql`

**Fixture nuances (to preserve each test's intended failure reason):**

- Seed a `verified` `seo_ownership_verifications` row (`method='dns_txt'`) for
  **each website expected to reach or pass enqueue** (16C `v_site`; 16D/16E/16F
  fixture websites; 16G `g.web`; 16H fixture website).
- **16C inactive-site fixture:** also seed a `verified` row for the inactive-site
  fixture so its negative test continues to fail for **inactivity**, not
  ownership (ownership is checked before the active/archived check).
- **16C config-validation fixtures:** run on `v_site` (already verified), so they
  continue to fail for **configuration**, not ownership.
- **16G cross-workspace `g.wother`:** keep **unverified** so the cross-workspace
  negative test still fails first on **authorization** (the intended reason).
- **No changes needed** to: P1a verification scripts (they only check
  `has_function_privilege` on the crawl RPCs, never invoke them), the 16C/16G
  rollback scripts (DROP only), any seed script (none enqueue), or the worker
  test suite (the worker never enqueues — it only claims).

## 15. P1b acceptance matrix

Implementation will add
`supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql` covering:

| # | Case | Expected |
|---|---|---|
| 1 | ownership `verified`, authorized role | enqueue **succeeds** (direct + audit) |
| 2 | `pending` | **blocked** |
| 3 | `failed` | **blocked** |
| 4 | `revoked` | **blocked** |
| 5 | **no** ownership row | **blocked** |
| 6 | unauthorized role | existing **authorization** error remains first (not the ownership error) |
| 7 | non-member | blocked by existing authorization |
| 8 | anonymous | blocked by existing authentication |
| 9 | cross-workspace attempt | blocked by existing authorization |
| 10 | direct `seo_crawl_request` invocation | cannot bypass — **blocked** when not verified |
| 11 | direct `seo_crawl_request_audit` invocation | cannot bypass — **blocked** when not verified |
| 12 | blocked audit request | creates **neither** a crawl job **nor** an audit run |
| 13 | verified→revoked race | serialized via `FOR SHARE`; **rejected** when revocation wins |
| 14 | idempotency (verified) | unchanged (same key returns existing job) |
| 15 | single-active-job (verified) | unchanged |
| 16 | crawl-event creation (verified) | unchanged (one append-only `queued` event) |
| 17 | worker lifecycle after a valid enqueue | unchanged |
| 18 | Phase 16C–16H regression (post-fixture) | **ALL PASS** |
| 19 | worker suite | **PASS (74/74)** |

The new script must be idempotent and self-cleaning (tagged disposable fixtures),
consistent with the existing verification-script conventions.

## 16. UI defense-in-depth follow-up (optional, separately approved)

Not part of the first mandatory P1b step. If later approved:

- Read ownership status via the **existing P1a read path**
  (`useOwnershipVerificationStatus`) — no new read surface.
- Disable or explain "Start crawl" in `CrawlPanel`/`StartCrawlControl` when the
  site is not `verified`, with a customer-safe explanation.
- Surface the RPC's customer-safe rejection message (currently
  `CrawlPanel.tsx` shows a generic string) instead of the generic retry text.
- **Not authoritative** — UI state must never replace the server gate.
- The crawl UI files (`CrawlPanel.tsx`, `StartCrawlControl.tsx`, and the crawl
  hooks/services) are **LOCKED** (Crawler 16C–16H) → this change requires the
  additive-extension procedure (§18).

## 17. Security and workspace-isolation requirements

- Enforcement lives in the trusted `SECURITY DEFINER` RPC; the frontend gate is
  defense-in-depth only.
- **No service-role credential** and **no browser-side secret** are introduced;
  the guard reads the P1a table inside the definer function (no new grant needed).
- Workspace isolation preserved: the guard keys strictly on `p_website_id`; the
  existing role check already resolves and enforces workspace membership before
  the ownership check, so a verified row in another workspace can never authorize
  a crawl of this website.
- The ownership check does not expose challenge tokens, lease tokens, internal
  diagnostics, or verification state to unauthorized callers (it runs after
  authorization and returns only allow/deny).

## 18. Locked-contract and unlock-extension procedure

- The crawler **enqueue contract is currently LOCKED** — `MODULE_LOCKS.md`
  protects the `seo_crawl_request` / `seo_crawl_request_audit` names + parameter
  contracts (Crawler 16C–16H entry).
- P1b is an **explicitly deferred extension** ("domain-ownership verification" in
  the Crawler and P1a "Deferred scope"), but modifying `seo_crawl_request` still
  requires the existing lock's **additive-extension + evidence procedure**:
  reproduction/spec → expected/actual → evidence → additive-only design →
  explicit human approval → **additive migration only** (no edit to the applied
  16C migration) → targeted locked-scope regression re-run (the crawler DB
  verifications + worker suite + relevant checks) → dated owner-doc note.
- **P1a remains LOCKED and untouched.**
- After full acceptance, **P1b should receive its own formal lock entry** in
  `MODULE_LOCKS.md` (locked scope = the verified-only enqueue precondition; locked
  file = the new migration's `seo_crawl_request` body; protected contract = the
  verified-ownership precondition + its `FOR SHARE` atomicity + the customer-safe
  message).
- **Production remains untouched** until a separately approved promotion stage.

## 19. Documentation update requirements

On implementation and acceptance, update (preserving older dated statements as
history):

- `CURRENT_PROJECT_STATUS.md` — authoritative status entries at each checkpoint.
- `CHATGPT_CONTEXT_HANDOVER.md` — current stage + exact next step.
- `BACKEND_MILESTONE_HANDOFF.md` — dated checkpoints.
- `PROJECT_DOCUMENTATION_INDEX.md` — register P1b artifacts (plan, migration,
  new verification script).
- `MODULE_LOCKS.md` — dated additive-extension note on the Crawler lock during
  implementation; a formal P1b lock entry after acceptance.
- This plan — dated addenda as decisions evolve.

## 20. Implementation sequence

1. **(This document)** Authoritative plan — DONE.
2. **Approval gate** — explicit human approval to modify the locked
   `seo_crawl_request` under the additive-extension procedure.
3. **DB guard** — author the new additive migration (`CREATE OR REPLACE`
   `seo_crawl_request` + §8 guard) and a P1b rollback script. Apply to
   `Digi_SEO_Test` only (dry-run → push), never production.
4. **Fixtures** — update the six Phase 16C–16H verification scripts (§14).
5. **Acceptance script** — add `seo_p1b_verified_only_crawl_enqueue_verification.sql`
   (§15); run on TEST → ALL PASS.
6. **Regression** — re-run 16C–16H DB verifications + worker suite (74/74) →
   ALL PASS.
7. **Docs** — update the authoritative docs (§19); dated `MODULE_LOCKS.md` note.
8. **Operator acceptance** — as required (authenticated browser: unverified site
   blocked, verified site succeeds).
9. **Lock** — add the formal P1b lock entry after full acceptance.
10. **(Deferred)** Optional UI defense-in-depth (§16), separately approved.
11. **(Deferred)** Production promotion, separately approved.

## 21. Final implementation-ready decision

The P1b architecture is **validated and implementation-ready**:

- **Boundary:** `public.seo_crawl_request`, guard after authorization and before
  eligibility/INSERT — single choke point covering all enqueue paths; worker
  untouched.
- **Source of truth:** `public.seo_ownership_verifications`
  (`website_id`, `method='dns_txt'`, `status='verified'`); no mirroring.
- **Concurrency:** `FOR SHARE` (required for write-time correctness; `FOR KEY
  SHARE` insufficient; no deadlock; do not remove).
- **Error:** plain `RAISE EXCEPTION` with the customer-safe message; default
  `P0001`; no custom SQLSTATE.
- **Migration:** one new additive `CREATE OR REPLACE` migration; the applied 16C
  migration is not edited.
- **Backward compatibility:** name/params/return/grants/role/idempotency/
  single-active-job/event all preserved; only a new rejection added.
- **Scope:** new enqueue only; existing jobs and the worker unchanged.

**Next action is not implementation** — it is the explicit approval gate (§20
step 2). No code, migration, SQL, worker, frontend, `.env`, or production change
has been made by this plan.
