# P1b — Verified-only Crawl Enqueue Enforcement — SIGN-OFF

**Verdict: `P1b COMPLETE — TEST-APPLIED, VERIFIED, and MODULE-LOCKED` (2026-07-19, `Digi_SEO_Test` ref `snyzotgwwfomgafrsvfm`).**
The verified-only crawl enqueue precondition is implemented as an additive
extension to the locked crawler enqueue contract, applied to **TEST only**, and
passed every acceptance and regression check including a live two-session
concurrency proof. **P1a remains LOCKED and untouched. Production untouched.**
A formal P1b lock entry has been added to `MODULE_LOCKS.md`.

---

## 1. Implemented scope
A new precondition inside `public.seo_crawl_request`: a crawl job may be created
only when the website's domain ownership is **currently `verified`**
(`public.seo_ownership_verifications`, `method='dns_txt'`, `status='verified'`).
The guard is placed after authentication / module-access / workspace resolution /
role authorization and before eligibility/config validation and the INSERT, uses
`FOR SHARE` for write-time atomicity, and raises a plain `P0001`
`RAISE EXCEPTION 'Domain ownership must be verified before this website can be crawled.'`.

## 2. Migration
- **Applied (TEST only):** `supabase/migrations/20260719120034_seo_p1b_verified_only_crawl_enqueue.sql`
  — `CREATE OR REPLACE FUNCTION public.seo_crawl_request(...)`; recorded once in
  `supabase_migrations.schema_migrations` (version `20260719120034`).
- The applied Phase 16C migration `20260713120025` was **not** edited.
- **Rollback (TEST only, unused):** `supabase/test/seo_p1b_verified_only_crawl_enqueue_rollback_TEST_ONLY.sql`
  restores the exact pre-P1b body (verified byte-identical to the 16C original).

## 3. Deployed RPC contract verification (post-apply, on TEST)
| Property | Result |
|---|---|
| Identity args | `p_website_id uuid, p_idempotency_key text, p_config jsonb` — unchanged |
| Return type | `uuid` — unchanged |
| SECURITY DEFINER | true — unchanged |
| `search_path` | `search_path=public` — unchanged |
| Grants | `authenticated` = EXECUTE; `anon` = denied — unchanged |
| Ownership guard present | yes (`seo_ownership_verifications`, `dns_txt`, `verified`) |
| `FOR SHARE` present | yes |
| Exact message | `Domain ownership must be verified before this website can be crawled.` |
| Custom SQLSTATE | none (default `P0001`) |
| `seo_crawl_request_audit` | unchanged (still calls `seo_crawl_request`; no guard in its own body; return shape `TABLE(audit_run_id, crawl_job_id, job_status)`) |

## 4. P1b acceptance verification — ALL PASS
`supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql` →
`ALL PASS — seo_p1b verified-only crawl enqueue enforcement verification complete`.
Covered: verified direct + audit enqueue succeed (job + audit run linked);
pending / failed / revoked / missing-row blocked with the ownership message;
rejected audit path creates **no orphan audit run**; authorization/authentication
precedence (anonymous → auth error; client / non-member / cross-workspace → role
error) with **no ownership-state leak**; direct RPC and audit RPC cannot bypass;
idempotency, single-active-job, and one-queued-event behaviour unchanged; static
`FOR SHARE` + guard presence; self-cleaning teardown (0 residual).

## 5. Phase 16C–16H regression — ALL PASS
| Script | Result |
|---|---|
| `seo_phase16c_crawl_control_plane_verification.sql` | **ALL PASS** |
| `seo_phase16d_worker_lifecycle_verification.sql` | **ALL PASS** |
| `seo_phase16e_crawl_discovery_verification.sql` | **ALL PASS** |
| `seo_phase16f_crawl_extraction_verification.sql` | **ALL PASS** |
| `seo_phase16g_publishing_verification.sql` | **ALL PASS** |
| `seo_phase16h_crawl_audit_finalization_verification.sql` | **ALL PASS** |

Intended-reason preservation (guaranteed by guard ordering — after role check,
before eligibility — plus the added verified fixtures): 16C inactive-site test
fails on **inactivity** (its site is verified); 16C config-validation tests fail on
**config** (run on the verified main site); 16G cross-workspace test fails on
**authorization** (the role check precedes the ownership guard, and `g.wother` is
left unverified). Valid enqueue / lifecycle / publishing / finalization paths
unchanged. All fixtures self-cleaned.

## 6. Worker regression — PASS
`cd crawler-worker && npm test` → **74 pass, 0 fail, 0 skipped**. The worker
source was not modified (git-confirmed); it still only claims existing jobs via
`seo_crawl_claim_job` (it never enqueues), so valid jobs remain claimable/
processable.

## 7. Concurrency (FOR SHARE) — PASS (live two-session, on TEST)
Two concurrent `supabase db query` sessions (the runner holds one transaction per
file — `txid_current()=txid_current()` → true — so `FOR SHARE` locks persist while
a session sleeps). Full procedure + evidence in `P1B_CONCURRENCY_VERIFICATION_GUIDE.md`.
- **Revoke wins:** enqueue **blocked ~6.3 s**, then **rejected** with `P0001`
  `Domain ownership must be verified before this website can be crawled.`; **0 jobs**
  created; ownership `revoked`.
- **Enqueue wins:** revoke **blocked ~6.1 s** until the enqueue committed; **1 job**
  created while verified; revoke applied afterward.

## 8. Cleanup & safety
- No P1b verification fixtures remain (P1b websites = 0; P1b ownership tokens = 0).
- No orphan audit runs from verification (= 0).
- No unexpected queued/running crawl jobs from verification.
- Migration history contains `20260719120034` **exactly once**.
- Production project never contacted (only the linked TEST project).
- No service-role value, verification token, or challenge value was printed.

## 9. Lock status
**P1b is now MODULE-LOCKED (2026-07-19)** — a formal `P1b — Verified-only Crawl
Enqueue Enforcement` entry is in `MODULE_LOCKS.md`. Future changes to the P1b guard
require that lock's additive-extension + evidence procedure and explicit approval.
The Crawler 16C–16H lock and the P1a lock remain fully in force and unchanged.

## 10. Production / remaining work
Production **untouched**; P1b is applied to `Digi_SEO_Test` only. Optional UI
defense-in-depth (disable Start-crawl + explain when unverified; surface the RPC
message) remains a **separately-approved follow-up** that touches locked crawl-UI
files — it is **not** required for the server-side enforcement, which is complete.

## Verdict
**`P1b COMPLETE — TEST-APPLIED, VERIFIED, MODULE-LOCKED`.** Rollback was **not**
used. No unresolved FAIL. P1a untouched; production untouched.
