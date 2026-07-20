# Phase 15B — Stage 6 Write UX Audit (Off-Page Authority + AI Visibility)

**Status: AUDIT ONLY. No application code, migration, seed SQL, RLS, or
production data was changed by this task.** This document inventories every
current mock-only UI write action for Off-Page Authority + AI Visibility and
compares each one against the actual legal state machine enforced by the
Stage 6 transition RPCs (`seo_authority_opportunity_transition`,
`seo_authority_campaign_transition` — `supabase/migrations/20260711120020_seo_stage6_authority_activity.sql`).
**No write has been wired to Supabase as a result of this audit.** Writes
remain 100% mock-only in every data mode, exactly as left by Phase 15A (see
`PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §7).

> **Preflight read:** `PROJECT_DOCUMENTATION_INDEX.md`,
> `CURRENT_PROJECT_STATUS.md`, `DOCUMENTATION_WORKFLOW_RULES.md`,
> `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md`,
> `SERVICE_LAYER_WIRING_PLAN.md` §16,
> `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md`,
> `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_PLAN.md` §0 (D5/D5a),
> `src/pages/seo/AuthorityBuilderPage.tsx`, `src/pages/seo/AiVisibilityPage.tsx`,
> `src/services/offPageService.ts`, `src/services/aiVisibilityService.ts`,
> `src/services/supabase/seoOffPageAuthoritySupabaseService.ts`, the two
> transition RPC bodies (`20260711120020_seo_stage6_authority_activity.sql`),
> and the Phase 13D/13E non-masking-write pattern
> (`approvalService.ts`'s `runApprovalWrite`/`ApprovalTransitionError`,
> `contentStudioService.ts`'s `runContentWrite`/`ContentTransitionError`).

---

## 1. The legal backend state machine (ground truth for this audit)

Read directly from `seo_authority_opportunity_transition` /
`seo_authority_campaign_transition` in
`supabase/migrations/20260711120020_seo_stage6_authority_activity.sql` — the
**only** legal path for a status change; a direct `UPDATE` is not how these
RPCs work and RLS's plain `FOR ALL` write policy on `seo_authority_opportunities`/
`seo_authority_campaigns` would technically *allow* a raw UPDATE from
owner/admin/team_member, but the RPC is the documented, audited, D5-mandated
path (see plan §0 D5: "Off-Page status movement goes through SECURITY DEFINER
transition RPCs... not free-form status UPDATEs").

### 1.1 Opportunity RPC (`seo_authority_opportunity_transition`)

| Action (`p_action`) | Legal `from` status(es) | `to` status | Role check |
| --- | --- | --- | --- |
| `shortlist` | `suggested` | `shortlisted` | owner/admin/team_member (base check) |
| `request_approval` | `shortlisted` | `approval_required` | owner/admin/team_member |
| `request_expert_review` | `shortlisted`, `approval_required`, `in_progress` | `expert_review_requested` | owner/admin/team_member |
| `start` | `approval_required`, `expert_review_requested` | `in_progress` | owner/admin/team_member |
| `complete` | `in_progress` | `completed` | owner/admin/team_member |
| `reject` | any **non-terminal** (not `completed`/`rejected`/`avoided`) | `rejected` | **owner/admin only** (extra check beyond the base) |
| `avoid` | any **non-terminal** | `avoided` | owner/admin/team_member |
| *(anything else)* | — | — | `RAISE EXCEPTION 'Unknown authority opportunity action'` |

No `pause`, `cancel`, or any other action exists — the `CASE` statement's
`ELSE` branch rejects every action name not in the table above. Terminal
states (`completed`, `rejected`, `avoided`) can never be re-entered by any
action.

### 1.2 Campaign RPC (`seo_authority_campaign_transition`)

| Action (`p_action`) | Legal `from` status(es) | `to` status | Role check |
| --- | --- | --- | --- |
| `submit_for_approval` | `draft` | `pending_approval` | owner/admin/team_member |
| `approve` | `pending_approval` | `approved` | **owner/admin only** |
| `reject` | `pending_approval` | `rejected` | **owner/admin only** |
| `return_to_draft` | `pending_approval`, `rejected` | `draft` | owner/admin/team_member |
| *(anything else)* | — | — | `RAISE EXCEPTION 'Unknown authority campaign action'` |

No `start`, `complete`, `pause`, or `cancel` action exists for campaigns —
`approved` is the terminal "cleared to execute" state; campaign *execution*
progress is tracked separately via `seo_authority_campaign_tasks`
(`is_complete` per task, D6), never via `approval_status`.

### 1.3 What both RPCs guarantee, independent of any specific action

- Every successful call writes exactly one append-only `seo_authority_activity`
  row (`from_status`/`to_status`/`activity_type`/`actor_role_snapshot`).
- The base manager check (owner/admin/team_member) runs **inside** the
  function for every action; `reject` (opportunity), `approve`, and `reject`
  (campaign) additionally require owner/admin. Clients and non-members are
  rejected in-function even though `EXECUTE` is granted to `authenticated`
  (D3: no client writes anywhere in Stage 6).
- `EXECUTE` is `GRANT`ed to `authenticated` on both RPCs, but they are **not
  called from any UI today** — see §3.

---

## 2. Current UI inventory — every write-capable action, as it exists today

### 2.1 `OpportunityCard.tsx` (rendered from `AuthorityBuilderPage.tsx`)

All six buttons below call the same prop, `onStatusChange(id, status)`, wired
in `AuthorityBuilderPage.tsx` to `statusMutation.mutate({ id, status })` →
`offPageService.updateAuthorityOpportunityStatus(id, status)` →
(mock-only) `offPageMockData.updateAuthorityOpportunityStatus` — which does
**no source-status check whatsoever**: it unconditionally overwrites
`status` to whatever the button passed, for any opportunity in any current
state.

**Non-risky branch** (`opportunity.risk !== "high" && spam_risk_flags.length === 0`) — all four buttons render together, unconditionally, regardless of the opportunity's current status:

| # | Button label | Mock call | Current source status shown for | Target status | RPC action equivalent | Legal from RPC? | Approval required? | Role restriction? | Recommendation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | "Shortlist" | `updateAuthorityOpportunityStatus(id, "shortlisted")` | any (unconditional) | `shortlisted` | `shortlist` | **Only when current status = `suggested`.** Illegal from any other status. | No | owner/admin/team_member — UI has no role gating at all today | **Kept**, but must be **conditionally hidden/disabled** except when status is `suggested` |
| 2 | "Mark in progress" | `updateAuthorityOpportunityStatus(id, "in_progress")` | any (unconditional) | `in_progress` | `start` | **Only when current status is `approval_required` or `expert_review_requested`.** Illegal from `suggested`/`shortlisted` — the two statuses this button is actually reachable from in normal use today, since nothing currently drives an opportunity into `approval_required`. | **Yes — this is the entire point of the RPC's `start` guard** (requirement 7: external-facing action must pass approval first) | Same as above, no UI gating | **Renamed to "Start"** and **hidden/disabled** except when status is `approval_required`/`expert_review_requested`. Currently misleading — it looks like a normal "move forward" button but is illegal from the two statuses the UI actually starts opportunities in. |
| 3 | "Mark completed" | `updateAuthorityOpportunityStatus(id, "completed")` | any (unconditional) | `completed` | `complete` | Only when current status = `in_progress` | No | Same, no UI gating | **Kept**, gate to `in_progress` only |
| 4 | "Reject" | `updateAuthorityOpportunityStatus(id, "rejected")` | any (unconditional) | `rejected` | `reject` | Any non-terminal status | No | **owner/admin only — UI has NO role check; a `client`/`team_member`-simulated role can click this today with no warning** | **Kept**, but must add **role gating** (hide/disable for team_member and client) — this is the single clearest role-legality gap in the current UI |

**Risky branch** (`risk === "high" \|\| spam_risk_flags.length > 0`) — two buttons render together, unconditionally:

| # | Button label | Mock call | Current source status shown for | Target status | RPC action equivalent | Legal from RPC? | Approval required? | Role restriction? | Recommendation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 5 | "Mark as Avoided" | `updateAuthorityOpportunityStatus(id, "avoided")` | any (unconditional) | `avoided` | `avoid` | Any non-terminal status | No | owner/admin/team_member — matches (no client) but UI still has no explicit check | **Kept as-is conceptually** — this is the most backend-compatible button in the file; only needs a "not already terminal" guard for robustness |
| 6 | "Send to Expert Review" | `updateAuthorityOpportunityStatus(id, "expert_review_requested")` | any (unconditional) | `expert_review_requested` | `request_expert_review` | **Only when current status is `shortlisted`, `approval_required`, or `in_progress`.** Illegal from `suggested` — a brand-new risky suggestion has not been shortlisted yet, so this is illegal in exactly the state it is most likely to be clicked from. | No (this *is* the approval-alternative path) | owner/admin/team_member, no UI gating | **Kept**, gate to hide/disable when status = `suggested` (or any terminal) |

**Disabled placeholder** (shown when `opportunity.requires_approval === true`, any branch):

| # | Button label | Mock call | Notes | Recommendation |
| --- | --- | --- | --- | --- |
| 7 | "Send to Approval Queue — coming soon" | none (`disabled`, no `onClick`) | Not wired to anything. Label conflates with the unrelated **Stage 2** `seo_approval_items` queue — Stage 6 has its own, separate `approval_required` status reached via the RPC's `request_approval` action, not Stage 2's queue. | **Rename** to something Stage-6-accurate (e.g. "Request approval") and **rebuild** as the real `request_approval` action (`shortlisted → approval_required`, owner/admin/team_member) in a future wiring phase — not a simple "enable the existing button," since its current label/intent point at the wrong subsystem |

**Missing entirely — no button exists today for:**
- `request_approval` as a real, correctly-labeled action (see #7 above — only a disabled, mislabeled placeholder exists).

### 2.2 `CampaignBuilder.tsx` (rendered from `AuthorityBuilderPage.tsx`)

| # | Button label | Mock call | Current source status | Target status | RPC action equivalent | Legal from RPC? | Approval required? | Role restriction? | Recommendation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | "Create campaign" | `createAuthorityCampaign(website, input)` → mock sets `approval_status: "pending_approval"` directly on creation | *(new row, no prior status)* | `pending_approval` | **None — this is not a single RPC action.** Campaign creation is a plain INSERT (owner/admin/team_member, via the table's `FOR ALL` RLS policy, not through either RPC — the RPCs only transition *existing* rows: `SELECT * INTO c FROM seo_authority_campaigns WHERE id = p_campaign_id; IF NOT FOUND THEN RAISE EXCEPTION`). A raw INSERT defaults `approval_status` to `'draft'` (the column's own `DEFAULT 'draft'`) — reaching `pending_approval` legally requires a **separate** `submit_for_approval` RPC call afterward. | N/A (two operations, not one) | INSERT: owner/admin/team_member. `submit_for_approval`: owner/admin/team_member. | **Split into two actions**: (a) "Create campaign" → creates in `draft` (matches the DB default, no RPC needed, plain RLS-gated INSERT) and (b) a separate, explicit "Submit for approval" action (`draft → pending_approval` via `submit_for_approval`). The current single-button behavior silently skips `draft` and its own audit trail entry, and there is no way in the UI today to see or work with a campaign in `draft`. |
| — | "Clear selection" | (no backend call — local UI state only) | — | — | — | N/A | N/A | N/A | **Kept as-is** — pure client-side selection reset, not a Stage 6 write |

### 2.3 `CampaignList.tsx` (rendered from `AuthorityBuilderPage.tsx`)

**Zero buttons of any kind.** Campaigns render read-only: name, goal, owner
badge, opportunity count, due date, progress percentage, and a read-only
task checklist (`<input type="checkbox" ... readOnly />`). There is
currently **no UI path at all** to:

| RPC action | Current UI equivalent | Recommendation |
| --- | --- | --- |
| `submit_for_approval` (`draft → pending_approval`) | **None exists** (only reachable today via the bundled "Create campaign" behavior in §2.2, which skips `draft` entirely) | **Add** — needed for any campaign that legitimately starts in `draft` under the split from #8 |
| `approve` (`pending_approval → approved`, owner/admin only) | **None exists** | **Add**, with explicit role gating (owner/admin only — team_member must not see an enabled "Approve" button) |
| `reject` (`pending_approval → rejected`, owner/admin only) | **None exists** | **Add**, same role gating as `approve` |
| `return_to_draft` (`pending_approval`/`rejected` → `draft`) | **None exists** | **Add** — the only way back from `rejected` |
| `start` / `complete` / `pause` / `cancel` | N/A | **Not supported by the backend at all** — no such campaign RPC action exists. Campaign execution is tracked via per-task `is_complete` (already correctly read-only-rendered in `CampaignList.tsx` today, matching D6 — progress is derived, never a stored/settable campaign-level status). No UI action should be built for these; they are out of scope by design, not an oversight. |

### 2.4 `AiVisibilityPage.tsx` and AI Visibility subcomponents

`PromptTrackingCard.tsx`, `BrandMentionCard.tsx`, `CompetitorMentionCard.tsx`,
`AiContentGapCard.tsx` — **zero `onClick`/mutation code in any of these
four files** (confirmed by direct grep). AI Visibility is correctly
read-only everywhere in the UI except one page-level button:

| # | Button label | Mock call | Notes | Stage 6 RPC applicable? | Recommendation |
| --- | --- | --- | --- | --- | --- |
| 9 | "Generate AI visibility data" (empty-state only, shown when `prompts.length === 0`) | `generateMockAiVisibilityRefresh(website)` → mock's `generateAiVisibilityDataForWebsite` pushes one placeholder `PromptTrackingRecord` (`visibility_status: "unknown"`) | This is a **demo-data generator**, not a status transition — it has no corresponding backend action of any kind. Stage 6 AI Visibility tables are correctly plain-RLS-written (D5: "AI Visibility stays plain-RLS-written... No transition RPC for AI Visibility") — this button doesn't need one either. | **N/A — not a transition, not comparable to the RPC matrix.** | **Kept as-is, mock-only.** Out of scope for RPC-legality wiring; if ever wired, it would be a plain manager-gated INSERT into `seo_ai_prompt_tracking`, not a guarded transition. |
| — | `updateAiVisibilityItemStatus(id, visibilityStatus)` (exported from `aiVisibilityService.ts`) | mock's `updatePromptTrackingStatus` | **Zero live callers anywhere in the current UI** (confirmed by grep — no component invokes it) | N/A — unused | **No action needed.** Not a UI bug (nothing is rendering an illegal action); it is unreferenced code kept from the original mock adapter design. If a future phase adds a UI surface for it, Stage 6 allows a plain RLS-gated `UPDATE` on `seo_ai_prompt_tracking.visibility_status` (owner/admin/team_member) — no RPC needed, since visibility_status is observed/reporting data (D5), not an external-facing execution action. |

---

## 3. Summary — current UI actions that are illegal or misleading against the RPC state machine

Ranked by how likely a developer is to hit the error in ordinary use (highest
first), assuming these were wired to Supabase as-is today:

1. **"Mark in progress" (#2) is illegal in the two statuses it is realistically clicked from.** In today's UI, an opportunity reaches `suggested`/`shortlisted` and then this button is immediately available — but `start` requires `approval_required`/`expert_review_requested` first. This is the same root cause already identified and deliberately left unwired in Phase 15A (`PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` §7) — this audit confirms it precisely against the RPC source and extends the finding to every other button.
2. **"Send to Expert Review" (#6) is illegal from `suggested`.** A freshly-flagged risky opportunity (the exact case this button is designed for) cannot legally go straight to `expert_review_requested` — it must be `shortlisted` first (there is no direct `suggested → expert_review_requested` path in the RPC).
3. **"Reject" (#4) has no role gating in the UI**, but the RPC restricts it to owner/admin. A team_member (or the mock's `client` role simulation) can click it today with no warning, and the real RPC would reject the call — an honest failure, but currently invisible in the UI's affordances (the button doesn't even hint that it's manager-only).
4. **"Shortlist" (#1) is only legal from `suggested`**, but is shown unconditionally — clicking it on an already-`shortlisted`/`approval_required`/etc. opportunity would raise "Illegal transition."
5. **"Mark completed" (#3) is only legal from `in_progress`**, same unconditional-visibility problem.
6. **"Create campaign" (#8) bundles two backend operations into one UI action** and skips the `draft` state + its own `submit_for_approval` audit trail entry entirely — not "illegal" in the sense of raising an RPC error (since it never calls the RPC), but structurally misrepresents the backend model: a campaign the UI shows as instantly `pending_approval` never legally passed through `draft` on the backend's terms.
7. **Campaign approve/reject/submit/return-to-draft (§2.3) don't exist as UI actions at all** — not "illegal," simply absent; the campaign workflow is currently a dead end past creation.
8. **"Send to Approval Queue — coming soon" (#7) is mislabeled**, not illegal (it's `disabled` and unwired) — but its name points at the wrong subsystem (Stage 2's approval queue, not Stage 6's own `approval_required` status) and would confuse whoever builds it next without this audit.
9. **"Mark as Avoided" (#5) is the one button that is already legally and role-correctly shaped** as-is (any non-terminal source status, owner/admin/team_member) — no illegality found, only the general "no explicit terminal-state guard" caveat that applies to every button in this file.

---

## 4. Proposed legal UX action matrix

This is a **design proposal only** — nothing below has been built. Every
action name matches an actual RPC action from §1; no invented status or
action is included.

### 4.1 Authority opportunities

| Proposed UI action | Backend action | Legal from status(es) | Resulting status | Manager role | Extra role restriction | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| "Shortlist" | `shortlist` | `suggested` | `shortlisted` | owner/admin/team_member | none | Only visible/enabled on `suggested` opportunities |
| **"Request approval"** *(new — replaces the mislabeled "coming soon" placeholder)* | `request_approval` | `shortlisted` | `approval_required` | owner/admin/team_member | none | Only visible/enabled on `shortlisted` opportunities that `requires_approval` |
| "Send to expert review" | `request_expert_review` | `shortlisted`, `approval_required`, `in_progress` | `expert_review_requested` | owner/admin/team_member | none | Only visible/enabled on those three statuses — not on `suggested` |
| **"Start"** *(renamed from "Mark in progress")* | `start` | `approval_required`, `expert_review_requested` | `in_progress` | owner/admin/team_member | none | Only visible/enabled once approval or expert review has actually happened — this is the schema-enforced safety gate (requirement 7) |
| "Mark completed" | `complete` | `in_progress` | `completed` | owner/admin/team_member | none | Only visible/enabled on `in_progress` |
| "Reject" | `reject` | any non-terminal | `rejected` | owner/admin/team_member (base) | **owner/admin only** | Hide/disable for team_member and client in the UI, not just rely on the RPC to reject the call |
| "Mark as avoided" | `avoid` | any non-terminal | `avoided` | owner/admin/team_member | none | Terminal — no further action possible |
| *(pause)* | — | — | — | — | — | **Not supported.** No backend action exists; do not build. |
| *(cancel)* | — | — | — | — | — | **Not supported as a distinct action.** `reject` and `avoid` already cover "stop working on this" semantics for opportunities — a "Cancel" button would need to map to one of those two, not a new backend action. |

### 4.2 Authority campaigns

| Proposed UI action | Backend action | Legal from status(es) | Resulting status | Manager role | Extra role restriction | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| "Create campaign" *(scope reduced from current)* | plain RLS INSERT (no RPC) | *(new row)* | `draft` (the column's own default) | owner/admin/team_member | none | Must **stop** setting `approval_status: "pending_approval"` directly — creation should land in `draft` |
| **"Submit for approval"** *(new)* | `submit_for_approval` | `draft` | `pending_approval` | owner/admin/team_member | none | The step the current "Create campaign" button silently skips today |
| **"Approve"** *(new)* | `approve` | `pending_approval` | `approved` | owner/admin/team_member (base) | **owner/admin only** | A team_member may submit but must not see an enabled "Approve" |
| **"Reject"** *(new)* | `reject` | `pending_approval` | `rejected` | owner/admin/team_member (base) | **owner/admin only** | Same role restriction as approve |
| **"Return to draft"** *(new)* | `return_to_draft` | `pending_approval`, `rejected` | `draft` | owner/admin/team_member | none | Only way back from `rejected`; also lets a team_member rework a submission before resubmitting |
| *(start)* | — | — | — | — | — | **Not supported.** `approved` is the terminal RPC-tracked status; there is no further campaign-level status. |
| *(complete)* | — | — | — | — | — | **Not supported as a campaign-level status.** "Completion" is represented by task-level `is_complete` (already correctly read-only in `CampaignList.tsx`) and the derived `progress_percentage` (D6) — not by `approval_status`. |
| *(pause / cancel)* | — | — | — | — | — | **Not supported.** No such campaign RPC action exists. |

---

## 5. Unresolved UX decisions (explicitly not decided by this audit)

This audit deliberately stops at "what the backend allows" and does not
decide product/UX questions that require a human call:

1. **Where does "Request approval" belong visually?** Replacing the
   disabled "Send to Approval Queue — coming soon" placeholder in place, or a
   new distinct button/section — not decided here.
2. **Should `draft` campaigns be visible in `CampaignList.tsx` at all**, or
   only surfaced during creation before the first "Submit for approval"
   click? The current component has no draft-state rendering to build from.
3. **How does the manager-only gating for "Reject"/"Approve" get enforced in
   the UI** — hide the button, show it disabled with a tooltip, or show it
   and let the RPC's real rejection surface (Phase 13D precedent: a real
   permission denial should never be silently masked, per
   `PHASE_13D_APPROVAL_QUEUE_WIRING_NOTES.md` §4 — but that doesn't resolve
   whether the button should be hidden *before* the click for a cleaner UX,
   which Phase 13D's own approval-queue role gating example also left to a
   simulated role switcher rather than a fully hidden control).
4. **Does "Send to Approval Queue" get renamed/rebuilt as "Request approval",
   or removed and replaced by an entirely new control?** This audit
   recommends the rename/rebuild path (§2.1 #7) but the exact copy/placement
   is a product decision.
5. **Should a future wiring phase use the Phase 13D/13E non-masking write
   pattern verbatim** (a new `runAuthorityWrite()` helper +
   `AuthorityTransitionError`, mirroring `runApprovalWrite`/
   `ApprovalTransitionError` and `runContentWrite`/`ContentTransitionError`),
   or does Stage 6's two-RPC split (opportunity vs. campaign) warrant two
   separate helpers? Not decided here — flagged as the natural next
   reference point for whoever picks up the actual wiring work.
6. **Campaign creation's `owner`/`due_date`/task-generation UX** (currently
   bundled into `CampaignBuilder.tsx`'s single form) is unaffected by the
   `draft`-vs-`pending_approval` split proposed in §4.2, but whether the
   "Submit for approval" action lives in the same form or a separate step in
   `CampaignList.tsx` is not decided.

---

## 6. What this audit does NOT do

- Does **not** change `AuthorityBuilderPage.tsx`, `AiVisibilityPage.tsx`,
  `OpportunityCard.tsx`, `CampaignBuilder.tsx`, `CampaignList.tsx`,
  `offPageService.ts`, `aiVisibilityService.ts`, or any mock data file.
- Does **not** call either transition RPC from any new code.
- Does **not** modify any migration, the seed SQL, or any RLS policy.
- Does **not** touch production — this task only read already-applied TEST
  migration files and existing frontend source.
- Does **not** claim writes are ready to wire — the proposed matrix in §4 is
  a design target for a **future** wiring phase (tentatively "Phase 15C"),
  not a statement that the work is done or safe to ship.

---

## 7. Recommended next step

A future, explicitly-scoped wiring phase (not this one) should:

1. Rebuild `OpportunityCard.tsx`'s button set to match §4.1 exactly —
   conditional visibility/disablement per current status, role gating on
   "Reject."
2. Split `CampaignBuilder.tsx`'s "Create campaign" into "Create campaign"
   (→ `draft`) and add a new "Submit for approval" control.
3. Build the missing campaign action set in `CampaignList.tsx` (§4.2) —
   submit / approve / reject / return-to-draft, role-gated.
4. Wire all of the above through the existing, unmodified
   `seo_authority_opportunity_transition` / `seo_authority_campaign_transition`
   RPCs, using the Phase 13D/13E non-masking write pattern (§5 point 5) so a
   genuine permission/state-machine denial is never silently swallowed by
   the mock fallback.
5. Live-test each transition, signed in as each of owner/admin/team_member/
   client, against the TEST project's seeded Stage 6 data.

Until that phase runs, **Off-Page Authority and AI Visibility writes remain
100% mock-only in every data mode** — unchanged by this audit.
