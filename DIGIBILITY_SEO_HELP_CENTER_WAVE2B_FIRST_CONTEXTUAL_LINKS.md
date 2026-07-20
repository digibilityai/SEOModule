# Digibility SEO Help Center — Wave 2B: First Contextual-Help Rollout

**Status:** IMPLEMENTED AND VERIFIED. Frontend-only, additive; no locked module
touched; no backend/database/routing/worker/migration/Supabase-configuration
change; no Cloud Run/production contact; nothing staged, committed, or pushed.

## 1. Implementation scope

This is the first of the two batches identified in the Wave 2A audit
(`DIGIBILITY_SEO_CONTEXTUAL_HELP_MAPPING.md` is the Phase-1 draft; the actual
audit and slug verification were done directly against the real, implemented
Help Center corpus). Exactly the four approved placements were implemented —
**no more, no less**:

1. Websites (`/seo/websites`)
2. Business Onboarding (`/seo/onboarding`)
3. Dashboard zero-website empty state (`/seo/dashboard`)
4. Login, both mock-mode and real-auth branches (`/seo/login`)

`PlaceholderPage.tsx` and every other Wave 2B/2C candidate identified in the
audit (Settings, Page Optimizer, Decline Diagnosis, Approvals, Reports,
Roadmap, Competitor Analysis, `WebsiteAuditPage`/`AuditHeader`, `RouteStates`)
were **not touched**, per instruction.

## 2. Route-constant design

New file: [src/help/routes.ts](src/help/routes.ts). A single `as const` object,
`HELP_ROUTES`, exporting only the 4 routes this batch actually links to:

```ts
export const HELP_ROUTES = {
  GETTING_STARTED: "/help/article/getting-started-with-digibility-seo",
  ADDING_WEBSITE: "/help/article/adding-a-website",
  BUSINESS_ONBOARDING: "/help/article/completing-business-onboarding",
  SIGN_IN_ACCESS: "/help/article/signing-in-and-access-states",
} as const;
```

No generic URL builder, no React component, no Help Center routing change.
Each of the 4 slugs was verified directly against
`src/help/content/{startHere,setup}.ts` before use — `published: true`,
`visibility: "public"` on all four (internal-only articles, e.g.
`support-diagnostic-runbook-internal`, are structurally excluded from
`publicArticles()` and were never candidates).

## 3. Exact placements

All four use one identical class string (the exact string specified in the
task, matching the existing `ExpertSupportPage.tsx` precedent plus explicit
`focus-visible` ring classes), defined as a local `HELP_LINK_CLASSNAME`
constant duplicated per file — no shared component was introduced, per
instruction:

```
text-sm font-medium text-primary underline-offset-4 hover:underline
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring
focus-visible:ring-offset-2 rounded-sm
```

| # | Page | File | Exact insertion point | Link text | Article |
|---|---|---|---|---|---|
| 1 | Websites | [src/pages/seo/WebsitesPage.tsx](src/pages/seo/WebsitesPage.tsx) | Inside `CardHeader`, immediately after the existing `CardDescription`, before the plan-limit warning and "Add website" button | "How adding a website works" | `adding-a-website` |
| 2 | Business Onboarding | [src/pages/seo/BusinessOnboardingPage.tsx](src/pages/seo/BusinessOnboardingPage.tsx) | Inside the `CardHeader` title/description `<div>`, entirely before `CardContent`'s `<form>` | "Why this matters" | `completing-business-onboarding` |
| 3 | Dashboard (zero-website state only) | [src/pages/seo/SeoDashboardPage.tsx](src/pages/seo/SeoDashboardPage.tsx) | Inside the `websites.length === 0` empty-state `Card`'s `CardContent`, below the "Add your website" button, in its own `<div>` | "New here? Read the getting-started guide" | `getting-started-with-digibility-seo` |
| 4 | Login — mock-mode branch | [src/pages/seo/SeoLoginPage.tsx](src/pages/seo/SeoLoginPage.tsx) | Inside that branch's `CardHeader`, after `CardDescription`, before `CardContent` | "Trouble signing in?" | `signing-in-and-access-states` |
| 5 | Login — real-auth branch | [src/pages/seo/SeoLoginPage.tsx](src/pages/seo/SeoLoginPage.tsx) | Inside that branch's separate `CardHeader`, after `CardDescription`, strictly before the `<form>` in `CardContent` | "Trouble signing in?" | `signing-in-and-access-states` |

