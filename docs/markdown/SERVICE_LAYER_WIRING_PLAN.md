# SEO Module — Service-Layer Wiring Plan (Phase 13A + 13B + 13B.1 + 13C + 13D + 13E + 13F + 14A.2 + 14B.2)

**Phase 13A = foundation only.** No mock adapter was removed, no service was converted, and no production credentials were used. This document describes what was built and how to use it going forward.

**Phase 13B = first real wiring.** `websiteService` and `businessOnboardingService` now have working Supabase implementations behind the Phase 13A adapter, alongside their unchanged mock adapters. See §8 below. Every other service (`auditService`, `recommendationService`, `approvalService`, `contentStudioService`, dashboard, admin preview) is still mock-only.

**Phase 13B.1 = dev-only auth test harness.** A hidden `/seo/dev/auth-test` page lets a developer sign in with a real test-project user (email/password) to exercise the Phase 13B Supabase wiring under real authenticated RLS, instead of only the graceful-fallback path. See §9 below. No customer-facing auth UI was added.

**Phase 13C = audit + recommendation wiring.** `auditService` and `recommendationService` now read from Stage 2 (`seo_audit_runs`, `seo_audit_issues`, `seo_recommendations`) and can trigger a real audit run via the `seo_run_audit` RPC. See §10 below. Approval Queue, Content Studio, and everything after remain mock-only.

**Phase 13D = approval queue wiring.** `approvalService` now reads/writes Stage 2's `seo_approval_items` / `seo_approval_comments` via `seo_approval_transition` — never a direct status update. See §11 below. Content Studio and everything after remain mock-only.

**Phase 13E = Content Studio wiring.** `contentStudioService` now reads/writes Stage 3's content-plan/wireframe/draft tables and drives workflow status via `seo_content_transition`. See §12 below. Page Performance, Off-Page, AI Visibility, Competitors, Roadmap, Reports, and Admin remain mock-only.

**Phase 13F = Dashboard summary + Admin Preview read-only wiring.** `dashboardService.fetchTopPriorityFixes` and `fetchPendingApprovalsSummary` now read from already-wired Stage 2 tables (`seo_recommendations`, `seo_approval_items`) behind the standard adapter. A new, small `adminPreviewSummaryService.ts` composes already-wired service calls into a read-only summary for the temporary `/seo/admin-preview` route — no new direct Supabase queries, no writes. See §13 below. Page Performance, Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, and Reports remain mock-only unless already wired incidentally by a shared service.

**Backend note (Phase 14A.1, not a wiring phase):** Stage 4 (Page Performance Tracker — `seo_page_inventory`, `seo_page_keywords`, `seo_page_performance_snapshots`, `seo_page_performance_latest` view) was written, applied to the test Supabase project, smoke-tested, and UI-seeded (see `SUPABASE_MIGRATION_STAGE_4_PAGE_PERFORMANCE_NOTES.md`, `SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md`).

**Phase 14A.2 = Page Performance Tracker wiring.** `performanceService.fetchPagePerformance` and `fetchPageDetail` now read from Stage 4 behind the standard adapter, flattening the normalized page/keyword/snapshot tables back into the app's existing flat `PagePerformance` shape — no UI or type changes. `fetchPerformanceSummary` was updated to derive from the now-wired `fetchPagePerformance` instead of importing the mock adapter directly, so dashboard's `PagePerformanceSummaryCard` (which already called `fetchPerformanceSummary`) picks up real data for free. See §14 below. Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, and Reports remain mock-only.

**Backend note (Phase 14B.1, not a wiring phase):** Stage 5 (Decline Diagnosis Engine — `seo_decline_diagnoses`, `seo_decline_diagnosis_evidence`, `seo_decline_diagnoses_current` view, `seo_create_decline_diagnosis_from_snapshot` RPC) was written, pre-apply safety-reviewed, dry-run, applied to the test Supabase project, structurally verified, and smoke-tested (see `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` §12), then UI-seeded (see `SUPABASE_STAGE5_DECLINE_DIAGNOSIS_SEED_EXTENSION_GUIDE.md`).

**Phase 14B.2 = Decline Diagnosis Engine wiring.** `performanceService.fetchDeclineDiagnoses` and `fetchDiagnosisForPage` now read from Stage 5 behind the standard adapter (new `seoDeclineDiagnosisSupabaseService.ts`), mapping the richer backend model (`diagnosis_type`/`severity`/`priority`/`status`/`suggested_owner`) down into the app's existing flat `DeclineDiagnosis` shape — no UI or type changes. `DeclineDiagnosisPage.tsx` gained the same page-local cross-workspace fallback as `PagePerformancePage.tsx` (Phase 14A.2). See `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` for full detail.

**Backend note (Phase 15A, not a wiring phase):** Stage 6 (Off-Page Authority + AI Visibility/GEO — 8 tables + 2 transition RPCs) was written, dry-run, applied to the test Supabase project, structurally verified, and smoke-tested (see `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md`), then UI-seeded (see `SUPABASE_STAGE6_OFFPAGE_AI_VISIBILITY_SEED_EXTENSION_GUIDE.md`).

**Phase 15A = Off-Page Authority + AI Visibility/GEO wiring (read-only).** `offPageService`'s and `aiVisibilityService`'s **read** functions now read from Stage 6 behind the standard adapter (new `seoOffPageAuthoritySupabaseService.ts` / `seoAiVisibilitySupabaseService.ts`), deriving `AuthorityCampaign.opportunity_ids`/`.tasks`/`.progress_percentage` from Stage 6's normalized junction/task tables and preferring the normalized `seo_ai_mentions` table for brand/competitor summaries — no UI or type changes. Both `AuthorityBuilderPage.tsx` and `AiVisibilityPage.tsx` gained the same page-local cross-workspace fallback as `DeclineDiagnosisPage.tsx` (Phase 14B.2), applied from the start with the corrected trigger conditions. **Writes remain mock-only in every mode this phase** — the current UI's status buttons don't provide a complete path through Stage 6's guarded transition RPCs' legal state machine (see `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §7 for the full reasoning and recommended follow-up). **Implemented, pending live test** — static validation and no-session browser verification passed; a signed-in live test was not performed (no test-user password available). See `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` for full detail. **Read-only** — no diagnosis creation/update/delete is wired, and the `seo_create_decline_diagnosis_from_snapshot` RPC is not called (no UI needs it yet). `RefreshRecommendation`-related functions remain mock-only — Stage 5 has no backend table for them. Off-Page Authority, AI Visibility, Competitors, Roadmap, and Reports remain mock-only.

**Phase 15C = Off-Page Authority Opportunity Workflow writes — implemented and signed off.** `offPageService`'s opportunity status-change writes now call `seo_authority_opportunity_transition` — never a direct status UPDATE — via a new non-masking write helper mirroring the Phase 13D/13E pattern. `OpportunityCard.tsx` uses real `seo_workspace_members.seo_role`-based role gating and legal status-based button visibility, and renders unauthorized-but-legal actions disabled with an explanatory tooltip (hover + keyboard focus). Mock mode is unchanged/preserved. See §17 below and `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md` for the full sign-off record. **Campaign writes remain untouched and mock-only**, and **AI Visibility remains read-only** apart from its existing mock-only demo behavior — neither was in scope for this phase. Authenticated TEST browser validation confirmed all 7 opportunity legal actions' status/role behavior (6 via a successfully executed transition, `reject` via its correct role-gated disabled-state + tooltip). A Stage 6 final regression pass and campaign write wiring are still pending before the broader Off-Page Authority module can be locked — see `CURRENT_PROJECT_STATUS.md` §4/§6/§7 and `MODULE_LOCKS.md`.

**Phase 15D Step 1 = Off-Page Authority draft campaign creation — implemented, pending authenticated live-test.** `offPageService.createAuthorityCampaign` now calls a new `seoOffPageAuthoritySupabaseService.createSupabaseAuthorityCampaign` (via a new non-masking `runAuthorityCampaignWrite` helper, same pattern as Phase 15C) that inserts one `seo_authority_campaigns` row — `approval_status` left at its `draft` column default, never inserted as `pending_approval` — plus the selected opportunities' `seo_authority_campaign_opportunities` junction links and one generated `seo_authority_campaign_tasks` row per opportunity (label = that opportunity's own `suggested_action`, mirroring the existing mock task-generation behavior exactly, no invented behavior). No RPC exists for campaign creation, so client-side compensating cleanup (delete the campaign row, which CASCADEs away any partial child rows) handles the case where a junction/task insert fails after the campaign row was created — see §18 below for the full atomicity assessment. **Opportunity transitions (Phase 15C) are untouched by this step.** Campaign submission-for-approval, approve/reject/return-to-draft, and task-completion writes remain unbuilt and mock-only. `tsc --noEmit`/`npm run build` both pass; mock-mode regression was verified in a browser with no console errors. **Authenticated TEST live-test has not been performed** (no TEST credentials available this task) — see `CURRENT_PROJECT_STATUS.md` §4/§7 for the recommended next step.

> **Superseded by Phase 15D Step 1B:** the client-side compensating-cleanup
> approach described immediately above is no longer what the code does — it
> was replaced by a single atomic `seo_authority_campaign_create` RPC. See §18
> below for the current implementation. This paragraph is left as the
> historical record of Step 1's original approach.

**Phase 15D Step 2A = Off-Page Authority Draft → Pending Approval campaign transition — implemented and authenticated browser-validated.** `CampaignList.tsx` shows a "Submit for approval" button, wired through `offPageService.submitAuthorityCampaignForApproval(id, websiteId)` → the non-masking `runAuthorityCampaignTransitionWrite` helper (same pattern as `runAuthorityOpportunityWrite`/`runAuthorityCampaignWrite`) → `seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityCampaign`, which calls the **existing, already-TEST-verified** `seo_authority_campaign_transition` RPC with `p_action: "submit_for_approval"` — no backend change was needed. Visible only when `approval_status === "draft"` (hidden for `pending_approval`/`approved`/`rejected`); enabled for owner/admin/team_member, disabled + tooltipped ("Requires the owner, admin, or team member role.") for `client`, using the same disabled-focusable-wrapper tooltip pattern as `OpportunityCard.tsx` (Phase 15C). Mock mode preserved via `updateAuthorityCampaignStatus`. **Opportunity transitions and Step 1B campaign creation are untouched.** See §19 below for full detail.

**Phase 15D Step 2B = Off-Page Authority Pending Approval → Approved campaign transition — implemented and authenticated owner/admin browser-validated.** `CampaignList.tsx` shows an "Approve" button, wired through `offPageService.approveAuthorityCampaign(id, websiteId)` reusing the `runAuthorityCampaignTransitionWrite` helper and `transitionSupabaseAuthorityCampaign` Supabase function as Step 2A — just with `p_action: "approve"` (the `AuthorityCampaignTransitionAction` type was widened from one literal to `"submit_for_approval" | "approve"`) — no backend change was needed. Visible only when `approval_status === "pending_approval"` (hidden for `draft`/`approved`/`rejected`); enabled for owner/admin only, disabled + tooltipped ("Requires the owner or admin role.") for team_member/client, using the shared `CampaignActionButton` component. Mock mode preserved via `CAMPAIGN_ACTION_TO_MOCK_STATUS.approve`. **Opportunity transitions, Step 1B creation, and Step 2A submission are all untouched.** See §20 below for full detail.

**Phase 15D Step 2C = Off-Page Authority Pending Approval → Rejected campaign transition — implemented and authenticated owner/admin browser-validated.** `CampaignList.tsx` shows a "Reject" button, wired through `offPageService.rejectAuthorityCampaign(id, websiteId)` reusing the `runAuthorityCampaignTransitionWrite` helper and `transitionSupabaseAuthorityCampaign` Supabase function as Steps 2A/2B — just with `p_action: "reject"` (the `AuthorityCampaignTransitionAction` type was widened to `"submit_for_approval" | "approve" | "reject"`) — no backend change was needed. Visible only when `approval_status === "pending_approval"` (hidden for `draft`/`approved`/`rejected`, alongside Approve); enabled for owner/admin only, disabled + tooltipped ("Requires the owner or admin role.") for team_member/client, reusing the shared `CampaignActionButton` component (the role-array constant was renamed `CAMPAIGN_APPROVE_ROLES` → `CAMPAIGN_OWNER_ADMIN_ROLES`). Mock mode preserved via `CAMPAIGN_ACTION_TO_MOCK_STATUS.reject`. **Opportunity transitions, Step 1B creation, and Steps 2A/2B are all untouched.** See §21 below for full detail.

