# P1a — Domain Ownership Verification — SIGN-OFF

**Verdict: `P1A COMPLETE — MODULE-LOCKED` (updated 2026-07-19, `Digi_SEO_Test` ref `snyzotgwwfomgafrsvfm`).**
All automated P1a + locked-scope regressions PASS; the full capability is
implemented and DB/worker/frontend-verified. **The authenticated browser role
matrix is COMPLETE — PASS** (owner/admin/team_member/client + sign-out/session
isolation; see §3 and §10 2026-07-18 entry). **The real DNS `verify-once` worker-binary
run is now COMPLETE — PASS** (see §4 and §10 2026-07-19 entry) — this was the last
outstanding acceptance item. **No defect or blocker was found.** Production
untouched. **A formal P1a lock entry now exists in `MODULE_LOCKS.md`.** **P1b —
verified-only crawl enqueue enforcement — is the next implementation stage (not
started).**

---

## 1. Implemented scope
End-to-end DNS-TXT domain ownership verification for a customer-owned website,
across five layers, all applied to **TEST only**:
- **Step 1 (`…120031`):** `seo_ownership_verifications` + append-only
  `seo_ownership_verification_events`; default-deny-write RLS; member-read; absence→unverified.
- **Step 2A (`…120032`):** guarded **customer** RPCs `initiate`/`recheck`/`reverify`/`revoke`
  (SECURITY DEFINER, `authenticated`-only, owner/admin server-gated).
- **Step 2B (`…120033`):** internal claim/lease ledger (global-admin-read-only) +
  **service-role** `claim`/`record_result` + **global-admin** `admin_override`.
- **Step 3 (worker, code-only):** isolated `verify-once` DNS-TXT runner under
  `crawler-worker/src/verification/**` (claims → resolves → exact-match → verified/failed),
  independent of the crawl processor.
- **Step 4 (frontend service):** types, RLS-read + Step-2A-RPC-write Supabase service,
  non-masking dispatcher, deterministic mock, hooks.
- **Step 5 (UI):** `OwnershipVerificationPanel` in `WebsiteCard` (status, DNS-TXT
  instructions + copy, owner/admin actions, read-only for others, accessible tooltips).

## 2. Explicit exclusions
- **P1b — verified-only crawl enqueue enforcement — NOT implemented** (the crawl
  enqueue RPCs `seo_crawl_request`/`seo_crawl_request_audit` do **not** check
  ownership; confirmed by inspection). No crawl authorization change.
- No crawl RPC/status/worker-lifecycle/`StartCrawlControl`/`CrawlPanel`/Page-Performance/Stage-6 change.
- No production deployment; no scheduler; no usage/subscription enforcement.
- The whole SEO module is **not** production-ready.

## 3. Authenticated role matrix
- **Backend authorization matrix — PROVEN (SQL, executed on TEST):** the Step 2A and
  Step 2B verification scripts exercise **owner / admin / team_member / client /
  non-member / global-admin** via jwt-claim switching and assert: owner+admin may
  initiate/recheck/reverify/revoke; team_member/client/non-member/anon denied
  (write RPCs raise); cross-workspace denied; global-admin override
  mark_verified/invalidate (reason required) with audit actor recorded; ordinary
  roles cannot override; customer direct table writes denied; internal claim/lease
  data not customer-readable. **ALL PASS.**