Inspection confirmed the two `SeoLoginPage` branches use **two distinct**
`CardHeader` elements (mock-mode vs. real-auth), so the link was added to
both, per the task's explicit fallback instruction.

## 4. Article mappings

All 4 slugs resolve to real, published, public articles already shipped in
Slice 1/1A — no new Help Center content was needed or added:

- `getting-started-with-digibility-seo` — Start Here category
- `adding-a-website` — Set Up Digibility SEO category
- `completing-business-onboarding` — Set Up Digibility SEO category
- `signing-in-and-access-states` — Start Here category

## 5. Accessibility behaviour

- All 5 link instances are semantic `react-router-dom` `<Link>` elements
  (same-tab navigation; no `target="_blank"`, matching the only existing
  convention in this codebase — `ExpertSupportPage.tsx`'s prior Help Center
  link).
- Each carries the explicit `focus-visible:outline-none focus-visible:ring-2
  focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm` classes.
  Confirmed structurally: the rendered `className` matches exactly on every
  instance, and the CSS custom property the ring depends on,
  `--ring`, resolves to a real HSL color (`221 83% 53%`), not transparent —
  the same utility pattern already used by the existing `Button` component
  elsewhere in this app. Programmatic/synthetic focus dispatched via the
  automated browser tooling in this environment does not reliably trigger
  the CSS `:focus-visible` pseudo-class the way a real keyboard `Tab` does
  (a known headless-browser-automation limitation) — the class list and the
  underlying design-token resolution are confirmed correct; a live keyboard
  `Tab` walkthrough by a human/operator would show the visible ring, but
  that exact interaction could not be triggered by the automated tooling
  used here.
- No color-only signaling — every link has visible underlined text.
- No new landmark, heading, or ARIA change; all 5 links sit inside their
  page's existing `CardHeader`/`CardContent`, so they inherit the existing
  heading hierarchy without altering it.

