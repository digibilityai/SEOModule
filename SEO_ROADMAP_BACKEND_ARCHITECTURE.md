# Roadmap Backend Architecture — From Real Module Findings to a Persisted 90-Day Plan

> ## ⛔ DESIGN ONLY — NOT IMPLEMENTED
>
> **Status (2026-09-19):** this is the Roadmap Backend design document and the
> *only* Roadmap Backend artefact that exists. **Nothing in it has been built.**
> The repository (`main` at `9cb3676`, plus documentation-only commits) contains
> **no** Roadmap migration, **no** Roadmap table (of any shape), **no** Roadmap
> generation RPC, and **no** Supabase Roadmap service. The existing `/seo/roadmap`
> page and `src/services/roadmapService.ts` are **mock-backed UI/service only**
> in every data mode (no `runWithServiceAdapter`, no Supabase call). The locked
> `seo_report_generate` RPC still reports `roadmap` as `unavailable`. Roadmap
> Backend implementation has **not been started**; it requires a separate,
> explicitly-approved task.
>
> ### ✅ Approved architecture (2026-09-19): `plans → periods → items`
>
> The operator has approved a **three-level** Roadmap Backend architecture:
> a **plan** contains **periods**, and a **period** contains **items**.
> **This supersedes the earlier flat single-table design** (`seo_roadmap_items`
> plus `seo_roadmap_generate … RETURNS SETOF seo_roadmap_items`) that §3–§7 and
> §10 of this document describe. Those sections are kept **only as historical
> reference for the product behaviour and rules they analyse**; they are **not**
> the design to implement — see the amendment section directly below for exactly
> what carries over, what is superseded, and what is TBD.
>
> The three-level design's own detailed document is **not among the surviving
> repository files**. Nothing beyond the hierarchy itself has been reconstructed
> or invented here: every detail not supported by surviving evidence or an
> existing approved decision is marked **TBD**. Nothing was reconstructed from any
> earlier, lost worktree.
>
> **Dependency status:** the on-page-recommendation source (§4.3) is now real —
> Recommendation Generation Stages 1–2 are locked and on `main` — but that RPC's
> migration was promoted and verified on `Digi_SEO_Test` on 2026-09-19 (backend only), so on TEST
> that source is populated once the RPC has been run for a website. Current project state: `SEO_CONTEXT_HANDOVER.md` §0; decision record
> `SEO_DECISIONS.md` A19; classification in
> `docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`.
>
> **Earlier reconciliation notes (2026-09-19, facts only):** §0.1 said "five
> exported functions" while listing seven — corrected to seven (matches
> `roadmapService.ts`); "five of its six upstream fetches" clarified to five of six
> upstream *sources*; the `src/services/supabase/` file count and the
> Recommendation Generation dependency status (§4.3) were updated. The
> "Verified against … `a594d1d` / `71ac8fd`" header is the 2026-07-24 record and is
> preserved.

---

## Approved architecture amendment (2026-09-19): plans → periods → items

### A.1 The decision

The Roadmap Backend architecture to be built is **`plans → periods → items`**.
It replaces the flat single-table model of the original design. Roadmap Backend
remains **DESIGN ONLY — NOT IMPLEMENTED**: no migration, RPC, table or service
has been created and none is authorised by this amendment.

### A.2 How to read the rest of this document

| Section | Status under the approved model |
|---|---|
| §0, §0.1 — current-state findings | **Still valid** (facts about the repository; §0.1's "no adapter dispatch" finding is the starting point for any backend). |
| §1 — sources, real-table columns, field translations, RLS/role convention | **Still valid.** |
| §2 — the existing mock heuristic | **Still valid** as the product behaviour to be formalised server-side. |
| §3 — database model (`seo_roadmap_items`, its RLS, the `manual_strategy` note) | **SUPERSEDED.** Flat single-table model; do not implement. The RLS *convention* in §1.4 stands; per-table policies must be re-derived for the three-level model (TBD). |
| §4.2 authorization, §4.3 source selection, §4.5 truthfulness/provenance | **Still valid** as rules/principles. |
| §4 intro, §4.1 contract, §4.4 replace-to-match, §5, §6, §7 | **SUPERSEDED as written** (they are keyed to a flat `seo_roadmap_items` row, its `source_fingerprint`, `is_current` and `superseded_by`). Their *intent* is retained as product requirements (see A.4); its expression on the three-level model is **TBD**. |
| §8 downstream integrations, §9 role gating | **Still valid** as behaviour; the concrete service surface is TBD. |
| §10 implementation plan | **SUPERSEDED** (flat-table steps). The five-step *process* (architecture → Stage 1 backend → Stage 2 frontend → verification → lock decision) still applies. |
| §11 verification against the repository | **Still valid** (repo facts). |

### A.3 What the approved model decides

| Level | Decided | Not decided (TBD) |
|---|---|---|
| **Plan** | The top-level container of a roadmap for a website. Every SEO record must be linked to a website URL (project rule 6), so a plan is website-scoped. | Table name and columns; whether a website has one plan or several; plan lifecycle/versioning and regeneration semantics; plan-level status and summary fields. |
| **Period** | A child of a plan: a segment of the plan's timeline that groups items. | Period granularity (month, week, another unit, or user-defined) and how many periods a plan has; period boundaries and ordering; period-level fields and status. |
| **Item** | A child of a period: an individual roadmap action. | Exact item columns and which content fields live on the item versus the period; identity/dedup key; how an item moves between periods on regeneration. |

### A.4 Product behaviour and requirements that carry over unchanged

These come from surviving evidence (§0–§2, §4.2–§4.5, §8–§9 of this document;
`src/types/roadmap.ts`; the mock in `src/mocks/roadmapMockData.ts`) and are not
altered by the model change:

- **A 90-day roadmap generated for a website from real module findings.** The
  frontend contract today exposes `month_number` (1–3), `week_number` (1–12) and
  `due_period` (`week_1`…`week_12`); how those map onto *periods* is TBD.
- **Six generation sources and their field translations** (audit issue, on-page
  recommendation, performance decline, off-page opportunity, AI-visibility gap,
  competitor gap — §1.2/§1.3). `content_gap` and `manual_strategy` exist in the
  frontend type but are not generated by anything today and remain out of scope.
- **The mock's selection heuristic** (month 1 = top 4 audit issues, month 2 = top 4
  on-page recommendations, month 3 = top 8 from the pooled remaining sources,
  ranked by priority weight high=3/medium=2/low=1 — §2.2) as the behaviour to
  formalise; the mapping to periods is TBD.
- **Item content the product already shows:** title, explanation, related module,
  source, priority, expected impact, effort, risk, owner, and status
  (`planned` / `in_progress` / `blocked` / `completed` / `skipped`). Their exact
  placement on the three-level model is TBD.
- **Safety refinements to source selection** (§4.3), e.g. only `open`/`in_review`
  audit issues, exclusion of terminal-status diagnoses/opportunities.
