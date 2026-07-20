# Digibility SEO Module — Current Project Status

**2026-07-21 GCP TEST scaffolding:** SEO module now has Cloud Run deploy
artifacts (`Dockerfile`, `nginx.conf`, `entrypoint.sh`, `cloudbuild.yaml`) and
runtime-config injection (same pattern as Digibility UI). Digibility
`entrypoint.sh` / `cloudbuild.yaml` accept `SEO_APP_URL` for linked logout.
Operator runbook: `GCP_TEST_SSO_DEPLOY.md`. **No GCP/Cloud Run/Supabase
production apply was executed in this session.**

**2026-07-20 cross-project SSO checkpoint:** source implementation is complete
for a separate SEO Supabase project with Digibility Core as the only upstream
login/purchase authority. Additive Core entitlement + one-time-code migration,
Core `seo-bridge` Edge Function, entitlement-gated Digibility header switch,
email/password + Google post-login continuation, SEO identity mirror,
bridge-code redemption, normal refreshable SEO Supabase session, direct
unauthenticated deep-link return, TEST/local standalone fallback, and unit tests
are present. **Localhost verification is now supported in source** (Digibility
`:8080`, SEO `:8090`, optional `VITE_SEO_BRIDGE_URL` + `supabase functions serve`,
HTTP loopback launch URLs only). **Linked logout** clears both GoTrue sessions
(Digibility `/logout` ↔ SEO `/seo/auth/logout`) and blocks the prior
SEO-sign-out → Digibility-still-logged-in → auto-relaunch loop via a fresh
`seoReturnTo` intent flag. Local unit verification: SEO **17/17 tests +
TypeScript PASS**; Digibility UI **107/107 tests + TypeScript PASS**. Full
Digibility lint remains red from its pre-existing repository-wide backlog.
**Nothing was applied/deployed to any Supabase project; production untouched;
authenticated localhost/cross-domain live validation still pending.** Details
and deployment gates: `CROSS_PROJECT_SSO_IMPLEMENTATION.md` (includes localhost
+ linked-logout sections).

