# Digibility SEO Help Center — Wave 3: Deferred Surfaces & Final Module Sign-Off

**Status:** COMPLETE. All four deferred contextual-help candidates received
**evidence-backed decisions**; every one was **closed without implementation**
after direct inspection. Wave 3 made **zero code changes** — it is a sign-off
wave. No locked module touched; no backend/database/migration/RPC/worker/
route/auth/mutation/status-transition/dependency change; no Cloud Run/production
contact; nothing staged, committed, or pushed. `MODULE_LOCKS.md` untouched.

## 1. Objective

Complete the Help Center contextual-help work deferred from Wave 2C — the four
"conditional" candidates — by (a) re-auditing each against current code and
locks, (b) implementing only safe, strong-fit, backward-compatible placements,
(c) explicitly closing or deferring anything that cannot be changed safely, and
(d) producing a definitive Help Center module completion decision. Per the task,
a correct evidence-based decision *not* to add a link is a valid completion.

## 2. Preflight state (fresh audit)

- **Repo:** `/Users/amitguptaamit/gitrepo/user_guide/Digibility-SEO-Module`;
  branch `main`; HEAD `0017e83` (unchanged).
- **Working tree:** 53 changed paths, all from prior approved waves (Slice 1,
  1A, Cloud Run readiness, P1a/P1b, Waves 2B/2B.5/2C). Nothing staged. No
  overlapping unreviewed change. Pre-existing work confirmed intact:
  `tsc` clean, `npm run build` clean, Wave 2C diffs present.
- **No later Help Center authority document** exists beyond the Wave 2C record.
- **Lock re-check (current `MODULE_LOCKS.md`):** none of the four candidate
  files — `roadmap/RoadmapSummaryHeader.tsx`, `competitors/CompetitorOverviewHeader.tsx`,
  `audit/AuditHeader.tsx`, `components/auth/RouteStates.tsx` — appear on any
  locked-files list. The only lock reference to the audit *parent*
  (`WebsiteAuditPage.tsx`) is specifically the `<CrawlPanel>` integration line,
  not `AuditHeader`.
- **Render-context map (each candidate has exactly one parent):**
  RoadmapSummaryHeader ← `RoadmapPage.tsx`; CompetitorOverviewHeader ←
  `CompetitorAnalysisPage.tsx`; AuditHeader ← `WebsiteAuditPage.tsx`;
  RouteStates exports (`RouteLoadingState`/`AccessRequiredState`/
  `ResolutionErrorState`) ← `ProtectedRoute.tsx` only.

## 3. Existing Help Center state (recap)

- **Wave 2B** (COMPLETE): contextual links on Websites, Business Onboarding,
  Dashboard empty state, Login (both branches); `src/help/routes.ts` created.
- **Wave 2B.5** (COMPLETE): Business Onboarding spacing normalized; 3-part
  placement guideline established.
- **Wave 2C** (COMPLETE): links on Page Optimizer, Decline Diagnosis, Reports,
  Approval Queue, 4 `PlaceholderPage` call sites, and `RouteStates.tsx`'s
  `AccessRequiredState` **module** variant. 4 candidates deferred to Wave 3.
- **`HELP_ROUTES` entries (8, all used):** `GETTING_STARTED`, `ADDING_WEBSITE`,
  `BUSINESS_ONBOARDING`, `SIGN_IN_ACCESS`, `APPROVAL_WORKFLOW`,
  `DECLINE_DIAGNOSIS`, `DIGIBILITY_OPERATING_MODEL`, `FEATURE_AVAILABILITY`.
- **Published public article inventory relevant to Wave 3:** 30 public articles.
  **There is no dedicated Roadmap, Competitor-Analysis, Technical-Audit, or
  global-admin-access article** — a decisive fact for all four candidates.

## 4. Candidate decision matrix

