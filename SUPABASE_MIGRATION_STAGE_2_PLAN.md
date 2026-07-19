# SEO Backend — Stage 2 Plan (Phase 12D): Audit / Recommendations / Approval

Planning only. **No SQL, no migration files, no DB connection in this phase.** Builds additively on Stage 1 (already applied + verified on a test project). Nothing here requires undoing Stage 1.

Status: **APPROVED — locked for SQL authoring.** See "Locked Decisions" below (authoritative; overrides any earlier wording in §1–§12).

Stage 1 objects reused: `seo_websites`, `seo_workspaces`, `seo_workspace_members`, and helpers `seo_is_global_admin(uid)`, `has_seo_module_access(uid)`, `is_seo_workspace_member(ws,uid)`, `seo_role_in(ws,roles[],uid)`, `can_manage_seo_workspace(ws,uid)`, `set_updated_at()`.

---

## Locked Decisions (Phase 12D — final, authoritative)

1. **Latest audit run** — `seo_audit_runs.is_latest` boolean, maintained by trigger (and by the `seo_run_audit` RPC on completion). Exactly **one** latest run per website: a partial unique index `UNIQUE (website_id) WHERE is_latest` guarantees it; the trigger clears the prior latest before/when setting the new one. Dashboard reads the latest via `WHERE is_latest`.
2. **Recommendation history** — **no** separate `recommendation_history` table. Use `seo_recommendations.is_current` + `superseded_by`; use `seo_approval_activity` for the action/history timeline.
3. **Audit generation** — client **may** trigger an audit via the `seo_run_audit` RPC (SECURITY DEFINER; creates the `seo_audit_runs` row). Clients **cannot** directly insert `seo_audit_issues` or `seo_recommendations`; those are written later by the service role / system process. RLS on issues/recommendations therefore excludes client (and, in fact, excludes direct client writes entirely — system-written).
4. **Comment mutability** — `seo_approval_comments` are **append-only** in Stage 2. No UPDATE, no DELETE policy for anyone (not even owner/admin) in Stage 2.
5. **Role snapshotting** — store `actor_role_snapshot text` on **`seo_approval_comments`** and **`seo_approval_activity`** (the role the actor held at the time). Membership may change later; historical rows keep their original role.
6. **`website_url` snapshot on all operational tables** — include `website_url` on **every** Stage 2 table: `seo_audit_runs`, `seo_audit_issues`, `seo_recommendations`, `seo_approval_items`, `seo_approval_comments`, `seo_approval_activity`. `website_id` remains the source of truth. (This overrides the earlier "child tables may omit website_url" note.)
7. **Approval item uniqueness** — exactly **one** approval item per recommendation: partial-safe `UNIQUE (recommendation_id)`. A changed recommendation is handled by inserting a **new** `seo_recommendations` row and superseding the old one (which produces its own new approval item); never create a second active approval row for the same recommendation.
8. **Status/type constraints** — **text + CHECK** constraints throughout, **not** PostgreSQL ENUM types (easier MVP evolution / adding values without `ALTER TYPE`).

---

## 1. Stage 2 objective

Persist the Technical Audit → Recommendation → Approval workflow behind the existing service layer, with **history preserved** (every audit run and recommendation version is retained) and **role-aware approval permissions** enforced in the DB (mirroring the frontend `approvalPermissions.ts` matrix). Supports current UI: Technical Audit, Page Optimizer/Recommendations, Approval Queue, Dashboard summaries. No crawler, no LLM, no CMS writes, no live publishing.

---

## 2. Tables proposed

| Table | Purpose |
|---|---|
| `seo_audit_runs` | one row per audit run (history preserved); scores + status |
| `seo_audit_issues` | issues found in a specific run (immutable per-run snapshot) |
| `seo_recommendations` | fixes derived from issues + on-page; versioned (`is_current`) |
| `seo_approval_items` | approval-queue entry per actionable recommendation |
| `seo_approval_comments` | threaded comments on an approval item |
| `seo_approval_activity` | append-only status/action history (approval + recommendation lifecycle) |

No separate `seo_recommendation_status_history` — recommendation versioning is handled by `is_current`/`superseded_by`, and status transitions are logged in `seo_approval_activity` (see §11 open questions).

---

## 3. Columns per table

Every operational table — **including child tables** (`comments`, `activity`) — carries the Stage-1 anchor set: `id uuid pk`, `workspace_id` (FK `seo_workspaces`), `website_id` (FK `seo_websites`), `website_url text` snapshot (Locked Decision 6), `created_by uuid`, `created_at`, `updated_at` (except append-only tables, which have no `updated_at`). Child tables also carry their parent FK.

