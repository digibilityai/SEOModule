# Phase 15D — Off-Page Authority Campaign Workflow Sign-Off

**Status: Campaign creation + transition writes implemented and authenticated
TEST-live-tested across all four roles (owner, admin, team_member, client).**
This document is the sign-off record for **campaign** writes (Stage 6):
atomic creation via `seo_authority_campaign_create` and the approval state
machine via `seo_authority_campaign_transition`
(submit_for_approval / approve / reject / return_to_draft). **No migration,
seed SQL, RLS policy, RPC, or production data was touched to reach this
sign-off** — the only code change in this phase was a frontend permission-
affordance fix (see §3). Campaign **task-completion** writes and AI Visibility
writes remain out of scope.

## Evidence Summary

*Quick-scan checklist — full detail in the numbered sections below.*

**Implementation**
- ✅ Campaign creation via `seo_authority_campaign_create` (atomic: row + junction + tasks in one transaction)
- ✅ Campaign transitions via `seo_authority_campaign_transition` (guarded RPC)
- ✅ No direct `approval_status` UPDATE anywhere in frontend
- ✅ Real `seo_workspace_members.seo_role` gating; RPC/RLS remain the authoritative boundary
- ✅ Non-masking error behavior (real RPC rejection surfaces; never faked as mock success)
- ✅ Mock mode preserved (role gating inactive when `roleGatingActive` is false)

**Authenticated browser validation (TEST — Digi_SEO_Test)**
- ✅ owner: full approval path + rejection/return path
- ✅ admin: full approval path + rejection/return path
- ✅ team_member: create + submit permitted; approve/reject denied (disabled + tooltip); return-to-draft permitted
- ✅ client: read-only — create/submit/approve/reject/return all denied; **zero writes**
- ✅ Persistence after refresh at every step
- ✅ Double-submit protection (disabled-while-pending; deliberate double-click → one row)

**Backend verification**
- ✅ Exactly one `seo_authority_activity` row per transition; no duplicates
- ✅ Correct `subject_type`, `from_status`, `to_status`, `actor_role_snapshot`, `created_by`
- ✅ No creation activity row (by design — creation is not a transition)
- ✅ Linked opportunities + tasks unchanged across transitions
- ✅ Production untouched

**Create-gating correction (this task)**
- ✅ Original defect (client could reach an enabled Create button) fixed in the frontend
- ✅ Client selection control + Create action now role-gated; no create RPC request issued
- ✅ Manager roles unaffected; `tsc` + `build` clean

**Outstanding**
- ⬜ Stage 6 final regression pass (next task)
- ⬜ Campaign task-completion writes
- ⬜ AI Visibility writes
- ⬜ Off-Page Authority module lock decision

> **Preflight read:** `PROJECT_BOOTSTRAP.md`, `CURRENT_PROJECT_STATUS.md`,
> `MODULE_LOCKS.md`, `PHASE_15C_OPPORTUNITY_WRITE_SIGNOFF.md`,
> `SERVICE_LAYER_WIRING_PLAN.md` §17–§18.

---

## 1. TEST environment

- **Supabase project:** `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`).
- **Local application:** `http://localhost:8090`, `VITE_SEO_DATA_MODE=supabase`.
- **Workspace/website exercised:** `44444444-0000-0000-0001-000000000001` /
  `https://ui-seed-digibility.example` (the shared workspace where all four
  test users hold their respective roles and which carries the seeded
  authority opportunities).
- **Validation date:** 2026-07-13.
- **Method:** temporary `puppeteer-core@23.11.1` under `/tmp` driving the
  installed Google Chrome; each role's password retrieved internally from
  macOS Keychain, never printed/logged/stored; DB evidence via read-only
  `supabase db query --linked`. No repository dependency was added.
- **Production:** never accessed or modified.

## 2. Authenticated role results

Authenticated user identity was confirmed each run against
`seo_workspace_members.seo_role` (resolved from the DB, not a UI role selector).

| Role | UUID | Resolved seo_role | Result |
|------|------|-------------------|--------|
| owner | `48c479db-…baaa` | `owner` | **PASS** |
| admin | `9830c4d7-…bd73` | `admin` | **PASS** |
| team_member | `0723d21f-…f58c` | `team_member` | **PASS** |
| client | `6c7a04e0-…092c` | `client` | **PASS** (after create-gating fix) |

**owner / admin** — Campaign A approval path
(create→draft→submit→pending_approval→approve→approved) and Campaign B
rejection/return path
(create→draft→submit→pending_approval→reject→rejected→return_to_draft→draft),
each with refresh-persistence at every step. All transitions produced exactly
one activity row with the correct role snapshot and `created_by`.

**team_member** — Permitted: create (→draft), submit_for_approval
(→pending_approval), return_to_draft (rejected→draft, against a dedicated
admin-prepared rejected fixture). Denied: approve, reject — both rendered
**disabled with the tooltip “Requires the owner or admin role.”**, clicks were
no-ops, status stayed `pending_approval`, and **no approve/reject activity
row** was written.

