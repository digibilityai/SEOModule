# Digibility SEO Help Center — Wave 2C: Remaining Unlocked Contextual-Help Placements

**Status:** IMPLEMENTED AND VERIFIED. Frontend-only, additive; no locked module
touched; no backend/database/routing/worker/migration/auth-logic change; no
Cloud Run/production contact; nothing staged, committed, or pushed.

## 1. Implemented pages

Per the priority order and the placement guideline in
`DIGIBILITY_SEO_HELP_CENTER_WAVE2B_FIRST_CONTEXTUAL_LINKS.md` §11.2:

1. **Page Optimizer** (`/seo/page-optimizer`)
2. **Decline Diagnosis** (`/seo/decline-diagnosis`)
3. **Progress Reports** (`/seo/reports`)
4. **Approval Queue** (`/seo/approvals`)
5. **4 `PlaceholderPage` call sites** (Settings, Keyword Research, Blog
   Briefs, Content Gaps) via an additive optional-prop API
6. **1 conditional candidate**: `RouteStates.tsx`'s `AccessRequiredState`,
   module variant only

## 2. Candidates deferred

| Candidate | Reason |
|---|---|
| `RoadmapSummaryHeader.tsx` | The "Generate / Refresh 90-Day Roadmap" mutation button is a direct sibling of the title/description in the same header row — fails the "outside mutation controls" gate. No dedicated Roadmap article exists in the published corpus either (article fit not strong). |
| `CompetitorOverviewHeader.tsx` | Same pattern — "Refresh benchmark data" mutation button directly adjacent. No dedicated Competitor Analysis article exists. |
| `AuditHeader.tsx` | The mock-mode-only "Run Audit" button sits directly adjacent to the title/description (same nested-div pattern). This component's parent page (`WebsiteAuditPage.tsx`) also renders the **locked** `<CrawlPanel>` integration immediately below it — while `AuditHeader.tsx` itself is not on any `MODULE_LOCKS.md` list, editing anything in this immediate vicinity carries meaningfully higher risk than the other three deferred candidates. No article in the corpus explains the *audit* (as opposed to the crawl process, which is locked) specifically — article fit is not strong. Deferred on the combination of mutation-adjacency + locked-proximity + weak content fit. |
| `RouteStates.tsx`'s `ResolutionErrorState` | Not implemented (only `AccessRequiredState`'s module variant was). No article precisely addresses a transient resolution error; `troubleshooting-overview` is a generic fit at best. Left unchanged per "if one article is not genuinely relevant to a call site, leave that call site unchanged." |
| `RouteStates.tsx`'s `AccessRequiredState`, **admin** variant | Not implemented. `signing-in-and-access-states` covers the SEO-module-access-required case precisely but says nothing about global-admin access — a mismatched link would misinform a user in that narrower, internal-admin-only scenario. The help link is conditionally rendered only for `variant !== "admin"` (see §12). |
| `ModulePlaceholderPage.tsx` (both internal usages) | Confirmed via `grep` that this component is not imported or rendered by any route (`SeoRoutes.tsx` or elsewhere) — it is unreachable dead code today. Not a legitimate live target for a contextual-help link; left entirely untouched. Its "Unknown module" fallback is also an internal registry-miss error state, not a genuine "not built yet" state, so it would not have been a good fit even if reachable. |
| `BusinessOnboardingPage.tsx`'s `PlaceholderPage` call ("Add a website first") | Explicitly excluded — this is a blocked-state usage, not a "feature not built yet" placeholder. Confirmed unchanged (no `helpRoute` passed; verified live that no link renders). |

## 3. Files created

- [DIGIBILITY_SEO_HELP_CENTER_WAVE2C_UNLOCKED_CONTEXTUAL_LINKS.md](DIGIBILITY_SEO_HELP_CENTER_WAVE2C_UNLOCKED_CONTEXTUAL_LINKS.md) (this file)

## 4. Files changed

All additive only:

- [src/help/routes.ts](src/help/routes.ts) — 4 new `HELP_ROUTES` entries
- [src/pages/seo/PageOptimizerPage.tsx](src/pages/seo/PageOptimizerPage.tsx)
- [src/pages/seo/DeclineDiagnosisPage.tsx](src/pages/seo/DeclineDiagnosisPage.tsx)
- [src/pages/seo/ReportsPage.tsx](src/pages/seo/ReportsPage.tsx)
- [src/pages/seo/ApprovalQueuePage.tsx](src/pages/seo/ApprovalQueuePage.tsx)
- [src/pages/seo/PlaceholderPage.tsx](src/pages/seo/PlaceholderPage.tsx) — new optional `helpRoute`/`helpLabel` props
- [src/pages/seo/BlogBriefsPage.tsx](src/pages/seo/BlogBriefsPage.tsx)
- [src/pages/seo/KeywordResearchPage.tsx](src/pages/seo/KeywordResearchPage.tsx)
- [src/pages/seo/ContentGapsPage.tsx](src/pages/seo/ContentGapsPage.tsx)
- [src/pages/seo/SeoSettingsPage.tsx](src/pages/seo/SeoSettingsPage.tsx)
- [src/components/auth/RouteStates.tsx](src/components/auth/RouteStates.tsx)

10 files, 67 insertions / 3 deletions total (the 3 deletions are the `<div>` → `<div className="space-y-1.5">` replacements in Decline Diagnosis and Approval Queue, applying the Wave 2B.5 spacing lesson proactively).

## 5. `HELP_ROUTES` additions

All 4 verified `published: true` / `visibility: "public"` against `src/help/content/**` before use:

```ts
APPROVAL_WORKFLOW: "/help/article/the-approval-workflow",
DECLINE_DIAGNOSIS: "/help/article/investigating-traffic-ranking-decline",
DIGIBILITY_OPERATING_MODEL:
  "/help/article/how-digibility-connects-insights-actions-approvals-reporting",
FEATURE_AVAILABILITY: "/help/article/preview-data-versus-live-data",
```

No unused constant was added — every one of the 8 total `HELP_ROUTES` entries
(4 from Wave 2B + 4 new) is used at least once; `APPROVAL_WORKFLOW` and
`FEATURE_AVAILABILITY` are each used at 2 and 4 call sites respectively (this
is not "one article globally attached to every placeholder" — each call site
was individually assessed for genuine relevance first; see §11).

## 6. Page Optimizer placement

**Article:** `the-approval-workflow` ("The approval workflow"). **Rationale:**
Page Optimizer's own recommendation cards show "Approval required"/"No
approval needed" badges — the page's own most likely point of confusion is
*why* some suggestions need approval and others don't, which this article
answers directly. No dedicated "where recommendations come from" article
exists in the corpus (a genuine content gap, not filled here per the
out-of-scope instruction against adding new articles).

**Placement:** `CardTitle`/`CardDescription` were already direct `CardHeader`
children (no wrapper `<div>`) — the link was added as a third direct child,
inheriting the existing `space-y-1.5` rhythm automatically. This header
`Card` has no controls, selectors, or mutations at all; the recommendation
list (with its own badges) is a separate, unrelated section below.

## 7. Decline Diagnosis placement

**Article:** `investigating-traffic-ranking-decline` (the dedicated Decline
Diagnosis article from Slice 1A — an exact, pre-existing match; `relevantRoutes`
already includes `/seo/decline-diagnosis`).

**Placement:** Inside the existing inner `<div>` wrapping title/description
(sibling to a conditional "View all diagnoses" button that only appears when
filtering by a specific page). Applying the Wave 2B.5 lesson proactively,
`className="space-y-1.5"` was added to that inner `<div>` so the link
inherits the same 6px rhythm as the title/description, rather than
reintroducing the spacing bug just fixed elsewhere. No diagnosis query,
mutation, or state was touched.

## 8. Reports placement

**Article:** `how-digibility-connects-insights-actions-approvals-reporting`.
**Rationale:** its own description — "connects technical health, content,
page performance, decline diagnosis, off-page authority, and AI-visibility
planning into one website-centric workflow... an append-only history
connecting insights to the actions taken on them" — is close to a paraphrase
of Reports' own copy ("what improved, what was done, what is pending, and
what happens next"), making it a genuinely strong conceptual fit for "how
does this report get built."

**Placement:** Directly inside the main `CardHeader` (title/description are
direct children, no wrapper needed), placed *before* `CardContent`, which
contains only `<ReportPeriodSelector>`. The "Generate / Refresh Report"
button and `<ReportExportActions>` live in entirely separate `Card`/fragment
blocks further down the page, never touched.

## 9. Approval Queue placement

**Article:** `the-approval-workflow` (`relevantRoutes` already includes
`/seo/approvals` — the most direct match anywhere in the corpus).