| # | Candidate | File | Render context | Lock | Nearby sensitive controls | Best article | Fit | Decision |
|---|---|---|---|---|---|---|---|---|
| 1 | Roadmap header | `roadmap/RoadmapSummaryHeader.tsx` | RoadmapPage (when `summary` exists) | Unlocked | "Generate / Refresh 90-Day Roadmap" mutation button in the header row; filters + `ROADMAP_SAFETY_NOTICE` below | none dedicated; operating-model article is generic (already used on Reports) | **NONE/PARTIAL** | **CLOSE** |
| 2 | Competitor header | `competitors/CompetitorOverviewHeader.tsx` | CompetitorAnalysisPage (when `overview` exists) | Unlocked | "Refresh benchmark data" mutation button in the header row; renders its own `data_source_status` mock-data line; `COMPETITOR_SAFETY_NOTICE` mock-data line directly below | none dedicated; `preview-data-versus-live-data` is generic and already delivered inline **twice** | **PARTIAL (redundant)** | **CLOSE** |
| 3 | Audit header | `audit/AuditHeader.tsx` | WebsiteAuditPage | Unlocked file, but renders **directly above the locked `<CrawlPanel>`**; audit surface is crawl-derived | mock-mode "Run Audit" mutation button in the header row; its own "Real crawler integration will come later" line | none dedicated; crawl articles describe the locked crawl workflow (belongs on the locked CrawlPanel — Wave 3 locked scope) | **NONE** | **CLOSE** |
| 4 | RouteStates admin variant | `components/auth/RouteStates.tsx` (`AccessRequiredState`, `variant="admin"`) | ProtectedRoute (global-admin gate) | Unlocked, but sensitive auth-state infra | callback buttons in `CardContent` | no public article explains **global-admin** access; `signing-in-and-access-states`/`seo-access-and-entitlements` cover **module** access only | **NONE** | **CLOSE** |

## 5. Candidates implemented

**None.** Every candidate was closed after evidence-based inspection (see §6).
This is a legitimate Wave 3 completion outcome: the task explicitly states a
correct decision not to add a link is preferable to a weak or risky placement,
and that the Help Center may be declared development-complete with candidates
intentionally not implemented, provided the decisions are documented and
evidence-based.

## 6. Candidates closed without implementation (evidence)

### 6.1 Roadmap header — CLOSE
- **No strong-fit article.** The corpus has no "what the roadmap is / how to use
  it" article. The nearest, `how-digibility-connects-insights-actions-approvals-reporting`,
  is a generic operating-model overview already surfaced on Progress Reports;
  reusing it here would be a weak, generic fit.
- **The page already sets expectations inline.** `ROADMAP_SAFETY_NOTICE` renders
  directly below the header: "This 90-day plan is a recommended sequence of next
  steps, not a guarantee of ranking or traffic improvement. Expert review is
  recommended for higher-risk actions." A generic help link would add noise, not
  guidance.
- **Placement constraint.** The header's title/description sits in a
  `flex justify-between` row with the "Generate / Refresh 90-Day Roadmap"
  mutation button; the informational left column is technically usable, but with
  no strong article the placement is moot.
- **Verdict:** closed on absence of a genuinely relevant published article.
  (Verified live: the page renders with zero `/help/*` links — the intended
  end state.)

### 6.2 Competitor header — CLOSE
- **No competitor-specific article,** and the only general candidate
  (`preview-data-versus-live-data`, the "is this data real?" honesty article)
  would be **redundant**: the competitor surface already delivers that exact
  message twice, inline —
  (a) the header renders `data_source_status` = "Mock competitor benchmarking
  data for local testing. Real competitor analysis integrations will come
  later.", and
  (b) `COMPETITOR_SAFETY_NOTICE` directly below = "These are gaps and
  opportunities based on mock data, not guarantees."
- Adding a link that says what the page already says twice is noise, not help
  (explicit close criterion).
- **Placement constraint.** "Refresh benchmark data" mutation button is in the
  header row.
- **Verdict:** closed on redundancy + absence of a competitor-specific article.
  (Verified live: both inline honesty lines confirmed on screen; zero `/help/*`
  links on the page.)

### 6.3 Audit header — CLOSE
- **No audit-specific article.** The audit surface is crawl-derived — in
  Supabase mode the page states "Start a website crawl to generate technical
  findings." Crawl help belongs on the **locked `<CrawlPanel>`** (Crawler
  16C–16H), which renders **directly below** `AuditHeader` in the same container.
  Linking crawl articles from the audit header would (a) misattribute crawl
  guidance to the audit results surface and (b) encroach on the locked module's
  natural help home (a Wave-3-locked-scope decision, out of scope here).
