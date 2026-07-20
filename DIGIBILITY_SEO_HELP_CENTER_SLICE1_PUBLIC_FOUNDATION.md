# Digibility SEO Help Center — Slice 1: Public Static Foundation (implementation record)

**Status:** `IMPLEMENTED + type/build-verified + browser-verified (dev server); NOT committed`.
**Scope:** Slice 1 only — the public, authentication-free Help Center foundation: content
model, P0+academy starter corpus, client-side search, public routes/pages, and
low-risk navigation/support compatibility links. No contextual links added to
other SEO module screens; no Help Drawer; no analytics; no CMS; no grounded AI
assistant. No locked module was touched. No database/backend/worker/production
change of any kind.

---

## 1. Scope

Implements Slice 1 of `DIGIBILITY_SEO_HELP_CENTER_IMPLEMENTATION_PLAN.md` (Wave
1): a standalone, public Help Center reachable at `/help*`, entirely outside the
authenticated `/seo/*` route boundary, built on bundled TypeScript content and a
hand-rolled client-side search index (Option C from the plan — no MiniSearch/
Fuse/Lunr/cmdk, no Markdown, no Supabase content tables, no external search
service).

## 2. Public architecture / authentication boundary

The Help Center renders identically whether the visitor is signed in, signed
out, Supabase config is present or absent, and regardless of workspace/website/
role/entitlement state. This was verified by direct code audit and live testing:

- **No auth/session hooks imported anywhere under `src/help/**` or
  `src/pages/help/**`** — confirmed by `grep` for `useAuth`, `useSeoAccess`,
  `useResolvedActiveWebsite`, `useActiveWebsite`, `getCurrentSeoRole`, and any
  import from `@/hooks`, `@/contexts`, or `@/services/supabase`: zero real hits
  (the only matches were comment text/regex-pattern strings, not code).
- **No `ProtectedRoute` wrapper** on any `/help*` route in `SeoRoutes.tsx`.
- **No Supabase network request** while browsing/searching — confirmed via the
  browser Network panel on the live dev server: zero requests to any Supabase
  host while loading the homepage, an article, and a search.
- The Help Center is still mounted inside the app's top-level
  `QueryClientProvider`/`AuthProvider`/`ActiveWebsiteProvider`/`BrowserRouter`
  tree (unavoidable — there is one router in `App.tsx`), but this is provably
  harmless: `src/integrations/supabase/client.ts` falls back to a placeholder
  URL/key and never throws without env vars, and `AuthContext`'s
  `onAuthStateChange`/`runtimeConfig.ts` never block or redirect on mount. Help
  pages simply never call any hook that would read from those providers.
- **Verified live:** `/seo/dashboard` (a real protected route) still correctly
  redirects a signed-out session to `/seo/login?returnTo=%2Fseo%2Fdashboard` in
  this environment's `VITE_SEO_DATA_MODE=supabase` setting — proving protected
  routes remain fully protected and unaffected by this change.

## 3. Public shell

`src/pages/help/HelpShell.tsx` — a standalone header/main/footer layout, **not**
built on `Layout`/`Sidebar`/`Header` (the authenticated app shell). Contains:
Digibility branding, Help Center title, nav (Help Center / Contact Support /
Sign in), a skip-to-content link, and a footer with the same links. Adds a
`noindex, nofollow` `<meta name="robots">` tag while mounted (removed on
unmount) — no new dependency (no react-helmet); a plain `useEffect` DOM mutation.
Contains **no** workspace/website selector, no user-specific header, no sign-out
action, no role-dependent controls, and no customer data.

## 4. Content model

`src/help/types.ts` defines `HelpArticle` with all required fields (id, slug,
title, summary, structured `body` blocks, category, subcategory, contentType,
audienceRoles, level, productArea, `featureStatus`, estimatedReadingMinutes,
tags, searchAliases, relatedArticleIds, relevantRoutes, contextualStates,
priority, lastReviewed, version, published, `visibility`, supportEscalationType,
externalReviewRequired, video). Body content is a closed union of safe block
types (`paragraph`/`heading`/`steps`/`list`/`callout`/`warning`/`statusNotice`/
`definition`/`table`/`relatedLink`/`expectedResult`/`troubleshootingNote`/
`escalationNote`) — never raw HTML.

## 5. Public/internal visibility model

`publicArticles()` in `src/help/content/index.ts` is the **single** boundary
function: `published === true && visibility === "public"`. Every public-facing
consumer (homepage, category page, article page, search) goes through it or a
helper built on it — never `ALL_ARTICLES` directly. One internal-only article
(`support-diagnostic-runbook-internal`) exists specifically to prove this
boundary end-to-end.

