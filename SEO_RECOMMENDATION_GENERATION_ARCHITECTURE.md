# Recommendation Generation Architecture — From Real Crawler Issues to Persisted SEO Recommendations

> ## ⚠ DOCUMENT CLASSIFICATION: HISTORICAL DESIGN RECORD — NOT CURRENT IMPLEMENTATION AUTHORITY
>
> **Status (2026-09-19):** this is the *pre-implementation* architecture design,
> written 2026-07-24 and preserved for traceability. **The feature it designs is
> now implemented:** Recommendation Generation **Stage 1** (backend — migration
> `20260724130000_seo_recommendation_generate.sql`) and **Stage 2** (frontend
> integration) are both **complete, accepted and MODULE-LOCKED**, and are in
> canonical `main` (`9cb3676`). It was verified **locally** (real Docker-based
> local Supabase stack). **TEST history:** the migration was applied to `Digi_SEO_Test` out of
> sequence on 2026-07-24 and fully rolled back the same day, then
> **promoted, recorded and verified on TEST on 2026-09-19** (`SEO_IMPLEMENTATION_STATUS.md` §5). Nothing has been applied to production; no SEO
> production project exists.
>
> **The canonical implementation differs from this design — do not read this
> document as a description of the shipped behaviour.** Known, recorded
> divergences:
> 1. **RPC return type.** The design (§4) specifies `RETURNS integer` (a count).
>    The implemented RPC returns **`SETOF public.seo_recommendations`** — the
>    canonical current recommendation set, ordered `area, created_at, id`.
> 2. **No-completed-audit behaviour.** The design (§4.3) says the RPC "returns 0
>    without error" when no completed run exists. The implementation always
>    generates the 7 on-page templates (they need only website/business-context
>    fields) and only the issue-derived half of the set is empty.
>
> **Where current truth lives:** the migration file itself;
> `SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md` (§3 records divergence 2)
> and `SEO_RECOMMENDATION_GENERATION_STAGE2_VERIFICATION.md`; `SEO_DECISIONS.md`
> A17/A18; the two Recommendation Generation entries in
> `docs/markdown/MODULE_LOCKS.md`; and `SEO_CONTEXT_HANDOVER.md` §0. Status-bearing
> phrases inside this document ("Design-only", "unaccepted", "not implemented",
> "Verified against `main` `71ac8fd…`") describe the moment of writing and are
> intentionally left as history. Classification: `docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`.

**Role:** the complete architecture design for closing the single
highest-impact gap identified in `SEO_RELEASE_ROADMAP.md` §4.1 — real,
crawler-detected `seo_audit_issues` never populate `seo_recommendations` in
Supabase mode. **Design-only.** No code, migration, or configuration was
written or applied while producing this document.

**Created:** 2026-07-24. **Verified against `main` commit:**
`71ac8fd0fd6087bb5435bea4cca865025bc27967`, and against the working tree at
`feat/seo-competitor-generate-stage2a` (`a594d1dbd0f67f71b218132b848ce9678c3cad17`)
— the two do not differ in any file this design touches.

**Method:** every schema fact, RPC contract, RLS rule, and mock heuristic
below was read directly from the repository during this task, not assumed
from prior conversation memory or documentation summaries. File paths and
line-level facts are cited throughout so the design can be checked against
the source at any time.

---

## 0. The Critical Finding This Design Is Built On

**The recommendation → approval-item pipeline already exists, is already
wired, and already works correctly.** Verified directly:

- `src/pages/seo/ApprovalQueuePage.tsx:55` calls
  `ensureApprovalQueueGenerated(activeWebsite!, recommendations, issues)`.
- `src/services/approvalService.ts:45-55` dispatches that call through
  `runWithServiceAdapter` to `ensureSupabaseApprovalQueueGenerated` in
  Supabase mode.