- **The header already carries its own honesty line** ("Mock audit for local
  testing. Real crawler integration will come later.") and a mock-mode "Run
  Audit" mutation button.
- **Risk.** Although `AuditHeader.tsx` itself is unlocked, it is the nearest
  presentational neighbour of the locked `<CrawlPanel>` integration; editing it
  for a weak-fit link is unjustified risk.
- **Verdict:** closed on absence of a strong-fit article + crawl-locked-domain
  overlap + adjacency to the locked CrawlPanel. (Verified live: header + locked
  Website-crawl panel render exactly as before; zero `/help/*` links on the
  audit page.)

### 6.4 RouteStates admin variant — CLOSE
- **No public article explains global-admin access.** `signing-in-and-access-states`
  (used by the Wave 2C **module** variant) and `seo-access-and-entitlements`
  both describe **SEO-module** access — "your account doesn't have access to the
  SEO module yet" — not the internal global-admin capability the admin variant
  gates ("this area requires global-admin access"). Pointing the admin state at
  a module-access article would misinform the user.
- Global-admin is an internal/operational concept; there is intentionally no
  customer-facing article for it, and creating one is out of scope.
- The **module** variant is already served (Wave 2C); the admin variant is
  correctly link-less via the existing `{!isAdmin && (...)}` gate.
- **Verdict:** closed on absence of a genuinely relevant public article for the
  global-admin state. (Confirmed by code: the help link is gated to the
  non-admin branch in `RouteStates.tsx`; the admin variant renders no link.)

## 7. Candidates still deferred (open, non-blocking)

None left ambiguous. The four candidates are **closed**, not deferred — each has
a definitive evidence-backed decision. If a future, separately-approved task
authors dedicated Roadmap / Competitor-Analysis / Technical-Audit / global-admin
articles (new content is out of scope here), these surfaces could be revisited;
that is a content-authoring prerequisite, not an open implementation item.

## Future Expansion Triggers

The four candidates closed in §6 (Roadmap header, Competitor Overview header,
Audit Header, RouteStates admin variant) are **closed for today's conditions**,
not closed forever. They should be **re-evaluated** — not automatically
re-implemented — only when one or more of the following occurs:

1. A dedicated published public **Roadmap** Help article is created.
2. A dedicated published public **Competitor Analysis** Help article is created.
3. A dedicated published public **Technical Audit** Help article is created.
4. A dedicated published public **Platform Admin / Permissions** Help article is
   created (covering global-admin access specifically, distinct from the
   existing SEO-module-access articles).
5. The `<CrawlPanel>` or the relevant crawl UX scope becomes formally unlocked
   for contextual-help improvements (today it is locked under Crawler
   16C–16H — see `MODULE_LOCKS.md`).
6. The underlying page's UX materially changes such that its current inline
   safety/honesty messaging (e.g. `ROADMAP_SAFETY_NOTICE`,
   `COMPETITOR_SAFETY_NOTICE`, the audit header's mock-crawler-integration
   line) no longer sufficiently explains the feature on its own.
7. User research, support-ticket data, or accessibility testing demonstrates a
   specific, evidenced, unmet help need on one of these four surfaces.

**Re-evaluation is not a commitment to implement.** If and when one of these
triggers occurs, the same decision rules used in Wave 3 still apply in full:

- the target file and sub-scope must still be unlocked;
- the destination article must still be published, public, and a **strong**
  fit — a generic or only-weakly-related article must not be used merely to
  add coverage where none currently exists;
- the placement must remain purely presentational, outside mutation
  controls, filters, exports, status actions, role switches, and
  auth-resolution logic;
- the change must remain backward compatible and use `HELP_ROUTES`
  constants, never a raw `/help/article/...` literal;
- any change touching a locked file or a locked integration line must follow
  that module's own additive-extension/unlock procedure and get separate,
  explicit approval;
- the module's existing regression suite (and, for locked surfaces, the
  targeted locked-scope regression required by `MODULE_LOCKS.md`) must pass
  before and after the change.

A correct decision to continue deferring is still preferable to a weak or
risky placement, even after a trigger occurs.

## 8. Article mappings

No new article mappings — Wave 3 implemented no links. Existing Wave 2B/2C
mappings are unchanged.

## 9. `HELP_ROUTES` changes

None. `src/help/routes.ts` is unchanged (no new placement → no new route). All 8
existing entries remain used.

## 10. Placement rationale

Not applicable — no link was placed. §6 documents, per candidate, why each
placement was declined.

## 11. Shared-component API changes

None. `PlaceholderPage.tsx`'s Wave 2C optional `helpRoute`/`helpLabel` API is
unchanged; `RouteStates.tsx` is unchanged from its Wave 2C state (module-variant
link only, admin variant gated off).

## 12. Backward-compatibility evidence

Trivially preserved — zero code changed in Wave 3. `git diff` confirms the three
header candidate files have no diff at all, and `RouteStates.tsx` shows only the
pre-existing Wave 2C insertion. `tsc` and `build` remain clean; content
validation remains PASS with the identical 31/30/1/10 counts.

## 13. Accessibility behavior

No new interactive elements were added, so no new accessibility surface. The
existing Wave 2B/2C contextual links retain their shared class string with
visible `focus-visible` ring classes. (Unchanged, previously-disclosed
limitation: no connected hardware browser was available for a physical-keyboard
`:focus-visible` walkthrough; class-level focus behavior is confirmed present.)

