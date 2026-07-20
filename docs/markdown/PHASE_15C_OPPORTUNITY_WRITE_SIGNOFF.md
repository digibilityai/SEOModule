# Phase 15C — Off-Page Authority Opportunity Write Sign-Off

**Status: Opportunity Workflow writes implemented and authenticated
TEST-live-tested.** This document is the sign-off record for **opportunity**
transition writes only (Stage 6, `seo_authority_opportunity_transition`).
Campaign writes are explicitly **out of scope** and remain mock-only — see
§9. **No migration, seed SQL, RLS policy, or production data was touched to
reach this sign-off**; only frontend service/component code (already landed
before this document) was exercised and validated.

## Evidence Summary

*Quick-scan checklist — full detail in the numbered sections below.*

**Implementation**
- ✅ Opportunity writes implemented
- ✅ `seo_authority_opportunity_transition` is the only status write path
- ✅ No direct status UPDATE
- ✅ Real `seo_workspace_members.seo_role` gating
- ✅ Mock mode preserved

**Authenticated browser validation**
- ✅ Suggested → Shortlisted
- ✅ Shortlisted → Approval Required
- ✅ Shortlisted → Expert Review Requested
- ✅ Approval Required → In Progress
- ✅ In Progress → Completed
- ✅ Mark as Avoided
- ✅ Refresh persistence
- ✅ Reject disabled for team_member
- ✅ Reject tooltip verified
- ✅ No console errors

**Backend verification**
- ✅ Matching `seo_authority_activity` rows created
- ✅ Correct `actor_role_snapshot`
- ✅ Production untouched

**Outstanding**
- ⬜ Owner/Admin Reject execution test
- ⬜ Campaign write workflow
- ⬜ Final Stage 6 regression

> **Preflight read:** `PROJECT_BOOTSTRAP.md`, `CURRENT_PROJECT_STATUS.md`,
> `MODULE_LOCKS.md`, `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` (the proposed legal
> action matrix this phase implements), `SERVICE_LAYER_WIRING_PLAN.md` §17,
> `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` (the read-only
> phase this builds on).

---

## 1. Scope of Phase 15C Opportunity Writes