**seo_audit_runs**
- `frequency` text · `status` text · `overall_visibility_score` int · `technical_health_score` int · `onpage_score` int · `authority_score` int · `ai_discovery_score` int · `issue_count` int default 0 · `is_latest` boolean default false (maintained by trigger — the newest completed run per website) · `started_at` timestamptz · `completed_at` timestamptz null · `error_message` text null.

**seo_audit_issues**
- `audit_run_id` uuid FK → `seo_audit_runs` · `category` text · `severity` text · `title` text · `simple_explanation` text · `why_it_matters` text · `technical_explanation` text · `affected_page_url` text · `impact` text · `effort` text · `risk` text · `confidence_percentage` int · `fix_owner` text · `suggested_next_action` text · `is_high_risk_category` boolean (set at insert from `category`) · `status` text default `'open'`.

**seo_recommendations**
- `audit_run_id` uuid FK → `seo_audit_runs` null (per decision 4) · `issue_id` uuid FK → `seo_audit_issues` null (on-page recs have none) · `area` text · `title` text · `current_value` text null · `suggested_change` text · `why_it_helps` text · `action_type` text · `impact` text · `effort` text · `risk` text · `confidence_percentage` int · `is_high_risk_category` boolean · `status` text default `'suggested'` · `is_current` boolean default true · `superseded_by` uuid FK → `seo_recommendations` null.

**seo_approval_items**
- `recommendation_id` uuid FK → `seo_recommendations` (**`UNIQUE`** — one approval item per recommendation, Locked Decision 7) · `issue_id` uuid FK → `seo_audit_issues` null · `title` text · `page_url` text null · `simple_explanation` text · `suggested_change` text · `action_type` text · `impact` text · `effort` text · `risk` text · `confidence_percentage` int · `fix_owner` text · `is_high_risk_category` boolean · `status` text default `'suggested'` · `assignee_user_id` uuid null (placeholder; no assignment workflow in Stage 2).

**seo_approval_comments** (append-only — Locked Decision 4)
- `approval_item_id` uuid FK → `seo_approval_items` · `author_user_id` uuid FK → `auth.users` · `actor_role_snapshot` text (SEO role at comment time — Locked Decision 5) · `comment_text` text. No `updated_at` (immutable).

**seo_approval_activity** (append-only)
- `approval_item_id` uuid FK → `seo_approval_items` · `actor_user_id` uuid · `actor_role_snapshot` text (Locked Decision 5) · `activity_type` text · `from_status` text null · `to_status` text null · `note` text null · `created_at`. No `updated_at` — immutable.

---

## 4. Enum / CHECK constraint recommendations

Use **text + CHECK** (matches Stage 1 + Core convention; lets us add values without `ALTER TYPE`). Values taken verbatim from current TS unions:

- audit `status`: `not_started, running, completed, failed`
- `frequency`: `monthly, weekly, weekly_plus_change_monitoring`
- issue `category`: `crawl, indexability, speed, mobile, schema, duplicate_content, broken_links, sitemap, robots_txt, canonical, redirects`
- `severity`: `critical, high, medium, low`
- issue `status`: `open, in_review, approved, fixed, ignored`
- recommendation `area`: `title, meta_description, h1, faq, schema, internal_links, content, technical`
- recommendation / approval `status`: `suggested, needs_review, approved, rejected, expert_review_requested, developer_needed, ready_to_publish, completed`
- `action_type`: `auto_suggest, approval_required, manual_support, expert_review, avoid`
- `fix_owner`: `client_action, developer_needed, digibility_expert, system_suggestion`
- `impact` / `effort` / `risk`: `low, medium, high`
- `confidence_percentage`: CHECK 0–100
- activity `activity_type`: `created, status_changed, comment_added, edited, expert_review_requested, developer_needed, completed, reassigned`

Add DB helper `public.seo_is_high_risk_category(cat text) returns boolean` (IMMUTABLE) → `cat IN ('robots_txt','canonical','redirects','sitemap','indexability')`, used to set `is_high_risk_category` and in RLS.

---

## 5. Foreign key relationships

```
seo_websites (Stage 1)
  └─ seo_audit_runs (website_id, workspace_id)  ON DELETE CASCADE
       └─ seo_audit_issues (audit_run_id)        ON DELETE CASCADE
            └─ seo_recommendations (issue_id)     ON DELETE SET NULL
seo_audit_runs
  └─ seo_recommendations (audit_run_id)           ON DELETE SET NULL
seo_recommendations
  ├─ seo_recommendations (superseded_by → self)   ON DELETE SET NULL
  └─ seo_approval_items (recommendation_id)        ON DELETE CASCADE
seo_approval_items
  ├─ seo_approval_comments (approval_item_id)      ON DELETE CASCADE
  └─ seo_approval_activity (approval_item_id)      ON DELETE CASCADE
```
All `website_id`/`workspace_id` → Stage-1 tables `ON DELETE CASCADE` (website teardown removes its whole audit tree). History is preserved by **never deleting runs/recs**, not by FK — deletion only happens on website removal.