## 14. Verification results

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.app.json` | **PASS** (0 errors) |
| `npm run build` | **PASS** (only the pre-existing chunk-size advisory) |
| Help Center content validation (`/help/dev/content-check`) | **PASS — 0 findings**, 31 total / 30 public / 1 internal / 10 categories (unchanged) |
| Roadmap page renders with no contextual link | **PASS** (live: `a[href^="/help/"]` count = 0; screenshot confirms header + `ROADMAP_SAFETY_NOTICE`) |
| Competitor page renders with no contextual link | **PASS** (live: both inline mock-data honesty lines confirmed; no `/help/*` link) |
| Audit page renders with no contextual link; locked CrawlPanel intact | **PASS** (live: header + "Website crawl" locked panel render as before; no `/help/*` link) |
| RouteStates admin variant link-less | **PASS** (code: `{!isAdmin && (...)}` gate; admin branch renders no link) |
| No console errors | **PASS** (mock-mode preview across Roadmap/Competitor/Audit) |
| Protected `/seo/*` still redirects signed-out | **PASS** (`/seo/roadmap` → `/seo/login?returnTo=%2Fseo%2Froadmap` on the Supabase-mode server) |
| Public Help Center article reachable signed-out | **PASS** (`/help/article/the-approval-workflow` loads, `<h1>` = "The approval workflow", no redirect) |
| Every `HELP_ROUTES` entry used | **PASS** (unchanged from Wave 2C) |
| No raw `/help/article/...` literal added | **PASS** (no code changed) |
| No internal article referenced | **PASS** |
| No locked file changed | **PASS** (re-checked all four candidate files against every `MODULE_LOCKS.md` list) |

## 15. Lock-boundary verification

Re-checked against current `MODULE_LOCKS.md`: none of the four candidate files
is on any locked-files list. Wave 3 changed none of them anyway. The locked
`<CrawlPanel>` integration in `WebsiteAuditPage.tsx` is untouched; the audit
header decision explicitly *avoided* it. `MODULE_LOCKS.md` itself is unchanged
(no typo correction was needed).

## 16. Known limitations

- **No physical-keyboard focus walkthrough** (no connected hardware browser) —
  unchanged from every prior wave; class-level focus styling confirmed.
- **RouteStates variants could not be triggered via a live auth session** (no
  TEST credentials in this environment) — the admin-variant close is verified by
  code (the `{!isAdmin && ...}` gate) rather than by rendering the live
  admin-denied state.
- **Four surfaces intentionally lack contextual help** (Roadmap, Competitor,
  Audit headers; global-admin access state) — by evidence-backed decision, not
  oversight. Each becomes eligible only if dedicated articles are later authored
  (out of scope here).

## 17. Cloud Run runtime verification — still deferred

Unchanged: the repo-root container config (`Dockerfile`,
`docker/nginx.conf.template`, `.dockerignore`) was statically verified in an
earlier slice, but **no actual container build/run/HTTP verification has been
performed** (Docker unavailable in that environment). Wave 3 did not touch or
re-attempt it. It remains deferred to the TEST promotion gate and is **not**
represented as completed.

## 18. Final Help Center completion decision

**The Digibility SEO Help Center is DEVELOPMENT-COMPLETE.**

- Public foundation (Slice 1) + Decline Diagnosis completion (Slice 1A):
  complete and verified — 30 public + 1 internal articles, hand-rolled search,
  content-integrity validation, auth-free public routes.
- Contextual-help rollout: complete across every **safe, unlocked, strong-fit**
  surface (Waves 2B / 2B.5 / 2C), following a documented placement guideline and
  a single shared, `HELP_ROUTES`-backed link pattern.
- Wave 3: all four remaining deferred candidates closed with evidence; no
  ambiguous candidate remains; no lock weakened.

**Intentionally not implemented (documented, evidence-based):** contextual links
on the Roadmap, Competitor Analysis, and Technical Audit headers, and on the
global-admin access state — each lacking a genuinely relevant published public
article and/or already communicating its message inline, and (for Audit) sitting
in the locked crawl domain.

**Explicitly still outside "Help Center development-complete":**
- **Wave-3 locked-module contextual links** (P1a ownership-verification panel,
  Crawler 16C–16H crawl UI, Page Performance page, Stage 6 Off-Page /
  Campaigns / AI Visibility) remain a **separate, future, per-module effort**,
  each requiring its own approval and that module's regression suite. This
  Wave 3 sign-off does **not** cover them; it covers the deferred *unlocked*
  candidates only.
- **Cloud Run runtime verification** (§17) — deferred to the TEST promotion gate.
- **Help Drawer, analytics, CMS, grounded AI assistant** — explicitly out of
  scope for the whole Help Center initiative to date.
