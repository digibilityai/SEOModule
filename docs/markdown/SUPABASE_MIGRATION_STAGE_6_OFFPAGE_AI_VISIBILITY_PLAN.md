# Supabase Migration — Stage 6: Off-Page Authority + AI Visibility / GEO (Plan)

**Status: decisions LOCKED; migration SQL now AUTHORED (not applied).** The seven
open decisions are **resolved and locked (see §0)**, and the Stage 6 migration
SQL has since been **authored** to this spec —
`supabase/migrations/20260711120017`–`…120023` (7 files) — see
`SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md`. **The SQL is NOT
dry-run, NOT applied, NOT verified, NOT wired; no database has been touched;
production remains untouched.** This document remains the design rationale; the
locked decisions were not changed by the SQL authoring. No app code, existing
migrations, seeds, or the reference Digibility app were modified.

> **Preflight source of truth:** `CURRENT_PROJECT_STATUS.md` (status),
> `PROJECT_DOCUMENTATION_INDEX.md` (doc map), `DOCUMENTATION_WORKFLOW_RULES.md`
> (workflow). Backend conventions: `BACKEND_MILESTONE_HANDOFF.md` +
> `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`. This plan continues the timestamp
> sequence after Stage 5 (`…120016`).

---

## 0. Locked Decisions (SQL-ready)

The seven open questions from the first draft (retained in §14 for traceability)
have been **resolved and locked**. The rest of this document is the design
rationale; **this section is the authoritative spec the migration-SQL author
should follow.** These decisions are locked for SQL authoring unless a future
review explicitly changes them.

Still **PLAN ONLY**: no SQL has been created, no database has been touched,
nothing is applied or verified, production remains untouched.

**D1 — Campaign ↔ opportunity: normalized junction (LOCKED).**
Use `seo_authority_campaign_opportunities` (real FKs to campaign + opportunity,
`PRIMARY KEY (campaign_id, opportunity_id)`, cascade on both) as the **source of
truth**. **Do not add `opportunity_ids uuid[]`** to `seo_authority_campaigns`.
The later service-wiring phase maps junction rows back into the UI's
`opportunity_ids: string[]` — no UI/type change.

**D2 — `seo_ai_mentions`: included (LOCKED).**
Adopt `seo_ai_mentions` as **normalized rows** in Stage 6. Mentions are **not**
left permanently derived from prompt-tracking blobs. The table supports brand
mentions, competitor mentions, and citation/source visibility, and is the store
that feeds brand/competitor summaries and future reporting. (The service layer
may still compute summaries; it reads these rows rather than re-parsing prompt
arrays.)

**D3 — Client writes: none in Stage 6 v1 (LOCKED).**
Clients get **read-only** access to safe/reporting data across all Stage 6
tables. `owner` / `admin` / `team_member` / global admin write and manage. **No
client write** — the previously-floated "client may flip a campaign task
`is_complete`" exception is **not** adopted; any future narrow client write must
be a separate, explicit phase, not assumed now.

**D4 — AI prompt tracking: time-series observations (LOCKED).**
`seo_ai_prompt_tracking` is **time-series observation data**. Repeated
observations of the **same prompt on later dates are allowed and first-class**.
**No uniqueness rule on `prompt_text`.** Add an `observed_on date NOT NULL
DEFAULT current_date` column and index by `website_id` / `observed_on` /
`visibility_status` / `source` instead of any over-strict unique constraint.

**D5 — Guarded transition RPCs for Off-Page workflow (LOCKED).**
Off-Page status movement goes through `SECURITY DEFINER` transition RPCs
(matching the Stage 2/3 pattern), **not** free-form status UPDATEs, because these
statuses gate external-facing execution and safety matters:
- `seo_authority_opportunity_transition(p_opportunity_id uuid, p_action text, p_note text DEFAULT NULL)`
- `seo_authority_campaign_transition(p_campaign_id uuid, p_action text, p_note text DEFAULT NULL)`

Each RPC: resolves the row, checks the caller's role **inside** the function
(rejecting clients/non-members even though `EXECUTE` is granted to
`authenticated`), enforces a **valid action→status transition** (rejecting unsafe
jumps), stamps `updated_at`, and writes an audit row to `seo_authority_activity`
(see D5a). Allowed transitions:

*Opportunity* (`status`):
| action | from → to | role |
| --- | --- | --- |
| `shortlist` | `suggested` → `shortlisted` | owner/admin/team_member |
| `request_approval` | `shortlisted` → `approval_required` | owner/admin/team_member |
| `request_expert_review` | `shortlisted`\|`approval_required`\|`in_progress` → `expert_review_requested` | owner/admin/team_member |
| `start` | `approval_required`\|`expert_review_requested` → `in_progress` | owner/admin/team_member |
| `complete` | `in_progress` → `completed` | owner/admin/team_member |
| `reject` | any non-terminal → `rejected` | owner/admin |
| `avoid` | any non-terminal → `avoided` | owner/admin/team_member |