- **Authorization principles** (§4.2, §9): generation limited to owner / admin /
  team_member (plus global admin); clients read-only; one non-leaking denial
  message; workspace/actor derived server-side; accept only the website identity
  from the client; advisory-lock serialisation; `anon`/`PUBLIC` denied. The exact
  RPC set and signatures are TBD.
- **Human-touched work is never silently overwritten or auto-retired** (the intent
  of §4.4 items 4–5): an item a person has started, blocked, completed or skipped
  must survive regeneration.
- **Truthfulness/provenance** (§4.5): rule-based, no AI/LLM claims.
- **Frontend rules:** mock mode preserved; reads through `runWithServiceAdapter`
  with no silent mock fallback in Supabase mode; role gating is a usability layer
  only (§9).
- **Downstream consumers** (§8): the Dashboard Roadmap widget; the locked Reports
  RPC's roadmap counts stay out of scope without a separate approved extension.

### A.5 TBD — not supported by surviving evidence or an existing approved decision

Table names, columns, constraints and indexes for all three levels · period
granularity, count and boundaries · plan cardinality per website and
lifecycle/versioning · how the mock's positional week scheduling (§2.2 point 4)
maps onto periods and how schedule drift is absorbed · item identity/dedup key and
supersession semantics · plan/period status and roll-up summary for
`fetchRoadmapSummary` and the Dashboard · per-table RLS · generation RPC set,
signatures and return types · status-update path · read-service surface (the seven
current `roadmapService.ts` exports map onto a three-level model in ways not yet
specified) · migration plan and verification plan · any extension to Reports'
roadmap counts.

### A.6 Explicit non-claims

No migration, table, RPC or service exists. Implementation has not been started or
authorised. Nothing here was reconstructed from any earlier, lost worktree. Do not
implement §3–§7 or §10 as written.

---