**Verified live:** navigating directly to
`/help/article/support-diagnostic-runbook-internal` renders the exact same
"We couldn't find that page" state as a genuinely unknown slug
(`/help/article/totally-unknown-slug-xyz`) and an unknown category
(`/help/category/does-not-exist`) — a public visitor cannot distinguish
"doesn't exist" from "exists but is internal."

## 6. Starter corpus

**30 total articles: 29 public + 1 internal**, across **9 categories**
(Start Here, Learn SEO/AEO/GEO, Set Up Digibility SEO, Websites & Ownership,
Website Crawling, Recommendations/Approvals & Roles, Troubleshooting, Feature
Availability, Contact Support).

- **P0 core (18 required):** getting started, signing in/access states, SEO
  access/entitlements, workspaces/active website, adding a website, business
  onboarding, verifying domain ownership, why ownership stays pending,
  protecting the DNS token, starting/monitoring a crawl, understanding crawl
  statuses, why a crawl is rejected (unverified ownership), why a crawl may stay
  queued, the approval workflow, roles and permissions, preview vs live data,
  troubleshooting overview, contacting support safely — **all 18 present**.
- **SEO/AEO/GEO academy (10 required):** what SEO/AEO/GEO are, how they work
  together, business goals, technical/content/authority/measurement pillars, how
  Digibility connects it all, why fragmented workflows create problems, how
  Digibility complements teams/freelancers/agencies — **all 10 present**, plus
  one extra honesty stub (`ai-visibility-data-is-seeded`) referenced by "What GEO
  is" to keep that related link resolvable within Slice 1's scope.
- **External-review flags:** `what-aeo-is`, `what-geo-is`, and
  `how-seo-aeo-geo-work-together` are marked `externalReviewRequired: true` and
  carry an in-body caveat disclaiming any proprietary-algorithm claim.
- **Honesty content rules followed:** no claim that the crawler worker is
  continuously deployed (explicit "Coming later" article); no claim seeded
  metrics are live GSC/GA4 (explicit article + `demo_data`/`available_on_test`
  labels throughout); no claim seeded AI Visibility is live model intelligence;
  no claim mock reports are real; no DNS challenge value included anywhere; no
  internal RPC/table names in customer-facing text; no disparagement of
  freelancers/agencies — approved phrasing ("Digibility is designed to…",
  "Compared with workflows that rely on separate spreadsheets…") used
  throughout the positioning articles.

## 7. Search design

`src/help/search.ts` — pure, deterministic, in-memory, hand-rolled (no
dependency added). Normalizes (lowercase, diacritic-strip, punctuation-safe,
whitespace-normalize), tokenizes, expands the exact required synonym list
(`src/help/synonyms.ts`, phrase-level, longest-match-first), filters English
stopwords **from the query only**, and scores weighted fields (title 10 >
aliases 8 > summary 5 > tags 4 > category/area 3 > body 1) with bounded
Levenshtein typo tolerance (≤1 for short tokens, ≤2 for longer) restricted to
title/aliases/summary/tags — never a full-body fuzzy scan. Per-query-token match
strength is capped at 2× a field's weight so repeated incidental words can't
outrank genuine topical alignment. Sorting is deterministic: score desc → title
asc → id asc.

**Mid-slice correctness fix:** initial testing surfaced that "why is my crawl
queued" ranked `why-crawl-rejected-ownership-unverified` above the intended
`why-a-crawl-may-remain-queued`, caused by (a) no stopword filtering letting
"is"/"why"/"my" inflate a title with incidental repeats, and (b) uncapped
repeated-token matching letting one alias list's four "crawl" mentions
outweigh a more precisely-matching article. Both were fixed (stopword filter +
match cap) and verified — see §10.

## 8. Route design

Added as top-level siblings to `/seo/login` in `SeoRoutes.tsx`, **before** the
pathless `<Route element={<ShellLayout/>}>` block (whose nested `<Route
path="*">` redirects unmatched paths to `/seo/dashboard`):

- `/help` → `HelpHomePage`
- `/help/search` → `HelpSearchPage` (reads `?q=`)
- `/help/category/:categorySlug` → `HelpCategoryPage`
- `/help/article/:articleSlug` → `HelpArticlePage` (supports `#anchor`)
- `/help/dev/content-check` → `HelpDevContentCheckPage`, **dev-only**
  (`import.meta.env.DEV`), mirroring the existing `/seo/dev/*` convention —
  never mounted in a production build.