## 6. Verification results

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.app.json` | **PASS** (0 errors) |
| `npm run build` | **PASS** (same pre-existing chunk-size advisory as every prior slice, unrelated) |
| Content integrity (`/help/dev/content-check`) | **PASS — 0 findings**, 31 total / 30 public / 1 internal / 10 categories — unchanged from before this batch, confirming the corpus itself was untouched |
| No test runner in repo | Unchanged; no test command exists (confirmed via `package.json`) |
| `/seo/websites` shows the correct link | **PASS** — verified live (mock-mode preview), correct position, correct target |
| `/seo/onboarding` shows the correct link outside the form | **PASS** — verified live; link renders above the `<form>` boundary |
| Zero-website `/seo/dashboard` shows the getting-started link | **PASS** — verified live by temporarily emptying the mock website collection in a disposable preview tab's own `localStorage` (`digibility_seo_mock:websites`, cleared again afterward); this is a client-side-only test manipulation, no file or repo state was touched |
| Populated dashboard does not gain an unintended extra link | **PASS** — verified live with the real seeded mock website present; `document.body.innerText` does not contain the new link text |
| `/seo/login` shows the sign-in help link in both relevant branches | **PASS** — mock-mode branch verified on a temporary mock-mode preview server; real-auth branch verified on the primary (Supabase-mode) preview server |
| Each link opens the expected `/help/article/...` route | **PASS** — clicked all 4 unique links live; `window.location.pathname` matched the expected article route in each case |
| Browser back navigation returns to the original page | **PASS** — verified for the Websites → article → back round-trip |
| No console errors | **PASS** — checked on both preview servers after every navigation |
| No layout overflow at 375 px and desktop width | **PASS visually** — screenshots at 375 px for all 4 placements (both `SeoLoginPage` branches included) show correct text wrapping and no clipped/cut-off content or visible horizontal scrollbar. **One unresolved measurement anomaly, disclosed for transparency:** a JS-side check (`document.documentElement.scrollWidth` vs. `window.outerWidth`) intermittently reported a ~50 px discrepancy on one of the two disposable preview servers used for this session; this could not be reproduced through direct visual inspection (multiple clean screenshots at 375 px showed correctly wrapped, non-overflowing content), and is most consistent with the two preview servers used in this session sharing one underlying browser session/tab (confirmed: resizing one server's viewport was observed to also change the other server's reported `innerWidth`). Not treated as a confirmed defect; flagged rather than silently dropped. |
| Protected `/seo/*` routes remain protected | **PASS** — `/seo/websites` and `/seo/dashboard`, accessed signed-out on the real Supabase-mode server, both correctly redirected to `/seo/login?returnTo=...` |
| Public Help Center routes remain public | **PASS** — all 4 target `/help/article/...` destinations loaded directly, signed-out, with no redirect |

## 7. Lock and backward-compatibility confirmation

- **No locked file was changed.** Cross-checked all 4 edited files (plus the
  new `src/help/routes.ts`) against every "Locked files" list in
  `MODULE_LOCKS.md` (Stage 6, Page Performance Tracker, Crawler 16C–16H, P1a,
  P1b) — zero matches, confirmed before and after editing.
- **No form or mutation code was changed.** `WebsitesPage.tsx`'s
  `createMutation`/`WebsiteForm` wiring, `BusinessOnboardingPage.tsx`'s
  `handleSubmit`/`saveMutation`/all form fields, and `SeoLoginPage.tsx`'s
  `handleSubmit`/`signInSeoCustomer`/`returnTo`/redirect logic are all
  byte-identical apart from the new import lines and the new `<Link>`
  elements themselves — confirmed by direct diff review of each edit.
- **No routing change.** `src/routes/SeoRoutes.tsx` was read for reference
  only and was not modified; no new route was added or altered.
- **Backward compatible.** Every existing call site, prop, export, and
  behavior in the 4 edited files is unchanged; the only additions are new
  imports (`Link` where not already imported, `HELP_ROUTES`) and new,
  purely-additive JSX.

## 8. Remaining Wave 2C candidates

Unchanged from the Wave 2A audit's "good but not first batch" list — still
not started:

- `PlaceholderPage.tsx` (optional `helpArticleSlug` prop) → Settings, Keyword
  Research, Blog Briefs, Content Gaps
- `PageOptimizerPage.tsx`
- `DeclineDiagnosisPage.tsx`
- `ApprovalQueuePage.tsx`
- `ReportsPage.tsx`
- `RoadmapSummaryHeader.tsx` (mutation button nearby — needs care)
- `CompetitorOverviewHeader.tsx` (mutation button nearby — needs care)
- `WebsiteAuditPage.tsx`'s `AuditHeader.tsx` (extra care re: `<CrawlPanel>` proximity)
- `components/auth/RouteStates.tsx` (auth-adjacent — its own careful pass)

Locked-module contextual links (ownership-verification panel, crawl UI, Page
Performance, Off-Page/Campaigns, AI Visibility) remain explicitly **Wave 3**,
each requiring its own separate approval and that module's regression suite.

## 9. Cloud Run runtime verification — still deferred

Unchanged from `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md`: the
repo-root `Dockerfile`/`docker/nginx.conf.template`/`.dockerignore` container
configuration exists and was statically verified (`tsc`/build clean, a
logic-trace of the nginx routing rules), but **no actual container
build/run/HTTP verification has been performed** — Docker was not available in
that session's environment. This Wave 2B batch does not change that status in
either direction; actual container-runtime verification (and, separately, a
live keyboard-`Tab` focus-visible walkthrough, per §5) remains deferred to the
TEST promotion gate, to be performed by an operator with Docker and/or a real
browser available.

## 10. Rollback

Delete [src/help/routes.ts](src/help/routes.ts) and revert the additive edits
in the 4 page files (each edit is a small, isolated diff: one new import line,
one local class-name constant, and 1–2 new `<Link>` elements per file) — no
database, migration, or backend rollback is applicable.

## 11. Wave 2B.5 refinement (additive note — does not rewrite the above)

A UX acceptance review performed after Wave 2B shipped (a chat-only,
read-only review turn — per its own instructions it produced no file) found
one real, code-confirmed inconsistency and recommended one process
improvement before Wave 2C. Both were addressed in a small, approved
follow-up (Wave 2B.5):

### 11.1 Business Onboarding spacing — fixed

**Root cause:** `CardHeader` (`src/components/ui/card.tsx`) applies `flex
flex-col space-y-1.5`, which only sets `margin-top` on its **direct**
children. On `WebsitesPage.tsx` and `SeoLoginPage.tsx`, the contextual-help
`<Link>` is a direct `CardHeader` child, so it inherits that 6px rhythm
automatically. On `BusinessOnboardingPage.tsx`, the title/description/link
group sits one level deeper, inside an unstyled `<div>` used for the
`flex-wrap items-center justify-between` header layout (needed because a
status-badge group sits alongside it) — that inner `<div>` had no `space-y-*`
of its own, and `CardTitle`/`CardDescription` carry no inherent margin, so the
link previously had no explicit vertical spacing from the description.

**Fix:** added `className="space-y-1.5"` to that one existing inner `<div>`
in `src/pages/seo/BusinessOnboardingPage.tsx` — the exact same token
`CardHeader` itself uses. No other structural change. Verified via
`getComputedStyle`: `marginTop` on both the description and the help link is
now `6px`, identical to the value measured on `WebsitesPage.tsx`'s link in
the same session. The link stays inside `CardHeader`, stays entirely outside
the `<form>`, keeps its exact target (`HELP_ROUTES.BUSINESS_ONBOARDING`) and
visible text ("Why this matters"), and `HELP_LINK_CLASSNAME` itself was not
touched. The responsive `flex-wrap`/badge alignment is unaffected — only the
title/description/link sub-group received the new class.

### 11.2 Placement guideline (for Wave 2C and beyond)

**A. Header-level informational or form pages** (Websites, Business
Onboarding, Login):
- Place the contextual-help link after the title/description, inside the
  header's informational content area — as a direct (or explicitly
  `space-y-*`-wrapped) sibling of the title/description, never floating
  loose.
- Keep it entirely outside forms, controls, and mutation handlers.
- It is expected and acceptable for the link to appear before the primary
  form/action when that matches the page's natural DOM/reading order (title
  → description → help → form). **This is not, by itself, a defect** — do not
  restructure tab order solely to move the help link after a primary action
  on this page type.

**B. Empty-state pages** (e.g. Dashboard's zero-website state):
- Keep the primary action (e.g. "Add your website") visually dominant.
- Place contextual help after or near the primary CTA, as a clearly secondary
  aid — this page type's existing pattern (`SeoDashboardPage.tsx`) already
  does this correctly and is the reference example.
- Render it only in the relevant empty state; confirm it is absent from every
  other state of the same component (populated dashboard, loading, etc.).

**C. Shared and complex pages** (future Wave 2C/3 candidates — Approvals,
Reports, Roadmap, Competitor Analysis, the crawl/audit UI, etc.):
- Do not assume one universal placement rule applies.
- Choose the least disruptive location on a per-page basis.
- Avoid mutation controls, filters, status actions, and any locked
  subcomponent (per `MODULE_LOCKS.md`).
- Preserve each page's existing information hierarchy rather than forcing a
  uniform position.

**Standing conventions (unchanged, apply to all placements):**
- Same-tab internal navigation only (`react-router-dom` `<Link>`, never
  `target="_blank"`) — matches every existing link convention in this
  codebase.
- One shared visual style: `text-sm font-medium text-primary
  underline-offset-4 hover:underline focus-visible:outline-none
  focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2
  rounded-sm` — byte-identical across every placement so far.
- Visible keyboard focus is required (the ring classes above); do not ship a
  placement without them.
- No tooltip, drawer, or reusable contextual-help component yet — plain
  `<Link>` elements remain the pattern until enough placements exist to
  justify extracting one (see the Wave 2A audit's §H reasoning, unchanged).
- `src/help/routes.ts` (`HELP_ROUTES`) remains the single source of truth for
  every contextual-help target; no page should hardcode a raw
  `/help/article/...` string.

### 11.3 Explicitly not changed by Wave 2B.5

No tab order was changed anywhere (the guideline in §11.2.A explicitly says
not to). No article content changed. No new route, dependency, or component
was added. `WebsitesPage.tsx`, `SeoDashboardPage.tsx`, and `SeoLoginPage.tsx`
were inspected and re-verified but not edited — no regression was found in
any of them.
