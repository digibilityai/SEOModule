# Phase 13D — Approval Queue Service Wiring

Wires `approvalService` to real Supabase (Stage 2) tables behind the Phase 13A mock/Supabase data-mode switch. In mock mode the app behaves exactly as before. In Supabase mode, reads and item-creation attempt a real Supabase call and gracefully fall back to mock on failure (missing config, no session, RLS denial, network error); **workflow-status writes go through the Stage 2 `seo_approval_transition` RPC and never fall back to mock on a real permission denial** — see §4.

**Content Studio is not wired.** Approval actions use `seo_approval_transition`, never a direct unsafe status update. No live publishing exists anywhere. Production remains untouched. No crawler/AI generator exists yet.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/seoApprovalSupabaseService.ts` — `fetchSupabaseApprovalQueue()`, `fetchSupabaseApprovalItemById()`, `ensureSupabaseApprovalQueueGenerated()`, `updateSupabaseApprovalItemFields()`, `addSupabaseApprovalComment()`, `ApprovalTransitionError`.
- `PHASE_13D_APPROVAL_QUEUE_WIRING_NOTES.md` — this file.

**Changed:**
- `src/services/approvalService.ts` — all five exported functions wired. Reads (`fetchApprovalQueue`, `fetchApprovalItemById`) and item-creation (`ensureApprovalQueueGenerated`) use the standard `runWithServiceAdapter()`. Writes that carry a workflow status or comment (`updateApprovalItemFields`, `addApprovalComment`) use a new local `runApprovalWrite()` helper instead — see §4. Same function signatures and return types as before.
- `src/pages/seo/dev/SupabaseAuthTestPage.tsx` — added "Test approval service", "Test approval comments", and "Run safe approval transition" dev-only buttons/results. `WebsiteTestResult.firstWebsite` was widened from `{id, website_url}` to the full `SeoWebsite` object (tiny, backward-compatible dev-page-only change) so it can be passed straight into `ensureApprovalQueueGenerated`.
- `SERVICE_LAYER_WIRING_PLAN.md` — status update (§11); corrected §10's "Approval Queue is NOT wired" note to point here.

**Not changed:** `src/services/contentStudioService.ts`, `src/services/serviceAdapter.ts`, any `src/mocks/*` file, any customer-facing page beyond what already called the now-wired service, any type, any migration, the reference Digibility app.

---

## 2. Services Wired

| Service function | Mock path | Supabase path (new) |
|---|---|---|
| `approvalService.fetchApprovalQueue(websiteId)` | `listApprovalQueue()` | `fetchSupabaseApprovalQueue(websiteId)` — items + their comments |
| `approvalService.fetchApprovalItemById(id)` | `getApprovalItemById()` | `fetchSupabaseApprovalItemById(id)` |
| `approvalService.ensureApprovalQueueGenerated(website, recs, issues)` | `createApprovalItemsFromRecommendations()` | `ensureSupabaseApprovalQueueGenerated(...)` — idempotent direct INSERT (owner/admin/team_member only) |
| `approvalService.updateApprovalItemFields(id, {status})` | Sets the field directly | Maps status → RPC action, calls `seo_approval_transition` |
| `approvalService.updateApprovalItemFields(id, {suggested_change})` | Sets the field directly | Direct RLS-gated `UPDATE` on `seo_approval_items.suggested_change` (not a transition) |
| `approvalService.addApprovalComment(id, {author_role, comment_text})` | Pushes to the item's comment array | `seo_approval_transition(id, 'comment', comment_text)` — `author_role` param is not sent to the RPC; the backend stamps the caller's real role |

---

## 3. Supabase Tables/RPCs Used

Stage 2 only, all previously test-verified (see `BACKEND_MILESTONE_HANDOFF.md`):
- `seo_approval_items` (read; direct INSERT for queue generation; direct UPDATE for `suggested_change` only — **never** a direct status UPDATE)
- `seo_approval_comments` (read only — every write goes through the RPC)
- `seo_approval_transition(uuid, text, text)` RPC — the only path for status changes (`approve`/`reject`/`expert_review`/`developer_needed`/`completed`) and for comments (`comment`)

Read for enrichment (from Phase 13C, unchanged): `seo_recommendations`, `seo_audit_issues`. Not used: `seo_approval_activity` (written server-side by the RPC; not read/written directly from the frontend this phase — no UI surface consumes it yet), `seo_role_of` / `seo_is_high_risk_category` (used internally by the RPC, never called directly from the frontend).

---

## 4. Mock Fallback Behavior

**Reads and item-creation** (`fetchApprovalQueue`, `fetchApprovalItemById`, `ensureApprovalQueueGenerated`) use the standard `runWithServiceAdapter()` — identical fallback semantics to every prior phase: missing config → mock; no session → clear throw → mock + one console warning; authenticated with zero rows → legitimate empty state, not a fallback.

**Writes that carry a workflow action** (`updateApprovalItemFields` with a `status`, `addApprovalComment`) are different **by design**, via a new `runApprovalWrite()` helper local to `approvalService.ts`:

1. **Supabase mode requested but config missing/invalid, or no session** → falls back to mock, exactly like reads (these are infra-level failures the app can't do anything about).
2. **Supabase mode + authenticated + the RPC itself rejects the call** (wrong role for this risk level, item not found, unknown action) → throws `ApprovalTransitionError`, which **propagates as a real error** — the mock path is *not* invoked. A team_member trying to approve a high-risk item, or a client trying an action they're not allowed, will see the backend's real rejection, not a silently-successful mock approval.

This asymmetry is intentional: a config/session problem is something the *app* failed at (fair to paper over with mock for a smooth dev/test experience), but a permission denial is the *backend correctly doing its job* — masking that would mean the approval queue's role/risk safeguards could be silently bypassed by anyone who just triggers a Supabase hiccup, which is unacceptable for anything gating what actions a role is allowed to take. See `SERVICE_LAYER_WIRING_PLAN.md` §11 and the code comments in `approvalService.ts`/`seoApprovalSupabaseService.ts` for the same explanation in context.

No raw Supabase error message reaches customer-facing UI as-is — `ApprovalTransitionError` carries the RPC's own human-readable message (Stage 2's `RAISE EXCEPTION` text is already written to be relatively clear, e.g. "Not permitted: team_member cannot approve this item (high-risk — use Request Expert Review or Send to Developer)").

---

## 5. Manual Test Steps — Mock Mode

1. No `.env` needed (or `VITE_SEO_DATA_MODE=mock`).
2. `npm run dev`, visit `/seo/approvals`.
3. Confirm identical behavior to before Phase 13D: seeded approval items, role switcher, approve/reject/edit/comment all work exactly as before, `RoleSwitcher` permission gating unchanged.

---

## 6. Manual Test Steps — Supabase Mode via `/seo/dev/auth-test`

**Prerequisite:** `.env` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (test project), `VITE_SEO_DATA_MODE=supabase`; Stage 1 + Stage 2 applied.

1. Sign in with a test-project user that has `user_module_access(module='seo')` granted.
2. **"Test website service"** → **"Create test website"** if needed → **"Test website service"** again to confirm a real website id.
3. **"Test approval service"** — on a fresh site this legitimately reports `0 approval item(s) found` (no crawler → no recommendations → nothing to turn into approval items yet; not a failure).
4. To exercise the RPC with real data, seed one recommendation manually in the Supabase SQL editor (service-role/dashboard context only):
   ```sql
   insert into public.seo_recommendations
     (workspace_id, website_id, website_url, area, title, suggested_change, why_it_helps, action_type, impact, effort, risk)
   values
     ('<workspace-id>', '<website-id>', '<website-url>', 'technical', 'Test recommendation',
      'Test suggested change', 'Test why', 'manual_support', 'low', 'low', 'low');
   ```
5. Click **"Test approval service"** again — it now generates and reports `1 approval item(s) found — first status: suggested`.
6. Click **"Test approval comments"** — expect `Comment added — item now has 1 comment(s).`
7. Click **"Run safe approval transition"** (dev-only, "Request expert review" only) — expect `Transition applied — new status: expert_review_requested.` This action is allowed for every role, so it succeeds regardless of the signed-in test user's workspace role.
8. To see the "real rejection surfaces, not masked" behavior described in §4: sign in as a `team_member` or `client` test user and attempt an action Stage 2 denies for that role (e.g. approving a `risk='high'` item) via the real `/seo/approvals` page — expect the mutation to fail visibly (React Query error), not silently "succeed."
9. Sign out — all test-panel results reset.

---

## 7. Known Limitations

- **No crawler/AI generator.** A fresh Supabase test website has 0 recommendations and therefore 0 approval items until a future crawler/LLM backend lands, or test data is seeded manually (§6 step 4) — same limitation carried over from Phase 13C.
- **`ensureApprovalQueueGenerated` requires owner/admin/team_member.** If the signed-in test user is a `client`, Stage 2 RLS denies the direct INSERT and the standard adapter falls back to mock for that call (client role is intentionally excluded from creating approval items).
- **`author_role` on `addApprovalComment` is accepted but not honored in Supabase mode.** The parameter exists to keep the mock-mode call site unchanged; the real comment is always stamped with the signed-in user's actual Stage 2 workspace role.
- **No activity-timeline UI.** `seo_approval_activity` is written by the RPC but nothing in the current app reads it back — wiring a history view is future work, not required by the current UI contract.
- **The "Run safe approval transition" dev button only exercises `expert_review`.** It's the one action every role is allowed to attempt, chosen specifically so the button never fails on role grounds alone — testing the actual role/risk matrix requires driving `/seo/approvals` directly with different signed-in test users (§6 step 8).
- Same auth/session prerequisites as Phase 13B/13C — no in-app login UI exists yet; use `/seo/dev/auth-test` to establish a session for testing.

---

## 8. Recommended Next Phase

**Phase 13E: wire `contentStudioService`** against Stage 3 (`seo_content_opportunities`, `seo_content_keyword_plans`, `seo_content_wireframes`, `seo_content_drafts`, `seo_content_assets`, etc.), following the same adapter pattern. Continue down the order in `SERVICE_LAYER_WIRING_PLAN.md` §6.
