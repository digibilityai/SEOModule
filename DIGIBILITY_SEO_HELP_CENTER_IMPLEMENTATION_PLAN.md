# Digibility SEO — Help Center Implementation Plan

> **DRAFT (Phase 1) — not authoritative.** Implementation architecture, routes,
> content schema, search, components, services, risk-sequenced rollout, lock
> analysis, backward-compat, testing, and slices. Grounded in the verified repo.
> No code/DB/production changed. `CURRENT_PROJECT_STATUS.md` controls status;
> `MODULE_LOCKS.md` controls scope.

## 1. Current-state audit

- **`/seo/support`:** `ExpertSupportPage` → `supportService` = **MOCK-ONLY**
  (`supportMockData` + `toAsync`; no Supabase). Create/comment/cancel/status flow
  writes nothing to Supabase. Route + sidebar "Expert Support Desk" exist.
- **Routing/nav:** `SeoRoutes.tsx` (React Router v6, `BrowserRouter`), `Layout` =
  Sidebar + Header; `ProtectedRoute` (Supabase-mode gating; mock bypass);
  `moduleRegistry.ts` drives sidebar modules.
- **Reusable UI:** `src/components/ui/` = badge, button, card, input, label,
  select, separator, skeleton, textarea. **No** dialog/drawer/sheet/tooltip/
  popover/command/tabs/accordion/breadcrumb — the codebase hand-builds these.
- **Service adapter:** `runWithServiceAdapter` + `isMockMode`/`isSupabaseMode`
  (`serviceAdapter.ts`, `runtimeConfig.ts`).
- **Search capability:** none. No `Fuse`/`cmdk`/`minisearch`/`lunr`/`flexsearch`,
  no markdown renderer. Deps: `@tanstack/react-query`, `react-router-dom`, a few
  Radix primitives.
- **Backend content tables:** **none** (`seo_help_*`/`tutorial`/`knowledge_base`
  do not exist). `seo_usage_events` exists (Stage 1) but is not wired for
  analytics.
- **Locked files likely near contextual links:** ownership panel (P1a), crawl UI
  (16C–16H), Page Performance page (Page Perf lock), Off-Page/Campaign/AI
  Visibility (Stage 6). The **Help Center itself touches none of these.**
- **Testing capability:** no frontend unit/lint framework in the repo (per prior
  sign-offs); `tsc`/`build` + operator/browser validation are the current bars.
  → the plan proposes **pure, testable helper modules** (search/index) even if a
  test runner must be added minimally for them.

## 2. Recommended architecture

Confirmed model: **browser → Supabase direct, RLS + guarded RPCs authoritative;
no BFF.** Help content is **static, read-only, non-personal** → it needs no RLS,
no RPC, no network.

- **Option A — bundled TS/JSON/Markdown + client-side index.** Simple, offline,
  mock-compatible, versioned, no DB. Con: content updates ship with the app.
- **Option B — Supabase content tables + RLS reads + admin publishing.** Powerful
  later; over-built for MVP; adds migrations, RLS, a publishing surface, and a
  network dependency that breaks the "mock mode = no Supabase" guarantee for help.
- **Option C — hybrid: version-controlled TS content for MVP + a generated
  in-memory search index, with a clean service seam for a future Supabase/CMS
  migration.** ✅ **Primary recommendation.**

**Why C.** *Scalability:* corpus is small (≈50 articles) — a bundled typed corpus
+ in-memory index is instant and cache-friendly. *Authoring:* content as typed
objects (title/summary/steps/etc.) is XSS-safe by construction (no markdown/HTML
injection) and reviewable in PRs. *Version control:* content lives with code and
locks to a product version. *Search:* fully client-side (§5), no SaaS. *Content
updates:* a content-only PR (low risk, no migration). *Mock mode:* identical in
mock and Supabase (no network) — preserves the permanent-mock guarantee.
*Security:* nothing sensitive is stored/indexed. *Deployment:* ships with the
frontend; no infra. *Future AI:* the same published corpus becomes the grounding
source for a Phase-3 assistant; the service seam allows swapping the repository to
Supabase/CMS without changing consumers.