- `src/services/supabase/seoApprovalSupabaseService.ts:172-224`
  (`ensureSupabaseApprovalQueueGenerated`) is a **complete, already-correct,
  idempotent** implementation: it reads existing `seo_approval_items` for the
  website, filters the passed-in `recommendations` array down to ones
  without an approval item yet, and inserts the rest via
  `.upsert(payload, { onConflict: "recommendation_id", ignoreDuplicates: true })`
  — safe to call on every page load. `is_high_risk_category` is deliberately
  omitted from the insert payload because the existing
  `trg_seo_approval_items_hrc` trigger (migration `20260711120006`, reusing
  `seo_set_hrc_from_issue()` from migration `20260711120005`) derives it
  non-forgeably server-side.
- `public.seo_approval_transition` (migration `20260711120006`) is a
  complete, locked-adjacent, unmodified RPC that already handles the entire
  approve/reject/expert-review/developer-needed/completed/comment lifecycle,
  the full owner/admin/team_member/client risk-gated permission matrix, and
  append-only activity logging.

**Consequence for this design:** `recommendations` in the call above comes
from `fetchRecommendations`/`fetchOnPageRecommendations`
(`src/services/recommendationService.ts:16-30`), which in Supabase mode read
real `seo_recommendations` rows via `fetchSupabaseRecommendations`. Today
that query always returns `[]` — not because the pipe is broken, but because
**nothing ever writes a real row**. This design adds exactly one missing
piece — a guarded generation RPC that populates `seo_recommendations` — and
the entire downstream chain (approval-item creation → transition workflow →
Roadmap's `fetchOnPageRecommendations` consumption) starts working
automatically, unmodified. No other file in the approval or roadmap chain
needs to change.

---

## 1. Current Schema (verified from migrations)

### 1.1 `seo_audit_issues` (source data) — migrations `20260711120004`, `20260714120029`

Base columns (`20260711120004`): `id, workspace_id, website_id, website_url,
audit_run_id, category, severity, title, simple_explanation, why_it_matters,
technical_explanation, affected_page_url, impact, effort, risk,
confidence_percentage, fix_owner, suggested_next_action,
is_high_risk_category, status`.

- `category` — 11 values: `crawl, indexability, speed, mobile, schema,
  duplicate_content, broken_links, sitemap, robots_txt, canonical, redirects`.
- `fix_owner` — 4 values: `client_action, developer_needed, digibility_expert,
  system_suggestion`.
- `status` — `open, in_review, approved, fixed, ignored`.
- `is_high_risk_category` is trigger-derived (non-forgeable) from `category`
  via `seo_is_high_risk_category()` — true for `robots_txt, canonical,
  redirects, sitemap, indexability`.

Provenance columns added additively by the **locked** Crawler 16C–16H scope
(`20260714120029`): `source` (`'crawler'` or NULL for legacy/manual),
`crawl_job_id`, **`source_issue_fingerprint`** (format `'<ISSUE_CODE>::<crawler
fingerprint>'`, unique per `(audit_run_id, source_issue_fingerprint)` — a new
row every audit run, even for a recurring problem), `source_rule_version`,
`issue_scope`, `source_category`, `source_severity`.

**Verified, non-obvious fact:** `seo_crawl_worker_publish_results`
(`20260714120029` lines 403-438) upserts issues per audit run and its
`UPDATE SET` list **does not include `status`** — a re-publish never resets
an issue a human already marked `fixed`/`ignored`. **This design follows the
same discipline for recommendations (§4).**

**Verified, non-obvious fact:** `seo_audit_issues` has no `issue_code`
column — only the compound `source_issue_fingerprint`. This design does
**not** add one (§3.3 explains why).

### 1.2 `seo_recommendations` (target table) — migration `20260711120005`

Columns: `id, workspace_id, website_id, website_url, audit_run_id, issue_id,
area, title, current_value, suggested_change, why_it_helps, action_type,
impact, effort, risk, confidence_percentage, is_high_risk_category, status,
is_current, superseded_by, created_by, created_at, updated_at`.

- `area` — 8 values: `title, meta_description, h1, faq, schema,
  internal_links, content, technical`.
- `action_type` — 5 values: `auto_suggest, approval_required, manual_support,
  expert_review, avoid`.
- `status` — 8 values, identical set to `seo_approval_items.status`:
  `suggested, needs_review, approved, rejected, expert_review_requested,
  developer_needed, ready_to_publish, completed`.
- `is_current` / `superseded_by` — an **already-designed versioning scheme**,
  currently only exercised by the manual `seo_supersede_recommendation(old,
  new)` RPC (never called by any frontend code today, confirmed by
  repo-wide search). **This design is the first real consumer of this
  scheme** (§4).
- `is_high_risk_category` is trigger-derived from the linked `issue_id` via
  the same `seo_set_hrc_from_issue()` used by `seo_approval_items` — reused
  unchanged.
- RLS (`seo_recommendations_select`/`_write`): read = any member; write =
  owner/admin/team_member or global admin. **Client cannot write — matches
  this design's role gate exactly, no RLS change needed.**

### 1.3 `seo_approval_items` (downstream, unmodified) — migration `20260711120006`

One row per recommendation (`UNIQUE recommendation_id`), created by the
already-working `ensureApprovalQueueGenerated` flow (§0). Nothing in this
design touches this table's schema, RLS, or the `seo_approval_transition`
RPC.

---

## 2. The Existing Mock Heuristic (the rule set this design formalizes server-side)

Read directly from `src/mocks/recommendationMockData.ts` and
`src/services/recommendationService.ts`. This is the **exact, already-agreed
product rule** — this design does not invent new rules, it reproduces this
one deterministically server-side, following the same precedent established
by Reports Stage 2 (`seo_report_generate` reproducing the mock's aggregation
rules) and Competitor Stage 2A (`seo_competitor_generate` reproducing
`hashStringToRange`).

### 2.1 Issue-derived recommendations (`recommendationsFromIssues`, lines 114-137)

One recommendation per issue, 1:1, entirely mechanical:

| Recommendation field | Source |
|---|---|
| `area` | `CATEGORY_TO_AREA[issue.category]` — 11→8 static map: `schema→schema`, `duplicate_content→content`, every other category → `technical` |
| `title` | `issue.title` (verbatim) |
| `suggested_change` | `issue.suggested_next_action` (verbatim) |
| `why_it_helps` | `issue.why_it_matters` (verbatim) |
| `action_type` | `ACTION_TYPE_BY_FIX_OWNER[issue.fix_owner]` — `client_action→manual_support`, `developer_needed→approval_required`, `digibility_expert→expert_review`, `system_suggestion→auto_suggest` |
| `impact`, `effort`, `risk`, `confidence_percentage` | copied verbatim from the issue |
| `issue_id` | the issue's own id |
| `status` | `suggested` (initial) |

**Verified downstream safety property:** every crawler-published issue today
has `fix_owner='system_suggestion'` uniformly (hardcoded in
`seo_crawl_worker_publish_results`'s INSERT), so every crawler-derived
recommendation would get `action_type='auto_suggest'` uniformly. This is
**not** a safety gap: `seo_approval_transition`'s role gate (migration
`20260711120006` lines 174-176) keys its client/team_member thresholds off
`risk` and `is_high_risk_category` — both of which the crawler **already**
derives correctly per issue (`risk='high'` for the 5 dangerous categories,
`'low'` otherwise) — not off `action_type` alone. A high-risk crawler issue
labeled `auto_suggest` still correctly requires owner/admin (or expert
review) downstream, because `v_dangerous := (v_risk = 'high') OR v_hrc`
overrides the action-type-derived self-serve threshold. **This design relies
on this already-correct interaction rather than re-deriving `action_type`
per issue code.**

### 2.2 On-page recommendations (`ON_PAGE_TEMPLATES`, lines 152-265)

7 fixed templates (`title, meta_description, h1, faq, schema,
internal_links, content`), **not** derived from any issue — personalized
only by `website.business_name` / `website.industry` / `website.target_location`
via simple string interpolation. Always regenerated in full alongside the
issue-derived set (`regenerateRecommendationsForWebsite`, lines 269-279).

### 2.3 What the mock does that this design deliberately does NOT copy

`regenerateRecommendationsForWebsite` **wipes every existing recommendation
for the website and replaces it wholesale** on every call. That is safe in
mock mode (no real approval history exists to lose) and would be **unsafe**
in Supabase mode: `seo_approval_items.recommendation_id` has `ON DELETE
CASCADE` — deleting a recommendation a client already approved would
silently destroy that approval's audit trail (`seo_approval_comments`,
`seo_approval_activity`). §4 replaces this with a history-preserving
replace-to-match.

