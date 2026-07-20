# SEO Backend — Stage 3 Content Studio Migration Notes (Phase 12G)

**Status:** SQL written + self-reviewed + **test-verified**. Applied and smoke-tested on a **fresh test Supabase project** (see checkpoint below). **Production has NOT been touched.**

## ✅ Test Verification Checkpoint (fresh test Supabase project)

- [x] Dry-run passed
- [x] Applied to fresh test Supabase project (`…120007` → `…120009`, after Stage 1 + Stage 2)
- [x] 11 Content Studio tables visible: `seo_content_opportunities`, `seo_content_keyword_plans`, `seo_content_competitor_summaries`, `seo_content_wireframes`, `seo_content_format_inputs`, `seo_content_drafts`, `seo_content_draft_sections`, `seo_content_section_revisions`, `seo_content_comments`, `seo_content_activity`, `seo_content_assets`
- [x] RLS = `true` for all 11 tables
- [x] 3 functions visible: `seo_content_assert_same_workspace()`, `seo_content_client_can_see_draft()`, `seo_content_transition(uuid,text,text)`
- [x] Private `seo-content-assets` bucket visible (`public=false`, 20 MB limit, 5-MIME allowlist)
- [x] Stage 3 table policies visible on all 11 tables
- [x] Stage 3 triggers visible (`updated_at` + same-workspace guard triggers)
- [x] Storage object policies visible (`seo_content_assets_obj_select`, `seo_content_assets_obj_insert`)
- [x] `seo_stage3_content_studio_smoke_test.sql` executed — **all assertions reported `PASS`, no known `FAIL` lines** (workflow transitions, client status-gates, draft/section visibility, append-only comments/activity, asset MIME allow/block, storage bucket privacy, non-member isolation)

**Production status:** Stage 1, Stage 2, and Stage 3 are **test-verified only, not production-applied**. Production apply should happen only after: (1) confirming the target project is the correct shared Digibility Supabase project, (2) a backup/branch strategy is in place, and (3) a final review/sign-off. **Service-layer wiring** (replacing mock adapters with these tables/RPC/bucket) is a separate later phase.

---

Files (run in order, after Stage 1 + Stage 2):
1. `supabase/migrations/20260711120007_seo_stage3_content_plan.sql`
2. `supabase/migrations/20260711120008_seo_stage3_content_drafts.sql`
3. `supabase/migrations/20260711120009_seo_stage3_content_assets.sql`

---

## 1. What Stage 3 creates

**Tables (11):** `seo_content_opportunities` (anchor + workflow status + brief_notes), `seo_content_keyword_plans` (1:1), `seo_content_competitor_summaries` (n), `seo_content_wireframes` (1:1 + approval snapshot), `seo_content_format_inputs` (1:1, `asset_id`) · `seo_content_drafts` (1:1 current), `seo_content_draft_sections` (n), `seo_content_section_revisions` (append-only regen history) · `seo_content_comments` (append-only), `seo_content_activity` (append-only), `seo_content_assets` (file metadata + soft-delete).
**Functions (3):** `seo_content_assert_same_workspace()` (child↔opportunity integrity guard), `seo_content_client_can_see_draft()` (client draft-read gate), `seo_content_transition(uuid,text,text)` RPC.
**Storage:** private bucket `seo-content-assets` (`public=false`, 20 MB limit, 5-MIME allowlist) + `storage.objects` SELECT/INSERT policies.
**Also:** `updated_at` triggers (non-append-only tables), same-workspace guard triggers, CHECK constraints on every status/type/scope/mime, indexes on workspace/website/opportunity/draft/status/type/target_keyword/asset_scope/mime/is_deleted/created_at, RLS enabled + policies on all 11 tables, `format_inputs.asset_id` forward-ref FK.

## 2. How it builds on Stage 1 & Stage 2

Reuses Stage 1 helpers unchanged: `seo_is_global_admin`, `is_seo_workspace_member`, `seo_role_in`, `seo_role_of`, `set_updated_at`; FKs to `seo_workspaces`/`seo_websites` (`ON DELETE CASCADE`) + `auth.users` (`SET NULL`). Reuses Stage 2 **patterns** — append-only comments/activity, `actor_role_snapshot`, SECURITY DEFINER transition RPC, same-workspace integrity guard — **without touching Stage 2 approval tables** (they are `recommendation_id`-bound; content uses its own local workflow). `website_id` = source of truth; `website_url` snapshot on all operational rows. No Stage 1/2 or Core object altered.

## 3. Content workflow status / action matrix

**Statuses (14, text CHECK, no `published`):** `idea, plan_ready, wireframe_in_progress, wireframe_internal_review, wireframe_client_review, wireframe_changes_requested, wireframe_approved, draft_in_progress, draft_internal_review, draft_client_review, draft_changes_requested, draft_approved, ready_for_manual_publish, archived`.

**`seo_content_transition(p_opportunity_id, p_action, p_note)`** (SECURITY DEFINER; enforces role + current-status → allowed transition, logs `seo_content_activity`, captures `p_note` as a comment):
- **owner/admin/team_member:** `mark_plan_ready` (idea→plan_ready), `start_wireframe`, `submit_wireframe_internal_review`, `send_wireframe_client_review`, `approve_wireframe_internal`, `request_wireframe_changes`, `start_draft`, `submit_draft_internal_review`, `send_draft_client_review`, `approve_draft_internal`, `request_draft_changes`, `mark_ready_for_manual_publish`, `archive`.
- **client (only when status ∈ {wireframe_client_review, draft_client_review}):** `client_approve_wireframe`, `client_reject_wireframe`, `client_approve_draft`, `client_reject_draft`, `request_team_review` (→ back to internal review), `request_expert_review` (activity only, no status change), `comment`.
- Any other combination (wrong role, wrong status, unknown action) → clear `RAISE EXCEPTION`. No action publishes or writes a CMS.