- **Authenticated UI (browser) operator matrix — COMPLETE — PASS (2026-07-18, `Digi_SEO_Test`).**
  Operator-executed logged-in click-through of the Step 5 UI against the real Supabase-mode
  app for **owner, admin, team_member, and client**, each followed by sign-out:
  - **Owner:** authenticated successfully; on `/seo/websites` saw `digibility.ai` with
    ownership controls enabled; **Verify ownership** issued exactly one
    `seo_ownership_verification_initiate` request, HTTP 200; UI changed to **Verification
    pending** and remained pending after a hard refresh (state read live from Supabase, not
    cached); sign-out redirected to `/seo/login` and removed all protected content.
  - **Admin:** authenticated successfully; saw the persisted **pending** status with
    **Check again / Re-verify / Revoke** enabled; **Check again** issued exactly one
    `seo_ownership_verification_recheck` request, HTTP 200; status remained **pending**;
    sign-out removed protected content.
  - **team_member:** authenticated successfully; saw **pending** status, **no** ownership
    action buttons, and the read-only "Requires the owner or admin role." message; Network
    evidence confirmed **no** initiate/recheck/reverify/revoke request fired; sign-out
    removed protected content.
  - **client:** authenticated successfully; identical read-only affordance to team_member
    (pending status, no action buttons, read-only message); Network evidence confirmed
    **no** write RPC fired; sign-out removed protected content.
  - **Cross-role/session isolation:** status was read live from Supabase across every role
    switch (no stale/cached cross-user state observed); protected routes were inaccessible
    after every sign-out.
  - **No defect found; no source/migration/SQL/worker/frontend/config file was changed**
    during this browser acceptance. DNS challenge values from any screenshot evidence are
    intentionally not reproduced in this record. Non-member click-through was not exercised
    (not required by the accepted evidence); the backend matrix above already proves
    non-member/anon denial at the RPC layer. Mock-mode UI was separately validated (§Mock).

## 4. Worker integration result
- **PROVEN (executed):** Step 3 TEST integration SQL
  (`seo_p1a_step3_worker_dns_verification_integration.sql`) — the worker's exact
  claim→result→audit flow via the **real Step 2B RPCs** with a deterministic
  simulated resolver: pending claimed; **exact match → verified**; **not-found →
  failed** (customer-safe reason); challenge token unchanged; audit events correct;
  internal diagnostics on the admin-only claim row (not customer-readable); **0**
  crawl/audit/Page-Inventory/Page-Performance/recommendation/Stage-6 rows changed;
  self-cleaning (0 residual). Node worker suite **74/74** (incl. exact-match,
  multi-record/multi-string flatten, NXDOMAIN/timeout/temporary/internal → customer-safe
  failed, no-work exit, stale-claim safe stop, no-crawl-processor-import, raw
  challenge/TXT never logged, graceful shutdown).
- **PROVEN (executed) — real worker binary, COMPLETE — PASS (2026-07-19, `Digi_SEO_Test`).**
  Operator ran `npm start -- --mode=verify-once` from `crawler-worker/` after exporting
  `crawler-worker/.env` into the shell; the worker started with `environment=test`,
  `mode=verify-once`, and logged `serviceRoleKey` **only as `[REDACTED]`**. It claimed the
  only eligible verification (`id=41d2a3e8-3c7e-4b55-a282-6682a8349b69`,
  `website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`, host `digibility.ai`), performed a
  **real Node DNS TXT lookup** (not the fixture resolver) against
  `_digibility-site-verification.digibility.ai` → no record found, and persisted the
  result via the real `seo_ownership_verification_record_result` RPC: `status=failed`,
  reason code `dns_not_found`, `last_checked_at=updated_at=2026-07-19
  05:18:27.369182+00`; exactly one new `seo_ownership_verification_events` row
  (`event_type=failed`, `from_status=pending`, `to_status=failed`, `actor=worker`,
  `note="Ownership verification failed"`, `created_at=2026-07-19 05:18:27.369182+00`).
  The worker emitted a `verify_once` completion log line and **exited code 0**. **No
  challenge value, lease token, or service-role key was ever exposed.** The legitimate
  DNS business outcome was a customer-safe `failed`/`dns_not_found` — **not a defect**;
  the acceptance proves the trusted end-to-end worker-binary path (real service-role
  client → real claim RPC → real DNS resolution → real result RPC, none simulated),
  which is independent of whether the DNS business result is `verified` or a legitimate
  `failed`. No source/migration/SQL/worker/config/crawl-contract/production file
  changed during this run. (The worker↔RPC wiring was separately proven by the Node
  integration test with a fake Supabase client; the RPC↔DB behaviour by the integration
  SQL; this run proves the real binary end-to-end.)

