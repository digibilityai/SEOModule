# SEO Backend — Stage 2 Migration Notes (Phase 12E)

**Status:** SQL written + self-reviewed + peer-reviewed (Phase 12E review) + **test-verified**. Applied and verified on a **fresh test Supabase project** (see checkpoint below). **Production has NOT been touched.**

## ✅ Test Verification Checkpoint (fresh test Supabase project)

- [x] Dry-run passed
- [x] Applied to fresh test Supabase project (`…120004` → `…120006`, after Stage 1)
- [x] 6 tables visible: `seo_audit_runs`, `seo_audit_issues`, `seo_recommendations`, `seo_approval_items`, `seo_approval_comments`, `seo_approval_activity`
- [x] RLS = `true` for all 6 tables
- [x] Policies visible on all 6 tables
- [x] Triggers visible: `updated_at` triggers + `trg_seo_audit_issues_hrc` / `trg_seo_recommendations_hrc` / `trg_seo_approval_items_hrc` (high-risk-category derivation)
- [x] 5 functions visible: `seo_is_high_risk_category`, `seo_run_audit`, `seo_supersede_recommendation`, `seo_role_of`, `seo_approval_transition` (plus shared helper `seo_set_hrc_from_issue`)
- [x] Smoke test (`supabase/test/seo_stage2_smoke_test.sql`) run — all checks reported `PASS`, **no known `FAIL` lines**

**Production status:** These migrations are **test-verified but not production-applied**. Production apply should happen only after: (1) confirming the target project is the correct shared Digibility Supabase project, (2) a backup/branch strategy is in place, and (3) a final review/sign-off.

**Review hardening:** BEFORE INSERT/UPDATE triggers force `is_high_risk_category` to the value derived from the (source) issue category — `trg_seo_audit_issues_hrc` (from own `category`) and `trg_seo_recommendations_hrc` / `trg_seo_approval_items_hrc` (from the linked issue via `seo_set_hrc_from_issue()`). `seo_set_hrc_from_issue()` is `SECURITY DEFINER` and additionally **enforces that a linked issue exists and shares the same workspace_id + website_id, raising otherwise** (no silent fallback, no cross-workspace linkage); issue-less items derive `false` on insert and preserve the prior value on update. This makes the high-risk approval gate un-bypassable and non-forgeable rather than trusting generation code. The team_member medium-risk approval rule is finalized (see §4) — no open decisions remain.

Files (run in order, after Stage 1):
1. `supabase/migrations/20260711120004_seo_stage2_audit.sql`
2. `supabase/migrations/20260711120005_seo_stage2_recommendations.sql`
3. `supabase/migrations/20260711120006_seo_stage2_approval.sql`

---

## 1. What Stage 2 creates

**Tables (6):** `seo_audit_runs`, `seo_audit_issues`, `seo_recommendations`, `seo_approval_items`, `seo_approval_comments`, `seo_approval_activity`.
**Functions (5):** `seo_is_high_risk_category(text)`, `seo_run_audit(uuid)` RPC, `seo_supersede_recommendation(uuid,uuid)`, `seo_role_of(uuid,uuid)`, `seo_approval_transition(uuid,text,text)` RPC.
**Also:** `updated_at` triggers (all mutable tables); `is_latest` partial-unique index; `is_current` partial index; CHECK constraints on every status/category/severity/risk/level/type; indexes on workspace/website/website_url-adjacent keys/run/rec/item/status/severity/risk/is_latest/is_current; RLS enabled + policies on all 6 tables.

History preserved: every audit run = new row (one `is_latest` per website); recommendations versioned via `is_current` + `superseded_by`; approval lifecycle logged append-only in `seo_approval_activity`.

## 2. How it builds on Stage 1

Reuses Stage 1 helpers unchanged: `seo_is_global_admin`, `has_seo_module_access`, `is_seo_workspace_member`, `seo_role_in`, `can_manage_seo_workspace`, `set_updated_at`. All FKs point at Stage 1 `seo_websites`/`seo_workspaces` (`ON DELETE CASCADE`) or `auth.users` (`ON DELETE SET NULL`). **No Stage 1 or Core table is altered/dropped.** `website_id` = source of truth; `website_url` snapshot on all 6 tables.

## 3. RLS / permission summary

- **Read:** any active workspace member (incl. client) + global admin, scoped by `workspace_id`.
- **Audit runs:** members read; owner/admin/team_member direct-write; **clients trigger only via `seo_run_audit` RPC** (creates the run, no issues).
- **Issues & recommendations:** owner/admin/team_member + global admin write; **clients cannot insert/update/delete** (system/service-role generated).
- **Approval items:** owner/admin/team_member create; **primary status path is `seo_approval_transition` RPC**; direct UPDATE is defense-in-depth for owner/admin (any) and team_member (status guardrails); **clients have no direct UPDATE**.
- **Comments:** append-only (SELECT + INSERT policies only, no update/delete for anyone); any member incl. client may comment as self; `actor_role_snapshot` stored.
- **Activity:** append-only; direct insert limited to owner/admin/team_member as self (clients cannot forge); RPC writes the rest via SECURITY DEFINER.
- **Global admin** can read/inspect all. **team_member cannot** manage workspace/members/subscriptions (Stage 1 owns those; untouched here).
- Both RPCs verify membership internally and are `SECURITY DEFINER SET search_path=public`.

## 4. Approval action matrix (enforced by `seo_approval_transition`)