**Phase 15D Step 2D = Off-Page Authority Rejected → Draft campaign transition — implemented, pending authenticated owner/admin click-through validation.** `CampaignList.tsx` now also shows a "Return to Draft" button, wired through a new `offPageService.returnCampaignToDraft(id, websiteId)` reusing the same `runAuthorityCampaignTransitionWrite` helper and `transitionSupabaseAuthorityCampaign` Supabase function as Steps 2A/2B/2C — just with `p_action: "return_to_draft"` (the `AuthorityCampaignTransitionAction` type was widened to `"submit_for_approval" | "approve" | "reject" | "return_to_draft"`) — no backend change was needed. The RPC also legally accepts this action from `pending_approval`, but this step's UI intentionally exposes it only from `rejected`. Visible only when `approval_status === "rejected"` (hidden for `draft`/`pending_approval`/`approved`); enabled for owner/admin/team_member (base check, same restriction as `submit_for_approval`), disabled + tooltipped ("Requires the owner, admin, or team member role.") for `client`, reusing the shared `CampaignActionButton` component and `CAMPAIGN_SUBMIT_ROLES`. Mock mode preserved via `CAMPAIGN_ACTION_TO_MOCK_STATUS.return_to_draft`. **Opportunity transitions, Step 1B creation, and Steps 2A/2B/2C are all untouched.** This completes the UI for the full campaign approval state machine. Campaign editing, deletion, and task-completion writes remain unbuilt. `tsc --noEmit`/`npm run build` both pass; browser regression verified **directly in-browser** (a `rejected` campaign showed only "Return to Draft" with the role-denial tooltip path rendering the exact required copy, a `draft` campaign showed only "Submit for approval," an `approved` campaign showed no buttons, no console errors). **A full owner/admin click-through has not been performed** (no TEST credentials available this task) — see §22 below and `CURRENT_PROJECT_STATUS.md` §4/§7 for the recommended next step. No Campaign Workflow sign-off document has been created yet.

**Phase 15D = Off-Page Authority Campaign Workflow — authenticated 4-role validation, create-gating fix, and SIGN-OFF.** All of Steps 1B/2A–2D were authenticated-TEST-validated in the real browser on `Digi_SEO_Test` across **owner, admin, team_member, and client**: owner/admin ran the full state machine (create→submit→approve/reject→return) with refresh-persistence; team_member could create/submit/return but not approve/reject; client was fully read-only (zero DB writes). Every transition wrote exactly one `seo_authority_activity` row with the correct `actor_role_snapshot`/`created_by`; linked opportunities + tasks stayed intact; double-submit was protected. **A frontend create-gating gap surfaced during client validation and was fixed frontend-only:** a real `client` could reach an enabled "Create campaign" button and issue a backend-rejected `seo_authority_campaign_create` request. The fix adds a shared accessible `RoleGateTooltip` (`src/pages/seo/offpage/RoleGateTooltip.tsx`) and role-gates both the opportunity-selection checkbox (`OpportunityCard.tsx`) and the Create action (`CampaignBuilder.tsx` via a new `createRolePermitted` prop wired from `AuthorityBuilderPage.tsx` using the exported, reused `CAMPAIGN_SUBMIT_ROLES`); `CampaignList.tsx`'s `CampaignActionButton` was refactored onto the shared wrapper. Backend authorization was never weakened — the `seo_authority_campaign_create`/`seo_authority_campaign_transition` RPCs remain authoritative. Client revalidation PASS (selection disabled + focus-revealed tooltip, **no create request issued**, no console 400); managers unaffected; `tsc`/`build` clean; **no migration/RPC/RLS/API/DB change; production untouched**. See `PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md`. The Off-Page Authority module remains **NOT LOCKED** pending the Stage 6 final regression pass (next task).

**Phase 16B = Customer authentication + route protection (implemented + TEST-validated).** A chromeless `/seo/login` customer sign-in (existing Supabase users; login-only) plus `<ProtectedRoute>` on all `/seo/*` in Supabase mode, driven by one centralized `useSeoAccess()` resolver (session → `has_seo_module_access` RPC → `getCurrentSeoWorkspace` → active website) with branded loading/access-required/setup-redirect/error states, safe internal deep-link restoration, `SessionSync` cross-user cache/selection cleanup, a Header customer sign-out, dev-only `/seo/dev/*`, and `seo_is_global_admin`-gated `/seo/admin-preview`. New frontend files only (`seoAccessService`, `routeAccess`, `useSeoAccess`, `useSeoSignOut`, `SessionSync`, `RouteStates`, `ProtectedRoute`, `SeoLoginPage`) + additive edits (`supabaseTypes` `seoIsGlobalAdmin` constant, `Header`, `App`, `SeoRoutes`). **RLS + guarded RPCs stay authoritative; no DB/migration/RLS/RPC change; mock mode fully bypasses; locked modules only wrapped, not changed; production untouched.** See `PHASE_16B_CUSTOMER_AUTH_ROUTE_PROTECTION_SIGNOFF.md`. Auth is **not module-locked**.