## 3. Proposed route structure

| Route | Purpose |
|---|---|
| `/seo/help` | Help Center home (Spec §4) |
| `/seo/help/search` | Full search results (also inline on home) |
| `/seo/help/category/:categorySlug` | Category index |
| `/seo/help/article/:articleSlug` | Article (supports `#anchor`) |
| `/seo/help/learning-path/:pathSlug` | Learning path |
| `/seo/help/videos` | Video library (Phase 2 content) |
| `/seo/help/contact` | Escalation → reuses/links `/seo/support` |

**`/seo/support` compatibility:** **unchanged** (preserved verbatim). Add a
"Browse the Help Center" link on it and a "Contact support" link from Help. No
redirect (backward compatible). Help routes are **auth-only** `ProtectedRoute`
(no `requireWebsite`) so help is reachable even before setup; mock mode bypasses
as usual.

## 4. Proposed content schema (typed `HelpArticle`)

```
id · slug · title · summary · body (structured blocks: paragraph|steps|note|
  table|callout — NO raw HTML) · category · subcategory · contentType · audienceRoles[]
  · productArea · featureStatus (Available | Available on TEST | Preview | Demo data
  | Mock-only | Coming later | Internal only) · level · estimatedTime · tags[]
  · aliases[] (search synonyms/questions) · relatedIds[] · relevantRoutes[]
  · contextualStates[] (e.g., crawl:queued) · videoUrl? · lastReviewed · nextReview?
  · productVersion · priority · published (bool) · supportEscalationType
```
Same shape whether later stored in Supabase; MVP ships it as a typed constant
corpus. Article status (Draft/In review/Published/Needs update/Archived) is a
governance field; only `published:true` articles are indexed.

## 5. Search architecture (MVP, client-side)

- **Indexing:** build an in-memory inverted index from the corpus at load
  (memoized). **Assess before adding a dep:** none installed. Recommend **either**
  a hand-rolled tokenized weighted index (zero new deps) **or** a tiny, well-
  scoped library (**MiniSearch** ~ small, no SaaS, typo + field weighting) — pick
  during the search slice; **no external SaaS** either way.
- **Tokenization:** lowercase, split on non-alphanumeric, keep status tokens
  intact (e.g., `retry_wait`).
- **Normalization:** lowercase, strip punctuation, basic stemming (optional).
- **Typo handling:** edit-distance ≤1 for tokens ≥4 chars (or MiniSearch fuzzy).
- **Synonym expansion:** expand the query via the IA §4 alias map before matching.
- **Weighted fields:** title/aliases/summary/tags/body per Spec §5.2; context/role/
  popularity/freshness boosts.
- **Result grouping:** by category/product area; show top per group + "more".
- **Query suggestions:** prefix-match titles + aliases (autocomplete).
- **No-result behaviour:** show suggested categories + "Contact support"; record
  (Phase 2) the query for zero-result analytics.
- **Article anchors:** deep-link `#anchor` to sections/statuses.
- **Performance budget:** index build < ~50ms for ~50 articles; search < ~10ms;
  all in-memory, no network.
- **Accessibility:** results in a labelled list; `aria-live` count; keyboard nav.
- **Test approach:** pure functions (tokenize/normalize/expand/rank) unit-tested
  with fixtures incl. synonym + typo + zero-result cases.

## 6. Component architecture (proposals; validate against conventions)