## 4. RLS / permission summary

- **Read:** plan/keyword/competitor/wireframe/format/comments/activity/assets → any active workspace member (incl. client) + global admin. Drafts/sections/revisions → gated by `seo_content_client_can_see_draft()`: managers/admin all stages; **client only when status ∈ {draft_client_review, draft_approved, ready_for_manual_publish, archived}**.
- **Write:** owner/admin/team_member + global admin manage all content tables; **clients never write** content/drafts/sections/revisions/assets. Service role bypasses RLS for generation.
- **Status changes** go through the RPC (SECURITY DEFINER); direct status writes are additionally RLS-restricted to the manager set (defense-in-depth). **Clients change status only via the RPC's client-review actions.**
- **Comments/activity:** append-only. Clients comment **only via the RPC** (status-gated); direct client INSERT blocked. Clients cannot forge activity (RPC writes it via definer).
- **Section revisions:** append-only (INSERT-only policy; no update/delete).
- team_member cannot manage workspace/members/subscriptions (Stage 1/2 own those; untouched).

## 5. Storage bucket & file policy

- Bucket `seo-content-assets` is **private** (`public=false`); allowed MIME = PDF, DOCX, PNG, JPEG, WEBP; 20 MB limit. **SVG/ZIP/EXE/scripts rejected** (bucket allowlist + `seo_content_assets.mime_type` CHECK).
- Path convention `{workspace_id}/{website_id}/{scope}/{asset_id}_{filename}` → first segment = workspace_id.
- `storage.objects` policies: **SELECT** = active member of the path's workspace (or global admin); **INSERT** = manager set only (**clients cannot upload**). No public/anon policy; no UPDATE/DELETE policy → object hard-delete deferred to a later admin/service job.
- DB `seo_content_assets` is metadata only (never bytes); deletion is **soft** (`is_deleted`/`deleted_at`/`deleted_by`) — no hard row delete in Stage 3. Downloads via short-lived signed URLs (app/service layer, later).

## 6. What Stage 3 intentionally does NOT include

No LLM/draft generation (drafts written by service role for now); no CMS write-back; no real/live publishing (`ready_for_manual_publish` is a status, no executor); no `published` status; no full draft-level versioning; no plan-limit/usage enforcement; no hard delete of Storage objects or asset rows; no Expert Support ticket creation (Stage 10); no billing; no modification of Stage 1/2 or Core.

## 7. Test checklist (dry-run/apply on the test project) — ✅ all passed, see checkpoint above

- [x] Apply after Stage 1+2 (007→008→009); no errors; idempotent re-run.
- [x] 11 tables visible; RLS `true` on all 11; policies visible; bucket `seo-content-assets` exists and is **private**; 2 storage policies present.
- [x] owner/admin/team_member advance the workflow via `seo_content_transition()`; only valid status→action transitions succeed; each writes a `seo_content_activity` row; invalid transitions raise.
- [x] Client `seo_content_transition` client actions succeed **only** when status ∈ {wireframe_client_review, draft_client_review}; rejected otherwise; client attempting a manager action / generate / edit / upload → rejected/denied.
- [x] Client direct INSERT/UPDATE on any content/draft/asset table → denied by RLS; client direct comment INSERT → denied (must use RPC).
- [x] Client cannot SELECT drafts/sections until status is client-visible; can once `draft_client_review`/`draft_approved`/`ready_for_manual_publish`/`archived`.
- [x] Service-role insert of draft + sections + a section revision succeeds (RLS bypass); append-only: UPDATE/DELETE on comments/activity/revisions → denied.
- [x] Insert `seo_content_assets` with an allowed MIME → ok; `image/svg+xml`/`application/zip` → CHECK rejects; upload to another workspace's path → Storage RLS denies for a non-member; global admin can read.
- [x] `asset_scope='workspace'` asset with NULL `content_opportunity_id` allowed; a child (keyword_plan/wireframe/draft/comment) with a cross-workspace `content_opportunity_id` → same-workspace guard raises.
- [x] Soft-delete an asset (`is_deleted=true`) → row retained, Storage object not removed; no hard DB delete path.
- [x] Global admin reads all content tables across workspaces; no public URL exposes any file.

See `SUPABASE_STAGE_3_CONTENT_STUDIO_VERIFICATION_GUIDE.md` and `supabase/test/seo_stage3_content_studio_smoke_test.sql` for the executed smoke test and full per-check mapping.

## 8. Known risks / assumptions

- Targets the **shared Digibility Supabase project** (Stage 1/2 objects + `auth.users`/`storage.*` present); SECURITY DEFINER functions owned by a BYPASSRLS role (Supabase `postgres`) so definer bypass works as intended.
- Draft/section/revision **generation** is a **service-role** action (no LLM in Stage 3); RLS gives clients no generation path.
- Storage-object cleanup for soft-deleted assets is a **later admin/service job**; Stage 3 leaves objects in place.
- The `((storage.foldername(name))[1])::uuid` cast in storage policies assumes the workspace-scoped path convention; malformed first segments are rejected on upload.
- App services/mocks unchanged; wiring these tables/RPC/bucket into `contentStudioService` is a later phase.
- No production apply.

## Next step

Stage 1, Stage 2, and Stage 3 are all test-verified (see checkpoints). **Production has not been touched.** Remaining step: **production apply**, only after confirming target project, backup/branch strategy, and final review. Service-layer wiring (replacing mock adapters with these tables/RPC/bucket in `contentStudioService`) is a separate later phase.