## 5. Database & security evidence
- **DB:** 33 migrations `…120001`–`…120033` on TEST; ownership tables/RPCs/claim
  ledger verified (Steps 1/2A/2B ALL PASS). No P1b/crawl/Page-Performance/Stage-6
  schema change.
- **Security (inspection + execution):** service-role key only in the worker runtime
  (`crawler-worker/src/config.ts`); **none in frontend/logs**; worker never logs the
  raw challenge/lease token (tests #9/#10); claims/lease/internal diagnostics are
  global-admin-read-only (customers denied); customer table writes denied; worker
  writes results only via the service-role RPC; cross-workspace denied; global-admin
  override isolated (not in the customer UI); **no crawl authorization change; no P1b
  behaviour present.**

## 6. Regression results (all actually executed on TEST unless noted)
| Suite | Result |
|---|---|
| P1a Step 1 / 2A / 2B SQL verification | **ALL PASS** (idempotent, self-cleaning, 0 residual) |
| P1a Step 3 worker DNS integration SQL | **ALL PASS** (self-cleaning) |
| Worker `tsc` + full suite | **PASS — 74/74, 0 fail** |
| Root `tsc` + `npm run build` | **PASS** |
| Static security sweep | **PASS** (9/9 criteria) |
| Locked crawler 16C/16D/16E/16F/16G/16H | **ALL PASS** |
| Crawl RPC grants/signatures + status constraints | **unchanged** (verified) |
| Crawler frontend/worker/`StartCrawlControl`/`CrawlPanel`/Page-Perf files | **unchanged** (verified) |
| Stage 6 smoke / campaign-create / campaign-transition | **PASS / ALL PASS / ALL PASS** |
| Page Performance (Stage 4) smoke | **EVIDENCE LIMITATION** — see §Known limitations |

## 7. Known limitations
- **Stage 2/3/4/5 smoke tests are not faithfully executable via the available
  `supabase db query --linked -f` runner:** they use explicit
  `BEGIN;`/`COMMIT;`/`ROLLBACK;` transaction control (psql-style), which the
  auto-wrapping runner scrambles. The Stage-4 "duplicate snapshot allowed" result
  is a **transaction-nesting artifact**, not a defect — the uniqueness contract is
  intact (unique index `uq_seo_page_perf_snap_combo` present; Page-Performance files
  unchanged; no migration since Stage 4). A psql-style runner (operator env) is
  needed to execute these smokes cleanly.
- **None remaining.** The **real worker binary** run (previously listed here as
  a limitation) is now **COMPLETE — PASS** (2026-07-19; see §4 and §10). The
  authenticated **browser** role matrix, also previously listed here, is
  **COMPLETE — PASS** (2026-07-18; see §3 and §10).
- `revokedAt` is a derived approximate value (Step 1 has no `revoked_at` column);
  deliberately not displayed in the UI.
- No frontend unit-test framework (mock-browser + operator validation + pure
  helpers used instead).

## 8. Mock-mode UI validation (executed, in-session)
`/seo/websites` in `VITE_SEO_DATA_MODE=mock`: panel renders per website with a
**Preview** label + honest "no real domain is verified" note; initiate → pending
with exact DNS TXT Host/Value + copy; **recheck reused** the challenge, **reverify
rotated** it, **revoke → revoked → "Verify ownership"**; **no console errors; no
Supabase request** (all network Vite/localhost). Existing website mocks unchanged.

## 9. Production / lock status
Production **untouched**. **P1a is now MODULE-LOCKED (2026-07-19).** All operator-acceptance
items have passed: the §3 authenticated browser role matrix (2026-07-18) and the §4 real
`verify-once` worker binary run (2026-07-19). A formal P1a lock entry (locked scope,
protected contracts, locked files, and the unlock/additive-extension procedure) has been
added to `MODULE_LOCKS.md`. Future changes to any P1a file require that entry's evidence
bar and explicit human approval.

## 10. Acceptance-attempt log
- **2026-07-16 — operator-acceptance run attempted; verdict unchanged.** Fresh
  environment probe confirmed the three acceptance prerequisites are **absent**
  here, so none of the three operator items could be executed (earlier automated/
  SQL evidence is **not** substituted to call them complete):
  1. **Authenticated browser role matrix (owner/admin/team_member/client/
     non-member + session isolation) — NOT RUN.** Missing prerequisite: **no
     TEST-user credentials/authenticated session** available, and the app is
     auth-gated (Supabase mode). Command prerequisite for a future run: real
     TEST-user logins for each role in a browser against the running app.
  2. **Real DNS `verify-once` worker binary against `Digi_SEO_Test` — NOT RUN.**
     Missing prerequisite: **`SUPABASE_SERVICE_ROLE_KEY` is not set** and no real
     `crawler-worker/.env` exists (only the blank `.env.example`), so the
     service-role client cannot be constructed. Command prerequisite for a future
     run: provide the service-role key in the worker env, then
     `cd crawler-worker && CRAWLER_ENV=test CRAWLER_VERIFICATION_FIXTURE_DNS=<fixture.json> npm start -- --mode=verify-once`
     against a disposable tagged pending verification (key never printed).
  3. **Legacy Stage 2–5 smoke tests via a psql-compatible runner — NOT RUN.**
     Missing prerequisite: **`psql` not found** and no `SUPABASE_DB_URL`; the
     scripts use explicit `BEGIN/COMMIT/ROLLBACK` and cannot run through the
     auto-wrapping `supabase db query -f` runner. This is a tooling limitation,
     not a defect; the protected Page-Performance/Stage-2/3/5 contracts are
     otherwise verified (unique index present, files unchanged, no migration
     since those stages).
- **Automated regression re-run (2026-07-16) — ALL PASS:** P1a Step 1/2A/2B +
  Step 3 integration; locked crawler 16C–16H; Stage 6 smoke + campaign-create +
  campaign-transition; worker `tsc` + suite **74/74**; root `tsc` + `build`;
  security sweep. **No defect.** No implementation/DB/production change.

- **2026-07-16 — operator-results recording attempt; no evidence supplied; verdict
  unchanged.** A "record the operator-acceptance results" submission was received,
  but it was the **unfilled runbook template** — every field still held the literal
  `[PASS / FAIL / NOT RUN]` options and the evidence sections still held the
  `[PASTE …]` instruction text. **No completed browser role-matrix, session/cache
  isolation, real `verify-once` worker binary, legacy-smoke, or automated-re-run
  results were provided.** No scenario is therefore marked accepted; no lock added;
  no code/DB/production change. Acceptance still requires an actual operator run
  with populated evidence (see the runbook / §3–§4 pending items).

- **2026-07-16 — operator acceptance Step 2.8 defect found + fixed (UI-only); verdict
  unchanged.** Authenticated owner acceptance (Steps 2.1–2.7 PASS) reached Step 2.8,
  where rapid clicks on "Check again" issued multiple
  `seo_ownership_verification_recheck` RPCs (async `disabled`-only guard). Approved
  one-file fix landed in `OwnershipVerificationPanel.tsx` (synchronous `useRef`
  submission latch); verified via `tsc`/`build` + a mock-browser rapid-burst proof
  (one mutation per burst) + security sweep; non-regression Step 1 / 16C–16H /
  Stage 6 / worker 74/74 / root tsc+build ALL PASS. **Step 2B + Step 3 SQL failed
  this run only due to operator-created leftover `pending` verifications on TEST
  (`digibility.ai`, `stage5-smoke-test.example`) being claimed first by the
  globally-oldest-first claim RPC** — a test-isolation artifact of the operator's
  own run, not a regression and not a product defect; they pass on a clean pending
  state. **Operator Step 2.8 authenticated re-test remains PENDING.** No lock added.
  See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md`.

- **2026-07-17 — Step 2.8 fix hardened (leading-edge throttle); verdict unchanged.**
  The first synchronous latch was concurrency-only and still allowed multiple
  sequential recheck RPCs on a real spaced burst against a fast backend. Approved
  one-file fix in `OwnershipVerificationPanel.tsx`: a leading-edge per-action throttle
  (1000 ms) + the retained in-flight latch. Verified via `tsc`/`build` + a mock
  spaced-click proof (5 clicks 120 ms apart → one mutation; deliberate click after
  the window works) + fix-unaffected non-regression (Step 1/2A/16C–16H/Stage 6/worker
  74/74/root tsc+build ALL PASS). **Authenticated operator Step 2.8 re-test PENDING**
  (real session required). **Step 2B/Step 3 SQL DEFERRED** until the two operator-
  created leftover pending verifications on TEST are cleared via customer revoke (no
  direct delete). No lock added. See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §8.

- **2026-07-17 — Step 2.8 double-submit RESOLVED + authenticated acceptance PASS.**
  The leading-edge throttle was retired after temporary `[OVP]` diagnostics proved it
  ran correctly on a single persistent instance; the operator's multi-second burst had
  inter-click gaps > cooldown, so each later click was a legitimate new action. This
  invalidated the **acceptance criterion** ("one RPC across an arbitrarily long burst"),
  which is unsound — the earlier long-burst runs are reclassified as **invalid tests
  against a retired criterion, not failures/defects.** Final approved one-file guard in
  `OwnershipVerificationPanel.tsx`: a per-action **visible bounded post-action lock**
  (`idle → in_flight → cooldown → idle`; synchronous `phaseRef` authoritative +
  `lockedActions` state driving `disabled`; first click immediate; disabled through
  mutation + refetch + a fixed 3000 ms cooldown; no keep-alive/throttle/debounce/countdown).
  Verified: root `tsc`/`build` clean; one-file scope; all `[OVP]` removed (grep = none);
  mock quantitative proof (recheck counted directly via `lastCheckedAt`, not token
  rotation — 8 rapid clicks → exactly 1; +1 deliberate after cooldown); no console
  errors; zero Supabase calls in mock. **Authenticated operator Step 2.8 = PASS:**
  **AT-1** rapid double/triple click → exactly 1 recheck POST (200); **AT-2** button
  disabled ≈ 3.5 s then re-enables; **AT-3** deliberate click after re-enable → exactly
  1 new recheck POST (200); **AT-4** no overlapping duplicates. UI stayed
  `Verification pending`. No service/hook/RPC/DB/RLS/worker/config/production change; no
  lock added yet (remaining §3 browser role matrix + §4 worker binary still pending).
  See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §9.

- **2026-07-17 — A3 DB integrity proof + pending-record cleanup COMPLETE (DB-confirmed on TEST; no code/DB-schema change).**
  - **A3 proof:** `select status, count(*) over () as row_count, last_checked_at, updated_at from public.seo_ownership_verifications where website_id='fb98d59c-0f7d-4724-9f60-9db385bf2592' and method='dns_txt'` → **one row**, `row_count=1`, `status=pending`, `last_checked_at=updated_at=2026-07-17 16:25:18.663042+00`. Confirms the double-submit testing produced **no duplicate ownership rows** for `digibility.ai`.
  - **Cleanup (via authenticated customer revoke UI — not direct delete; append-only audit preserved):** `digibility.ai` (`fb98d59c-…`) → `status=revoked`, `updated_at=2026-07-17 16:33:13.804585+00`; Stage-5 smoke fixture `stage5-smoke-test.example` (`website_id=77777777-0000-0000-0000-0000000000b1`, source `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql`; was `pending`, `has_open_claim=false`) → `status=revoked`, `updated_at=2026-07-17 16:43:24.935897+00`.
  - **Effect:** the earlier "Step 2B/Step 3 SQL DEFERRED until the two leftover pending verifications are cleared" note is **RESOLVED** — TEST has a clean pending state. The Step 2B + Step 3 SQL regressions are **UNBLOCKED but NOT yet re-executed** (follow-up; not claimed PASS). Production untouched; no lock added; the two operator items in §3/§4 are still outstanding.

- **2026-07-18 — P1a Step 2B + Step 3 SQL regressions RE-RUN on the clean TEST pending state — RESULT: ALL PASS.** A read-only eligibility diagnostic (`select id, website_id, status from seo_ownership_verifications where status in ('pending','failed')`) confirmed **0** eligible rows on `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`) before execution — no leftover-claim risk. `supabase/test/seo_p1a_step2b_ownership_verification_service_rpcs_verification.sql` returned its sentinel **`ALL PASS — seo_p1a_step2b service-role + global-admin ownership-verification verification complete`**; `supabase/test/seo_p1a_step3_worker_dns_verification_integration.sql` returned **`ALL PASS — seo_p1a_step3 worker DNS-verification TEST integration complete`**. Both scripts' own teardown + locked-crawler/Page-Inventory/Stage-6 isolation-count assertions passed as a precondition of returning the sentinel row (a failed assertion raises an exception and suppresses it); both are single-transaction, self-cleaning, and net-nothing committed on success. **This resolves the preceding entry's "Step 2B + Step 3 SQL regressions UNBLOCKED but NOT yet re-executed" note** — the follow-up is now closed. No source/migration/SQL/worker/frontend/config file was changed; no production access. This repository copy has no `.git` directory in this execution environment, so no git-status/commit evidence is available — recorded as a known environment limitation, not a repository-state change. **Verdict unchanged: `P1A IMPLEMENTED — OPERATOR ACCEPTANCE PENDING`; P1a remains NOT module-locked.** The two remaining operator items are unchanged: §3 authenticated browser role matrix; §4 real `verify-once` worker binary run.

- **2026-07-18 — P1a authenticated browser role matrix COMPLETE — PASS (`Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm`).** Operator-executed logged-in click-through of the Step 5 UI (`OwnershipVerificationPanel`) against the real Supabase-mode app for **owner, admin, team_member, and client**, each followed by sign-out:
  - **Owner:** signed in successfully; on `/seo/websites` saw `digibility.ai` with ownership controls enabled; clicking **Verify ownership** issued exactly one `seo_ownership_verification_initiate` request (HTTP 200); UI updated to **Verification pending** and remained pending after a hard refresh (state read live from Supabase, not cached); sign-out redirected to `/seo/login` and removed all protected content.
  - **Admin:** signed in successfully; saw the persisted **pending** status with **Check again**, **Re-verify**, and **Revoke** enabled; clicking **Check again** issued exactly one `seo_ownership_verification_recheck` request (HTTP 200); status remained **pending**; sign-out removed protected content.
  - **team_member:** signed in successfully; saw **pending** status, **no** ownership action buttons, and the read-only "Requires the owner or admin role." message; Network evidence confirmed **no** initiate/recheck/reverify/revoke request fired; sign-out removed protected content.
  - **client:** signed in successfully; identical read-only affordance to team_member (pending status, no action buttons, read-only message); Network evidence confirmed **no** write RPC fired; sign-out removed protected content.
  - **Cross-role state + session isolation:** status was read live from Supabase across every role switch (no stale/cached cross-user state observed); protected routes were inaccessible after every sign-out.
  - **No defect found. No source/migration/SQL/worker/frontend/config file was changed during this browser acceptance.** DNS challenge values from any screenshot evidence are intentionally not reproduced in this record. Non-member click-through was not exercised (not part of the accepted evidence); the SQL-proven backend matrix (§3) already covers non-member/anon denial at the RPC layer.
  - **Effect:** the §3 "Authenticated UI (browser) operator matrix — PENDING" item is **RESOLVED — PASS**. The role matrix is no longer an open P1a acceptance blocker. **Verdict unchanged: `P1A IMPLEMENTED — OPERATOR ACCEPTANCE PENDING`; P1a remains NOT module-locked.** The **sole remaining operator item** is §4: the real `verify-once` worker binary run against `Digi_SEO_Test` (needs `SUPABASE_SERVICE_ROLE_KEY`).

- **2026-07-19 — Real `verify-once` worker-binary run COMPLETE — PASS. P1a ACCEPTANCE COMPLETE; P1a is now MODULE-LOCKED.** Operator ran `npm start -- --mode=verify-once` from `crawler-worker/` against `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`), with `crawler-worker/.env` exported into the shell. The worker started with `environment=test`, `mode=verify-once`; the startup log's `serviceRoleKey` field appeared **only as `[REDACTED]`** (never printed in full). It claimed the single eligible verification (`id=41d2a3e8-3c7e-4b55-a282-6682a8349b69`, `website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`, host `digibility.ai`), performed a **real Node DNS TXT lookup** (not the fixture resolver — `CRAWLER_VERIFICATION_FIXTURE_DNS` was not set) against `_digibility-site-verification.digibility.ai`, found no matching record, and persisted the result via the real `seo_ownership_verification_record_result` RPC: `status=failed`, failure reason code `dns_not_found`, `last_checked_at=updated_at=2026-07-19 05:18:27.369182+00`. Exactly one new `seo_ownership_verification_events` row was written: `event_type=failed`, `from_status=pending`, `to_status=failed`, `actor=worker`, `note="Ownership verification failed"`, `created_at=2026-07-19 05:18:27.369182+00`. The worker logged a `verify_once` completion line (outcome=`failed`, matching `verificationId`) and **exited code 0**. **At no point was the challenge value, lease token, or service-role key exposed** (console, logs, or otherwise). **The legitimate DNS business outcome — `failed`/`dns_not_found`, because no TXT record is currently present at that host — is not a defect.** Per the accepted acceptance criterion, the worker-binary proof is the **trusted end-to-end path** (a real service-role Supabase client constructing successfully, a real `seo_ownership_verification_claim` RPC call, real Node DNS resolution, and a real `seo_ownership_verification_record_result` RPC call — none simulated, unlike all prior automated evidence which used either a fake Supabase client or a `postgres`-superuser SQL simulation), independent of whether the DNS business result is `verified` or a legitimate customer-safe `failed`. **No source, migration, SQL, worker, config, crawl-contract, or production file was changed during this run.**
  - **Effect:** the §4 "real worker binary — PENDING" item is **RESOLVED — PASS**. This was the **last outstanding P1a operator-acceptance item.** All three acceptance items are now PASS: backend authorization matrix (SQL, §3), authenticated browser role matrix (§3, 2026-07-18), and the real worker-binary run (§4, 2026-07-19). **P1a Domain Ownership Verification is COMPLETE.** A formal implemented-scope lock has been added to `MODULE_LOCKS.md` — **P1a is now MODULE-LOCKED.** **P1b — verified-only crawl enqueue enforcement — is the next implementation stage** (separately approved, additive to the locked crawler 16C–16H contracts; not started).

## Verdict
**`P1A COMPLETE — MODULE-LOCKED`** (Step 2.8 double-submit acceptance
**PASS**, §10 2026-07-17; A3 DB proof + pending-record cleanup **COMPLETE**, §10 2026-07-17; P1a Step 2B + Step 3 SQL regressions **RE-RUN COMPLETE = PASS**, §10 2026-07-18; authenticated **browser role matrix COMPLETE — PASS**, §10 2026-07-18; real **`verify-once` worker binary run COMPLETE — PASS**, §10 2026-07-19. All operator-acceptance items are satisfied; a formal P1a lock entry now exists in `MODULE_LOCKS.md`). Next milestone
(separately approved, additive to the locked 16C–16H contracts): **P1b — verified-only
crawl enqueue enforcement (not started).**
