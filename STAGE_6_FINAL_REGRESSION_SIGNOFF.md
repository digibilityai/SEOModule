# Stage 6 — Final Regression & Lock-Readiness Assessment

**Status: The currently approved Stage 6 implementation scope passed a full
regression on TEST.** This is a regression checkpoint, **not** a module lock —
the Off-Page Authority module remains **NOT LOCKED** pending a separate lock
decision. **No application code, migration, RPC, RLS, or production data was
changed to reach this sign-off** (expected code changes: none; actual: none).

- **Date:** 2026-07-13
- **Environment:** local app `http://localhost:8090` (Vite dev, `supabase`
  mode) + a temporary throwaway `mock`-mode instance on `:8091`.
- **Supabase TEST project:** `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`).
- **Production:** never accessed or modified.

## 1. Regression scope (approved Stage 6 implementation)

1. Off-Page Authority **opportunity** reads + workflow (`seo_authority_opportunity_transition`).
2. Off-Page Authority **campaign** reads + approval workflow
   (`seo_authority_campaign_create`, `seo_authority_campaign_transition`).
3. Client + manager permission behavior.
4. Campaign-creation role gating (Phase 15D fix).
5. AI Visibility/GEO **reads**.
6. Stage 6 Supabase smoke + verification scripts.
7. Mock-mode compatibility.
8. Earlier-stage (1–5) route/service smoke.
9. Static TypeScript + production build.
10. Documentation consistency for a separate lock decision.

**Canonical Stage 6 RPCs (from `supabaseTypes.ts`):**
`seo_authority_opportunity_transition`, `seo_authority_campaign_create`,
`seo_authority_campaign_transition`.
**Relevant tables:** `seo_authority_opportunities`, `seo_authority_campaigns`,
`seo_authority_campaign_opportunities`, `seo_authority_campaign_tasks`,
`seo_authority_activity`, `seo_ai_prompt_tracking`, `seo_ai_content_gaps`,
`seo_ai_mentions`.
**Files/modules regressed:** `AuthorityBuilderPage.tsx`,
`offpage/OpportunityCard.tsx`, `offpage/CampaignBuilder.tsx`,
`offpage/CampaignList.tsx`, `offpage/RoleGateTooltip.tsx`, `AiVisibilityPage.tsx`,
`offPageService.ts`, `aiVisibilityService.ts`,
`seoOffPageAuthoritySupabaseService.ts`, `seoAiVisibilitySupabaseService.ts`.

### Explicitly deferred / out-of-scope (NOT regression failures)

Campaign task-completion writes; AI Visibility writes; real crawler / GSC /
GA4 integration; real LLM ingestion; production deployment; parent-platform /
BFF integration; mobile horizontal-overflow remediation; Competitors / Roadmap
/ Reports backend wiring; route-level `ProtectedRoute`. None were built in this
task.

## 2. Static regression

- `npx tsc --noEmit -p tsconfig.app.json` → **PASS** (clean).
- `npm run build` → **PASS** (pre-existing chunk-size advisory only).
- No service-role key in frontend code.
- No direct `approval_status` update; no direct opportunity `status` update
  bypassing the RPC.
- Creation uses `seo_authority_campaign_create` (svc line 659); transitions use
  `seo_authority_campaign_transition` (720); opportunity transitions use
  `seo_authority_opportunity_transition` (558).
- No applied migration changed; no locked Page Performance Tracker file changed.
- Shared `RoleGateTooltip` present and reused by `OpportunityCard`,
  `CampaignBuilder`, and `CampaignList`.

## 3. SQL regression (Digi_SEO_Test only)

| Script | Result |
|--------|--------|
| `supabase/test/seo_stage6_offpage_ai_visibility_smoke_test.sql` | **STAGE 6 … SMOKE TEST PASSED** |
| `supabase/test/seo_stage6_authority_campaign_create_verification.sql` | **ALL PASS** |
| `supabase/test/seo_stage6_authority_campaign_transition_verification.sql` | **ALL PASS** |

Scripts are idempotent + self-cleaning: post-run there were **0** temp-prefix
(`a7000000-`/`a8000000-`/`99999999-`) campaign or activity rows. Existing Phase
15 evidence intact (14 workspace campaigns, 9 `PHASE15D-` tagged). The scripts
collectively cover: legal transitions succeed; illegal transitions fail with no
change; role-denied transitions fail with no change; exactly one activity row
per successful transition and none for denied/illegal; correct
`actor_role_snapshot`/`created_by`; append-only activity (no UPDATE/DELETE);
atomic creation; linked-opportunity/task integrity on failures and transitions.
No production connection; no migration edited.