`HelpCenterPage` · `HelpSearch` · `HelpSearchResults` · `HelpCategoryGrid` ·
`HelpArticlePage` · `HelpArticleCard` · `HelpBreadcrumbs` · `HelpArticleFeedback`
· `HelpLearningPath` · `ContextualHelpLink` (the shared, reusable link used across
the app) · `HelpDrawer` (Phase 2) · `FeatureAvailabilityBadge` (built on existing
`Badge`) · `RelatedArticles` · `ContactSupportPanel`. All render structured
content blocks (no raw HTML) using existing primitives (Card/Badge/Button/Input/
Separator/Skeleton).

## 7. Service architecture

- **`helpContentRepository`** — returns the bundled corpus (MVP) behind a seam so
  a future Supabase/CMS source can replace it without changing callers. No network
  in MVP.
- **`helpSearchService`** — builds/queries the in-memory index.
- **`contextToArticleResolver`** — maps `{route, status, role}` → article/anchor
  (drives contextual links + drawer suggestions), from the §File-3 map.
- **`helpAnalyticsAdapter`** — a no-op stub in MVP (event names only; §11); a real
  sink is Phase 2.
- **Mock compatibility:** all of the above are pure/bundled → **identical in mock
  and Supabase**, preserving permanent mock mode; help works with zero Supabase
  calls.

## 8. Contextual-help rollout (by risk)

### Wave 1 — Help Center only (no locked module touched)
- **Files:** new `src/pages/seo/help/**`, `src/help/**` (corpus + search +
  resolver), new routes in `SeoRoutes.tsx` (additive), a new `ContextualHelpLink`.
- **Lock implications:** none (all new files; `SeoRoutes.tsx` addition is additive
  and not a locked file).
- **Tests:** search units; route renders; article render; invalid-slug fallback.
- **Rollback:** delete new files + revert the additive route lines.
- **Acceptance:** home/category/article/search work in mock + Supabase; `/seo/
  support` unchanged.

### Wave 2 — unlocked/shared nav + low-risk pages
- **Files:** `Sidebar.tsx` (+1 Help entry), optional `Header.tsx` help link;
  `ContextualHelpLink` added to **non-locked** pages (websites, onboarding,
  dashboard, approvals, page-optimizer, settings, support, competitors, roadmap,
  reports, placeholders, ProtectedRoute states).
- **Lock implications:** Sidebar/Header are shared but **not** in a lock registry —
  additive link only, preserve existing nav/sign-out.
- **Tests:** nav renders; links resolve to correct articles; sign-out unaffected.
- **Rollback:** revert per-file additive lines.
- **Acceptance:** every non-locked page exposes correct contextual help.

### Wave 3 — locked-module contextual links (separate approvals, per module)
- **Modules (each its own approval + regression):** P1a ownership panel; Crawler
  16C–16H crawl UI; Page Performance page; Stage 6 Off-Page/Campaigns/AI
  Visibility.
- **Files:** the specific locked components (add ONE `ContextualHelpLink` /
  status link each; **display-only**).
- **Lock implications:** each is an **additive change to a locked file** → follow
  that lock's procedure (state file, name preserved behaviour, run targeted
  locked-scope regression, get approval).
- **Tests:** the module's existing regression (DB verifications + worker suite +
  relevant browser checks) must remain PASS; plus link-target correctness.
- **Rollback:** revert the single added link per file.
- **Acceptance:** locked behaviour byte-unchanged except the added link; regression
  green.

### Wave 4 — Help Drawer + feedback + analytics
- **Files:** `HelpDrawer` (built from scratch), `HelpArticleFeedback` wiring, a
  real analytics sink.
- **Lock implications:** none (new components; drawer mounts globally in the shell).
- **Tests:** focus trap/Esc/mobile; feedback local store; analytics payload safety.
- **Rollback:** feature-flag off / remove drawer mount.
- **Acceptance:** drawer works in mock + Supabase; no sensitive data in events.

## 9. Module-lock analysis

