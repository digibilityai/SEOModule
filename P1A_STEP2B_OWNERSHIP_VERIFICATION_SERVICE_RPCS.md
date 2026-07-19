# P1a Step 2B — Service-role ownership-verification RPCs + global-admin override (record)

**Status:** `IMPLEMENTED + TEST-VERIFIED (Digi_SEO_Test) — additive; production untouched` (2026-07-16).
**Scope:** Step 2B only — the trusted backend API for the FUTURE isolated DNS-TXT
verification worker (Step 3) and the global-admin administrative path. **P1a is
NOT complete. Step 3 (worker) is NOT included and NOT implemented.** No worker
code, no DNS resolution, no frontend, no crawl change, no P1b enforcement.

**Builds on:** `…120031` (Step 1 tables) + `…120032` (Step 2A customer RPCs).
**Migration:** `supabase/migrations/20260716120033_seo_p1a_step2b_ownership_verification_service_rpcs.sql`.

---

## 1. What was delivered (additive only)
- **`seo_ownership_verification_claims`** — new **internal** claim/lease ledger
  (mirrors the crawler's internal `seo_crawl_attempts` split). Columns:
  verification_id/workspace_id/website_id, worker_id, lease_token, claimed_at,
  lease_expires_at, released_at, outcome, `internal_error_code`/
  `internal_error_detail` (INTERNAL). **RLS: global-admin SELECT only** → lease
  tokens / worker ids / internal diagnostics are **not** customer-readable. A
  **partial unique index** (`verification_id WHERE released_at IS NULL`) enforces
  at most one OPEN claim per verification.
- **`seo_ownership_verification_claim(p_worker_id text, p_lease_seconds int DEFAULT 120)`**
  — **SERVICE-ROLE ONLY**. Atomically selects one eligible `pending`/`failed`
  `dns_txt` verification with no open unexpired claim (`FOR UPDATE SKIP LOCKED`),
  releases any expired open claim (stale recovery → `lease_expired`), opens one
  new lease. **Returns only**: `verification_id, workspace_id, website_id,
  verification_host, dns_txt_name (=_digibility-site-verification.<host>),
  expected_challenge_value (challenge token), lease_token, lease_expires_at`.
- **`seo_ownership_verification_record_result(p_verification_id uuid, p_worker_id text, p_lease_token uuid, p_outcome text, p_failure_reason text, p_internal_error_code text, p_internal_error_detail text)`**
  — **SERVICE-ROLE ONLY**. Validates the OPEN claim + workspace/website
  consistency; accepts only `verified`/`failed`; persists customer-safe status +
  timestamps (customer-safe `failure_reason`; internal diagnostics stay on the
  claim row); **does NOT rotate the challenge token**; appends exactly one
  customer event (`verified`/`failed`); duplicate identical result is idempotent;
  rejects stale/mismatched/cross-workspace/cross-website claims.
- **`seo_ownership_verification_admin_override(p_website_id uuid, p_action text, p_reason text)`**
  — `authenticated`, **internally `seo_is_global_admin`-gated**. Actions:
  `mark_verified` (create-or-update → verified) and `invalidate` (→ revoked).
  Requires a non-empty reason; resolves website/workspace/host server-side;
  appends one `admin_override` event (`actor='global_admin'`, actor id + action +
  reason); idempotent on a repeat of the same terminal action. Ordinary
  owner/admin/team_member/client/non-member are rejected; owner/admin customer
  permissions are unchanged.

**Return shapes:** claim → the 8-column TABLE above; result + override →
`public.seo_ownership_verifications` (customer-safe row).

## 2. Lease model (mirrors Phase 16D; no crawler object reused)
Random `lease_token uuid` + bounded `lease_expires_at`; `FOR UPDATE SKIP LOCKED`
claim; expired-lease recovery invalidates the previous worker's token; result
persistence validates `(verification_id, worker_id, lease_token)` against the
OPEN claim. The crawler's tables/leases/statuses/RPCs are **not** reused or
modified — this is a separate ownership-only ledger.

## 3. Security
`SECURITY DEFINER` + `SET search_path = public` on all three RPCs; explicit
grant/revoke; **claim + result revoked from PUBLIC/anon/authenticated
(service_role only)**; override revoked from anon, granted to authenticated but
internally global-admin-gated. No client-supplied workspace/host/role/status/
ownership trusted (all resolved server-side). Append-only customer audit
preserved. Internal diagnostics live only on the admin-only claims table.
Customer-safe errors only; no secret/credential exposure.

## 4. Locked-scope compliance — no lock update needed
No applied migration edited (`…120031`/`…120032` and earlier untouched); **no
crawler table/RPC/status/worker/UI touched** (16C–16H standalone verifications
all re-run ALL PASS; `seo_crawl_request`/`seo_crawl_request_audit`/
`seo_crawl_cancel`/`seo_crawl_claim_job` unchanged); no Page-Performance or
Stage-6 object touched; no existing RLS policy modified (only a new policy on the
new table). **This DB-only step changes no locked contract, so `MODULE_LOCKS.md`
requires no update** (the locked Crawler 16C–16H and Page Performance entries are
unaffected).

## 5. Verification evidence (executed on Digi_SEO_Test, 2026-07-16)
- **Dry-run:** migration in one transaction + forced abort → rollback; post-check
  confirmed 0 claims table + 0 RPCs persisted.
- **Apply:** `supabase db push --linked` applied `…120033` (recorded). An
  in-session ambiguous-column defect (the claim `RETURNS TABLE` output columns
  shadowing the claim table in the stale-recovery `UPDATE`) was fixed in the
  migration (aliased the table) and the corrected, fully-idempotent migration was
  re-applied to TEST.
- **Structural:** claims table + RLS (1 admin-SELECT policy) + open-claim unique
  index; 3 RPCs SECURITY DEFINER + `search_path=public`; claim/result executable
  by `service_role` only (authenticated/anon denied); override authenticated /
  anon denied.
- **Step 2B SQL verification**
  (`supabase/test/seo_p1a_step2b_ownership_verification_service_rpcs_verification.sql`):
  **ALL PASS** — 35 checks (structure/grants; claim eligibility incl. failed
  re-claim, verified/revoked-not-claimable, duplicate-concurrent prevention,
  stale/expired recovery, returned-fields, cross-website mismatch; result
  verified/failed, customer-safe reason, internal-diagnostics-not-customer-
  readable, stale rejection, idempotency, one-event-per-result, token-not-rotated;
  global-admin mark_verified/invalidate with reason + server-side resolution +
  audit actor + idempotency + empty-reason rejection; non-global-admin override
  denial for all 5 roles; Step 2A customer RPCs still operational; team/client
  write denial; direct customer table writes denied; customer-safe RLS reads;
  crawler RPC non-regression; other-module isolation). Idempotent + self-cleaning
  (tagged disposable websites `af…a3/a4/a5`; a **self-cleaning temporary
  `profiles` stub** created only-if-absent to exercise the global-admin path, then
  dropped; teardown asserts 0 residual).
- **Regression:** Step 2A + Step 1 **ALL PASS**; standalone Phase **16C, 16D,
  16E, 16F, 16G, 16H** verifications **ALL PASS**; **worker crawl suite 47/47
  pass, 0 fail**; frontend `tsc --noEmit -p tsconfig.app.json` clean; `npm run
  build` OK.

## 6. Rollback
`supabase/test/seo_p1a_step2b_ownership_verification_service_rpcs_rollback_TEST_ONLY.sql`
drops only the 3 RPCs + the claims table; **preserves** Step-1 tables + audit
history, Step-2A customer RPCs, all crawler objects/data, Page Performance,
Stage 6, and every earlier migration. TEST only; do not run unless instructed.

## 7. Next step
**P1a Step 3 — isolated DNS-TXT verification worker module** is now **✅ done +
TEST-verified** (code-only additive extension of the locked `crawler-worker/**`;
calls these Step 2B RPCs) — see `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`. The
**exact next task is P1a Step 4 — frontend ownership-verification service, types,
hooks, and mock adapter.** Step 6 (P1a sign-off) and P1b remain excluded.

**Addendum (2026-07-18):** this Step 2B SQL verification script was re-run on TEST
(as part of a post-Step-6 regression checkpoint) and returned **ALL PASS** again —
see `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §10 (2026-07-18 entry) for the
full evidence. No file in this record changed.