## 4. Supabase-mode browser regression (authenticated, focused)

Representative checks per role (temporary `puppeteer-core` + Keychain creds;
no credentials/tokens printed; temp files deleted). **No role issued any
unintended mutation request; reads persisted across refresh (14 campaigns
before/after); all signed out.**

| Check | admin (manager) | team_member | client |
|-------|-----------------|-------------|--------|
| Resolved session (supabase) | ✅ | ✅ | ✅ |
| Opportunity cards load | ✅ (9) | ✅ (9) | ✅ (9) |
| Campaign cards load | ✅ (14) | ✅ (14) | ✅ (14) |
| Opportunity selection | enabled | enabled | **disabled + tooltip + focus-reveal** |
| Opportunity `Reject` (owner/admin-only) | enabled | **disabled** | disabled |
| Other legal opp actions | enabled | enabled | disabled |
| CampaignBuilder reachable | ✅ | ✅ | **unreachable** |
| Create button | enabled | enabled | n/a (unreachable) |
| Campaign Submit (draft) | enabled | enabled | disabled + tooltip |
| Campaign Approve/Reject (pending) | enabled | **disabled + "Requires the owner or admin role."** | disabled + tooltip |
| Campaign Return to Draft (rejected) | enabled | enabled | disabled + tooltip |
| Approved campaign controls | none | none | none |
| create/transition RPC requests issued | 0 | 0 | **0** |

(Manager Create was verified enabled without clicking — no fixture created;
existing Phase 15D evidence is sufficient.)

## 5. Opportunity workflow regression

Statuses and action names unchanged; status-conditional actions correct;
team-member legal actions enabled with owner/admin-only `Reject` role-gated;
client read-only (all opportunity actions disabled). Successful transitions go
through `seo_authority_opportunity_transition`; activity append-only; no direct
frontend status update. Consistent with `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`.
No terminal evidence records were altered.

## 6. Campaign workflow regression

Status values `draft` / `pending_approval` / `approved` / `rejected` and actions
`submit_for_approval` / `approve` / `reject` / `return_to_draft` unchanged.
Owner/admin can approve + reject; team_member can create, submit, and return
rejected campaigns; client cannot create or transition. `Return to Draft` is
exposed in the UI **only** from `rejected` (the RPC also accepts it from
`pending_approval`, but that path is not newly exposed). Campaign creation is
atomic (SQL verification); no `activity_type='create'` row is introduced;
linked opportunities + tasks stable. Shared accessible tooltip behavior intact.
Consistent with `PHASE_15D_CAMPAIGN_WORKFLOW_SIGNOFF.md`.

## 7. Client create-gating regression

Post-fix behavior holds: for a real authenticated `client` the
opportunity-selection checkbox is **disabled**, wrapped in `RoleGateTooltip`
(tooltip “Requires the owner, admin, or team member role.”, `tabindex=0`,
**keyboard focus reveals it**), `CampaignBuilder` is **unreachable**, and **no
`seo_authority_campaign_create` request is issued**. Managers are unaffected
(checkbox + Create enabled). Backend RPC/RLS remain the authoritative boundary.

## 8. AI Visibility regression (read-only scope)

- Route loads under both modes. **Supabase (admin):** seeded data renders
  (“UI Seed Demo Site”, “AI Prompt Tracking”, tracked prompts), no console
  error, **0 write requests**. Website scoping correct.
- **Reads:** implemented. **Writes:** deferred. **Real LLM ingestion:**
  deferred. **Current data source:** `manual_seed`.
- The service (`seoAiVisibilitySupabaseService.ts`) contains **no**
  insert/update/delete/rpc. The page’s “Generate …” control calls
  `generateMockAiVisibilityRefresh` — an explicitly labeled **mock/demo**
  generator (“Generate mock AI visibility data … to see how this will look
  once …”), **not** a live backend write. No real LLM ingestion is claimed or
  invoked.

## 9. Mock-mode regression