**Placement:** Inside the existing inner `<div>` wrapping title/description,
which is a sibling of `<RoleSwitcher>` in the same header row.
`className="space-y-1.5"` was added to that inner `<div>` (same fix pattern
as Decline Diagnosis) so the link gets consistent spacing without touching
`RoleSwitcher`, `ApprovalFiltersBar`, or any of the three `useMutation` hooks
(`statusMutation`, `editMutation`, `commentMutation`) further down the file.

## 10. `PlaceholderPage` changes

**API (additive, backward compatible):**

```ts
interface PlaceholderPageProps {
  title: string;
  description: string;
  helpRoute?: string;   // e.g. a HELP_ROUTES constant
  helpLabel?: string;   // defaults to "Learn more" if helpRoute is set but helpLabel isn't
}
```

When `helpRoute` is omitted, the component renders **byte-identical** output
to before — verified live on `BusinessOnboardingPage.tsx`'s untouched call
site (no link rendered) and confirmed `ModulePlaceholderPage.tsx` was not
touched at all.

**Opted-in call sites** (all pass `HELP_ROUTES.FEATURE_AVAILABILITY`, each
individually judged genuinely relevant — its "Coming later — Designed but
not built yet" table row is a near-literal match for every one of these
pages' own "hasn't been built yet" copy):

| Page | `helpLabel` |
|---|---|
| Settings | "What 'not built yet' means" |
| Keyword Research | "What 'not built yet' means" |
| Blog Briefs | "What 'not built yet' means" |
| Content Gaps | "What 'not built yet' means" |

## 11. Conditional candidate decisions

| Candidate | Decision | Why |
|---|---|---|
| `RoadmapSummaryHeader.tsx` | **Deferred** | Mutation button adjacent; no strong article fit. See §2. |
| `CompetitorOverviewHeader.tsx` | **Deferred** | Same reasons. See §2. |
| `AuditHeader.tsx` | **Deferred** | Mutation-button adjacency + proximity to the locked `<CrawlPanel>` integration in its parent page + weak article fit. See §2. |
| `RouteStates.tsx` | **Implemented (partially, scoped)** | `AccessRequiredState`'s **module** variant only. All five gate conditions were checked directly: file unlocked ✓ (confirmed against every `MODULE_LOCKS.md` list); placement (`CardHeader`, after `CardDescription`, before `CardContent`) is outside the `onRetry`/`onSignOut` buttons, which live in a separate `CardContent` block ✓; the file contains zero auth-resolution logic — it is purely presentational, receiving pre-computed `variant`/callback props from `ProtectedRoute.tsx` ✓; no locked file/integration touched ✓; article fit is strong — `signing-in-and-access-states` has a heading literally titled `"Access required"` with the text "This means your account doesn't currently have SEO module access. Ask a workspace owner or admin to grant it," a precise match for this exact state ✓. The link is conditionally rendered (`{!isAdmin && (...)}`) so it does **not** appear on the admin-access-required variant, where the article would not fit. |

## 12. Accessibility behaviour

- All 11 new link instances (Page Optimizer, Decline Diagnosis, Reports,
  Approval Queue, 4 `PlaceholderPage` call sites, `RouteStates.tsx`) use the
  byte-identical Wave 2B class string:
  `text-sm font-medium text-primary underline-offset-4 hover:underline
  focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring
  focus-visible:ring-offset-2 rounded-sm`.
- Same-tab `react-router-dom` `<Link>` throughout — no `target="_blank"`,
  consistent with every existing link in this codebase.
- No icons were introduced (none exist in the local pattern for this link
  type).
- No tooltip, drawer, modal, or reusable `ContextualHelpLink` component was
  added — plain links only, per instruction.
- **Known verification limitation (unchanged from Wave 2B/2B.5):** no
  connected browser was available in this environment to perform a genuine
  hardware-keyboard `:focus-visible` walkthrough. The class list itself was
  confirmed present and correct on every new instance (spot-checked via
  `preview_inspect`/`getComputedStyle`), consistent with the same,
  previously-disclosed limitation.

## 13. Validation results

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.app.json` | **PASS** (0 errors) |
| `npm run build` | **PASS** (same pre-existing chunk-size advisory as every prior slice, unrelated) |
| Content integrity (`/help/dev/content-check`) | **PASS — 0 findings**, 31 total / 30 public / 1 internal / 10 categories — unchanged (no article content was added or modified) |
| No test runner in repo | Unchanged; confirmed via `package.json` |
| Page Optimizer link | **PASS** — renders in header, no controls nearby, opens `the-approval-workflow`, browser-back returns to `/seo/page-optimizer` |
| Decline Diagnosis link | **PASS** — renders with correct (fixed) spacing, opens `investigating-traffic-ranking-decline` |
| Reports link | **PASS** — renders before the period selector, opens `how-digibility-connects-insights-actions-approvals-reporting` |
| Approval Queue link | **PASS** — renders with correct spacing beside (not overlapping) `RoleSwitcher`, opens `the-approval-workflow`, browser-back returns to `/seo/approvals` |
| 4 `PlaceholderPage` sites | **PASS** — Settings, Keyword Research, Blog Briefs, Content Gaps all show "What 'not built yet' means" linking to `preview-data-versus-live-data`; `BusinessOnboardingPage`'s blocked-state call confirmed to still render with **no** link |
| No console errors | **PASS** — checked after every navigation on both the mock-mode and primary Supabase-mode servers |
| No horizontal overflow at 375px | **PASS** — screenshot-verified on Approval Queue (the most visually dense of the four changed pages: title/description/link + `RoleSwitcher` + safety notice + 8 filter chips) |
| Primary actions remain visually dominant | **PASS** — every new link uses the same small, secondary text style; no primary `Button` (Generate/Refresh, Run audit, Approve/Reject, etc.) was moved, resized, or visually diminished |
| Filters/forms/mutations unchanged | **PASS** — confirmed by direct diff review: zero lines changed inside any `useMutation`, `<form>`, filter component, or role-switching logic in any of the 4 pages |
| Protected routes remain protected | **PASS** — `/seo/approvals` (and, by extension, every other `/seo/*` route touched) still redirects signed-out users to `/seo/login?returnTo=...` on the primary Supabase-mode server |
| Help Center article routes remain public | **PASS** — all `HELP_ROUTES` targets loaded directly, signed-out, with no redirect |
| Every `HELP_ROUTES` entry used | **PASS** — grepped; all 8 entries (4 Wave 2B + 4 Wave 2C) are referenced at least once |
| No raw `/help/article/...` literal introduced | **PASS** — grepped every changed SEO page file; zero matches outside `src/help/routes.ts` itself |
| No internal article referenced | **PASS** — `support-diagnostic-runbook-internal` appears only in an explanatory code comment, never as an actual route value |
| No locked file changed | **PASS** — all 10 changed files cross-checked against every `MODULE_LOCKS.md` "Locked files" list; zero matches |

## 14. Lock and backward-compatibility confirmation

Zero file touched in this task appears on any `MODULE_LOCKS.md` locked-file
list (Stage 6, Page Performance Tracker, Crawler 16C–16H, P1a, P1b) —
re-checked immediately before and after editing. `PlaceholderPage.tsx`'s new
props are optional with no behavior change when omitted (verified live).
`RouteStates.tsx`'s new conditional JSX does not alter `RouteLoadingState`,
`ResolutionErrorState`, or the `AccessRequiredState` admin variant in any way,
and does not touch `onRetry`/`onSignOut` callback wiring. All existing
queries, mutations, filters, role-switching, and period-selection behavior in
Page Optimizer, Decline Diagnosis, Reports, and Approval Queue are
byte-identical apart from the new imports and new `<Link>` JSX.

## 15. Remaining Wave 3 scope

Unchanged — locked-module contextual links (P1a ownership-verification
panel, Crawler 16C–16H crawl UI, Page Performance page, Stage 6
Off-Page/Campaigns/AI Visibility) remain explicitly **Wave 3**, each
requiring its own separate approval and that module's regression suite. The
four deferred candidates in §2 (`RoadmapSummaryHeader`,
`CompetitorOverviewHeader`, `AuditHeader`, `RouteStates`'s
`ResolutionErrorState`/admin variant) remain open, unlocked, low-priority
follow-ups — not part of Wave 3, but not implemented here either, pending
either a stronger article fit or a more careful mutation-adjacent placement
design.

## 16. Cloud Run runtime verification — still deferred

Unchanged from every prior slice: the repo-root `Dockerfile`/
`docker/nginx.conf.template`/`.dockerignore` container configuration exists
and was statically verified in an earlier slice, but no actual container
build/run/HTTP verification has been performed — Docker was not available in
that session's environment, and this task did not touch or re-attempt that
verification. It remains deferred to the TEST promotion gate.