`start` is only reachable **after** `approval_required` or
`expert_review_requested` — this is the schema-enforced guarantee that an
external-facing action passes approval/expert review before execution
(requirement 7). Unsafe jumps (e.g. `suggested → in_progress`, reopening a
terminal `completed`/`rejected`/`avoided`) raise. Terminal states:
`completed`, `rejected`, `avoided`.

*Campaign* (`approval_status`):
| action | from → to | role |
| --- | --- | --- |
| `submit_for_approval` | `draft` → `pending_approval` | owner/admin/team_member |
| `approve` | `pending_approval` → `approved` | owner/admin (+ global admin) |
| `reject` | `pending_approval` → `rejected` | owner/admin (+ global admin) |
| `return_to_draft` | `pending_approval`\|`rejected` → `draft` | owner/admin/team_member |

Approve/reject are **manager-only** (owner/admin/global admin), mirroring
`can_manage_seo_workspace`; a team_member may submit and rework but not
self-approve.

**AI Visibility stays plain-RLS-written (LOCKED).** `seo_ai_prompt_tracking`,
`seo_ai_content_gaps`, and `seo_ai_mentions` are observed/reporting data, not
external-facing execution — managers write them via normal RLS-gated
INSERT/UPDATE. **No transition RPC for AI Visibility.**