Ran a throwaway `mock`-mode instance (`VITE_SEO_DATA_MODE=mock` process-env
override on `:8091`; **`.env.local` never modified**, original `supabase` mode
restored afterward — the `:8091` instance was stopped and `:8090` remains).
Results: Off-Page route loads; 9 opportunity cards render; selection remains
**enabled and ungated** (no `RoleGateTooltip` wrapper — the new client
create-role gate does **not** disable mock-mode creation); `CampaignBuilder`
usable; **campaign creation works** per the mock contract (campaign count 1→2);
AI Visibility renders mock data; 0 console errors. No SEO-role requirement was
introduced into mock mode. **No TEST/production DB write occurred** during mock
validation (real DB unchanged; 0 `MOCK-REG%` rows).

## 10. Earlier-stage (1–5) smoke regression

Authenticated (admin) route smoke — each rendered with **no crash and 0 console
errors**: Business Onboarding, Technical Audit, Approval Queue (“Nothing to
review yet”), Content Studio, **Page Performance Tracker (LOCKED — unchanged)**,
Decline Diagnosis, Websites. (Content Studio / Page Performance / Decline
Diagnosis showed the pre-existing “Complete business onboarding first” gate for
the finder-resolved website — an expected empty/gated state, not a regression.)
No shared role/tooltip change broke an unrelated page. Mock-only modules
(Competitors, Roadmap, Reports) remain mock-only and are not described as
backend-wired.

## 11. Data-integrity result

Across the entire regression: workspace `44444444-…` campaign count **14→14**,
activity count **27→27**; `campaigns_created_by_client = 0`; no stray
`REG-CHECK%` / `MOCK-REG%` / temp-prefix rows; SQL scripts self-cleaned; Phase
15C/15D tagged evidence intact; append-only activity preserved.

## 12. Known benign observations (unchanged; not repaired here)

- **Favicon 404** — static-asset request, unrelated to the workflow.
- **Sign-out `ERR_ABORTED`** on the global `/auth/v1/logout` revocation call,
  while the local session still clears (verified absent after reload).
- **~20px mobile horizontal overflow at 390px** — pre-existing, all roles;
  non-blocking; not repaired.
- **Tooltip evidence (honest):** keyboard-focus reveal and the focusable
  wrapper are **directly verified** (incl. the create/selection gate,
  `display: block` on focus); the CSS mouse-hover mechanism (`group-hover`) is
  present but **not** overstated from synthetic headless hover.

## 13. Database / API / permission / backward-compat impact

- **Database:** none. **API:** none. **Permission:** none. **Frontend:** none
  (no regression defect required a fix).
- Backward compatibility intact: existing APIs, DB records, URLs, payloads,
  service signatures, status/action/role values, mock behavior, and frontend
  read-shape types are all unchanged.

## 14. Files changed

- **Application:** none.
- **Migration:** none.
- **Documentation:** this file (new); `CURRENT_PROJECT_STATUS.md`,
  `SERVICE_LAYER_WIRING_PLAN.md`, `PROJECT_DOCUMENTATION_INDEX.md` (regression
  checkpoint). `MODULE_LOCKS.md` — status note only (Stage 6 awaiting a separate
  lock decision); **no lock added**.

## 15. Remaining risks & limitations

- Deferred features in §1 remain unbuilt (task-completion writes, AI Visibility
  writes, real crawler/GSC/GA4/LLM, `ProtectedRoute`, Competitors/Roadmap/Reports
  wiring, mobile overflow).
- All Stage 6 write authorization ultimately depends on RLS + `SECURITY DEFINER`
  RPCs (frontend gates are UX/defense-in-depth only) — verified by the SQL
  scripts and the browser matrix.
- `AuthorityBuilderPage`/`AiVisibilityPage` cross-workspace website resolution
  can land different pages on different websites; observed here only as benign
  onboarding-gate empty states.

## 16. Lock readiness

The implemented Stage 6 scope (Off-Page Authority opportunity + campaign
workflows, with AI Visibility read-only) is **READY FOR A SEPARATE MODULE-LOCK
DECISION**. This document does not itself lock the module.

**Update (2026-07-13):** that separate lock decision has since been recorded —
the implemented Stage 6 scope is now **LOCKED** under `MODULE_LOCKS.md` →
**"Stage 6 — Off-Page Authority Workflows and AI Visibility Reads"** (implemented
scope only; deferred Stage 6 work remains UNLOCKED for separately-authorized
additive implementation). This regression sign-off is the lock evidence.

## 17. Production status

Production was never accessed or modified. All validation ran against
`Digi_SEO_Test` (`snyzotgwwfomgafrsvfm`) and the local app.
