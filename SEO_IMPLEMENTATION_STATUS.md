# SEO Implementation Status — Authoritative (Concise Current Truth)

**Role:** the single concise source of *current* implementation + lock + TEST +
production state for the SEO module. Part of the four-file authoritative package
(`SEO_CONTEXT_HANDOVER.md` is the entry point). For full dated evidence chains,
this file points to `CURRENT_PROJECT_STATUS.md` (the retained detailed ledger),
`MODULE_LOCKS.md`, and the per-module sign-off documents.

**As of:** 2026-07-24. **Branch:** `main`. **HEAD:**
`e00caa21f837b892777117538bb6a3dd9343d1de` (`feat(seo): add competitor
benchmarking read path`). **Working tree clean; local `main` = `origin/main`
(pushed).** All work below is committed. The **cross-project SSO identity-bridge
migration `20260720121000` is intentionally DEFERRED** — it remains pending on
`Digi_SEO_Test` and is not applied (see `SEO_DECISIONS.md` A14).

---

## 1. Completed modules and current lock state

| Area | State | Locked? | Primary evidence |
|---|---|---|---|
| Stages 1–6 service wiring + mock-mode UI (setup, onboarding, dashboard, audit, on-page, approvals, content studio, page performance, decline diagnosis, off-page, AI visibility, competitors, roadmap, support, reports) | Implemented (Supabase-adapter-wired where applicable, otherwise mock; several modules mock-only) | See per-item below | `SERVICE_LAYER_WIRING_PLAN.md`, `PHASE_13*/14*/15*_*.md`, `CURRENT_PROJECT_STATUS.md` |
| **Page Performance Tracker** | Complete | **LOCKED** | `MODULE_LOCKS.md`; `PHASE_14A_*` |
| **Stage 6 — Off-Page Authority + AI Visibility (reads + campaign/opportunity workflows)** | Complete, TEST-verified, operator-accepted | **LOCKED** | `STAGE_6_FINAL_REGRESSION_SIGNOFF.md`, `PHASE_15C/15D_*` |
| **Crawler Phases 16C–16H (customer crawl UI + crawl/audit/publishing contracts)** | Complete, TEST-verified, operator-accepted (all 7 scenarios PASS) | **LOCKED** | `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`, `OPERATOR_TEST_RESULTS.md`, `supabase/test/seo_phase16c–h_*` |
| **P1a — Domain Ownership Verification (DNS-TXT, Steps 1–6)** | **COMPLETE, TEST-verified, MODULE-LOCKED** | **LOCKED** | `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`, `MODULE_LOCKS.md` (P1a entry) |
| **P1b — Verified-only Crawl Enqueue Enforcement** | **COMPLETE, TEST-APPLIED, VERIFIED, concurrency-tested, MODULE-LOCKED** | **LOCKED** | `P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md`, `P1B_CONCURRENCY_VERIFICATION_GUIDE.md`, `MODULE_LOCKS.md` (P1b entry) |
| **Customer authentication + route protection (Phase 16B)** | Implemented (login-only; reuses Digibility auth) | Not locked (deferred) | `PHASE_16B_CUSTOMER_AUTH_ROUTE_PROTECTION_SIGNOFF.md`, `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md` |
| **Help Center (public docs surface)** — Slice 1, Slice 1A, Waves 2B / 2B.5 / 2C / 3 | **DEVELOPMENT-COMPLETE** (public foundation + contextual-help rollout across all safe/unlocked/strong-fit surfaces; 30 public + 1 internal articles; hand-rolled search; content validator PASS) | Not locked (frontend, additive) | `DIGIBILITY_SEO_HELP_CENTER_SLICE1_PUBLIC_FOUNDATION.md`, `..._SLICE1A_COMPLETION.md`, `..._WAVE2B/2C/WAVE3_*.md` |
| **Collapsible SEO Navigation IA** | Implemented + verified (SEO as one collapsible module, 7 logical groups, SEO Dashboard first; "Visibility Dashboard" → "SEO Dashboard") | Not locked (frontend, additive) | `DIGIBILITY_SEO_COLLAPSIBLE_NAVIGATION_INFORMATION_ARCHITECTURE.md` |
| **Cloud Run frontend container readiness** | Prepared + statically verified; **NOT deployed, NOT runtime-verified** | Not locked | `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` |
| **Reports — Stage 1 (real-data read foundation)** | **FULLY VERIFIED on `Digi_SEO_Test`** (migration `20260720120035` recorded once; SQL/RLS read-path PASS; tsc/build clean; **authenticated browser acceptance PASS 2026-07-20** — operator-login matrix: populated render + value match, Supabase read path `GET /rest/v1/seo_reports…→200`, no mock fallback, Generate disabled w/ copy, exports "coming soon", website-switch isolation, refresh/Back, no console errors). Generation/exports/history/schedule/delivery/sharing **deferred to Stage 2+**. | **LOCKED** (part of **Reports v1**, Stages 1–3; 2026-07-20) | `supabase/migrations/20260720120035_seo_reports_foundation.sql`, `supabase/test/seo_reports_read_path_verification.sql`, `supabase/test/seo_reports_stage1_browser_fixture_TEST_ONLY.sql`, `src/services/supabase/seoReportsSupabaseService.ts` |
| **Reports — Stage 2 (guarded generation & persistence)** | **TEST-APPLIED + backend-verified (2026-07-20)** — RPC `seo_report_generate` (migration `20260720120036` + corrective `20260720120037` denying anon EXECUTE) recorded once each; verification PASS (authz matrix incl. client/nonmember/anon/cross-tenant deny + no-leak; server-derived period/workspace/url/actor; latest-vs-previous audit selection; **all page-performance branches incl. deterministic Branch 3**; content=`archived` / authority=`avoided` DB-native aggregation; truthful `data_provenance` for the 3 unavailable areas; insert-then-update idempotency → one canonical row); Generate re-enabled in Supabase mode via the RPC; tsc/build clean. **Concurrency:** advisory-lock (`pg_advisory_xact_lock`) — **true two-session held-transaction lock-wait VERIFIED 2026-07-20** (two independent `pg` connections on `Digi_SEO_Test`: Session B blocked while A held the lock — `pg_locks` advisory waiter, B waited ~2.66 s and finished 91 ms after A committed; both returned the same UUID; exactly one canonical row; isolated disposable workspace/website/membership, 0 residue). **Authenticated browser acceptance PASS (2026-07-20)** — operator-login matrix on `Digi_SEO_Test` (owner, `digibility.ai`): Generate enabled → `POST /rpc/seo_report_generate → 200` (minimal `(uuid,text)` inputs, no client metrics) → report renders via Stage 1 read path with values matching raw source (audit score/issues, 0/0 pages with no snapshots, provenance); regenerate → same canonical row/id; refresh persists; period-change empty state; website-switch isolation + restore; no localStorage mock fallback; exports "coming soon"; Back; no console errors. | **LOCKED** (part of **Reports v1**, Stages 1–3; 2026-07-20) | `supabase/migrations/20260720120036_seo_report_generate.sql`, `supabase/migrations/20260720120037_seo_report_generate_revoke_anon.sql`, `supabase/test/seo_report_generate_verification.sql` |
| **Reports — Stage 3 (PDF export)** | **TEST-verified + browser-accepted (2026-07-20)** — read-only role-gated RPC `seo_report_export_data` (migration `20260720120038`, recorded once; `STABLE` SECURITY DEFINER; owner/admin/team_member only, **client/anon/nonmember/cross-tenant denied**, anon EXECUTE revoked; returns the stored row **unchanged**, no writes). Client-side `jsPDF` rendering (no BFF exists) of the already-persisted report — **never regenerates** (browser: Download PDF → `POST /rpc/seo_report_export_data → 200` → `application/pdf` blob; **no `seo_report_generate` call**); unavailable areas render "Not connected" via `data_provenance`; CSV/email/share stay disabled; downloading/success/error + double-click guard; tsc/build clean. | **LOCKED** (part of **Reports v1**, Stages 1–3; 2026-07-20) | `supabase/migrations/20260720120038_seo_report_export_data.sql`, `supabase/test/seo_report_export_data_verification.sql`, `src/pages/seo/reports/reportPdf.ts` |
| **Competitor Benchmarking — Stage 1 (persisted read path)** | **Implemented + backend-verified on `Digi_SEO_Test` (2026-07-20).** Additive table `public.seo_competitors` (migration `20260720123000`; workspace/website-scoped RLS — member SELECT incl. client read-only, owner/admin/team_member write; `UNIQUE(website_id, normalized_competitor_url)`). **Truthful provenance:** `data_provenance` CHECK-constrained to `'estimated'` (+ optional `generation_method`) — these scores are heuristic **estimates**, **no external provider (SEMrush/Ahrefs/GSC) is integrated**. Reads (`fetchCompetitors`/`fetchCompetitorDetail`, and the computed overview/benchmark/gap functions) wired through `runWithServiceAdapter` — **no silent mock fallback** in Supabase mode; mock mode unchanged (verified in browser). Generate/Refresh **disabled in Supabase mode** (generation is Stage 2). SQL/RLS verification PASS (owner=1/client=1/nonmember=0/anon=0; provenance=estimated; uniqueness; client write-denied; 0 residue); vitest 20/20; tsc/build clean. **Migration RECORDED on TEST (2026-07-20):** the DDL was applied via isolated `db query` (not `db push`, to avoid applying the unrelated pending SSO migration `20260720121000`), then the live schema was proven byte-equivalent to the migration and `20260720123000` was marked applied via `supabase migration repair --status applied` — **recorded exactly once; SSO `20260720121000` remains pending/untouched; no other migration status changed.** **Supabase-mode reachability + route protection verified in-browser** (via a temporary, since-restored `public/runtime-config.js` override — the tracked file forces `SEO_DATA_MODE:"mock"`). **Authenticated Supabase-mode read-path matrix OPERATOR-VERIFIED PASS (2026-07-22)** — signed-in owner on `digibility.ai`; confirmed: empty state renders with no mock fallback; persisted `estimated` rows read back and ordered; Generate/Refresh disabled in Supabase mode with deferred-reason copy; refresh persistence; website isolation; no write-on-read (client read-only role re-confirmed via SQL/RLS). Run via a temporary, since-restored `public/runtime-config.js` override (tracked file forces `SEO_DATA_MODE:"mock"`; restored byte-for-byte, hash-verified); disposable fixture deleted with 0 residue. **Truthful-wording fix:** `COMPETITOR_SAFETY_NOTICE` changed from "based on mock data" to "based on estimated benchmarking" to stay accurate in Supabase mode and consistent with the `estimated` provenance contract (A13). **COMMITTED + PUSHED (2026-07-24, HEAD `e00caa2` `feat(seo): add competitor benchmarking read path`).** **Stage 2A (guarded generation RPC) is now BACKEND-IMPLEMENTED + TEST-VERIFIED (2026-07-24)** — see the next row; Stage 2B (frontend service/hook/UI re-enable) + operator browser acceptance remain PENDING. | **Not locked** (module not complete; **Stage 2A backend done + TEST-verified; Stage 2B frontend pending**) | `supabase/migrations/20260720123000_seo_competitors.sql`, `supabase/test/seo_competitors_read_path_verification.sql`, `src/services/supabase/seoCompetitorSupabaseService.ts` |
| **Competitor Benchmarking — Stage 2A (guarded generation RPC)** | **BACKEND-IMPLEMENTED + TEST-VERIFIED + CONCURRENCY-VERIFIED on `Digi_SEO_Test` (2026-07-24); NO frontend integration, NO operator browser acceptance yet.** Additive migration `20260724120040_seo_competitor_generate.sql` introduces one guarded `SECURITY DEFINER` RPC `public.seo_competitor_generate(p_website_id uuid) RETURNS integer` (`SET search_path=public`; `authenticated` EXECUTE, **anon revoked up-front + PUBLIC revoked** — no corrective follow-up needed) plus an internal `IMMUTABLE` helper `seo_competitor_heuristic_score(text)` (PUBLIC-revoked). Server-derives actor/workspace/website-url from `seo_websites`, the competitor URL list from `seo_business_onboarding.competitors`, and the comparison score from the latest completed `seo_audit_runs` — **accepts only `p_website_id`; no client-supplied workspace/actor/scores/provenance/timestamps/metadata**. Authorizes owner/admin/team_member or global admin (**client/anon/non-member/cross-tenant denied with one non-leaking message; missing website == unauthorized**). **Deterministic local heuristic** reproducing the repo's confirmed rule (`hashStringToRange(url:dimension,35,90)` + 5-dim mean; `competitorService`-parity 8-dim our-score → status), **without** the mock's non-deterministic regenerate nudge, so repeated generation is **stable/idempotent**. Persists only `data_provenance='estimated'` + `generation_method='heuristic_v1'` (**never SEMrush/Ahrefs/GSC/measured/observed/verified/live**). Normalizes competitor URLs to the Stage 1 host contract; enforces `UNIQUE(website_id, normalized_competitor_url)`; **transaction-scoped `pg_advisory_xact_lock`** keyed to (website, generation op); **replace-to-match** (upsert canonical set + delete stale rows for that website only; other websites/workspaces untouched; empty-onboarding = non-destructive return 0). **SQL verification ALL PASS** (contract/grants/advisory-lock; owner/admin/team_member allowed; client/anon/non-member/cross-tenant denied + no-leak; server-derived fields; deterministic+idempotent; normalized de-dup+uniqueness; only-`estimated`; score bounds+required fields; audit-derived status; stale-row removal; other-website + cross-workspace isolation; non-destructive empty; **0 residue**); Stage 1 competitor regression PASS; vitest 20/20; `tsc` clean; `npm run build` clean. **Migration RECORDED on TEST (2026-07-24):** DDL applied via isolated `supabase db query --linked -f` (not `db push`), then `20260724120040` marked applied via `supabase migration repair --status applied` — **recorded exactly once; SSO `20260720121000` remains the only pending/unapplied migration; no other migration status changed; production never contacted.** **Concurrency: true two-session lock-wait VERIFIED on TEST (2026-07-24)** — two independent concurrent `supabase db query --linked` sessions against `Digi_SEO_Test` (same method as the P1b/Reports proofs): Session A called the RPC then held its transaction open via `pg_sleep(8)`; Session B, started ~1.5 s later, called the RPC on the same website and was directly observed in `pg_stat_activity` as `wait_event_type=Lock, wait_event=advisory` (blocked ~2.29 s at the observation point) while Session A was mid-`PgSleep`; once Session A committed, Session B unblocked and completed. Post-race state: exactly one canonical row per competitor (2 rows, 2 distinct normalized URLs, no duplicates, no unique-constraint error) — both rows' `created_at` from Session A's INSERT, both rows' `updated_at` from Session B's subsequent `ON CONFLICT DO UPDATE` pass, confirming clean serialization with no interleaved/partial write. Replace-to-match re-verified functioning identically after the race (competitor swap correctly applied). 0 residue across all 5 disposable fixture tables. Full method, timeline, and raw evidence: `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`. **NOT committed/pushed; NOT locked.** | **Not locked** (Stage 2B frontend + operator acceptance pending) | `supabase/migrations/20260724120040_seo_competitor_generate.sql`, `supabase/test/seo_competitor_generate_verification.sql`, `supabase/test/seo_competitor_generate_rollback_TEST_ONLY.sql`, `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md` |
| **Competitor Benchmarking — Stage 2B (frontend generation integration)** | **FRONTEND-IMPLEMENTED + UNIT-TESTED + AUTHENTICATED OPERATOR-ACCEPTED on `Digi_SEO_Test` (2026-07-24).** Wires the Stage 2A RPC through the established adapter pattern: new `generateSupabaseCompetitors(websiteId)` in `seoCompetitorSupabaseService.ts` calls `supabase.rpc('seo_competitor_generate', { p_website_id })` (only the website id — no workspace/actor/scores/provenance/timestamps sent), validates the response is a numeric count, then re-reads the canonical set through the Stage 1 read path (`fetchSupabaseCompetitors`) — the heuristic is never reproduced client-side. `competitorService.generateCompetitorBenchmarkData` dispatches via `runWithServiceAdapter` (`fallbackToMockOnError: false`); the mock branch is the pre-existing local generation, extracted verbatim into `generateMockCompetitorBenchmarkData` (unchanged behaviour). **Role gating (usability layer only; the RPC remains authoritative):** new `canGenerateCompetitorBenchmarks(role, supabaseMode)` + `COMPETITOR_GENERATE_ROLES = ['owner','admin','team_member']` (mirrors `AuthorityBuilderPage`'s `CAMPAIGN_SUBMIT_ROLES` pattern) — `CompetitorAnalysisPage` queries the real `seo_workspace_members.seo_role` via the existing `getCurrentSeoRole` helper (Supabase mode only; mock mode stays always-enabled, unchanged) and disables Generate/Refresh with the established "Requires the owner, admin, or team member role." tooltip (same wording as the Stage 6 role-gated controls) for client/non-member/no-membership. Added an actionable error message on generation failure (mirrors `ReportsPage`'s pattern); empty-onboarding behaviour is a backend safety net (Stage 2A returns 0, non-destructive) since the UI already gates the Generate button behind a non-empty onboarding competitor list. **No heuristic scoring logic added to the frontend; no locked module touched; no backend authorization weakened.** **Unit tests (new, 16 total):** `seoCompetitorSupabaseService.test.ts` (+7 — exact RPC name/args incl. proof only `p_website_id` is sent; error propagates with no fallback attempt; RPC-response-type validation; successful generation reads back the persisted rows, not the RPC's raw payload; truthful `estimated` provenance survives the read-back) and new `competitorService.test.ts` (+9 — `canGenerateCompetitorBenchmarks` for owner/admin/team_member/client/null across mock and Supabase mode; Supabase-branch dispatch sends only the website id; a Supabase generation error propagates unmasked; mock-mode branch never calls the RPC and still functions against the seeded onboarding fixture). Full suite **33/33 pass** (was 20/20); `tsc` clean; `npm run build` clean. **Browser verification performed (mock mode, no auth needed):** `/seo/competitor-analysis` renders with Refresh enabled, a live Refresh click re-generates and reloads correctly (count/score/timestamp update, button returns to idle), no console errors beyond the pre-existing app-wide React-Router v7 future-flag warnings. **Browser verification performed (Supabase mode, unauthenticated, via the same temporary/since-restored `public/runtime-config.js` override used for Stage 1 — restored byte-for-byte, hash-verified, 0 residue):** unauthenticated access to `/seo/competitor-analysis` correctly redirects to the real Digibility sign-in page (`ProtectedRoute` route protection intact) — no data leak, no mock fallback, no console errors.

**Authenticated operator acceptance — ALL PASS (2026-07-24, `Digi_SEO_Test`, real TEST accounts, real browser sessions):**
- **Owner (`seo-owner-test@example.com`, real user id `48c479db-…`):** page loaded persisted canonical data; Refresh enabled; click → `POST /rest/v1/rpc/seo_competitor_generate → 200` (network-observed) followed immediately by a `GET seo_competitors` re-read (canonical reload confirmed); generated 3 competitors (`ahrefs.com`/`moz.com`/`semrush.com`) for the real seed website `digibility.ai`; repeated refresh (2×) kept the set stable (3 rows, 3 distinct normalized URLs, same scores, exactly one RPC call per click — no duplicate-firing); DB-inspected (read-only) `data_provenance='estimated'` + `generation_method='heuristic_v1'` on every row; UI provenance text reads "Estimated competitor benchmarking from a heuristic model. No external competitor-data provider is integrated."; 0 console errors.
- **Admin (`seo-admin-test@example.com`, real user id `9830c4d7-…`):** same page loaded the owner-generated persisted data; Refresh enabled; generation succeeded (1 RPC call, 200); canonical set stayed 3/3 distinct, no duplicates; 0 console errors.
- **Team member (`seo-team-test@example.com`, real user id `0723d21f-…`):** same checks; generation succeeded (1 RPC call, 200); canonical set stayed 3/3 distinct, no duplicates; 0 console errors.
- **Client (`seo-client-test@example.com`, real user id `6c7a04e0-…`):** persisted read-only data loaded correctly (RLS member-SELECT, matches Stage 1); Refresh button `disabled=true` with `title="Requires the owner, admin, or team member role."`; clicking the disabled control issued **zero** RPC calls (network-confirmed); a direct in-session RPC call (client's real bearer token, safe in-page fetch, no credential logged) returned **HTTP 400, `P0001`, `"Not authorized to generate competitor benchmarks for this website."`** — backend remains authoritative and denies even a direct bypass attempt.
- **Error-path (owner session, client-side `fetch` intercepted for the RPC URL only — no DB/authorization change, fully reversible):** simulated 500 on the RPC → UI showed "Couldn't refresh benchmark data just now. Please try again."; the 3 previously-persisted competitors remained displayed unchanged (no fabricated/mock rows appeared); DB re-inspected afterward — identical 3 rows, untouched; interceptor removed immediately after.
- **Responsive/regression:** desktop (1280×800) and mobile (375×812) both render the page and the Generate/Refresh control usably with no broken layout; 0 console errors at either width; the unrelated `/seo/dashboard` page (real Supabase-backed data for the same TEST website) loaded normally with 0 console errors.
- **No defects found; no code changes were required.**

**NOT committed/pushed.** Competitor module remains **NOT locked** — a module lock requires separate explicit approval/review of this evidence, not an automatic consequence of acceptance passing. | **Not locked** (ready for commit; lock requires separate approval) | `src/services/supabase/seoCompetitorSupabaseService.ts`, `src/services/competitorService.ts`, `src/pages/seo/CompetitorAnalysisPage.tsx`, `src/services/supabase/supabaseTypes.ts`, `src/services/supabase/seoCompetitorSupabaseService.test.ts`, `src/services/competitorService.test.ts` |

## 2. P1a completion evidence (locked)

- DNS-TXT Domain Ownership Verification, Steps 1 (DB contract) → 2A (customer
  RPCs) → 2B (service-role claim/result + global-admin override) → 3 (isolated
  worker) → 4 (frontend service) → 5 (Websites-area UI + double-submit guard) →
  6 (sign-off), all applied/verified on `Digi_SEO_Test`.
- **Automated ALL PASS:** Step 1/2A/2B SQL, Step 3 worker DNS integration SQL,
  worker suite, root `tsc`/`build`, 9/9 security sweep, locked 16C–16H
  non-regression, Stage 6 non-regression.
- **Operator acceptance = PASS:** authenticated browser role matrix
  (owner/admin/team_member/client + sign-out isolation, 2026-07-18); real
  `verify-once` worker-binary run against TEST (2026-07-19; real Node DNS lookup,
  service-role key `[REDACTED]`, customer-safe `failed`/`dns_not_found` outcome —
  not a defect). Formal P1a lock added to `MODULE_LOCKS.md` 2026-07-19.

## 3. Crawler 16C–16H completion evidence (locked)

- Customer crawl request/status/cancel UI on `/seo/audit`; Supabase-authoritative
  status polling; explicit crawl→audit association (`seo_crawl_request_audit`
  returns both ids); audit-finalization + published-result preservation; Page
  Inventory publication-preservation rules.
- All 7 operator acceptance scenarios PASS; worker unit tests; DB verifications
  `seo_phase16c/d/e/f/g/h` (must remain PASS + idempotent). LOCKED 2026-07-15.

## 4. P1b evidence (locked) — migration / verification / regression / worker / concurrency / cleanup / lock

- **Migration (APPLIED to TEST, recorded once):**
  `supabase/migrations/20260719120034_seo_p1b_verified_only_crawl_enqueue.sql` —
  `CREATE OR REPLACE FUNCTION public.seo_crawl_request(...)` adding **one**
  verified-ownership guard (`PERFORM 1 FROM public.seo_ownership_verifications
  WHERE website_id=p_website_id AND method='dns_txt' AND status='verified' FOR
  SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Domain ownership must be verified
  before this website can be crawled.'`) placed **after** role authorization and
  **before** eligibility/config/INSERT. Static diff vs the applied Phase-16C body
  = guard only; the applied 16C migration is **not** edited; `seo_crawl_request_audit`
  unchanged (inherits the guard); plain `P0001` (no custom SQLSTATE).
- **Deployed-RPC contract check on TEST:** signature (`p_website_id uuid,
  p_idempotency_key text, p_config jsonb`), `RETURNS uuid`, SECURITY DEFINER,
  `search_path=public`, grants (`authenticated` EXECUTE; `anon` denied) — all
  **unchanged** except the added guard.
- **Acceptance verification ALL PASS**
  (`supabase/test/seo_p1b_verified_only_crawl_enqueue_verification.sql`): verified
  direct+audit succeed; pending/failed/revoked/missing blocked with the ownership
  message; rejected audit path creates no orphan audit run; authz/authn
  precedence (anon→auth error; client/non-member/cross-workspace→role error) with
  no ownership-state leak; idempotency/single-active-job/one-queued-event
  preserved; self-cleaning.
- **Regression ALL PASS:** the six 16C–16H DB verifications (with added
  verified-ownership fixtures, guard-ordering preserves intended negative
  reasons).
- **Worker regression:** `cd crawler-worker && npm test` → **74 pass, 0 fail,
  0 skipped** (worker source unchanged; still only claims jobs).
- **Concurrency (live two-session `FOR SHARE` proof,
  `P1B_CONCURRENCY_VERIFICATION_GUIDE.md`):** revoke-wins → enqueue blocked
  ~6.3 s then rejected (`P0001`), 0 jobs; enqueue-wins → revoke blocked ~6.1 s
  until enqueue committed, 1 job created while verified.
- **Cleanup/safety:** 0 fixture residue, 0 orphan audit runs, migration recorded
  exactly once, production never contacted, no service-role/token/challenge value
  printed. Rollback (`..._rollback_TEST_ONLY.sql`) authored, **not used**.
- **Lock:** formal `P1b — Verified-only Crawl Enqueue Enforcement` entry added to
  `MODULE_LOCKS.md` (2026-07-19). **No further P1b implementation work is required.**

## 5. TEST state

- `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`) carries the applied P1a + 16C–16H +
  P1b schema and passes all listed verifications. Migration history is clean
  (P1b recorded once). No fixture residue.

## 6. Production state

- **UNTOUCHED.** No migration, RPC, worker, or config has been applied to any
  production project. Cloud Run has **not** been deployed. This is a hard invariant.

## 7. Optional / deferred items (not started; each needs separate approval)

- **Production-promotion of the crawler + P1a + P1b stack** — planning/preflight
  not started (see §8; this is the recommended next major step).
- **Locked-UI defense-in-depth for verified-only crawl initiation** — an optional,
  separately-approved follow-up touching the locked crawl-UI to pre-block a crawl
  before the server rejects it. Server-side enforcement (P1b) already makes this
  non-blocking. Requires the Crawler 16C–16H additive-extension procedure.
- **Reports v1 (Stages 1–3) — DONE, not a deferred item.** COMPLETE + LOCKED
  (2026-07-20; committed `b976340`, pushed). See §1 (Reports rows, now **LOCKED**)
  for the per-stage status and `docs/markdown/MODULE_LOCKS.md` (Reports v1 entry)
  for the protected contracts. Migration range `20260720120035`–`20260720120038`;
  full SQL/authz/idempotency + true two-session advisory-lock concurrency + operator
  browser acceptance all PASS on `Digi_SEO_Test`. **Only these Reports features
  remain deferred/UNLOCKED (out of scope, not defects):** CSV export, report
  history, scheduling, email delivery, public/secure sharing, period comparison.
- **Mobile navigation drawer** — none exists today (pre-existing gap; sidebar is
  `hidden md:block`). Out of scope until prioritized.
- **Wave-3 locked-module contextual Help links** (P1a panel, crawl UI, Page
  Performance, Stage 6) — deferred; each needs its own approval + regression.

## 8. Exact recommended next workstream + first step

- **Immediate next step:** **Competitor Benchmarking Stage 2B is COMPLETE —
  backend (Stage 2A) TEST-applied + concurrency-verified, frontend (Stage 2B)
  implemented + unit-tested + AUTHENTICATED OPERATOR-ACCEPTED, all on
  2026-07-24** (see §1 Competitor Stage 2B row for full evidence): owner/admin/
  team_member generation all PASS against `Digi_SEO_Test` with real TEST
  accounts and real browser sessions (network-observed RPC calls, canonical
  reload, repeated-refresh stability, no duplicates, truthful `estimated`
  provenance); client correctly denied both in the UI (control disabled with
  the role tooltip) and at the backend (direct RPC attempt → `P0001`, non-leaking
  message); error path shows an actionable message with no mock fallback and
  persisted data left intact; responsive + regression checks clean. **Stage 2B
  is ready for commit.** The Competitor module stays **NOT locked** — a lock is
  a separate decision requiring explicit approval/review of this acceptance
  evidence, not an automatic next step.
- **Recommended next major / infrastructure step (separate track):**
  **production-promotion planning / preflight** for the crawler + P1a + P1b stack.
- **Selection between the two tracks is pending operator direction.**
- **Production-promotion first step:** author a *planning-only* production-promotion preflight
  document (no DB action, no deploy) that enumerates and gates: production
  migration order + rollback plan for P1a/16C–16H/P1b; secrets management +
  service-role handling for the worker; worker deployment runtime; Cloud Run
  frontend deploy + the still-deferred container-runtime verification; usage/
  subscription enforcement; rate limits; monitoring/alerting; and the
  `BACKEND_MILESTONE_HANDOFF.md` §5 production-gating checklist. It must reuse the
  established plan → approve → apply-to-TEST-equivalent → verify → sign-off
  pattern and require explicit approval before any production action.
- **No stale "P1b pending" language** appears anywhere in this package: P1b is
  COMPLETE, TEST-APPLIED, VERIFIED, and MODULE-LOCKED.