| Lock | Locked behaviour to preserve | Smallest additive change | Owner doc to update | Required regression | Approval gate |
|---|---|---|---|---|---|
| **Page Performance** | fetch/adapter/fallback + refresh-race fix; service signatures; query timing | one header help link + metric-label anchors (display only) | `PHASE_14A_...NOTES.md` | Page-Performance smoke + browser render | Wave 3, explicit |
| **Crawler 16C–16H** | crawl RPC/status/polling/query keys/customer-safe columns; `StartCrawlControl`/`CrawlPanel`/status card | one help link in panel header + "what does this mean?" beside badge | `PHASE_16H_...SIGNOFF.md` | `seo_phase16c/d/e/f/g/h` verifications + worker 74/74 + browser | Wave 3, explicit |
| **P1a (ownership)** | double-submit lock, states, Step-2A RPCs, no token exposure | one help link in the panel section header + status link | `P1A_..._SIGNOFF.md` | P1a Step 1/2A/2B + Step 3 SQL + browser | Wave 3, explicit |
| **P1b** | server-only `seo_crawl_request` guard (no UI) | **none** — P1b has no UI; the crawl help copy explains the rejection | — | n/a | n/a |
| **Stage 6** | opportunity/campaign transition RPCs, role gates, `RoleGateTooltip`, AI read behaviour | help links in headers + status links; **do not edit `RoleGateTooltip`** | `STAGE_6_...`, `PHASE_15C/15D` | Stage 6 smoke/create/transition + browser | Wave 3, explicit |

**Explicit:** "adding only a link" to any of the above **is not exempt** from the
lock.

## 10. Backward compatibility

Preserved: all existing routes (Help routes are additive); `/seo/support`
unchanged (no redirect); role values; Supabase RPCs; DB schema (**no migration**);
service signatures; query keys; `ActiveWebsiteContext`; permanent mock mode
(help works with zero Supabase calls); existing UI patterns; loading/error states;
**all locked behaviour** (Waves 1–2 touch no locked file; Wave 3 is additive per
lock procedure).

## 11. Search & content analytics plan (events designed only)

Events: `help_center_opened`, `help_search_submitted`, `help_search_zero_results`,
`help_search_result_clicked`, `contextual_help_clicked`, `help_article_viewed`,
`help_article_helpful`, `help_article_not_helpful`, `help_contact_support_started`,
`help_contact_support_submitted`.
**Safe payload:** article id/slug, category, product area, route, role (advisory),
search query text (user-typed help queries only), result count, helpful bool +
optional reason. **Prohibited payload:** passwords, service-role keys, DNS
challenge/TXT values, lease tokens, internal diagnostics, raw network bodies,
active-website *contents* (id only if policy allows), any customer PII beyond the
above. **No analytics is implemented in MVP.**

## 12. Security and privacy

No article contains secrets; no DNS token is authored/indexed (aliases reference
the *concept* "token", never a value); no password/service-role data; no raw
network body captured; role context is **advisory for relevance, not authority**
(RLS/RPC remain authoritative); internal-only content (A36 runbook) is separated
and not shown to customers; user-typed search text is treated as untrusted (no
injection into markup); **article rendering is XSS-safe by construction** (typed
content blocks, no `dangerouslySetInnerHTML`); external links use
`rel="noopener noreferrer"` + `target="_blank"`; screenshots follow the blur rules
(emails, tokens, secret-looking ids).

## 13. SEO/indexability of the Help Center

- **Current TEST/private module:** **authenticated-only + `noindex`.** Help lives
  behind `/seo/*` and reflects a preview build; it should not be publicly indexable
  yet (avoids implying preview features are live to the open web).
- **Future production:** a **partially public** documentation site (concept/academy
  + generic how-tos) on a docs domain is a reasonable **business decision** once
  the module is production-promoted — deferred; not part of MVP.

## 14. Testing plan