Phase 15C wires the Stage 6 **opportunity** status-transition actions
(`OpportunityCard.tsx`) through the guarded `seo_authority_opportunity_transition`
RPC, replacing the old mock-only unconditional status overwrite described in
`PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §7 and audited in
`PHASE_15B_STAGE6_WRITE_UX_AUDIT.md`. In scope:

- Calling `seo_authority_opportunity_transition` for every legal opportunity
  action, never a direct status `UPDATE`.
- Real role gating using the signed-in user's actual
  `seo_workspace_members.seo_role`.
- Legal, status-conditional button visibility (a button only renders/enables
  when the opportunity's current status legally permits that action).
- Disabled-but-visible rendering with an explanatory tooltip for actions that
  are legal-by-status but not permitted for the caller's role.
- Preserving mock mode exactly as before.

**Explicitly out of scope** (unchanged by this phase): campaign creation,
campaign transitions (`seo_authority_campaign_transition`), and any AI
Visibility write.

---

## 2. Files involved

- `src/pages/seo/AuthorityBuilderPage.tsx` — resolves the signed-in user's
  real `seo_role` (`getCurrentSeoRole`, Supabase mode only) and surfaces a
  real RPC rejection verbatim (never masked by the mock fallback).
- `src/pages/seo/offpage/OpportunityCard.tsx` — the legal action/status/role
  matrices, button rendering (visible/hidden/disabled), and the
  disabled-button tooltip (hover + keyboard focus).
- `src/services/offPageService.ts` — `transitionAuthorityOpportunity` +
  `runAuthorityOpportunityWrite` (the non-masking write helper).
- `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` —
  `transitionSupabaseAuthorityOpportunity`, `callAuthorityOpportunityTransition`,
  `AuthorityOpportunityTransitionError`, and the
  `AuthorityOpportunityTransitionAction` action-name union.

No migration, seed SQL, RLS policy, or mock data file was changed to reach
this sign-off.

---

## 3. Exact transition actions implemented

All 7 legal actions from `seo_authority_opportunity_transition`'s `CASE`
statement (`supabase/migrations/20260711120020_seo_stage6_authority_activity.sql`)
are represented, exactly named, with no invented action:

| Action | UI label |
| --- | --- |
| `shortlist` | "Shortlist" |
| `request_approval` | "Request approval" |
| `request_expert_review` | "Send to expert review" |
| `start` | "Start" |
| `complete` | "Mark completed" |
| `reject` | "Reject" |
| `avoid` | "Mark as avoided" |

---

## 4. Legal state matrix (as implemented, mirrors the RPC exactly)

| Action | Legal `from` status(es) | Resulting status |
| --- | --- | --- |
| `shortlist` | `suggested` | `shortlisted` |
| `request_approval` | `shortlisted` | `approval_required` |
| `request_expert_review` | `shortlisted`, `approval_required`, `in_progress` | `expert_review_requested` |
| `start` | `approval_required`, `expert_review_requested` | `in_progress` |
| `complete` | `in_progress` | `completed` |
| `reject` | `suggested`, `shortlisted`, `approval_required`, `in_progress`, `expert_review_requested` (any non-terminal) | `rejected` |
| `avoid` | `suggested`, `shortlisted`, `approval_required`, `in_progress`, `expert_review_requested` (any non-terminal) | `avoided` |

A button for a given action only renders when the opportunity's current
status is in that action's legal `from` list — this is a UX convenience, not
the authorization boundary; the RPC re-validates every transition
server-side regardless of what the UI decides to show.

---

## 5. Role-gating rules

- **Base check (all actions except `reject`):** `owner`, `admin`,
  `team_member`.
- **`reject` only:** `owner`, `admin` — the one action the RPC restricts
  beyond the base check.
- Role is read from the signed-in user's real `seo_workspace_members.seo_role`
  for the opportunity's workspace (`getCurrentSeoRole`), **not** the UI's
  client-side role-simulation selector.
- **Role gating is Supabase-mode-only** (`roleGatingActive` = `isSupabaseMode()`).
  Mock mode has no `seo_workspace_members` rows at all, so every
  legal-by-status action stays enabled in mock mode — unchanged pre-existing
  behavior, not a gap.
- A legal-by-status action the caller's role doesn't permit renders
  **visible, disabled**, with a tooltip reading exactly "Requires the owner
  or admin role." (2-role case) or "Requires the owner, admin, or team
  member role." (3-role case). The tooltip is attached to a focusable
  wrapper `<span>` around the disabled button (a disabled native button
  can't reliably receive hover or keyboard focus), and works on both mouse
  hover and keyboard (Tab) focus.

---

## 6. Non-masking error behavior

Mirrors the Phase 13D (`ApprovalTransitionError`) / Phase 13E
(`ContentTransitionError`) pattern exactly:

- `seoOffPageAuthoritySupabaseService.ts`'s `callAuthorityOpportunityTransition`
  throws `AuthorityOpportunityTransitionError` whenever the RPC itself
  rejects the call (illegal transition for the row's current status, role
  not permitted, opportunity not found, unknown action).
- `offPageService.ts`'s `runAuthorityOpportunityWrite` re-throws
  `AuthorityOpportunityTransitionError` as-is — it is **never** swallowed
  into a mock "success". Only a genuine pre-RPC failure (no session, no
  Supabase config) falls back to mock.
- `AuthorityBuilderPage.tsx` surfaces the resulting error message verbatim in
  the UI (`transitionMutation.isError`) rather than silently no-op'ing.

---

## 7. Authenticated TEST browser validation — results

All confirmed passing, signed in against the TEST project (`Digi_SEO_Test`),
in a real browser:

1. Suggested → Shortlisted — ✅ passed
2. Shortlisted → Approval Required — ✅ passed
3. Shortlisted → Expert Review Requested — ✅ passed
4. Approval Required → In Progress — ✅ passed
5. In Progress → Completed — ✅ passed
6. Mark as Avoided from a legal non-terminal state — ✅ passed
7. Status persisted after page refresh — ✅ passed (all of the above)
8. Reject visible but disabled for `seo-team-test@example.com` (real role
   `team_member`) — ✅ passed
9. Reject tooltip appeared on both hover and keyboard focus, reading exactly
   "Requires the owner or admin role." — ✅ passed
10. No console errors during any of the confirmed validations — ✅ passed

**Note on `reject`:** validations #8–#9 confirm the role-gated
**disabled-state and tooltip** behavior for a `team_member`. A successful
`reject` transition **executed by an owner/admin** was not separately
itemized in this validation pass — see §11 (Known Limitations). All 6 of the
other 7 actions have a confirmed, successfully executed transition; `reject`
has a confirmed, correct *denial* path.

---

## 8. Persistence verification

Every transition in §7 (items 1–6) was confirmed to persist after a full
page refresh — the opportunity's status survives a reload rather than
reverting or reflecting stale client-side state, matching the RPC being the
single source of truth for status (no direct `UPDATE`, no client-side
optimistic-only state).

---

## 9. Activity-log verification

Backend evidence already confirmed for the transitions exercised above:

- Each transition was recorded through the guarded
  `seo_authority_opportunity_transition` RPC (never a direct status
  `UPDATE`).
- A matching `seo_authority_activity` row was created for each transition
  (append-only audit trail, written server-side by the RPC).
- `actor_role_snapshot` on those activity rows correctly reflected the
  acting user's real role at the time of the transition.
- Production was untouched throughout.

---

## 10. Mock-mode status

**Fully preserved, unchanged.** `roleGatingActive` is `false` in mock mode,
so every legal-by-status action stays enabled exactly as before this phase;
`ACTION_TO_MOCK_STATUS` in `offPageService.ts` keeps a mock-mode click
visibly equivalent to the real RPC's resulting status. No mock adapter or
mock data file was modified.

---

## 11. Known limitations

- **`reject` executed by an owner/admin was not separately validated** in
  this pass (only the `team_member` denial/tooltip path was). The
  role-gating logic is identical to every other action's base-check pattern
  and `reject`'s RPC branch is already smoke-tested server-side (Stage 6
  backend notes), but an explicit owner/admin-executed `reject` UI
  transition + persistence check remains a recommended follow-up smoke
  check, not a blocking gap.
- **Campaign writes remain mock-only. Opportunity writes are fully
  implemented through `seo_authority_opportunity_transition` and are not
  affected by this limitation.** Campaign creation still bundles two backend
  operations into one UI action (skips `draft` + its own
  `submit_for_approval` audit entry), and the campaign approve/reject/
  return-to-draft workflow has no UI at all. See
  `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` §2.2–§2.3, §4.2.
- **AI Visibility remains read-only** apart from its existing mock-only demo
  behavior (the "Generate AI visibility data" empty-state button and the
  unused `updateAiVisibilityItemStatus` export) — unchanged since Phase
  15A/15B.
- **No Stage 6 final regression pass** has been recorded yet (confirming no
  other module — Page Performance, Decline Diagnosis, Content Studio, etc. —
  regressed as a side effect of this phase).
- **No real GSC/GA4/crawler/LLM/scraper/outreach/review-generation/backlink-automation**
  anywhere in Stage 6 — all TEST data is `manual_seed` demo content.

---

## 12. Definition of Done

Opportunity Writes are considered **complete** because:

- All supported opportunity transitions are implemented.
- The guarded RPC (`seo_authority_opportunity_transition`) is the only
  status write path.
- Role gating matches backend authorization.
- Persistence was verified.
- Authenticated browser testing passed.
- Activity logging was verified.
- Mock mode remains intact.
- Production was untouched.

**The Opportunity Workflow is SIGNED OFF.**

**The overall Off-Page Authority module remains NOT LOCKED** because
campaign writes and final Stage 6 regression are still outstanding (see §13
below).

---

## 13. Remaining Stage 6 work

1. Campaign creation split: "Create campaign" (→ `draft`, matching the
   column default) + a new, separate "Submit for approval" action
   (`draft → pending_approval` via `submit_for_approval`).
2. Build the missing campaign action set in `CampaignList.tsx`: submit /
   approve / reject / return-to-draft, role-gated per
   `PHASE_15B_STAGE6_WRITE_UX_AUDIT.md` §4.2 (approve/reject owner/admin
   only).
3. Wire the above through the existing, unmodified
   `seo_authority_campaign_transition` RPC using the same non-masking write
   pattern as this phase.
4. Live-test each campaign transition per role, signed in against TEST.
5. Run a Stage 6 final regression pass across Off-Page Authority + AI
   Visibility + every other already-wired module.
6. Only after 1–5 pass: consider the full Off-Page Authority module (not
   just the Opportunity Workflow) for `MODULE_LOCKS.md` LOCKED status.

---

## 14. Production status

**Production has NOT been touched.** No production migration, data,
connection, or deploy occurred as part of this phase or this sign-off. All
validation in §7 ran against the disposable TEST Supabase project
(`Digi_SEO_Test`) only.
