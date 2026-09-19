# SEO Release Roadmap — Path to Release Candidate (Local, Product-Scope Only)

> ## ⚠ DOCUMENT CLASSIFICATION: PLANNING / REFERENCE — A 2026-07-24 SNAPSHOT, NOT CURRENT STATUS
>
> **Not authoritative for implementation status.** This is a planning document
> written on 2026-07-24 against `main` `71ac8fd`. It was originally described as
> "the authoritative source of truth" for what remained to a Release Candidate —
> **that description is withdrawn.** Current status lives only in
> `SEO_CONTEXT_HANDOVER.md` §0, `SEO_IMPLEMENTATION_STATUS.md` and
> `docs/markdown/MODULE_LOCKS.md`. The prioritisation and analysis below are kept as
> planning input; its point-in-time numbers and statuses are **not** kept current.
>
> **Factual status changes since this snapshot (2026-09-19; the roadmap itself is
> not redesigned):**
>
> | Snapshot statement (2026-07-24) | Now (canonical `main` `9cb3676`) |
> |---|---|
> | §4.1 / §3 / §8 step 2 — issue → recommendation gap, "P0 — highest", mock-only | **Closed on the mainline.** Recommendation Generation Stage 1 (backend RPC) and Stage 2 (frontend) are complete, locked and on `main`. Caveat: the migration `20260724130000` is **not applied to `Digi_SEO_Test`** (rolled back 2026-07-24), so TEST cannot yet exercise it. |
> | §3 — Roadmap backend, P0 | **Still open, not implemented.** A design exists (`SEO_ROADMAP_BACKEND_ARCHITECTURE.md` — design only). |
> | §1/§2.1 — "7 modules formally locked" | 9 registry entries incl. Recommendation Generation Stage 1 and Stage 2 (Competitor Benchmarking was already in the snapshot's 7). |
> | §1 — 4 frontend Vitest files | 6 files / **48 tests** (Stage 2 added two files, 15 tests); crawler-worker suite 74 tests. |
> | Migration counts (41 files, 40 on TEST) | **42** files; **40 recorded on TEST**; two not recorded — `20260720121000` SSO (deferred) and `20260724130000` Recommendation Generation (absent after rollback). |
> | Production / TEST planning "out of scope" | Unchanged: no SEO production project exists; no production rollout has occurred. |
>
> Items not listed here (Expert Support backend, placeholder routes, external
> integrations, test-coverage and documentation debt, the RC checklist) are
> unchanged **as planning items** but were not re-verified on 2026-09-19.

**Original role statement (withdrawn — see banner):** the source of truth *as of
2026-07-24* for what remained to make the
Digibility SEO Intelligence module **feature-complete**, targeting a local
Release Candidate (RC). **Explicitly out of scope by instruction:**
deployment, Cloud Run, production planning, TEST-environment planning,
CI/CD, and infrastructure — none of that is assessed or recommended here
unless a specific item is genuinely required for local development itself
(none were found to be).

**Created:** 2026-07-24. **Based on `main` commit:**
`71ac8fd0fd6087bb5435bea4cca865025bc27967` (`docs(seo): lock competitor
benchmarking module`).

**Method:** every claim below is grounded either in the authoritative
documents (read fresh from `origin/main`) or in direct source-code
inspection performed for this document (service files, RPC calls, migration
contents, route definitions, test files) — not in inference from
documentation alone. Where a documentation claim and the source code
disagreed, **the source code wins** and the discrepancy is called out
explicitly. Anything not independently confirmable is marked **UNKNOWN**.

---

## 1. Current Project Maturity

**The product is a functionally real, workflow-complete SEO platform for 12
of 18 customer-facing feature areas, with one confirmed architectural gap
connecting two of its most important locked modules (§4).** It is not a
"demo over seed data" anymore — that was true as of the 2026-07-13
`MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` assessment (superseded), but is no
longer accurate for large parts of the product:

- **Real, end-to-end, non-seeded data now exists** for the technical-audit
  pipeline: DNS-TXT domain-ownership verification (P1a) → verified-only
  crawl enqueue (P1b) → real crawl discovery/extraction → real,
  crawler-detected audit issues published to `seo_audit_issues` and
  `seo_page_inventory` (Crawler 16C–16H, migration `20260714120029`
  §"complete 29-code Audit-Issue mapping"). This did **not** exist at the
  2026-07-13 assessment and closes what that document called "blocker for
  value."
- **Real, guarded, role-gated generation RPCs** now exist and are locked for
  Reports (`seo_report_generate`) and Competitor Benchmarking
  (`seo_competitor_generate`) — both read live upstream data, persist a
  canonical row, and were verified with true two-session concurrency proofs.
- **7 modules are formally locked** in `docs/markdown/MODULE_LOCKS.md`; **6
  more pass the general completion rule but have no formal lock entry yet**
  (§2).
- **One confirmed, source-verified gap remains between two already-real
  modules:** real crawler-detected audit issues are never turned into
  `seo_recommendations` rows — that generation path is **mock-only by
  explicit design**, per its own code comment (§4.1). This means the
  Approval Queue and Content Studio workflows, while themselves fully wired,
  currently only ever see recommendation content in mock mode.
- **Two customer-facing modules (Roadmap, Expert Support) have zero backend
  code** — confirmed by direct inspection of `roadmapService.ts` and
  `supportService.ts`: neither imports `runWithServiceAdapter` nor calls
  `supabase.rpc` anywhere; every function is a `toAsync(...)` wrapper around
  a mock-store function. `src/services/supabase/` (22 files) contains **no**
  `seoRoadmapSupabaseService.ts` or `seoSupportSupabaseService.ts`.
- **4 routes are explicit, product-labeled placeholders** (Keyword Research,
  Content Gaps, Blog Briefs, Settings) — each renders `PlaceholderPage` with
  copy stating the feature "hasn't been built yet" and, for three of the
  four, points to an existing substitute inside Content Studio.
- **Test coverage is thin relative to the backend's size:** 4 frontend
  Vitest files (`routeAccess.test.ts`, `competitorService.test.ts`,
  `seoBridgeService.test.ts`, `seoCompetitorSupabaseService.test.ts`) cover
  a 22-file Supabase-service layer; 5 crawler-worker test files
  (`discovery`, `extraction`, `ownershipVerification`, `publishing`,
  `worker`) cover the crawler package. No React component-rendering tests
  exist anywhere (`vite.config.ts` sets `environment: "node"`, no
  jsdom/testing-library). Locked-module correctness rests almost entirely on
  the `supabase/test/*.sql` verification scripts and documented operator
  browser acceptance, not on frontend unit tests.

---

## 2. Every Completed Module

### 2.1 Formally locked (`docs/markdown/MODULE_LOCKS.md`)

| Module | Implementation | Testing | Lock status |
|---|---|---|---|
| Page Performance Tracker | Real Supabase reads (`seoPagePerformanceSupabaseService.ts`); generation/refresh is **mock-only by design** in every mode (no `supabase.rpc` call anywhere in its service files — confirmed) | SQL verification + operator browser acceptance (per lock evidence); no dedicated frontend unit test | **LOCKED** 2026-07-10 |
| Stage 6 — Off-Page Authority + AI Visibility | Off-Page: real reads + real guarded transition/campaign-create RPCs, role-gated. AI Visibility: real reads only; writes confirmed **mock-only** (`generateMockAiVisibilityRefresh`; no `supabase.rpc` anywhere in `seoAiVisibilitySupabaseService.ts`) | SQL verification (13+9 scenario scripts) + operator acceptance; no dedicated frontend unit test | **LOCKED** 2026-07-13 (implemented scope only) |
| Crawler 16C–16H (customer crawl UI + publishing) | Real end-to-end: request/status/cancel UI, worker lifecycle, discovery, extraction, issue detection, Page Inventory + Audit publishing (29-code issue map). **Confirmed: publishing writes to `seo_page_inventory`/`seo_audit_issues`, explicitly does NOT write `seo_recommendations`** (migration `20260714120029` line 15: `-- No seo_recommendations write.`) | Worker unit suite (5 test files) + 6 DB verification scripts + 7 operator scenarios, all PASS | **LOCKED** 2026-07-15 (implemented scope only) |
| P1a — Domain Ownership Verification (DNS-TXT) | Real, 4 guarded customer RPCs (`seo_ownership_verification_initiate`/`recheck`/`reverify`/`revoke`, confirmed via source) + isolated worker `verify-once` mode | SQL verification + real DNS lookup + operator role matrix, all PASS | **LOCKED** 2026-07-19 (implemented scope only) |
| P1b — Verified-only Crawl Enqueue Enforcement | Real `FOR SHARE`-guarded precondition inside `seo_crawl_request` | Live two-session concurrency proof + regression, all PASS | **LOCKED** 2026-07-19 |
| Reports v1 (Stages 1–3) | Real: persisted read path, guarded `seo_report_generate` RPC (confirmed via source: `reportService.ts` dispatches through `runWithServiceAdapter` to `generateSupabaseReport`), role-gated client-side PDF export via `seo_report_export_data` | SQL verification (3 scripts) + true two-session concurrency proof + operator acceptance, all PASS | **LOCKED** 2026-07-20 |
| Competitor Benchmarking (Stages 1–2) | Real: persisted read path, guarded `seo_competitor_generate` RPC, role-gated frontend (owner/admin/team_member enabled, client denied in UI **and** at the RPC) | SQL verification + live two-session concurrency proof + 33/33 vitest + 4-role authenticated operator acceptance, all PASS | **LOCKED** 2026-07-24 |

### 2.2 Informally locked (pass the general completion rule; **no formal `MODULE_LOCKS.md` entry exists yet** — flagged as documentation debt, §6)

| Module | Implementation | Testing | Lock status |
|---|---|---|---|
| Website Setup + Business Onboarding | Real reads/writes (`seoWebsiteSupabaseService.ts`, `seoBusinessOnboardingSupabaseService.ts`) | Covered indirectly by other modules' SQL fixtures; no dedicated test | Passes general rule; no formal entry |
| Technical Audit + Recommendations | **Split status — see §4.1.** Audit reads real; real completion only via the crawler path; the plain `seo_run_audit` RPC alone never completes (`auditService.ts`, confirmed by code comment in `recommendationService.ts`); recommendation generation is mock-only **by explicit design** | No dedicated frontend test | Passes general rule for its implemented scope; no formal entry |
| Approval Queue | Real reads + guarded `seo_approval_transition` RPC | No dedicated frontend test | Passes general rule; no formal entry |
| Content Studio | Real reads + guarded `seo_content_transition` RPC + section/draft workflow | No dedicated frontend test | Passes general rule; no formal entry |
| Dashboard + Admin Preview | Real aggregation reads across child modules; no writes (by design — dashboard is a summary) | No dedicated frontend test | Passes general rule; no formal entry |
| Decline Diagnosis Engine | Real reads (depends on Page Performance data); refresh stays read-only/display, no generate RPC | No dedicated frontend test | Passes general rule; no formal entry |

### 2.3 Implemented, not locked, not mock-gap (product-complete for its own scope)

| Module | Status |
|---|---|
| Customer authentication + route protection (Phase 16B) | Implemented, TEST-validated, login-only; not formally locked (deferred formalization, not a functional gap) |
| Help Center (`/help*`) | Development-complete; public, auth-free; not locked (frontend, additive) |
| Collapsible SEO Navigation IA | Implemented + verified; not locked (frontend, additive) |
| Ownership Verification UI (`OwnershipVerificationPanel`) | Implemented as part of the locked P1a scope; embedded in `WebsiteCard`, not a standalone route |

---

## 3. Every Remaining Module

Verified from the repository (route file, service files, mock-only
confirmation) — every item below was independently checked, not assumed
from documentation.

| Module | Route | Priority | Dependencies | Verified state |
|---|---|---|---|---|
| **Recommendation generation from real audit issues** _(DONE on `main` as of 2026-09-19 — Stages 1–2 locked; row below is the 2026-07-24 snapshot)_ | N/A (backend gap inside Technical Audit) | **P0 — highest** | Crawler 16C–16H (done), Stage 2 `seo_recommendations` schema (done) | Confirmed via `recommendationService.ts` code comment: mock-only by explicit design; no migration or RPC populates `seo_recommendations` from crawl-detected issues. This is the single gap connecting two already-complete modules. |
| **Roadmap backend (persistence)** | `/seo/roadmap` | **P0** | Reuses the exact pattern already proven twice (Reports Stage 2, Competitor Stage 2A/2B): guarded generation RPC + canonical persisted read | Confirmed `roadmapService.ts` has zero Supabase calls; `generateRoadmapFromFindings` reads real upstream data (audit, recommendations, decline diagnoses, off-page, AI gaps, competitor gaps — each via its own already-wired service) but **persists only to the in-memory mock store**, discarding the result in Supabase mode. This is a real, confirmed architectural gap, not a documentation gap. |
| **Expert Support backend** | `/seo/support` | **P1** | None technical; needs a product design decision first (see §7 — no architecture decision for this module exists anywhere in `SEO_DECISIONS.md`) | Confirmed `supportService.ts` has zero Supabase calls; entirely mock. |
| **AI Visibility writes + real LLM ingestion** | `/seo/ai-visibility` | **P2** | External LLM integration design (not built anywhere in the repo) | Confirmed mock-only by the Stage 6 lock's own documented scope; the "Generate" button is an explicit mock generator with a "once real AI answer tracking is connected" disclaimer already in the UI copy |
| **Page Performance real ingestion (GSC/GA4)** | `/seo/page-performance` | **P2** | External OAuth + API integration (not built anywhere) | Confirmed no `supabase.rpc` write path exists for generation; data is seeded/imported, matching the module's own UI disclaimer |
| **Decline Diagnosis real ingestion** | `/seo/decline-diagnosis` | **P2** | Depends on Page Performance real ingestion above | Confirmed read-only; "refresh recommendations" is display-only |
| **Keyword Research** | `/seo/keyword-research` | **P3 (deferred by product decision)** | None blocking — product copy states the substitute (Content Studio keyword planning) already exists | Confirmed `PlaceholderPage`, explicit "hasn't been built yet" copy |
| **Content Gaps** | `/seo/content-gaps` | **P3 (deferred by product decision)** | Largely superseded — Competitor Benchmarking (now real, locked) already surfaces competitor content gaps inside Content Studio's competitor summary, per the placeholder's own copy | Confirmed `PlaceholderPage` |
| **Blog Briefs** | `/seo/blog-briefs` | **P3 (deferred by product decision)** | None blocking — product copy states the substitute (Content Studio drafts) already exists | Confirmed `PlaceholderPage` |
| **Settings** | `/seo/settings` | **P3** | UNKNOWN what "Settings" is meant to contain — no design decision found anywhere in `SEO_DECISIONS.md` or `SEO_PROJECT_CONTEXT.md` | Confirmed `PlaceholderPage` |
| **Off-Page Authority — Campaign task-completion writes** | `/seo/off-page` (existing route) | **P2** | Touches the **locked** Stage 6 module — requires the additive-extension + evidence procedure and explicit approval per `MODULE_LOCKS.md` | Confirmed still deferred in the Stage 6 lock's own "Deferred scope" list |
| **Formal `MODULE_LOCKS.md` entries for the 6 informally-locked modules (§2.2)** | N/A | **P1 (documentation, not code)** | None | Confirmed missing — `MODULE_LOCKS.md`'s own "Other modules marked locked in `PROJECT_BOOTSTRAP.md`" section names exactly these six and states no formal entry exists |

---

## 4. Cross-Module Work Still Pending

### 4.1 The issue → recommendation gap (highest-impact finding)

> **[2026-09-19 status note]** This gap has since been **closed on `main`**
> (Recommendation Generation Stages 1–2, locked). Text below is the 2026-07-24
> finding, preserved as history.

Two already-complete, already-locked pipelines do not connect:

- **Crawler 16C–16H** produces real, non-seeded `seo_audit_issues` rows from
  actual page crawling (confirmed: migration `20260714120029`'s 29-code
  issue map, `seo_crawl_worker_publish_results`).
- **`seo_recommendations`** (Stage 2 schema, consumed by Approval Queue and
  referenced by Content Studio/Roadmap) has **no automatic population path**
  from those issues. `recommendationService.ts`'s own code comment states
  this is by design: *"Stage 2 recommendations are system/service-role
  generated (no crawler/LLM yet, and RLS excludes clients from writing
  `seo_recommendations` directly)."*

**Effect:** in Supabase mode, a real, verified, ownership-checked crawl can
produce real technical issues, but the Approval Queue — despite being fully
real and RPC-wired — has nothing real to show for that crawl unless
recommendations are populated some other way. This is the largest concrete
gap between "modules individually work" and "the product delivers its
described value end-to-end."

### 4.2 Roadmap reads real data but discards its own output

`generateRoadmapFromFindings` correctly fans out to six already-wired
services (`fetchLatestAudit`, `fetchOnPageRecommendations`,
`fetchDeclineDiagnoses`, `fetchAuthorityOpportunities`,
`fetchAiContentGaps`, `fetchCompetitorGaps`) — each of which, in Supabase
mode, returns real data where the underlying module is real. But the
generated roadmap itself is written only to `replaceRoadmapForWebsite` in
`src/mocks/roadmapMockData.ts` — there is no `seo_roadmap_items` table, no
RPC, and nothing persists across a real user's session in Supabase mode.

### 4.3 Support has no cross-module linkage at all

Unlike Roadmap, `supportService.ts` does not even read from other modules —
it is a fully self-contained mock domain with no design decision recorded
anywhere for what its real backend should look like.

### 4.4 Role-gating consistency

Every real write path checked (Reports, Competitor Benchmarking, Off-Page
Authority, Content Studio, Approval Queue, Ownership Verification) follows
the same pattern: a real `SECURITY DEFINER` RPC is the authoritative gate,
with a frontend usability layer that mirrors it. This pattern is now proven
across 3 independently-built, independently-locked modules and should be
the template for both remaining-work items in §4.1 and §4.2 — no new
architectural decision is needed for *how* to build them, only *what rules*
they encode (see §7).

---

## 5. Remaining Testing Work

- **Frontend unit-test coverage is the largest gap.** 4 test files exist
  against a 22-file Supabase-service layer and dozens of RPCs. Every other
  locked module's correctness evidence comes from `supabase/test/*.sql`
  scripts (single-transaction, self-cleaning, TEST-only) plus documented
  operator browser acceptance — a valid pattern for backend/authorization
  correctness, but it does not protect frontend dispatch logic (adapter
  wiring, role-gating math, error-surfacing) from regression the way the
  newly-added `competitorService.test.ts` / `seoCompetitorSupabaseService.test.ts`
  pattern does. **Recommendation (not yet built):** extend that same
  RPC-mock + dispatch-mock pattern to the other guarded-RPC services
  (Reports, Off-Page transitions, Content Studio transitions, Approval
  transitions, Ownership Verification) — it is a proven, low-risk pattern
  now that it exists twice.
- **No React component-rendering tests exist anywhere** in the repo
  (`vite.config.ts`: `environment: "node"`, `include: ["src/**/*.test.ts"]`
  — `.tsx` test files would not even be picked up today). Adding one would
  require introducing `jsdom` + a testing-library dependency and updating
  the vitest config — a real, but currently unscoped, decision (§7).
- **No dedicated SQL verification exists yet** for the two P0 gaps in §4
  (recommendation generation, roadmap persistence) because neither has been
  built — this is future work tied to their implementation, not a
  standalone gap today.
- **Existing SQL verification scripts should be re-run** any time a locked
  module's shared dependency changes, per each lock's own "Required after
  an approved change" section — this is standing process, not a one-time
  backlog item.

---

## 6. Remaining Documentation Work

- **Formal `MODULE_LOCKS.md` entries for the 6 informally-locked modules**
  (§2.2) — `MODULE_LOCKS.md` itself already names this gap explicitly and
  instructs: *"Add an entry the next time one of these is touched or
  reviewed, rather than inferring its file list from memory."* This is
  confirmed outstanding, low-risk documentation debt.
- **`docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`'s "Last audited" banner**
  still reads 2026-07-24 with a HEAD reference (`e00caa2`) that predates the
  Competitor Stage 2A/2B/lock work now on `main` — confirmed stale (the
  authoritative four-file package itself was correctly updated through the
  lock commit; only this index's top banner + entries for the newly-created
  files (`SEO_PRODUCTION_PROMOTION_PLAN.md`, this document,
  `COMPETITOR_STAGE2A_CONCURRENCY_VERIFICATION.md`) have not been added).
  **Not fixed in this task** — this is a planning-only document per
  instruction.
- **`MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md`** is materially superseded
  (its §0/§1/§3/§8 status claims predate Crawler 16C–16H, P1a, P1b, Reports
  v1, and Competitor Benchmarking) but has not been marked superseded or
  redirected — per `DOCUMENTATION_WORKFLOW_RULES.md` §3/§6, a future task
  should add a forward-reference banner rather than delete it (it remains a
  legitimate historical record of the 2026-07-13 decision point).
- **This document itself, `SEO_RELEASE_ROADMAP.md`, is new** and should be
  added to `PROJECT_DOCUMENTATION_INDEX.md`'s file table in a future
  documentation-sync task (not performed here, per this task's
  documentation-only, no-new-implementation-decision scope).

---

## 7. Technical Debt

- **No design decision exists anywhere in `SEO_DECISIONS.md` or
  `SEO_PROJECT_CONTEXT.md` for**: the recommendation-generation rule set
  (which of the 29 issue codes map to which recommendation, if any 1:1 at
  all, or a different aggregation), the Roadmap persistence schema, or what
  "Settings" and "Expert Support" are meant to contain. These are **product
  decisions, not implementation gaps** — building any of them without a
  decision first would risk inventing scope.
- **No React component-rendering test infrastructure** — a real, if modest,
  piece of technical debt: the current test setup can only unit-test pure
  functions and mocked-dispatch service logic, never verify a component
  actually renders correctly. This has been an accepted trade-off
  throughout the project (documented repeatedly as "verify via `tsc`/build +
  live browser checks"), not an oversight, but it remains debt relative to
  a typical frontend test pyramid.
- **`recommendationService.ts`'s mock-only design was a deliberate, correct
  choice at the time it was made** (no crawler existed yet) but is now
  **stale relative to the rest of the stack** — the crawler it was waiting
  on has since shipped and locked. This is the clearest example of debt
  created by sequencing, not by a mistake.
- **Two supabase services referenced only implicitly by the Explore-agent
  research pass turned out not to exist** (`seoRoadmapSupabaseService.ts`,
  `seoSupportSupabaseService.ts`) — confirming there is no partial/half-built
  backend for either module to build on top of; any future work starts from
  zero for both.
- **`data_provenance='estimated'` truthfulness pattern (Competitor
  Benchmarking) has no equivalent yet for Roadmap or a future
  recommendation-generation feature** — if either is built, the same
  truthful-provenance discipline established for Competitor Benchmarking
  and Reports (never claim `live`/`measured` for a heuristic) should be
  extended, not re-invented.

---

## 8. Exact Execution Order From Today Until Release Candidate

Dependency-ordered; each step only depends on what precedes it. No
deployment/infrastructure step appears anywhere in this list, per
instruction.

1. **Author formal `MODULE_LOCKS.md` entries for the 6 informally-locked
   modules** (§2.2, §6). Pure documentation; zero code risk; unblocks
   nothing technically but closes a named, self-identified gap in the
   authoritative registry before more modules are added on top of them.
2. **[DONE on `main` as of 2026-09-19 — see banner]** **Design + build the recommendation-generation pipeline** (§4.1). The
   single highest-impact remaining item — it connects two already-complete,
   already-locked modules (Crawler 16C–16H, Stage 2 Recommendations) using
   the now-proven guarded-RPC pattern. Requires one new product decision
   first (the issue→recommendation rule set, §7) before implementation.
3. **Build the Roadmap backend** (§4.2). Second-highest impact, but lower
   ambiguity than #2 — it is a direct application of the Reports
   Stage 2 / Competitor Stage 2A pattern (server-derived tenancy, advisory
   lock, canonical persisted read) with no new authorization model to
   invent. Depends on #2 only in the sense that a roadmap generated after
   #2 lands will draw on real recommendations too — but it is independently
   buildable today against the currently-real subset (audit, decline,
   off-page, AI gaps, competitor gaps).
4. **Decide and, if approved, build Expert Support's real backend** (§4.3).
   Requires a product-scope decision first (§7) — genuinely blocked on a
   decision, not on engineering sequencing.
5. **Decide the fate of the 4 placeholder routes** (§3) — for 3 of them
   (Keyword Research, Content Gaps, Blog Briefs) the product's own copy
   already states a working substitute exists; the open question is whether
   RC requires dedicated tools or whether the substitutes are sufficient.
   This is a **scope decision, not a build task** and should be resolved
   before RC sign-off either way.
6. **Extend frontend unit-test coverage** (§5) to the remaining guarded-RPC
   services, following the pattern now proven twice (Competitor
   Benchmarking). Can run in parallel with steps 2–4 once each is built —
   sequenced last here only because it depends on the new services from
   steps 2/3/4 existing to test.
7. **Re-run the full existing regression set** (every locked module's SQL
   verification + worker suite + `tsc`/`build`) as a final consolidation
   pass once steps 1–6 land, to confirm nothing regressed.
8. **Release Candidate checklist** (§9).

**External-integration items (GSC, GA4, LLM ingestion for AI Visibility) are
deliberately not sequenced into this list** — they are large, separately-scoped
product tracks (each needing its own OAuth/API design decision) rather
than a "next module" in the same sense as steps 1–6, and this document does
not assume RC requires them (see §9 for the explicit RC-scope question this
implies).

---

## 9. Release Candidate Checklist

**A genuine, honest RC decision requires resolving one scope question
first, since it changes which boxes below are required:**

> **REQUIRES OPERATOR DECISION:** does "feature-complete RC" mean (a) every
> currently-real module works correctly end-to-end including the
> recommendation/roadmap gaps closed (§8 steps 1–3), with the 4 placeholder
> routes and Expert Support explicitly out of RC scope (matching their own
> product copy), **or** (b) does RC additionally require Expert Support,
> Settings, and/or the placeholder tools to be real? This document does not
> assume an answer — the checklist below is written for interpretation (a),
> the narrower and better-evidenced reading, and should be revisited if the
> operator chooses (b).

- [ ] Every module in §2 remains passing its own existing test/verification
      evidence (no regression).
- [ ] Recommendation-generation pipeline (§4.1, §8 step 2) built, and its
      role-gating/authorization matches the established pattern (server-side
      authoritative, frontend gate presentation-only).
- [ ] Roadmap backend (§4.2, §8 step 3) built; generated roadmaps persist
      correctly in Supabase mode and mock mode remains unchanged.
- [ ] Formal `MODULE_LOCKS.md` entries authored for the 6 modules in §2.2.
- [ ] Explicit, written decision recorded for each of the 4 placeholder
      routes (§3) and for Expert Support (§4.3) — even if the decision is
      "remains deferred past RC," it must be a recorded decision, not silence.
- [ ] Frontend unit-test coverage extended to at least the two new services
      built in steps 2–3 above, following the established mock-RPC pattern.
- [ ] `npx tsc --noEmit -p tsconfig.app.json` clean.
- [ ] `npm run build` clean.
- [ ] Full `npx vitest run` clean, including any new test files added.
- [ ] `crawler-worker` test suite still passing (no regression from any
      change touching shared code).
- [ ] Every locked module's own SQL verification script still returns its
      documented `ALL PASS` / self-cleaning result on `Digi_SEO_Test` (no
      regression from schema-adjacent changes).
- [ ] No `data_provenance` mislabeling introduced anywhere new — any new
      generated/estimated data follows the same truthful-provenance
      discipline as Reports and Competitor Benchmarking.
- [ ] `docs/markdown/PROJECT_DOCUMENTATION_INDEX.md` updated to include this
      document and any other files created reaching RC.
- [ ] Explicit written confirmation of the scope decision above (interpretation
      a or b) attached to the RC sign-off record.

**This checklist does not include any deployment, hosting, CI/CD, or
production-readiness item** — those are covered separately by
`SEO_PRODUCTION_PROMOTION_PLAN.md` and are explicitly out of scope for local
RC per this task's instructions.

---

## Appendix: Documents and source read to produce this roadmap

**Documents:** `SEO_CONTEXT_HANDOVER.md`, `SEO_IMPLEMENTATION_STATUS.md`,
`SEO_PROJECT_CONTEXT.md`, `SEO_DECISIONS.md`, `docs/markdown/MODULE_LOCKS.md`,
`docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`,
`docs/markdown/MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` (historical, treated
as superseded per §6), `CURRENT_PROJECT_STATUS.md` (redirect stub, followed
to `docs/markdown/`).

**Source verified directly (not inferred from docs):** `src/routes/SeoRoutes.tsx`;
every file in `src/services/supabase/` (22 files) and `src/mocks/` (18 files);
`src/services/roadmapService.ts`, `src/services/supportService.ts`,
`src/services/recommendationService.ts`, `src/services/reportService.ts`,
`src/services/performanceService.ts`, `src/services/aiVisibilityService.ts`,
`src/services/supabase/seoOwnershipVerificationSupabaseService.ts`;
migrations `20260714120029_seo_phase16g_publishing.sql` and
`20260711120005_seo_stage2_recommendations.sql`; the placeholder pages
(`KeywordResearchPage.tsx`, `ContentGapsPage.tsx`, `BlogBriefsPage.tsx`,
`SeoSettingsPage.tsx`, `PlaceholderPage.tsx`); the full frontend and
crawler-worker test-file inventory via `find`.

**Note on research methodology:** an initial broad repository sweep was
performed by a research subagent; several of its specific claims (Roadmap
and Expert Support marked as "Supabase-backed"; Reports marked as
"reads-only"; the Ownership Verification RPC names) were found to be
**incorrect** on direct re-verification and are corrected in this document.
Only the subagent's low-inference, mechanical findings (route table, file
listings, test-file inventory, placeholder-page detection) were trusted
without re-verification; every narrative "is this wired to Supabase" claim
was independently re-checked against source before being stated here as fact.