**Last updated:** 2026-07-18 (P1a **authenticated browser role matrix — COMPLETE = PASS** on `Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm`. Operator-executed logged-in click-through of the Step 5 UI (`OwnershipVerificationPanel`) against the real Supabase-mode app for **owner, admin, team_member, and client**, each followed by sign-out. **Owner:** authenticated successfully; on `/seo/websites` saw `digibility.ai` with ownership controls enabled; **Verify ownership** issued exactly one `seo_ownership_verification_initiate` request (HTTP 200); UI changed to **Verification pending** and remained pending after a hard refresh (state read live from Supabase, not cached); sign-out redirected to `/seo/login` and removed all protected content. **Admin:** authenticated successfully; saw the persisted **pending** status with **Check again / Re-verify / Revoke** enabled; **Check again** issued exactly one `seo_ownership_verification_recheck` request (HTTP 200); status remained **pending**; sign-out removed protected content. **team_member:** authenticated successfully; saw **pending** status, **no** ownership action buttons, and the read-only "Requires the owner or admin role." message; Network evidence confirmed **no** initiate/recheck/reverify/revoke request fired; sign-out removed protected content. **client:** authenticated successfully; identical read-only affordance to team_member (pending status, no action buttons, read-only message); Network evidence confirmed **no** write RPC fired; sign-out removed protected content. **Cross-role state + session isolation:** status was read live from Supabase across every role switch (no stale/cached cross-user state observed); protected routes were inaccessible after every sign-out. **No defect found; no source/migration/SQL/worker/frontend/config file was changed during this browser acceptance.** DNS challenge values from any screenshot evidence are intentionally not reproduced in this record. **This closes the §3 authenticated-browser-role-matrix acceptance item.** **P1a remains `IMPLEMENTED — OPERATOR ACCEPTANCE PENDING` and remains NOT module-locked.** The **sole remaining operator blocker** to the P1a lock is the real **`verify-once` worker binary** run against `Digi_SEO_Test` (needs `SUPABASE_SERVICE_ROLE_KEY`). P1b — verified-only crawl enqueue enforcement — remains not started. Production remains untouched; no code/migration/SQL/worker/frontend/config file changed; no commit/push. See `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §3/§10 (2026-07-18 entry) and `CHATGPT_CONTEXT_HANDOVER.md` (updated). Prior line — 2026-07-18 (P1a **Step 2B + Step 3 SQL regressions — RE-RUN COMPLETE = PASS** on `Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm`. A read-only pre-run eligibility diagnostic confirmed **0** `seo_ownership_verifications` rows with `status` in (`pending`,`failed`) before execution — no leftover-claim risk. `supabase/test/seo_p1a_step2b_ownership_verification_service_rpcs_verification.sql` returned its explicit sentinel `ALL PASS — seo_p1a_step2b service-role + global-admin ownership-verification verification complete`; `supabase/test/seo_p1a_step3_worker_dns_verification_integration.sql` returned `ALL PASS — seo_p1a_step3 worker DNS-verification TEST integration complete`. Both scripts' own teardown + locked-crawler/Page-Inventory/Stage-6 isolation-count assertions passed as a precondition of returning the sentinel row (a failed assertion raises an exception and suppresses it); both are single-transaction and self-cleaning — net-nothing committed on success. **This resolves the earlier "Step 2B + Step 3 SQL regressions UNBLOCKED but NOT yet re-executed" follow-up** — it is no longer an open item. **No source, migration, SQL script, worker, frontend, config, or production file/state was changed by this verification run.** This repository copy has no `.git` directory in this execution environment, so no git-status/commit evidence is available — recorded as a known environment limitation, not a repository-state change. **P1a remains `IMPLEMENTED — OPERATOR ACCEPTANCE PENDING` and remains NOT module-locked.** The two remaining operator blockers are unchanged: (1) authenticated **browser role matrix** (needs TEST-user credentials/session); (2) real **`verify-once` worker binary** run against TEST (needs `SUPABASE_SERVICE_ROLE_KEY`). P1b — verified-only crawl enqueue enforcement — remains not started. See `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §10 (2026-07-18 entry) and `BACKEND_MILESTONE_HANDOFF.md` (2026-07-18 checkpoint). Prior line — 2026-07-17 (P1a Step 2.8 double-submit — **RESOLVED + AUTHENTICATED OPERATOR ACCEPTANCE = PASS**; final one-file **visible bounded post-action lock** in `src/pages/seo/websites/OwnershipVerificationPanel.tsx`. The earlier keep-alive/throttle guards were retired after temporary `[OVP]` diagnostics proved they ran correctly on a **single persistent instance** — the operator's multi-second burst simply had inter-click gaps > cooldown, so each later click was a legitimate new action; this **invalidated the acceptance criterion** ("one RPC across an arbitrarily long burst", which is unsound), so those long-burst runs are reclassified as **invalid tests against a retired criterion, NOT failures/defects.** Final guard = per-action state machine `idle → in_flight → cooldown → idle`: synchronous `phaseRef` authoritative + `lockedActions` state driving `disabled` (`disabled = anyPending || lockedActions[action]`); first click fires immediately; button stays visibly disabled through mutation + refetch + a **fixed 3000 ms** cooldown; clicks while locked never mutate/reset the timer; a later click after re-enable is intentionally a new recheck. No keep-alive/throttle/debounce/countdown/module-guard; no service/hook/RPC/DB/RLS/worker/config change; production untouched. **Verified:** root `tsc`/`build` clean; one-file scope; all `[OVP]` removed (grep = none); security sweep clean; **mock quantitative proof** (recheck counted **directly via the mock store's `lastCheckedAt`**, not token rotation — 8 rapid "Check again" → exactly **1** accepted recheck; +1 deliberate after cooldown = 2 total; same guard confirmed for initiate/reverify/revoke; no console errors; **zero Supabase calls** in mock). **Authenticated operator Step 2.8 = PASS:** **AT-1** rapid double/triple click → exactly **1** recheck POST (HTTP 200); **AT-2** button disabled ≈ 3.5 s then re-enables; **AT-3** deliberate click after re-enable → exactly **1** new recheck POST (HTTP 200); **AT-4** no overlapping duplicates. UI stayed `Verification pending`. **A3 DB proof + pending-record cleanup COMPLETE (2026-07-17, DB-confirmed on TEST):** (a) A3 integrity proof for `digibility.ai` (`website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`, `method=dns_txt`) returned **exactly one** row (`row_count=1`), `status=pending`, `last_checked_at`/`updated_at`=`2026-07-17 16:25:18.663042+00` — no duplicate rows from any double-submit testing. (b) The two operator-created leftover pending verifications were then **cleared via the authenticated customer revoke UI** (not direct delete; append-only history preserved): `digibility.ai` → `status=revoked`, `updated_at=2026-07-17 16:33:13.804585+00`; the Stage-5 smoke fixture `stage5-smoke-test.example` (`website_id=77777777-0000-0000-0000-0000000000b1`, source `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql`, was `pending` with `has_open_claim=false`) → `status=revoked`, `updated_at=2026-07-17 16:43:24.935897+00`. **This RESOLVES the earlier "Step 2B/Step 3 SQL DEFERRED until the two leftover pending verifications are cleared" blocker** — TEST now has a clean pending state; the Step 2B + Step 3 SQL regressions are **UNBLOCKED but NOT yet re-executed** (re-run remains a follow-up; not claimed as PASS here). **Overall P1a lock still withheld** pending the two remaining separate operator items (authenticated browser role matrix + real `verify-once` worker binary), whose status is unchanged per the sign-off; P1b not started. See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §9/§10 + `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §10. Prior line — 2026-07-16 (P1a Step 6 — **Validation, full regression & sign-off: `P1A IMPLEMENTED — OPERATOR ACCEPTANCE PENDING`; no defect found; production untouched; P1b NOT implemented**). The complete DNS-TXT Domain Ownership Verification capability (Steps 1 DB contract → 2A customer RPCs → 2B service-role claim/result + global-admin override → 3 isolated worker → 4 frontend service → 5 Websites-area UI) is implemented on `Digi_SEO_Test` and passed all automated regressions. **Automated (executed on TEST): ALL PASS** — P1a Step 1/2A/2B SQL verifications; Step 3 worker DNS integration SQL; worker `tsc` + suite **74/74**; root `tsc` + `build`; static security sweep (9/9: no service-role key in frontend/logs; worker never logs challenge/token; customer denied claims/lease/internal; customer table writes denied; worker writes via service-role RPC only; cross-workspace denied; global-admin override isolated; **no crawl authorization change; no P1b leak**); **locked crawler 16C/16D/16E/16F/16G/16H ALL PASS**; crawl RPC grants/signatures + crawl-status constraints **unchanged**; crawler frontend/worker/`StartCrawlControl`/`CrawlPanel`/Page-Performance files **unchanged**; **Stage 6 smoke PASSED + campaign-create + campaign-transition ALL PASS**. **Backend role matrix PROVEN** (owner/admin/team_member/client/non-member/global-admin) via the Step 2A/2B SQL scripts. **Mock-mode UI browser validation DONE** (deterministic initiate→pending, recheck token-reuse, reverify rotation, revoke; no console errors; no Supabase request). **PENDING operator follow-ups (exact reasons — NOT substituted with earlier evidence): (a) authenticated *browser* role matrix** — no TEST-user credentials/sessions here + app auth-gated; **(b) real DNS *worker binary* `verify-once` run against TEST** — no `SUPABASE_SERVICE_ROLE_KEY` in this environment. **Known evidence limitation (not a defect):** the Stage 2/3/4/5 smoke tests use explicit `BEGIN/COMMIT/ROLLBACK` (psql-style) and cannot run faithfully through the auto-wrapping `supabase db query -f` runner — the Stage-4 "duplicate snapshot allowed" is a transaction-nesting artifact; the Page-Performance uniqueness contract is intact (unique index `uq_seo_page_perf_snap_combo` present; files unchanged; no migration since Stage 4). **P1a is IMPLEMENTED but NOT module-locked** (formal lock withheld until the two operator-acceptance items pass). **This is not "the SEO module is production-ready."** **Double-submit fix (2026-07-16, approved, one-file UI-only):** operator acceptance Step 2.8 found that rapid clicks on the ownership "Check again" button sent multiple `seo_ownership_verification_recheck` RPCs (frontend guard relied only on the async `disabled={anyPending}`). Fixed in `src/pages/seo/websites/OwnershipVerificationPanel.tsx` only — added a synchronous `useRef` submission latch (`submitOnce`, set before `mutate`, cleared on `onSettled`) on initiate/recheck/reverify + confirm-revoke; `disabled={anyPending}`/labels/lifecycle/invalidation unchanged; no debounce, no service/hook/RPC/DB/locked change. Verified: `tsc`/`build` clean; security sweep clean (only that file); **mock-browser rapid-burst proof** (5 "Re-verify" clicks → exactly one token rotation; latch clears; "Check again" burst reuses token; no console errors; no Supabase request). Non-regression: **Step 1 + Phase 16C–16H + Stage 6 + worker 74/74 + root tsc/build ALL PASS**. **Step 2B + Step 3 SQL FAILED this run — NOT a regression, NOT a defect:** both failed at `seo_ownership_verification_claim` because **operator-created leftover `pending` ownership verifications on TEST** (`digibility.ai`, `stage5-smoke-test.example`, from the authenticated owner Steps 2.1–2.7 run) are claimed first by the correct globally-oldest-first claim RPC, breaking those scripts' single-pending isolation assumption; they will PASS on a clean pending state (operator data NOT deleted). **Operator Step 2.8 authenticated re-test remains PENDING.** Acceptance in progress; P1a not accepted/not locked; P1b not started. See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md`. **Double-submit fix — second iteration (2026-07-17, approved, one-file UI-only):** the first synchronous latch was a concurrency-only guard (a fast backend settled between real spaced clicks, so a burst still fired one RPC per click; the earlier mock proof used a synchronous click loop). Fixed by adding a **leading-edge per-action throttle** (`THROTTLE_MS=1000`, per-action `lastAcceptedRef`) alongside the retained in-flight latch in `OwnershipVerificationPanel.tsx` only — first click runs, repeat same-action clicks within 1s ignored, deliberate later click works, per-action (no global block), no debounce/first-click-delay; `disabled={anyPending}`/labels/lifecycle unchanged; no service/hook/RPC/DB/worker/crawl/locked change. Verified: `tsc`/`build` clean; security sweep clean; **mock SPACED-click proof** (5 "Re-verify" clicks 120ms apart → exactly one rotation; deliberate click after window rotates again; "Check again" burst reuses token; no console errors; no Supabase request); fix-unaffected non-regression **Step 1 + Step 2A + 16C–16H + Stage 6 + worker 74/74 + root tsc/build ALL PASS**. **Authenticated operator Step 2.8 re-test still PENDING** (needs real session). **Step 2B + Step 3 SQL DEFERRED** until the two operator-created leftover pending verifications on TEST (still present) are cleared via the approved customer revoke path (not direct delete). **Acceptance re-attempt (2026-07-16):** automated regression re-run **ALL PASS** (P1a + 16C–16H + Stage 6 + worker 74/74 + tsc/build); the three operator items remain blocked by **absent environment prerequisites** — no TEST-user credentials/session (browser matrix), no `SUPABASE_SERVICE_ROLE_KEY`/worker `.env` (real worker binary), and `psql` not found (legacy Stage 2–5 psql-runner smokes); verdict **unchanged**, no lock added. See `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §10. Next milestone (separately approved, additive to locked 16C–16H): **P1b — verified-only crawl enqueue enforcement** (not started). Prior line — P1a Step 5 — **Websites/onboarding Domain Ownership Verification UI implemented + type/build-verified + MOCK-mode browser-validated; authenticated TEST validation PENDING; additive UI; production untouched**). New `src/pages/seo/websites/OwnershipVerificationPanel.tsx` (full workflow: status badge + DNS-TXT instructions [Type=TXT, exact Host `_digibility-site-verification.<host>`, exact Value=challenge token] + copy controls + owner/admin actions + read-only role explanation for team_member/client + explicit two-step revoke confirm + a **local** accessible role tooltip — the locked Stage 6 `RoleGateTooltip` is NOT edited); uses **only** the Step 4 hooks (`useOwnershipVerification*`). Additive 3-line edit to `src/pages/seo/WebsiteCard.tsx` (renders the panel after `WebsiteConnectionHealth` + a `Separator`) — smallest Websites/onboarding surface; no new route; no page redesign; the locked crawl UI/`StartCrawlControl`/`CrawlPanel` untouched. States: unverified/pending/verified/failed/revoked with owner/admin initiate/recheck/reverify/revoke (double-submit disabled while pending; refresh only the matching ownership query; no polling, no browser DNS, no fake progress); genuine RPC errors surfaced verbatim (non-masking); derived approximate revoked timestamp omitted; global-admin override NOT exposed. Accessibility: text-labelled status (never colour-only); `aria-label` section; tooltip on hover+focus; copy buttons `aria-label`+`aria-live`; errors `role="alert"`; keyboard-operable confirm. Permanent deterministic mock preview (Preview badge + "no real domain verified" note; per-website isolated; no Supabase/DNS/timers). **This is Step 5 ONLY — P1a is NOT complete** (Step 6 sign-off pending); NO DB/migration/RPC/RLS change, NO worker change, NO crawl UI/authorization change, NO P1b, NO global-admin override; RLS + Step 2A RPCs authoritative (no role simulation). Verified: root `tsc` clean; `npm run build` OK; static security sweep clean (no service-role key/claims/lease/internal fields; no direct table write/raw Supabase in the UI — Step 4 hooks only; only `seo-ownership-verification[-role]` query keys, no crawl collision; no crawl/worker file edited); **Step 1/2A/2B + standalone Phase 16C–16H ALL PASS (non-regression); worker suite 74/74**. **Mock-mode browser validation DONE** (in-session `VITE_SEO_DATA_MODE=mock`): `/seo/websites` renders the panel; initiate→pending with correct DNS Host/Value+copy; recheck **reused** token (…000001), reverify **rotated** (…000002), revoke→"Verification revoked"→"Verify ownership"; **no console errors; no Supabase request** (all network Vite/localhost); locked crawl UI + Website cards unchanged. **Authenticated TEST validation (owner/admin/team_member/client role affordances, live RPC round-trips + error surfacing, refresh persistence, cross-user sign-out isolation) PENDING** — not performed (no TEST-user credentials/session in this environment; app `.env.local` is Supabase/auth-gated); code-covered, operator follow-up for Step 6. Rollback: delete the panel file + revert the 3-line WebsiteCard integration (no DB rollback). `MODULE_LOCKS.md` unchanged (no locked file/contract touched). See `P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md`. Prior line — P1a Step 4 — **Frontend ownership-verification service, types, hooks, and mock adapter implemented + type/build-verified; additive frontend service layer; NO UI; production untouched**). New frontend files behind the existing mock/Supabase adapter: `src/types/ownershipVerification.ts` (customer-safe `OwnershipVerificationView` + `OwnershipVerificationWriteError`); `src/lib/ownershipVerification.ts` (pure helpers `deriveDnsTxtName`/`unverifiedOwnershipView`/`mapOwnershipRow`/`ownershipVerificationQueryKey`); `src/services/supabase/seoOwnershipVerificationSupabaseService.ts` (RLS read of the Step-1 `seo_ownership_verifications` table — customer-safe columns only, website-id scoped, `unverified` when no row, never reads the internal claims/events tables, no service-role, no cross-website fallback — + Step 2A RPC writes sending **only** `p_website_id`); `src/services/ownershipVerificationService.ts` (public dispatcher: standard `runWithServiceAdapter` read + a **non-masking** write helper — a real `OwnershipVerificationWriteError` is surfaced, never masked by mock; only no-session/config falls back to mock); `src/mocks/ownershipVerificationMockData.ts` (deterministic per-website preview: unverified/pending/verified/failed/revoked; initiate/recheck/reverify/revoke move mock state per the Step 2A lifecycle; no Supabase/timers/DNS); `src/hooks/useOwnershipVerification.ts` (status query [**no polling**] + 4 mutation hooks; query key `["seo-ownership-verification", websiteId, userId]` user+website scoped, SessionSync/sign-out compatible, invalidates only its own key, no crawl-key collision, no DNS retry loop). Additive `supabaseTypes.ts` constants: `SEO_TABLES.ownershipVerifications` + the 4 `SEO_RPCS.ownershipVerification{Initiate,Recheck,Reverify,Revoke}` only (internal claims/events tables + Step 2B service-role/override RPCs deliberately NOT added). Frontend data contract derives only from Step-1 customer-safe fields (`dnsTxtName` derived `_digibility-site-verification.<host>`; `dnsTxtValue`=challenge token; **absence of a row → `unverified`**; `revokedAt` derived from `updated_at` while revoked since Step 1 has no `revoked_at` column); internal claim rows/lease tokens/worker ids/diagnostics/correlation/service-role metadata never exposed. **This is Step 4 ONLY — P1a is NOT complete:** NO customer-facing UI (Step 5), NO Websites/onboarding/card/connection-health/crawl UI edit, NO worker/DB/migration/RPC/RLS change, NO crawl authorization, NO P1b, NO global-admin override exposed; RLS + the Step 2A RPCs remain authoritative (no frontend role invention). Verified: root `tsc` clean; `npm run build` OK; static security sweep clean (no service-role key; no claims/events/lease/worker/diagnostic field; no direct table write; only the 4 Step 2A RPCs; only the `seo-ownership-verification` query key; no crawl/worker file edited); **Step 2A/2B/1 + standalone Phase 16C–16H verifications ALL PASS (non-regression); worker suite 74/74**. **Known limitation:** repo has no frontend test/lint framework (none added; mapping/query-key logic isolated into pure review-verifiable helpers); no UI so no browser validation required. Rollback: delete the 6 new frontend files + revert the additive `supabaseTypes.ts` constants (no DB rollback). `MODULE_LOCKS.md` unchanged (no locked file/contract touched). See `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md`. **Exact next task: P1a Step 5 — Websites/onboarding ownership-verification UI.** Prior line — P1a Step 3 — **Isolated DNS-TXT ownership-verification worker module implemented + TEST-verified; code-only additive extension of the LOCKED crawler-worker (approved); production untouched**). A standalone DNS-TXT verification runner inside the existing crawler-worker runtime host — **no migration, no schema, no new RPC** (reuses the Step 2B RPCs). New files `crawler-worker/src/verification/{dns,verificationGateway,runner}.ts` + `crawler-worker/src/modes.ts` + `crawler-worker/test/ownershipVerification.test.ts`; minimal additive edits to `crawler-worker/src/index.ts` (new `verify-once` mode handled **before** any crawl JobGateway/health-check/stale-recovery) and `crawler-worker/src/config.ts` (2 **optional** additive fields). Flow: claim ONE pending item via `seo_ownership_verification_claim` → resolve the exact `dns_txt_name` (`_digibility-site-verification.<host>`, DNS TXT only, bounded 5s timeout, multi-string flattened, multiple records supported) → **exact** case-sensitive challenge match → persist `verified`/`failed` via `seo_ownership_verification_record_result` (token **preserved**; deterministic customer-safe failure reasons `dns_not_found`/`dns_mismatch`/`dns_timeout`/`dns_temporary`/`dns_malformed`/`internal_error` with internal code/detail stored only on the admin-only claim row; **no auto-retry** — customer re-triggers `recheck`). **Fully independent of the crawl processor** (imports nothing from processor/worker/jobGateway; never touches crawler jobs/attempts/events/leases/statuses; no crawl RPC called); secret-safe structured logging (only verificationId/websiteId/outcome/reasonCode; never the challenge/lease token or raw TXT); DNS-only (no HTTP → no new SSRF surface); graceful shutdown abandons a claim (lease recovers it). **This is Step 3 ONLY — P1a is NOT complete:** NO frontend/service/hook/mock/UI (Steps 4–5), NO Step 6 sign-off, NO P1b enqueue enforcement, NO migration/DB/RPC change, NO crawler contract/behaviour/status change, NO production deployment. Verified: worker `tsc` clean; **worker suite 74/74 pass, 0 fail**; **Step 2B/2A/1 verifications ALL PASS**; **standalone Phase 16C/16D/16E/16F/16G/16H ALL PASS**; root `tsc`/`build` clean; security sweep clean (no service-role key/raw-token logging; no direct ownership-table write; no crawl-processor import; only the two ownership RPCs called; no HTTP). **TEST integration** (`supabase/test/seo_p1a_step3_worker_dns_verification_integration.sql`, real Step 2B RPCs + deterministic simulated resolver) **ALL PASS**: pending claimed; verified + failed persisted; audit events written; token unchanged; internal diagnostics not customer-readable; **0** crawl/audit-issue/Page-Inventory/Page-Performance/recommendation/Stage-6 rows changed; self-cleaning. **Known limitation:** the Node worker **binary** was not run against TEST here (no `SUPABASE_SERVICE_ROLE_KEY` in this environment) — worker↔RPC wiring proven by an executed Node integration test (fake Supabase), RPC↔DB behaviour by the integration SQL. `MODULE_LOCKS.md` received a dated approved-additive-extension note. Rollback: delete the new verification files + `modes.ts` + test, revert the additive `index.ts`/`config.ts` edits (no DB rollback). See `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`. **Exact next task: P1a Step 4 — frontend ownership-verification service, types, hooks, and mock adapter.** Prior line — P1a Step 2B — **Service-role ownership-verification RPCs + global-admin override implemented + TEST-verified on `Digi_SEO_Test`; additive; production untouched**). Additive migration `20260716120033_seo_p1a_step2b_ownership_verification_service_rpcs.sql` adds the trusted backend API the FUTURE DNS-TXT worker (Step 3) + the global-admin path will call: a new **internal** `seo_ownership_verification_claims` claim/lease ledger (global-admin SELECT only; lease tokens/worker ids/internal diagnostics **not** customer-readable; partial unique index = at most one OPEN claim per verification) + **3 RPCs** — `seo_ownership_verification_claim` (**service_role only**; `FOR UPDATE SKIP LOCKED` claim of a `pending`/`failed` item, expired-lease stale recovery, returns only verification id/workspace/website/host/`dns_txt_name`/expected challenge/lease token/expiry), `seo_ownership_verification_record_result` (**service_role only**; validates the open claim + workspace/website consistency, accepts `verified`/`failed`, customer-safe reason vs internal diagnostics on the claim row, **token not rotated**, one event per result, idempotent duplicate, rejects stale/mismatched/cross-workspace/cross-website), and `seo_ownership_verification_admin_override` (`authenticated` but internally `seo_is_global_admin`-gated; `mark_verified`/`invalidate` with a required reason; server-side resolution; one `admin_override` audit event; idempotent). Lease model mirrors Phase 16D but on a **separate ownership-only table — no crawler table/lease/status/RPC reused or modified**. All 3 RPCs **SECURITY DEFINER + `SET search_path=public`** with explicit grant/revoke. **This is Step 2B ONLY — P1a is NOT complete and Step 3 (worker) is NOT implemented:** NO worker code, NO DNS resolution, NO frontend/service/hook/mock/UI, NO `supabaseTypes.ts` constant, NO crawler-worker/crawl-RPC/crawl-status/crawl-UI change, NO Page-Performance/Stage-6 change, NO P1b enforcement; migrations `…120031`/`…120032`/earlier not edited; no existing policy modified (only a new policy on the new table). Verified on TEST: dry-run (txn + forced rollback; 0 objects persisted) → `supabase db push --linked` applied + recorded (one in-session ambiguous-column defect in the claim RPC fixed + corrected idempotent migration re-applied) → structural (claims table + RLS + open-claim unique index; 3 RPCs SECDEF+search_path; claim/result service_role-only, authenticated/anon denied; override authenticated/anon-denied) → Step 2B SQL script **ALL PASS (35 checks)** → **Step 2A + Step 1 regressions ALL PASS** → **standalone Phase 16C/16D/16E/16F/16G/16H verifications ALL PASS** → **worker crawl suite 47/47 pass, 0 fail** → `tsc`/`build` clean. Rollback: `supabase/test/seo_p1a_step2b_ownership_verification_service_rpcs_rollback_TEST_ONLY.sql` (drops only the 3 RPCs + claims table; Step-1/2A + crawler + Page-Performance + Stage-6 preserved). No `MODULE_LOCKS.md` change needed (DB-only; no locked contract altered). See `P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`. **Exact next task: P1a Step 3 — isolated DNS-TXT verification worker module.** Prior line — P1a Step 2A — **Guarded CUSTOMER ownership-verification RPCs implemented + TEST-verified on `Digi_SEO_Test`; additive; production untouched**). Additive migration `20260716120032_seo_p1a_step2a_ownership_verification_rpcs.sql` adds **4 guarded customer RPCs** over the Step-1 tables — `seo_ownership_verification_initiate` / `recheck` / `reverify` / `revoke` — plus 3 internal helpers (`seo_ownership_extract_host` [URL host **parse**, not DNS resolution], `seo_ownership_new_challenge_token` [256-bit CSPRNG token, no pgcrypto dep], `_seo_ownership_authorize` [shared non-masking authz]). All 4 RPCs are **SECURITY DEFINER + `SET search_path = public`, `authenticated`-only (PUBLIC/anon revoked)**, authorize **owner/admin only** server-side (team_member/client/non-member/anon denied; **no global-admin override** — that is Step 2B), resolve workspace/website/current-host/role server-side, write append-only audit, and surface real errors verbatim. Behaviour: **initiate** creates a challenge, restarts from failed/revoked or host-change (rotates token), and is an idempotent no-op (no rotation, no event) when already pending-same-host or verified; **recheck** reuses the token (no rotation, **no DNS resolution**) and re-arms pending; **reverify** rotates the token + invalidates prior verified; **revoke** sets revoked, idempotent (no event on repeat), history preserved. **No status RPC added** — every column is customer-safe and both tables carry a member SELECT policy, so status is read directly via RLS. **This is Step 2A ONLY — P1a is NOT complete and Step 2B is NOT included:** NO service-role claim/result RPC, NO global-admin override, NO worker/DNS logic, NO frontend/service/hook/mock, NO `supabaseTypes.ts` constant, NO crawl RPC/authorization/UI change, NO P1b; `seo_crawl_request`/`seo_crawl_request_audit`/`seo_crawl_cancel`/`seo_crawl_claim_job` unchanged + non-regression-verified; no Step-1 table/policy change; no applied migration edited; no locked crawler/Page-Performance/Stage-6 object touched. Verified on TEST: dry-run (txn + forced rollback; 4 RPCs did not persist) → `supabase db push --linked` applied + recorded → structural (4 RPCs SECDEF+search_path; authenticated yes/anon no; internal helper not authenticated-executable) → Step 2A SQL script **ALL PASS** (23 checks incl. owner/admin allowed, team/client/non-member/anon + cross-workspace denied, initiate create+idempotency, recheck token-reuse, reverify rotation, revoke+idempotent revoke, admin restart-from-revoked rotation, one-event-per-meaningful-change, direct-write denial, customer-safe RLS reads, internal-field guard, crawler RPC non-regression, other-module isolation, self-cleaning) → **Step-1 + Phase 16C verifications ALL PASS (non-regression)** → `tsc`/`build` clean (no frontend file changed). Rollback: `supabase/test/seo_p1a_step2a_ownership_verification_rpcs_rollback_TEST_ONLY.sql` (drops only the 4 RPCs + 3 helpers; Step-1 tables/history + crawler + Page-Performance + Stage-6 preserved). See `P1A_STEP2A_OWNERSHIP_VERIFICATION_RPCS.md`. **Exact next task: P1a Step 2B — service-role claim/result RPCs and global-admin override.** Prior line — P1a Step 1 — **Domain Ownership Verification DATABASE CONTRACT implemented + TEST-verified on `Digi_SEO_Test`; additive; production untouched**). Additive migration `20260716120031_seo_p1a_step1_ownership_verification.sql` adds ONLY the DB foundation for DNS-TXT domain ownership verification: **`seo_ownership_verifications`** (one record per website+method; customer-safe; `method`=`dns_txt` only; status `pending`/`verified`/`failed`/`revoked`; `ownership_source`=`standalone_dns` provenance seam for a FUTURE Digibility signal; **UNIQUE (website_id, method)**) and append-only **`seo_ownership_verification_events`**, plus a defense-in-depth workspace/website integrity trigger (reusing the shared `set_updated_at()`), with **default-deny RLS** (workspace-member SELECT only on both tables; **no** customer INSERT/UPDATE/DELETE; audit immutable). Existing websites stay **unverified by default** (no rows created; absence == unverified); **no auto-expiry** (no `expired` state); state authoritative in Supabase. **This is Step 1 ONLY — P1a is NOT complete and P1b is entirely excluded:** NO customer/service-role RPCs, NO DNS/worker logic, NO frontend/service/hook/mock, NO `supabaseTypes.ts` constant, NO crawl-authorization change; `seo_crawl_request`/`seo_crawl_request_audit`/`seo_crawl_cancel`/crawl status/crawl UI/Page Performance/Stage 6 **all unchanged**; no applied migration edited; no file under the crawler 16C–16H lock touched. Verified on TEST: dry-run (txn + forced rollback, 0 leaked tables) → `supabase db push --linked` applied + recorded → structural (2 tables, RLS on both, exactly 1 SELECT policy + 0 write policies each, unique constraint present) → SQL script `supabase/test/seo_p1a_step1_ownership_verification_verification.sql` **ALL PASS** (structure/RLS/policy-shape; privileged fixture create; duplicate + integrity-mismatch + bad-FK + unknown-status rejected; member owner/client read; non-member/cross-workspace denied; authenticated direct write denied on both tables; audit immutable; self-cleaning; crawler/Page-Inventory/Stage-6 counts unchanged) → `tsc`/`build` clean (no frontend file changed). Rollback: `supabase/test/seo_p1a_step1_ownership_verification_rollback_TEST_ONLY.sql` (TEST only). See `P1A_STEP1_OWNERSHIP_VERIFICATION_DB_CONTRACT.md`. **Exact next task: P1a Step 2A — guarded customer ownership-verification RPCs.** Prior line — Phase 16H / Crawler 1F — **FULLY ACCEPTED ON TEST — PRODUCTION READINESS NOT STARTED**. All 7 operator acceptance scenarios PASS: 1 owner journey; 2 team-member request + queued cancel; 3 client read-only + prior published-result visibility (after an approved Page-Performance refresh-race fix); 4 active cancellation + worker acknowledgement; 5 partial result + inventory preservation; **6A/6B/6C** retry_wait → recovery+publish → max-attempt exhaustion+audit-failed (controlled DB-level lifecycle proof via the real one-shot worker + a temporary job-scoped fault trigger removed after each — no source/migration change); 7 refresh restoration + sign-out isolation + client read-only role gate. **Phase 16H — `FULLY ACCEPTED ON TEST — PRODUCTION READINESS NOT STARTED`: implementation Complete; automated verification Complete; operator acceptance Complete; documentation Complete; production Untouched. Known implementation defects: None. Known evidence limitations (documentation-only, no code change): tooltip screenshot not captured; hydration flash not recorded; timed polling-stop window not saved — all supported by confirmed code paths.** One non-blocking data-cleanliness note remains (a terminal crawl retains prior retry error fields; not customer-visible for `completed`). No implementation work remains for 16H. **Next milestone: production-readiness planning for the crawler** (deployment runtime, secrets management, ownership verification, usage/subscription enforcement, rate limits, monitoring/alerting, scheduler operation, production migration + rollback plans). **This does not mean the whole standalone SEO project is production-ready — it is not; SEO remains independent of the Visibility module, and the future wider-Digibility BFF integration is deferred.** See `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md` + `OPERATOR_TEST_RESULTS.md`. Prior line — Phase 16H / Crawler 1F — **Authenticated Crawl Request + Status + Freshness + Published-Result UI implemented + automated-verified; OPERATOR ACCEPTANCE PENDING** (no DB change; no recommendation write; no subscription enforcement; worker not deployed; crawler not customer-operational; production untouched) — see `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`. A customer crawl workflow on the existing `/seo/audit` surface: an owner/admin/team_member can **Start crawl** (explicit accessible two-step confirm) → calls `seo_crawl_request_audit` (returns both audit-run + crawl-job ids directly — **never a "latest run" guess**) → the queued job renders immediately → **Supabase is the single authoritative status source** (TanStack Query polling at 4s while active, stops at terminal, pauses on hidden tab, reconciles on refresh) → customer-safe status/labels (Queued/Preparing/Crawling/Waiting to retry/Cancelling/Completed/Partially completed/Failed/Cancelled), safe counts + honest freshness (from real timestamps, never the browser clock) → **Cancel** via `seo_crawl_cancel` only in its legal states (honest `cancellation_requested` → `cancelled`; idempotent) → on publish, links to the associated Audit results + Page Inventory (`/seo/page-performance`) and invalidates those existing queries. **Clients are read-only** (Start/Cancel disabled with the shared accessible role tooltip; **no** request/cancel RPC issued). New frontend only — `src/types/crawl.ts`, `src/lib/crawlStatus.ts`, `src/services/crawlService.ts` (+ `supabase/seoCrawlSupabaseService.ts`, `mocks/crawlMockData.ts`), `src/hooks/useWebsiteCrawl.ts`, `src/pages/seo/audit/crawl/*` — integrated into `WebsiteAuditPage.tsx` (2 lines). Customer-safe reads only (**no** lease token/worker id/correlation id/raw config); **no** direct crawler-table writes; **no** fake success after a failed RPC (`fallbackToMockOnError:false`); permanent **mock mode** shows a clearly-labelled Preview that writes nothing. **No DB/migration change.** Verified: frontend `tsc`/`build` clean; **worker 47/47**; `npm audit` 0 vulns; **16C+16D+16E+16F+16G all ALL PASS** (seed 7/7; recommendations + Page-Performance unchanged); frontend security sweep clean (no service-role/latest-run/direct-write/recommendation/worker-command in UI). **Browser/operator acceptance PENDING** (`OPERATOR_USER_ACCEPTANCE_TEST_GUIDE.md` + `OPERATOR_TEST_RESULTS.md`; the live customer-login flow needs TEST credentials + a running worker). During Scenario 1 operator acceptance, a reproduced Page Performance refresh
race was fixed under explicit locked-module approval in
`src/pages/seo/PagePerformancePage.tsx`; the production build passed and hard
refresh now retains all 3 crawler-published pages. Scenario 1 is PASS; Scenarios
2–7 remain pending, so overall operator acceptance remains PENDING. Stage 6 remains
untouched. Next: **Production crawler deployment, ownership verification and
usage-limit enforcement** (not started). Prior line — Phase 16G / Crawler 1E — **Controlled Page-Inventory + Audit PUBLISHING implemented + TEST-verified** (additive; no `seo_recommendations` write; no audit score; no customer crawl UI; crawler not customer-available; not deployed; production untouched) — see `CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`. Additive migration `20260714120029` binds a crawl job to **one explicit audit run** (`seo_crawl_jobs.audit_run_id` + guarded orchestration RPC `seo_crawl_request_audit` — `seo_crawl_request`/`seo_run_audit` unchanged; **never a "latest run" guess**) and adds one **service-role-only transactional** `seo_crawl_worker_publish_results` that reads the persisted crawler snapshots/issues **server-side** and additively/idempotently upserts the EXISTING `seo_page_inventory` + `seo_audit_issues` (deterministic **29-code** `seo_crawl_issue_audit_map`; severity `critical/error/warning/info`→`critical/high/medium/low`; site issues represented via `issue_scope='site'` + the real `website_url`, **no fabricated page**), records `seo_crawl_publications` evidence, and marks the run `completed` (**no score change**). Provenance-preserving, **stale-job-safe** (DB-level ordering — an older crawl can't overwrite newer facts), **manual/user-owned records preserved** (never overwritten/deleted; missing pages never marked removed). Customer pages still read through their **existing** Page-Inventory/Audit services (`select("*")` — additive nullable columns don't change shapes); **no frontend page/service changed** (registry constants only). **Complete:** control plane, worker lifecycle, secure discovery, robots/sitemap, HTML-link discovery, extraction+normalization, deterministic issue detection, crawler-domain persistence, **Page-Inventory publishing, Audit-Issue publishing, explicit audit-run association, publication idempotency**. **Not complete:** Recommendation generation, customer crawl-result UI, production crawler deployment, customer-operational crawling. Verified: `seo_phase16g_...` **ALL PASS**; **worker 47/47**; `npm audit` 0 vulns; **16C+16D+16E+16F all ALL PASS**; `tsc`/`build` clean; **E2E fixture publish** (real service-role one-shot, key never printed) = 3 Page-Inventory rows + 8 Audit Issues (7 page + 1 site `DUPLICATE_TITLE`), run `completed` (score still 0), publication `published` 3/8, crawl `completed`, **0 recommendations, 0 Page-Performance writes**, seed Page-Inventory/Audit unchanged (7/7), disposable fixtures self-cleaned. **Browser/read regression:** not run as a live customer login (app defaults to **mock** data mode; Page-Inventory surface is the **locked** Page Performance page; no TEST-user password) — render compatibility is structurally guaranteed (no page/service change; `select("*")` reads; additive nullable columns) + evidenced by the E2E column population. Next: **Crawler Phase 1F — authenticated crawl request, status, freshness and published-result UI** (not started). Prior line — Phase 16F / Crawler 1D — **Page EXTRACTION + deterministic technical-SEO issue detection + site-level duplicate detection implemented + TEST-verified** (no audit/page-inventory publishing; no SEO score/AI; crawler not customer-available; not deployed) — see `CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`. New worker modules `crawler-worker/src/extraction/*` (+ `discovery/charset.ts`) extract bounded technical facts from the HTML **already fetched in Phase 1C (no second fetch)** — title/desc/H1–H6/lang/canonical-classification/robots-directive-precedence/link+image counts/structured-data count/word-count + **sha-256 content hash** — with zero-dep `TextDecoder` charset handling (unsupported labels reported), deterministic text normalization, a **versioned issue-rule registry** (RULESET 1.0.0; ~26 stable page codes + 3 site duplicate codes; thresholds as versioned guidance, not Google rules), and site-level duplicate (title/description/content-hash) detection excluding empty/noindex. Additive migration `20260714120028` adds `seo_crawl_page_snapshots` + `seo_crawl_issues` (customer-read via workspace RLS; **no customer writes**; data-minimized — **no full HTML/text/scripts/JSON-LD/PII/headers**, only metadata + hash + bounded evidence) + `extraction_stats`, and **service-role-only** `seo_crawl_worker_record_snapshots`/`record_issues`/`update_extraction_progress` (validate lease_token; derive workspace/website server-side; reject unknown codes + oversized evidence). **No new dependency** (`npm audit` 0 vulns). Verification `seo_phase16f_...` = ALL PASS; **worker unit tests 32/32**; **integration** (real one-shot, fixture transport, service-role key never printed) = completed with 3 snapshots + issues incl. `DUPLICATE_TITLE`, **0 body columns**, **Page-Inventory/Audit unchanged (7/7 — no writes)**, 0 secret in logs. `tsc`/`build` clean; **16C+16D+16E+16F all ALL PASS**; no existing status/RPC changed; customer RLS + locked Page Performance/Stage 6 untouched; **no writes to Page-Inventory/Audit/Recommendations/locked tables; crawler NOT available to customers; production untouched.** Next: **Crawler Phase 1E — controlled Page Inventory and Audit publishing integration**. Prior line — Phase 16E / Crawler 1C — **Secure page-DISCOVERY engine (URL safety, SSRF+DNS-rebinding protection, robots.txt, sitemap, HTML link discovery, budgets, persistence) implemented + TEST-verified** (no SEO analysis; not deployed) — see `CRAWLER_PHASE_1C_DISCOVERY_ENGINE.md`. New worker modules under `crawler-worker/src/discovery/` (all network access via one `SafeHttpTransport` with **connection-time DNS validation** — resolves all addresses, rejects if any is unsafe, pins a validated address; TLS never disabled; every redirect re-validated; `ipSafety` blocks loopback/private/link-local/CGNAT/multicast/metadata/IPv4-mapped; `urlSafety` normalizes + rejects userinfo/non-default-ports/control-chars/non-http(s); robots RFC 9309 longest-match; XXE-safe sitemap parsing (`processEntities:false` + DOCTYPE reject); `<a>`-only same-origin HTML discovery with unsafe-`<base>` rejection; deterministic budgeted BFS). Additive migration `20260714120027` adds `seo_crawl_discovered_pages` + `seo_crawl_sitemaps` (customer-read via workspace RLS; **no customer writes**) + `discovery_stats`, and **service-role-only** `seo_crawl_worker_record_discovery` (bulk upsert; validates lease_token; workspace/website derived server-side) + `seo_crawl_worker_update_discovery_progress`. Deps added: `fast-xml-parser@5` (0 advisories) + `node-html-parser@6`. **Verification** `seo_phase16e_...` = ALL PASS; **worker unit tests 22/22**; **integration** (real one-shot, TEST-only fixture transport, service-role key never printed) = completed with 3 pages fetched, 1 robots-blocked, 0 cross-origin leak, 1 sitemap parsed, **Page-Inventory/Audit unchanged (7/7 — no writes)**, 0 secret in logs. **Real-public-network crawl NOT live-tested** (no operator fixture domain; deterministic + fixture coverage instead — documented). `tsc`/`build` clean; **16C+16D+16E all ALL PASS** (backward compatible); no existing status/RPC changed; customer RLS + locked Page Performance/Stage 6 untouched; **no Page-Inventory/Audit/Recommendations/locked-table writes; crawler NOT available to customers; production untouched.** Next: **Crawler Phase 1D — page extraction, normalization and basic technical SEO issue detection**. Prior line — Phase 16D / Crawler 1B — **Dedicated crawler WORKER skeleton + secure job-lifecycle contract implemented + TEST-verified** (no crawling; not deployed) — see `CRAWLER_PHASE_1B_WORKER_SKELETON.md`. Additive migration `20260714120026_seo_phase16d_worker_lifecycle.sql` adds a **lease_token** (jobs + attempts) and **service-role-only** worker functions (`seo_crawl_worker_heartbeat`/`complete`/`partial`/`fail`/`schedule_retry`/`acknowledge_cancellation`, `seo_crawl_recover_stale_jobs`) + an ownership guard; `seo_crawl_claim_job` was additively enhanced to issue + return the lease token. Every lifecycle function validates `(job_id, worker_id, lease_token)` (a re-claim after lease expiry invalidates a stale worker), updates the attempt, writes exactly one append-only event, and is EXECUTE-restricted to `service_role` (authenticated/anon revoked). A **Node/TypeScript worker** lives in `crawler-worker/` (outside `src/`; separate package): typed fail-fast config with service-role-key redaction, structured secret-safe JSON logging, error taxonomy, claim/heartbeat/terminal via the RPCs only, a **no-crawl skeleton processor that refuses non-test jobs**, dry-run/one-shot/gated-poll modes, startup stale-recovery, graceful shutdown, unit tests (10 pass), and a non-root Dockerfile (not deployed). **Verification** `seo_phase16d_worker_lifecycle_verification.sql` = ALL PASS; **TEST integration** proved dry-run (no claim) → one-shot claim→heartbeat→**complete** with **page-inventory/audit counts unchanged (no crawling)**, non-test job **refused→failed** (customer-safe), poll refused without the dev flag, and **no secret in logs** (service-role key never printed). `tsc`/`build` clean; **16C verification still ALL PASS** (backward compatible); no existing status value changed; customer RLS unchanged; locked Page Performance + Stage 6 untouched; **production untouched.** Next: **Crawler Phase 1C — URL safety, robots.txt, sitemap and basic page-discovery engine**. Prior line — Phase 16C — **Crawler Job Control-Plane DATABASE CONTRACT implemented + TEST-verified** (additive migration only; no crawler runs) — see `CRAWLER_PHASE_1A_DATA_CONTRACT.md`. New additive migration `20260713120025_seo_phase16c_crawl_control_plane.sql` (applied to `Digi_SEO_Test`, recorded in migration history) adds three tables — `seo_crawl_jobs` (RLS-scoped, customer-safe, with a **partial unique index enforcing one active job per website** + `UNIQUE(workspace_id, idempotency_key)`), `seo_crawl_attempts` (INTERNAL diagnostics, global-admin-read-only), and append-only `seo_crawl_events` — plus guarded SECURITY DEFINER RPCs: `seo_crawl_request` + `seo_crawl_cancel` (EXECUTE authenticated only; in-function owner/admin/team_member-or-global-admin gate, **client denied**; workspace/url/role resolved server-side; config validated) and `seo_crawl_claim_job` (**service_role only** — the future worker's atomic `FOR UPDATE SKIP LOCKED` claim; not frontend-callable). RLS is default-deny (customers read only via workspace membership; **no direct customer writes**; events append-only; internal attempts hidden). **Usage/plan-limit enforcement DEFERRED** (seo_plan_limits has no crawl columns; seo_usage_events can't model reservations cleanly) and **external domain-ownership verification is a documented prerequisite** — neither is claimed. Verification `supabase/test/seo_phase16c_crawl_control_plane_verification.sql` = **ALL PASS**, idempotent, self-cleaning (0 residual; seed data unchanged). `tsc`/`build` clean (only additive `supabaseTypes.ts` name constants added; no frontend crawl service/UI). **Crawler WORKER not implemented; crawling NOT operational; no existing table/RPC/RLS altered; locked Page Performance + Stage 6 untouched; production untouched.** Next: **Crawler Phase 1B — dedicated worker skeleton + secure job-claim integration**. Prior line — Phase 16B — **Customer Authentication & Route Protection IMPLEMENTED + TEST-validated** — see `PHASE_16B_CUSTOMER_AUTH_ROUTE_PROTECTION_SIGNOFF.md`. Login-only customer sign-in (existing Supabase users) at chromeless `/seo/login`, plus `<ProtectedRoute>` on all `/seo/*` (Supabase mode) via a centralized `useSeoAccess()` resolver (session → `has_seo_module_access` → workspace → active website) with branded loading / access-required / setup-redirect / recoverable-error states; safe internal deep-link (`returnTo`) restoration; customer sign-out in the Header that clears user-scoped query cache + active-website and handles the benign global-revocation abort; `SessionSync` prevents cross-user data/selection leakage; `/seo/dev/*` now **development-only** (`import.meta.env.DEV`); `/seo/admin-preview` gated by the existing `seo_is_global_admin` RPC. **RLS + guarded RPCs remain authoritative; no DB/migration/RLS/RPC change; mock mode fully bypasses protection (permanent); locked Page Performance + Stage 6 behaviour unchanged (client action gate still disabled under the new flow = no new permissions); production untouched.** `tsc`/`build` clean. Browser-validated: anonymous→login redirect (returnTo preserved, no content leak); owner sign-in→deep-link restore→refresh persist→locked routes render→sign-out→inaccessible; client readable + locked gate intact; admin-preview denied for non-global-admins; mock mode works with 0 Supabase writes. Known limits (honest): global-admin ALLOW branch + no-module-access/no-workspace/no-website states are code-covered but not live-tested (no fixtures; TEST data not mutated); no unit-test framework in repo. **Auth implementation is NOT module-locked.** Next milestone: **Crawler Phase 1 — crawl-job data contract + additive migration design** (not started). Prior line — Phase 16A — Customer Authentication & Crawler Runtime **architecture decision (documentation only, no code/DB/prod change)** — see `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md`, `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`, `CRAWLER_PHASE_1_IMPLEMENTATION_PLAN.md`. **Proposed (awaiting operator approval):** **Auth = Option C hybrid** — customer-facing **standalone Supabase Auth** for MVP + a `ProtectedRoute` gate on `/seo/*` (RLS + guarded RPCs stay authoritative; dev routes become dev-only) + a future additive parent-Digibility identity-adapter seam (parent SSO **rejected for MVP** because the cross-app session/token contract is unconfirmed; no separate identity DB; SEO role strings unchanged). **Crawler runtime = Option C hybrid** — a guarded `SECURITY DEFINER` enqueue RPC (optionally a thin Edge Function) validates auth+ownership+plan/usage and atomically enqueues a job; a **dedicated service-role background worker** claims + crawls within budget and writes normalized results; the frontend observes via RLS-scoped reads (no BFF; service-role only in the worker; Edge Function = thin control plane, not the crawl runtime). Security/compliance mandated (SSRF/private-range blocking, robots, redirect re-validation, budgets, consent/retention, audit logging). Crawler is **additive**: it populates `seo_audit_runs`/`seo_audit_issues`/`seo_page_inventory`/`seo_recommendations` (shapes preserved) + new additive `seo_crawl_jobs`; **locked Page Performance snapshots + Stage 6 contracts untouched** (Page Performance fed read-only/additive, with locked-scope regression required). Subscription/usage tables confirmed **schema-only (not enforced)** — enforcement is P1. **Exact next implementation task (not started): customer authentication + route protection**, before any crawler migration/worker. Open operator gates: worker runtime host, Edge-Fn-vs-direct-RPC, crawl budgets/consent/retention, subscription tiers/limits, new table/column names, signup model. Prior line — MVP Release-Readiness & Next-Scope decision — **planning only, no code/DB/prod change** — see `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md`. Assessment: the module is currently a **WORKFLOW/DEMO MVP** (polished, RLS-secured, role-gated SEO workflows over `manual_seed` data) — **not customer-usable and not production-ready**, because there is **no live data ingestion** (no website crawler, GSC, GA4, or LLM/AI-visibility ingestion) and **no customer auth/route protection** (routes rely on data-layer RLS only; only a dev auth harness exists). Recommended path = **Option B (Minimum Customer-Usable MVP):** P0 customer auth + route protection + production baseline, then **crawler → GSC** (the two highest-value real SEO sources), plus subscription/usage enforcement and data-freshness UI — everything additive, preserving the locked Stage 6 + Page Performance foundations. GA4, LLM/AI-visibility writes, campaign task-completion, and the mock-only modules (Competitor/Roadmap/Reports/Keyword/Content-Gaps/Blog-Briefs) are **post-MVP (P2/P3)**; AI Visibility must be labeled *preview* until LLM ingestion exists. **Exact next implementation milestone (not started):** *Website Crawler — Phase 1 (additive crawl-ingestion foundation: site discovery + page inventory + basic technical issues, feeding the wired Audit/Page-Inventory reads without changing any locked contract)* — gated on operator decisions (release path, auth approach, crawler runtime host, crawl/privacy compliance). Prior line — Stage 6 Implemented-Scope Lock — **the completed + regression-verified Stage 6 scope is now LOCKED** (documentation-only decision) under a new `MODULE_LOCKS.md` entry **"Stage 6 — Off-Page Authority Workflows and AI Visibility Reads"**. **Locked & complete:** Off-Page Authority opportunity workflow, campaign creation + approval workflow, client/manager permission UX (incl. the campaign-create client role gate + shared `RoleGateTooltip`), and AI Visibility **reads** (`manual_seed`) — with all protected contracts (statuses `suggested…avoided`/`draft…rejected`, actions, roles, the 3 RPCs `seo_authority_opportunity_transition`/`seo_authority_campaign_create`/`seo_authority_campaign_transition`, the 8 Stage 6 tables + append-only activity, service signatures, read-shape types, immutable applied migrations `…120017`–`…120024`). **Deferred & UNLOCKED (open for separate additive work — not defects):** campaign task-completion writes; AI Visibility writes; real crawler/GSC/GA4/LLM ingestion; parent-platform/BFF integration; production deployment; route-level `ProtectedRoute`; Competitors/Roadmap/Reports wiring; mobile-overflow remediation. Shared Stage 6 files may receive **separately-authorized, backward-compatible, additive** changes that preserve the locked behaviour and re-run the Stage 6/Phase-15 regression. **This is not "all Stage 6 development is complete."** No application/migration/DB/API/permission change; production untouched; Page Performance Tracker lock unchanged. See `STAGE_6_FINAL_REGRESSION_SIGNOFF.md` (lock evidence) and `MODULE_LOCKS.md`. Prior line — Stage 6 Final Regression — **the approved Stage 6 scope (Off-Page Authority opportunity + campaign workflows; AI Visibility read-only) PASSED a full regression on TEST and is READY FOR A SEPARATE MODULE-LOCK DECISION** — see `STAGE_6_FINAL_REGRESSION_SIGNOFF.md`. Static: `tsc`/`build` clean; source invariants hold (no service-role key, no direct `approval_status`/opportunity-`status` update, RPCs = `seo_authority_opportunity_transition`/`seo_authority_campaign_create`/`seo_authority_campaign_transition`; `RoleGateTooltip` reused across the three consumers). SQL: Stage 6 smoke + campaign-create + campaign-transition verification scripts **ALL PASS**, idempotent + self-cleaning (0 temp leftovers; Phase 15 evidence intact — 14 workspace campaigns). Authenticated browser matrix (admin/team_member/client): opportunity + campaign reads load, refresh-persistent; manager full capability; team_member create/submit/return enabled + approve/reject and opportunity-`Reject` denied; client fully read-only (selection disabled + tooltip + focus-reveal, `CampaignBuilder` unreachable, **0 create/transition requests**); **0 unintended writes** (campaigns 14→14, activity 27→27). AI Visibility renders seeded reads (source `manual_seed`), **0 write requests**; writes + real LLM ingestion remain deferred. Mock mode (throwaway `:8091`, `.env.local` untouched): selection/builder/**create still work ungated** — the client create-gate does not affect mock. Earlier-stage routes (onboarding/audit/approvals/content-studio/**page-performance LOCKED**/decline-diagnosis/websites) render with no crash + 0 console errors. Known benign observations unchanged (favicon 404, sign-out `ERR_ABORTED`, ~20px mobile overflow). **No application/migration/RPC/RLS/API/DB change; production untouched.** Off-Page Authority remains **NOT LOCKED** — a separate lock decision is the next step. Prior line — Phase 15D — **Off-Page Authority Campaign Workflow fully authenticated-TEST-validated across all four roles (owner/admin/team_member/client) and SIGNED OFF** — see `PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md`. Authenticated browser validation on `Digi_SEO_Test`: owner + admin ran the full state machine (create→draft→submit→pending_approval→approve→approved and →reject→rejected→return_to_draft→draft) with refresh-persistence; team_member create+submit+return-to-draft permitted while approve/reject were denied (disabled + "Requires the owner or admin role." tooltip); client fully **read-only with zero writes**. Every transition produced exactly one `seo_authority_activity` row with correct `subject_type`/`from_status`/`to_status`/`actor_role_snapshot`/`created_by`; linked opportunities + tasks unchanged; double-submit protected. **During client validation a frontend create-gating gap was found and fixed (frontend-only):** a real `client` could reach an enabled "Create campaign" button and issue a backend-rejected `seo_authority_campaign_create` request. Fix = new shared `src/pages/seo/offpage/RoleGateTooltip.tsx`; the opportunity-select checkbox (`OpportunityCard.tsx`) and the Create button + handler (`CampaignBuilder.tsx`, wired from `AuthorityBuilderPage.tsx` via the reused/exported `CAMPAIGN_SUBMIT_ROLES`) are now role-gated for a real authenticated client; `CampaignList.tsx`'s `CampaignActionButton` refactored onto the shared wrapper. Client revalidation PASS (selection disabled + focus-revealed tooltip, **no create RPC request**, no console 400); managers unaffected (checkbox + Create still enabled); `tsc`/`build` clean. **No migration/RPC/RLS/API/DB change; production untouched.** The broader Off-Page Authority module remains **NOT LOCKED** pending the Stage 6 final regression pass (next task). Prior line — Phase 15E — **Stage 6 campaign-transition RPC backend-verified on TEST**: new TEST-only SQL script `supabase/test/seo_stage6_authority_campaign_transition_verification.sql` exercises the existing `seo_authority_campaign_transition` RPC across all 4 legal transitions + the extra pending_approval→draft path, per-role success/rejection, activity-row correctness incl. `actor_role_snapshot`, 9 illegal-transition rejections, data-integrity invariants, and RLS-enforced append-only activity — **ALL PASS, idempotent, self-cleaning** (`a8000000-` prefix; no migration/RLS/seed/frontend changed; production untouched). This gives backend evidence for the Phase 15D campaign transition steps (2A–2D); their authenticated owner/admin **browser** click-through for Step 2D remains separately pending. Prior line — Phase 15D Step 2D — Off-Page Authority **Rejected → Draft campaign transition implemented, completing the full campaign approval state machine (create/draft → submit → approve/reject → return-to-draft)**: `CampaignList.tsx` now shows a "Return to Draft" button for `rejected` campaigns only (hidden for draft/pending_approval/approved), enabled for owner/admin/team_member and disabled+tooltipped ("Requires the owner, admin, or team member role.") for client, wired through the existing, already-TEST-verified `seo_authority_campaign_transition` RPC (`return_to_draft` action) via the existing non-masking campaign-transition write helper — never a direct status UPDATE. `tsc`/`build` clean; browser regression verified directly in-browser (rejected campaign shows only "Return to Draft"; draft shows only "Submit for approval"; approved shows no action buttons; disabled+tooltip role-denial path renders with exact copy; no console errors). **Authenticated owner/admin click-through (status flips to Draft, persists after refresh, Submit for approval reappears) still pending** — no TEST credentials available this task. Atomic draft creation (Step 1B), Draft → Pending Approval (Step 2A), Pending Approval → Approved (Step 2B), and Pending Approval → Rejected (Step 2C) are confirmed implemented and browser-validated per current confirmed status. Phase 15C's Opportunity Workflow sign-off is untouched. Campaign editing/deletion and task-completion writes remain unbuilt; no Campaign Workflow sign-off document created yet, so the broader Off-Page Authority module remains NOT LOCKED. Production untouched).
**Purpose:** the single, always-current one-page status checkpoint for this repo.