**Phase 16C = Crawler job control-plane database contract (implemented + TEST-verified; no crawler runs).** Additive migration `20260713120025` adds `seo_crawl_jobs` / `seo_crawl_attempts` (internal, admin-read-only) / append-only `seo_crawl_events`, guarded SECURITY DEFINER RPCs `seo_crawl_request` + `seo_crawl_cancel` (authenticated only; owner/admin/team_member-or-global-admin gate, client denied; workspace/url/role resolved server-side; config validated; duplicate-active-job blocked by a partial unique index), and the **service-role-only** `seo_crawl_claim_job` (future worker's atomic `FOR UPDATE SKIP LOCKED` claim). Default-deny RLS (member reads only; no customer writes; internal attempts hidden). Usage/plan enforcement + external domain-ownership verification are DEFERRED (documented). No frontend crawl service/UI yet (only additive `supabaseTypes.ts` name constants). Verified ALL PASS (idempotent, self-cleaning). **No worker; crawling not operational; no existing object altered; locked modules untouched; production untouched.** See `CRAWLER_PHASE_1A_DATA_CONTRACT.md`.

**Phase 16D / Crawler 1B = worker skeleton + secure job-lifecycle contract (implemented + TEST-verified; still no crawling).** Additive migration `20260714120026` adds a **lease_token** (jobs + attempts), enhances `seo_crawl_claim_job` to issue/return it, and adds **service-role-only** worker functions (`seo_crawl_worker_heartbeat`/`complete`/`partial`/`fail`/`schedule_retry`/`acknowledge_cancellation`, `seo_crawl_recover_stale_jobs`) — each validating `(job_id, worker_id, lease_token)`, updating the attempt, writing one append-only event, clearing the lease at terminal/retry. A **Node/TS worker** in `crawler-worker/` (outside `src/`) drives them (config redaction, secret-safe logs, no-crawl processor refusing non-test jobs, dry-run/one-shot/gated-poll, stale-recovery, graceful shutdown, 10 unit tests, non-root Dockerfile — not deployed). Frontend unchanged except additive `supabaseTypes.ts` worker-RPC name constants. Verified ALL PASS + end-to-end integration (no page/audit writes; secret-safe). **16C still ALL PASS (backward compatible); no existing status value changed; customer RLS + locked modules untouched; production untouched.** See `CRAWLER_PHASE_1B_WORKER_SKELETON.md`.

**Phase 16E / Crawler 1C = secure page-discovery engine (implemented + TEST-verified; no SEO analysis).** Worker modules `crawler-worker/src/discovery/*` do all network access through one `SafeHttpTransport` (SSRF + connection-time DNS-rebinding-safe; TLS never disabled), interpret robots.txt (RFC 9309), parse sitemaps XXE-safely, discover `<a>` same-origin links, and run a budgeted BFS. Additive migration `20260714120027` adds `seo_crawl_discovered_pages` + `seo_crawl_sitemaps` (customer-read via workspace RLS; no customer writes) + `discovery_stats` and **service-role-only** `seo_crawl_worker_record_discovery`/`update_discovery_progress`. Deps: `fast-xml-parser@5` (0 advisories) + `node-html-parser@6`. Verified ALL PASS (unit 22/22, DB `seo_phase16e_...`, fixture-transport integration: 3 fetched / 1 robots-blocked / 0 cross-origin / no page-inventory-audit writes). Real-public-network crawl not live-tested (documented). **16C+16D+16E all ALL PASS; no existing status/RPC changed; customer RLS + locked modules untouched; crawler not customer-available; production untouched.** See `CRAWLER_PHASE_1C_DISCOVERY_ENGINE.md`.

**Phase 16F / Crawler 1D = page extraction + deterministic issue detection (implemented + TEST-verified; no audit/page-inventory publishing).** Worker modules `crawler-worker/src/extraction/*` (+ `discovery/charset.ts`) extract bounded technical facts from the Phase-1C-fetched HTML (no second fetch), normalize them, and run a versioned issue-rule registry + site-level duplicate detection. Additive migration `20260714120028` adds `seo_crawl_page_snapshots` + `seo_crawl_issues` (customer-read via workspace RLS; no customer writes; data-minimized — no full HTML/text) + `extraction_stats` and **service-role-only** `seo_crawl_worker_record_snapshots`/`record_issues`/`update_extraction_progress`. No new dependency (0 audit vulns). Verified ALL PASS (unit 32/32, DB `seo_phase16f_...`, fixture integration incl. `DUPLICATE_TITLE`; no page-inventory/audit writes). **16C+16D+16E+16F all ALL PASS; no existing status/RPC changed; customer RLS + locked modules untouched; crawler not customer-available; production untouched.** See `CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`.

**Phase 16G / Crawler 1E = controlled Page-Inventory + Audit PUBLISHING (implemented + TEST-verified).** Additive migration `20260714120029` binds a crawl job to one explicit audit run (`seo_crawl_jobs.audit_run_id` + guarded orchestration RPC `seo_crawl_request_audit`; `seo_crawl_request`/`seo_run_audit` unchanged) and adds one **service-role-only** transactional `seo_crawl_worker_publish_results` that reads persisted crawler snapshots/issues server-side and additively/idempotently upserts the EXISTING `seo_page_inventory` + `seo_audit_issues` (via a deterministic 29-code `seo_crawl_issue_audit_map`), records `seo_crawl_publications` evidence, and completes the run — with provenance, stale-job protection, manual-record preservation, and site issues represented without fabricated pages. **Customer pages still read Page-Inventory/Audit through their EXISTING services** (`select("*")` — additive nullable columns don't change shapes); no frontend page/service changed. **Complete:** crawl control plane, worker lifecycle, secure discovery, robots/sitemap, HTML-link discovery, extraction + normalization, deterministic crawler-domain issue detection, crawler-domain snapshot/issue persistence, **page extraction publishing + audit-issue publishing + explicit audit-run association + publication idempotency**. **Not complete:** Page-Inventory removal semantics, Recommendation generation, customer crawl-result UI, production crawler deployment, customer-operational crawling. Verified: `seo_phase16g_...` ALL PASS; worker 47/47; 16C–16F all ALL PASS; E2E fixture publish (3 pages + 8 issues incl. site duplicate; run completed; **no recommendation / Page-Performance write**; seed 7/7). **No customer crawl UI; no `seo_recommendations` write; locked Page Performance + Stage 6 untouched; crawler not customer-available; production untouched.** See `CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`.

**Phase 16H / Crawler 1F = customer crawl UI (implemented + automated-verified + **FULLY ACCEPTED ON TEST 2026-07-15 — PRODUCTION READINESS NOT STARTED**; implemented scope now LOCKED, see `MODULE_LOCKS.md`).** New frontend layer on `/seo/audit`, following the existing `runWithServiceAdapter` mock/supabase pattern: `crawlService.ts` → `seoCrawlSupabaseService.ts` (RPCs `seo_crawl_request_audit` + `seo_crawl_cancel`; customer-safe reads of `seo_crawl_jobs`/`seo_crawl_publications` — **no** lease token/worker id/config) + `crawlMockData.ts` (labelled preview). Hooks `useWebsiteCrawl.ts` (terminal-aware polling; role gate via `getCurrentSeoRole`; user+website-scoped keys). Components `audit/crawl/*` (Start Crawl with accessible confirm + role gate + double-submit + active-job disable; status card with safe counts/freshness/cancel/result links). **Supabase is the single authoritative status source** (no second backend; `fallbackToMockOnError:false` — no fake success). **No DB change.** Clients read-only. Verified: frontend `tsc`/`build` clean; worker 47/47; 16C–16G all ALL PASS; security sweep clean. Browser/operator acceptance **COMPLETE (all 7 scenarios PASS; three low-risk Scenario 7 artifacts un-saved — documentation-only)**; no future-wiring change (the frontend crawl service/hooks remain as documented; parent-BFF orchestration remains the future integration seam, unchanged). See `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md` + `OPERATOR_TEST_RESULTS.md`. **Next: production crawler deployment, ownership verification and usage-limit enforcement.**

**Stage 6 Final Regression = full regression of the approved Stage 6 scope — PASS; READY FOR A SEPARATE MODULE-LOCK DECISION.** Static (`tsc`/`build` clean; invariants hold), SQL (Stage 6 smoke + campaign-create + campaign-transition scripts ALL PASS, self-cleaning, evidence intact), authenticated browser matrix (admin/team_member/client: opportunity + campaign reads + role-gated workflow, client fully read-only, 0 unintended writes), AI Visibility reads (seeded `manual_seed`, 0 write requests; writes/LLM deferred), mock-mode (selection/builder/create still ungated — client gate does not affect mock), and earlier-stage route smoke (no crash, 0 console errors; Page Performance Tracker LOCKED + unchanged) all passed. No application/migration/RPC/RLS/API/DB change; production untouched. This is a regression checkpoint only — it does **not** lock the module. See `STAGE_6_FINAL_REGRESSION_SIGNOFF.md`.

**Stage 6 Implemented-Scope Lock (2026-07-13) = the completed + regression-verified Stage 6 scope is now LOCKED** (documentation-only) under `MODULE_LOCKS.md` → **"Stage 6 — Off-Page Authority Workflows and AI Visibility Reads"**. Locked: Off-Page Authority opportunity + campaign workflows, client/manager permission UX (create gate + shared `RoleGateTooltip`), and AI Visibility **reads** (`manual_seed`), with all protected contracts (statuses/actions/roles, the 3 RPCs, the 8 tables + append-only activity, service signatures, read-shape types, immutable migrations). **Deferred + UNLOCKED (open for separate additive work):** campaign task-completion writes, AI Visibility writes, real crawler/GSC/GA4/LLM ingestion, parent/BFF integration, production deployment, `ProtectedRoute`, Competitors/Roadmap/Reports wiring, mobile-overflow. Shared Stage 6 files may take backward-compatible additive changes that preserve the locked behaviour and re-run the Phase 15C/15D + Stage 6 regression. This is **not** "all Stage 6 development is complete." No application/migration/DB/API change; production untouched.

---

## 1. Current Mode

**Default mode is `mock`.** With `VITE_SEO_DATA_MODE` unset or `mock`, every service reads/writes local mock data exactly as before — the mock adapters were never removed. The mock/Supabase switching foundation was added *alongside* the mocks (Phase 13A), not in place of them.

**In `supabase` mode, the wired services now use real Supabase reads/writes** and gracefully fall back to mock on error. As of Phase 15D Step 2D, the wired services span Stages 1–6: `websiteService` + `businessOnboardingService` (13B), `auditService` + `recommendationService` (13C), `approvalService` (13D), `contentStudioService` (13E), `dashboardService` summaries + admin preview (13F), `performanceService` Page Performance reads (14A.2), `performanceService` Decline Diagnosis reads (14B.2), `offPageService` + `aiVisibilityService` reads (15A, read-only), `offPageService`'s opportunity transition writes (15C, Opportunity Workflow complete + signed off — see §17), `offPageService.createAuthorityCampaign` (15D Step 1B, atomic draft campaign creation, implemented + backend-verified + browser-validated — see §18), `offPageService.submitAuthorityCampaignForApproval` (15D Step 2A, Draft → Pending Approval transition, implemented + browser-validated — see §19), `offPageService.approveAuthorityCampaign` (15D Step 2B, Pending Approval → Approved transition, implemented + browser-validated — see §20), `offPageService.rejectAuthorityCampaign` (15D Step 2C, Pending Approval → Rejected transition, implemented + browser-validated — see §21), and `offPageService.returnCampaignToDraft` (15D Step 2D, Rejected → Draft transition, implemented — see §22; this completes the campaign approval state machine's UI. Campaign editing/deletion, task-completion, and AI Visibility writes remain mock-only). Sections §8–§22 below document each. Competitors, Roadmap, and Reports remain mock-only (no backend stage yet). See `CURRENT_PROJECT_STATUS.md` for the authoritative status.

> **Forward reference (2026-07-16 — Production Readiness A / P1a Steps 1 + 2A + 2B + 3 + 4 + 5).**
> Step 5 (Websites/onboarding ownership-verification UI — `OwnershipVerificationPanel`
> in `WebsiteCard`, consuming the Step 4 hooks) is implemented + mock-browser-verified.
> **Step 6 sign-off is complete: verdict `P1A IMPLEMENTED — OPERATOR ACCEPTANCE
> PENDING`** (all automated P1a + locked 16C–16H + Stage 6 regressions PASS; no
> defect; pending = authenticated browser matrix + real worker-binary run, neither
> runnable in this environment; P1a not yet module-locked). The next milestone
> (separately approved, additive to locked 16C–16H) is **P1b — verified-only crawl
> enqueue enforcement**. See `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`.
>
> _Prior (Steps 1–4):_
> The Domain Ownership Verification **database contract** (`…120031`, Step 1),
> **guarded customer RPCs** (`…120032`, Step 2A), **service-role + global-admin
> backend API** (`…120033`, Step 2B), **isolated DNS-TXT worker module** (Step 3),
> and now the **frontend service layer** (Step 4 — `ownershipVerificationService`
> + `seoOwnershipVerificationSupabaseService` [RLS read + Step 2A RPC writes] +
> deterministic mock + `useOwnershipVerification` hooks + pure helpers, behind the
> standard `runWithServiceAdapter`/non-masking-write pattern) are implemented +
> verified. **Step 4 adds a wired service + hooks but NO UI** (that is Step 5). It
> changes no existing wiring, no crawl service/hook/key, and no DB. The **exact
> next task is P1a Step 5 — the Websites/onboarding ownership-verification UI**
> (consumes the Step 4 hooks/service; owner/admin actions + read-only for others).
> P1a overall is not complete; crawl authorization is unchanged; P1b is excluded;
> production untouched. See `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md`
> + `CURRENT_PROJECT_STATUS.md`.

---

## 2. How to Set `.env` for Mock Mode

This is the default — no `.env` file is required at all. If you do create one:

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_SEO_DATA_MODE=mock
```

Leaving `VITE_SEO_DATA_MODE` unset also resolves to mock mode.

## 3. How to Set `.env` for Supabase Test Mode

Point at the **fresh test Supabase project** (Stage 1–3 applied and verified — see `BACKEND_MILESTONE_HANDOFF.md`). **Never** use a production project here.

```bash
VITE_SUPABASE_URL=https://<your-test-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<test-project-anon-key>
VITE_SEO_DATA_MODE=supabase
```

Only the **public URL** and **anon key** are ever read by frontend code. If either is missing/blank, or `VITE_SEO_DATA_MODE` has an unrecognized value, the app automatically falls back to `mock` mode and logs a console warning — it will not crash.

## 4. Why Mocks Remain the Fallback

- Only the switching **foundation** exists so far — no individual service has a working Supabase implementation to switch *to* yet.
- Frontend UI must keep working even with no `.env` file, a bad key, or a test project that's temporarily unreachable.
- Converting services module-by-module (per the order in §6) lets each one be verified against the test project independently, without risking the rest of the app.

## 5. What Phase 13A Created

| File | Purpose |
|---|---|
| `.env.example` | Documents `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_SEO_DATA_MODE` with safety comments. |
| `src/config/runtimeConfig.ts` | `getSeoDataMode()`, `isMockMode()`, `isSupabaseMode()`, `hasSupabaseConfig()`, `shouldUseSupabase()`. Never throws; missing/invalid env always resolves to mock. |
| `src/integrations/supabase/client.ts` | Reviewed/documented (no functional change) — anon-key-only, never throws on missing env, safe placeholder fallback. |
| `src/services/dataMode.ts` | Service-facing wrapper: `getSeoDataMode()`, `shouldUseSupabaseData()`, `requireSupabaseOrFallback()`, `logDataModeWarning()`. |
| `src/services/serviceAdapter.ts` | `runWithServiceAdapter()` — the pattern future services will use to pick mock vs. Supabase per call, with automatic fallback-on-error. |
| `src/services/supabase/supabaseTypes.ts` | `SEO_TABLES`, `SEO_RPCS`, `SEO_STORAGE_BUCKETS` name constants matching the applied migrations. |
| `src/services/supabase/supabaseErrors.ts` | `normalizeSupabaseError()` / `normalizeSupabaseErrorMessage()`. |
| `src/services/supabase/supabaseServiceUtils.ts` | `assertSupabaseConfigured()`, `getCurrentUserId()`, `requireAuthenticatedUser()`, `safeSingle()`, `safeList()`. |
| `src/services/supabase/supabaseHealthService.ts` | `checkSupabaseReadiness()` — read-only, no writes, does not require login. |
| `src/pages/seo/dev/SupabaseReadinessPage.tsx` + route `/seo/dev/supabase-readiness` | Dev-only diagnostics view (not in the sidebar/module registry). |
| `src/services/supabase/supabaseDevAuthService.ts` (Phase 13B.1) | `getDevAuthState()`, `signInDevUser()`, `signOutDevUser()`, `refreshDevSession()`, `checkSeoAccessForCurrentUser()`, `checkWorkspaceAccessForCurrentUser()`. |
| `src/pages/seo/dev/SupabaseAuthTestPage.tsx` + route `/seo/dev/auth-test` (Phase 13B.1) | Dev-only sign-in + service-check harness (not in the sidebar/module registry). Updated in Phase 13C with audit/recommendation checks, Phase 13D with approval checks. |
| `src/services/supabase/seoAuditSupabaseService.ts` (Phase 13C) | `fetchSupabaseAudits()`, `fetchSupabaseLatestAudit()`, `fetchSupabaseAuditById()`, `fetchSupabaseIssuesForAudit()`, `runSupabaseAudit()` (Stage 2 `seo_run_audit` RPC). |
| `src/services/supabase/seoRecommendationSupabaseService.ts` (Phase 13C) | `fetchSupabaseRecommendations()`, `fetchSupabaseOnPageRecommendations()`, `fetchSupabaseRecommendationById()`. |
| `src/services/supabase/seoApprovalSupabaseService.ts` (Phase 13D) | `fetchSupabaseApprovalQueue()`, `fetchSupabaseApprovalItemById()`, `ensureSupabaseApprovalQueueGenerated()`, `updateSupabaseApprovalItemFields()`, `addSupabaseApprovalComment()` (Stage 2 `seo_approval_transition` RPC), `ApprovalTransitionError`. |
| `src/services/supabase/seoContentStudioSupabaseService.ts` (Phase 13E) | Full Content Studio read/write set (opportunities, keyword plan, competitor summaries, wireframe, format input, draft + sections + revisions) via Stage 3 `seo_content_transition` RPC for workflow status. `ContentTransitionError`. |
| `src/services/supabase/seoDashboardSupabaseService.ts` (Phase 13F) | `fetchSupabaseTopPriorityFixes()` (derived from Stage 2 `seo_recommendations`, `is_current=true`), `fetchSupabasePendingApprovalsSummary()` (Stage 2 `seo_approval_items` counts). Read-only, no writes. |
| `src/services/adminPreviewSummaryService.ts` (Phase 13F) | `fetchAdminPreviewSummary()` — pure composition of already-wired service calls (`fetchWebsites`, `fetchAudits`, `fetchRecommendations`, `fetchApprovalQueue`, `fetchContentOpportunities`) into a compact read-only summary for `/seo/admin-preview`. No direct Supabase queries of its own. |
| `src/services/supabase/seoPagePerformanceSupabaseService.ts` (Phase 14A.2) | `fetchSupabasePagePerformance()` / `fetchSupabasePageDetail()` (flatten Stage 4's normalized tables into the app's `PagePerformance` shape), plus `fetchSupabasePageInventory()`, `fetchSupabasePageKeywords()`, `fetchSupabaseLatestPerformance()`, `fetchSupabasePerformanceHistory()`, `fetchSupabaseMovementSummary()`, `findAccessibleWebsiteWithPerformanceData()`. Read-only, no writes. |
| `src/services/supabase/seoDeclineDiagnosisSupabaseService.ts` (Phase 14B.2) | `fetchSupabaseDeclineDiagnoses()` / `fetchSupabaseDiagnosesForPage()` (map Stage 5's richer diagnosis model down into the app's `DeclineDiagnosis` shape), plus `fetchSupabaseCurrentDiagnosisRows()`, `fetchSupabaseDiagnosisEvidence()`, `findAccessibleWebsiteWithDeclineDiagnosisData()`. Read-only, no writes. |
| `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` (Phase 15A) | `fetchSupabaseAuthorityOpportunities()` / `fetchSupabaseAuthorityCampaigns()` (map Stage 6's normalized junction/task tables down into the app's `OffPageOpportunity`/`AuthorityCampaign` shapes, deriving `opportunity_ids`/`tasks`/`progress_percentage`), plus raw-row reads, `fetchSupabaseAuthorityActivity()`, `findAccessibleWebsiteWithAuthorityData()`. Read-only, no writes. |
| `src/services/supabase/seoAiVisibilitySupabaseService.ts` (Phase 15A) | `fetchSupabasePromptTrackingRecords()` / `fetchSupabaseAiContentGaps()` / `fetchSupabaseBrandMentionSummary()` / `fetchSupabaseCompetitorMentionSummaries()` (preferring the normalized `seo_ai_mentions` table per Stage 6 D2), plus raw-row reads, `findAccessibleWebsiteWithAiVisibilityData()`. Read-only, no writes. |

**Not touched in 13A:** `websiteService.ts`, `businessOnboardingService.ts`, `auditService.ts`, `recommendationService.ts`, `approvalService.ts`, `contentStudioService.ts`, `dashboardService.ts`, `performanceService.ts`, or any `src/mocks/*` file. All mock adapters remained exactly as they were. (`websiteService.ts` and `businessOnboardingService.ts` were wired in Phase 13B — see §8. `auditService.ts` and `recommendationService.ts` were wired in Phase 13C — see §10. `approvalService.ts` was wired in Phase 13D — see §11. `contentStudioService.ts` was wired in Phase 13E — see §12. `dashboardService.ts`'s two summary reads and a new admin-preview composition service were wired in Phase 13F — see §13. `performanceService.ts`'s `fetchPagePerformance`/`fetchPageDetail` were wired in Phase 14A.2 — see §14. `performanceService.ts`'s `fetchDeclineDiagnoses`/`fetchDiagnosisForPage` were wired in Phase 14B.2 — see §15. Every `src/mocks/*` file is still untouched.)

## 6. Recommended Wiring Order

1. `websiteService` + `businessOnboardingService` — **wired in Phase 13B (see §8)**
2. `auditService` + `recommendationService` — **wired in Phase 13C (see §10)**
3. `approvalService` — **wired in Phase 13D (see §11)**
4. `contentStudioService` — **wired in Phase 13E (see §12)**
5. Dashboard summaries — **wired in Phase 13F (see §13)**
6. Admin preview (read-only) — **wired in Phase 13F (see §13)**
7. `performanceService` (Page Performance Tracker) — **wired in Phase 14A.2 (see §14)**
8. `performanceService` (Decline Diagnosis Engine) — **wired in Phase 14B.2 (see §15)**
9. `offPageService` + `aiVisibilityService` (Off-Page Authority + AI Visibility/GEO, reads only) — **wired in Phase 15A (see §16)**
10. `offPageService` opportunity transition writes (Off-Page Authority, Opportunity Workflow) — **wired + signed off in Phase 15C (see §17 and `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`); campaign writes and AI Visibility writes remain mock-only**
11. `offPageService.createAuthorityCampaign` (Off-Page Authority, atomic draft campaign creation) — **implemented + backend-verified on TEST in Phase 15D Step 1B (see §18); pending authenticated browser validation**
12. `offPageService.submitAuthorityCampaignForApproval` (Off-Page Authority, Draft → Pending Approval transition) — **implemented + browser-validated in Phase 15D Step 2A (see §19)**
13. `offPageService.approveAuthorityCampaign` (Off-Page Authority, Pending Approval → Approved transition) — **implemented + browser-validated in Phase 15D Step 2B (see §20)**
14. `offPageService.rejectAuthorityCampaign` (Off-Page Authority, Pending Approval → Rejected transition) — **implemented + browser-validated in Phase 15D Step 2C (see §21)**
15. `offPageService.returnCampaignToDraft` (Off-Page Authority, Rejected → Draft transition) — **implemented in Phase 15D Step 2D (see §22); pending authenticated owner/admin click-through validation; this completes the campaign approval state machine's UI; campaign editing/deletion, task-completion, and AI Visibility writes remain mock-only**

Each step: convert one service's functions to use `runWithServiceAdapter()` (or `requireSupabaseOrFallback()` directly), verify against the test Supabase project, then move to the next. Keep the mock branch in place until the Supabase path for that service is confirmed stable.

## 7. Rules

- No service role key in frontend code, ever. Frontend may only use `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
- No production Supabase credentials until explicitly approved (target-project confirmation, backup/branch strategy, final review, sign-off — see `BACKEND_MILESTONE_HANDOFF.md` §5).
- No mock removal until a service's Supabase path is verified stable against the test project.

## 8. Phase 13B Status — Website Setup + Business Onboarding

- **Website Setup service (`websiteService.ts`):** wired. `fetchWebsites`, `fetchWebsiteById`, `addWebsite` all use `runWithServiceAdapter()` — mock in mock mode; in Supabase mode, reads/writes `seo_websites` + `seo_connection_status` (Stage 1) via `src/services/supabase/seoWebsiteSupabaseService.ts`.
- **Business Onboarding service (`businessOnboardingService.ts`):** wired. `fetchOnboardingByWebsiteId`, `saveOnboarding` use the same adapter pattern against `seo_business_onboarding` (Stage 1) via `src/services/supabase/seoBusinessOnboardingSupabaseService.ts`.
- **Mock fallback preserved.** No mock adapter, mock data file, or mock-mode behavior changed. `runWithServiceAdapter()` still falls back to mock automatically on any Supabase error, logging one dev-facing console warning.
- **Supabase mode requires an authenticated user.** Both wired services resolve the caller's own SEO workspace via `src/services/supabase/seoWorkspaceService.ts` (`getOrCreateDefaultSeoWorkspace()`), which requires a real Supabase session and (per Stage 1 RLS) an existing `user_module_access(module='seo')` grant for that user. No session, or no module grant, both fail gracefully into the mock fallback.
- **No crawler / GSC / GA4 / CMS / GBP integration.** Connection-status fields are still placeholders (`seo_connection_status` row seeded with the same "just added" defaults the mock adapter uses) — no real check of any kind is performed.
- **No production wiring.** All Supabase calls above target the test Supabase project only, per the mode rules in §3 and §7.

Full details: `PHASE_13B_SERVICE_WIRING_NOTES.md`.

## 9. Phase 13B.1 Status — Dev-Only Supabase Auth Test Harness

- **New hidden page:** `/seo/dev/auth-test` (`SupabaseAuthTestPage.tsx`) — not in the sidebar, not in the module registry, not linked from any customer-facing page. Dev-gated (`import.meta.env.DEV`) like `/seo/dev/supabase-readiness`.
- **Real sign-in, no fake auth.** Uses `supabase.auth.signInWithPassword()` against an existing test-project user via the same anon client as the rest of the app. Does not create users, does not use the service role key, does not store or log the password (cleared from state immediately after submit).
- **Access checks are read-only.** SEO module access is checked via the Stage 1 `has_seo_module_access` RPC (falls back to a direct `user_module_access` self-row read if the RPC call fails); workspace access is checked via the existing read-only `seoWorkspaceService.getCurrentSeoWorkspace()`. Neither check grants access or creates a workspace — only the existing "Test website service" / "Create test website" actions (which call the already-wired `websiteService`) can trigger the pre-existing create-on-first-use path from Phase 13B.
- **Service verification, not new services.** The page's buttons call the already-wired `websiteService.fetchWebsites`/`addWebsite` and `businessOnboardingService.fetchOnboardingByWebsiteId` directly — no approval or Content Studio service is touched. (Phase 13C later added audit + recommendation checks to this same page — see §10.)
- **No production credentials.** Same `.env` rules as §7 — test/staging Supabase project only.

Full details: `PHASE_13B1_DEV_AUTH_TEST_NOTES.md`.

## 10. Phase 13C Status — Technical Audit + SEO Recommendation

- **Audit service (`auditService.ts`):** wired. `fetchAudits`, `fetchLatestAudit`, `fetchAuditById`, `fetchIssuesForAudit` all use `runWithServiceAdapter()` — mock in mock mode; in Supabase mode, read `seo_audit_runs` / `seo_audit_issues` (Stage 2) via `src/services/supabase/seoAuditSupabaseService.ts`. `runAudit` triggers the Stage 2 `seo_run_audit(uuid)` RPC in Supabase mode.
- **Recommendation service (`recommendationService.ts`):** wired. `fetchRecommendations`, `fetchOnPageRecommendations`, `fetchRecommendationById` read `seo_recommendations` (`is_current=true`) via `src/services/supabase/seoRecommendationSupabaseService.ts`. `generateRecommendationsFromAudit` stays **mock-only in every mode** — Stage 2 recommendations are system/service-role generated, and RLS excludes clients from writing `seo_recommendations` directly.
- **No fake audit completion.** Stage 2 has no crawler — the RPC only creates a `running` run row (score 0, no issues). Nothing here fabricates a "completed" audit or synthesizes issues client-side. The existing UI (`WebsiteAuditPage`) already gates recommendation generation behind `status === "completed"`, so that path is naturally unreachable in Supabase mode too.
- **Mock fallback preserved.** No mock adapter, mock data file, or mock-mode behavior changed. Same graceful-fallback-with-one-console-warning behavior as Phase 13B.
- **Supabase mode requires an authenticated user.** Reads/writes throw a clear "no authenticated Supabase user" error when signed out, letting the adapter fall back to mock — no session silently returning an empty Supabase result.
- **Approval Queue was NOT wired in this phase.** `approvalService.ts` and `seo_approval_transition` were untouched here; recommendation *status* was read-only in this phase. (Wired in Phase 13D — see §11.)
- **Content Studio was NOT wired in this phase.** `contentStudioService.ts` was untouched here. (Wired in Phase 13E — see §12.)
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_13C_AUDIT_RECOMMENDATION_WIRING_NOTES.md`.

## 11. Phase 13D Status — Approval Queue

- **Approval service (`approvalService.ts`):** wired. `fetchApprovalQueue`, `fetchApprovalItemById` use `runWithServiceAdapter()` (standard read fallback). `ensureApprovalQueueGenerated` creates Stage 2 `seo_approval_items` rows via direct INSERT (owner/admin/team_member only, per Stage 2 RLS) — a mechanical 1:1 mapping from existing recommendations, not content generation, so unlike `generateRecommendationsFromAudit` it IS wired.
- **Workflow-status changes always go through `seo_approval_transition`.** `updateApprovalItemFields({status})` maps the UI's target status (`approved`/`rejected`/`expert_review_requested`/`developer_needed`/`completed`) onto the matching RPC action — never a direct status UPDATE. Editing `suggested_change` (no status involved) uses a direct RLS-gated UPDATE instead, per Stage 2's own design (owner/admin/team_member only; clients have no UPDATE).
- **A real backend permission denial is never masked.** Unlike every other wired service so far, approval **writes** (`updateApprovalItemFields`, `addApprovalComment`) do **not** use the standard `runWithServiceAdapter` fallback-on-any-error. A dedicated `ApprovalTransitionError` (thrown when the RPC itself rejects the call — wrong role, high-risk item, unknown action, item not found) propagates as a real, visible error instead of silently "succeeding" via mock. Only pre-RPC failures (no session, no config) still fall back to mock gracefully. This preserves the entire point of Stage 2's role/risk enforcement — see `src/services/approvalService.ts`'s `runApprovalWrite()`.
- **Comments are append-only and role-authentic.** `addApprovalComment` routes through the RPC's `comment` action, which stamps the caller's *real* Stage 2 workspace role (`seo_role_of`) — the UI's client-side role-simulation selector value is not trusted for this.
- **Activity stays read-only/unexposed.** `seo_approval_activity` is not read or written directly from the frontend this phase — the RPC writes it server-side; the current UI has no activity-timeline view to wire against.
- **Content Studio was NOT wired in this phase.** `contentStudioService.ts` was untouched here. (Wired in Phase 13E — see §12.)
- **No live publishing exists.** No action anywhere reaches a CMS, changes a URL/redirect/canonical/noindex/robots.txt/sitemap, or publishes content — matches Stage 2's design (`ready_to_publish` is a queue marker with no executor).
- **No crawler/AI generator exists yet.** A fresh Supabase test website legitimately has 0 recommendations (Phase 13C) and therefore 0 approval items until either a future crawler/LLM backend lands or test data is seeded manually via the Supabase SQL editor.
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_13D_APPROVAL_QUEUE_WIRING_NOTES.md`.

## 12. Phase 13E Status — Content Studio

- **Content Studio service (`contentStudioService.ts`):** wired. All 15 exported functions now go through the adapter — reads and mechanical creation/authoring writes (opportunities, keyword plan, competitor summaries, wireframe content, format input, draft + sections + section revisions) use the standard `runWithServiceAdapter()`; the four functions that are explicit, user-intentional workflow actions (`startContentPlan`, `approveWireframe`, `updateContentStatus`, `addDraftFeedback`) use a dedicated `runContentWrite()` helper — same non-masking rule as Phase 13D's approval writes.
- **Status model mismatch, handled explicitly.** The app's simplified 12-value `ContentWorkflowStatus` is mapped both ways against Stage 3's richer 14-value status enum (which separately tracks internal vs. client review). `DB_STATUS_TO_APP_STATUS` / `APP_STATUS_TO_TRANSITION_ACTION` in `seoContentStudioSupabaseService.ts` document the full mapping and its reasoning — see `PHASE_13E_CONTENT_STUDIO_WIRING_NOTES.md` §7 for the known limitations this introduces (e.g. `expert_review_requested` has no Stage 3 equivalent yet and surfaces a clear `ContentTransitionError` instead of silently no-op'ing).
- **Workflow-status changes always go through `seo_content_transition`.** Never a direct status UPDATE on `seo_content_opportunities`. Two supporting helper patterns: `tryTransition()` tolerantly treats an "Invalid transition" rejection as a benign no-op (needed because "Regenerate wireframe" reuses the same generate action, and Stage 3's `start_wireframe`/`start_draft`/`submit_draft_internal_review` actions aren't re-callable once already past that step); genuine, unexpected rejections still propagate as `ContentTransitionError` and are never masked by mock success.
- **Keyword plan and competitor summaries auto-create on first read**, mirroring the mock adapter's own `ensureKeywordPlan`/`ensureCompetitorSummaries` convenience behavior — deterministic template text only (no real keyword research, no real scraping), needed because the real UI only renders the downstream wireframe/draft workflow once a keyword plan exists.
- **Content Studio Storage/assets are deferred entirely this phase.** `seo_content_assets` and the private `seo-content-assets` bucket are untouched — the current UI's format-input file picker only ever stores a filename **string** ("Only the filename is stored for now — file contents aren't processed yet"), so there is no real upload flow to wire against yet.
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_13E_CONTENT_STUDIO_WIRING_NOTES.md`.

## 13. Phase 13F Status — Dashboard Summaries + Admin Preview (Read-Only)

- **Dashboard service (`dashboardService.ts`):** two functions wired via `runWithServiceAdapter()`. `fetchTopPriorityFixes` derives "Top Priority Fixes" from Stage 2 `seo_recommendations` (`is_current=true`) — there is no dedicated fixes table — ranked by the same impact/confidence weighting the mock uses and capped at 5. `fetchPendingApprovalsSummary` reads Stage 2 `seo_approval_items` status/fix_owner counts. Both are pure reads, no RPC calls, no writes.
- **Everything else on `/seo/dashboard` needed no new wiring.** Visibility score cards, the setup checklist, and the recommended-next-step card are pure functions fed by data that already flows through Phase 13B/13C wired services (`fetchOnboardingByWebsiteId`, `fetchAudits`). `fetchRecentActivity` / `logRecentActivity` stay **mock-only in every mode** — no Stage 1-3 activity table is in this phase's allowed read list.
- **Admin Preview (`/seo/admin-preview`) got a new, small composition service, not a rewrite.** `src/services/adminPreviewSummaryService.ts` (`fetchAdminPreviewSummary()`) purely composes already-wired service calls (`fetchWebsites`, `fetchAudits`, `fetchRecommendations`, `fetchApprovalQueue`, `fetchContentOpportunities`) — no direct Supabase queries of its own, so it inherits correct mock/Supabase behavior for free. The existing `seoAdminService.ts` (used by the actual `/seo/admin-preview` page/`SeoAdminShell`) was deliberately left untouched — it spans every SEO module including several explicitly out-of-scope this phase, and it already transitively benefits from prior phases' wiring via its own composition of `fetchWebsites`/`fetchAudits`/`fetchRecommendations`/`fetchApprovalQueue`/`fetchContentOpportunities`.
- **`/seo/admin-preview` is still explicitly temporary.** No UI changes were made to `SeoAdminPreviewPage.tsx` or `SeoAdminShell` this phase — the existing "temporary standalone preview, final destination: existing Digibility Admin Panel" banner is unchanged. This phase does not constitute final Digibility Admin Panel integration.
- **Read-only only.** No writes, no RPC calls, no role/access/billing/module-access data anywhere in this phase's new code.
- **Mock fallback preserved.** Same `runWithServiceAdapter()` graceful-fallback-with-one-console-warning behavior as every prior phase. Both new dashboard functions call `requireAuthenticatedUser()` first, so with no session they never even issue a network request before falling back to mock.
- **Dev harness updated.** `/seo/dev/auth-test` gained two new buttons: "Test Dashboard Summary Service" and "Test Admin Preview Read Service" — summary counts only, no writes.
- **Out of scope, unchanged:** Page Performance, Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, Reports remain mock-only (their services were not touched this phase).
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_13F_DASHBOARD_ADMIN_READONLY_WIRING_NOTES.md`.

## 14. Phase 14A.2 Status — Page Performance Tracker

- **Performance service (`performanceService.ts`):** `fetchPagePerformance` and `fetchPageDetail` wired via `runWithServiceAdapter()`. The Supabase path (`src/services/supabase/seoPagePerformanceSupabaseService.ts`) reads Stage 4's normalized tables (`seo_page_inventory`, `seo_page_keywords`, `seo_page_performance_snapshots`, and the `seo_page_performance_latest` view) and **flattens** them back into the app's existing flat `PagePerformance` shape (one row per page, one primary keyword, metrics inlined) — no type or UI change needed anywhere.
- **`fetchPerformanceSummary` updated to derive from the now-wired `fetchPagePerformance`** instead of importing the mock adapter's `listPagePerformance` directly (a pre-existing inconsistency where the summary always used mock data regardless of data mode, even after other reads were wired). Its aggregation logic (counts by status, totals, averages) is otherwise unchanged, so it's correct in both modes automatically.
- **Status mapping.** Stage 4's `movement_status` (`improving`/`stable`/`declining`/`new`/`no_data`) is a distinct, newer enum from the app's `PagePerformanceStatus` (`improving`/`stable`/`declining`/`needs_refresh`/`not_enough_data`). `new` and `no_data` both map to `not_enough_data`; `seo_page_inventory.content_status` (`aging`/`stale`) overrides the movement-derived status to `needs_refresh`, since "needs a refresh" is fundamentally a content-freshness signal in the app, tracked on the page row in Stage 4 rather than the snapshot.
- **`page_type` maps 1:1**, no translation needed — Stage 4's CHECK constraint was deliberately designed identical to the app's existing `PageType` back in Phase 14A.1.
- **Dashboard integration came for free.** `PagePerformanceSummaryCard` (`/seo/dashboard`) already called `fetchPerformanceSummary` directly — no dashboard code changed, no new card added.
- **Decline Diagnosis was NOT wired in this phase** (`fetchDeclineDiagnoses`, `fetchDiagnosisForPage`, `fetchRefreshRecommendationsForWebsite`, `fetchRefreshRecommendationForPage`, and `generateMockPerformanceRefresh` were all mock-only in every mode at the time). `DeclineDiagnosisPage` also called the now-wired `fetchPagePerformance`, so it showed real Stage 4 page data correlated with mock diagnosis data — an accepted, expected side effect at the time. **`fetchDeclineDiagnoses`/`fetchDiagnosisForPage` were subsequently wired in Phase 14B.2 (see §15)**; `fetchRefreshRecommendationsForWebsite`/`fetchRefreshRecommendationForPage`/`generateMockPerformanceRefresh` remain mock-only (no Stage 5 backend equivalent).
- **Read-only only.** No writes, no RPC calls anywhere in this phase's new code.
- **Mock fallback preserved.** Same `runWithServiceAdapter()` graceful-fallback-with-one-console-warning behavior as every prior phase. Both new Supabase functions call `requireAuthenticatedUser()` first, so with no session they never even issue a network request before falling back to mock.
- **Dev harness updated.** `/seo/dev/auth-test` gained three new buttons: "Test Page Performance Service" (adapter-wired, works in both modes), "Test Page Performance Latest View" and "Test Page Performance History" (Supabase-only diagnostics that call the Stage 4 service directly, bypassing the adapter, to prove the view/table work independent of the flattening logic — these are expected to show a warning in mock mode or without a session, since there is no mock equivalent of "the Supabase view").
- **No real GSC/GA4, no real crawler.** `source` on every Stage 4 row is `manual_seed` (from the Phase 14A.1 UI seed extension) — nothing in this phase calls an external API.
- **Out of scope, unchanged:** Decline Diagnosis, Off-Page Authority, AI Visibility, Competitors, Roadmap, Reports remain mock-only (their services were not touched this phase).
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_14A_PAGE_PERFORMANCE_WIRING_NOTES.md`.

## 15. Phase 14B.2 Status — Decline Diagnosis Engine

- **Performance service (`performanceService.ts`):** `fetchDeclineDiagnoses` and `fetchDiagnosisForPage` wired via `runWithServiceAdapter()`. The Supabase path (`src/services/supabase/seoDeclineDiagnosisSupabaseService.ts`) reads Stage 5 (`seo_decline_diagnoses`, `seo_decline_diagnosis_evidence`, `seo_decline_diagnoses_current` view) and **maps** the richer backend model down into the app's existing flat `DeclineDiagnosis` shape — no type or UI change needed anywhere.
- **`fetchDeclineDiagnoses` reads the current view** (`seo_decline_diagnoses_current`), which already filters to live statuses (`open`/`in_review`/`action_planned`) — resolved/dismissed diagnoses never reach the app. `fetchDiagnosisForPage` reads the base table directly (all 5 statuses) for a page-level history read; no UI currently calls it, same as before this phase.
- **Mapping.** `diagnosis_type` (12 backend values) maps to the app's existing `DeclineCause` (10 values) via an explicit lookup table with a safe `technical_issue` fallback for anything unrecognized (`no_data`, `mixed_signals`, or a future value) — never throws. `priority` passes through 1:1; a `severity='critical'` row is forced to `priority='high'`. `suggested_owner` passes through 1:1 (validated, with a `system_suggestion` fallback) to `fix_owner`. `status` has no frontend field — handled entirely by which table/view is queried (see above). Full mapping table in `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` §4.
- **`page_performance_id` = `seo_page_inventory.id`** (the diagnosis row's `page_id`) — exactly what `PagePerformance.id` already is (Phase 14A.2), so `DeclineDiagnosisPage.tsx`'s existing `pages.find((p) => p.id === diagnosis.page_performance_id)` keeps working unchanged.
- **`DeclineDiagnosisPage.tsx` gained a cross-workspace fallback**, structurally identical to `PagePerformancePage.tsx`'s (Phase 14A.2): in Supabase mode, if the auto-selected active website has zero live diagnoses **or its onboarding is incomplete**, the page searches every accessible workspace/website for one with live diagnosis data and uses it as a page-local `displayWebsite` override (never mutating the shared active-website context). **The underlying finder ranks by live diagnosis count** (highest wins, not "first found") — a post-launch fix after a live test found it picking a low-data smoke-test workspace over the richer UI seed one; see `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` §10. This ranking is specific to the Decline Diagnosis finder — Page Performance's analogous finder (`findAccessibleWebsiteWithPerformanceData`) still stops at the first match and was not changed. A second post-launch fix corrected the fallback effect's trigger order: it originally required the *active* website's onboarding to already be complete before it would even search, which meant it could never fire for the common case (a never-onboarded smoke-test website) — see §11 there.
- **Live-verified end-to-end in the browser (signed in, TEST project).** After both post-launch fixes, `/seo/dev/auth-test`'s finder correctly selects `UI Seed Workspace` / `https://ui-seed-digibility.example` / 6 live diagnoses, and `/seo/decline-diagnosis` renders the seeded diagnosis cards on "UI Seed Demo Site" with no onboarding block and no console errors. See `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md` §12 for the full checkpoint. Production untouched throughout.
- **Read-only only.** No writes, no RPC calls. The Stage 5 `seo_create_decline_diagnosis_from_snapshot` RPC exists but is intentionally not called — no UI has a "create a diagnosis" action yet.
- **Mock fallback preserved.** Same `runWithServiceAdapter()` graceful-fallback-with-one-console-warning behavior as every prior phase. Both new Supabase functions call `requireAuthenticatedUser()` first, so with no session they never even issue a network request before falling back to mock.
- **Dev harness updated.** `/seo/dev/auth-test` gained a "Phase 14B.2 — Decline Diagnosis Engine" section: "Find website with Decline Diagnosis data" (cross-workspace search), "Test Decline Diagnosis Current View" (adapter-bypassing diagnostic, mirrors the Page Performance latest-view button), and "Test Diagnosis Evidence" (optional, reads raw evidence rows) — expected to show a warning in mock mode or without a session, same caveat as the Page Performance diagnostics.
- **No real GSC/GA4/crawler/LLM.** All Stage 5 rows on the test project come from the Stage 5 UI seed extension's hand-written demo content.
- **Out of scope, unchanged:** refresh recommendations (no Stage 5 backend equivalent), Off-Page Authority, AI Visibility, Competitors, Roadmap, Reports remain mock-only.
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_14B_DECLINE_DIAGNOSIS_WIRING_NOTES.md`.

## 16. Phase 15A Status — Off-Page Authority + AI Visibility/GEO (Read-Only)

- **Off-Page Authority (`offPageService.ts`):** `fetchAuthorityOpportunities` and `fetchAuthorityCampaigns` wired via `runWithServiceAdapter()`. The Supabase path (`src/services/supabase/seoOffPageAuthoritySupabaseService.ts`) reads Stage 6 (`seo_authority_opportunities`, `seo_authority_campaigns`, `seo_authority_campaign_tasks`, `seo_authority_campaign_opportunities`) and **maps + derives** them into the app's existing `OffPageOpportunity`/`AuthorityCampaign` shapes: `opportunity_ids` is derived from the junction table (D1 — the source of truth, never a stored array) and `tasks`/`progress_percentage` are derived from the tasks table (D6 — progress is computed, never a stored column). `fetchSpamRiskReview` and `fetchAuthorityOverview` now derive from these wired reads instead of importing mock data directly, so they're correct in both modes automatically — same pattern as `performanceService.fetchPerformanceSummary` (Phase 14A.2).
- **AI Visibility (`aiVisibilityService.ts`):** `fetchPromptTrackingRecords`, `fetchBrandMentionSummary`, `fetchCompetitorMentionSummary`, `fetchAiContentGaps` wired the same way. The Supabase path (`src/services/supabase/seoAiVisibilitySupabaseService.ts`) reads Stage 6's `seo_ai_prompt_tracking` / `seo_ai_content_gaps` / `seo_ai_mentions`. Brand/competitor mention summaries **prefer the normalized `seo_ai_mentions` table** over re-deriving from prompt arrays (Stage 6 D2 — the backend's intended replacement for the mock's own derivation approach), falling back to the prompt-array derivation only when a website has prompts but zero mention rows yet. `fetchAiVisibilityOverview` derives from the wired reads.
- **Cross-workspace fallback.** Both `AuthorityBuilderPage.tsx` and `AiVisibilityPage.tsx` gained the same page-local `displayWebsite` override pattern as `DeclineDiagnosisPage.tsx` (Phase 14B.2) — ranked-by-count finders (`findAccessibleWebsiteWithAuthorityData`/`findAccessibleWebsiteWithAiVisibilityData`), applied from the start with the corrected trigger conditions (search on incomplete onboarding OR a settled zero-row read) that Phase 14B.2 only reached after a post-launch fix (§11 there). Neither finder hardcodes any workspace/website id, name, or URL. The shared `ActiveWebsiteContext` is never mutated.
- **Writes are NOT wired — mock-only in every mode, by design.** `updateAuthorityOpportunityStatus` and `createAuthorityCampaign` (Off-Page) and `updateAiVisibilityItemStatus`/`generateMockAiVisibilityRefresh` (AI Visibility) all remain mock-only. The key reason: the current UI's opportunity status buttons (`OpportunityCard.tsx`) don't provide a complete, legal path through Stage 6's guarded `seo_authority_opportunity_transition` RPC's state machine — e.g. "Mark in progress" fires from `suggested`/`shortlisted`, but the RPC's `start` action requires `approval_required`/`expert_review_requested` first, and there is no "Request approval"/"Request expert review" button yet to legally reach that state. Wiring the write now would surface a real "Illegal transition" error on an ordinary click — a UI/workflow mismatch, not a genuine permission denial, and per the task's own "do not rewrite pages unless necessary to render Supabase data" constraint, adding the missing buttons is scoped as a follow-up phase, not done here. See `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §7 for the full reasoning and recommended follow-up (mirroring Phase 13D/13E's non-masking `ApprovalTransitionError`/`ContentTransitionError` pattern once the buttons exist).
- **Dev harness updated.** `/seo/dev/auth-test` gained a "Phase 15A — Off-Page Authority + AI Visibility/GEO" section: "Find website with Off-Page Authority data" / "Test Off-Page Authority Service" and "Find website with AI Visibility data" / "Test AI Visibility Service" (all read-only, Supabase-only diagnostics — expected to show a warning in mock mode or without a session, same caveat as every prior phase's diagnostics).
- **No real GSC/GA4/crawler/LLM/scraper/outreach/review-generation/backlink-automation.** All Stage 6 rows on the test project come from the Stage 6 UI seed extension's hand-written demo content (`source = 'manual_seed'`).
- **Verification performed:** `npx tsc --noEmit` and `npm run build` both passed. Mock mode verified unchanged in a browser preview (both pages render identically to before this phase, zero console errors). Supabase mode with no session verified to fail gracefully (clear "no authenticated Supabase user" warnings, zero console errors) — same established fallback behavior as every prior phase.
- **Not performed:** a signed-in live test against the TEST project's seeded Stage 6 data — no test-user password was available in this task (by design, none is ever stored in this repo). **Status: implemented, pending live test.** See `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §10 for the exact steps to complete it.
- **No production wiring.** All Supabase calls target the test Supabase project only.

Full details: `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md`.

> **Forward-looking note (Phase 15B, audit only — not a wiring phase):**
> `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` inventories every current mock-only
> Off-Page Authority + AI Visibility UI write action against the actual legal
> state machine enforced by `seo_authority_opportunity_transition` /
> `seo_authority_campaign_transition`, and finds that most of the current
> opportunity status buttons (`OpportunityCard.tsx`) are illegal from the
> status they are realistically clicked in, "Reject"/campaign "Approve"/
> "Reject" have no UI role gating, and the entire campaign approval workflow
> (submit/approve/reject/return-to-draft) has no UI at all —
> `CampaignList.tsx` is still fully read-only. The audit proposes (does not
> build) a legal action matrix for a future wiring phase. **No code was
> changed by the audit; writes remain 100% mock-only, unchanged from this
> section's status above.**

## 17. Phase 15C Status — Off-Page Authority Opportunity Transition Writes (Signed Off)

**Forward reference:** the Opportunity Workflow validation items that were
open when this section was first written are now closed. Full sign-off
record: `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`. The bullets below are kept
as the implementation-detail record; see that document for the authoritative
current status.


- **Scope: opportunity transition writes only.** Following the Phase 15B
  audit's §4.1 legal action matrix, `OpportunityCard.tsx`'s status-change
  buttons now call `seo_authority_opportunity_transition` — never a direct
  status UPDATE — through a new non-masking write helper in
  `offPageService.ts`, mirroring the Phase 13D/13E
  `runApprovalWrite`/`runContentWrite` pattern: a genuine RPC rejection
  (illegal transition, wrong role) propagates as a real, visible error
  instead of silently "succeeding" via the mock fallback. Only pre-RPC
  failures (no session, no config) still fall back to mock gracefully.
- **Role gating uses the real workspace role.** Button visibility/enablement
  reads the caller's actual `seo_workspace_members.seo_role` for the current
  workspace (not the UI's client-side role-simulation selector), matching
  the Phase 13D precedent for `addApprovalComment`'s role stamping.
- **Legal status-based button visibility implemented**, per the §4.1 matrix:
  each action (`shortlist`, `request_approval`, `request_expert_review`,
  `start`, `complete`, `reject`, `avoid`) is only shown/enabled from the
  status(es) the RPC actually allows it from, replacing the old
  unconditional-visibility mock behavior documented in
  `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` §2.1.
- **Unauthorized-but-legal actions render disabled with an explanatory
  tooltip** rather than being hidden outright or left silently clickable —
  e.g. "Reject" is visible-but-disabled (with a tooltip) for a `team_member`,
  since the RPC restricts `reject` to owner/admin.
- **Mock mode fully preserved.** No mock adapter, mock data file, or
  mock-mode behavior changed; the non-masking write helper only affects the
  Supabase-mode path.
- **Campaign writes are explicitly untouched.** `CampaignBuilder.tsx`'s
  "Create campaign" and `CampaignList.tsx` (still fully read-only) were not
  modified by this phase — campaign creation/transition remains mock-only,
  per `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` §2.2–§2.3, §4.2 (not yet built).
- **AI Visibility is unaffected.** `aiVisibilityService.ts` and its pages
  were not touched — AI Visibility remains read-only apart from its existing
  mock-only demo behavior (the "Generate AI visibility data" button and the
  unused `updateAiVisibilityItemStatus` export), unchanged since Phase
  15A/15B.
- **Authenticated TEST browser validation — confirmed passing, all 7 legal
  actions' status/role behavior, status persisted after refresh, no console
  errors:**
  - Suggested → Shortlisted
  - Shortlisted → Approval required
  - Shortlisted → Expert review requested
  - Approval required → In progress
  - In progress → Completed
  - Mark as Avoided from a legal non-terminal state
  - Reject visible but disabled for `seo-team-test@example.com` (real role
    `team_member`), with the tooltip "Requires the owner or admin role."
    appearing on both hover and keyboard focus
- **Backend evidence confirmed:** transitions recorded through the guarded
  RPC, matching `seo_authority_activity` rows with correct
  `actor_role_snapshot` values, production untouched.
- **Known limitation:** a `reject` transition executed by an owner/admin
  (as opposed to the `team_member` denial path above) was not separately
  itemized in this validation pass — see
  `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md` §11.
- **Opportunity Workflow sign-off recorded** in `CURRENT_PROJECT_STATUS.md`
  and `MODULE_LOCKS.md`. The broader Off-Page Authority module remains
  **NOT LOCKED**.
- **Not in scope for this phase:** campaign creation/transition wiring (the
  `draft` → "Submit for approval" split, and the missing campaign
  approve/reject/return-to-draft UI), and the Stage 6 final regression pass.
- **No production wiring.** All Supabase calls target the test Supabase
  project only.
- **Full sign-off record:** `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md` —
  scope, files, legal state matrix, role-gating rules, non-masking error
  behavior, validation results, persistence + activity-log verification,
  known limitations, remaining Stage 6 work, production status.

Do not mark the full Off-Page Authority module locked, and do not treat
campaign or AI Visibility writes as complete — only the Opportunity
Workflow is signed off (see `MODULE_LOCKS.md`).

> **Forward reference (Phase 15D Step 1B):** the "campaign creation ... split"
> item in this section's "Not in scope" bullet above has since been
> addressed for draft creation — an atomic `seo_authority_campaign_create` RPC
> now creates a `draft` campaign (backend-verified on TEST; authenticated
> browser validation pending). See §18 below. This section's own text is left
> unchanged as the historical record of Phase 15C's scope.

---

## 18. Phase 15D Step 1B Status — Off-Page Authority Atomic Draft Campaign Creation (Implemented + Backend-Verified on TEST, Pending Browser Validation)

> **Supersedes the original Phase 15D Step 1 approach.** Step 1 created a
> campaign with three separate PostgREST requests (campaign INSERT, junction
> INSERT, task INSERT) plus a best-effort client-side compensating DELETE —
> which is not one PostgreSQL transaction. Step 1B replaces that with a single
> atomic RPC. The compensating-delete flow and its disclosed double-failure
> residual risk no longer exist.

- **Scope: campaign creation only, always landing in `draft`.** Backed by a
  NEW additive migration, `supabase/migrations/20260712120024_seo_stage6_authority_campaign_create_rpc.sql`,
  which defines `public.seo_authority_campaign_create(p_website_id uuid,
  p_name text, p_goal text, p_owner text, p_due_date date DEFAULT NULL,
  p_opportunity_ids uuid[] DEFAULT '{}') RETURNS uuid`. `LANGUAGE plpgsql
  SECURITY DEFINER SET search_path = public` — same security pattern as the two
  existing Stage 6 transition RPCs. No already-applied migration was edited.
- **Atomicity (now true, DB-enforced):** the RPC performs the campaign INSERT,
  the junction batch INSERT, and the task batch INSERT inside ONE PL/pgSQL
  function body = one transaction. Any failure raises and rolls the whole call
  back, leaving ZERO rows — no client-side compensation. Proven on TEST by the
  verification script's forced-failure test (a temporary BEFORE INSERT trigger
  on the tasks table makes the 3rd write fail; a before/after delta shows the
  campaign + junction inserts were rolled back too — net zero).
- **Server-side authorization + validation (inside the function):** resolves
  `workspace_id`/`website_url` from `seo_websites` by `p_website_id` (client
  never supplies them); requires `auth.uid()`; requires
  `seo_role_in(ws, ['owner','admin','team_member']) OR seo_is_global_admin()`
  (clients + non-members rejected); requires non-empty name/goal; requires
  `p_owner` ∈ the four `OwnerType` values; requires every opportunity to
  belong to the same workspace + website (rejects cross-workspace); dedupes
  `p_opportunity_ids` preserving first-occurrence order.
- **Row shape written:** campaign — `approval_status` omitted so the column
  `DEFAULT 'draft'` applies (never `pending_approval`); `source` left at its
  default `'manual_seed'` (the CHECK has no app-created value and adding one
  would edit an applied migration — deliberately left, documented in the
  migration + Stage 6 NOTES). Junction — one row per deduped opportunity.
  Tasks — one per deduped opportunity, `label = suggested_action`,
  `is_complete=false`, deterministic 0-based `position`. No invented
  task/status/owner/workflow behavior.
- **Grants:** `REVOKE ALL FROM PUBLIC` + `REVOKE ALL FROM anon` +
  `GRANT EXECUTE TO authenticated` — EXECUTE is granted to `authenticated`
  only (anon revoked; `postgres`/`service_role` keep their default grants as
  with every RPC in this project). Stricter than the two existing transition
  RPCs, which left anon's default grant; the in-function check rejects anon
  anyway, but this satisfies the requirement's "authenticated only".
- **Frontend files changed:**
  - `src/services/supabase/supabaseTypes.ts` — added
    `authorityCampaignCreate: "seo_authority_campaign_create"` to `SEO_RPCS`.
  - `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` —
    `createSupabaseAuthorityCampaign` now makes a single
    `supabase.rpc(SEO_RPCS.authorityCampaignCreate, {...})` call, throws
    `AuthorityCampaignCreationError` on RPC error, then re-reads the created
    campaign via the existing `fetchSupabaseAuthorityCampaigns` mapping (so
    `opportunity_ids`/`tasks`/`progress_percentage` are derived exactly as
    everywhere else). The old 3-request body + compensating-delete + the
    `MinimalOpportunityRow` type were removed.
  - `src/services/offPageService.ts` — unchanged from Step 1: still routes
    `createAuthorityCampaign` through the non-masking `runAuthorityCampaignWrite`
    helper (pre-write failures fall back to mock; a real
    `AuthorityCampaignCreationError` is re-thrown, never masked).
  - `src/pages/seo/AuthorityBuilderPage.tsx` — unchanged from Step 1 (the
    `createCampaignMutation.isError` block still surfaces a real rejection).
    `CampaignBuilder.tsx` / `CampaignList.tsx` unchanged (the latter already
    renders the `draft` badge as "Draft").
- **Mock mode: fully preserved.** `offPageMockData.createAuthorityCampaign`
  untouched (still creates `pending_approval` in mock — a pre-existing
  mock-only quirk; the task's Supabase requirements do not touch it).
- **Backend verification on TEST (`Digi_SEO_Test`):** dry-run (BEGIN + the
  migration + ROLLBACK) left the function absent; `supabase db push --linked`
  applied only `…120024`; structural check confirmed `security_definer=true`,
  `search_path=public`, EXECUTE grantees = `authenticated`/`postgres`/
  `service_role` (anon absent); the verification script
  `supabase/test/seo_stage6_authority_campaign_create_verification.sql` PASSED
  all 13 scenarios and left the DB clean.
- **Static checks:** `npx tsc --noEmit -p tsconfig.app.json` and
  `npm run build` both passed after the rewire.
- **Not yet done:** authenticated browser validation (create a campaign
  signed-in through the real UI, confirm "Draft" + tasks + persistence). No
  sign-off document exists for this phase yet (see `CURRENT_PROJECT_STATUS.md`
  §4/§7).
- **Not in scope:** campaign submit-for-approval / approve / reject /
  return-to-draft, and task-completion writes. Opportunity transitions
  (Phase 15C) and AI Visibility were not touched.
- **Production untouched.** All Supabase work targeted the disposable TEST
  project only.

> **Forward reference (Phase 15D Step 2A):** "campaign submit-for-approval"
> in the "Not in scope" bullet above has since been implemented. See §19
> below. This section's own text is left unchanged as the historical record
> of Step 1B's scope.

---

## 19. Phase 15D Step 2A Status — Off-Page Authority Draft → Pending Approval Campaign Transition (Implemented, Pending Browser Validation)

- **Scope: the Draft → Pending Approval transition only.** Uses the
  **existing, already-applied, already-TEST-verified**
  `seo_authority_campaign_transition` RPC (migration `20260711120020`) with
  `p_action: "submit_for_approval"` — no backend change was made or needed
  this step. Approve, reject, return-to-draft, and any task-completion write
  remain explicitly unbuilt.
- **Files changed:**
  - `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` — new
    `AuthorityCampaignTransitionAction` type (deliberately narrowed to only
    `"submit_for_approval"` — a future phase must deliberately widen it to add
    more actions), new `AuthorityCampaignTransitionError` class, new private
    `callAuthorityCampaignTransition` (mirrors
    `callAuthorityOpportunityTransition` exactly), and new
    `transitionSupabaseAuthorityCampaign(id, websiteId, action, note?)` —
    calls the RPC, then re-reads the campaign via the existing
    `fetchSupabaseAuthorityCampaigns(websiteId)` mapping (campaigns have no
    single-row-by-id fetch, unlike opportunities, because `AuthorityCampaign`
    needs derived `opportunity_ids`/`tasks`/`progress_percentage` — same
    read-back approach already used by `createSupabaseAuthorityCampaign` in
    Step 1B, avoiding a duplicate derivation code path).
  - `src/services/offPageService.ts` — new
    `runAuthorityCampaignTransitionWrite` (mirrors `runAuthorityOpportunityWrite`
    exactly: pre-write failures — no session/config — fall back to mock; a
    real `AuthorityCampaignTransitionError` is re-thrown, never masked), new
    `CAMPAIGN_ACTION_TO_MOCK_STATUS` map (mock-mode-only, mirrors the RPC's
    `v_to` for this one action), and new
    `submitAuthorityCampaignForApproval(id, websiteId, note?)`.
  - `src/mocks/offPageMockData.ts` — new `updateAuthorityCampaignStatus(id,
    approvalStatus)`, mirroring `updateAuthorityOpportunityStatus`'s shape
    exactly. `createAuthorityCampaign`/`listAuthorityCampaigns` unchanged.
  - `src/pages/seo/offpage/CampaignList.tsx` — new "Submit for approval"
    button per campaign (in a new `CardFooter`, rendered only when
    `approval_status === "draft"`), new `role`/`roleGatingActive`/
    `onSubmitForApproval`/`isMutating` props, and the disabled-button tooltip
    wrapper (`<span tabIndex={0}>` + `group-hover`/`group-focus` CSS),
    reusing the exact pattern already proven in `OpportunityCard.tsx`
    (Phase 15C).
  - `src/pages/seo/AuthorityBuilderPage.tsx` — new `submitCampaignMutation`
    (invalidates the same queries as `invalidateAll`), a new
    `submitCampaignMutation.isError` block surfacing real rejections verbatim
    (matching the existing two error blocks), and the new props passed to
    `<CampaignList>`. `transitionMutation` (opportunity) and
    `createCampaignMutation` (Step 1B) are untouched.
- **UI visibility rule:** the button renders only when
  `c.approval_status === "draft"` — hidden entirely (not just disabled) for
  `pending_approval`, `approved`, and `rejected`, since `submit_for_approval`
  is status-illegal from any of those per the RPC.
- **Role gating:** enabled for `owner`/`admin`/`team_member` (the RPC's base
  manager check for this action — no extra restriction, unlike opportunity
  `reject`); disabled + tooltipped for `client`. Tooltip text is exactly
  "Requires the owner, admin, or team member role." Role gating is
  Supabase-mode-only (`roleGatingActive = isSupabaseMode()`) — mock mode has
  no real `seo_role` concept, matching every other Stage 6 action's
  precedent.
- **Non-masking write pattern:** identical contract to
  `runAuthorityOpportunityWrite`/`runAuthorityCampaignWrite` — a genuine RPC
  rejection is a real, visible error; only a pre-write failure (no session,
  no config) falls back to mock.
- **Mock-mode behavior: preserved.** The new `updateAuthorityCampaignStatus`
  mock function keeps a mock-mode click visibly equivalent to the real RPC's
  resulting status, though mock campaigns can never naturally reach `draft`
  in the first place (mock creation still creates directly as
  `pending_approval`, the same pre-existing quirk noted in Step 1/1B and
  still not touched by this step).
- **Validation performed:** `npx tsc --noEmit -p tsconfig.app.json` and
  `npm run build` both passed. A mock-mode browser regression check
  confirmed the existing seeded `approved`/`pending_approval` campaigns
  correctly render no "Submit for approval" button (status-illegal → hidden)
  with no console errors. The disabled-button tooltip markup/CSS (hover +
  keyboard focus) was additionally verified directly against the compiled
  stylesheet — confirmed hidden by default and `display: block` on real
  keyboard focus — using the same method already proven for
  `OpportunityCard.tsx` in Phase 15C.
- **Validation NOT performed:** an authenticated TEST browser validation of
  the real `draft → pending_approval` transition (sign in as a manager, click
  "Submit for approval," confirm the badge updates to "Pending approval" and
  persists after refresh) and of live role gating (a `client` session seeing
  the button disabled+tooltipped) — no TEST credentials were available in
  this task. This is the recommended immediate next step, together with Step
  1B's own still-pending browser validation. No sign-off document exists for
  this phase yet (see `CURRENT_PROJECT_STATUS.md` §4/§7).
- **Not in scope for this step:** campaign approve, reject, return-to-draft,
  and any task-completion write. Opportunity transitions (Phase 15C) and
  Step 1B campaign creation were not touched. AI Visibility was not touched.
  No migration, seed SQL, RLS policy, or TEST/production data was changed —
  this step used only the already-applied `seo_authority_campaign_transition`
  RPC.
- **No production wiring.** All Supabase calls target the test Supabase
  project only.

> **Forward reference (Phase 15D Step 2B):** the "Validation NOT performed"
> item above (authenticated TEST browser validation of `submit_for_approval`)
> and Step 1B's own pending browser validation have both since been
> confirmed done (see `CURRENT_PROJECT_STATUS.md`). "Campaign approve" in the
> "Not in scope" bullet above has since been implemented — see §20 below.
> This section's own text is left unchanged as the historical record of Step
> 2A's scope at the time it was written.

---

## 20. Phase 15D Step 2B Status — Off-Page Authority Pending Approval → Approved Campaign Transition (Implemented, Pending Owner/Admin Click-Through Validation)

- **Scope: the Pending Approval → Approved transition only.** Uses the
  **same existing, already-applied, already-TEST-verified**
  `seo_authority_campaign_transition` RPC (migration `20260711120020`) as
  Step 2A, now with `p_action: "approve"` — no backend change was made or
  needed this step. Reject, return-to-draft, and any task-completion write
  remain explicitly unbuilt.
- **Files changed:**
  - `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` —
    `AuthorityCampaignTransitionAction` widened from `"submit_for_approval"`
    (a single literal) to `"submit_for_approval" | "approve"`. No other
    change needed: `callAuthorityCampaignTransition` and
    `transitionSupabaseAuthorityCampaign` were already generic over the
    action type.
  - `src/services/offPageService.ts` — `CAMPAIGN_ACTION_TO_MOCK_STATUS`
    gained an `approve: "approved"` entry; new
    `approveAuthorityCampaign(id, websiteId, note?)`, reusing the existing
    `runAuthorityCampaignTransitionWrite` helper unchanged.
  - `src/pages/seo/offpage/CampaignList.tsx` — new "Approve" button per
    campaign (visible only when `approval_status === "pending_approval"`),
    new `onApprove` prop. The disabled-tooltip wrapper logic (previously
    inline for the one "Submit for approval" action) was extracted into a
    small shared `CampaignActionButton({ label, visible, rolePermitted,
    isMutating, deniedTooltip, onClick })` component in the same file, since
    there are now two independently role-gated campaign actions — this
    avoids duplicating the ~15-line disabled-focusable-wrapper markup a
    second time. `APPROVAL_STATUS_LABEL`, the checklist rendering, and
    `CAMPAIGN_SUBMIT_ROLES`/the submit-for-approval behavior are unchanged.
  - `src/pages/seo/AuthorityBuilderPage.tsx` — new `approveCampaignMutation`
    (invalidates the same queries as `invalidateAll`), a new
    `approveCampaignMutation.isError` block surfacing real rejections
    verbatim (matching the existing three error blocks), and `onApprove` +
    a combined `isMutating` (`submitCampaignMutation.isPending ||
    approveCampaignMutation.isPending`) passed to `<CampaignList>`.
    `transitionMutation` (opportunity), `createCampaignMutation` (Step 1B),
    and `submitCampaignMutation` (Step 2A) are all untouched.
- **UI visibility rule:** the button renders only when
  `c.approval_status === "pending_approval"` — hidden entirely (not just
  disabled) for `draft`, `approved`, and `rejected`, since `approve` is
  status-illegal from any of those per the RPC.
- **Role gating:** enabled for `owner`/`admin` only — the RPC's own extra
  restriction for this action (`IF NOT v_is_owner_admin THEN RAISE
  EXCEPTION 'Only owner/admin may approve a campaign'`), stricter than
  `submit_for_approval`'s base manager check; disabled + tooltipped for
  `team_member`/`client`. Tooltip text is exactly "Requires the owner or
  admin role." Role gating is Supabase-mode-only, matching every other
  Stage 6 action.
- **Non-masking write pattern:** identical contract, reusing
  `runAuthorityCampaignTransitionWrite` and `AuthorityCampaignTransitionError`
  unchanged from Step 2A — a genuine RPC rejection is a real, visible error;
  only a pre-write failure (no session, no config) falls back to mock.
- **Mock-mode behavior: preserved.** `updateAuthorityCampaignStatus` (Step
  2A) is reused unchanged; the new mock mapping entry
  (`CAMPAIGN_ACTION_TO_MOCK_STATUS.approve = "approved"`) keeps a mock-mode
  click visibly equivalent to the real RPC's resulting status.
- **Validation performed:** `npx tsc --noEmit -p tsconfig.app.json` and
  `npm run build` both passed. A browser regression check confirmed: a
  seeded `pending_approval` mock campaign correctly shows "Approve"
  (visibility rule); the disabled+tooltip role-denial path renders with the
  exact required copy ("Requires the owner or admin role.") — confirmed in
  this dev environment, which runs with `VITE_SEO_DATA_MODE=supabase` and no
  signed-in session, so role gating is active and correctly denies by
  default (the same, pre-existing behavior already exhibited by opportunity
  buttons — e.g. "Shortlist" — in the same session, confirming this is not a
  regression); an `approved` campaign correctly shows no action buttons at
  all; and there were no console errors throughout.
- **Validation NOT performed:** a full authenticated owner/admin
  click-through (click "Approve," confirm the badge updates to "Approved,"
  confirm it persists after refresh, confirm linked opportunities/checklist
  tasks remain intact) — no TEST credentials with an owner/admin role were
  available in this task. This is the recommended immediate next step. No
  sign-off document exists for this phase yet (see
  `CURRENT_PROJECT_STATUS.md` §4/§7).
- **Not in scope for this step:** campaign reject, return-to-draft, and any
  task-completion write. Opportunity transitions (Phase 15C), Step 1B
  campaign creation, and Step 2A submission-for-approval were not touched.
  AI Visibility was not touched. No migration, seed SQL, RLS policy, or
  TEST/production data was changed — this step used only the already-applied
  `seo_authority_campaign_transition` RPC.
- **No production wiring.** All Supabase calls target the test Supabase
  project only.

> **Forward reference (Phase 15D Step 2C):** the "Validation NOT performed"
> item above (a full owner/admin click-through for `approve`) has since been
> confirmed done (see `CURRENT_PROJECT_STATUS.md`). "Campaign reject" in the
> "Not in scope" bullet above has since been implemented — see §21 below.
> This section's own text is left unchanged as the historical record of Step
> 2B's scope at the time it was written.

---

## 21. Phase 15D Step 2C Status — Off-Page Authority Pending Approval → Rejected Campaign Transition (Implemented, Pending Owner/Admin Click-Through Validation)

- **Scope: the Pending Approval → Rejected transition only.** Uses the
  **same existing, already-applied, already-TEST-verified**
  `seo_authority_campaign_transition` RPC (migration `20260711120020`) as
  Steps 2A/2B, now with `p_action: "reject"` — no backend change was made or
  needed this step. Return-to-draft and any task-completion write remain
  explicitly unbuilt.
- **Files changed:**
  - `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` —
    `AuthorityCampaignTransitionAction` widened from
    `"submit_for_approval" | "approve"` to
    `"submit_for_approval" | "approve" | "reject"`. No other change needed:
    `callAuthorityCampaignTransition` and `transitionSupabaseAuthorityCampaign`
    were already generic over the action type.
  - `src/services/offPageService.ts` — `CAMPAIGN_ACTION_TO_MOCK_STATUS`
    gained a `reject: "rejected"` entry; new `rejectAuthorityCampaign(id,
    websiteId, note?)`, reusing the existing `runAuthorityCampaignTransitionWrite`
    helper unchanged.
  - `src/pages/seo/offpage/CampaignList.tsx` — new "Reject" button per
    campaign (visible only when `approval_status === "pending_approval"`,
    alongside "Approve"), new `onReject` prop, reusing the existing shared
    `CampaignActionButton` component unchanged. The role-array constant
    `CAMPAIGN_APPROVE_ROLES` was renamed to `CAMPAIGN_OWNER_ADMIN_ROLES`
    (and the local variable `canApprove`/`approveRolePermitted` renamed to
    `isPendingApproval`/`ownerAdminRolePermitted`) since it now gates two
    actions (`approve` and `reject`) that share the identical
    owner/admin-only restriction — matching the established precedent in
    `OpportunityCard.tsx`, which already reuses one `OWNER_ADMIN_ONLY_ROLES`
    constant across multiple actions via a `Record` mapping. No behavior
    change from this rename, only naming accuracy.
  - `src/pages/seo/AuthorityBuilderPage.tsx` — new `rejectCampaignMutation`
    (invalidates the same queries as `invalidateAll`), a new
    `rejectCampaignMutation.isError` block surfacing real rejections
    verbatim (matching the existing four error blocks), and `onReject` +
    a combined `isMutating` (`submitCampaignMutation.isPending ||
    approveCampaignMutation.isPending || rejectCampaignMutation.isPending`)
    passed to `<CampaignList>`. `transitionMutation` (opportunity),
    `createCampaignMutation` (Step 1B), `submitCampaignMutation` (Step 2A),
    and `approveCampaignMutation` (Step 2B) are all untouched.
- **UI visibility rule:** the button renders only when
  `c.approval_status === "pending_approval"` — hidden entirely (not just
  disabled) for `draft`, `approved`, and `rejected`. Approve and Reject
  render together while a campaign is pending approval, per requirement.
- **Role gating:** enabled for `owner`/`admin` only — the RPC's own extra
  restriction for this action (`IF NOT v_is_owner_admin THEN RAISE
  EXCEPTION 'Only owner/admin may reject a campaign'`), identical to
  `approve`'s restriction; disabled + tooltipped for `team_member`/`client`.
  Tooltip text is exactly "Requires the owner or admin role." Role gating
  is Supabase-mode-only, matching every other Stage 6 action.
- **Non-masking write pattern:** identical contract, reusing
  `runAuthorityCampaignTransitionWrite` and `AuthorityCampaignTransitionError`
  unchanged from Steps 2A/2B — a genuine RPC rejection is a real, visible
  error; only a pre-write failure (no session, no config) falls back to
  mock.
- **Mock-mode behavior: preserved.** `updateAuthorityCampaignStatus` (Step
  2A) is reused unchanged; the new mock mapping entry
  (`CAMPAIGN_ACTION_TO_MOCK_STATUS.reject = "rejected"`) keeps a mock-mode
  click visibly equivalent to the real RPC's resulting status.
- **Validation performed:** `npx tsc --noEmit -p tsconfig.app.json` and
  `npm run build` both passed. A browser regression check confirmed: a
  seeded `pending_approval` mock campaign correctly shows both "Approve" and
  "Reject" together (visibility rule); both render the disabled+tooltip
  role-denial path with the exact required copy ("Requires the owner or
  admin role.") — confirmed in this dev environment, which runs with
  `VITE_SEO_DATA_MODE=supabase` and no signed-in session, so role gating is
  active and correctly denies by default (the same, pre-existing behavior
  already exhibited by the Approve button and opportunity buttons in the
  same session, confirming this is not a regression); an `approved`
  campaign correctly shows neither button; and there were no console errors
  throughout.
- **Validation NOT performed:** a full authenticated owner/admin
  click-through (click "Reject," confirm the badge updates to "Rejected,"
  confirm both Approve and Reject disappear, confirm it persists after
  refresh, confirm linked opportunities/checklist tasks remain intact) — no
  TEST credentials with an owner/admin role were available in this task.
  This is the recommended immediate next step. No sign-off document exists
  for this phase yet (see `CURRENT_PROJECT_STATUS.md` §4/§7).
- **Not in scope for this step:** campaign return-to-draft and any
  task-completion write. Opportunity transitions (Phase 15C), Step 1B
  campaign creation, and Steps 2A/2B (submission-for-approval/approval)
  were not touched. AI Visibility was not touched. No migration, seed SQL,
  RLS policy, or TEST/production data was changed — this step used only the
  already-applied `seo_authority_campaign_transition` RPC.
- **No production wiring.** All Supabase calls target the test Supabase
  project only.

> **Forward reference (Phase 15D Step 2D):** the "Validation NOT performed"
> item above (a full owner/admin click-through for `reject`) has since been
> confirmed done (see `CURRENT_PROJECT_STATUS.md`). "Campaign return-to-draft"
> in the "Not in scope" bullet above has since been implemented — see §22
> below. This section's own text is left unchanged as the historical record
> of Step 2C's scope at the time it was written.

---

## 22. Phase 15D Step 2D Status — Off-Page Authority Rejected → Draft Campaign Transition (Implemented, Pending Owner/Admin Click-Through Validation)

- **Scope: the Rejected → Draft transition only, completing the campaign
  approval state machine's UI.** Uses the **same existing, already-applied,
  already-TEST-verified** `seo_authority_campaign_transition` RPC (migration
  `20260711120020`) as Steps 2A/2B/2C, now with `p_action: "return_to_draft"`
  — no backend change was made or needed this step. The RPC's
  `return_to_draft` action also legally accepts `pending_approval` as a
  from-status, but this step's UI intentionally exposes the button only from
  `rejected`, per the task's explicit scope. Campaign editing, deletion, and
  any task-completion write remain explicitly unbuilt.
- **Files changed:**
  - `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` —
    `AuthorityCampaignTransitionAction` widened from
    `"submit_for_approval" | "approve" | "reject"` to
    `"submit_for_approval" | "approve" | "reject" | "return_to_draft"`. No
    other change needed: `callAuthorityCampaignTransition` and
    `transitionSupabaseAuthorityCampaign` were already generic over the
    action type.
  - `src/services/offPageService.ts` — `CAMPAIGN_ACTION_TO_MOCK_STATUS`
    gained a `return_to_draft: "draft"` entry; new `returnCampaignToDraft(id,
    websiteId, note?)`, reusing the existing `runAuthorityCampaignTransitionWrite`
    helper unchanged.
  - `src/pages/seo/offpage/CampaignList.tsx` — new "Return to Draft" button
    per campaign (visible only when `approval_status === "rejected"`), new
    `onReturnToDraft` prop, reusing the existing shared `CampaignActionButton`
    component and `CAMPAIGN_SUBMIT_ROLES` (owner/admin/team_member, the same
    role set as `submit_for_approval`) unchanged.
  - `src/pages/seo/AuthorityBuilderPage.tsx` — new `returnToDraftMutation`
    (invalidates the same queries as `invalidateAll`), a new
    `returnToDraftMutation.isError` block surfacing real rejections verbatim
    (matching the existing five error blocks), and `onReturnToDraft` + a
    combined `isMutating` across all five campaign-transition/creation
    mutations passed to `<CampaignList>`. `transitionMutation` (opportunity),
    `createCampaignMutation` (Step 1B), `submitCampaignMutation` (Step 2A),
    `approveCampaignMutation` (Step 2B), and `rejectCampaignMutation` (Step
    2C) are all untouched.
- **UI visibility rule:** the button renders only when
  `c.approval_status === "rejected"` — hidden entirely (not just disabled)
  for `draft`, `pending_approval`, and `approved`.
- **Role gating:** enabled for `owner`/`admin`/`team_member` — the RPC's
  base manager check, identical to `submit_for_approval`'s restriction (no
  extra owner/admin-only restriction, unlike `approve`/`reject`); disabled +
  tooltipped for `client`. Tooltip text is exactly "Requires the owner,
  admin, or team member role." Role gating is Supabase-mode-only, matching
  every other Stage 6 action.
- **Non-masking write pattern:** identical contract, reusing
  `runAuthorityCampaignTransitionWrite` and `AuthorityCampaignTransitionError`
  unchanged from Steps 2A/2B/2C — a genuine RPC rejection is a real, visible
  error; only a pre-write failure (no session, no config) falls back to
  mock.
- **Mock-mode behavior: preserved.** `updateAuthorityCampaignStatus` (Step
  2A) is reused unchanged; the new mock mapping entry
  (`CAMPAIGN_ACTION_TO_MOCK_STATUS.return_to_draft = "draft"`) keeps a
  mock-mode click visibly equivalent to the real RPC's resulting status.
- **Validation performed:** `npx tsc --noEmit -p tsconfig.app.json` and
  `npm run build` both passed. Unlike Steps 2A/2B/2C's static/no-session
  regression checks, this step performed a **direct in-browser check**: a
  seeded mock campaign's `approval_status` was set to `rejected` (via the
  mock store's actual namespaced localStorage key,
  `digibility_seo_mock:authority_campaigns`) and the page reloaded — the
  campaign then correctly rendered only "Return to Draft," disabled with a
  tooltip reading exactly "Requires the owner, admin, or team member role."
  (role gating active in this dev environment: `VITE_SEO_DATA_MODE=supabase`
  with no signed-in session, consistent with every other campaign/opportunity
  button's already-established denial-by-default behavior — confirmed not a
  regression). A campaign set to `draft` correctly showed only "Submit for
  approval" (Return to Draft correctly hidden). A campaign left `approved`
  correctly showed no action buttons. No console errors occurred at any
  point. Test data was restored to its original state after the check.
- **Validation NOT performed:** a full authenticated owner/admin (or
  team_member) click-through (click "Return to Draft," confirm the badge
  updates to "Draft," confirm the button disappears and "Submit for
  approval" reappears, confirm it persists after refresh, confirm linked
  opportunities/checklist tasks remain intact) — no TEST credentials were
  available in this task. This is the recommended immediate next step. No
  Campaign Workflow sign-off document has been created yet (see
  `CURRENT_PROJECT_STATUS.md` §4/§7).
- **Not in scope for this step:** campaign editing, campaign deletion, and
  any task-completion write. Opportunity transitions (Phase 15C), Step 1B
  campaign creation, and Steps 2A/2B/2C were not touched. AI Visibility was
  not touched. No migration, seed SQL, RLS policy, or TEST/production data
  was changed — this step used only the already-applied
  `seo_authority_campaign_transition` RPC.
- **No production wiring.** All Supabase calls target the test Supabase
  project only.

> **Backend verification (Phase 15E):** the `seo_authority_campaign_transition`
> RPC underlying Steps 2A–2D now has a dedicated TEST-only SQL verification
> script — `supabase/test/seo_stage6_authority_campaign_transition_verification.sql`
> (`a8000000-` prefix) — covering all 4 legal transitions + the extra
> `pending_approval → draft` path per role, activity-row correctness
> (incl. `actor_role_snapshot`), 9 illegal-transition rejections,
> data-integrity invariants, and RLS-enforced append-only activity. **ALL
> PASS, idempotent, self-cleaning** on `Digi_SEO_Test` (2026-07-12). No
> migration, seed, RLS, or frontend code was changed. See
> `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md` §12 and
> `CURRENT_PROJECT_STATUS.md` §4.