`tsc`/`build`; route renders (home/category/article/search/contact); search unit
tests (tokenize/normalize/synonym-expand/rank/typo/zero-result); synonym-map
tests; keyboard/accessibility (focus order, `aria-live`, semantic headings);
responsive (mobile nav + full-width search); role-aware recommendation selection;
feature-status label correctness (matches status doc); contextual-link route/anchor
correctness (resolver map); invalid/stale article-id fallback (graceful "not
found" → home/search); mock-mode parity (help works with zero Supabase);
sign-out/session isolation (recently-viewed is user-scoped, cleared on user
change); **locked-module regressions for any Wave-3 link** (per §9).

## 15. Acceptance criteria

- **Home:** all 12 blocks render; search focilable; status notice present.
- **Categories:** every category (A–T) reachable; articles listed.
- **Article:** renders all metadata + status badge + related + feedback + escalate;
  invalid slug → graceful fallback.
- **Search:** as-you-type; typo tolerance; synonyms; NL questions match; grouped
  results; zero-result recovery; keyboard nav; highlighted matches.
- **Contextual links:** each mapped route/status opens the correct article/anchor
  (not the home).
- **Role relevance:** role-scoped recommendations differ appropriately; no role
  used as authorization.
- **Status honesty:** every seeded/mock/preview/placeholder/deferred article shows
  the correct feature-availability label; no content implies unbuilt features are
  live.
- **Responsive + accessibility:** passes keyboard + reduced-motion + mobile checks.
- **Feedback + escalation:** helpful/not-helpful recorded (local MVP); "Contact
  support" carries only safe context.
- **Backward compatibility:** `/seo/support` unchanged; no route/role/RPC/schema
  change; mock mode intact.
- **Zero production impact:** TEST-only; no migration; no production contact.

## 16. Implementation slices (smallest safe sequence + recommended model)

| # | Slice | Touches locked? | Recommended model | Why |
|---|---|---|---|---|
| 1 | Content schema + starter corpus (P0 articles: A01–A16 + N01/N03/N05/N08) | no | **Sonnet 5** | well-specified content + typed schema |
| 2 | Search utilities + tests (tokenize/normalize/synonyms/rank) | no | **Opus 4.6** | correctness-critical pure logic |
| 3 | Help routes + pages (home/category/article/search/contact) | no | **Sonnet 5** | UI assembly from existing primitives |
| 4 | Nav + `/seo/support` compatibility link | no (shared, additive) | **Sonnet 4.6** | small additive nav edit |
| 5 | `ContextualHelpLink` shared component + resolver | no | **Sonnet 5** | reusable + resolver map |
| 6 | Unlocked-page contextual links (Wave 2) | no | **Sonnet 4.6** | many small additive edits |
| 7 | Locked-page links, per module, separately approved (Wave 3) | **yes** | **Opus 4.8** | locked-boundary + regression judgment |
| 8 | Feedback + analytics stub | no | **Sonnet 5** | payload-safety care |
| 9 | Help Drawer (Phase 2) | no | **Opus 4.6** | focus-trap/mobile/a11y from scratch |
| 10 | Grounded AI assistant (Phase 3) | no (additive) | **Opus 4.8** | grounding/safety design |

## 17. Exact next implementation step (after approval)

**Slice 1 + 2 combined as the foundation is tempting, but keep them separate.**
Recommended first slice: **Slice 1 — the `HelpArticle` content schema + a
representative P0 starter corpus (Getting started, Sign in, Add a website, Verify
ownership, Crawl how-to + statuses + "why queued", the honesty articles N01/N03/
N05/N08, Roles, Approvals) as version-controlled typed content**, with a couple of
pure helper stubs and their tests.

It:
- creates the Help Center foundation (content + schema + seam);
- touches **no locked module** and **no existing page**;
- preserves `/seo/support` untouched;
- introduces **no database migration** (bundled content);
- includes representative starter content spanning operational + honesty topics;
- includes the first search-helper unit tests;
- is independently reviewable and fully reversible (delete new files).

Recommended model for Slice 1: **Sonnet 5**. Search logic (Slice 2) that follows:
**Opus 4.6**.