---

## 6. RLS model by role

RLS ON for all 6 tables. Every policy `OR public.seo_is_global_admin()` for inspect-all. Reads scope to workspace membership.

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `seo_audit_runs` | member | active member + `has_seo_module_access` (running an audit is client-allowed) | owner/admin/team_member (status/scores) | manage (owner/admin) |
| `seo_audit_issues` | member | owner/admin/team_member (+ service role) — generated artifacts, **not** client | owner/admin/team_member | manage |
| `seo_recommendations` | member | owner/admin/team_member (+ service role) | owner/admin/team_member | manage |
| `seo_approval_items` | member | owner/admin/team_member | **role+risk gated — see §7** | manage |
| `seo_approval_comments` | member | active member (incl. client — commenting allowed for all) | — (append-only, no policy) | — (append-only, no policy) |
| `seo_approval_activity` | member | written by transition RPC/trigger (SECURITY DEFINER); no direct client insert | — (append-only) | — |

"member" = `is_seo_workspace_member(workspace_id)`. "manage" = `can_manage_seo_workspace(workspace_id)`. Service-role/webhook and the SECURITY DEFINER audit-generation RPC bypass RLS for system writes (issues/recommendations/activity).

New Stage-2 helper: `public.seo_role_of(ws_id uuid, uid uuid DEFAULT auth.uid()) returns text` (SECURITY DEFINER) → caller's active `seo_role` in the workspace (or null). Used by the transition RPC and approval-item `WITH CHECK`.

**Billing:** untouched in Stage 2. No new access to `seo_subscriptions` beyond the read granted in Stage 1. Plan-limit *enforcement* (audit frequency etc.) is deferred to the usage RPC (later stage), not Stage-2 RLS.

---

## 7. Permission model for approval actions

Primary enforcement: a `SECURITY DEFINER` RPC **`public.seo_approval_transition(p_item_id uuid, p_action text, p_note text)`** that reads the item's `risk`/`is_high_risk_category`/`action_type`, reads `seo_role_of(workspace_id)`, validates against the matrix below, updates `status`, and writes a `seo_approval_activity` row atomically. The frontend calls this RPC (not raw UPDATE), matching how `getAvailableActions` already centralizes the rules.

Definitions (mirror `approvalPermissions.ts`):
- `high_risk` = `risk <> 'low' OR is_high_risk_category`.
- `low_risk_simple` = `risk = 'low' AND NOT is_high_risk_category AND action_type IN ('auto_suggest','manual_support')`.

| Action → target status | owner/admin | team_member | client |
|---|---|---|---|
| comment | ✅ | ✅ | ✅ |
| approve → `approved` | ✅ | ✅ only if **not** high_risk | ✅ only if `low_risk_simple` |
| reject → `rejected` | ✅ | ✅ | ✅ only if `low_risk_simple` |
| edit suggestion | ✅ | ✅ | ❌ |
| request expert review → `expert_review_requested` | ✅ | ✅ | ✅ |
| send to developer → `developer_needed` | ✅ | ✅ | ✅ only if high_risk |
| mark completed → `completed` | ✅ | ❌ | ❌ |
| publish live | ❌ (no live publish in Stage 2 for anyone) | ❌ | ❌ |

Client high-risk safety: a client attempting approve/reject on a high-risk or non-simple item is rejected by the RPC with a message steering to **Request Expert Review** or **Send to Developer** (per rule 6). Clients can never set `approved` on anything touching URLs/redirects/canonical/noindex/robots.txt/sitemap (captured by `is_high_risk_category`) nor mark `completed`.

RLS **defense-in-depth** `WITH CHECK` on `seo_approval_items` UPDATE (in case of a direct write bypassing the RPC), by `seo_role_of(workspace_id)`:
- global admin / owner / admin → allowed.
- team_member → allowed **except** `NEW.status = 'completed'` and except `NEW.status = 'approved' AND high_risk`.
- client → allowed only when `NEW.status IN ('expert_review_requested','developer_needed')`, or (`NEW.status IN ('approved','rejected')` **AND** `low_risk_simple`); never `completed`.
- `ready_to_publish` / any publish path: allowed to set as a *queue marker* only by owner/admin; **no** row/status represents an executed live change (nothing publishes).

---

## 8. Data lifecycle