> **Source of truth:** this file for *status*; `PROJECT_DOCUMENTATION_INDEX.md`
> for *which doc to read*. If any other document disagrees with this one about
> current status, treat **this file** as authoritative and flag the other doc as
> stale (see `DOCUMENTATION_WORKFLOW_RULES.md`).

---

## 1. Backend (Supabase migrations)

All applied to a **disposable TEST Supabase project** (`Digi_SEO_Test`, ref
`snyzotgwwfomgafrsvfm`) only, and verified by dry-run + structural checks +
dedicated SQL smoke tests (all `PASS`) — **Stages 1–6**. **None applied to
production.**

| Stage | Scope | Migrations | Status |
| --- | --- | --- | --- |
| Stage 1 | Access / Workspaces / Websites | `…120001`–`…120003` | ✅ Applied to TEST + verified + smoke-tested |
| Stage 2 | Audit / Recommendations / Approval | `…120004`–`…120006` | ✅ Applied to TEST + verified + smoke-tested |
| Stage 3 | Content Studio (+ private Storage bucket) | `…120007`–`…120009` | ✅ Applied to TEST + verified + smoke-tested |
| Stage 4 | Page Performance Tracker (+ latest-snapshot view) | `…120010`–`…120013` | ✅ Applied to TEST + verified + smoke-tested |
| Stage 5 | Decline Diagnosis Engine (+ current view + RPC) | `…120014`–`…120016` | ✅ Safety-reviewed + applied to TEST + verified + smoke-tested |
| Stage 6 | Off-Page Authority + AI Visibility/GEO | `…120017`–`…120023` | ✅ **Applied to TEST + structurally verified + smoke-tested PASS + UI-seeded — NOT service-wired.** All 7 migrations pushed to `Digi_SEO_Test` via `supabase db push --linked`; structural verification (8 tables, RLS on all 8, 3 functions, integrity trigger, policy shape 8 SELECT / 7 FOR ALL / 1 activity-INSERT / 0 activity-UPDATE-DELETE) and the `99999999-` smoke test both PASSED. The Stage 6 UI seed extension (`supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`, `a6000000-` prefix, attached to the base UI seed workspace/website, `created_by` derived from members) is **applied + verified on TEST** (idempotent re-run confirmed): **9 opportunities / 4 campaigns / 11 tasks / 6 junction links / 5 activity / 9 prompt-tracking (incl. a 3-point time-series) / 6 content gaps / 13 mentions** — all `manual_seed` demo. **Still not service-wired (Off-Page + AI Visibility remain mock-only in the UI). Production untouched.** |