`/seo/help` was **not** added (per the approved decision to use `/help` as
primary, with no compatibility redirect needed since `/seo/help` never
existed before).

## 9. Support compatibility

- `ExpertSupportPage.tsx` (`/seo/support`) gained one additive line: *"Looking
  for step-by-step guides instead? Browse the Help Center."* linking to `/help`.
  Its request/comment/cancel/status workflow and mock behavior are byte-for-byte
  unchanged below that line.
- `HelpShell.tsx` links to `/seo/support` in both its header and footer, and
  every article page's `StillNeedHelp` component links there with the note that
  signing in may be required.
- `Sidebar.tsx` gained one additive nav entry (`{ to: "/help", label: "Help
  Center", icon: HelpCircle }`) in the existing `extraNavItems` list — the
  lowest-risk existing navigation convention (same pattern already used for
  Keyword Research / Content Gaps / Blog Briefs / Settings). "Expert Support
  Desk" is untouched and still present as its own item from the module registry.

## 10. Static hosting / deep-link findings

- **No hosting config exists in this repository** — no `vercel.json`,
  `netlify.toml`, `_redirects`, or nginx config anywhere. Production SPA
  fallback behavior on the actual deployment target is **unconfirmed** by this
  slice; no hosting change was made (per the explicit stop condition).
- **Local dev server (Vite):** confirmed direct navigation and full-page refresh
  work for `/help`, a deep article link, and an unknown slug — all render
  correctly.
- **Production static build (`vite preview`, which serves the real `dist/`
  output with its own SPA fallback):** `curl` against a running `vite preview`
  server returned HTTP 200 + the `index.html` shell for `/help`, a valid deep
  link (`/help/article/verifying-domain-ownership`), and an invalid one
  (`/help/article/does-not-exist`) — consistent, working client-side routing.
  **This is `vite preview`-server evidence only** — it does not prove behavior
  on an arbitrary unconfigured production host (S3, GitHub Pages, a bare nginx
  without a rewrite rule, etc.), which would each need their own explicit
  fallback rule. This gap is carried forward as an open, undecided item (see
  §12) rather than silently resolved.

## 11. Status labels

`FeatureStatusBadge` (built on the existing `Badge` primitive) renders all six
required labels (Available, Available on TEST, Preview, Demo data, Mock-only,
Coming later) plus an `Internal only` variant (never shown publicly, since
internal articles never reach a public route). No article claims "Available" in
a production sense; the whole Help Center itself is described only as available
"in this app build," never as production-promoted.

## 12. Accessibility

Skip-to-content link; single `h1` per page with ordered headings; labelled
search landmark (`role="search"`, associated `<label>`); `aria-live="polite"`
result counts; keyboard-operable links/buttons throughout (native `<a>`/
`<Link>`/`<button>`, no custom widgets needing extra ARIA); `focus-visible`
outline classes on every interactive element; status meaning is never
color-only (every badge carries text). **Verified at 375×812 (mobile):** zero
horizontal overflow (`scrollWidth === clientWidth`), cards stack to one column,
search stays prominent, header wraps cleanly.

## 13. Security

- No `dangerouslySetInnerHTML` anywhere (confirmed by repo-wide grep — the only
  matches are comment text stating the constraint).
- Article bodies render only through the closed `BodyRenderer` block-type
  switch — no raw HTML, no runtime Markdown, no remote content fetch.
- No DNS challenge value, TEST database identifier, Supabase project reference,
  internal RPC/table name, migration timestamp, workspace/website/user/job UUID,
  or JWT/API-key-shaped string appears anywhere in the **public** corpus —
  enforced by `src/help/validate.ts`'s `PROHIBITED_PATTERNS` scan (see §14).
- The internal article is structurally excluded from every public surface
  (§5), not merely hidden by UI.
- Search query text is read from the URL, matched entirely client-side, and is
  **never persisted or logged** (no localStorage write, no console output, no
  network call).

