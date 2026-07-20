# P1a Step 4 — Frontend ownership-verification service, types, hooks, mock (record)

**Status:** `IMPLEMENTED + TYPE/BUILD-VERIFIED — additive frontend service layer; no UI; production untouched` (2026-07-16).
**Scope:** Step 4 only — the frontend **service-layer foundation** (types, Supabase
service, public dispatcher, mock adapter, hooks, pure helpers, additive constants).
**No customer-facing UI** (that is Step 5). **P1a is NOT complete.** Step 6 and P1b
excluded. **No DB/migration/RPC/RLS change.**

**Builds on:** `…120031` (Step 1 table), `…120032` (Step 2A customer RPCs).

---

## 1. Files added / edited (frontend only)
**New:**
- `src/types/ownershipVerification.ts` — `OwnershipVerificationView` (customer-safe
  shape) + status/method/source unions + `OwnershipVerificationWriteError`.
- `src/lib/ownershipVerification.ts` — **pure** helpers: `deriveDnsTxtName`,
  `unverifiedOwnershipView`, `mapOwnershipRow` (safe row→view mapping),
  `ownershipVerificationQueryKey`.
- `src/services/supabase/seoOwnershipVerificationSupabaseService.ts` — RLS read of
  the Step 1 table + Step 2A RPC writes.
- `src/services/ownershipVerificationService.ts` — public dispatcher (standard
  adapter read + non-masking write helper).
- `src/mocks/ownershipVerificationMockData.ts` — deterministic per-website mock.
- `src/hooks/useOwnershipVerification.ts` — status query + 4 mutation hooks.

**Additive edit:**
- `src/services/supabase/supabaseTypes.ts` — `SEO_TABLES.ownershipVerifications`
  (customer-safe table only) + `SEO_RPCS.ownershipVerification{Initiate,Recheck,
  Reverify,Revoke}` (the 4 Step 2A RPCs only). The internal claims/events tables
  and the Step 2B service-role / global-admin RPCs are **deliberately not** added.

**No UI component created.** No crawl/worker/DB file touched.

## 2. Frontend data contract (customer-safe)
Derived only from Step 1 fields: verification id, workspace id, website id,
verified host, method, status, `dnsTxtName` (**derived** `_digibility-site-
verification.<host>`), `dnsTxtValue` (challenge token), customer-safe failure
reason, requested/last-checked/verified timestamps, `revokedAt`, ownership
source, created/updated. **Absence of a DB row → explicit `unverified`.** The
`OwnershipSource` union is widenable for a FUTURE trusted source. **Never
exposed:** internal claim rows, lease tokens, worker ids, internal diagnostics,
correlation ids, service-role metadata.
- **Honest mapping note:** Step 1 has **no** `revoked_at` column, so `revokedAt`
  is **derived** (`updated_at` while `status = 'revoked'`; null otherwise).

## 3. Read / write behaviour
- **Read** (`fetchOwnershipVerification`): standard `runWithServiceAdapter`;
  Supabase impl requires an authenticated user (defense-in-depth; RLS
  authoritative), validates the website UUID, selects **only** customer-safe
  columns of `seo_ownership_verifications` scoped by `website_id` + `method`,
  returns one view or `unverified`, never queries claims/events, never uses a
  service-role credential, never falls back to another website, maps malformed
  rows safely, normalizes errors.
- **Writes** (`initiate`/`recheck`/`reverify`/`revoke`): via the **Step 2A RPCs
  only** (send **only** `p_website_id`; workspace/role/host/status/source resolved
  server-side), mapped into the view. A REAL RPC rejection throws
  `OwnershipVerificationWriteError` and is **never masked** by mock success; only
  pre-RPC failures (no session/config) fall back to the mock preview — the same
  non-masking rule as Phase 13D/13E/15C/16H writes. No direct table write. No
  global-admin override exposed.

## 4. Mock adapter (deterministic preview)
Per-website in-memory state (isolated by website id); no Supabase, no timers, no
DNS. Supports unverified/pending/verified/failed/revoked; initiate creates/
restarts pending (idempotent for pending/verified), recheck reuses the challenge,
reverify rotates it, revoke is idempotent. Does not affect other mocks/services.
Permanent mock mode preserved.

## 5. Hooks & query keys
`useOwnershipVerificationStatus` (read; **no polling**) + `useInitiate/Recheck/
Reverify/Revoke` mutations. Query key `["seo-ownership-verification", websiteId,
userId]` — **user + website scoped** (SessionSync / sign-out cache clearing
compatible; no crawl-query-key collision). Mutation success updates + invalidates
**only** that key. No DNS retry loop, no worker-status polling. Errors remain
visible to the future UI. No role-selection/simulation path; RLS + RPCs remain
authoritative (frontend gating belongs to Step 5).

## 6. Verification evidence (executed 2026-07-16)
| Command | Result |
|---|---|
| Root `tsc --noEmit -p tsconfig.app.json` | **PASS** (clean) |
| Root `npm run build` | **PASS** |
| Frontend test/lint | **N/A** — repo has no frontend test/lint script (none added; logic isolated in the pure `src/lib/ownershipVerification.ts` — stated limitation) |
| Static security sweep | **PASS** — no service-role key; no claims/events/lease/worker/diagnostic field; no direct table write; only the 4 Step 2A RPCs referenced; only the `seo-ownership-verification` query key (no crawl collision); no crawl/worker file edited |
| Step 2A / 2B / 1 SQL verification | **ALL PASS** (non-regression; self-cleaning) |
| Standalone Phase 16C/16D/16E/16F/16G/16H | **ALL PASS** (non-regression) |
| Worker suite | **74/74 pass, 0 fail** (non-regression) |

**Known limitation:** no automated frontend unit test (repo has no framework; a
framework was intentionally not introduced). Mapping/query-key logic is isolated
into pure, review-verifiable helpers. No UI exists, so no browser validation was
required.

## 7. Rollback (code-only)
Delete the 6 new frontend files and revert the additive `supabaseTypes.ts`
constants. No database rollback (no DB change). Step 1/2A/2B DB objects and the
Step 3 worker module remain; all existing frontend behaviour preserved.

## 8. Next step
**P1a Step 5 — Websites/onboarding ownership-verification UI** is now **✅
implemented + mock-browser-verified** (consumes these hooks/service; owner/admin
actions + read-only for others) — authenticated TEST validation pending; see
`P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md`. The next milestone is **Step 6 — full
regression, operator acceptance, and P1a sign-off.** P1b remains excluded.