**Backend totals (applied to TEST) — Stage-6 era, through migration `…120024` (pre-crawler):** **39 tables** + 2 views + **4 RPCs**
(`seo_create_decline_diagnosis_from_snapshot`,
`seo_authority_opportunity_transition`, `seo_authority_campaign_transition`,
and — new, Phase 15D — `seo_authority_campaign_create`)
+ 1 junction-integrity trigger function
(`seo_authority_campaign_opportunity_integrity`) + 1 private Storage bucket. This
**includes Stage 6** (8 tables + 2 transition RPCs, `…120017`–`…120023`, applied
+ structurally verified on 2026-07-11) **plus the Phase 15D additive migration
`…120024`** (the atomic `seo_authority_campaign_create` RPC, applied to TEST +
structurally verified + verification-script PASS on 2026-07-12). All additive;
none alter Core or the reference Digibility app.

> **Note (this Stage-6-era totals paragraph predates the crawler + P1a work and
> is not re-summed here).** The applied crawler control-plane/worker/discovery/
> extraction/publishing/finalization migrations (`…120025`–`…120030`, Phases
> 16C–16H) and the **P1a Step 1** migration (`…120031`) each added their own
> additive tables — tracked authoritatively by the top status line and their
> owner docs, not by this figure. P1a Step 1 specifically added **2** additive
> tables (`seo_ownership_verifications`, `seo_ownership_verification_events`) +
> 1 trigger function; all additive; production untouched.
> **Recalculated current whole-backend totals (CREATE TABLE across all 33
> migrations `…120001`–`…120033`): 51 tables** (Stages 1–5 = 31; Stage 6 = 8;
> crawler 16C–16H = 9; P1a Step 1 = 2; P1a Step 2B = 1 internal claims table)
> **+ 2 views + 1 private storage bucket**, all additive — this agrees with the
> "Current backend-state addendum" in `BACKEND_MILESTONE_HANDOFF.md` §1. (RPC
> totals are not restated as one grand number — customer RPCs, service-role
> worker functions, and trigger functions differ across Stage 6 + the crawler;
> P1a Step 1 added **0 RPCs**; P1a Step 2A added **4 customer RPCs + 3 helpers**,
> 0 tables; P1a Step 2B added **3 RPCs + 1 internal table**, 0 views.)

