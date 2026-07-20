# Digibility SEO Module — Backend Milestone Handoff

**Audience:** developer, technical lead, or a future AI coding agent picking up this project.
**Purpose:** a single-file status handoff for the Supabase backend build (Phase 12C–12G, plus the Stage 4 Page Performance Tracker addendum from Phase 14A.1 and the Stage 5 Decline Diagnosis Engine addendum from Phase 14B.1).

> **Single source of truth for the overall current status:** `CURRENT_PROJECT_STATUS.md`. **Documentation map / what-to-read-first:** `PROJECT_DOCUMENTATION_INDEX.md`. This handoff focuses on the **backend**; frontend service-wiring detail lives in `SERVICE_LAYER_WIRING_PLAN.md` and the `PHASE_*` notes.

---

## 1. Executive Summary

- **Completed (backend):** Stages 1–5 of the Supabase backend (access/module + workspaces + websites; audit/recommendations/approval; Content Studio; Page Performance Tracker; Decline Diagnosis Engine) are written, reviewed, and applied to a **fresh/disposable TEST Supabase project**.
- **Verified:** All five stages passed dry-run, structural checks (tables/RLS/functions/policies/triggers/storage/views), and dedicated SQL smoke tests with **all `PASS`, no known `FAIL`**. Stage 5 additionally passed a dedicated pre-apply safety review.
- **Frontend service wiring is complete through Phase 14B.2** (see `SERVICE_LAYER_WIRING_PLAN.md`): Stages 1–3 wired in Phases 13A–13F, Stage 4 (Page Performance) in Phase 14A.2, Stage 5 (Decline Diagnosis) in Phase 14B.2 — every wired service sits behind the mock/Supabase data-mode adapter, with **mock mode preserved as the default and as the fallback**. Page Performance and Decline Diagnosis were **live-tested signed-in** against the TEST project's UI seed data.
- **Test data seeded + verified on TEST:** base UI seed dataset, Stage 4 Page Performance UI seed extension, and Stage 5 Decline Diagnosis UI seed extension (**8 diagnoses / 20 evidence rows / 6 current-view rows**).
- **Production has not been touched.** No production migration, no production data, no production connection. Production apply remains gated (see §5).