**client** — Read: all workspace campaigns visible (RLS
`is_seo_workspace_member(workspace_id)`), all four status fixtures rendered
correctly, visibility retained after refresh. Write-denial: create, submit,
approve, reject, return-to-draft all denied; approved campaigns expose no
workflow controls. **The client produced zero writes** (campaign count and
activity count unchanged; `campaigns_created_by_client = 0`,
`activity_by_client = 0`).

## 3. The original client create-gating defect and the fix

**Defect (found during client validation, before this task):** the campaign
**Create** control was not role-gated in the UI. A real `client` could select
an opportunity, reach `CampaignBuilder`, fill name/goal, and click an enabled
**Create campaign** button, which issued a `POST …/rpc/seo_authority_campaign_create`
request. The backend RPC correctly **rejected** it (HTTP 400, surfaced as a
console error) and **no campaign or activity row was created** — so
authorization was never bypassed — but the UI affordance and the outbound
request were inconsistent with the (already gated) transition controls.

**Root cause:** `CampaignBuilder.tsx`’s `canCreate` checked only form
validity; `AuthorityBuilderPage.tsx` rendered `CampaignBuilder` without a role
gate; and the opportunity-select checkbox in `OpportunityCard.tsx` was always
enabled.

**Fix (frontend only, defense-in-depth, this task):**
- New shared `src/pages/seo/offpage/RoleGateTooltip.tsx` — extracts the
  existing accessible focusable-wrapper tooltip pattern (previously inlined in
  `CampaignList`’s `CampaignActionButton`) into one reusable component.
- `OpportunityCard.tsx` — the selection checkbox is **disabled** for a real
  authenticated non-manager (Supabase mode), wrapped in `RoleGateTooltip`
  (tooltip “Requires the owner, admin, or team member role.”). This is the
  primary gate: with no selection, `CampaignBuilder` never renders.
- `CampaignBuilder.tsx` — additive `createRolePermitted` prop (defaults
  `true`); the **Create campaign** button is disabled + wrapped in
  `RoleGateTooltip` when denied, and `handleCreate` refuses to fire when
  role-denied (secondary gate against stale selection state).
- `AuthorityBuilderPage.tsx` — computes `createRolePermitted` from the real
  `currentSeoRole` against the reused `CAMPAIGN_SUBMIT_ROLES`
  (`owner`/`admin`/`team_member`) and passes it to `CampaignBuilder`.
- `CampaignList.tsx` — `CampaignActionButton` refactored to use the shared
  `RoleGateTooltip` (identical markup, behavior preserved); `CAMPAIGN_SUBMIT_ROLES`
  exported so the create gate reuses the exact existing role list.

**Backend authorization was never weakened or bypassed.** The frontend gate
only prevents an ordinary-UI unauthorized request and provides consistent
feedback; `seo_authority_campaign_create` / `seo_authority_campaign_transition`
remain the authoritative authorization layer, as verified by the existing SQL
RPC-rejection scripts.

**Post-fix client revalidation (TEST, authenticated):**
- Opportunity-select checkbox **disabled** for the client, wrapped, `tabindex=0`,
  tooltip “Requires the owner, admin, or team member role.”, **keyboard focus
  reveals the tooltip** (`display: block`).
- Ordinary interaction cannot select → `CampaignBuilder` does **not** appear.
- **Zero `seo_authority_campaign_create` requests** issued; **no 400 console
  error** (only the benign favicon 404 remained).
- Workspace campaign count and activity count unchanged; client-created count
  still 0; no stray rows.
- Regression: submit/approve/reject/return still disabled; approved campaigns
  expose no controls; no transition request issued; statuses unchanged.
- Manager positive check (admin): selection checkbox **enabled** (no wrapper),
  `CampaignBuilder` appears, **Create campaign enabled** after filling the form
  (not clicked — no fixture created).

## 4. Legal transition coverage (as implemented, mirrors the RPC)

| From | Action | To | Roles permitted (UI + RPC) |
|------|--------|----|----------------------------|
| draft | submit_for_approval | pending_approval | owner, admin, team_member |
| pending_approval | approve | approved | owner, admin |
| pending_approval | reject | rejected | owner, admin |
| rejected | return_to_draft | draft | owner, admin, team_member |
| (creation) | `seo_authority_campaign_create` | draft | owner, admin, team_member |

All five were exercised live by at least one permitted role; owner and admin
covered the full path; team_member covered submit + return; approve/reject
role-denial was verified for team_member and client; all writes were denied for
client.

## 5. Denied-action coverage

- **team_member:** approve, reject → disabled + tooltip “Requires the owner or
  admin role.”; no activity written.
- **client:** create (checkbox + Create button gated, no request),
  submit_for_approval, approve, reject, return_to_draft → all disabled + role
  tooltip; approved campaigns expose no controls; no activity written; no
  transition/create request issued.

## 6. Persistence evidence

For every transition, the UI badge matched the DB `approval_status` before the
action, after the action, and after a hard browser refresh. Final DB states of
the evidence campaigns (left in place):

