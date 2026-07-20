# SEO Backend — Stage 3 Plan (Phase 12F): Content Studio

Planning only. **No SQL, no migration files, no DB connection, no production.** Builds additively on Stage 1 (test-verified) + Stage 2 (test-verified). Nothing here requires modifying Stage 1/2. Goal: the **minimum** real backend that can later replace the Content Studio mock adapters (`src/services/contentStudioService.ts`, `src/mocks/contentStudioMockData.ts`) 1:1.

Status: **APPROVED — locked for SQL authoring.** See "Locked Decisions" below (authoritative; overrides any conflicting wording in §1–§14).

Stage 1/2 objects reused (unchanged): `seo_workspaces`, `seo_websites`, helpers `seo_is_global_admin`, `has_seo_module_access`, `is_seo_workspace_member`, `seo_role_in`, `can_manage_seo_workspace`, `seo_role_of`, `set_updated_at`.

---

## Locked Decisions (Phase 12F — final, authoritative)

1. **Approval queue = content-local workflow status.** Content Studio uses its own lifecycle (§8). **Do NOT modify or reuse** the Stage 2 recommendation approval tables (they are `recommendation_id`-bound). Resolves J-1.
2. **Status transitions via a lightweight RPC — `seo_content_transition(p_opportunity_id, p_action, p_note)` (SECURITY DEFINER).** It enforces allowed workflow transitions, role checks, **client review actions**, activity logging, and optional feedback/comment capture. Workflow transitions must **not** rely on frontend logic alone. Resolves J-2 (RPC chosen over RLS+trigger-only).
3. **Draft versioning deferred.** Keep **one current draft** + `seo_content_draft_sections` + `seo_content_section_revisions` (regeneration history). No full draft-level versioning in Stage 3. Resolves J-3.
4. **Client rights (only when content is explicitly sent for client review).** Clients **can**: view client-visible content; comment; **approve a wireframe or draft when sent for client review**; **reject with feedback**; **request expert/team review**. Clients **cannot**: generate drafts, edit content, regenerate sections, publish, change internal workflow, or upload system assets. Enforced in `seo_content_transition` (client actions allowed only when `status IN ('wireframe_client_review','draft_client_review')`) + RLS (no client write on content/draft/asset tables). Resolves J-4.
5. **Orphaned Storage = soft-delete first.** `seo_content_assets` gets `is_deleted boolean default false`, `deleted_at timestamptz null`, `deleted_by uuid null`. Stage 3 does **no automatic hard delete**; actual Supabase Storage object cleanup is a later admin/service job. Resolves J-5.
6. **`seo_content_assets.content_opportunity_id` is nullable** (workspace-/website-level assets exist). Add `asset_scope text NOT NULL` CHECK ∈ (`workspace`, `website`, `opportunity`, `draft`, `comment`). Resolves J-6.
7. **File-type allowlist (MVP-safe only).** MIME CHECK ∈ (`application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `image/png`, `image/jpeg`, `image/webp`). **Disallow** ZIP, EXE, **SVG**, scripts, and any unrestricted/random uploads — enforced by the CHECK **and** the Storage bucket's allowed-MIME list. Resolves J-7.

All blocking questions resolved — **Stage 3 is ready for SQL authoring** (see updated §12).

---

## Locked Workflow Statuses & Transitions (Phase 12F final — authoritative, overrides §8)

**"Sent for client review" is represented by workflow status values, NOT a separate `client_review_requested` flag.** Any earlier mention of such a flag is superseded by this design.

**MVP workflow statuses** (`seo_content_opportunities.status` CHECK, text, not ENUM). No `published` status — Stage 3 has no real publishing.
```
idea
plan_ready
wireframe_in_progress
wireframe_internal_review
wireframe_client_review
wireframe_changes_requested
wireframe_approved
draft_in_progress
draft_internal_review
draft_client_review
draft_changes_requested
draft_approved
ready_for_manual_publish
archived
```

**`seo_content_transition(p_opportunity_id, p_action, p_note)` action set** (SECURITY DEFINER RPC; enforces role + current-status → allowed-action, logs `seo_content_activity`, captures `p_note` as a comment where relevant).

*Owner / admin / team_member actions:*
`mark_plan_ready · start_wireframe · submit_wireframe_internal_review · send_wireframe_client_review · approve_wireframe_internal · request_wireframe_changes · start_draft · submit_draft_internal_review · send_draft_client_review · approve_draft_internal · request_draft_changes · mark_ready_for_manual_publish · archive`

*Client actions — allowed ONLY when `status IN ('wireframe_client_review','draft_client_review')`:*
`client_approve_wireframe · client_reject_wireframe · client_approve_draft · client_reject_draft · request_team_review · request_expert_review · comment`

Clients still cannot: generate drafts, edit drafts, regenerate sections, publish, upload system assets, or change internal workflow. The RPC rejects any client action outside the two `*_client_review` states, and RLS blocks all client writes to content/draft/asset tables.

**Client draft-read visibility** = opportunity `status IN ('draft_client_review','draft_approved','ready_for_manual_publish','archived')` (via `seo_content_client_can_see_draft()`). Wireframe/plan tables remain member-readable at all stages.

---

## 1. Stage 3 objective

Persist the Content Studio workflow — content opportunity/brief → keyword plan → competitor summary → wireframe (approved) → format input → draft → sections → section regeneration history → comments → status lifecycle → publish-queue placeholder — plus **metadata for uploaded source files** (real bytes in Supabase Storage). No LLM, no CMS, no live publishing. Draft/section generation is a **service-role/system** action (LLM later); clients read + comment only.

---

## 2. Proposed tables (11)

The "content brief / content plan" is **not** a separate table — it is a `seo_content_opportunities` row composed with its keyword plan + competitor summaries + wireframe (matches the current mock, avoids overbuild). The "publish queue" is **not** a table — it is opportunities filtered by `status = 'ready_for_manual_publish'` (Stage 3 has no publish executor).

| Table | Purpose | Cardinality |
|---|---|---|
| `seo_content_opportunities` | content item / brief anchor + workflow status | anchor |
| `seo_content_keyword_plans` | keyword plan | 1:1 opportunity |
| `seo_content_competitor_summaries` | competitor content gaps | n per opportunity |
| `seo_content_wireframes` | wireframe + approval snapshot | 1:1 opportunity |
| `seo_content_format_inputs` | format/tone/reference input | 1:1 opportunity |
| `seo_content_drafts` | current generated draft | 1:1 opportunity |
| `seo_content_draft_sections` | draft sections | n per draft |
| `seo_content_section_revisions` | regeneration/rewrite history (append-only) | n per section |
| `seo_content_comments` | feedback (append-only) | n per opportunity |
| `seo_content_activity` | status/workflow timeline (append-only) | n per opportunity |
| `seo_content_assets` | uploaded file **metadata only** | n per workspace/opportunity |

---

## 3. Columns per table

Every operational table carries the Stage-1/2 anchor set: `id uuid pk`, `workspace_id`→`seo_workspaces`, `website_id`→`seo_websites`, `website_url text` snapshot, `created_by`, `created_at`, `updated_at` (append-only tables — revisions/comments/activity — omit `updated_at`). Child tables also carry `content_opportunity_id`→`seo_content_opportunities ON DELETE CASCADE`.

- **seo_content_opportunities** — `title`, `target_keyword`, `search_intent`(CHECK), `funnel_stage`(CHECK), `difficulty`(CHECK), `opportunity_score int` (CHECK 0–100), `reason`, `brief_notes text` (the compiled brief), `is_custom boolean default false`, `status text default 'idea'` (CHECK = the 14 locked workflow statuses, §8 / "Locked Workflow Statuses").
- **seo_content_keyword_plans** — `content_opportunity_id` UNIQUE, `primary_keyword`, `secondary_keywords text[]`, `semantic_keywords text[]`, `question_keywords text[]`, `intent`(CHECK), `difficulty`(CHECK), `business_relevance`, `why_it_matters`.
- **seo_content_competitor_summaries** — `content_opportunity_id`, `competitor_title`, `competitor_url`, `what_they_covered`, `what_they_missed`, `our_opportunity`, `content_gap_angle`.
- **seo_content_wireframes** — `content_opportunity_id` UNIQUE, `suggested_h1`, `intro_angle`, `cta_suggestion`, `section_outline text[]`, `faq_section text[]`, `internal_link_suggestions text[]`, `schema_suggestion text null`, `is_approved boolean default false`, `approved_at timestamptz null`, `approved_by uuid null`.
- **seo_content_format_inputs** — `content_opportunity_id` UNIQUE, `format_type text`(CHECK: default/url_reference/file_reference/match_brand_style/custom_instructions), `reference_url text null`, `custom_instructions text null`, `asset_id uuid null` (FK → `seo_content_assets`, added in file 3c to avoid forward-ref).
- **seo_content_drafts** — `content_opportunity_id` UNIQUE, `title`.
- **seo_content_draft_sections** — `draft_id`→`seo_content_drafts`, `content_opportunity_id` (denormalized for RLS), `position int`, `heading`, `content`, `status text default 'generated'`(CHECK: generated/approved/rejected/edited), `regeneration_count int default 0`.
- **seo_content_section_revisions** *(append-only)* — `draft_section_id`→`seo_content_draft_sections`, `content_opportunity_id`, `revision_number int`, `content`, `reason text null`, `created_by`, `created_at`.
- **seo_content_comments** *(append-only)* — `content_opportunity_id`, `draft_section_id uuid null` (optional target), `author_user_id uuid null` (SET NULL), `actor_role_snapshot text NOT NULL`, `comment_text`, `created_at`.
- **seo_content_activity** *(append-only)* — `content_opportunity_id`, `actor_user_id uuid null`, `actor_role_snapshot text`, `activity_type text`(CHECK: created/status_changed/wireframe_approved/draft_generated/section_regenerated/comment_added/client_review_sent/client_approved/client_rejected/changes_requested/team_review_requested/expert_review_requested/ready_for_manual_publish/archived), `from_status text null`, `to_status text null`, `note text null`, `created_at`.
- **seo_content_assets** *(metadata only)* — `content_opportunity_id uuid null` (nullable — workspace/website-level assets), `draft_section_id uuid null`, `format_input_id uuid null`, `asset_scope text NOT NULL` (CHECK: workspace/website/opportunity/draft/comment), `asset_kind text` (CHECK: source_pdf/source_docx/reference_image/brand_sample/other), `file_name`, `mime_type text NOT NULL` (CHECK: `application/pdf` / `application/vnd.openxmlformats-officedocument.wordprocessingml.document` / `image/png` / `image/jpeg` / `image/webp` — no SVG/ZIP/EXE/scripts), `file_ext`, `file_size_bytes bigint null`, `storage_bucket text default 'seo-content-assets'`, `storage_path text NOT NULL UNIQUE`, `uploaded_by uuid`→auth.users, **soft-delete:** `is_deleted boolean NOT NULL default false`, `deleted_at timestamptz null`, `deleted_by uuid null`, plus anchor set. **Never stores file bytes; never hard-deletes in Stage 3.**

---

## 4. Supabase Storage bucket plan

- **One private bucket** `seo-content-assets` (`public = false`). Configure allowed MIME types (`application/pdf`, the DOCX mime, `image/png`, `image/jpeg`, `image/webp`) and a file-size limit (e.g. 20 MB) at bucket level.
- **Path convention (workspace-scoped, for RLS):**
  `{workspace_id}/{website_id}/{content_opportunity_id | 'workspace'}/{asset_id}_{safe_filename}`
  → the first path segment is always the workspace UUID, so Storage RLS can authorize by membership.
- **No public/uncontrolled access.** Downloads use **short-lived signed URLs** minted by the app (authenticated/service client); never expose the bucket publicly or store public URLs.
- **Storage RLS on `storage.objects`** (bucket = `seo-content-assets`), for `SELECT/INSERT/UPDATE/DELETE`:
  `bucket_id = 'seo-content-assets' AND (public.is_seo_workspace_member(((storage.foldername(name))[1])::uuid) OR public.seo_is_global_admin())`
  — with INSERT/DELETE further restricted to `seo_role_in(ws, owner/admin/team_member)` (clients read-only on files).

## 5. File metadata strategy

DB row in `seo_content_assets` is the source of truth for listing/lifecycle; the object lives only in Storage. Insert order: create the `seo_content_assets` row (gets `id`) → upload to `storage_path` derived from that id → path is immutable. **Deletion is soft-only in Stage 3:** set `is_deleted=true`/`deleted_at`/`deleted_by`; the Storage object is **not** removed by Stage 3 (a later admin/service cleanup job hard-deletes soft-deleted objects). Non-deleted listing filters `WHERE NOT is_deleted`. `storage_path` is `UNIQUE`. `format_input.asset_id` links a chosen source file to the draft-generation format when `format_type='file_reference'`.

---

## 6. Relationship with the Stage 2 approval queue

Content Studio has its **own linear workflow** (ContentWorkflowStatus), which is **not** the risk-gated recommendation approval queue. Stage 2's `seo_approval_items.recommendation_id` is `NOT NULL UNIQUE` → it cannot host content items without **modifying Stage 2** (out of scope, forbidden). Therefore:

- **Do NOT** create `seo_approval_items`/`seo_approval_comments`/`seo_approval_activity` rows for content, and **do NOT** modify those tables.
- **Reuse the Stage 2 _patterns_** instead: append-only comments + activity, `actor_role_snapshot`, SECURITY DEFINER helpers, forward-only status + activity logging.
- Client/expert/team review requests are content **workflow states + activity events** here (e.g. `*_client_review`, `request_expert_review` / `request_team_review` actions logged in `seo_content_activity`). A real Expert Support hand-off is the future Stage 10 module, not Stage 3.
- A future "unified approval queue" could generalize Stage 2 to polymorphic (`subject_type`,`subject_id`) — **deferred** (Locked Decision 1); not needed to replace the mock.

---

## 7. RLS model by role

RLS ON for all 11 tables; every policy `OR seo_is_global_admin()`. "member" = `is_seo_workspace_member(workspace_id)`; "manager set" = `seo_role_in(workspace_id, owner/admin/team_member)`.

| Table group | SELECT | INSERT / UPDATE / DELETE |
|---|---|---|
| opportunities, keyword_plans, competitor_summaries, wireframes, format_inputs | member (incl. client) | manager set only (clients cannot write) |
| drafts, draft_sections, section_revisions | member **but client gated by status** (see below) | manager set + service role only — **clients never generate drafts** |
| comments | member (incl. client) | INSERT: any active member as self (append-only, no update/delete policy) |
| activity | member | INSERT via manager set / trigger (clients cannot forge); append-only |
| assets | member (non-deleted) | INSERT/UPDATE (incl. soft-delete) manager set only; clients cannot upload/modify. No hard `DELETE` in Stage 3. |

- **Client draft visibility gate:** clients may SELECT `drafts`/`draft_sections`/`section_revisions` only when the parent opportunity `status IN ('draft_client_review','draft_approved','ready_for_manual_publish','archived')`. Owner/admin/team_member see all stages. Enforced via a `SECURITY DEFINER` helper `seo_content_client_can_see_draft(opportunity_id)` used in the draft-table SELECT policies.
- **Status transitions go through the `seo_content_transition(p_opportunity_id, p_action, p_note)` RPC** (SECURITY DEFINER — Locked Decision 2), which enforces the current-status → allowed-action matrix, role checks, activity logging, and optional comment capture. Direct `UPDATE` of `seo_content_opportunities.status` is **not** the app path; RLS still restricts any direct status write to the manager set as defense-in-depth (clients cannot direct-write status). "Sent for client review" is a **status value** (`wireframe_client_review` / `draft_client_review`) — no separate flag.
- **Client actions** (via the RPC, allowed **only** when `status IN ('wireframe_client_review','draft_client_review')`): `client_approve_wireframe`, `client_reject_wireframe`, `client_approve_draft`, `client_reject_draft`, `request_team_review`, `request_expert_review`, `comment` (`p_note` → feedback comment). Clients **cannot** generate drafts, edit content, regenerate sections, publish, change internal workflow, or upload assets — enforced by the RPC's action allowlist **and** by RLS (no client INSERT/UPDATE on content/draft/asset tables).

## 8. Content workflow statuses

`seo_content_opportunities.status` CHECK = the **14 locked MVP statuses** (text, not ENUM) — see "Locked Workflow Statuses & Transitions" above:
`idea, plan_ready, wireframe_in_progress, wireframe_internal_review, wireframe_client_review, wireframe_changes_requested, wireframe_approved, draft_in_progress, draft_internal_review, draft_client_review, draft_changes_requested, draft_approved, ready_for_manual_publish, archived`.
No `published` status (Stage 3 has no real publishing). Transition actions (owner/admin/team_member + client) are the locked set above; the RPC enforces the current-status → allowed-action matrix.
Section status CHECK: `generated, approved, rejected, edited`.

## 9. Regeneration / versioning approach

- **Draft:** one **current** draft per opportunity (`UNIQUE content_opportunity_id`) — matches the mock.
- **Section rewrites:** each regenerate/edit writes a `seo_content_section_revisions` row (append-only history) and bumps `seo_content_draft_sections.regeneration_count`; the section row holds the **current** content, revisions hold the trail. This is the history the mock lacks and the "preserve history" principle wants.
- **Wireframe:** `is_approved`/`approved_at`/`approved_by` snapshot; re-generating a wireframe overwrites the single row (or, if needed later, version it — deferred).
- Draft-level versioning (multiple full drafts) is **deferred** (open question J-3).

## 10. Indexes needed

- `content_opportunity_id` on every child table; `website_id` + `workspace_id` on every table.
- `seo_content_opportunities (workspace_id, status)`, `(website_id)`.
- `seo_content_draft_sections (draft_id, position)`; `seo_content_section_revisions (draft_section_id, revision_number)`.
- `seo_content_comments (content_opportunity_id, created_at DESC)`; `seo_content_activity (content_opportunity_id, created_at DESC)`.
- `seo_content_assets (workspace_id)`, `(content_opportunity_id)`, `UNIQUE (storage_path)`.
- `updated_at` triggers on all non-append-only tables.

## 11. What Stage 3 intentionally does NOT include

No LLM/draft generation logic (drafts written by service role for now); no CMS write-back; no live publishing (publish queue is a status filter, no executor); no separate brief/publish tables; no plan-limit/usage enforcement (content-opportunity/draft caps come with the metered-usage stage); no modification of Stage 1/2; no draft-level versioning; no polymorphic/unified approval queue; no Expert Support ticket creation (Stage 10); **no hard delete of Storage objects (soft-delete only)**; no billing.

## 12. Risks / open questions

**Resolved in Phase 12F** (see Locked Decisions — no longer open):
- ✅ J-1 Approval queue → content-local status; Stage 2 tables untouched.
- ✅ J-2 Status transitions → `seo_content_transition()` RPC (not frontend-only).
- ✅ J-3 Draft versioning → deferred; current draft + section revisions.
- ✅ J-4 Client rights → approve/reject/comment/request-review **only when sent for client review**; no generate/edit/regenerate/publish/upload.
- ✅ J-5 Orphaned Storage → soft-delete (`is_deleted`/`deleted_at`/`deleted_by`); hard delete via later admin job.
- ✅ J-6 Asset nullability → `content_opportunity_id` nullable + `asset_scope` CHECK (workspace/website/opportunity/draft/comment).
- ✅ J-7 File types → MIME allowlist (PDF/DOCX/PNG/JPEG/WEBP); no SVG/ZIP/EXE/scripts.

**Remaining blockers:** none. Workflow statuses and the `seo_content_transition` action set are now locked (see "Locked Workflow Statuses & Transitions"); "sent for client review" is a **status value**, not a flag. **Stage 3 is ready for SQL authoring** (Phase 12G).

## 13. Recommended migration file breakdown (3 files, matches Stage 1/2)

1. `…_seo_stage3_content_plan.sql` — `seo_content_opportunities`, `seo_content_keyword_plans`, `seo_content_competitor_summaries`, `seo_content_wireframes`, `seo_content_format_inputs`; `updated_at` triggers; RLS.
2. `…_seo_stage3_content_drafts.sql` — `seo_content_drafts`, `seo_content_draft_sections`, `seo_content_section_revisions`; `seo_content_client_can_see_draft()` helper; RLS (incl. client status gate).
3. `…_seo_stage3_content_assets.sql` — `seo_content_comments`, `seo_content_activity`, `seo_content_assets` (with soft-delete cols + `asset_scope`/MIME CHECKs); `format_inputs.asset_id` FK (deferred add); **Storage bucket create + Storage RLS policies**; `seo_content_transition()` RPC (+ activity logging); RLS.

Timestamps must sort after Stage 2 (`20260711120006`). All additive; RLS enabled on create; no Stage 1/2 or Core objects touched.

## 14. Test verification checklist (future test-project dry-run/apply)

- [ ] Apply after Stage 1+2 on the test project; no errors; idempotent re-run.
- [ ] 11 tables visible; RLS `true` on all 11; policies visible.
- [ ] Storage bucket `seo-content-assets` exists and is **private** (`public=false`); Storage RLS policies present.
- [ ] owner/admin/team_member advance the workflow via `seo_content_transition()`; status advances only along allowed transitions; each writes a `seo_content_activity` row.
- [ ] Client **cannot** insert/update any content record; client **can** SELECT opportunity/plan/wireframe; client **can** insert a comment; client comment update/delete → denied (append-only).
- [ ] Client `seo_content_transition` actions (`client_approve_wireframe`/`client_reject_wireframe`/`client_approve_draft`/`client_reject_draft`/`request_team_review`/`request_expert_review`/`comment`) **succeed only when `status IN ('wireframe_client_review','draft_client_review')`**, and are **rejected in any other status**; a client attempting `generate`/`edit`/`regenerate`/`publish`/internal-workflow actions or asset upload → rejected/denied.
- [ ] Client **cannot** SELECT drafts/sections until `status IN ('draft_client_review','draft_approved','ready_for_manual_publish','archived')`.
- [ ] Service-role insert of draft + sections succeeds; section regenerate writes a `seo_content_section_revisions` row and bumps `regeneration_count`.
- [ ] Insert `seo_content_assets` metadata with an allowed MIME → ok; a disallowed MIME (e.g. `image/svg+xml`, `application/zip`) → CHECK rejects. Upload to workspace-scoped path; a member of another workspace **cannot** read the object (Storage RLS); global admin can.
- [ ] Soft-delete an asset (`is_deleted=true`/`deleted_at`/`deleted_by`) → row retained, Storage object **not** hard-deleted; non-deleted listing filters it out.
- [ ] `asset_scope='workspace'` asset with `content_opportunity_id` NULL allowed; cross-workspace `content_opportunity_id` on a child → same-workspace integrity guard (Stage 2 pattern) raises.
- [ ] Global admin reads all content tables across workspaces.
- [ ] No public URL exposes any uploaded file.

---

## Next step

Review + approve this plan (resolve J-1…J-7), then **Phase 12G: write Stage 3 migration SQL** in the 3-file order, dry-run + smoke-test on the test project, and only then consider production apply (still gated on target-project + backup/branch + final review).