**D5a — `seo_authority_activity` audit table (LOCKED, consequence of D5).**
A lightweight append-only activity/audit table backs the transition RPCs so
who-did-what-when is captured. Columns: standard record columns (workspace/
website/url), `opportunity_id uuid` (nullable, FK→opportunities cascade) +
`campaign_id uuid` (nullable, FK→campaigns cascade) with a CHECK that **exactly
one** is set, `action text`, `from_status text`, `to_status text`, `note text`,
`actor_role_snapshot text` (the caller's resolved SEO role at action time, like
Stage 2's `seo_approval_activity`), `created_by`, `created_at`. **Append-only**
(SELECT for members; INSERT via the RPCs / managers; **no** UPDATE/DELETE
policy for anyone), matching the Stage 2/3 activity-table pattern.

**D6 — Campaign progress: derived, not stored (LOCKED).**
**Do not store `progress_percentage`** on `seo_authority_campaigns`. Progress is
derived from `seo_authority_campaign_tasks` (`count(is_complete)/count(*)`). The
frontend `AuthorityCampaign.progress_percentage` field is populated by the later
service-wiring phase (compute-on-read); an optional read-only
`security_invoker` view can be added later if a SQL-side value is ever needed —
not in Stage 6.

**D7 — Opportunity duplicate guard: soft, active-only (LOCKED).**
Add only a **soft** duplicate guard on `seo_authority_opportunities`:
- A **partial unique index** preventing a duplicate **active** opportunity for
  the same `(website_id, opportunity_type, lower(target_url))` **only when
  `target_url IS NOT NULL`** and `status` is in the **active set**
  (`suggested`, `shortlisted`, `approval_required`, `in_progress`,
  `expert_review_requested`).
- **Terminal opportunities never block** — `completed`, `rejected`, `avoided`
  are excluded from the index, so a resolved/avoided idea does not prevent a
  future one.
- **No guard when `target_url` is missing** — pure ideas (citations/reviews/
  community with no URL) may repeat freely.
- **Never dedupe by `title` alone.**
- An optional nullable `target_domain text` (app-populated, not a DB trigger) is
  included for future domain-level grouping/reporting; the v1 unique guard keys
  on `target_url`, not `target_domain`.

**Locked object list:** 8 tables + 2 RPCs — see §2 (updated) and §9 (updated).

---

## 1. Purpose

Stage 6 gives the two next modules in the approved rollout order a real Supabase
backend, replacing their mock-only adapters in a later wiring phase:

1. **Off-Page Authority Builder** — trust-signal / backlink / citation / review
   / PR / partnership **opportunities** (not automation), grouped into
   **campaigns** with **tasks**, with explicit spam-risk flagging and
   approval/expert-review gating for anything external-facing.
2. **AI Visibility / GEO** — **prompt-tracking** records (how a business appears
   in AI answers), **content gaps** surfaced from those, and (proposed)
   normalized **mention** rows that feed brand/competitor summaries.

Stage 6 stores **observed / manual / imported** data only. It ships **no real
backlink automation, no review generation, no mass outreach, no LLM scraping,
and no external API ingestion** — provenance is recorded via `source` columns
(`manual_seed` / `import` / `system`) without implying any integration exists.

This plan was validated against the **actual current frontend/mock model**
(`src/types/offpage.ts`, `src/types/aiVisibility.ts`, `src/mocks/offPageMockData.ts`,
`src/mocks/aiVisibilityMockData.ts`, `src/services/offPageService.ts`,
`src/services/aiVisibilityService.ts`) as well as
`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` §"Off-page & AI visibility". The two
sources agree on the table set; where the current code and the architecture plan
differ (see §14), this doc flags the decision rather than guessing.

---

## 2. Tables proposed

**Locked table list — 8 tables** (all adopted per §0; junction, mentions, and
activity are confirmed, not optional):

| Table | Backs / role | Kind |
| --- | --- | --- |
| `seo_authority_opportunities` | `OffPageOpportunity` (`offpage.ts`) | operational |
| `seo_authority_campaigns` | `AuthorityCampaign` (`offpage.ts`) — **no `opportunity_ids[]`, no `progress_percentage`** (D1/D6) | operational |
| `seo_authority_campaign_tasks` | `CampaignTask` (embedded in `AuthorityCampaign.tasks`) | child of campaigns |
| `seo_authority_campaign_opportunities` | Junction campaign ↔ opportunity (D1) — real FKs, source of truth for campaign membership | junction |
| `seo_authority_activity` | Append-only audit trail for the Off-Page transition RPCs (D5a) | audit (append-only) |
| `seo_ai_prompt_tracking` | `PromptTrackingRecord` (`aiVisibility.ts`) — **time-series, `observed_on date`** (D4) | operational |
| `seo_ai_content_gaps` | `AiContentGap` (`aiVisibility.ts`) | operational |
| `seo_ai_mentions` | Normalized brand/competitor/citation mention rows (D2) — store that feeds summaries + future reporting | operational |

**Plus 2 RPCs** (D5): `seo_authority_opportunity_transition(...)`,
`seo_authority_campaign_transition(...)` — `SECURITY DEFINER`, guarded,
manager-gated, activity-logging.

---

## 3. Column design (per table)

All operational tables carry the standard SEO record columns, matching Stage 4/5
exactly: `id uuid PK`, `workspace_id uuid NOT NULL → seo_workspaces`,
`website_id uuid NOT NULL → seo_websites`, `website_url text NOT NULL` (snapshot),
`created_by uuid → auth.users ON DELETE SET NULL`, `created_at`, `updated_at`.
The app's flat types expose both `user_id` and `created_by`; both map from
`created_by` (same as Stage 4/5). **Child tables also carry
`workspace_id`/`website_id`/`website_url`** — not for their own sake but because
the RLS predicate must call `is_seo_workspace_member(workspace_id)` on the row
itself; this follows the Stage 5 `seo_decline_diagnosis_evidence` precedent
(requirement 1's "pure child" exemption is deliberately *not* taken, for RLS
uniformity).

> **Note:** §3 below is the original per-column draft. Where it still shows an
> unresolved either/or, the **§0 Locked Decisions win** — the inline callouts
> here have been updated to match (D1/D4/D6/D7).

### 3.1 `seo_authority_opportunities`
- `opportunity_type text NOT NULL CHECK IN ('backlink','mention','citation','review','pr','social_community','partnership')`
- `title text NOT NULL`, `source_platform text NOT NULL`, `target_url text` (nullable), `target_domain text` (nullable, app-populated — D7 grouping/reporting; not in the unique key)
- `suggested_action text NOT NULL`, `why_it_matters text NOT NULL`
- `expected_authority_impact text NOT NULL CHECK IN ('low','medium','high')`
- `effort text NOT NULL CHECK IN ('low','medium','high')`
- `risk text NOT NULL CHECK IN ('low','medium','high')`
- `confidence_percentage integer CHECK (0..100)` (nullable — some system flags have no score)
- `requires_approval boolean NOT NULL DEFAULT true` (safe default: external-facing needs approval)
- `fix_owner text NOT NULL CHECK IN ('client_action','developer_needed','digibility_expert','system_suggestion')`
- `status text NOT NULL DEFAULT 'suggested' CHECK IN ('suggested','shortlisted','approval_required','in_progress','expert_review_requested','completed','rejected','avoided')`
- `spam_risk_flags text[] NOT NULL DEFAULT '{}' CHECK (spam_risk_flags <@ ARRAY['paid_link_risk','irrelevant_directory','pbn_like_site','exact_match_anchor_manipulation','fake_review_risk','mass_outreach_risk','low_relevance','low_trust']::text[])` — array containment CHECK validates every element is an allowed flag, keeping the mock's array shape without a child table.
- `source text NOT NULL DEFAULT 'manual_seed' CHECK IN ('manual_seed','import','system')` — provenance only.

### 3.2 `seo_authority_campaigns`
- `name text NOT NULL`, `goal text NOT NULL`
- `approval_status text NOT NULL DEFAULT 'draft' CHECK IN ('draft','pending_approval','approved','rejected')`
- `owner text NOT NULL CHECK IN ('client_action','developer_needed','digibility_expert','system_suggestion')`
- `due_date date` (nullable)
- **No `progress_percentage` column (D6)** — derived from campaign tasks in the service layer (compute-on-read); an optional `security_invoker` view can add a SQL-side value later if ever needed.
- **No `opportunity_ids[]` column (D1)** — campaign membership lives in the `seo_authority_campaign_opportunities` junction (§3.4), which is the source of truth.

### 3.3 `seo_authority_campaign_tasks` (child of campaigns)
- `campaign_id uuid NOT NULL → seo_authority_campaigns ON DELETE CASCADE`
- `label text NOT NULL`, `is_complete boolean NOT NULL DEFAULT false`
- `position integer NOT NULL DEFAULT 0` (display order)
- Optional `opportunity_id uuid → seo_authority_opportunities ON DELETE SET NULL` (the mock derives task labels from an opportunity's `suggested_action`; a nullable link preserves that provenance).

### 3.4 `seo_authority_campaign_opportunities` (junction — LOCKED, D1)
- `campaign_id uuid NOT NULL → seo_authority_campaigns ON DELETE CASCADE`
- `opportunity_id uuid NOT NULL → seo_authority_opportunities ON DELETE CASCADE`
- `PRIMARY KEY (campaign_id, opportunity_id)`
- carries `workspace_id` (+ `website_id`/`website_url`) for RLS.

### 3.4a `seo_authority_activity` (append-only audit — LOCKED, D5a)
- standard record columns (`workspace_id`/`website_id`/`website_url`)
- `opportunity_id uuid → seo_authority_opportunities ON DELETE CASCADE` (nullable)
- `campaign_id uuid → seo_authority_campaigns ON DELETE CASCADE` (nullable)
- CHECK `(opportunity_id IS NOT NULL) <> (campaign_id IS NOT NULL)` — exactly one subject
- `action text NOT NULL`, `from_status text`, `to_status text`, `note text`
- `actor_role_snapshot text` (caller's resolved SEO role at action time)
- `created_by`, `created_at`. **Append-only:** SELECT for members; INSERT via the
  transition RPCs / managers; **no** UPDATE/DELETE policy (Stage 2/3 pattern).

### 3.5 `seo_ai_prompt_tracking`
- `prompt_text text NOT NULL`, `topic text NOT NULL`
- `brand_mentioned boolean NOT NULL DEFAULT false`
- `competitors_mentioned text[] NOT NULL DEFAULT '{}'` (free text — competitor names, no CHECK)
- `citation_sources text[] NOT NULL DEFAULT '{}'` (free text — URLs/source names, no CHECK)
- `our_site_cited boolean NOT NULL DEFAULT false`
- `visibility_status text NOT NULL DEFAULT 'unknown' CHECK IN ('visible','partially_visible','not_visible','unknown')`
- `gap_summary text NOT NULL DEFAULT ''`, `recommended_next_step text NOT NULL DEFAULT ''`
- `source text NOT NULL DEFAULT 'manual_seed' CHECK IN ('manual_seed','import','system')` — observed/manual/imported only (requirement 9/10).
- `observed_on date NOT NULL DEFAULT current_date` (D4) — the observation date. **Time-series: the same `prompt_text` may be tracked again on a later `observed_on`; there is no `prompt_text` uniqueness.** Indexed by `(website_id, observed_on DESC)` and `visibility_status`/`source`.

### 3.6 `seo_ai_content_gaps`
- `topic text NOT NULL`, `missing_answer_angle text NOT NULL`
- `suggested_content_type text NOT NULL`, `related_keyword_or_question text NOT NULL`
- `priority text NOT NULL DEFAULT 'medium' CHECK IN ('low','medium','high')`
- `recommended_next_action text NOT NULL`
- `source text NOT NULL DEFAULT 'manual_seed' CHECK IN ('manual_seed','import','system')`
- Optional `prompt_id uuid → seo_ai_prompt_tracking ON DELETE SET NULL` (a gap often originates from a tracked prompt; nullable link).

### 3.7 `seo_ai_mentions` (LOCKED, D2)
- `prompt_id uuid → seo_ai_prompt_tracking ON DELETE CASCADE` (nullable — a mention may be recorded independently of a specific tracked prompt; cascade when linked)
- `mention_type text NOT NULL CHECK IN ('brand','competitor','citation_source')` — D2 says mentions support brand mentions, competitor mentions, **and citation/source visibility**; `citation_source` rows capture which source/site an AI answer cited (feeding "where our site / a competitor is cited" reporting).
- `entity_name text NOT NULL` (the brand, competitor, or citation source/site name)
- `is_our_site boolean NOT NULL DEFAULT false` — for `citation_source` rows, whether the cited source is the tracked website (supports "our site cited" summaries without re-parsing prompt arrays).
- `where_appears text` (prompt/answer context snippet), `notes text`
- `source text NOT NULL DEFAULT 'manual_seed' CHECK IN ('manual_seed','import','system')`

---

## 4. Reconciliation with current code + prior stages

- **Off-page has its own status model, separate from the Stage 2 approval queue.**
  `OffPageOpportunity.status` and `AuthorityCampaign.approval_status` are distinct
  from `seo_approval_items`. Stage 6 preserves that (own status columns). A future
  option to route `requires_approval` opportunities / `pending_approval` campaigns
  *into* the Stage 2 queue is noted in §13, not built.
- **AI mention summaries are currently derived, not stored.** `offPageMockData`/
  `aiVisibilityMockData` compute `BrandMentionSummary` / `CompetitorMentionSummary`
  from prompt-tracking rows. `seo_ai_mentions` (§3.7) would let those be stored +
  aggregated instead of recomputed — a genuine enrichment, but a decision (§14).
- **Overviews (`AuthorityOverview`, `AiVisibilityOverview`) are aggregates**, not
  tables — computed in the service layer (they also read `authority_score` /
  `ai_discovery_score` from the latest audit). No Stage 6 table needed for them.
- **Naming** matches prior stages (`seo_` prefix, snake_case, `_at` timestamps,
  `text` + `CHECK` enums, `security_invoker` for any future views).
- **Additive + non-destructive** (requirement 11/12): new tables only; the sole
  touch to existing tables is **FK references** from Stage 6 tables to
  `seo_workspaces` / `seo_websites` / `auth.users` (and internal Stage 6 FKs). No
  Core or existing SEO table is altered.

---

## 5. RLS model

RLS **enabled** on every Stage 6 table, reusing Stage 1 helpers only — no new
auth, no `profiles.role`, no service-role dependency. Same shape as Stage 4/5:

- **SELECT** — `is_seo_workspace_member(workspace_id) OR seo_is_global_admin()`
  (any active member, **including `client`**, reads — off-page opportunities and
  AI visibility are safe/reporting data).
- **Write (ALL)** —
  `seo_role_in(workspace_id, ARRAY['owner','admin','team_member']) OR seo_is_global_admin()`
  (owner/admin/team_member manage; **clients cannot write** by default).
- `updated_at` maintained by the Stage 1 `set_updated_at()` trigger on every
  table that has an `updated_at` column.

**Client writes: none (LOCKED — D3).** Clients are **read-only across all Stage 6
tables**, matching Stage 4/5. The previously-floated "client may flip a campaign
task `is_complete`" exception is **not** adopted; any future narrow client write
is a separate, explicit phase — not assumed here.

**Off-Page status changes go through the transition RPCs (D5), not raw UPDATEs.**
The RPCs are `SECURITY DEFINER` with an internal manager-role check, so clients
and non-members are rejected there too; `EXECUTE` is granted to `authenticated`
but the in-function check is the real gate (Stage 2/3 pattern). AI Visibility
tables take plain manager RLS writes (no RPC).

---

## 6. Role access model

| Role | Read all Stage 6 | Insert/update/delete | Notes |
| --- | --- | --- | --- |
| `owner` | ✅ | ✅ | full manage |
| `admin` | ✅ | ✅ | full manage |
| `team_member` | ✅ | ✅ (write/manage; campaign `approve`/`reject` are manager-only, D5) | full manage except self-approving a campaign |
| `client` | ✅ (read-only) | ❌ | **no client writes in Stage 6 v1 (D3)** |
| non-member | ❌ (0 rows) | ❌ | isolated |
| global admin | ✅ | ✅ | via `seo_is_global_admin()` |

---

## 7. Status workflows

- **Off-page opportunity** (`status`): `suggested → shortlisted → approval_required
  → in_progress → expert_review_requested → completed | rejected | avoided`. Any
  **external-facing action** (backlink/PR/review outreach) is expected to pass
  through `approval_required` / `expert_review_requested` before `in_progress`
  (requirement 7). `avoided` is the terminal state for spam-flagged items
  (requirement 4–6): the schema records the *decision to avoid*, it never
  automates the action.
- **Campaign** (`approval_status`): `draft → pending_approval → approved | rejected`.
  A campaign only moves to execution once `approved`.
- **Prompt visibility** (`visibility_status`): `unknown / not_visible /
  partially_visible / visible` — a state label of observed AI presence, not a
  workflow; freely settable by managers as observations are recorded/imported.
- **v1 mechanism (LOCKED — D5):** Off-Page status movement (opportunity + campaign)
  goes through **guarded `SECURITY DEFINER` transition RPCs**
  (`seo_authority_opportunity_transition`, `seo_authority_campaign_transition`)
  that enforce valid action→status transitions, manager role checks, and
  activity logging — see §0/D5 for the full transition matrices and the
  `seo_authority_activity` audit table (D5a). This prevents unsafe status jumps
  (e.g. `suggested → in_progress` skipping approval) at the database, not just in
  the UI. **AI Visibility** status (`visibility_status`) stays a plain
  RLS-gated manager UPDATE — it is observed/reporting data, not an
  external-facing execution action.

---

## 8. Safety guarantees (requirements 4–10, restated as schema facts)

- **No spammy backlink automation / no fake reviews / no mass outreach:** Stage 6
  stores *opportunities and decisions*, never executes outreach. `spam_risk_flags`
  + the `avoided` status exist specifically to record and steer *away from* risky
  actions. No table, trigger, or RPC sends anything anywhere.
- **External-facing actions require approval/manual status:** `requires_approval`
  defaults `true`; the status lifecycle gates execution behind
  `approval_required` / `expert_review_requested`.
- **No guaranteed-ranking claims:** no schema field asserts an outcome; impact is
  `low/medium/high` estimation only.
- **AI Visibility is observed/manual/imported:** `source ∈ (manual_seed, import,
  system)`; `last_checked_at` is a passive seam. **No LLM call, no scraper, no
  external API, no cron** anywhere in Stage 6.

---

## 9. Proposed migration file split (timestamps continue after `…120016`)

One migration per table/logical unit, matching Stage 4/5 granularity. **7 files
(`…120017`–`…120023`), all locked:**

| File | Contents |
| --- | --- |
| `20260711120017_seo_stage6_authority_opportunities.sql` | `seo_authority_opportunities` (incl. nullable `target_domain`, D7 soft-dup partial unique index) + indexes + `updated_at` trigger + RLS |
| `20260711120018_seo_stage6_authority_campaigns.sql` | `seo_authority_campaigns` (**no `opportunity_ids[]`, no `progress_percentage`** — D1/D6) + indexes + trigger + RLS |
| `20260711120019_seo_stage6_authority_campaign_children.sql` | `seo_authority_campaign_tasks` + `seo_authority_campaign_opportunities` (junction, D1) + indexes + trigger + RLS |
| `20260711120020_seo_stage6_ai_prompt_tracking.sql` | `seo_ai_prompt_tracking` (time-series, `observed_on date` — D4) + indexes + trigger + RLS |
| `20260711120021_seo_stage6_ai_content_gaps.sql` | `seo_ai_content_gaps` + indexes + trigger + RLS |
| `20260711120022_seo_stage6_ai_mentions.sql` | `seo_ai_mentions` (D2) + indexes + trigger + RLS |
| `20260711120023_seo_stage6_authority_activity_and_transitions.sql` | `seo_authority_activity` (append-only audit, D5a) + the two transition RPCs `seo_authority_opportunity_transition` / `seo_authority_campaign_transition` (D5) + `GRANT EXECUTE … TO authenticated` |

Ordering matters: `…120019` (junction/tasks) must follow `…120017` + `…120018`;
`…120022` (mentions) must follow `…120020` (prompt tracking); `…120023`
(activity + RPCs) is **last** — the RPCs reference the opportunity/campaign
tables and write to `seo_authority_activity`, so all Off-Page tables must exist
first.

---

## 10. Constraints, indexes, uniqueness

- **Indexes** on every FK/filter column, matching Stage 4/5: `workspace_id`,
  `website_id` on all; plus `opportunity_type`/`status`/`risk` (opportunities),
  `approval_status`/`due_date` (campaigns), `campaign_id` (tasks + junction),
  `visibility_status`/`observed_on`/`source`/`topic` (prompt tracking — D4),
  `priority` (content gaps), `prompt_id`/`mention_type`/`entity_name` (mentions),
  `opportunity_id`/`campaign_id` (activity). Composite `(website_id, status)` /
  `(website_id, visibility_status)` / `(website_id, observed_on DESC)` for the
  common per-website listing reads.
- **Array CHECK:** `spam_risk_flags <@ ARRAY[…allowed…]` (element-membership).
- **Junction PK:** `(campaign_id, opportunity_id)` — prevents duplicate links.
- **Task ordering:** unique `(campaign_id, position)` (per-campaign ordered
  tasks; positions unique within a campaign).
- **Opportunity soft-dup guard (LOCKED — D7):** partial unique index on
  `(website_id, opportunity_type, lower(target_url))` **WHERE `target_url IS NOT
  NULL` AND `status` IN (`suggested`,`shortlisted`,`approval_required`,
  `in_progress`,`expert_review_requested`)** — blocks a duplicate *active*
  opportunity for the same URL, lets terminal (`completed`/`rejected`/`avoided`)
  and URL-less opportunities repeat. **No `prompt_text` uniqueness** on prompt
  tracking (D4 — time-series; repeat observations are first-class).
- **Activity CHECK:** exactly one of `opportunity_id` / `campaign_id` set
  (`(opportunity_id IS NOT NULL) <> (campaign_id IS NOT NULL)`); append-only (no
  UPDATE/DELETE policy).

---

## 11. Smoke-test plan (for a later `seo_stage6_offpage_ai_smoke_test.sql`)

Follows the corrected Stage 4/5 pattern exactly (UUID prefix **`99999999-`** —
unused by any prior smoke test/seed: `aaaaaaaa`/`bbbbbbbb`, `33333333`,
`55555555`, `77777777`, `44444444`, `66666666`, `88888888`). Run only on a
disposable TEST project; loud **DO NOT RUN ON PRODUCTION** header; no
`auth.users` inserts; placeholder-UUID guard; optional commented teardown.

Coverage:
- **Setup** (privileged role): disposable workspace + owner/admin/team/client
  members + website.
- **Positive writes** as team_member/admin: insert an opportunity, a campaign, a
  task, a junction link, a prompt-tracking row, a content gap, a mention.
- **Transition RPCs (D5):** exercise `seo_authority_opportunity_transition`
  through a legal path (`shortlist → request_approval → start → complete`) and
  assert each `status` + a matching `seo_authority_activity` row is written;
  assert an **unsafe jump raises** (e.g. `start` from `suggested`, reopening a
  terminal); exercise `seo_authority_campaign_transition`
  (`submit_for_approval → approve`) and assert a **team_member cannot `approve`**
  (manager-only) while owner/admin can.
- **RLS SELECT** for owner/admin/team/client (all see the workspace rows,
  including `seo_authority_activity`) and **non-member = 0 rows**, each inside
  its own `BEGIN; _login(); SET LOCAL ROLE authenticated; … ROLLBACK;` block
  (the corrected Stage 4/5 pattern — a bare JWT-claim-only block runs as
  `postgres`/BYPASSRLS and would falsely pass).
- **Client is read-only (D3):** client INSERT (raises) + client direct-UPDATE
  (0 rows) on every table, **and** client call of each transition RPC **raises**
  (in-function role check).
- **Activity append-only:** client/any-role UPDATE/DELETE on
  `seo_authority_activity` is blocked (0 rows / raises).
- **CHECK-constraint rejection** of invalid `opportunity_type` / `status` /
  `risk` / `fix_owner` / a bad `spam_risk_flags` element (`<@` violation) /
  invalid `visibility_status` / invalid `priority` / bad `source` / invalid
  `approval_status` / `mention_type` / the activity "exactly one subject" CHECK.
- **Uniqueness rejection** for the junction PK, `(campaign_id, position)`, and
  the D7 active-only opportunity soft-dup index — plus a **positive** check that a
  *terminal* (`avoided`) duplicate URL and a *URL-less* duplicate are **allowed**,
  and that the **same prompt re-tracked on a later `observed_on` is allowed** (D4).
- **Cascade check:** deleting a campaign removes its tasks + junction +
  campaign-subject activity rows; deleting a prompt removes its mentions.
- `PASS`/`FAIL` notices throughout.

---

## 12. Seed strategy (for a later UI seed extension — NOT created now)

A future `supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`,
attaching to the **existing base UI seed** workspace
(`44444444-0000-0000-0001-000000000001`) / website
(`https://ui-seed-digibility.example`), mirroring the Stage 4/5 seed pattern:

- New UUID prefix (e.g. **`aaaa0000-`** or the next unused fixed prefix — confirm
  at seed time it collides with nothing).
- Dependency guards: base UI seed present; (for AI content gaps / mentions that
  link to prompts) the prompt rows this seed creates.
- Realistic demo rows translated from the current mock seeds (9 opportunities
  incl. 2 `avoided` spam examples, 1 campaign + tasks, 4 prompt-tracking rows
  across all 4 `visibility_status` values, 3 content gaps, derived mentions).
- All `source = 'manual_seed'`; loud TEST-only header; idempotent `ON CONFLICT
  (id) DO NOTHING`; commented teardown; verified expected counts documented in a
  matching `SUPABASE_STAGE6_*_SEED_EXTENSION_GUIDE.md`.

---

## 13. Service-wiring implications (for a later Phase — NOT wired now)

- **New Supabase services:** `seoOffPageAuthoritySupabaseService.ts` and
  `seoAiVisibilitySupabaseService.ts` under `src/services/supabase/`, mapping
  Stage 6 rows into the existing flat types (same "map down into existing shape,
  no UI/type change" approach as Phase 14A.2 / 14B.2).
- **Adapter wiring:** `offPageService.ts` (`fetchAuthorityOpportunities`,
  `updateAuthorityOpportunityStatus`, `fetchAuthorityCampaigns`,
  `createAuthorityCampaign`, `fetchSpamRiskReview`, `fetchAuthorityOverview`) and
  `aiVisibilityService.ts` (`fetchPromptTrackingRecords`,
  `updateAiVisibilityItemStatus`, `fetchBrandMentionSummary`,
  `fetchCompetitorMentionSummary`, `fetchAiContentGaps`,
  `fetchAiVisibilityOverview`) move behind `runWithServiceAdapter`, keeping mock
  as default + fallback.
- **Derived summaries:** `AuthorityOverview` / `AiVisibilityOverview` /
  `BrandMentionSummary` / `CompetitorMentionSummary` / `SpamRiskReview` stay
  service-layer aggregations; **`BrandMentionSummary` / `CompetitorMentionSummary`
  read `seo_ai_mentions`** (D2) rather than recomputing from prompt arrays.
- **`opportunity_ids` mapping (D1):** the service maps `seo_authority_campaign_opportunities`
  junction rows back into the `opportunity_ids: string[]` the UI's
  `AuthorityCampaign` expects — no UI/type change.
- **`progress_percentage` computed on read (D6):** the service derives it from
  `seo_authority_campaign_tasks` (`complete / total`) and populates the frontend
  `AuthorityCampaign.progress_percentage` field; it is not a stored column.
- **Status writes go through the transition RPCs (D5):** `updateAuthorityOpportunityStatus`
  and the campaign approval actions call `seo_authority_opportunity_transition` /
  `seo_authority_campaign_transition` (via `supabase.rpc`), never a direct status
  UPDATE — mirroring how `approvalService`/`contentStudioService` (Phases 13D/13E)
  route status writes through their Stage 2/3 transition RPCs.
- **Cross-workspace fallback + onboarding-gate:** the Off-Page and AI Visibility
  pages should reuse the Phase 14A/14B page-local `displayWebsite` fallback +
  ranked finder pattern (highest-data-count wins) if they show a single active
  website — noted for the wiring phase.
- **Optional approval-queue integration:** a later enhancement could route
  `requires_approval` opportunities / `pending_approval` campaigns into the
  Stage 2 `seo_approval_items` flow instead of a standalone status.

---

## 14. Open questions — RESOLVED (kept for traceability)

All seven original open questions are now **resolved and locked in §0**. Retained
here as a record of what was decided:

1. **Campaign ↔ opportunity: junction vs array?** → **Junction** (`seo_authority_campaign_opportunities`), source of truth; no `opportunity_ids[]`. (D1)
2. **`seo_ai_mentions`: adopt or defer?** → **Adopt** as normalized rows (brand/competitor/citation-source). (D2)
3. **Narrow client write?** → **No** — clients read-only in Stage 6 v1; any future narrow write is a later explicit phase. (D3)
4. **Prompt tracking: single-row or time-series?** → **Time-series** (`observed_on date`); no `prompt_text` uniqueness. (D4)
5. **Transition RPC?** → **Yes for Off-Page** (`seo_authority_opportunity_transition`, `seo_authority_campaign_transition`, guarded + activity-logging via `seo_authority_activity`); AI Visibility stays plain-RLS-written. (D5 / D5a)
6. **`progress_percentage`: stored or derived?** → **Derived** from tasks in the service layer; not stored. (D6)
7. **Soft-dup guard on opportunities?** → **Soft, active-only** partial unique on `(website_id, opportunity_type, lower(target_url))` where `target_url` present and status active; terminal/URL-less never blocked; never by title. (D7)

**No open questions remain before SQL authoring.** These decisions are locked
unless a future review explicitly changes them.

---

## 15. What is NOT in Stage 6

- **No migration SQL** (this is plan-only), no seed, no service wiring, no UI
  changes — all later phases.
- **No real backlink/review/outreach automation; no LLM/scraper/external API; no
  cron.** Observed/manual/imported data only.
- **No Competitor / Roadmap / Support / Reports backend** — those are later
  stages in the rollout order, after Off-Page / AI Visibility.
- **No admin-panel tables** (`seo_admin_notes`, `seo_prompt_library`, etc. from
  the architecture plan's admin section) — a separate later stage.
- **No production apply** — Stage 6, once built, targets the TEST project only.

---

## 16. Production gating reminder

⚠️ **Plan only — nothing to apply.** When Stage 6 SQL is eventually written and
applied, it goes to a **disposable TEST project first** and is gated for
production exactly as Stages 1–5: target-project confirmation, backup/branch
strategy, final migration review, and technical-owner sign-off
(`BACKEND_MILESTONE_HANDOFF.md` §5). Stage 6 is **not implemented, not applied,
not verified.**