---

## 3. Database Model (additive)

### 3.1 New columns on `seo_recommendations` (additive, nullable)

```
source_issue_fingerprint  text          -- copied from the linked issue at generation time; NULL for on-page recs
generation_method         text          -- e.g. 'rule_based_v1'; optional, mirrors Competitor Stage 2A's provenance discipline
```

No new column is added to `seo_audit_issues` — see §3.3.

### 3.2 New partial unique indexes (the dedup keys — §5)

```sql
-- Issue-derived: at most one CURRENT recommendation per stable issue identity.
CREATE UNIQUE INDEX ... ON seo_recommendations (website_id, source_issue_fingerprint)
  WHERE is_current AND source_issue_fingerprint IS NOT NULL;

-- On-page: at most one CURRENT recommendation per area per website
-- (distinguished from issue-derived rows, which always carry an issue_id).
CREATE UNIQUE INDEX ... ON seo_recommendations (website_id, area)
  WHERE is_current AND issue_id IS NULL;
```

These mirror the exact pattern already established by Competitor
Benchmarking's `UNIQUE(website_id, normalized_competitor_url)` — a stable
identity key plus a partial index scoped to the "live" rows only (`is_current`
here plays the same role `is_current`-equivalent filtering would in a
simpler table; Competitor Benchmarking has no versioning concept at all,
which is exactly why its uniqueness constraint could be simpler — this
table's constraint is necessarily partial because superseded/retired rows
must be allowed to keep the same identity as their replacement).