**Role:** the complete architecture design for closing the Roadmap backend
gap identified in `SEO_RELEASE_ROADMAP.md` §4.2 and §3 ("Roadmap backend
(persistence)" — P0) — `generateRoadmapFromFindings` already reads real data
from six other modules in Supabase mode, but its output (the 90-day plan
itself) is discarded into an in-memory/localStorage mock store and never
persists. **Design-only.** No code, migration, or configuration was written
or applied while producing this document.

**Created:** 2026-07-24. **Verified against:** the current working tree,
local HEAD `a594d1dbd0f67f71b218132b848ce9678c3cad17`, which does not differ
from `origin/main` `71ac8fd0fd6087bb5435bea4cca865025bc27967` in any file
this design touches (confirmed by inspection during this task).

**Method:** every schema fact, service dispatch pattern, RLS rule, and mock
heuristic below was read directly from the repository during this task, not
assumed from prior conversation memory or documentation summaries. File
paths and line-level facts are cited throughout. Where this document depends
on the **Recommendation Generation Stage 1** work — unaccepted when this was
written, **since accepted, locked and merged to `main` (with Stage 2), 2026-09-19**
(see §4.3 and §8) — that dependency is called out explicitly rather than assumed.

**Process:** this document is Step 1 of the same five-step sequence already
proven for Competitor Benchmarking and Recommendation Generation —
Architecture → Stage 1 Backend → Stage 2 Frontend → Verification → Module
Lock. It intentionally follows that template's section structure.

---

## 0. The Critical Finding This Design Is Built On

**Unlike every other module built so far in this project, Roadmap has *zero*
backend today — not even a persisted read path.** This is a materially
different starting point than Recommendation Generation (which already had a
real, working `seoRecommendationSupabaseService.ts` read path before its
Stage 1 work) or Reports/Competitor Benchmarking (whose Stage 1 was "add a
persisted read table"). Verified directly:

- `find src -iname "*roadmap*"` returns 8 files — a service, a mock-data
  module, a filter helper, a label helper, and 5 page/component files.
  **None of them is a Supabase service.** `src/services/supabase/` contains
  22 files at design time (**23 non-test files on canonical `main` as of
  2026-09-19**, none roadmap-related); none is named (or contains) anything
  roadmap-related beyond a single explanatory comment (§0.1 below).
- `grep -ril roadmap supabase/migrations/*.sql` returns exactly one file,
  `20260720120036_seo_report_generate.sql` — and only because that
  **locked** RPC's payload-builder hardcodes
  `'roadmap_summary', 'The 90-day roadmap is not connected yet.',
  'roadmap_completed_count', 0, 'roadmap_total_count', 0` and marks
  `'roadmap', 'unavailable'` in its `data_provenance` object (lines 282–292).
  This is a locked module's own truthful acknowledgment, at the time it was
  written, that no Roadmap backend exists — independent corroboration of
  this design's starting premise, not something this design modifies.
- `docs/markdown/MODULE_LOCKS.md` (Stage 6 entry, line 156, and the Reports
  v1 entry's deferred-scope list) explicitly lists **"Competitors/Roadmap/
  Reports backend wiring"** as deferred scope that "is **not** part of the
  locked scope and is **not** a defect in it" — confirming this gap is
  known, pre-scoped, and open for exactly this kind of additive work.

### 0.1 `src/services/roadmapService.ts` has no adapter dispatch at all

Every other real-or-partially-real service in this repo dispatches through
`runWithServiceAdapter({ mock, supabase })` (`src/services/serviceAdapter.ts`)
so that Supabase mode reads/writes real data. **`roadmapService.ts` never
imports `runWithServiceAdapter` or checks `dataMode`/`supabaseMode` at all**
— every one of its seven exported functions
(`fetchRoadmapItems`, `fetchRoadmapItemById`, `fetchRoadmapItemsByMonth`,
`fetchHighPriorityRoadmapItems`, `updateRoadmapItemStatus`,
`fetchRoadmapSummary`, `generateRoadmapFromFindings` — five reads, one status
write, one generator) calls straight into
`@/mocks/roadmapMockData` via `toAsync(...)`, unconditionally, in **both**
mock and Supabase mode. This means:

- **Reads are always mock**, regardless of data mode — there is no
  read-path gap to close separately from the write path, unlike every prior
  module in this project. Stage 1 here must build **both** the persisted
  table/RLS **and** wire the read functions to it (the Reports/Competitor
  Stage-1 pattern), not just add a generation RPC on top of an existing
  read path (the Recommendation Stage-1 pattern).
- **`generateRoadmapFromFindings` reads real data but writes fake data.**
  This is the specific, worse failure mode `SEO_RELEASE_ROADMAP.md` §4.2
  flags: in Supabase mode, five of its six upstream sources (fetched via the six
functions below — `fetchLatestAudit` and `fetchIssuesForAudit` both serve the audit source)
  (`fetchLatestAudit`, `fetchIssuesForAudit`, `fetchOnPageRecommendations`,
  `fetchDeclineDiagnoses`, `fetchAuthorityOpportunities`,
  `fetchAiContentGaps`) are genuinely dispatched through
  `runWithServiceAdapter` and return real rows where the underlying module
  is real (verified individually in §1). But the **generated roadmap items
  themselves** are written only via `replaceRoadmapForWebsite` in
  `src/mocks/roadmapMockData.ts` (line 85) — never to any database. A signed
  in operator in Supabase mode today can click "Generate 90-Day Roadmap" and
  see a plausible-looking plan built from real audit/recommendation/
  performance titles, and it will vanish on next login / not appear for a
  teammate, with **no error, no warning, and no `supabaseMode`-based
  disabling of the button anywhere in `RoadmapPage.tsx`** (verified: no
  `supabaseMode` or `dataMode` reference exists in that file or in
  `RoadmapSummaryHeader.tsx`). This is a more actively misleading state than
  Recommendation Generation's prior gap (which at least returned an honest
  empty `[]`).
- **The Dashboard also silently shows mock Roadmap data in Supabase mode.**
  `src/services/supabase/seoDashboardSupabaseService.ts` lines 18–24 contain
  an explicit, still-accurate-for-Roadmap comment: *"Page Performance /
  Off-Page / AI Visibility / Competitor / Roadmap / Support / Reports
  widgets on the same page stay mock-only (their services are untouched,
  out of scope)."* (Several of the other modules named in that comment have
  since gone real — this design does not correct that comment, only notes
  that Roadmap's part of it is still true.) `SeoDashboardPage.tsx` line
  98–102 calls `fetchRoadmapSummary` unconditionally, same as
  `RoadmapPage.tsx` — confirming the Dashboard's roadmap widget
  (`CompetitorRoadmapSummaryCard.tsx`) is currently always fed mock numbers
  regardless of data mode.

---

## 1. Current Schema and Services (verified from source)

### 1.1 `seo_roadmap_items` — does not exist. No table, no RLS, no RPC.

### 1.2 The six upstream sources `generateRoadmapFromFindings` reads (verified individually)

| # | Source (`RoadmapSource`) | Frontend fetch (`roadmapService.ts`) | Dispatch | Real table | Real status filter available |
|---|---|---|---|---|---|
| 1 | `audit_issue` | `fetchIssuesForAudit` / `fetchLatestAudit` (`auditService.ts`) | `runWithServiceAdapter` ✅ | `seo_audit_issues` | `status IN ('open','in_review','approved','fixed','ignored')` |
| 2 | `recommendation` | `fetchOnPageRecommendations` (`recommendationService.ts`) | `runWithServiceAdapter` ✅ | `seo_recommendations` (`issue_id IS NULL`, on-page areas) | `status` (8-value approval-lifecycle set) |
| 3 | `performance_decline` | `fetchDeclineDiagnoses` (`performanceService.ts`) | `runWithServiceAdapter` ✅ | `seo_decline_diagnoses` | `status IN ('open','in_review','action_planned','resolved','dismissed')` |
| 4 | `offpage_opportunity` | `fetchAuthorityOpportunities` (`offPageService.ts`) | `runWithServiceAdapter` ✅ | `seo_authority_opportunities` | `status IN ('suggested','shortlisted','approval_required','in_progress','expert_review_requested','completed','rejected','avoided')` |
| 5 | `ai_visibility_gap` | `fetchAiContentGaps` (`aiVisibilityService.ts`) | `runWithServiceAdapter` ✅ | `seo_ai_content_gaps` | `status IN ('open','planned','addressed','dismissed')` |
| 6 | `competitor_gap` | `fetchCompetitorGaps` (`competitorService.ts`) | **Not dispatched at all** — a pure, always-computed derivation over `fetchCompetitors`/`fetchBenchmarkComparisons` (themselves real via `runWithServiceAdapter`) | none (ephemeral; computed, never persisted, in **either** mode) | n/a (no status concept; always "current") |

Two `RoadmapSource` values exist in the type (`src/types/roadmap.ts`) but are
**verified unused** by `generateRoadmapFromFindings` or anywhere else in
`src/` (`grep -rn "'manual_strategy'\|'content_gap'" src/` returns nothing
outside the type file): `content_gap` (a plausible future link to Content
Studio's real `seo_content_opportunities` table, migration
`20260711120007` — **not** wired to Roadmap today, out of scope for this
design) and `manual_strategy` (an operator-added freeform item — no UI or
service exists to create one). **This design reproduces only the 6 sources
the mock actually generates from today**, per the same "reproduce, don't
invent" discipline used for Recommendation Generation.

### 1.3 Exact real-table columns needed, and the field-name translations the frontend already performs

Fields already verified in prior work (Recommendation Generation
architecture/implementation, this session): `seo_audit_issues`
(`id, category, severity, title, why_it_matters, suggested_next_action,
impact, effort, risk, fix_owner, status, audit_run_id`); `seo_recommendations`
(`id, area, title, why_it_helps, suggested_change, impact, effort, risk,
action_type, status, issue_id, is_current`).

Newly verified this task:

- **`seo_decline_diagnoses`** (migration `20260711120014`): `id,
  diagnosis_type` (11-value enum: `ctr_drop, ranking_decline,
  clicks_decline, impressions_decline, content_freshness, indexing_issue,
  cannibalization_risk, intent_mismatch, competitor_improvement,
  technical_performance, no_data, mixed_signals`), `business_summary,
  likely_cause` (free text, distinct from `diagnosis_type` — see below),
  `recommended_next_action, suggested_owner, priority, status, page_url`
  (via `seo_page_inventory` join or the row's own snapshot).
  **Non-obvious, verified field-mapping fact:** the frontend
  `DeclineDiagnosis.likely_cause: DeclineCause` field is **not** the DB's own
  `likely_cause` text column — it is `mapDiagnosisTypeToCause(row.diagnosis_type)`
  (`seoDeclineDiagnosisSupabaseService.ts` lines 119–130), a fixed
  11→10-value collapse table (e.g. `clicks_decline` and
  `impressions_decline` both collapse to `ranking_loss`; `no_data`/
  `mixed_signals`/anything unrecognized fall back to `technical_issue`).
  The roadmap title builder (`Address ${d.likely_cause.replace(/_/g,' ')} on
  ${pathname}`) operates on this **mapped** value, not the raw DB column —
  this design's RPC must reproduce `DIAGNOSIS_TYPE_TO_CAUSE` exactly, in SQL,
  not read `likely_cause` directly.
  `business_explanation`(frontend)↔`business_summary`(DB);
  `recommended_fix`(frontend)↔`recommended_next_action`(DB);
  `fix_owner`(frontend)↔`suggested_owner`(DB) — three more verified
  1:1-but-renamed mappings.
- **`seo_authority_opportunities`** (migration `20260711120017`): `id,
  opportunity_type, title, suggested_action, why_it_matters,
  expected_authority_impact, effort, risk, fix_owner, status` (8-value enum;
  the migration's own comment states terminal states are `completed,
  rejected, avoided` — **exactly** the 3 values `roadmapService.ts`'s
  `.filter((o) => o.status !== "avoided" && o.status !== "rejected" &&
  o.status !== "completed")` already excludes, a verified 1:1 match needing
  no refinement). All field names match the frontend `OffPageOpportunity`
  type 1:1 — no translation layer.
- **`seo_ai_content_gaps`** (migration `20260711120022`): `id, topic,
  missing_answer_angle, suggested_content_type,
  related_keyword_or_question, priority, recommended_next_action, status`
  (4-value: `open, planned, addressed, dismissed`). All field names match
  the frontend `AiContentGap` type 1:1.
- **Competitor gap derivation** (`competitorService.ts` lines 103–292, fully
  re-derivable server-side): `computeOurBenchmarkScores` (8 named scores
  from the latest completed audit's 4 stored scores, via fixed
  offsets/clamps) and `competitorDimensionScore` (the same 8 dimensions per
  competitor, from `seo_competitors`' 5 stored scores) are **the exact same
  formulas already implemented once in SQL** by the applied
  `seo_competitor_generate` migration's `v_our_overall` calculation
  (`20260724120040_seo_competitor_generate.sql` lines 155–164) — but that
  RPC only persists the **mean**, not the 8 individual dimension scores this
  design needs. `gapLevelFor` (`gap = competitor_avg − our_score`; `≥15`
  high, `≥5` medium, else low), the 7-of-8-dimension
  `GAP_TYPE_BY_DIMENSION` map (`local_visibility` has **no** mapped gap
  type — verified `Partial<Record<...>>`, so a local-visibility gap, however
  large, never produces a `competitor_gap` roadmap candidate — a real,
  non-obvious exclusion to preserve, not a bug to fix), `MODULE_BY_GAP_TYPE`,
  `GAP_TITLE_BY_TYPE`, and `OWNER_BY_GAP_TYPE` are all fixed small lookup
  tables, fully reproducible in SQL (lines 221–259).
  **Verified, load-bearing fact:** `fetchCompetitorGaps`'s own id format is
  `gap_mock_${websiteId}_${gapType}` — **one gap per dimension-type per
  website**, deterministic, **even in Supabase mode** (the literal string
  `gap_mock_` is hardcoded regardless of data mode) — meaning there is no
  real persisted row or stable uuid to link to for this source; `gap_type`
  itself is the only available stable identity.

### 1.4 RLS/role convention (verified consistent across every real table checked)

Every real writable table checked this session and in prior sessions
(`seo_audit_issues`, `seo_recommendations`, `seo_competitors`,
`seo_ai_content_gaps`, `seo_decline_diagnoses`, `seo_authority_opportunities`)
uses the **same** write policy shape: `FOR ALL USING/WITH CHECK
(seo_role_in(workspace_id, ARRAY['owner','admin','team_member']) OR
seo_is_global_admin())` — client and anon excluded from direct writes,
member (incl. client) allowed to `SELECT`. This design's read table follows
the identical, unmodified pattern (§3.2).

---

## 2. The Existing Mock Heuristic (the rule set this design formalizes server-side)

Read directly from `src/services/roadmapService.ts` (`generateRoadmapFromFindings`,
lines 120–239) and `src/mocks/roadmapMockData.ts`. As with Recommendation
Generation, this design **reproduces** the already-agreed product rule; it
does not invent new logic.

### 2.1 Candidate building (per source, verbatim field mapping)

| Source | Title | Explanation | `related_module` | Priority/impact | Effort | Risk | Owner |
|---|---|---|---|---|---|---|---|
| audit_issue | `issue.title` | `issue.simple_explanation` | `'audit'` | `issue.impact` | `issue.effort` | `issue.risk` | `issue.fix_owner` |
| recommendation (on-page only) | `rec.title` | `rec.why_it_helps` | `'content_studio'` | `rec.impact` | `rec.effort` | `rec.risk` | `ACTION_TYPE_OWNER[rec.action_type]` (a 5→4 map, `roadmapService.ts` line 92: `auto_suggest/avoid→system_suggestion`, `approval_required→developer_needed`, `manual_support→client_action`, `expert_review→digibility_expert`) |
| performance_decline | `` `Address ${cause_words} on ${pathname(page_url)}` `` | `d.business_explanation` | `'page_performance'` | `d.priority` | `'medium'` (hardcoded) | `'low'` (hardcoded) | `d.fix_owner` |
| offpage_opportunity | `o.title` | `o.why_it_matters` | `'offpage_authority'` | `o.expected_authority_impact` | `o.effort` | `o.risk` | `o.fix_owner` |
| ai_visibility_gap | `` `Close AI content gap: ${g.topic}` `` | `g.recommended_next_action` | `'ai_visibility'` | `g.priority` | `'medium'` (hardcoded) | `'low'` (hardcoded) | `'client_action'` (hardcoded — not derived from any gap field) |
| competitor_gap | `g.title` (from `GAP_TITLE_BY_TYPE`) | `g.recommended_action` | `g.related_module` (from `MODULE_BY_GAP_TYPE`) | `g.priority` (`'high'` if `gap_level==='high'` else `'medium'`) | `'medium'` (hardcoded) | `'low'` (hardcoded) | `g.suggested_owner` (from `OWNER_BY_GAP_TYPE`) |

### 2.2 Selection and scheduling (the part this design must redesign, not just port)

1. **Month 1** = top **4** `audit_issue` candidates by priority weight
   (`high=3, medium=2, low=1`, stable sort), from the **latest audit** only
   — **no status filter in the mock** (every issue from the latest audit is
   a candidate, including ones already `fixed`/`ignored`).
2. **Month 2** = top **4** on-page `recommendation` candidates, same
   priority sort — again **no status filter** in the mock.
3. **Month 3** = top **8** candidates from the pooled remaining four
   sources, same priority sort (off-page opportunities are the one source
   the mock already filters, to its 3 terminal statuses — §1.3).
4. **Week assignment is purely positional, not a stable per-item
   property:** `assignWeeks` (`roadmapService.ts` lines 212–230) assigns
   `weekRange[index % weekRange.length]` where `weekRange` is `[1,2,3,4]`
   for month 1, `[5,6,7,8]` for month 2, `[9,10,11,12]` for month 3, and
   `index` is the item's position in the **already-sorted, already-truncated**
   array. **Consequence verified by direct reasoning about the code:** if
   the candidate pool changes at all (a new issue appears, an old one drops
   below the top-4 cutoff), every other item's week number in that month can
   shift too, even for items whose own content is completely unchanged —
   week number is a function of the whole month's candidate set, not of the
   individual item. **This is the single hardest problem this design has to
   solve that Recommendation Generation did not**, because Recommendation's
   identity (`source_issue_fingerprint`) never depended on sibling items;
   Roadmap's `(source, source_row)` identity is stable, but its **schedule**
   is not. §4.4 resolves this by treating `week_number`/`month_number` as
   ordinary mutable content (eligible for the same supersede-if-untouched
   rule as everything else), not as part of the identity key.

### 2.3 `replaceRoadmapForWebsite`'s regeneration behavior (the mock's own precedent — partially reused, partially replaced)

`replaceRoadmapForWebsite` (`roadmapMockData.ts` lines 85–105) already does
**better** than the pre-Stage-1 Recommendation mock: it matches new items to
previous ones by `(title, week_number)` text equality and preserves the
matched item's `id`/`created_at`/**`status`** — so a completed item doesn't
silently reset to `planned` on regeneration. This is a real, deliberate
safety property already in the product, worth preserving in spirit. But it
is **not** a safe pattern to port literally to a real, RLS-governed,
shared-workspace table:

- `(title, week_number)` is a **fragile, coincidental** match key — two
  different underlying issues can legitimately have the same title text
  after a rewrite, and (per §2.2) `week_number` is not even stable for an
  *unchanged* item across regenerations. A text-based match key would
  silently misattribute history in a real multi-user system in a way that
  never surfaced in single-browser mock testing.
- It still performs a **wholesale delete-and-replace** of every item for
  the website on every generation (`mockRoadmapItems.length = 0;
  mockRoadmapItems.push(...remaining, ...merged)` at the website-filtered
  level) — safe in mock mode (no separate approval/activity trail can
  reference a roadmap item), but this design's real table has no such
  guarantee once any downstream feature (comments, activity log, a future
  "convert to recommendation" link) references a `seo_roadmap_items.id` by
  FK. **This design replaces the title/week match with the stable
  `(source, source_row)` identity from §1.2–§1.3, and replaces
  delete-and-replace with the same non-destructive `is_current`/
  `superseded_by` versioning §4 of the Recommendation Generation design
  established** — the first table in this project designed with that
  versioning scheme from creation, rather than retrofitted onto an existing
  one.

---

## 3. Database Model (additive — one new table, unlike Recommendation's column-additions)

> **[SUPERSEDED 2026-09-19 — flat single-table design]** The approved architecture is `plans → periods → items` (see the amendment at the top). The single-table model below is retained as historical reference only; do not implement it. Table/column details for the three-level model are TBD.


### 3.1 New table `seo_roadmap_items`

```
id                    uuid PK
workspace_id          uuid NOT NULL REFERENCES seo_workspaces
website_id            uuid NOT NULL REFERENCES seo_websites
website_url           text NOT NULL                 -- snapshot, per repo-wide convention
week_number           integer NOT NULL CHECK (week_number BETWEEN 1 AND 12)
month_number          integer NOT NULL CHECK (month_number IN (1,2,3))
due_period            text NOT NULL                 -- 'week_1' .. 'week_12', derived from week_number
title                 text NOT NULL
explanation           text NOT NULL
related_module        text NOT NULL CHECK (... the 12 RelatedModule values ...)
source                text NOT NULL CHECK (source IN (
                        'audit_issue','recommendation','performance_decline',
                        'offpage_opportunity','ai_visibility_gap','competitor_gap'))
                      -- 'content_gap'/'manual_strategy' intentionally NOT
                      -- included in the CHECK yet — no generator produces
                      -- them (§1.2); adding them later is a pure additive
                      -- CHECK-constraint extension, not a breaking change.
priority              text NOT NULL CHECK (impact-level: low/medium/high)
expected_impact       text NOT NULL CHECK (impact-level)
effort                text NOT NULL CHECK (effort-level)
risk                  text NOT NULL CHECK (risk-level)
owner                 text NOT NULL CHECK (owner-type: the 4 OwnerType values)
status                text NOT NULL DEFAULT 'planned'
                        CHECK (status IN ('planned','in_progress','blocked','completed','skipped'))
-- Source linkage: typed nullable FKs for the 4 real, FK-able sources (for
-- referential integrity + easy joins, ON DELETE SET NULL so a removed
-- upstream row never deletes roadmap history), PLUS a uniform text
-- fingerprint used as the actual identity/dedup key across all 6 sources
-- (including the FK-less competitor_gap case) — mirrors Recommendation
-- Generation's dual issue_id + source_issue_fingerprint approach (§3.1/§4.1
-- of that design), extended to 4 possible FK columns instead of 1.
issue_id                    uuid REFERENCES seo_audit_issues(id) ON DELETE SET NULL
recommendation_id           uuid REFERENCES seo_recommendations(id) ON DELETE SET NULL
decline_diagnosis_id        uuid REFERENCES seo_decline_diagnoses(id) ON DELETE SET NULL
authority_opportunity_id    uuid REFERENCES seo_authority_opportunities(id) ON DELETE SET NULL
ai_content_gap_id           uuid REFERENCES seo_ai_content_gaps(id) ON DELETE SET NULL
-- competitor_gap rows leave all 5 FK columns NULL; source_fingerprint alone
-- carries their identity, e.g. 'competitor_gap::ai_visibility_gap'.
source_fingerprint     text NOT NULL   -- '<source>::<source-row-id-or-gap_type>'
generation_method      text            -- e.g. 'rule_based_v1', mirrors A15/A17 provenance discipline
is_current             boolean NOT NULL DEFAULT true
superseded_by          uuid REFERENCES seo_roadmap_items(id) ON DELETE SET NULL
created_by             uuid REFERENCES auth.users(id) ON DELETE SET NULL
created_at             timestamptz NOT NULL DEFAULT now()
updated_at             timestamptz NOT NULL DEFAULT now()
```

Only one partial unique index is needed (unlike Recommendation's two),
because every roadmap item — including competitor-gap-derived ones — always
has a non-null `source_fingerprint`:

```sql
CREATE UNIQUE INDEX ... ON seo_roadmap_items (website_id, source_fingerprint)
  WHERE is_current;
```

### 3.2 RLS (unmodified pattern, per §1.4)

- `seo_roadmap_items_select`: `is_seo_workspace_member(workspace_id) OR
  seo_is_global_admin()` — every role, including client, can read (matches
  the mock UI, which shows the roadmap to any signed-in user with no role
  gate).
- `seo_roadmap_items_write`: `seo_role_in(workspace_id,
  ARRAY['owner','admin','team_member']) OR seo_is_global_admin()` — service
  role / generation RPC and manager roles only; **client excluded from
  direct writes**, same as every other real table in this repo.

**Verified divergence from the current mock UI, to flag explicitly (per the
"stop and report a conflict" discipline):** `RoadmapItemCard.tsx` shows the
status `<Select>` unconditionally to *any* signed-in user, with no role
check anywhere in that component or its parent. In Supabase mode with this
RLS, a client attempting to change status would get a real, enforced
`403`/RLS-denial where the mock silently succeeded today. This is the same
class of "frontend implies access RLS won't actually grant" issue every
other module's Stage 2 has had to reconcile with a role-gated disabled
control (Reports' Generate button, Competitor's Generate button, the
planned Recommendation Generate button) — Roadmap's Stage 2 (§9) needs the
equivalent: disable status-editing for client/non-member in Supabase mode.
**Why client-write was not instead allowed** (the alternative that would
avoid a UI behavior change): every real writable domain table in this
project (§1.4) already excludes clients from direct writes, and Roadmap
items carry no risk/approval concept that would justify inventing a new,
one-off "clients may write" exception — consistency with the established
convention was judged more important than preserving the mock's
permissiveness. This is a design decision, not an oversight; a different
call could reasonably be made by an approver, at which point the RLS write
policy would simply add `'client'` to the allowed-roles array.

### 3.3 Why no `manual_strategy` write path is designed here

The mock has no UI, service function, or mock-data function for
operator-created roadmap items — `manual_strategy` is a declared-but-unused
type value. Building a "let a workspace manager add a custom roadmap item"
feature is a plausible, reasonable future extension (the schema's `source`
CHECK constraint is additive-extensible to accommodate it), but it is **not
part of what `generateRoadmapFromFindings` does today**, so per the
"reproduce, don't invent" discipline this design does not include it.

---

## 4. Generation Rules (the guarded RPC's logic, described — not implemented)

> **[SUPERSEDED 2026-09-19 — flat single-table design]** §4.2 (authorization), §4.3 (source selection) and §4.5 (provenance) remain valid rules. The contract below and §4.4 are keyed to the flat `seo_roadmap_items` row and are superseded as written; their intent (idempotent regeneration; human-touched items never overwritten) carries over, its expression on the three-level model is TBD.


**`public.seo_roadmap_generate(p_website_id uuid) RETURNS SETOF
public.seo_roadmap_items`** — returns the canonical current roadmap set
after persistence, matching the return-shape convention this task's own
prior work (Recommendation Generation Stage 1) established as the current
standard (a deliberate continuation of "that consistency has worked well,"
per this task's own framing) — **not** the earlier `RETURNS integer`
convention Competitor Stage 2A used.

### 4.1 Contract

`SECURITY DEFINER`, `SET search_path = public`, `authenticated` EXECUTE
granted, `anon` + `PUBLIC` revoked in the same migration (no corrective
follow-up — the Competitor Stage 2A / Recommendation Stage 1 discipline, not
the two-migration Reports Stage 2 precedent). Accepts **only**
`p_website_id`.

### 4.2 Authorization

Identical shape to every prior guarded generation RPC in this repo: resolve
`workspace_id`/`website_url` from `seo_websites`; authorize
`seo_role_in(...,['owner','admin','team_member']) OR seo_is_global_admin()`;
missing-website and role-failure share one non-leaking message;
`pg_advisory_xact_lock(hashtextextended(p_website_id::text ||
':roadmap_generate', 0))`.

### 4.3 Source selection (server-side reproduction of §2.1–§2.2, with two safety refinements)

1. Latest **completed** `seo_audit_runs` row for the website (same
   selection rule as `seo_report_generate` / `seo_competitor_generate` /
   `seo_recommendation_generate`, which was unaccepted when this was written and is
now locked) → its `seo_audit_issues`.
   **Refinement:** limit candidates to `status IN ('open','in_review')`
   (the mock has no filter; a `fixed`/`ignored` issue should not populate a
   fresh 90-day plan) — the same refinement already applied and verified in
   Recommendation Generation Stage 1's design for the identical reason.
2. **On-page** `seo_recommendations` (`issue_id IS NULL`, `is_current`) for
   the website. **Cross-module dependency, stated plainly:** this source
   will be **empty** until Recommendation Generation's generation RPC has
   actually been run for a website — Roadmap Month 2 generation is not blocked by
   this design, but its real output depends on that separate workstream.
   *(Status when written, 2026-07-24: `IMPLEMENTED — NOT YET LOCALLY VERIFIED OR
   ACCEPTED`. **Status 2026-09-19:** Stages 1–2 are complete, accepted, locked and
   on `main`; the RPC's migration was promoted and verified on `Digi_SEO_Test` on 2026-09-19, so this
   source can be populated on TEST once the RPC has been run for a website.)* This design does not
   attempt to work around that dependency (e.g. by reading `seo_audit_issues`
   a second time under a different label) — it reproduces the mock's actual
   data source faithfully and accepts the resulting temporary gap.
3. `seo_decline_diagnoses` for the website. **Refinement:** exclude
   `status IN ('resolved','dismissed')` (the two DB terminal states; the
   mock has no filter). `likely_cause` for the title is computed via the
   verified `DIAGNOSIS_TYPE_TO_CAUSE` mapping (§1.3), not read directly.
4. `seo_authority_opportunities` for the website, `status NOT IN
   ('completed','rejected','avoided')` — an exact, already-matching
   reproduction of the mock's own filter, no refinement needed.
5. `seo_ai_content_gaps` for the website, `status IN ('open','planned')`
   (**refinement**: exclude `addressed`/`dismissed`; the mock has no
   filter).
6. **Competitor gaps**, computed inline exactly as §1.3 describes: the
   8-dimension our-score/competitor-score/gap-level derivation, the 7-entry
   `GAP_TYPE_BY_DIMENSION` (excluding `local_visibility`), filtered to
   `gap_level <> 'low'`. No status filter exists or is needed (always
   freshly recomputed, matching the mock's own "derived, not stored"
   behavior — §1.2 row 6).

For each source, map fields per §2.1's table exactly (including the
hardcoded `effort='medium'`/`risk='low'` values for
performance_decline/ai_visibility_gap/competitor_gap, and the hardcoded
`owner='client_action'` for ai_visibility_gap — these are the mock's actual,
verified behavior, not simplifications).

### 4.4 Selection, scheduling, and the three-way replace-to-match

> **[SUPERSEDED 2026-09-19 — flat single-table design]** Written for a flat items table (`source_fingerprint`, `is_current`, `superseded_by` on the item). Superseded as written; TBD on plans → periods → items. The selection rule (steps 1–2) and the never-overwrite-human-touched-items rule (cases 4–5) are the retained product behaviour.


1. Rank month-1 candidates (issue-derived) by priority weight, take top 4;
   rank month-2 candidates (on-page recs) by priority, take top 4; pool
   month-3 candidates (4 sources), rank by priority, take top 8 — identical
   selection rule to §2.2, applied against real rows.
2. Assign `week_number`/`month_number`/`due_period` positionally within
   each month's ranked list, identical to `assignWeeks` (§2.2 point 4).
3. For each selected candidate, compute `source_fingerprint =
   '<source>::<source-row-id-or-gap_type>'` (stable across regenerations
   regardless of rank/week — this is the identity key, **not**
   `week_number`, resolving the §2.2 point-4 problem).
4. **Three-way replace-to-match**, identical structure to Recommendation
   Generation Stage 1 (§4.4 of that design), adapted to Roadmap's single
   "untouched" status (`planned` — vs. Recommendation's two,
   `suggested`/`needs_review`):
   1. No current item with this fingerprint → insert, `status='planned'`.
   2. Current item exists, **all** content fields unchanged **including**
      `week_number`/`month_number`/`due_period` (§2.2's scheduling
      instability means an unrelated candidate-pool change can legitimately
      change an untouched item's schedule; treating the schedule as
      ordinary content, not identity, is the correct place to absorb that)
      → no write.
   3. Current item exists, content changed, `status = 'planned'`
      (untouched) → supersede: retire the old row first (`is_current=false,
      updated_at=now()`) — before inserting the new row, avoiding the same
      momentary partial-unique-index collision Recommendation Stage 1's
      implementation had to sequence around — then insert the new row,
      then set the old row's `superseded_by` to the new row's id.
   4. Current item exists, content changed, `status <> 'planned'` (a human
      has set `in_progress`/`blocked`/`completed`/`skipped`) → do nothing at
      all. A schedule or content change on an item someone is actively
      working is never silently rewritten out from under them.
5. **Retire pass:** any current item whose source is no longer in this
   generation's desired set (its underlying issue/gap/opportunity/diagnosis
   resolved, was excluded by a status filter, or dropped out of the
   top-4/top-8 cutoff) **and** whose `status = 'planned'` → retire
   (`is_current=false, superseded_by=NULL`). Same status carve-out as case 4
   — an item a human has already started, blocked, completed, or skipped is
   never auto-retired just because it fell out of this month's top-N or its
   source resolved; that is a human decision to close out via the status
   control, not a side effect of the next regeneration.
6. Return `SELECT * FROM seo_roadmap_items WHERE website_id=... AND
   is_current ORDER BY week_number, created_at, id`.

### 4.5 Truthfulness / provenance

Every generated row is a deterministic transformation of real,
already-persisted (or, for competitor gaps, already-real-input-derived)
data — never AI/LLM inference, never fabricated. `generation_method =
'rule_based_v1'` (consistent with A15/A17's provenance discipline),
recorded but not required.

---

## 5. Deduplication (summary — full mechanics in §4.4/§3.1)

> **[SUPERSEDED 2026-09-19 — flat single-table design]** Flat-table dedup key; TBD for the three-level model.


One stable key: `(website_id, source_fingerprint)`, partial-unique
`WHERE is_current`. Because `source_fingerprint` encodes the underlying
source row's own stable id (or, for competitor gaps, the deterministic
`gap_type`) rather than any positional/schedule property, a recurring
finding across repeated regenerations reuses the same roadmap-item identity
even as its week/month/rank shift — resolving the scheduling-instability
problem identified in §2.2.

---

## 6. Update Strategy (summary — full mechanics in §4.4)

> **[SUPERSEDED 2026-09-19 — flat single-table design]** Flat-table update strategy; TBD for the three-level model.


| Scenario | Result |
|---|---|
| New eligible finding appears | New roadmap item inserted, `status='planned'` |
| Finding's mapped content or its schedule slot changed, item still `planned` | Old item superseded, new item inserted `planned` |
| Finding's mapped content or schedule changed, item already `in_progress`/`blocked`/`completed`/`skipped` | Left untouched — a human decision (or human-set schedule) is never overwritten |
| Finding resolved / fell out of the top-N, item still `planned` | Item retired (`is_current=false`, `superseded_by=NULL`) |
| Finding resolved / fell out of the top-N, item already acted on | Left untouched |
| Regenerate with no real-world change | Zero writes |

---

## 7. Status-Update Path (simpler than a guarded transition RPC — justified)

> **[SUPERSEDED 2026-09-19 — flat single-table design]** Targets the flat items table; the status-update path for items within periods is TBD.


Unlike Off-Page Authority's `seo_authority_opportunity_transition` (a
guarded RPC needed because opportunity status changes interact with
`requires_approval`/`spam_risk_flags`-driven role/risk branching) or the
Recommendation/Approval lifecycle's `seo_approval_transition` (a genuine
5-role/risk matrix), **`RoadmapStatus` has no risk-differentiated branching
logic** — it is a flat, self-tracking 5-state checklist
(`planned/in_progress/blocked/completed/skipped`) with a single "untouched"
value. This design proposes **plain RLS-gated direct `UPDATE`** on
`status`/`updated_at` (owner/admin/team_member, per §3.2 — no client), the
same pattern already used for `seo_ai_content_gaps` and
`seo_decline_diagnoses` (§1.4), rather than introducing a second guarded RPC
whose only job would be `SET status = p_new_status`. If a future
requirement adds role- or risk-differentiated status rules (e.g. a
high-risk-owner item requiring approval before `completed`), a guarded
transition RPC could be introduced then as an additive extension — nothing
in this design forecloses that.

---

## 8. Downstream Integrations (verified, not modified)

| Consumer | File | Verified behavior |
|---|---|---|
| Roadmap page itself | `RoadmapPage.tsx`, `RoadmapItemCard.tsx` | Will read real data automatically via the read-path wiring in Stage 2 (§9); status-editing needs the role-gated disabled-control treatment noted in §3.2 |
| Dashboard | `SeoDashboardPage.tsx` + `CompetitorRoadmapSummaryCard.tsx` | Already calls `fetchRoadmapSummary` unconditionally (§0.1); will show real numbers automatically once `fetchRoadmapSummary` is wired to the real table in Stage 2 — no Dashboard-side code change needed |
| Reports (`seo_report_generate`, **locked**) | `20260720120036_seo_report_generate.sql` lines 282–292 | Hardcodes `roadmap: unavailable` / zero counts today. **Not modified by this design** — updating a locked RPC to report real roadmap counts is a separate, explicitly-approved additive extension to the Reports v1 lock, out of scope here (mirrors how this design also does not touch the Competitor-still-showing-`unavailable` gap in the same RPC, a pre-existing, separately-tracked inconsistency) |
| Content Studio | not found to read Roadmap | No integration verified or assumed |

---

## 9. Role Gating (frontend — future Stage 2, usability layer only, mirrors prior Stage 2Bs)

- New `canGenerateRoadmap(role, supabaseMode)` +
  `ROADMAP_GENERATE_ROLES = ['owner','admin','team_member']`, identical
  shape to `canGenerateCompetitorBenchmarks`/`COMPETITOR_GENERATE_ROLES`.
- New `canEditRoadmapStatus(role, supabaseMode)` (or reuse the same
  constant) to gate `RoadmapItemCard`'s status `<Select>` — the divergence
  flagged in §3.2.
- Backend RLS/RPC remain the sole authoritative check in both cases; the
  frontend gate is presentation-only, per the established pattern.

---

## 10. Implementation Plan (steps only — no code)

> **[SUPERSEDED 2026-09-19 — flat single-table design]** Step 2 (a single `seo_roadmap_items` table and `seo_roadmap_generate(uuid) RETURNS SETOF seo_roadmap_items`) is superseded. The five-step process still applies; the three-level content of Stage 1/2 is TBD and needs its own approved design before any implementation.


Follows the same five-step sequence as Competitor Benchmarking and
Recommendation Generation, per this task's own stated intent to keep using
it:

1. **Architecture** — this document.
2. **Stage 1 backend**: one additive migration creating `seo_roadmap_items`
   (§3.1), its RLS (§3.2), and the guarded `seo_roadmap_generate(uuid)` RPC
   (§4) with grants folded in; wire `roadmapService.ts`'s five read
   functions through `runWithServiceAdapter` to a new
   `seoRoadmapSupabaseService.ts` (the part of Stage 1 that has no
   Recommendation-generation precedent, since Roadmap had no prior real read
   path at all — closer in shape to Reports/Competitor Stage 1). A
   self-cleaning SQL verification suite (contract; full authz matrix
   +no-leak; all 6 source mappings incl. the `diagnosis_type→DeclineCause`
   and competitor-gap 8-dimension reproductions; eligibility filters; the
   full §4.4 replace-to-match matrix incl. the schedule-drift case;
   dedup-index enforcement; isolation; non-destructive empty/no-completed-
   audit case; idempotency) plus a live two-session concurrency proof —
   same discipline as every prior Stage 1.
3. **Stage 2 frontend**: `generateSupabaseRoadmap`/read functions in
   `seoRoadmapSupabaseService.ts`; `roadmapService.ts` dispatches through
   `runWithServiceAdapter` for the first time (mock branch preserved
   verbatim); role gates (§9); the status-editing role-gate on
   `RoadmapItemCard.tsx`; unit tests mirroring the Competitor Stage 2B /
   Recommendation Stage 2 pattern; authenticated operator acceptance.
4. **Verification**: the same evidence discipline as every locked module —
   SQL suite ALL PASS, concurrency proof, operator acceptance, tsc/build
   clean.
5. **Module lock decision**: a separate, explicitly-approved step, not
   automatic — per the process this project has followed for every prior
   module.

---

## 11. Verification Against the Current Repository (summary)

Every fact this design depends on was confirmed by direct inspection during
this task:

- ✅ No `seo_roadmap_items` table, RPC, or Supabase service file exists
  anywhere in the repo.
- ✅ `roadmapService.ts` has zero `runWithServiceAdapter`/`dataMode`
  references — confirmed by reading the full file, not grep alone.
- ✅ All 5 of the 6 upstream sources' individual fetch functions are
  genuinely Supabase-dispatched; `fetchCompetitorGaps` is confirmed to be a
  pure, always-mock-labeled, non-persisted computation in both modes.
- ✅ Every real source table's exact columns, status vocabulary, and
  frontend-field-name translations read directly from their migrations and
  Supabase service files, not assumed from the frontend types alone (the
  `diagnosis_type→DeclineCause` mapping in particular would have been wrong
  if inferred from the frontend type alone).
- ✅ The mock's own `replaceRoadmapForWebsite` merge behavior read in full,
  its `(title, week_number)` match key and wholesale-replace mechanic
  identified as unsafe to port literally, with the reasoning documented
  (§2.3).
- ✅ The week/month scheduling instability problem (§2.2 point 4) derived
  directly from reading `assignWeeks`'s implementation, not assumed.
- ✅ `RoadmapPage.tsx`, `RoadmapItemCard.tsx`, `RoadmapSummaryHeader.tsx`
  read in full, confirming no existing role gate on status editing or
  generation, and no `supabaseMode`/`dataMode` reference anywhere in the
  Roadmap page tree.
- ✅ `SeoDashboardPage.tsx` and `seoDashboardSupabaseService.ts` read,
  confirming the Dashboard's Roadmap widget is unconditionally mock-fed
  today, with an explicit, still-accurate source comment saying so.
- ✅ `docs/markdown/MODULE_LOCKS.md` checked for lock conflicts — Roadmap
  backend wiring is explicitly named as deferred/unlocked scope in two
  separate locked-module entries (Stage 6, Reports v1); no locked file this
  design touches.
- ✅ RLS role convention checked across 6 real tables for consistency
  before proposing the same convention here.

**No code, migration, or configuration file was changed to produce this
document.**

---

## Appendix: Files read to produce this design

`src/services/roadmapService.ts`, `src/mocks/roadmapMockData.ts`,
`src/types/roadmap.ts`, `src/types/common.ts`, `src/lib/roadmapFilters.ts`,
`src/pages/seo/RoadmapPage.tsx`, `src/pages/seo/roadmap/RoadmapItemCard.tsx`,
`src/pages/seo/roadmap/RoadmapSummaryHeader.tsx`,
`src/pages/seo/roadmap/roadmapLabels.ts`,
`src/pages/seo/dashboard/CompetitorRoadmapSummaryCard.tsx`,
`src/pages/seo/SeoDashboardPage.tsx`, `src/lib/safetyRules.ts`;
`src/services/auditService.ts`, `src/services/recommendationService.ts`,
`src/services/performanceService.ts`, `src/services/offPageService.ts`,
`src/services/aiVisibilityService.ts`, `src/services/competitorService.ts`
(in full, lines 1–292); `src/services/businessOnboardingService.ts`;
`src/services/supabase/seoDeclineDiagnosisSupabaseService.ts`,
`src/services/supabase/seoDashboardSupabaseService.ts`, and a directory
listing of `src/services/supabase/` (22 files at design time — 23 non-test files
on canonical `main` at 2026-09-19 — none roadmap-related);
`src/types/performance.ts`, `src/types/aiVisibility.ts`,
`src/types/offpage.ts`; `supabase/migrations/20260711120004_seo_stage2_audit.sql`,
`20260711120005_seo_stage2_recommendations.sql`,
`20260711120014_seo_stage5_decline_diagnoses.sql`,
`20260711120017_seo_stage6_authority_opportunities.sql`,
`20260711120022_seo_stage6_ai_content_gaps.sql`,
`20260720120036_seo_report_generate.sql`,
`20260724120040_seo_competitor_generate.sql`; `docs/markdown/MODULE_LOCKS.md`
(Stage 6 and Reports v1 entries, for the locked-scope/deferred-scope check);
`SEO_RELEASE_ROADMAP.md` §3/§4.2/§4.4/§5; a repo-wide search confirming
`manual_strategy`/`content_gap` are unused, and confirming
`seo_content_opportunities` (Content Studio, migration `20260711120007`)
exists as the plausible future real source for `content_gap`.