- owner A `approved`, owner B `draft`; admin A `approved`, admin B `draft`.
- team A `pending_approval`; team return-fixture `draft` (admin submit→reject,
  team return_to_draft).
- client rejected-fixture `rejected` (admin-prepared; client could not change
  it).

## 7. Activity-log evidence

Append-only `seo_authority_activity`, one row per transition, no duplicates.
Representative owner run — Campaign A (2 rows): `submit_for_approval`
(draft→pending_approval), `approve` (pending_approval→approved); Campaign B
(3 rows): `submit_for_approval`, `reject` (pending_approval→rejected),
`return_to_draft` (rejected→draft). Each row carried `subject_type='campaign'`,
correct `from_status`/`to_status`, `actor_role_snapshot` equal to the acting
role, and `created_by` equal to the authenticated user UUID. **No
`activity_type='create'` row** is written for campaign creation (confirmed
design). The team return-fixture retained its admin `submit_for_approval` +
`reject` rows unchanged, plus exactly one team `return_to_draft` row.

## 8. Role snapshot and `created_by` evidence

Every activity row's `actor_role_snapshot` matched the DB-resolved role of the
actor (owner/admin/team_member), and every `created_by` matched the
authenticated user's UUID. Campaign `created_by` matched the creating user.
No client-authored campaign or activity row exists.

## 9. Linked-opportunity and task integrity

Each created campaign retained exactly its linked opportunities
(`seo_authority_campaign_opportunities`) and tasks
(`seo_authority_campaign_tasks`) unchanged across all transitions (e.g. 1
linked opportunity + 1 task per fixture, stable before/after each action).

## 10. Double-submit protection

Mutation controls report `disabled` while pending; a deliberate double-click on
**Create** produced a single draft campaign; each transition produced exactly
one activity row (no duplicate transition activity).

## 11. Static + code verification (this task)

- `npx tsc --noEmit -p tsconfig.app.json` → **clean**.
- `npm run build` → **success** (pre-existing chunk-size advisory only).
- No service-role key in frontend code.
- No direct `approval_status` UPDATE.
- Creation still uses `seo_authority_campaign_create`; transitions still use
  `seo_authority_campaign_transition`.
- No migration added or edited; no RLS/RPC/table/column/status/role change.
- No locked Page Performance Tracker file touched.

## 12. Mock-mode status

Mock mode is preserved. The new gates are guarded by
`!roleGatingActive || …` (OpportunityCard selection) and by
`createRolePermitted` defaulting to `true` / `!isSupabaseMode()`
(AuthorityBuilderPage), so when role gating is inactive (mock mode has no real
`seo_role`) opportunity selection and campaign creation stay fully enabled,
unchanged from prior behavior. Guaranteed by the short-circuit logic and
confirmed by `tsc`/`build`; not separately runtime-exercised in a mock server
this pass.

## 13. Known benign observations (carried forward, not fixed here)

- **Favicon 404** — a static-asset request unrelated to the workflow.
- **Sign-out `ERR_ABORTED`** — the global-scope `/auth/v1/logout` revocation
  call is aborted, while the local session still clears (verified absent after
  reload).
- **~20px mobile horizontal overflow at 390px** — pre-existing, present for all
  roles; non-blocking; **not** fixed in this task.
- **Tooltip evidence (honest):** disabled-control role tooltips were verified by
  reading rendered text and by **keyboard focus** revealing the tooltip
  (`display: block`), including the new create/selection gate. The CSS
  mouse-hover mechanism (`group-hover:block`) is present but was not directly
  observed via synthetic headless hover — not overstated.

## 14. Files changed

**Application (frontend only):**
- `src/pages/seo/offpage/RoleGateTooltip.tsx` (new)
- `src/pages/seo/offpage/OpportunityCard.tsx`
- `src/pages/seo/offpage/CampaignBuilder.tsx`
- `src/pages/seo/offpage/CampaignList.tsx`
- `src/pages/seo/AuthorityBuilderPage.tsx`

**Migration / API / RPC / RLS:** none.

**Documentation:** this file; plus `CURRENT_PROJECT_STATUS.md`,
`SERVICE_LAYER_WIRING_PLAN.md`, `PROJECT_DOCUMENTATION_INDEX.md`.

## 15. Rollback plan

Frontend-only. Revert exactly the five application files listed in §14
(deleting `RoleGateTooltip.tsx` and reverting the other four to restore the
inline `CampaignActionButton` wrapper and the ungated Create/selection
controls). No database rollback, migration, or data cleanup is required. The
tagged Phase 15D TEST evidence campaigns remain intact.

## 16. Remaining Stage 6 work

- **Stage 6 final regression pass** — the next task.
- Campaign **task-completion** writes (checklist item completion) — not yet
  wired.
- AI Visibility writes — remain read-only apart from existing mock demo
  behavior.
- Off-Page Authority **module lock** decision — a separate task after the
  regression pass; this sign-off does **not** lock the module.

## 17. Production status

Production was never accessed or modified. All validation ran against
`Digi_SEO_Test` (`snyzotgwwfomgafrsvfm`) and `http://localhost:8090`.