### 3.3 Why no new `issue_code` column, and no new reference table

The mock's `CATEGORY_TO_AREA` (11 entries) and `ACTION_TYPE_BY_FIX_OWNER` (4
entries) both operate on columns **already present and already correctly
populated** on every `seo_audit_issues` row (`category`, `fix_owner`) —
including crawler-published ones. A per-issue-code (29-value) mapping table
akin to `seo_crawl_issue_audit_map` is **not needed**, because the existing
category/fix_owner-level mapping is both (a) exactly what the already-agreed
mock does today and (b) sufficient, per the safety analysis in §2.1. This
keeps the new migration self-contained — it does not read, write, or extend
any table owned by the **locked** Crawler 16C–16H scope, and does not
require the crawler's additive-extension procedure at all.

The dedup key (§3.2) instead reuses `source_issue_fingerprint`, which
**already exists** on `seo_audit_issues` (added by the locked Phase 16G
migration) — this design only *reads* it, copying the value onto the new
recommendation row at generation time. Reading a locked table's existing
column is not a change to the locked scope.

---

## 4. Generation Rules (the guarded RPC's logic, described — not implemented)

**`public.seo_recommendation_generate(p_website_id uuid) RETURNS integer`**
— returns the count of current recommendations after generation, mirroring
`seo_competitor_generate`'s minimal return-shape precedent.

> **[2026-09-19 note — implementation differs]** The shipped RPC is
> `public.seo_recommendation_generate(p_website_id uuid) RETURNS SETOF
> public.seo_recommendations` (the canonical current set), not `RETURNS integer`.
> See the banner at the top of this document.

