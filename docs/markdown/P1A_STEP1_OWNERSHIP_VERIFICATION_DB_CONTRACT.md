# P1a Step 1 — Domain Ownership Verification DATABASE CONTRACT (implementation record)

**Status:** `IMPLEMENTED + TEST-VERIFIED (Digi_SEO_Test) — additive; production untouched` (2026-07-16).
**Scope:** the first step of P1a only — the **database foundation** for DNS-TXT
domain ownership verification. **P1a is NOT complete; P1b is entirely excluded.**
This step adds **no** RPCs, **no** DNS/worker logic, **no** frontend, **no**
`supabaseTypes.ts` constant, and **no** crawl-authorization change. It does not
consume, gate, or alter any crawl behaviour.

**Owner docs / context:** approved P1a design + Step-1 implementation plan
(prior planning turns), `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md` (ownership
verification named prerequisite), `MODULE_LOCKS.md` (crawler 16C–16H lock).

---

## 1. What was delivered (additive only)
Migration `supabase/migrations/20260716120031_seo_p1a_step1_ownership_verification.sql`:

- **`seo_ownership_verifications`** — one verification record per website per
  method. Customer-safe columns: `workspace_id`, `website_id`, `website_url`
  (snapshot), `verification_host`, `method` (`dns_txt` only, CHECK), status
  (`pending`/`verified`/`failed`/`revoked`, default `pending`), `challenge_token`
  (customer-safe TXT value), challenge/checked/verified timestamps,
  `failure_reason` (customer-safe), `ownership_source` (`standalone_dns` only —
  forward-compatible provenance seam for a future Digibility signal),
  `created_by`, `created_at`, `updated_at`. **UNIQUE (website_id, method).**
- **`seo_ownership_verification_events`** — APPEND-ONLY audit
  (`initiated`/`challenge_rotated`/`check_started`/`verified`/`failed`/`revoked`/
  `re_verification_requested`/`invalidated`/`admin_override`), with
  from/to status, actor (`customer`/`worker`/`system`/`global_admin`),
  `actor_user_id`, `actor_role_snapshot`, customer-safe `note`.
- **Triggers:** reuses existing `public.set_updated_at()`; a new defense-in-depth
  `seo_ownership_verification_integrity()` (website must belong to its workspace),
  mirroring the Phase 16C `seo_crawl_job_integrity` pattern.
- **RLS (default-deny writes):** workspace-member (or global-admin) **SELECT
  only** on both tables; **no** INSERT/UPDATE/DELETE policy → customers cannot
  write; the audit table is immutable (SELECT-only). Writes will arrive only via
  the future guarded **customer** RPCs (Step 2A) and the **service-role**
  result/claim + global-admin-override RPCs (Step 2B), and the Step 3
  service-role worker — none of which exist in this step.

### Design invariants honoured
DNS-TXT is the only MVP method; scoped to workspace+website+host; **existing
websites remain unverified by default (no rows created; absence == unverified)**;
**no auto-expiry** (no `expired` state — invalidation is event-driven, later
steps); state authoritative in Supabase; audit append-only; internal diagnostics
are not stored on these customer-readable tables (worker diagnostics table is a
later step). No secrets stored.

## 2. Explicitly NOT in this step
Customer RPCs (initiate/retry/revoke/re-verify), service-role claim/result RPCs,
DNS resolution/token comparison, worker code, frontend service/component/hook/
mock, `supabaseTypes.ts` constants, verified-only enqueue enforcement (**P1b**),
and any change to `seo_crawl_request` / `seo_crawl_request_audit` /
`seo_crawl_cancel` / crawl status / crawl UI / Page Performance / Stage 6.

## 3. Locked-scope compliance
No applied migration edited; no crawler table/RPC/status/worker/UI touched; no
Page-Performance or Stage-6 object touched. Only the shared `set_updated_at()`
was **reused** (not modified). This step touches **no** file under the crawler
lock; the isolated worker module (a locked-area additive extension) is a **later
P1a step**, not this one.

## 4. Verification evidence (all executed on Digi_SEO_Test, 2026-07-16)
- **Dry-run:** migration run inside one transaction with a forced terminal
  abort → whole-file rollback; post-check confirmed **0** leaked tables.
- **Apply:** `supabase db push --linked` applied `20260716120031`; recorded in
  remote migration history.
- **Structural:** 2 tables present; RLS enabled on both; exactly **1 SELECT
  policy each** and **0 non-SELECT policies**; `(website_id, method)` unique
  constraint present.
- **SQL verification** (`supabase/test/seo_p1a_step1_ownership_verification_verification.sql`):
  **ALL PASS** — structure/RLS/policy-shape; privileged fixture create; duplicate
  (website_id, method) rejected; workspace/website integrity mismatch rejected;
  FK to non-existent website rejected; unknown status (`expired`) rejected;
  member (owner/client) reads; non-member/cross-workspace denied; authenticated
  direct INSERT/UPDATE/DELETE on both tables denied; audit immutable; teardown
  self-cleaning; crawler/Page-Inventory/Stage-6 counts unchanged. Idempotent +
  self-cleaning (tag `OWNVERIFY-` + disposable website `af000000-…-099`).
- **Frontend:** `tsc --noEmit -p tsconfig.app.json` clean; `npm run build` OK
  (no frontend file changed — regression proof only).

## 5. Rollback
`supabase/test/seo_p1a_step1_ownership_verification_rollback_TEST_ONLY.sql`
(reverse order: triggers + integrity fn → audit table → verifications table).
Drops only Step-1 objects; **does not** drop the shared `set_updated_at()`. TEST
only; do not run unless instructed. DB rollback = these drops; no migration to
un-apply elsewhere; production never touched.

## 6. Approved P1a sequence (Step 1 done; remainder not started)
1. **Step 1 — DB contract** — ✅ done + TEST-verified (this document).
2. **Step 2A — guarded customer RPCs only.** ✅ done + TEST-verified — see `P1A_STEP2A_OWNERSHIP_VERIFICATION_RPCS.md`.
3. **Step 2B — service-role claim/result + global-admin override RPCs.** ✅ done + TEST-verified — see `P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`.
4. **Step 3 — isolated DNS-TXT worker module.** ✅ done + TEST-verified — see `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`.
5. **Step 4 — frontend service, types, hooks and mock.** ✅ done + type/build-verified — see `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md`.
6. **Step 5 — Websites/onboarding UI.** ✅ implemented + mock-browser-verified (authenticated TEST validation pending) — see `P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md`.
7. **Step 6 — full regression and sign-off.** ⬅ next milestone.
8. **P1b — separately approved verified-only crawl enforcement.**

### Exact next task — P1a Step 2A (guarded customer RPCs only)
Guarded `SECURITY DEFINER`, `authenticated`-execute customer RPCs that write the
Step-1 tables (owner/admin gating in-function; append-only audit): **initiate
verification, retry / re-check, re-verification, revoke, and a customer-safe
status read if an RPC is required.**

**Step 2A explicitly EXCLUDES:** the service-role **claim** RPC; the service-role
**result-persistence** RPC; the **global-admin override** RPC (all Step 2B); the
**worker** implementation (Step 3); any **frontend** implementation (Steps 4–5);
any **crawl RPC** change; any **crawl UI** change; and **P1b** verified-only
enqueue enforcement. `seo_crawl_request` / `seo_crawl_request_audit` /
`seo_crawl_cancel` and crawl authorization remain unchanged; production untouched.