`dangerous = risk='high' OR is_high_risk_category` (URLs/redirects/canonical/noindex/robots.txt/sitemap) · `high_risk = risk<>'low' OR is_high_risk_category` · `low_simple = risk='low' AND NOT is_high_risk_category AND action_type IN ('auto_suggest','manual_support')`

| Action | owner/admin | team_member | client |
|---|---|---|---|
| comment | ✅ | ✅ | ✅ |
| approve | ✅ | ✅ if **not dangerous** (low + medium OK; blocked on high/dangerous category) | ✅ if low_simple |
| reject | ✅ | ✅ | ✅ if low_simple |
| request expert review | ✅ | ✅ | ✅ |
| send to developer | ✅ | ✅ | ✅ if high_risk |
| mark completed | ✅ | ❌ | ❌ |
| edit suggested_change | ✅ (direct UPDATE) | ✅ (direct UPDATE) | ❌ |
| publish live | ❌ (no action exists for anyone) | ❌ | ❌ |

Final rule (resolved): team_member may approve **low and medium** risk items but **not** high-risk items and **not** dangerous technical-category items (robots.txt/canonical/redirects/sitemap/noindex/URLs). Enforced in both the RPC and the `seo_approval_items_update` `WITH CHECK`. Client remains strictest (low-risk-simple only).

Client attempting approve/reject on a non-low-simple or high-risk item is rejected with a message steering to Request Expert Review / Send to Developer. No action performs a CMS/live change; `ready_to_publish` is only a queue marker with no executor.

## 5. What Stage 2 intentionally does NOT include

No crawler / real audit execution; no LLM; no CMS writes / live publishing; no plan-limit/usage enforcement; no billing/subscription mutation; no member/workspace management; no assignment workflow (only an `assignee_user_id` placeholder); none of the later modules (content/performance/off-page/AI/competitor/roadmap/support/report/admin).

## 6. Test checklist (executed on the fresh test project — see checkpoint above)

All items below were exercised by `supabase/test/seo_stage2_smoke_test.sql` (or by manual dashboard/SQL checks) on the test project. Result: **all PASS, no known FAIL lines.**

- [x] Apply Stage 1 then Stage 2 (004→005→006) on a scratch project; no errors; re-run is idempotent.
- [x] `seo_run_audit(website)` as owner/admin/team_member/client → creates one `running` run; prior run's `is_latest` flips false; exactly one `is_latest` per website (violate manually → unique error).
- [x] Non-member calling `seo_run_audit` → exception.
- [x] Client direct INSERT/UPDATE into `seo_audit_issues` / `seo_recommendations` → denied by RLS.
- [x] Insert a `robots_txt`/`canonical`/`redirects`/`sitemap`/`indexability` issue with `is_high_risk_category=false` → trigger forces it to `true`; a recommendation/approval item linked to that issue also resolves to `true` (client approve then correctly blocked even if the generator passed a wrong flag).
- [x] Insert a recommendation/approval item whose `issue_id` points to an issue in a **different** workspace/website → raises (integrity guard); non-existent `issue_id` → raises; issue-less item → `is_high_risk_category=false`; direct `UPDATE ... SET is_high_risk_category=false` without touching `issue_id` → value preserved/re-derived (not forgeable).
- [x] Generate issues + recommendations as service role → succeeds (bypasses RLS).
- [x] `seo_approval_transition` matrix: team_member approve **medium-risk non-dangerous → ok**; team_member approve high-risk or dangerous-category → error; team_member mark completed → error; client approve high_risk → error (steer message); client approve low_simple → ok; client send-to-developer on non-high-risk → error; client request expert_review → ok; owner completed → ok.
- [x] Direct UPDATE defense-in-depth: team_member direct `UPDATE` setting `status='approved'` on a medium non-dangerous item → ok; on a high-risk/dangerous item → denied; setting `status='completed'` → denied.
- [x] Approve via RPC mirrors status onto linked recommendation; writes one activity row; optional comment appended.
- [x] Comment UPDATE/DELETE by anyone → denied (append-only).
- [x] Client direct UPDATE of approval item → denied; owner/admin/team_member edit `suggested_change` → ok (team_member cannot set completed/approve-high-risk via direct UPDATE either).
- [x] Global admin reads all tables across workspaces.
- [x] `superseded_by`/`is_current`: supersede an old rec → old `is_current=false`, retained; cross-website supersede → error.

## 7. Known risks / assumptions

- Targets the **shared Digibility Supabase project** (Stage 1 objects + `auth.users` present); functions owned by a BYPASSRLS role (Supabase `postgres`) so `SECURITY DEFINER` bypasses RLS as intended.
- Issue/recommendation **generation** (no crawler/LLM in Stage 2) is expected via the **service role**; RLS deliberately excludes clients and does not grant a client generation path.
- `seo_run_audit` sets `frequency` from plan tier as a hint only — **no** plan-limit/frequency enforcement in Stage 2.
- Direct-INSERT of an audit run with `is_latest=true` while another latest exists will hit the unique index — intended invariant; app should use the RPC.
- Edit-of-`suggested_change` is a direct RLS-gated UPDATE (owner/admin/team_member), not an RPC action, by design.
- App services/mocks are unchanged; wiring these tables/RPCs into the service layer is a later phase.

## Next step

Stage 1 + Stage 2 are both test-verified (see checkpoints). **Production has not been touched.** Remaining step: production apply, only after confirming target project, backup/branch strategy, and final review. Service-layer wiring (replacing mock adapters) is a separate later phase.