**Contract**, following the Reports Stage 2 / Competitor Stage 2A precedent
exactly: `SECURITY DEFINER`, `SET search_path = public`, `authenticated`
EXECUTE granted, **`anon` and `PUBLIC` revoked in the same migration** (no
corrective follow-up, matching Competitor Stage 2A's improvement over
Reports Stage 2's two-migration anon-revoke). Accepts **only**
`p_website_id` — no client-supplied recommendation content, scores,
timestamps, or actor.

### 4.1 Authorization (server-derived, no client input trusted)

1. `auth.uid()` must be non-null.
2. Resolve `workspace_id`/`website_url` from `seo_websites` by
   `p_website_id`.
3. Authorize `owner`/`admin`/`team_member` via `seo_role_in(...)` or
   `seo_is_global_admin()` — **client denied**, matching the existing
   `seo_recommendations_write` and `seo_approval_items_insert` RLS policies
   (this RPC's authorization intentionally mirrors, not weakens, what direct
   RLS already allows for these tables).
4. A missing website and a role failure raise the **same** non-leaking
   message (established pattern from every prior guarded RPC in this repo).

### 4.2 Concurrency

`PERFORM pg_advisory_xact_lock(hashtextextended(p_website_id::text ||
':recommendation_generate', 0));` — transaction-scoped, serializes
concurrent Generate calls for the same website, identical mechanism to
Reports Stage 2 and Competitor Stage 2A (both independently proven with a
live two-session lock-wait).

### 4.3 Source selection

```
latest completed audit run :=
  SELECT id, ... FROM seo_audit_runs
  WHERE website_id = p_website_id AND status = 'completed'
  ORDER BY COALESCE(completed_at, started_at) DESC LIMIT 1
```

Identical selection rule to `seo_report_generate`'s audit selection — reused
for consistency, not reinvented. If no completed run exists, the RPC returns
`0` without error (mirrors Competitor Stage 2A's non-destructive
empty-input behavior — an audit-less website is not an error state).

**Refinement beyond the mock (a real-data safety improvement):** only issues
with `status IN ('open', 'in_review')` from that run are candidates for
generation — an issue a human already marked `fixed`/`ignored` should not
spawn a fresh "please fix this" recommendation. The mock has no equivalent
concern (it always operates on a freshly-generated, always-`open` issue
batch).

### 4.4 The three-way replace-to-match (the core of this design)

For the **desired set** (every open/in-review issue from the selected run,
mapped per §2.1, plus the 7 on-page templates from §2.2), each item has a
stable identity key from §3.2. For each desired item:

1. **No current recommendation exists with this identity** → `INSERT` a new
   row, `status='suggested'`, `is_current=true`.
2. **A current recommendation exists with this identity, content
   unchanged** (same `title`, `suggested_change`, `impact`, `risk`,
   `action_type`) → **no write at all**. This is the common case on a
   routine re-crawl where nothing changed — it leaves `updated_at`,
   `status`, and every downstream approval record completely untouched.
3. **A current recommendation exists with this identity, content changed,
   and its `status` is still `suggested` or `needs_review`** (nobody has
   acted on it yet) → supersede: `UPDATE ... SET is_current=false,
   superseded_by=<new id>` on the old row (reusing the exact mechanic
   `seo_supersede_recommendation` already implements, inlined into this
   RPC's transaction rather than called as a separate statement), then
   `INSERT` the new row as in case 1.
4. **A current recommendation exists with this identity, content changed,
   but its `status` has moved to a human-decided terminal-ish state**
   (`approved`, `rejected`, `expert_review_requested`, `developer_needed`,
   `completed`) → **do nothing**. A human has already acted on this item;
   regeneration must never silently supersede a decision in progress. The
   next regeneration after that item eventually reaches `completed` (or is
   otherwise resolved through the approval workflow) is free to supersede it
   then, under case 3.

For **issue-derived recommendations no longer in the desired set** (the
underlying issue was resolved — status changed, or a re-crawl no longer
finds it) whose current `status` is still `suggested`/`needs_review`: mark
`is_current=false` (with `superseded_by` left `NULL` — the schema already
supports this: "retired, not replaced by anything" is a valid, existing
state per `superseded_by`'s nullable FK). **Same terminal-state exception as
case 4** — a recommendation already approved/in-review/completed is never
auto-retired just because its source issue later disappeared; that is a
human decision to close out via the approval workflow, not a side effect of
the next crawl.

On-page recommendations are **never** auto-retired by this rule (they have
no external issue that can "resolve" independently) — only ever inserted
(case 1) or superseded (case 3) if the interpolated content changes because
a business-context field changed.

### 4.5 Truthfulness / provenance

Every generated row is a deterministic transformation of either (a) a real,
crawler-verified `seo_audit_issues` row, or (b) a static, business-context
template — never an AI/LLM inference, never fabricated data. This design
recommends (not requires) setting `generation_method='rule_based_v1'`
(§3.1) to leave an explicit, non-breaking seam for a future LLM-based
generation method — consistent with how Competitor Benchmarking's
`generation_method='heuristic_v1'` and `data_provenance='estimated'` leave
room for a future real-provider integration without relabeling existing
data.

---

## 5. Deduplication (summary — full mechanics in §4.4/§3.2)

Two independent stable keys, each enforced by a partial unique index scoped
to `is_current` rows only:

- **Issue-derived:** `(website_id, source_issue_fingerprint)` — survives
  across audit runs (the fingerprint encodes the issue code + page identity,
  not the audit-run id), so a recurring problem across repeated crawls
  reuses the same recommendation identity instead of accumulating
  duplicates.
- **On-page:** `(website_id, area)` — exactly one current on-page
  recommendation per area, matching the fixed 7-template catalog.

Because both indexes are `WHERE is_current`, a superseded/retired row
(`is_current=false`) never conflicts with its own replacement — the same
"replace-to-match with history preserved" mechanic Competitor Stage 2A
proved live under true two-session concurrency, extended here with the
additional versioning dimension `seo_recommendations` already has and
Competitor Benchmarking does not.

---

## 6. Update Strategy (summary — full mechanics in §4.4)

| Scenario | Result |
|---|---|
| Re-generate with no real-world change | Zero writes; nothing touched |
| Issue's mapped content changed, recommendation still `suggested`/`needs_review` | Old row superseded (`is_current=false`), new row inserted `suggested` |
| Issue's mapped content changed, recommendation already acted on | Left untouched — human decision is never overwritten |
| Issue resolved externally, recommendation still `suggested`/`needs_review` | Recommendation retired (`is_current=false`, `superseded_by=NULL`) |
| Issue resolved externally, recommendation already acted on | Left untouched |
| New issue appears | New recommendation inserted `suggested` |
| On-page template content changed (rare — business field edited) | Same supersede/leave-alone rule as issues |

---

## 7. Approval Lifecycle (unchanged — confirmed compatible, not modified)

This design produces `seo_recommendations` rows with `status='suggested'`.
Everything from that point on is the **existing, unmodified** Stage 2
approval workflow:

1. `ApprovalQueuePage` calls the already-working `ensureApprovalQueueGenerated`
   (§0), which creates one `seo_approval_items` row per current
   recommendation that doesn't have one yet — including newly-generated
   ones on the very next page load, with zero new code.
2. `seo_approval_transition` (unmodified) drives `suggested → {approved,
   rejected, expert_review_requested, developer_needed, completed}` with
   its existing, already-verified owner/admin/team_member/client role and
   risk matrix — `is_high_risk_category` on the approval item is still
   derived from the same linked `issue_id`, unaffected by this design.
3. `seo_approval_transition` already mirrors status changes back onto
   `seo_recommendations.status` (migration `20260711120006` lines 231-233)
   — meaning once approved/rejected/completed, the recommendation and its
   approval item stay in lockstep automatically, with no new code required.

**No change to the approval lifecycle is proposed or needed.** This is a
generation-side design only.

---

## 8. Downstream Integrations (verified, not modified)

| Consumer | File | Verified behavior |
|---|---|---|
| Approval Queue | `seoApprovalSupabaseService.ts` (§0) | Already creates approval items from any current recommendation; works unmodified once real rows exist |
| Roadmap (Month 2) | `roadmapService.ts:138` (`fetchOnPageRecommendations`) | Already calls the real service in Supabase mode; will read real on-page recommendations once they exist. **Note (carried from `SEO_RELEASE_ROADMAP.md` §4.2, unaffected by this design):** Roadmap's own generated output still only persists to the mock store — that gap is separate and not addressed here. |
| Dashboard | `seoDashboardSupabaseService.ts` | Not verified in this task — **UNKNOWN** whether it reads recommendation/approval counts; if it does, it will pick up real data automatically since it already reads real `seo_approval_items`/`seo_recommendations` via RLS the same way every other consumer does. Should be spot-checked during implementation, not assumed. |
| Content Studio | `contentStudioService.ts:110` | A code comment references `ensureApprovalQueueGenerated` in passing; Content Studio has its own separate `seo_content_opportunities` domain and was **not** found to consume `seo_recommendations` directly. No integration assumed here beyond what's verified. |
| Page Optimizer | reads `fetchOnPageRecommendations` (same function as Roadmap) | Same as Roadmap row — starts showing real data automatically |

---

## 9. Role Gating (frontend — usability layer only, mirrors Competitor Stage 2B exactly)

- New `canGenerateRecommendations(role, supabaseMode)` +
  `RECOMMENDATION_GENERATE_ROLES = ['owner','admin','team_member']`,
  identical shape to `canGenerateCompetitorBenchmarks`/
  `COMPETITOR_GENERATE_ROLES` (`src/services/competitorService.ts`).
- A new "Generate Recommendations" (or "Refresh Recommendations") control on
  `WebsiteAuditPage.tsx`, shown when `resultAudit?.status === 'completed'`
  in Supabase mode. **Verified safe to add:** `MODULE_LOCKS.md`'s Crawler
  16C–16H entry locks only "the `<CrawlPanel>` integration in
  `src/pages/seo/WebsiteAuditPage.tsx`" — not the whole file. This control
  is a separate, additive UI element outside that integration point.
- Client sees the control disabled with the established "Requires the
  owner, admin, or team member role." tooltip (same wording used by every
  prior role-gated control in this repo).
- Backend RPC remains the sole authoritative check, exactly as designed in
  §4.1 — the frontend gate is presentation-only.

---

## 10. Implementation Plan (steps only — no code)

Follows the exact phased pattern already proven twice (Competitor Stage
2A→2B), adapted for this feature:

1. **Author one additive migration**: the two new nullable columns + two
   partial unique indexes on `seo_recommendations` (§3.1–3.2), plus the new
   `seo_recommendation_generate(uuid)` RPC (§4) with grants folded in
   (`authenticated` EXECUTE, `anon`+`PUBLIC` revoked, no corrective
   follow-up).
2. **Author a self-cleaning SQL verification script** (TEST-only, matching
   the established `supabase/test/*.sql` shape) covering at minimum: contract
   (SECURITY DEFINER, search_path, grants, advisory lock present);
   owner/admin/team_member allowed, client/anon/non-member/cross-tenant
   denied with no-leak; correct area/action_type mapping for a
   representative issue of each category/fix_owner combination; on-page
   template generation; the full §4.4 update-strategy matrix (no-op on
   unchanged regen, supersede on changed-but-untouched, leave-alone on
   changed-but-acted-on, retire on resolved-but-untouched, leave-alone on
   resolved-but-acted-on); the two dedup unique indexes actually preventing
   duplicates under regeneration; zero fixture residue.
3. **Apply in isolation to `Digi_SEO_Test`** via `supabase db query --linked
   -f`, then record via `supabase migration repair --status applied` —
   identical procedure to every prior migration in this repo, keeping the
   still-pending SSO migration `20260720121000` untouched.
4. **Live two-session concurrency proof** (same method as
   `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`) — since this RPC
   introduces a new advisory-lock key, it warrants its own proof rather than
   assuming the pattern transfers.
5. **Frontend wiring**: a new `generateSupabaseRecommendations` function in
   `seoRecommendationSupabaseService.ts` calling the RPC then re-reading via
   the existing `fetchSupabaseRecommendations`; `recommendationService.ts`'s
   `generateRecommendationsFromAudit` gains a real Supabase branch dispatched
   through `runWithServiceAdapter` (`fallbackToMockOnError: false`), mock
   branch preserved verbatim; the new role-gate helper (§9); the new UI
   control on `WebsiteAuditPage.tsx`.
6. **Unit tests**, mirroring the Competitor Stage 2B pattern: exact RPC
   args, response validation, no-fallback-on-error, canonical
   read-back-after-generation, mock-mode-unchanged, and the role-gating pure
   function's full role matrix.
7. **Authenticated operator acceptance** against `Digi_SEO_Test`: the full
   4-role matrix (owner/admin/team_member generate successfully; client
   denied in UI and at the RPC), plus a **regeneration-safety scenario**
   specific to this feature — approve a recommendation, then trigger a
   re-crawl that changes the underlying issue, and verify the approved
   item's status and approval history are untouched while a new,
   separately-approvable recommendation appears alongside it.
8. **Documentation + lock decision**: update the authoritative status docs
   with the same evidence discipline used throughout this repo; a formal
   `MODULE_LOCKS.md` entry (or an amendment folding this into a future
   formal "Technical Audit + Recommendations" entry, per
   `SEO_RELEASE_ROADMAP.md` §6) is a **separate, explicitly-approved**
   decision, not automatic.

---

## 11. Verification Against the Current Repository (summary)

Every fact this design depends on was confirmed by direct inspection during
this task, not assumed:

- ✅ `seo_recommendations`, `seo_audit_issues`, `seo_approval_items` schemas
  read in full from their migration files.
- ✅ The mock heuristic (`CATEGORY_TO_AREA`, `ACTION_TYPE_BY_FIX_OWNER`,
  `ON_PAGE_TEMPLATES`) read in full from source, not paraphrased from memory.
- ✅ `ensureApprovalQueueGenerated`/`ensureSupabaseApprovalQueueGenerated`
  confirmed to already exist, already be wired into `ApprovalQueuePage.tsx`,
  and already be correct/idempotent — the single most important finding
  this design rests on.
- ✅ `seo_approval_transition`'s exact role/risk gating logic read in full,
  confirming this design's authorization choices are consistent with it
  rather than assumed compatible.
- ✅ `seo_crawl_worker_publish_results`'s exact upsert behavior read in full,
  confirming the "never overwrite a human-set status" precedent this design
  extends to recommendations.
- ✅ `WebsiteAuditPage.tsx` read in full, confirming exactly where
  `generateRecommendationsFromAudit` is (and is not) currently called, and
  confirming the Crawler 16C–16H lock covers only the `<CrawlPanel>`
  integration point within that file, not the whole file.
- ✅ Confirmed no `issue_code` column and no existing per-code-to-recommendation
  mapping table exist anywhere — this design's choice not to add one is
  deliberate (§3.3), not an oversight.
- ⚠️ Dashboard's consumption of recommendation/approval data (§8) was
  **not** verified in this task — marked explicitly as unconfirmed rather
  than assumed.

**No code, migration, or configuration file was changed to produce this
document.**

---

## Appendix: Files read to produce this design

`supabase/migrations/20260711120004_seo_stage2_audit.sql`,
`20260711120005_seo_stage2_recommendations.sql`,
`20260711120006_seo_stage2_approval.sql`,
`20260714120029_seo_phase16g_publishing.sql`;
`src/mocks/recommendationMockData.ts`; `src/services/recommendationService.ts`,
`src/services/approvalService.ts`,
`src/services/supabase/seoRecommendationSupabaseService.ts`,
`src/services/supabase/seoApprovalSupabaseService.ts`;
`src/pages/seo/WebsiteAuditPage.tsx`; `src/types/recommendation.ts`,
`src/types/common.ts`, `src/types/audit.ts`; `docs/markdown/MODULE_LOCKS.md`
(Crawler 16C–16H entry, for the locked-files boundary check); a repo-wide
search confirming `seo_supersede_recommendation` and
`ensureApprovalQueueGenerated`/`ensureSupabaseApprovalQueueGenerated` call
sites.