## 14. Verification results

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.app.json` | **PASS** (clean, 0 errors) |
| `npm run build` (production) | **PASS** — `dist/` built in ~2.6s, only a pre-existing generic chunk-size advisory (unrelated to this change) |
| Content integrity (`/help/dev/content-check`, live in-browser) | **PASS — 0 findings.** 30 total / 29 public / 1 internal / 9 categories. Confirms: unique ids+slugs; every category/related-article reference resolves; internal article structurally excluded from `publicArticles()`; every public article has required metadata + a non-empty body; anchors unique per article; homepage/popular/featured references all resolve; search ordering deterministic (verified by running the same 3 sample queries twice and diffing); zero prohibited-pattern matches in the public corpus |
| No-Supabase-request check | **PASS** — Network panel showed zero requests to any Supabase host while loading the homepage, an article, and a search |
| Signed-out `/seo/dashboard` still protected | **PASS** — redirected to `/seo/login?returnTo=%2Fseo%2Fdashboard`, unchanged |
| Internal/unknown-article/unknown-category safe not-found | **PASS** — all three render the identical "We couldn't find that page" state |
| Mobile responsive (375×812) | **PASS** — no horizontal overflow, clean single-column stacking |
| Static hosting deep-link (local `vite preview`) | **PASS** (preview-server evidence only — see §10 for the open production-host caveat) |

### Search fixtures (all 14 required queries)

| Query | Top result | Notes |
|---|---|---|
| "how do I verify my website" | `verifying-domain-ownership` | exact intended match |
| "site scan stuck" | `starting-and-monitoring-a-crawl` | synonym-expanded correctly |
| "why is my crawl queued" | `why-a-crawl-may-remain-queued` | exact intended match (post-fix; see §7) |
| "what is answer engine optimization" | `what-aeo-is` | exact intended match |
| "AI search visibility" | `ai-visibility-data-is-seeded` | synonym-expanded correctly |
| "why did my traffic drop" | `what-seo-is` | **best available match — see limitation below** |
| "I cannot approve" | `roles-and-permissions` | exact intended match |
| "wrong website data" | `workspaces-and-the-active-website` | exact intended match |
| "how do I contact support" | `contacting-support-safely` | exact intended match |
| "is this real data" | `preview-data-versus-live-data` | exact intended match |
| "verfy domain" (typo) | `verifying-domain-ownership` | typo tolerance working |
| "crawel status" (typo) | `understanding-crawl-statuses` | typo tolerance working |
| "permision denied" (typo) | `roles-and-permissions` | typo tolerance working |
| "genrative engine optimisation" (typo) | `what-geo-is` | synonym + typo tolerance working |

**13 of 14 land on the precisely intended article.** "Why did my traffic drop" is
a Decline Diagnosis question, and **Decline Diagnosis was not part of the
required Slice-1 corpus** (it is not in the 28-article P0/academy list in the
approved task scope) — no dedicated article exists for it yet. The search
correctly falls back to the closest topically-adjacent content available
(general SEO/visibility concepts) rather than returning nothing or an unrelated
result. This is recorded as a **content-coverage gap, not a search-algorithm
defect** — see §15.

## 15. Known limitations

- **Production static-hosting fallback is unconfirmed** (§10) — no hosting
  config exists in-repo; this slice makes no hosting change and the actual
  deployment target's behavior is unverified.
- **No Decline Diagnosis article exists yet** — "why did my traffic drop"
  therefore returns a topically-adjacent but not precisely-targeted result.
  Adding Decline Diagnosis content is natural follow-on scope, not required by
  Slice 1.
- **Sidebar/`ExpertSupportPage` changes are verified by static code review and
  `tsc`/build only, not by an authenticated live browser session** — no
  TEST-user credentials are available in this environment (a recurring,
  previously-documented constraint across this project). The added lines are
  structurally simple (a static nav-array entry; a single unconditional JSX
  block) and were confirmed present via source inspection.
- No Help Drawer, no analytics implementation, no CMS/Supabase content backend,
  and no grounded AI assistant — all explicitly out of Slice 1 scope.
- No contextual-help links were added to any other SEO module screen (Wave 2/3
  of the implementation plan) — Slice 1 is the Help Center foundation only.

## 16. Rollback

Delete `src/help/` and `src/pages/help/` entirely; revert the four additive
edits in `SeoRoutes.tsx` (imports + the `/help*` route block), `Sidebar.tsx`
(the one `extraNavItems` entry), and `ExpertSupportPage.tsx` (the one link
paragraph). No database, migration, worker, or config rollback is needed — none
were touched.

## 17. Exact next slice

Per the implementation plan, the next slice is **Wave 2 — unlocked-page
contextual links**: add `ContextualHelpLink` instances to the non-locked SEO
screens (dashboard, websites, onboarding, approvals, page-optimizer, settings,
support, competitors, roadmap, reports, placeholders, and the `ProtectedRoute`
access states), using the route-by-route mapping already specified in
`DIGIBILITY_SEO_CONTEXTUAL_HELP_MAPPING.md` §2. Locked-module links (ownership
panel, crawl UI, Page Performance, Stage 6) remain **Wave 3**, gated on
separate, per-module approval and regression per that document's §4/§9 analysis.