> **Current backend-state addendum (2026-07-16 — post P1a Step 1).** This
> handoff's §3/§6 inventory covers **Stages 1–5 only**; the TEST backend has
> since grown additively. Reconciled against the authoritative migration set and
> `CURRENT_PROJECT_STATUS.md`:
> - **Migration range:** `20260711120001` … `20260716120033` — **33 migration
>   files**, all applied to `Digi_SEO_Test` (**TEST only**); **production
>   untouched**.
> - **Beyond Stages 1–5 (additive):** **Stage 6** (Off-Page Authority + AI
>   Visibility, `…120017`–`…120024`: **8 tables** + transition/create RPCs —
>   LOCKED implemented scope); **crawler Phases 16C–16H** (`…120025`–`…120030`:
>   **9 crawler-domain tables** + guarded/worker RPCs + audit-finalization —
>   LOCKED implemented scope); **P1a Step 1** (`…120031`).
> - **P1a Step 1 additions (`20260716120031_seo_p1a_step1_ownership_verification.sql`):**
>   **2 additive tables** — `seo_ownership_verifications` + append-only
>   `seo_ownership_verification_events` — plus **1 trigger function**
>   `seo_ownership_verification_integrity()` (reuses the shared
>   `set_updated_at()`). **0 RPCs, 0 views.** Default-deny-write RLS
>   (workspace-member SELECT only; no customer INSERT/UPDATE/DELETE; audit
>   immutable). TEST-verified; production untouched. See
>   `P1A_STEP1_OWNERSHIP_VERIFICATION_DB_CONTRACT.md`.
> - **P1a Step 2A additions (`20260716120032_seo_p1a_step2a_ownership_verification_rpcs.sql`):**
>   **4 guarded customer RPCs** (`seo_ownership_verification_initiate` /
>   `recheck` / `reverify` / `revoke`) + **3 internal helpers** (host-parse,
>   strong token, shared authz). **0 tables, 0 views.** All 4 RPCs SECURITY
>   DEFINER + `search_path=public`, `authenticated`-only, owner/admin-gated
>   server-side (no global-admin override — that is Step 2B); no status RPC
>   (direct RLS read). Crawler RPCs non-regression-verified. TEST-verified;
>   production untouched. See `P1A_STEP2A_OWNERSHIP_VERIFICATION_RPCS.md`.
> - **P1a Step 2B additions (`20260716120033_seo_p1a_step2b_ownership_verification_service_rpcs.sql`):**
>   **1 internal table** (`seo_ownership_verification_claims`, global-admin-read-
>   only claim/lease ledger; open-claim unique index) + **3 RPCs** —
>   `seo_ownership_verification_claim` & `record_result` (**service_role only**)
>   and `admin_override` (authenticated, internally global-admin-gated). **0
>   views.** Lease model mirrors Phase 16D on a separate ownership-only table (no
>   crawler object reused/modified); no existing policy modified. Crawler RPCs
>   non-regression-verified (16C–16H standalone ALL PASS; worker 47/47).
>   TEST-verified; production untouched. See
>   `P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`.
> - **Recalculated current totals (CREATE TABLE across all 33 migrations):**
>   **51 tables** (Stages 1–5 = 31; Stage 6 = 8; crawler 16C–16H = 9; P1a
>   Step 1 = 2; P1a Step 2B = 1) + **2 views** (`seo_page_performance_latest`,
>   `seo_decline_diagnoses_current`) + **1 private storage bucket** — all
>   additive; none alter Core. **RPC totals are not restated as one grand
>   number here** (customer RPCs, service-role worker functions, and trigger
>   functions differ across Stage 6 + the crawler); they are enumerated in
>   `MODULE_LOCKS.md` and the owner docs. **P1a Step 1 added 0 RPCs.**
> - **Current milestone:** **Production Readiness A** active; **P1a Step 1
>   complete + TEST-verified; P1a overall NOT complete; crawl authorization
>   unchanged; P1b excluded; production untouched. P1a Steps 2A (guarded customer
>   RPCs) + 2B (service-role claim/result + global-admin override) complete +
>   TEST-verified. P1a Step 3 (isolated DNS-TXT verification worker module) is
>   also complete + TEST-verified — **code-only** under
>   `crawler-worker/**` (no migration/schema/RPC; reuses the Step 2B RPCs;
>   approved additive extension noted in `MODULE_LOCKS.md`; worker suite 74/74;
>   16C–16H standalone ALL PASS). See `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`.
>   P1a Step 4 (frontend ownership-verification service/types/hooks/mock) is also
>   complete — **frontend-only, no DB/migration/RPC change** (RLS read of the
>   Step-1 table + Step 2A RPC writes; no UI; `tsc`/`build` clean; non-regression
>   ALL PASS). See `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md`.
>   P1a Step 5 (Websites/onboarding ownership-verification UI) is also implemented
>   — **frontend-only, no DB/RPC/worker/crawl change** (`OwnershipVerificationPanel`
>   in `WebsiteCard`; `tsc`/`build` clean; mock-mode browser-validated;
>   non-regression ALL PASS). **Authenticated TEST role/RPC validation PENDING**
>   (operator follow-up for Step 6). See `P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md`.
>   P1a Step 6 (validation + full regression + sign-off) is complete: **verdict
>   `P1A IMPLEMENTED — OPERATOR ACCEPTANCE PENDING`** — all automated P1a + locked
>   16C–16H + Stage 6 regressions PASS; worker 74/74; security 9/9; no defect;
>   backend role matrix proven via SQL; PENDING operator items = authenticated
>   *browser* matrix (no TEST creds here) + real *worker binary* run (no
>   service-role key here); Page-Performance smoke is a psql-runner evidence
>   limitation (contract intact). **P1a NOT yet module-locked.** No DB/code change
>   in Step 6. See `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`.**
> - **Checkpoint update (2026-07-17, frontend + DB-state only; no migration/schema change):**
>   the one open acceptance item on the customer UI — **Step 2.8 double-submit — is now
>   ACCEPTED PASS** (final visible bounded post-action lock in
>   `OwnershipVerificationPanel.tsx`; the retired "one-RPC-per-arbitrary-burst" criterion
>   is not a failure). **A3 DB integrity proof** (one `dns_txt` row for `digibility.ai`
>   `fb98d59c-…`) and **pending-record cleanup** are **COMPLETE** — `digibility.ai` and the
>   Stage-5 smoke fixture `77777777-…-b1` were both **revoked via the authenticated
>   customer UI** (append-only history preserved), so the earlier "Step 2B/Step 3 SQL
>   DEFERRED until leftover pending cleared" note is **resolved** (those SQL regressions are
>   now UNBLOCKED but not yet re-run). **P1a overall remains OPERATOR-ACCEPTANCE-PENDING and
>   NOT module-locked** (authenticated browser role matrix + real worker binary still
>   outstanding). Authoritative status: `CURRENT_PROJECT_STATUS.md`; details:
>   `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §9/§10.
>   The next milestone (separately approved, additive to locked 16C–16H) is
>   **P1b — verified-only crawl enqueue enforcement** (not started).
> - **Checkpoint update (2026-07-18, TEST-only SQL regression re-run; no migration/schema/code
>   change):** the P1a **Step 2B + Step 3 SQL regressions** — previously unblocked by the
>   2026-07-17 revoke-cleanup but not yet re-executed — were **re-run on `Digi_SEO_Test`**
>   (ref `snyzotgwwfomgafrsvfm`) after a read-only eligibility diagnostic confirmed **0**
>   `pending`/`failed` ownership-verification rows. `supabase/test/seo_p1a_step2b_ownership_verification_service_rpcs_verification.sql`
>   and `supabase/test/seo_p1a_step3_worker_dns_verification_integration.sql` both returned
>   their explicit **ALL PASS** sentinels; each script's own teardown + locked-crawler/
>   Page-Inventory/Stage-6 isolation assertions passed (both single-transaction,
>   self-cleaning, net-nothing on success). **This closes the "UNBLOCKED but not yet
>   re-run" follow-up.** No source/migration/SQL/worker/frontend/config file changed;
>   production untouched. This repository copy has no `.git` directory in this execution
>   environment, so no git-status/commit evidence is available (environment limitation
>   only). **P1a remains OPERATOR-ACCEPTANCE-PENDING and NOT module-locked** — the two
>   outstanding operator items (authenticated browser role matrix; real `verify-once`
>   worker binary run) are unchanged. Authoritative status: `CURRENT_PROJECT_STATUS.md`;
>   details: `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §10 (2026-07-18 entry).
> - **Checkpoint update (2026-07-18, authenticated browser acceptance; no migration/schema/
>   code change):** the P1a **authenticated browser role matrix** was executed on
>   `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`) — **COMPLETE = PASS**. Operator-executed
>   logged-in click-through of the Step 5 UI for **owner, admin, team_member, and client**,
>   each followed by sign-out: owner's `Verify ownership` on `digibility.ai` issued exactly
>   one `seo_ownership_verification_initiate` request (HTTP 200), UI moved to **Verification
>   pending** and persisted through a hard refresh; admin's `Check again` on the persisted
>   pending state issued exactly one `seo_ownership_verification_recheck` request (HTTP 200),
>   status remained pending; team_member and client both saw pending status with **no**
>   ownership action buttons and the read-only role message, with Network evidence
>   confirming **no** initiate/recheck/reverify/revoke request fired for either role; every
>   sign-out redirected to `/seo/login` and removed protected content; status was read live
>   from Supabase across every role switch (no stale cross-user state). **No defect found;
>   no source/migration/SQL/worker/frontend/config file changed.** DNS challenge values from
>   any screenshot evidence are not reproduced here. **This closes the authenticated browser
>   role matrix as an open P1a acceptance item.** **P1a remains OPERATOR-ACCEPTANCE-PENDING
>   and NOT module-locked** — the **sole remaining operator item** is the real
>   `verify-once` **worker binary** run against `Digi_SEO_Test` (needs
>   `SUPABASE_SERVICE_ROLE_KEY`). Authoritative status: `CURRENT_PROJECT_STATUS.md`; details:
>   `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §3 + §10 (2026-07-18 entry).

---

## 2. Product Context

Digibility SEO Intelligence is a paid module inside the Digibility platform (an AI-powered visibility management platform), built independently and reusing Digibility Core's auth, UI, and design system. It is an **SEO execution cockpit**, not a keyword-research clone: website setup → onboarding → technical audits → recommendations → approval queue → content studio, with future modules for page performance, off-page authority, AI visibility, competitor benchmarking, a 90-day roadmap, expert support, and reporting. Every SEO record links to a website URL; SEO roles (owner/admin/team_member/client) are workspace-scoped, not platform roles.

---

## 3. Current Backend Status

### Stage 1 — Access, Workspaces, Websites (Phase 12C)
- **Migration files:** `20260711120001_seo_stage1_access_module.sql`, `20260711120002_seo_stage1_workspaces.sql`, `20260711120003_seo_stage1_websites.sql`
- **Tables created (9):** `user_module_access`, `seo_plan_limits`, `seo_subscriptions`, `seo_usage_events`, `seo_workspaces`, `seo_workspace_members`, `seo_websites`, `seo_business_onboarding`, `seo_connection_status`
- **Helper functions (6):** `set_updated_at`, `seo_is_global_admin`, `has_seo_module_access`, `is_seo_workspace_member`, `seo_role_in`, `can_manage_seo_workspace` (+ `seo_workspace_add_owner_member` trigger fn)
- **RLS/policies:** enabled + policies on all 9 tables; client read-only on website/onboarding/connection; subscription writes global-admin-only in Stage 1
- **Test verification:** ✅ dry-run + applied + structural checks passed on the fresh test project (see §4)

### Stage 2 — Audit, Recommendations, Approval Queue (Phase 12E)
- **Migration files:** `20260711120004_seo_stage2_audit.sql`, `20260711120005_seo_stage2_recommendations.sql`, `20260711120006_seo_stage2_approval.sql`
- **Tables created (6):** `seo_audit_runs`, `seo_audit_issues`, `seo_recommendations`, `seo_approval_items`, `seo_approval_comments`, `seo_approval_activity`
- **RPCs/functions (5):** `seo_is_high_risk_category(text)`, `seo_run_audit(uuid)` RPC, `seo_supersede_recommendation(uuid,uuid)`, `seo_role_of(uuid,uuid)`, `seo_approval_transition(uuid,text,text)` RPC
- **RLS/policies:** enabled + policies on all 6 tables; append-only comments/activity; high-risk-category derivation is trigger-enforced and non-forgeable
- **Smoke test result:** ✅ `supabase/test/seo_stage2_smoke_test.sql` — all `PASS`, no known `FAIL`

### Stage 3 — Content Studio (Phase 12G)
- **Migration files:** `20260711120007_seo_stage3_content_plan.sql`, `20260711120008_seo_stage3_content_drafts.sql`, `20260711120009_seo_stage3_content_assets.sql`
- **Tables created (11):** `seo_content_opportunities`, `seo_content_keyword_plans`, `seo_content_competitor_summaries`, `seo_content_wireframes`, `seo_content_format_inputs`, `seo_content_drafts`, `seo_content_draft_sections`, `seo_content_section_revisions`, `seo_content_comments`, `seo_content_activity`, `seo_content_assets`
- **RPCs/functions (3):** `seo_content_assert_same_workspace()`, `seo_content_client_can_see_draft()`, `seo_content_transition(uuid,text,text)` RPC
- **Storage bucket:** private `seo-content-assets` (`public=false`, 20 MB limit, 5-MIME allowlist)
- **RLS/storage policies:** RLS on all 11 tables + `storage.objects` SELECT/INSERT policies (workspace-path-scoped)
- **Smoke test result:** ✅ `supabase/test/seo_stage3_content_studio_smoke_test.sql` — all `PASS`, no known `FAIL`

### Stage 4 — Page Performance Tracker (Phase 14A.1)
- **Migration files:** `20260711120010_seo_stage4_page_inventory.sql`, `20260711120011_seo_stage4_page_keywords.sql`, `20260711120012_seo_stage4_performance_snapshots.sql`, `20260711120013_seo_stage4_performance_latest_view.sql`
- **Tables created (3):** `seo_page_inventory`, `seo_page_keywords`, `seo_page_performance_snapshots`
- **Views created (1):** `seo_page_performance_latest` (`security_invoker = true` — inherits the underlying snapshots table's RLS at query time, not `SECURITY DEFINER`)
- **RLS/policies:** enabled + 6 policies (one `_select` + one `_write` per table) on all 3 tables, matching the exact `seo_audit_issues` shape from Stage 2 — any workspace member (incl. client) reads, only owner/admin/team_member (+ global admin) write
- **Test verification:** ✅ dry-run + applied + structural checks + smoke test passed on the fresh test project (see §4)
- **Product intent:** page inventory, mapped keywords per page, periodic clicks/impressions/CTR/average-position snapshots with period-over-period deltas, `movement_status` (improving/stable/declining/new/no_data), and a `diagnosis_hint` seam for a future Decline Diagnosis module. `source` (`manual_seed`/`gsc`/`ga4`/`system`/`import`) is a placeholder column only — **no real GSC/GA4 integration, no external API calls, no cron jobs, no crawler** ship in Stage 4.

### Stage 5 — Decline Diagnosis Engine (Phase 14B.1)
- **Migration files:** `20260711120014_seo_stage5_decline_diagnoses.sql`, `20260711120015_seo_stage5_decline_diagnosis_evidence.sql`, `20260711120016_seo_stage5_decline_diagnosis_current_view.sql`
- **Tables created (2):** `seo_decline_diagnoses`, `seo_decline_diagnosis_evidence`
- **Views created (1):** `seo_decline_diagnoses_current` (`security_invoker = true` — inherits the base tables' RLS at query time, not `SECURITY DEFINER`)
- **RPC created (1):** `seo_create_decline_diagnosis_from_snapshot(...)` — a deterministic, no-heuristic `SECURITY DEFINER` helper that snapshots page/keyword/url/movement from a Stage 4 performance snapshot, inserts a caller-classified diagnosis, and copies stored Stage 4 metrics into evidence rows. Enforces owner/admin/team_member (or global admin) on the snapshot's workspace before writing (clients/non-members rejected even though `EXECUTE` is granted to `authenticated`). No LLM, crawler, external API, or diagnosis heuristics in SQL.
- **RLS/policies:** enabled + 4 policies (one `_select` + one `_write` per table) on both tables, matching the exact `seo_recommendations`/`seo_page_performance_snapshots` shape — any workspace member (incl. client) reads, only owner/admin/team_member (+ global admin) write
- **Test verification:** ✅ pre-apply safety review + dry-run + applied + structural checks + smoke test passed on the test project (see §4). **Backend applied to TEST only** (never production). The Stage 5 UI seed extension has since been created + verified on TEST (8 diagnoses / 20 evidence / 6 current-view rows), and frontend service wiring is complete (Phase 14B.2, live-tested) — see `SERVICE_LAYER_WIRING_PLAN.md` §15 and `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md`.
- **Product intent:** business-first "why this page is losing ranking/traffic" records with `diagnosis_type` (ctr_drop/ranking_decline/clicks_decline/impressions_decline/content_freshness/indexing_issue/cannibalization_risk/intent_mismatch/competitor_improvement/technical_performance/no_data/mixed_signals), severity/confidence/priority/status lifecycle, a suggested owner, and structured evidence rows. `linked_recommendation_id` is a nullable seam only — the diagnosis→recommendation/support conversion flow is **not** built in Stage 5.

---

## 4. Supabase Test Project Verification Summary

**Stage 1**
- [x] Dry-run passed
- [x] Applied to fresh test Supabase project
- [x] 9 Stage 1 tables visible
- [x] RLS true for 9 tables
- [x] 6 Stage 1 helper functions visible

**Stage 2**
- [x] Dry-run passed
- [x] Applied to fresh test Supabase project
- [x] 6 Stage 2 tables visible
- [x] RLS true for 6 tables
- [x] 5 Stage 2 functions visible
- [x] Stage 2 smoke test passed (`PASS`, no known `FAIL`)

**Stage 3**
- [x] Dry-run passed
- [x] Applied to fresh test Supabase project
- [x] 11 Stage 3 tables visible
- [x] RLS true for 11 tables
- [x] 3 Stage 3 functions visible
- [x] Private `seo-content-assets` bucket visible
- [x] Stage 3 table policies/triggers/storage object policies visible
- [x] Stage 3 smoke test passed (`PASS`, no known `FAIL`)

**Stage 4**
- [x] Dry-run passed
- [x] Applied to fresh test Supabase project
- [x] 3 Stage 4 tables visible: `seo_page_inventory`, `seo_page_keywords`, `seo_page_performance_snapshots`
- [x] RLS true for 3 tables
- [x] 1 latest-snapshot view visible: `seo_page_performance_latest`
- [x] 6 policies visible: `seo_page_inventory_select`, `seo_page_inventory_write`, `seo_page_keywords_select`, `seo_page_keywords_write`, `seo_page_performance_snapshots_select`, `seo_page_performance_snapshots_write`
- [x] Stage 4 smoke test passed after a smoke-test-harness fix (`PASS`, no known `FAIL` — the initial failure was a smoke-test simulation defect, not a migration/RLS defect; see `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`)
- [ ] Stage 4 frontend service wiring — **not started**
- [ ] Stage 4 UI test dataset seed extension — **not created**

**Stage 5**
- [x] Pre-apply safety review passed (SECURITY DEFINER RPC reviewed and accepted; no files changed by the review; no migration defect found)
- [x] Dry-run passed
- [x] Applied to test Supabase project
- [x] 2 Stage 5 tables visible: `seo_decline_diagnoses`, `seo_decline_diagnosis_evidence`
- [x] RLS true for both tables
- [x] 1 current view visible: `seo_decline_diagnoses_current`
- [x] 1 RPC visible: `seo_create_decline_diagnosis_from_snapshot`
- [x] 4 policies visible: `seo_decline_diagnoses_select`, `seo_decline_diagnoses_write`, `seo_decline_diagnosis_evidence_select`, `seo_decline_diagnosis_evidence_write`
- [x] Stage 5 smoke test passed after a smoke-test call-signature fix (`PASS`, no red ERROR popup; reached the `STAGE 5 SMOKE TEST COMPLETE` marker — the initial failure was a smoke-test call passing 11 args instead of the correct 10-argument RPC signature, fixed in the smoke-test file with explicit `::uuid`/`::text` casts; **not** a migration/RPC defect; see `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` §12)
- [ ] Stage 5 frontend service wiring — **not started**
- [ ] Stage 5 UI seed extension — **not created**

Full detail: `SUPABASE_MIGRATION_STAGE_1_NOTES.md`, `SUPABASE_MIGRATION_STAGE_2_NOTES.md`, `SUPABASE_MIGRATION_STAGE_3_CONTENT_STUDIO_NOTES.md`, `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`, `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_PLAN.md`, `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md`, `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_PLAN.md`, `SUPABASE_STAGE_2_VERIFICATION_GUIDE.md`, `SUPABASE_STAGE_3_CONTENT_STUDIO_VERIFICATION_GUIDE.md`.

---

## 5. Production Status

- **Production has not been touched.**
- **No production migrations have been applied.** All work above ran only on a disposable/fresh test Supabase project.
- **Production apply requires, before it happens:**
  1. Target project confirmation (correct shared Digibility Supabase project)
  2. Branch or backup strategy in place
  3. Final migration review
  4. Developer/technical owner sign-off
  5. Rollback/restore plan

---

## 6. Tables and Backend Capabilities Created

**Stage 1 (9 tables)**
- `user_module_access` · `seo_plan_limits` · `seo_subscriptions` · `seo_usage_events`
- `seo_workspaces` · `seo_workspace_members` · `seo_websites` · `seo_business_onboarding` · `seo_connection_status`

**Stage 2 (6 tables)**
- `seo_audit_runs` · `seo_audit_issues` · `seo_recommendations` · `seo_approval_items` · `seo_approval_comments` · `seo_approval_activity`

**Stage 3 (11 tables + 1 storage bucket)**
- `seo_content_opportunities` · `seo_content_keyword_plans` · `seo_content_competitor_summaries` · `seo_content_wireframes` · `seo_content_format_inputs`
- `seo_content_drafts` · `seo_content_draft_sections` · `seo_content_section_revisions`
- `seo_content_comments` · `seo_content_activity` · `seo_content_assets`
- Storage bucket: **`seo-content-assets`** (private)

**Stage 4 (3 tables + 1 view)**
- `seo_page_inventory` · `seo_page_keywords` · `seo_page_performance_snapshots`
- View: **`seo_page_performance_latest`** (`security_invoker = true`, not `SECURITY DEFINER`)

**Stage 5 (2 tables + 1 view + 1 RPC)**
- `seo_decline_diagnoses` · `seo_decline_diagnosis_evidence`
- View: **`seo_decline_diagnoses_current`** (`security_invoker = true`, not `SECURITY DEFINER`)
- RPC: **`seo_create_decline_diagnosis_from_snapshot(...)`** (`SECURITY DEFINER`; manager-only role check inside; deterministic, no LLM/crawler/heuristics)

**Total (Stages 1–5 scope): 31 tables + 2 views + 1 RPC + 1 private storage bucket**, all additive, none altering Core or the reference Digibility app. _(This §6 total is the Stages-1–5 inventory only; for the current whole-backend totals incl. Stage 6, the crawler, and P1a Step 1 — **50 tables + 2 views + 1 storage bucket** across migrations `…120001`–`…120031` — see the "Current backend-state addendum" under §1.)_

---

## 7. Key Security / RLS Decisions

- Same Supabase Auth (`auth.users`) as Digibility Core — **no separate SEO auth system**.
- SEO roles (`owner`/`admin`/`team_member`/`client`) live in `seo_workspace_members`, never on `profiles.role`.
- Clients have restricted access:
  - Cannot approve high-risk technical changes.
  - Cannot publish (no live-publish path exists for any role).
  - Cannot change URLs, redirects, canonical tags, noindex, robots.txt, or sitemap.
- Comments, activity, and section revisions are **append-only** where applicable (no update/delete policy for anyone).
- Content assets live in a **private** Storage bucket only — **no public/anonymous file access**.
- No live CMS publishing path anywhere in the schema.
- No crawler or LLM integrations yet — issue/recommendation/draft generation is a service-role/system responsibility, not implemented in these migrations.

---

## 8. Verified Smoke-Test Coverage

- **Stage 2** (`seo_stage2_smoke_test.sql`): `seo_run_audit` trigger behavior (single `is_latest`, non-member rejection), the full approval-transition matrix per role (owner/admin/team_member/client), high-risk-category blocking (non-forgeable, cross-workspace guard), append-only comments/activity with `actor_role_snapshot`.
- **Stage 3** (`seo_stage3_content_studio_smoke_test.sql`): full content workflow transitions via `seo_content_transition`, client review status-gates (`wireframe_client_review`/`draft_client_review` only), draft/section visibility rules, append-only comments/activity, asset MIME allow/block (PDF/DOCX/PNG/JPEG/WEBP allowed; SVG/ZIP/EXE blocked), private-bucket/storage-policy checks, non-member isolation.
- **Stage 4** (`seo_stage4_page_performance_smoke_test.sql`): owner/admin/team_member/client SELECT access on all 3 tables + the latest-snapshot view; non-member isolation (0 rows); client INSERT denial (RLS `WITH CHECK`) and client direct-UPDATE denial (0 rows affected); manager (team_member) insert of page inventory, keywords, and performance snapshots; active-page-URL and snapshot-combo uniqueness rejection; `seo_page_performance_latest` correctly resolves to the newest snapshot per page/keyword; CHECK-constraint rejection of invalid `ctr`, `movement_status`, `device`, and `source` values. One smoke-test-harness defect (RLS-read checks not switching to the `authenticated` role) was found and fixed mid-verification — not a migration/RLS defect; see `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md` for detail.
- **Stage 5** (`seo_stage5_decline_diagnosis_smoke_test.sql`): owner/admin/team_member/client SELECT access on both tables + the current view; non-member isolation (0 rows); client INSERT denial (diagnoses + evidence), client direct-UPDATE denial (0 rows), and client rejection from the `seo_create_decline_diagnosis_from_snapshot` RPC; manager (team_member) diagnosis insert and (admin) evidence insert; the RPC deterministically creating a diagnosis + 4 auto-derived evidence rows with auto-snapshotted workspace/page; active-combo uniqueness rejection; CHECK-constraint rejection of invalid `diagnosis_type`/`severity`/`status`/`suggested_owner`/out-of-range `confidence_percentage`/evidence `source`; the current view excluding a dismissed diagnosis. One smoke-test call-signature defect (an 11-argument RPC call vs the correct 10-argument signature) was found and fixed mid-verification — not a migration/RPC defect; see `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` §12 for detail.

---

## 9. What Is Still Mock / Not Wired

> **Wiring status has moved on since this doc's original backend-only framing.** Service-layer wiring is now complete through Phase 14B.2 (Stages 1–5), all behind the mock/Supabase data-mode adapter. The items below reflect what is **genuinely still mock/placeholder or unbuilt**, not the wiring status of already-wired reads/writes. See `SERVICE_LAYER_WIRING_PLAN.md` and `CURRENT_PROJECT_STATUS.md` for the authoritative wiring picture.

- **Mock mode remains the default and the fallback.** With `VITE_SEO_DATA_MODE` unset/`mock`, every service still uses local mock adapters exactly as before; in `supabase` mode, wired services read/write the 31 Supabase tables and gracefully fall back to mock on error. Mocks were never removed.
- **Some modules beyond Stage 5 are still mock/frontend-only.** Off-Page Authority, AI Visibility, Competitors, Roadmap, and Reports have no backend stage yet and run entirely on mock data. Refresh Recommendations on the Decline Diagnosis page also remain mock/demo (no Stage 5 backend table for them).
- **Decline Diagnosis is read-only in the UI.** No diagnosis create/update/delete path is wired; the Stage 5 `seo_create_decline_diagnosis_from_snapshot` RPC exists and is smoke-tested but is **not** called from the UI. No diagnosis-to-recommendation conversion is wired (`linked_recommendation_id` is a backend seam only).
- No real crawler (technical audits are not yet executing real checks; Stage 4 page inventory is hand-seeded, not crawler-discovered).
- No real LLM generation (drafts/wireframes are service-role placeholders in the schema, not generated content yet; Stage 5 diagnoses are hand-written demo seed rows, not model-generated).
- No real GSC/GA4/CMS/GBP integration (`seo_connection_status` holds placeholders only; Stage 4's `source` column accepts `gsc`/`ga4` as placeholder values only — all seeded rows use `manual_seed`).
- No real publishing — `ready_for_manual_publish` is a status marker with no executor.
- No production billing enforcement (`seo_subscriptions`/`seo_plan_limits` exist but no gateway/enforcement wiring).
- No real file-upload wiring in the UI yet (Storage bucket + policies exist; no upload flow built).
- **Admin final integration into the existing Digibility Admin Panel is still future work** — the current `/seo/admin-preview` is a temporary read-only composition, not the production admin surface.
- **No production apply yet** — Stages 1–5 are all **applied to the TEST project only**.

---

## 10. Recommended Next Technical Options

> **Stage 4 + Stage 5 are now fully complete end-to-end (backend + seed + wiring + live test).** The two addenda below are retained as a historical record of how each landed; their "no wiring yet / recommended next step" wording described the state at the time each stage's backend first landed and has since been superseded. Current authoritative status: `CURRENT_PROJECT_STATUS.md`.
>
> **Stage 4 addendum (Phase 14A.1 → 14A.2):** Stage 4 (Page Performance Tracker) backend was written, applied, structurally verified, and smoke-tested on TEST (§3/§4, `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`). It has **since** been UI-seeded (verified) and service-wired in Phase 14A.2 (live-tested) — see `PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md`.
>
> **Stage 5 addendum (Phase 14B.1 → 14B.2):** Stage 5 (Decline Diagnosis Engine) backend was written, pre-apply safety-reviewed, dry-run, applied, structurally verified (2 tables, RLS true on both, 1 `security_invoker` view, 1 `SECURITY DEFINER` RPC, 4 policies), and smoke-tested on TEST (§3/§4/§8, `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` §12). It has **since** been UI-seeded (8 diagnoses / 20 evidence / 6 current-view rows, verified) and service-wired in Phase 14B.2 (live-tested, including two follow-up fixes: finder ranking + onboarding-gate order) — see `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` §10–§11.

**Option A — Continue backend Stage 5+ migrations**
Decline Diagnosis, Off-Page Authority, AI Visibility (next in the Section H staged order, now that Stage 4 is complete).

**Option B — Start service-layer wiring against test Supabase** ✅ *Recommended (Stage 4 UI seed + Page Performance wiring first)*
Replace mock adapters with real Supabase calls. Stages 1-3 have already been wired per `SERVICE_LAYER_WIRING_PLAN.md` (Phases 13A-13F); Stage 4 (Page Performance) is the next service to wire, after its UI test dataset seed extension.

**Option C — Prepare a production apply checklist**
Only after target-project confirmation, backup/branch strategy, and final review/sign-off (see §5).

**Historical recommendation (now completed): the Stage 4 track — seed realistic test data, then wire the service layer against the test project — was chosen and has since been carried through for both Stage 4 (Phase 14A.2) and Stage 5 (Phase 14B.2), each seeded, wired, and live-tested.** With five backend stages test-verified and wired, the open choices are now: continue with further backend stages (Off-Page Authority / AI Visibility / Competitors / Roadmap / Reports — none applied), or prepare a production-apply checklist (Option C). See `CURRENT_PROJECT_STATUS.md` for the current recommended next step.

> **Forward-looking note (Stage 6):** **Stage 6 — Off-Page Authority + AI
> Visibility/GEO** migration SQL has now been **authored** to the locked plan
> (`SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_PLAN.md` §0,
> `…_NOTES.md`). Files `…120017`–`…120023` — **8 tables** (opportunities,
> campaigns, campaign tasks, campaign↔opportunity junction, activity audit,
> AI prompt tracking (time-series), AI content gaps, AI mentions) **+ 2 guarded
> `SECURITY DEFINER` transition RPCs** for the Off-Page workflow. After a
> transaction-wrapped dry-run on TEST (rolled back), the 7 Stage 6 migrations have
> now been **APPLIED to the disposable TEST project `Digi_SEO_Test` (ref
> `snyzotgwwfomgafrsvfm`) via `supabase db push --linked`, and structurally
> verified** (`SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md` §7c):
> versions `…120017`–`…120023` are in the remote migration history; **8 tables,
> RLS on all 8, 3 functions** (2 transition RPCs + `seo_authority_campaign_opportunity_integrity`),
> the `trg_seo_authority_camp_opp_integrity` trigger, and policy shape **8 SELECT
> / 7 FOR ALL / 1 activity-INSERT / 0 activity-UPDATE-DELETE** — all as designed.
> It has **since been SMOKE-TESTED PASS** on TEST
> (`supabase/test/seo_stage6_offpage_ai_visibility_smoke_test.sql`, `99999999-`
> prefix, self-cleaning — `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md`
> §7d): manager inserts on all 7 writable tables, RLS role behavior (client
> read-only, nonmember isolated), both guarded transition RPCs (legal paths +
> illegal-jump/terminal/manager-only rejections + activity logging), junction
> integrity (PK dup + cross-workspace/website trigger rejection + cascades), the
> D7 soft-dup guard, prompt time-series, mention/gap CHECKs + prompt-delete
> cascade/set-null, and append-only activity — the test tore itself down (0 Stage 6
> rows remain). It has **since been UI-SEEDED + verified** on TEST
> (`supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`,
> `a6000000-` prefix, attached to the base UI seed workspace/website, `created_by`
> derived from members, idempotent — guide:
> `SUPABASE_STAGE6_OFFPAGE_AI_VISIBILITY_SEED_EXTENSION_GUIDE.md`): **9 opportunities
> / 4 campaigns / 11 tasks / 6 junction links / 5 activity / 9 prompt-tracking (incl.
> a 3-point time-series) / 6 content gaps / 13 mentions**, all `manual_seed` demo.
> Bugs found during authoring were fixed in the test/seed files (no migration
> defect; no migration SQL changed). **Stage 6 backend (applied + structurally
> verified + smoke-tested PASS + UI-seeded) is unchanged and complete.**
> **Service-wiring status (Phase 15A, frontend — see
> `SERVICE_LAYER_WIRING_PLAN.md` §16 and
> `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` for full detail):**
> `offPageService`/`aiVisibilityService` **read** functions are now wired to
> Stage 6 via `runWithServiceAdapter` (new `seoOffPageAuthoritySupabaseService.ts` /
> `seoAiVisibilitySupabaseService.ts`), mock mode unchanged and still the
> default/fallback. **Implemented, pending live test** — static validation
> (`tsc`/`build`) and no-session browser verification passed; a signed-in
> live test was not performed (no test-user password available this task).
> **Writes remain mock-only in every mode by design** — the current UI's
> status buttons don't map onto Stage 6's guarded transition RPCs' legal
> state machine yet (see wiring notes §7). **Production untouched.** Next
> module in the approved rollout order (Off-Page / AI Visibility before
> Competitor / Roadmap and Support / Reports) remains gated on Stage 6's own
> live-test + write-wiring follow-up, or can proceed independently per the
> approved order.

---

## 11. Suggested Service-Layer Wiring Order

1. Supabase environment setup (test project client/env vars)
2. Auth/session compatibility check (`auth.uid()` + `profiles` against SEO RLS helpers)
3. `websiteService` + `businessOnboardingService`
4. `auditService` + `recommendationService`
5. `approvalService`
6. `contentStudioService`
7. Storage asset metadata + signed URL flow
8. Dashboard summaries
9. Admin preview read-only wiring

---

## 12. Risks / Watchouts

- Production schema may differ from the fresh test project (drift risk) — reconcile before any production apply.
- `seo_is_global_admin` assumes `profiles.role IN ('super_admin','admin')`; confirm this still matches Core's current role enum before wiring.
- Service role is required for system-generated issues/recommendations/drafts (no crawler/LLM yet) — RLS intentionally gives no client/team generation path.
- Storage cleanup for soft-deleted assets is deferred to a later admin/service job — objects are not removed today.
- Local mock data and real Supabase data may diverge during the service-layer transition — convert one service at a time behind a per-service adapter flag.
- RLS must be exercised with **real** `auth.users` rows (not just SQL-simulated roles) before trusting it in the app.
- **Never expose the service role key in frontend code** — service-role actions belong server-side only.

---

## 13. Final Handoff Status

Backend foundations through Stage 5 (access/workspaces/websites, audit/recommendations/approval, Content Studio, Page Performance Tracker, Decline Diagnosis Engine) are **applied to the TEST project and verified**. **All five stages are now also wired into the frontend service layer** (Stages 1–3 in Phases 13A–13F, Stage 4 in Phase 14A.2, Stage 5 in Phase 14B.2 — see `SERVICE_LAYER_WIRING_PLAN.md`), each behind the mock/Supabase adapter with mock mode preserved. The Stage 4 and Stage 5 UI seed extensions have been created and verified on TEST, and Page Performance + Decline Diagnosis were live-tested signed-in. Production remains untouched and gated behind target-project confirmation, backup/branch strategy, final migration review, and explicit developer/technical owner sign-off (§5). **For the always-current one-page status, see `CURRENT_PROJECT_STATUS.md`.**