1. **Audit run** — created `running`; server/RPC (service role) writes issues; run flips to `completed` (or `failed` with `error_message`); trigger sets this run `is_latest=true` and clears the flag on the website's prior runs. Old runs are never deleted → full history for reports.
2. **Issues** — immutable snapshot of their run; `status` may move `open → in_review → approved/fixed/ignored`.
3. **Recommendations** — generated from issues + on-page templates, linked to `audit_run_id`; `is_current=true`. On a later run, superseded recs get `is_current=false` + `superseded_by`; **never deleted**. UI shows `is_current` by default; reports/roadmap can read history.
4. **Approval items** — generated from actionable recommendations; move through the status workflow **only via `seo_approval_transition`**; every transition appends `seo_approval_activity`; comments accumulate independently.
5. **Teardown** — only website deletion (Stage-1 cascade) removes the tree. No re-run "replace" — re-runs append.

---

## 9. Indexes

- `seo_audit_runs`: `(website_id)`, `(workspace_id)`, **`UNIQUE (website_id) WHERE is_latest`** (enforces one latest per website + fast dashboard read), `(started_at DESC)`.
- `seo_audit_issues`: `(audit_run_id)`, `(website_id)`, `(workspace_id)`, `(status)`, `(is_high_risk_category)`.
- `seo_recommendations`: `(website_id)`, `(workspace_id)`, `(audit_run_id)`, `(issue_id)`, `(status)`, `(website_id, is_current) WHERE is_current`.
- `seo_approval_items`: `(website_id)`, `(workspace_id)`, **`UNIQUE (recommendation_id)`**, `(status)`, `(is_high_risk_category)`.
- `seo_approval_comments`: `(approval_item_id)`, `(workspace_id)`.
- `seo_approval_activity`: `(approval_item_id, created_at DESC)`, `(workspace_id)`.
- `updated_at` triggers on all except append-only `seo_approval_activity`.

---

## 10. What Stage 2 intentionally does NOT include

- No crawler / real audit execution (issues are written by service/mock; run creation is real, crawl is not).
- No LLM generation of recommendations/content.
- No CMS write-back, no live publishing, no `ready_to_publish` that executes anything.
- No plan-limit/usage enforcement (audit frequency caps) — deferred to the usage RPC stage.
- No billing/subscription writes; no member/workspace management (Stage 1 owns those).
- No Content Studio, performance, off-page, AI, competitor, roadmap, support, report, or admin tables (later stages).
- No assignment workflow (only an `assignee_user_id` placeholder column).

---

## 11. Risks / open questions

**Resolved in Phase 12D** (see Locked Decisions — no longer open):
- ✅ `is_latest` maintenance → boolean maintained by trigger + `seo_run_audit` RPC, `UNIQUE (website_id) WHERE is_latest` (Decision 1).
- ✅ Recommendation history → `is_current`/`superseded_by` + `seo_approval_activity`; no separate table (Decision 2).
- ✅ Issue/recommendation generation → client triggers `seo_run_audit` RPC; issues/recs written by service role/system, never by client (Decision 3).
- ✅ Comment mutability → append-only, no update/delete in Stage 2 (Decision 4).
- ✅ Role snapshot → `actor_role_snapshot` on comments + activity (Decision 5).
- ✅ `website_url` on child tables → included on all Stage 2 tables (Decision 6).
- ✅ Approval item uniqueness → one per recommendation via `UNIQUE (recommendation_id)`; changes create a new recommendation + supersede (Decision 7).
- ✅ ENUM vs CHECK → text + CHECK throughout (Decision 8).

**Remaining blockers:** none. Stage 2 is **ready for SQL authoring** (Phase 12E). Non-blocking implementation detail to settle while writing SQL: the exact `seo_run_audit` RPC signature/return (recommend returning the new `audit_run` id with `status='running'`).

---

## 12. Recommended migration file breakdown (3 files, mirrors Stage 1)

1. `2026071112xxxx_seo_stage2_audit.sql` — `seo_audit_runs`, `seo_audit_issues`, `seo_is_high_risk_category()`, `is_latest` trigger, RLS.
2. `2026071112xxxx_seo_stage2_recommendations.sql` — `seo_recommendations`, `is_current`/supersede support, RLS.
3. `2026071112xxxx_seo_stage2_approval.sql` — `seo_approval_items`, `seo_approval_comments`, `seo_approval_activity`, `seo_role_of()`, `seo_approval_transition()` RPC, RLS (incl. the §7 `WITH CHECK`).

Timestamps must sort after Stage 1 (`20260711120003`). Each file additive, RLS enabled on create, no changes to Stage 1 or Core objects.

---

## Next step

Review + approve this plan, then **Phase 12E: write Stage 2 migration SQL** in the 3-file order above, dry-run on the test project, and verify the approval permission matrix (esp. client high-risk blocks) before any production apply.
