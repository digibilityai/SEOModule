# P1a Step 2A — Guarded CUSTOMER ownership-verification RPCs (implementation record)

**Status:** `IMPLEMENTED + TEST-VERIFIED (Digi_SEO_Test) — additive; production untouched` (2026-07-16).
**Scope:** Step 2A only — the guarded, customer-facing database API over the
Step-1 tables. **P1a is NOT complete.** **Step 2B is NOT included** (service-role
claim/result + global-admin override). No worker, no DNS resolution, no frontend,
no crawl change, no P1b enforcement.

**Builds on:** `P1A_STEP1_OWNERSHIP_VERIFICATION_DB_CONTRACT.md` (migration `…120031`).
**Migration:** `supabase/migrations/20260716120032_seo_p1a_step2a_ownership_verification_rpcs.sql`.

---

## 1. What was delivered (additive only)
Four SECURITY DEFINER, `SET search_path = public`, `authenticated`-only (PUBLIC/anon
revoked), server-authorized customer RPCs, plus three internal helpers.

**Customer RPCs (owner/admin only; team_member/client/non-member denied):**
- `seo_ownership_verification_initiate(uuid)`
- `seo_ownership_verification_recheck(uuid)`
- `seo_ownership_verification_reverify(uuid)`
- `seo_ownership_verification_revoke(uuid)`

**Internal helpers (NOT granted to authenticated/anon):**
- `seo_ownership_extract_host(text)` — parse host from the authoritative
  `website_url` (parse only; **not** DNS resolution).
- `seo_ownership_new_challenge_token()` — strong per-record TXT token
  (`'digibility-site-verification=' || 2× gen_random_uuid()`, 256 bits CSPRNG;
  no pgcrypto dependency).
- `_seo_ownership_authorize(uuid)` — shared non-masking auth (authenticated +
  `has_seo_module_access` + server-side website resolve + owner/admin role +
  host derivation), raising verbatim on any failure.

Each RPC returns the full **customer-safe** `seo_ownership_verifications` row.

## 2. Status read — NO RPC added (direct RLS)
Repository inspection confirmed every Step-1 column is customer-safe and both
tables carry a workspace-member SELECT policy, so **customer-safe status is read
directly through existing RLS**. Per the Step 2A rule, **no status RPC was created**.
The internal-field guard test confirms the customer table exposes no
correlation/worker/lease/internal-error/service-role columns.

## 3. Behavioural contract (exact, as implemented)
All actions require **owner or admin**; workspace/website/current-host/role are
resolved server-side; client-supplied values are never trusted; every meaningful
state change appends exactly one append-only audit event.

- **initiate:**
  - no record → create (`pending`, fresh token, host snapshot); event `initiated`.
  - record `failed`/`revoked`, or `pending` with a **changed host** → restart:
    rotate token, set `pending`, refresh host/url, clear `verified_at`/
    `failure_reason`; event `initiated`.
  - record already `pending` **same host** → idempotent no-op: same row, **token
    preserved, no event**.
  - record `verified` → idempotent no-op (never silently drops a verified state;
    use re-verify to force a new challenge): **no rotation, no event**.
- **recheck (retry/re-check):** owner/admin; applies only to `pending`/`failed`;
  **token reused (never rotated)**; sets/retains `pending`; sets `last_checked_at`;
  **no DNS resolution** (that is Step 3); exactly one `check_started` event;
  deterministic + repeatable.
- **reverify (manual re-verification):** owner/admin; **rotates the token**; sets
  `pending`; invalidates any prior `verified` state (`verified_at` cleared);
  exactly one `re_verification_requested` event (its `from_status` records the
  invalidation); returns new customer-safe challenge.
- **revoke:** owner/admin; sets `revoked`; **idempotent** (a repeat revoke returns
  the row and appends **no** new event); history preserved (no delete); one
  `revoked` event on the meaningful change.

## 4. Permission matrix (server-enforced)
| Role | initiate | recheck | reverify | revoke | read status |
|---|---|---|---|---|---|
| owner | ✅ | ✅ | ✅ | ✅ | ✅ (RLS) |
| admin | ✅ | ✅ | ✅ | ✅ | ✅ (RLS) |
| team_member | ❌ | ❌ | ❌ | ❌ | ✅ (RLS) |
| client | ❌ | ❌ | ❌ | ❌ | ✅ (RLS) |
| global_admin | **no special override in Step 2A** (override is Step 2B) | | | | ✅ (RLS) |
| anon / non-member | ❌ (denied) | ❌ | ❌ | ❌ | ❌ |

## 5. Security
Cryptographically strong per-record token (never shared across websites/
workspaces/methods/hosts); host validated from the authoritative website row;
malformed/non-http(s) URLs rejected; append-only audit preserved; customers
cannot write the tables directly (writes only via these SECURITY DEFINER RPCs,
which bypass RLS as the definer — same pattern as Stage 6 / Phase 16C); no
secrets stored or logged; **no global-admin override** and **no service-role
path** in this step.

## 6. Locked-scope compliance
No applied migration edited; **no crawler table/RPC/status/worker/UI touched**
(`seo_crawl_request`/`seo_crawl_request_audit`/`seo_crawl_cancel`/`seo_crawl_claim_job`
unchanged and non-regression-verified); no Page-Performance or Stage-6 object
touched; no Step-1 table/policy change; no frontend / `supabaseTypes.ts` change;
no crawl-authorization or P1b enforcement.

## 7. Verification evidence (executed on Digi_SEO_Test, 2026-07-16)
- **Dry-run:** migration run in one transaction with a forced terminal abort →
  full rollback; post-check confirmed the 4 RPCs did not persist.
- **Apply:** `supabase db push --linked` applied `20260716120032`; recorded in
  remote migration history.
- **Structural:** 4 RPCs SECURITY DEFINER + `search_path=public`; `authenticated`
  EXECUTE yes; `anon` no; internal `_seo_ownership_authorize` not
  authenticated-executable.
- **Step 2A SQL verification**
  (`supabase/test/seo_p1a_step2a_ownership_verification_rpcs_verification.sql`):
  **ALL PASS** — 23 checks incl. signatures/SECDEF/grants; owner+admin allowed;
  team/client/non-member/anon denied; cross-workspace denied; initiate create +
  idempotency; recheck token-reuse; reverify token-rotation; revoke + idempotent
  revoke; admin restart-from-revoked rotation; exactly-one-event-per-meaningful-
  change; direct customer table writes denied; customer-safe RLS reads;
  internal-field guard; **crawler RPC non-regression**; other-module isolation;
  self-cleaning.
- **Non-regression:** Step-1 verification **ALL PASS**; Phase 16C crawler
  control-plane verification **ALL PASS**.
- **Frontend:** `tsc --noEmit -p tsconfig.app.json` clean; `npm run build` OK
  (no frontend file changed).

## 8. Rollback
`supabase/test/seo_p1a_step2a_ownership_verification_rpcs_rollback_TEST_ONLY.sql`
drops only the 4 RPCs + 3 helpers; **preserves** the Step-1 tables + audit
history, all crawler objects, Page Performance, Stage 6, and the shared
`set_updated_at()`. TEST only; do not run unless instructed. Production never
touched.

## 9. Next step
**P1a Step 2B — service-role claim/result RPCs and global-admin override** is now
**✅ done + TEST-verified** — see `P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`.
The **exact next task is P1a Step 3 — isolated DNS-TXT worker module.** Steps 4–5
(frontend), Step 6 (sign-off), and **P1b** (verified-only crawl enforcement)
remain excluded and unstarted.