---

## 2. Frontend / Service Wiring

Complete through **Phase 15A** (reads only for Phase 15A — see below). Every
wired service sits behind the mock/Supabase data-mode adapter
(`runWithServiceAdapter`); **mock mode is the default and the graceful
fallback** — mocks were never removed.

| Phase | Wiring | Status |
| --- | --- | --- |
| 13A | Service-layer wiring foundation (adapter, data-mode switch) | ✅ Complete |
| 13B | `websiteService` + `businessOnboardingService` (Stage 1) | ✅ Complete |
| 13B.1 | Dev-only Supabase Auth Test harness (`/seo/dev/auth-test`) | ✅ Complete |
| 13C | `auditService` + `recommendationService` (Stage 2) | ✅ Complete |
| 13D | `approvalService` (Stage 2, via `seo_approval_transition` RPC) | ✅ Complete |
| 13E | `contentStudioService` (Stage 3, via `seo_content_transition` RPC) | ✅ Complete |
| 13F | Dashboard summaries + Admin Preview (read-only) | ✅ Complete |
| 14A.2 | Page Performance reads (Stage 4) | ✅ Complete + **live-tested** |
| 14B.2 | Decline Diagnosis reads (Stage 5) | ✅ Complete + **live-tested** |
| 15A | Off-Page Authority + AI Visibility/GEO reads (Stage 6) | ✅ Complete + **live-tested** — writes remain mock-only (see §6) |
| 15B | Stage 6 write UX audit (no wiring) | ✅ Complete — audit only, see `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md`; no writes wired |
| 15C | Off-Page Authority **Opportunity Workflow** writes (Stage 6, via `seo_authority_opportunity_transition`) | ✅ **Complete + signed off + live-tested** — see `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`; campaign writes untouched/mock-only (see §4, §6, §7) |
| 15D.1B | Off-Page Authority **atomic draft campaign creation** (Stage 6, via new `seo_authority_campaign_create` SECURITY DEFINER RPC, migration `…120024`; `approval_status` defaults to `draft`) | ✅ **Implemented + backend-verified on TEST + browser-validated** — RPC applied + structurally verified + SQL verification script PASS (13/13); frontend rewired to one `rpc()` call; `tsc`/`build` clean (see §4, §7) |
| 15D.2A | Off-Page Authority **Draft → Pending Approval campaign transition** (Stage 6, via existing `seo_authority_campaign_transition` RPC, `submit_for_approval` action) | ✅ **Implemented + browser-validated** — `CampaignList.tsx` "Submit for approval" button (status + role gated); `tsc`/`build` clean (see §4, §7) |
| 15D.2B | Off-Page Authority **Pending Approval → Approved campaign transition** (Stage 6, via existing `seo_authority_campaign_transition` RPC, `approve` action) | ✅ **Implemented + browser-validated** — `CampaignList.tsx` "Approve" button (status + owner/admin-only role gated); `tsc`/`build` clean (see §4, §7) |
| 15D.2C | Off-Page Authority **Pending Approval → Rejected campaign transition** (Stage 6, via existing `seo_authority_campaign_transition` RPC, `reject` action) | ✅ **Implemented + browser-validated** — `CampaignList.tsx` "Reject" button (status + owner/admin-only role gated, shown alongside Approve); `tsc`/`build` clean (see §4, §7) |
| 15D.2D | Off-Page Authority **Rejected → Draft campaign transition** (Stage 6, via existing `seo_authority_campaign_transition` RPC, `return_to_draft` action) | ✅ **Implemented + fully authenticated-validated (all 4 roles) + signed off** — `CampaignList.tsx` "Return to Draft" button (status + role gated); `tsc`/`build` clean. Authenticated owner/admin/team_member click-through confirmed (status flips to Draft, persists after refresh); client denied. See `PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md` |
| 15D | Off-Page Authority **Campaign Workflow** (creation + full approval state machine) — **authenticated 4-role validation + create-gating fix + sign-off** | ✅ **Complete + signed off + live-tested** — owner/admin/team_member/client validated on TEST; frontend create-gating fix (role-gated opportunity selection + Create control via new `RoleGateTooltip.tsx`); zero client writes; no migration/RPC/RLS/API change. See `PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md`. Module still **NOT LOCKED** pending Stage 6 final regression |

**Still mock-only:** Competitors, Roadmap, Reports (no backend stage yet);
**Off-Page Authority campaign editing/deletion and task-completion writes**
(no UI, no wiring — the full create/submit/approve/reject/return-to-draft
campaign workflow is now wired, see below); **AI Visibility writes** (status
updates, demo-data generation — unchanged since Phase
15A/15B, read-only
apart from existing mock-only demo behavior).

**Off-Page Authority Opportunity Workflow writes are implemented and signed
off (Phase 15C).** `OpportunityCard.tsx`'s status-change actions call
`seo_authority_opportunity_transition` via a non-masking write helper — never
a direct status UPDATE — with real `seo_workspace_members.seo_role`-based
role gating, legal status-based button visibility, and disabled+tooltip
rendering for unauthorized-but-legal actions. Mock mode is preserved.
Authenticated TEST browser validation has confirmed all 7 legal actions'
status/role behavior — 6 via a successfully executed transition, `reject`
via its correct role-gated disabled-state + tooltip for a `team_member` (see
§4 and `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`). This phase (15C) is
untouched by everything below.

**Off-Page Authority draft campaign creation is now ATOMIC (Phase 15D Step
1B), backend-verified on TEST, pending authenticated browser validation.**
`CampaignBuilder.tsx`'s "Create campaign" action calls
`seoOffPageAuthoritySupabaseService.createSupabaseAuthorityCampaign` (via
`offPageService.createAuthorityCampaign` → the non-masking
`runAuthorityCampaignWrite` helper, Phase 13D/13E/15C pattern), which now
makes a **single** `supabase.rpc('seo_authority_campaign_create', …)` call.
That new `SECURITY DEFINER` RPC (migration `20260712120024`) creates the
`seo_authority_campaigns` row (`approval_status` left at its `draft` column
default — **never** `pending_approval`), its
`seo_authority_campaign_opportunities` junction links, and one
`seo_authority_campaign_tasks` row per selected opportunity (label = that
opportunity's own `suggested_action`) **all inside one PL/pgSQL transaction**,
so any failure rolls the entire call back and leaves zero rows — replacing
the earlier 3-request + best-effort compensating-delete flow (which was not
atomic). The RPC resolves `workspace_id`/`website_url` server-side (never
trusts client-supplied values), enforces the owner/admin/team_member role
check in-function (clients + non-members rejected), validates the owner value
and that every opportunity belongs to the same workspace/website, and dedupes
opportunity ids. `EXECUTE` is granted to `authenticated` only (anon revoked).
The frontend re-reads the created campaign through the existing campaign
mapping. `CampaignList.tsx` already renders the `draft` badge as "Draft".
Mock mode is unchanged (still creates directly as `pending_approval` — a
separate, pre-existing mock-only quirk not touched by this step).
**Backend verified on TEST:** the RPC was applied, structurally verified, and
a dedicated SQL verification script passed all 13 scenarios (owner/admin/team
create draft; client + non-member rejected; draft status; junction + task
rows; cross-workspace + invalid-owner rejected; dedup; forced-failure
atomicity; teardown). `tsc`/`build` clean.

**Draft → Pending Approval campaign transition is now implemented (Phase 15D
Step 2A), pending authenticated browser validation.** `CampaignList.tsx` now
shows a "Submit for approval" button per campaign, wired to a new
`offPageService.submitAuthorityCampaignForApproval(id, websiteId)` → a new
non-masking `runAuthorityCampaignTransitionWrite` helper (same pattern as
`runAuthorityOpportunityWrite`) → a new
`seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityCampaign`,
which calls the **existing, already-TEST-verified**
`seo_authority_campaign_transition` RPC with `p_action: "submit_for_approval"`
— never a direct `approval_status` UPDATE — then re-reads the campaign.
**Visibility:** the button renders only when `approval_status === "draft"`
(hidden for `pending_approval`/`approved`/`rejected` — status-illegal actions
stay hidden, not just disabled). **Role gating:** enabled for
owner/admin/team_member (the RPC's base check for this action); disabled with
a tooltip reading exactly "Requires the owner, admin, or team member role."
for `client` — same disabled-focusable-wrapper tooltip pattern proven in
Phase 15C's `OpportunityCard.tsx` (hover + keyboard focus). Role gating is
Supabase-mode-only, matching every other Stage 6 action. A real RPC rejection
(`AuthorityCampaignTransitionError`) is surfaced verbatim in the UI, never
masked by mock. Mock mode is preserved (a new `updateAuthorityCampaignStatus`
mock function mirrors the RPC's `v_to` for this action so a click is visibly
equivalent in both modes — though mock campaigns can never naturally reach
`draft`, since mock creation still creates directly as `pending_approval`, a
separate pre-existing quirk not touched by this step). **Not implemented at
the time:** approve, reject, return-to-draft, and any task-completion write.
`tsc`/`build` clean. Both Step 1B and Step 2A are now confirmed **implemented
and authenticated browser-validated.**

**Pending Approval → Approved campaign transition is now implemented (Phase
15D Step 2B), pending authenticated owner/admin click-through validation.**
`CampaignList.tsx` now also shows an "Approve" button per campaign, wired to
a new `offPageService.approveAuthorityCampaign(id, websiteId)` — reusing the
same `runAuthorityCampaignTransitionWrite` non-masking helper and
`transitionSupabaseAuthorityCampaign` Supabase function as Step 2A, just with
`p_action: "approve"` — the campaign-transition action type
(`AuthorityCampaignTransitionAction`) was widened from a single literal to
`"submit_for_approval" | "approve"`. **Visibility:** the button renders only
when `approval_status === "pending_approval"` (hidden for
`draft`/`approved`/`rejected`). **Role gating:** enabled for owner/admin
only (the RPC's own extra restriction for this action — team_member and
client are both denied, stricter than `submit_for_approval`'s base check);
disabled with a tooltip reading exactly "Requires the owner or admin role."
for team_member/client — same disabled-focusable-wrapper pattern, now
extracted into a small shared `CampaignActionButton` component in
`CampaignList.tsx` since there are two independently role-gated actions.
A real RPC rejection is surfaced verbatim, never masked. Mock mode preserved
(`CAMPAIGN_ACTION_TO_MOCK_STATUS.approve = "approved"`). **Not implemented at
the time:** reject, return-to-draft, and any task-completion write.
`tsc`/`build` clean. Step 2B is now confirmed **implemented and authenticated
owner/admin browser-validated**, per current confirmed status.

**Pending Approval → Rejected campaign transition is now implemented (Phase
15D Step 2C), pending authenticated owner/admin click-through validation.**
`CampaignList.tsx` now also shows a "Reject" button per campaign, wired to a
new `offPageService.rejectAuthorityCampaign(id, websiteId)` — reusing the
same `runAuthorityCampaignTransitionWrite` non-masking helper and
`transitionSupabaseAuthorityCampaign` Supabase function as Steps 2A/2B, just
with `p_action: "reject"` — the campaign-transition action type
(`AuthorityCampaignTransitionAction`) was widened to
`"submit_for_approval" | "approve" | "reject"`. **Visibility:** the button
renders only when `approval_status === "pending_approval"` (hidden for
`draft`/`approved`/`rejected`) — Approve and Reject render together while a
campaign is pending approval. **Role gating:** enabled for owner/admin only
(the same RPC restriction as `approve`); disabled with a tooltip reading
exactly "Requires the owner or admin role." for team_member/client, reusing
the shared `CampaignActionButton` component (the role-array constant was
renamed from `CAMPAIGN_APPROVE_ROLES` to `CAMPAIGN_OWNER_ADMIN_ROLES` since
it now gates two actions). A real RPC rejection is surfaced verbatim, never
masked. Mock mode preserved (`CAMPAIGN_ACTION_TO_MOCK_STATUS.reject =
"rejected"`). **Not implemented at the time:** return-to-draft and any
task-completion write. `tsc`/`build` clean. Step 2C is now confirmed
**implemented and authenticated owner/admin browser-validated**, per current
confirmed status.

**Rejected → Draft campaign transition is now implemented (Phase 15D Step
2D), completing the full campaign approval state machine, pending
authenticated owner/admin click-through validation.** `CampaignList.tsx` now
also shows a "Return to Draft" button per campaign, wired to a new
`offPageService.returnCampaignToDraft(id, websiteId)` — reusing the same
`runAuthorityCampaignTransitionWrite` non-masking helper and
`transitionSupabaseAuthorityCampaign` Supabase function as Steps 2A/2B/2C,
just with `p_action: "return_to_draft"` — the campaign-transition action
type (`AuthorityCampaignTransitionAction`) was widened to
`"submit_for_approval" | "approve" | "reject" | "return_to_draft"`. The RPC
also legally accepts this action from `pending_approval`, but this step's UI
intentionally exposes it only from `rejected`, per scope. **Visibility:**
the button renders only when `approval_status === "rejected"` (hidden for
`draft`/`pending_approval`/`approved`). **Role gating:** enabled for
owner/admin/team_member (the RPC's base check, same restriction as
`submit_for_approval`); disabled with a tooltip reading exactly "Requires
the owner, admin, or team member role." for `client`, reusing the shared
`CampaignActionButton` component. A real RPC rejection is surfaced verbatim,
never masked. Mock mode preserved (`CAMPAIGN_ACTION_TO_MOCK_STATUS.return_to_draft
= "draft"`). **Not implemented:** campaign editing, campaign deletion, and
any task-completion write — out of scope. `tsc`/`build` clean; browser
regression verified **directly in-browser** (not just static): a `rejected`
mock campaign correctly showed only "Return to Draft" with the
disabled+tooltip role-denial path rendering the exact required copy; a
`draft` campaign correctly showed only "Submit for approval" (Return to
Draft hidden); an `approved` campaign correctly showed no action buttons;
and there were no console errors throughout — confirmed in this dev
environment's Supabase-data-mode-with-no-session state, consistent with
Steps 2B/2C's own already-established, non-regression behavior. **A full
owner/admin click-through (status flips to "Draft," "Return to Draft"
disappears, "Submit for approval" reappears, and it persists after refresh)
has not been performed** — no TEST credentials were available in this task;
this is the recommended immediate next step. The Opportunity Workflow
remains **signed off** (Phase 15C, untouched), but the broader Off-Page
Authority module is **still not locked** (see `MODULE_LOCKS.md`) — campaign
editing/deletion, task-completion writes, a Campaign Workflow sign-off, and
a Stage 6 final regression pass are all still pending. **Refresh
Recommendations** on the Decline Diagnosis page are also still mock/demo (no
Stage 5 backend table for them).

---

## 3. Seed / Test Datasets (TEST project only)

| Seed | Script | Status |
| --- | --- | --- |
| Base UI seed dataset | `supabase/test/seo_seed_ui_test_dataset.sql` | ✅ Applied + verified |
| Stage 4 Page Performance UI extension | `supabase/test/seo_seed_stage4_page_performance_ui_extension.sql` | ✅ Applied + verified |
| Stage 5 Decline Diagnosis UI extension | `supabase/test/seo_seed_stage5_decline_diagnosis_ui_extension.sql` | ✅ Applied + verified — **8 diagnoses / 20 evidence / 6 current-view rows** |
| Stage 6 Off-Page + AI Visibility UI extension | `supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql` | ✅ Applied + verified (`a6000000-` prefix, idempotent) — **9 opportunities / 4 campaigns / 11 tasks / 6 junction / 5 activity / 9 prompts / 6 gaps / 13 mentions** |

Base seed workspace/website used across extensions: workspace
`44444444-0000-0000-0001-000000000001`, website
`44444444-0000-0000-0002-000000000001` (`https://ui-seed-digibility.example`,
displayed as "UI Seed Demo Site").

---

## 4. Live-Test Status

- **Page Performance (14A.2):** live-tested signed-in against the TEST project's
  UI seed data.
- **Decline Diagnosis (14B.2):** live-tested signed-in. Two issues were found
  and fixed during live testing:
  1. **Finder ranking fix** — `findAccessibleWebsiteWithDeclineDiagnosisData`
     originally stopped at the first accessible website with any diagnosis data
     (which was the Stage 5 smoke-test workspace, 2 rows). Fixed to scan all
     accessible websites and pick the one with the **highest live diagnosis
     count**. After the fix the dev harness correctly selects **UI Seed
     Workspace / `https://ui-seed-digibility.example` / 6 live diagnoses
     (highest among 2 accessible websites with diagnoses)**.
  2. **Onboarding-gate order fix** — `/seo/decline-diagnosis` initially showed
     "Complete business onboarding first" because the page checked onboarding on
     the initially-active (never-onboarded smoke-test) website before the
     fallback could select the correct diagnosis-backed website. Fixed so the
     fallback search runs when the active website's onboarding is incomplete
     *or* it has no live diagnoses; the onboarding gate then re-evaluates
     against the page-local `displayWebsite` override.
  - After both fixes + restart, `/seo/decline-diagnosis` renders the seeded UI
    diagnosis cards on "UI Seed Demo Site". Legitimate onboarding requirements
    for real websites are still enforced. See
    `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` §10–§11.
- **Off-Page Authority + AI Visibility (15A): live-tested signed-in.**
  `/seo/dev/auth-test` passed with the expected seeded counts, and both
  `/seo/off-page` and `/seo/ai-visibility` passed authenticated browser
  testing against the TEST project's seeded Stage 6 data. Production
  untouched throughout. (Static validation — `tsc --noEmit`, `npm run
  build` — had already passed; see `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md`
  §10 for the retest procedure this confirmation followed.)
- **Stage 6 write UX audit (15B): completed, no new live testing performed.**
  `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` is a static, read-only audit of the
  existing mock-only write buttons against the Stage 6 transition RPCs — it
  did not exercise the app in a browser and did not change any code, so it
  neither adds to nor changes the live-test status above. Writes remain
  mock-only in every mode.
- **Off-Page Authority Opportunity Workflow writes (15C): signed off,
  fully live-tested signed-in against TEST.** Confirmed passing,
  authenticated, in the browser — status persisted after page refresh and no
  console errors during these checks:
  - Suggested → Shortlisted
  - Shortlisted → Approval required
  - Shortlisted → Expert review requested
  - Approval required → In progress
  - In progress → Completed
  - Mark as Avoided from a legal non-terminal state
  - Reject visible but disabled for `seo-team-test@example.com` (real role
    `team_member`), with the tooltip "Requires the owner or admin role."
    appearing on both hover and keyboard focus

  Backend evidence confirmed matching `seo_authority_activity` rows with
  correct `actor_role_snapshot` values for the transitions above. Full detail
  in `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`.

  **Known limitation:** a `reject` transition **executed by an owner/admin**
  (as opposed to the `team_member` denial path above) was not separately
  itemized in this validation pass — see the sign-off doc §11.

  Campaign creation and campaign transition writes were not exercised by this
  phase — they remain mock-only, untouched. A Stage 6 final regression pass
  is still pending, so the broader Off-Page Authority module remains **NOT
  LOCKED** (see `MODULE_LOCKS.md`). AI Visibility remains read-only apart
  from its existing mock-only demo behavior. Production untouched throughout.
- **Off-Page Authority atomic draft campaign creation (15D Step 1B):
  backend-verified on TEST via SQL AND authenticated browser-validated.**
  The `seo_authority_campaign_create` RPC (migration `…120024`) was applied to
  TEST via `supabase db push --linked`, dry-run-verified (transaction +
  rollback left nothing), structurally verified (SECURITY DEFINER,
  `search_path=public`, EXECUTE granted to `authenticated` only — anon
  revoked), and exercised by a dedicated verification script
  (`supabase/test/seo_stage6_authority_campaign_create_verification.sql`) that
  **passed all 13 scenarios**: owner/admin/team_member each create a draft
  campaign; client + non-member rejected; `approval_status='draft'`; correct
  junction rows; correct task rows (label = opportunity `suggested_action`,
  0-based positions); cross-workspace opportunity rejected; invalid owner
  rejected; duplicate opportunity ids deduped; a **forced child-write failure
  left net-zero campaign/junction/task rows** (true function atomicity); and
  full teardown. `npx tsc --noEmit -p tsconfig.app.json` + `npm run build`
  both passed. Production untouched throughout.
- **Off-Page Authority Draft → Pending Approval campaign transition (15D Step
  2A): implemented and authenticated browser-validated.** Uses the
  already-TEST-verified `seo_authority_campaign_transition` RPC (no new
  backend change this step). `npx tsc --noEmit -p tsconfig.app.json` and
  `npm run build` both passed. Production untouched throughout.
- **Off-Page Authority Pending Approval → Approved campaign transition (15D
  Step 2B): implemented and authenticated owner/admin click-through
  validated.** Reuses the same already-TEST-verified
  `seo_authority_campaign_transition` RPC (no new backend change — only the
  `p_action` value sent from the frontend differs). `npx tsc --noEmit
  -p tsconfig.app.json` and `npm run build` both passed. Production
  untouched throughout.
- **Off-Page Authority Pending Approval → Rejected campaign transition (15D
  Step 2C): implemented and authenticated owner/admin click-through
  validated.** Reuses the same already-TEST-verified
  `seo_authority_campaign_transition` RPC (no new backend change — only the
  `p_action` value sent from the frontend differs). `npx tsc --noEmit
  -p tsconfig.app.json` and `npm run build` both passed. Production
  untouched throughout.
- **Off-Page Authority Rejected → Draft campaign transition (15D Step 2D):
  implemented, NOT yet authenticated owner/admin click-through validated.**
  Reuses the same already-TEST-verified `seo_authority_campaign_transition`
  RPC (no new backend change — only the `p_action` value sent from the
  frontend differs). Static validation this task: `npx tsc --noEmit
  -p tsconfig.app.json` and `npm run build` both passed; a **direct
  in-browser check** (not just a static/no-session regression scan)
  confirmed: a `rejected` mock campaign (its status set for this specific
  check) correctly showed only "Return to Draft," disabled with a tooltip
  reading exactly "Requires the owner, admin, or team member role." — role
  gating is active in this dev environment (`VITE_SEO_DATA_MODE=supabase`,
  no signed-in session), consistent with every other campaign/opportunity
  button already exhibiting this same denial-by-default behavior; a `draft`
  campaign correctly showed only "Submit for approval" (Return to Draft
  correctly hidden); an `approved` campaign correctly showed no action
  buttons; and there were no console errors throughout. Test data was
  restored to its original state after the check. **No authenticated TEST
  session with an owner/admin role was available in this task**, so the
  real `rejected → draft` Supabase transition, its persisted status change
  after refresh, "Submit for approval" reappearing, and the live
  enabled-path for owner/admin/team_member have not been exercised signed in
  against TEST. This is the recommended immediate next step. This completes
  the full campaign approval state machine's UI (create → submit → approve/
  reject → return-to-draft); no Campaign Workflow sign-off document has been
  created yet. Production untouched throughout.
- **Off-Page Authority campaign-transition RPC backend SQL verification (15E):
  ALL PASS on TEST.** A dedicated TEST-only script
  (`supabase/test/seo_stage6_authority_campaign_transition_verification.sql`,
  `a8000000-` prefix) was run twice against `Digi_SEO_Test` via `supabase db
  query --linked -f` — both runs **ALL PASS**, DB clean afterward (zero
  leftover rows, helper functions dropped), idempotent. It exercises the
  **existing** `seo_authority_campaign_transition` RPC (no backend object
  created or changed): all 4 legal transitions plus the extra
  `pending_approval → draft` return path, per-role success/rejection
  (owner/admin/team_member/client/non-member), one correct
  `seo_authority_activity` row per success (subject_type / activity_type /
  from_status / to_status / `actor_role_snapshot`), 9 illegal-transition
  rejections (incl. unknown action + missing campaign id, each leaving status
  unchanged and no activity), data-integrity invariants (workspace/website/
  junction/tasks unchanged, exactly one activity row per transition), and
  RLS-enforced append-only activity (direct UPDATE/DELETE of
  `seo_authority_activity` as the `authenticated` role both affect 0 rows).
  This provides the **backend** evidence for the Phase 15D campaign transition
  steps (2A–2D) that the browser checks alone did not; the authenticated
  owner/admin **browser** click-through for Step 2D is still separately
  pending. No existing migration, seed SQL, RLS policy, or frontend code was
  changed; production untouched throughout.

---

## 5. Production Status

- **Production has NOT been touched.** No production migration, data, or connection.
- **Production apply remains gated** on all of: (1) target-project confirmation
  (correct shared Digibility Supabase project), (2) backup/branch strategy,
  (3) final migration review, (4) developer/technical-owner sign-off, and a
  rollback plan. See `BACKEND_MILESTONE_HANDOFF.md` §5.

---

## 6. Known Limitations (current)

- Data is **demo / manual seed data** where applicable (test project only).
- **No real GSC/GA4/crawler/LLM ingestion** for any module yet — all seeded
  rows use `manual_seed`; Stage 5 diagnoses are hand-written demo content.
- **No production apply.**
- **No diagnosis-to-recommendation conversion** wired (`linked_recommendation_id`
  is a backend seam only).
- **Stage 5 RPC write flow is not wired into the UI** — the RPC exists and is
  smoke-tested, but no UI creates diagnoses.
- **Refresh Recommendations** on Decline Diagnosis remain mock/demo.
- **Admin final integration into the existing Digibility Admin Panel** is future
  work; `/seo/admin-preview` is a temporary read-only surface.
- **Off-Page Authority Opportunity Workflow writes are wired and signed off
  (Phase 15C)** — `seo_authority_opportunity_transition` is called via a
  non-masking write helper, with real `seo_workspace_members.seo_role`-based
  role gating and legal status-based button visibility, replacing the
  direct-status-overwrite mock behavior described in
  `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §7 and audited in
  `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md`. See `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`
  for the full sign-off record. One minor validation gap remains (an
  owner/admin-executed `reject` was not separately itemized — see that
  doc's §11), and the **broader Off-Page Authority module is still not
  locked** pending campaign write wiring and a Stage 6 final regression pass
  (see `MODULE_LOCKS.md`).
- **Off-Page Authority draft campaign creation is now atomic + backend-verified
  on TEST + browser-validated (Phase 15D Step 1B)** — see §2 and §4. The
  earlier 3-request + compensating-delete flow was replaced by a single
  `seo_authority_campaign_create` SECURITY DEFINER RPC (migration `…120024`)
  that does all writes in one transaction, so the previous "double-failure
  residual risk" no longer exists.
- **Off-Page Authority Draft → Pending Approval campaign transition is now
  implemented and browser-validated (Phase 15D Step 2A)** — see §2 and §4.
  `CampaignList.tsx`'s "Submit for approval" button calls the
  already-TEST-verified `seo_authority_campaign_transition` RPC
  (`submit_for_approval`) via a non-masking service helper.
- **Off-Page Authority Pending Approval → Approved campaign transition is now
  implemented and browser-validated (Phase 15D Step 2B)** — see §2 and §4.
  `CampaignList.tsx`'s "Approve" button calls the same already-TEST-verified
  `seo_authority_campaign_transition` RPC (`approve` action, owner/admin
  only) via the existing non-masking campaign-transition service helper.
- **Off-Page Authority Pending Approval → Rejected campaign transition is now
  implemented and browser-validated (Phase 15D Step 2C)** — see §2 and §4.
  `CampaignList.tsx`'s "Reject" button calls the same already-TEST-verified
  `seo_authority_campaign_transition` RPC (`reject` action, owner/admin
  only) via the existing non-masking campaign-transition service helper.
- **Off-Page Authority Rejected → Draft campaign transition is now
  implemented but not yet authenticated owner/admin click-through validated
  (Phase 15D Step 2D)** — see §2 and §4. `CampaignList.tsx`'s "Return to
  Draft" button calls the same already-TEST-verified
  `seo_authority_campaign_transition` RPC (`return_to_draft` action, base
  manager check) via the existing non-masking campaign-transition service
  helper. This completes the UI for the full campaign approval state
  machine (`draft → pending_approval → approved`/`rejected → draft`).
  Campaign **editing, deletion, and task-completion writes remain unbuilt
  and mock-only**; no Campaign Workflow sign-off document has been created
  yet. See `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` §2.2–§2.3, §4.2 for the
  originally proposed design this now fully implements for the opportunity
  and campaign transition surfaces (task-completion writes were never part
  of that proposal).
- **AI Visibility remains read-only apart from existing mock-only demo
  behavior** — the "Generate AI visibility data" empty-state button and the
  unused `updateAiVisibilityItemStatus` export are unchanged from Phase
  15A/15B; no Stage 6 AI Visibility write was wired by Phase 15C.
- **Competitors, Roadmap, Reports** (no backend stage yet) are
  **mock/frontend-only**.

---

## 7. Next Recommended Implementation Step

No single step is mandated. The reasonable options, in the same
"backend → seed → wire → live-test" cadence that has worked so far:

1. **Stage 6 (Off-Page Authority + AI Visibility/GEO) — backend applied/verified/smoke-tested/UI-seeded; reads wired + live-tested (15A); write UX audited (15B); Opportunity Workflow writes implemented and signed off (15C); atomic draft campaign creation implemented + backend-verified + browser-validated (15D Step 1B); Draft → Pending Approval implemented + browser-validated (15D Step 2A); Pending Approval → Approved implemented + browser-validated (15D Step 2B); Pending Approval → Rejected implemented + browser-validated (15D Step 2C); Rejected → Draft implemented (15D Step 2D), completing the full campaign approval state machine's UI — authenticated owner/admin click-through validation of 15D Step 2D is the immediate next step.**
   All 7 migrations (`…120017`–`…120023`: 8 tables + 2 transition RPCs) are
   **applied to the disposable TEST project `Digi_SEO_Test`**, structurally
   verified, **smoke-tested PASS**, and **UI-seeded + verified**
   (`supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`,
   `a6000000-`). `offPageService`/`aiVisibilityService` **read** functions are
   wired to Supabase and **live-tested signed-in** (Phase 15A). A Phase 15B
   audit (`PHASE_15B_STAGE6_WRITE_UX_AUDIT.md`, audit only) documented which
   write buttons were illegal against the Stage 6 transition RPCs' state
   machine and proposed a legal action matrix.
   **Phase 15C (complete, signed off):** `OpportunityCard.tsx`'s writes call
   `seo_authority_opportunity_transition` (no direct status UPDATE) via a
   non-masking write helper (Phase 13D/13E pattern), using real
   `seo_workspace_members.seo_role`-based role gating, legal status-based
   button visibility, and disabled+tooltip rendering for
   unauthorized-but-legal actions. Mock mode is preserved; campaign writes
   are untouched. Authenticated TEST browser validation confirmed all 7
   legal actions' status/role behavior — see
   `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md` for the full record.
   **Phase 15D Step 1B (implemented + backend-verified + browser-validated):**
   `CampaignBuilder.tsx`'s "Create campaign" makes a single
   `supabase.rpc('seo_authority_campaign_create', …)` call (migration
   `…120024`) that atomically creates the campaign (`draft`), junction links,
   and one task per opportunity in one PL/pgSQL transaction. The RPC was
   applied to TEST, structurally verified, and a SQL verification script
   passed all 13 scenarios (incl. a forced-failure atomicity test proving
   net-zero partial rows). `tsc`/`build` clean; mock preserved.
   **Phase 15D Step 2A (implemented + browser-validated):**
   `CampaignList.tsx` shows a "Submit for approval" button — visible only
   for `draft` campaigns (hidden for pending_approval/approved/rejected),
   enabled for owner/admin/team_member, disabled + tooltipped ("Requires the
   owner, admin, or team member role.") for client — wired through
   `offPageService.submitAuthorityCampaignForApproval` → the existing,
   already-TEST-verified `seo_authority_campaign_transition` RPC
   (`submit_for_approval` action, no backend change needed).
   **Phase 15D Step 2B (implemented + browser-validated):**
   `CampaignList.tsx` shows an "Approve" button — visible only for
   `pending_approval` campaigns (hidden for draft/approved/rejected),
   enabled for owner/admin only, disabled + tooltipped ("Requires the owner
   or admin role.") for team_member/client — wired through
   `offPageService.approveAuthorityCampaign` → the existing,
   already-TEST-verified `seo_authority_campaign_transition` RPC (`approve`
   action, no backend change needed).
   **Phase 15D Step 2C (implemented + browser-validated):**
   `CampaignList.tsx` shows a "Reject" button — visible only for
   `pending_approval` campaigns alongside Approve (hidden for
   draft/approved/rejected), enabled for owner/admin only, disabled +
   tooltipped ("Requires the owner or admin role.") for team_member/client —
   wired through `offPageService.rejectAuthorityCampaign` → the existing,
   already-TEST-verified `seo_authority_campaign_transition` RPC (`reject`
   action, no backend change needed).
   **Phase 15D Step 2D (implemented, pending owner/admin click-through
   validation):** `CampaignList.tsx` now also shows a "Return to Draft"
   button — visible only for `rejected` campaigns (hidden for
   draft/pending_approval/approved), enabled for owner/admin/team_member,
   disabled + tooltipped ("Requires the owner, admin, or team member role.")
   for client — wired through a new `offPageService.returnCampaignToDraft`
   reusing the same non-masking campaign-transition helper and Supabase
   function as Steps 2A/2B/2C, just with `p_action: "return_to_draft"` (the
   campaign transition action type was widened to
   `"submit_for_approval" | "approve" | "reject" | "return_to_draft"`). No
   backend change needed. `tsc`/`build` clean; browser regression verified
   **directly in-browser** — a `rejected` campaign showed only "Return to
   Draft" (disabled+tooltip role-denial path with exact copy), a `draft`
   campaign showed only "Submit for approval," an `approved` campaign showed
   no buttons, and there were no console errors; opportunity writes, Step 1B
   creation, and Steps 2A/2B/2C untouched. This completes the UI for the
   full campaign approval state machine.
   **Immediate next step:** (a) authenticated owner/admin click-through
   validation of Step 2D — sign in as owner, admin, or team_member, click
   "Return to Draft" on a `rejected` campaign, confirm the badge updates to
   "Draft," "Return to Draft" disappears and "Submit for approval"
   reappears, it persists after refresh, and linked opportunities/checklist
   tasks remain intact; also confirm a `client` session sees the button
   disabled with its tooltip; (b) once that passes and Step 2C's remaining
   validation (if any) is confirmed, consider producing a Campaign Workflow
   sign-off document (not created yet); (c) then run a Stage 6 final
   regression pass before considering the full Off-Page Authority module
   (not just the Opportunity Workflow) for `MODULE_LOCKS.md` LOCKED status.
   Campaign editing/deletion and task-completion writes remain out of scope
   for all of the above. (Competitors / Roadmap / Support / Reports come
   after, per the approved rollout order.)
2. **Production-apply preparation:** assemble the gated checklist in
   `BACKEND_MILESTONE_HANDOFF.md` §5 (target-project confirmation, backup/branch
   strategy, final migration review, sign-off) — only if a production apply is
   actually intended.
3. **Deepen an existing module:** e.g. wire the Stage 5 diagnosis-creation RPC
   into a UI action, or add diagnosis-to-recommendation conversion — each as its
   own scoped task.

Whichever is chosen, follow `DOCUMENTATION_WORKFLOW_RULES.md`.
