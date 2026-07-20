# Digibility SEO — Collapsible Navigation Information Architecture

**Status:** IMPLEMENTED AND VERIFIED. Frontend-only, additive/restructuring;
no locked module touched; no backend/database/migration/RPC/worker/route-path/
auth/permission change; no Cloud Run/production contact; nothing staged,
committed, or pushed.

## 1. Problem statement

Digibility will eventually host multiple major tools/modules alongside SEO.
The sidebar could not continue to show a permanent, flat list of every SEO
page — it needed to (a) present SEO as one collapsible top-level module so it
can coexist with future modules, (b) group its ~20 pages into logical,
independently collapsible sections instead of one long list, (c) put the SEO
Dashboard first, (d) stop using "Visibility Dashboard" as a label, since
"Visibility" names a separate, distinct Digibility module, and (e) reorder
pages to match a real customer journey rather than incidental registry order.

## 2. Previous flat navigation

`Sidebar.tsx` rendered `SEO_MODULE_REGISTRY` (filtered `status === "active"`,
sorted by `priority`) as one flat list of 15 links, followed by a `<hr>` and 5
more hardcoded links (`extraNavItems`: Keyword Research, Content Gaps, Blog
Briefs, Settings, Help Center) — 20 links total, no grouping, no collapse, no
accordion of any kind. The desktop sidebar (`hidden ... md:block`) was the
**only** place this list rendered; **no mobile navigation of any kind existed**
in the codebase (verified by repository-wide search — no drawer/hamburger/
mobile-nav component, and `Header.tsx` had no menu trigger).

## 3. Final module hierarchy

```
SEO (top-level collapsible module, default expanded)
├── SEO Dashboard                          (standalone, first, no group)
├── Setup
│   ├── SEO Setup & Connections            /seo/websites
│   └── Business Onboarding                /seo/onboarding
├── Research & Strategy
│   ├── Competitor Benchmarking            /seo/competitor-analysis
│   ├── 90-Day SEO Roadmap                 /seo/roadmap
│   ├── Keyword Research (not yet built)   /seo/keyword-research
│   └── Content Gaps (not yet built)       /seo/content-gaps
├── Audit & Optimization
│   ├── Technical SEO Audit                /seo/audit
│   ├── On-Page SEO Autopilot              /seo/page-optimizer
│   ├── Page Performance Tracker           /seo/page-performance
│   └── Decline Diagnosis Engine           /seo/decline-diagnosis
├── Content
│   ├── Content Studio                     /seo/content-studio
│   └── Blog Briefs (not yet built)        /seo/blog-briefs
├── Off-Page & AI Visibility
│   ├── Off-Page Authority Builder         /seo/off-page
│   └── AI Visibility / GEO Engine         /seo/ai-visibility
├── Reports & Workflow
│   ├── Approval Queue                     /seo/approvals
│   └── Progress Reports                   /seo/reports
└── Settings & Support
    ├── Settings (not yet built)           /seo/settings
    ├── Expert Support Desk                /seo/support
    └── Help Center (public route)         /help
```

`/seo/admin-preview` (global-admin-only) remains excluded from the sidebar —
unchanged from before; it was never in the nav.

## 4. Bucket definitions

Every bucket has 2–4 children (never exactly 1, per the "avoid single-child
buckets" guideline). Within each bucket, active/functioning pages are ordered
before not-yet-built placeholder pages, per "placeholders must not be
promoted above core functioning pages." "Off-Page & AI Visibility" was chosen
deliberately over the starting hypothesis's "Authority & Visibility" — see §7.

## 5. Page ordering — old vs. new

| # | Old flat order | New position |
|---|---|---|
| 1 | SEO Setup & Connections | Setup #1 |
| 2 | Business Onboarding | Setup #2 |
| 3 | **Visibility Dashboard** | **SEO Dashboard** — standalone, first overall |
| 4 | Technical SEO Audit | Audit & Optimization #1 |
| 5 | On-Page SEO Autopilot | Audit & Optimization #2 |
| 6 | Approval Queue | Reports & Workflow #1 |
| 7 | Content Studio | Content #1 |
| 8 | Page Performance Tracker | Audit & Optimization #3 |
| 9 | Decline Diagnosis Engine | Audit & Optimization #4 |
| 10 | Off-Page Authority Builder | Off-Page & AI Visibility #1 |
| 11 | AI Visibility / GEO Engine | Off-Page & AI Visibility #2 |
| 12 | Competitor Benchmarking | Research & Strategy #1 |
| 13 | 90-Day SEO Roadmap | Research & Strategy #2 |
| 14 | Expert Support Desk | Settings & Support #2 |
| 15 | Progress Reports | Reports & Workflow #2 |
| 16 | Keyword Research | Research & Strategy #3 |
| 17 | Content Gaps | Research & Strategy #4 |
| 18 | Blog Briefs | Content #2 |
| 19 | Settings | Settings & Support #1 |
| 20 | Help Center | Settings & Support #3 |

No route path changed for any item — only sidebar grouping/order and one
label.

## 6. "Visibility Dashboard" → "SEO Dashboard"

- **Renamed (user-visible):** `SEO_MODULE_REGISTRY` entry `name: "Visibility
  Dashboard"` → `name: "SEO Dashboard"` (`src/registry/moduleRegistry.ts`).
  This is the **only** place this exact string existed in any code file
  (confirmed by full-repo grep both before and after the change).
- **Retained (internal, not user-visible):** the registry `id:
  "visibility-dashboard"` and the corresponding key in `Sidebar.tsx`'s icon
  map are **unchanged**, per the task's own backward-compatibility guidance —
  they are internal identifiers, never rendered, and renaming them carried
  needless risk for zero user-facing benefit. A code comment at the registry
  entry documents this decision.
- **Not renamed (unrelated, legitimate uses of "visibility"):**
  `VisibilityScoreCard`/`VisibilityScoreCards`/`buildVisibilityScoreCards`/
  `VisibilityScoreKey`/`VisibilityScoreLabel` (the pre-existing "search
  visibility score" SEO metric shown on the dashboard, e.g. "Overall
  Visibility: 62/100") and "AI Visibility / GEO Engine" (an established SEO/
  GEO domain concept — brand visibility in AI-generated answers — already
  used consistently across the Help Center's `what-geo-is`/
  `how-seo-aeo-geo-work-together` articles). Neither is a synonym for the
  separate Digibility Visibility module.

## 7. SEO versus Visibility module distinction

Per `CLAUDE.md`'s non-negotiable rules, SEO and Visibility are separate
Digibility modules. The Help Center already states this correctly and
untouched: `seo-access-and-entitlements` says *"Digibility SEO is a separate
module from Digibility Visibility Management."* This task's own new group
label deliberately avoids "Authority & Visibility" (the starting-point
hypothesis's suggested name) — using **"Off-Page & AI Visibility"** instead,
so "Visibility" never appears standing alone as if it were a reference to the
separate module; it always carries the "AI" qualifier that ties it to the
existing, already-published GEO/AEO domain concept.

## 8. Desktop behavior

- New file `src/registry/navigationGroups.ts` defines `SEO_NAV_GROUPS` (7
  group defs: id, label, ordered `itemIds`) and `SEO_EXTRA_NAV_ITEMS` (the 5
  previously-hardcoded pages, now with stable ids so they can sit inside a
  group like any registry item). Fully additive — `moduleRegistry.ts`'s
  `SeoModule` type and its other consumers (`ModulePlaceholderPage.tsx`,
  `getModuleById`/`getModuleByRoute`) are unaffected.
- `Sidebar.tsx` builds one `Map<id, ResolvedNavItem>` combining active
  registry items + extra items, then resolves each group's `itemIds` through
  it — any id that doesn't resolve (e.g. a future `"later"`-status change) is
  silently dropped, and a group with zero resolved children renders nothing
  (§13).
- The SEO module is a native `<button>` toggling a collapsible `<div>`
  containing, in order: the standalone SEO Dashboard link, then each
  `NavGroupSection` (also a native `<button>` toggling its own collapsible
  `<div>` of `SidebarLink`s).
- Verified live: clicking the SEO module button hides/shows every group and
  the Dashboard link; clicking a group button hides/shows only that group's
  own children; other groups are unaffected (not an accordion — multiple
  groups can be open at once, since no accordion UX existed to preserve).

## 9. Collapsed-sidebar behavior

**No icon-collapsed sidebar mode exists in this codebase** (verified — no
`isCollapsed`/`sidebarCollapsed` state anywhere before this task). This is a
different feature from the required module/group disclosure and was not
invented here, per "do not over-engineer... do not add a dependency unless
separately approved" and "do not redesign the entire application shell." The
sidebar remains a fixed `w-64` when visible, exactly as before. Nothing to
preserve or regress here; nothing was added.

## 10. Mobile behavior

**No mobile navigation drawer, hamburger trigger, or overlay existed in this
codebase before this task** (verified by repository-wide search — confirmed,
not assumed). Building one from scratch is a materially larger, separate
feature (new component, portal/overlay, focus trap, escape-key handling) that
the task's own "do not redesign the entire application shell" and "do not
over-engineer" instructions rule out as in-scope here. **Decision: preserve
the exact pre-existing mobile behavior** — the sidebar stays `hidden` below
the `md:` breakpoint (768px), unchanged. Verified live at 375px: `aside`
`display: none` (identical to before), `document.documentElement.scrollWidth
=== window.innerWidth` (no horizontal overflow), main page content renders
correctly. This is documented as a known limitation (§19), not silently
skipped.

## 11. Active-route and auto-expansion rules

- `SidebarLink` uses React Router's native `NavLink` `isActive` — ignores
  query strings by default, matches on pathname.
- Each group computes `containsActiveRoute = items.some(i => i.route ===
  pathname)` and passes it to a small shared hook,
  `usePersistedDisclosure(storageKey, computeDefault)`:
  - **Initial state** (lazy `useState` initializer): read localStorage; if
    nothing is stored yet, fall back to `computeDefault()` (for groups: "does
    this group contain the active route"; for the SEO module: always `true`
    — see §12).
  - **`revealIfActive(isActive)`**, called from a `useEffect` keyed on
    `pathname`: if the section is the active one and currently collapsed,
    expand it (and persist that). This **never auto-collapses** anything —
    it only ever reveals, so navigating away from a group does not
    unexpectedly hide it if the user had it open, and a fresh deep link or
    full-page reload always reveals the active item's section.
- Verified live: a fresh navigation straight to `/seo/decline-diagnosis`
  (Audit & Optimization) auto-expands the SEO module **and** the Audit &
  Optimization group only — Setup, Research & Strategy, Content, Off-Page &
  AI Visibility, Reports & Workflow, and Settings & Support all remain
  collapsed. Clicking a link, browser Back, and re-expanding a manually
  collapsed group were all verified to work correctly.
- When the SEO module is manually collapsed while the active route is still
  inside SEO (or `/help`), the module toggle button itself receives the same
  active/accent styling used for active links, so the user can see "you're
  inside this collapsed section" — verified live.

## 12. State-persistence decision

Reuses the exact existing convention from `ActiveWebsiteContext.tsx`: plain
`window.localStorage.getItem`/`setItem`, guarded by `typeof window !==
"undefined"`. No new persistence mechanism was introduced. Keys:
`digibility_seo_nav:module-expanded` and
`digibility_seo_nav:group-expanded:<groupId>`. **Default for the SEO module:
expanded.** Today, 100% of the authenticated app is SEO (there is no other
module to be "outside" of yet), so defaulting to expanded is the only
non-surprising choice; the module remains fully user-collapsible and that
choice persists across reloads, ready for the day a second module exists
alongside it. **Default for each group:** collapsed, unless it contains the
currently active route on first load — this is the actual mechanism that
reduces visual clutter, which is the whole point of this task.

## 13. Permission filtering

**Unchanged.** The only filter that existed before (`status === "active"`,
excluding the two `"later"`-status registry entries — SEO Guardrail Monitor,
Content Trust Review) is the only filter that exists now. **No plan-based or
role-based filtering was added** — none existed before (`getModulesForPlan()`
was, and remains, unused by the sidebar). Verified live: "Guardrail" and
"Content Trust" do not appear anywhere in the rendered nav text. A group
renders nothing if all of its resolved items become empty (defensive; not
currently triggered by any real data, since nothing in today's registry is
conditionally hidden beyond the pre-existing active/later split).

## 14. Accessibility behavior

- Every toggle is a native `<button type="button">` — no custom keyboard
  handling was written; native Enter/Space activation is used as-is.
- `aria-expanded` reflects live state on both the module and every group
  toggle; `aria-controls` points to a stable `id` on the corresponding
  content region, verified to resolve (`document.getElementById(...)  !==
  null`) whenever expanded.
- Accessible names come from each button's own visible text ("SEO", "SETUP",
  "AUDIT & OPTIMIZATION", ...) — descriptive enough that no redundant
  `aria-label` was added.
- Hidden children are not just visually hidden — they are **not rendered at
  all** when a section is collapsed (conditional JSX), so they are never
  keyboard-focusable while hidden.
- All interactive elements (toggles and links) carry visible
  `focus-visible:ring-2` styling, consistent with the rest of this
  codebase's established link/button focus treatment.
- **Not claimed:** a genuine hardware-keyboard Tab/Enter/Space walkthrough —
  no connected browser was available in this environment (same disclosed,
  unchanged limitation as every prior Help Center wave in this project).
  `aria-expanded`/`aria-controls`/native-button semantics were verified
  structurally instead.

## 15. Backward compatibility

- **Zero route paths changed** — every `/seo/*` and `/help*` URL from before
  this task still resolves identically; confirmed live (protected routes
  still redirect signed-out to `/seo/login?returnTo=...`; the public Help
  Center still loads signed-out with no redirect).
- **No `SeoModule` type change** — `navigationGroups.ts` references registry
  items by `id` only; nothing about the registry's existing shape or its
  other two consumers changed.
- **No auth/permission logic touched** — `ProtectedRoute.tsx`,
  `useSeoAccess`, role resolution: none were opened or edited.
- The one content edit (`startHere.ts`) is additive only (new heading +
  paragraph, one extended `searchAliases` array) — no existing article field
  was removed or restructured.

## 16. Help Center content changes

Audited all 30 public articles for "Visibility Dashboard," sidebar/menu
descriptions, and dashboard-order references — **zero existing occurrences**
were found (the string never appeared in any article body). Two changes were
made to `getting-started-with-digibility-seo`
(`src/help/content/startHere.ts`):

1. A new heading + paragraph, **"Finding your way around,"** added right
   after the "Your first day" steps, describing the grouped/collapsible
   structure in general terms (expand SEO, then expand the group you need;
   SEO Dashboard is always first) — without hardcoding fragile exact
   positions beyond naming the real group labels, which the UI itself now
   matches exactly.
2. `searchAliases` extended with `"visibility dashboard"`, `"seo dashboard"`,
   and `"where is the dashboard"` — retaining the old name **only** as a
   search synonym (per the task's explicit suggestion) so a user who
   searches the old term is still routed to the right article; the old name
   itself never appears in any rendered article body.

Content validation re-run after the change: **PASS, 0 findings**, counts
unchanged (31 total / 30 public / 1 internal / 10 categories) — confirming
the edit didn't break anything and added no new article.

One draft, non-authoritative planning document
(`DIGIBILITY_SEO_END_TO_END_USER_JOURNEY_AND_SUPPORT_BLUEPRINT.md`) was
corrected in place (one paragraph) since it stated the old flat order as
present fact; a second, unrelated document
(`SEO_PRODUCT_BLUEPRINT_REAL_APP.md`) was left untouched as an accurate
historical record of original project planning.

### Terminology audit (full)

| Occurrence | Location | Classification | Action |
|---|---|---|---|
| `name: "Visibility Dashboard"` | `moduleRegistry.ts` | Must rename | Renamed to `"SEO Dashboard"` |
| `id: "visibility-dashboard"` | `moduleRegistry.ts`, `Sidebar.tsx` icon map | Internal id, not user-visible | Retained, documented |
| "Visibility Dashboard" (planning sections) | `SEO_PRODUCT_BLUEPRINT_REAL_APP.md` | Historical record | Left unchanged |
| "Visibility Dashboard (`/seo/dashboard`)" | `DIGIBILITY_SEO_END_TO_END_USER_JOURNEY_AND_SUPPORT_BLUEPRINT.md` | Draft stating current fact | Corrected in place |
| `VisibilityScoreCard(s)`, `buildVisibilityScoreCards`, etc. | `types/dashboard.ts`, `dashboard/VisibilityScoreCards.tsx`, `dashboardService.ts` | Unrelated — SEO "search visibility score" metric | Untouched |
| "AI Visibility / GEO Engine" | `moduleRegistry.ts`, `AiVisibilityPage.tsx`, Help Center corpus | Unrelated — established SEO/GEO domain term | Untouched; new group label avoids bare "Visibility" (see §7) |
| Published Help Center article body text | `src/help/content/*.ts` | Zero existing occurrences | No correction needed; additive nav-instructions + search-synonym only (see above) |

## 17. Files changed

- `src/registry/moduleRegistry.ts` — one label rename + explanatory comment.
- `src/registry/navigationGroups.ts` — **new file**: group definitions + the
  5 extra-page definitions.
- `src/components/layout/Sidebar.tsx` — rewritten to render the collapsible
  module/group tree (was: flat list).
- `src/help/content/startHere.ts` — additive navigation-instructions section
  + extended search aliases on one article.
- `DIGIBILITY_SEO_END_TO_END_USER_JOURNEY_AND_SUPPORT_BLUEPRINT.md` — one
  paragraph corrected (draft, non-authoritative doc).
- This file (new).
- `CURRENT_PROJECT_STATUS.md`, `CHATGPT_CONTEXT_HANDOVER.md`,
  `PROJECT_DOCUMENTATION_INDEX.md` — additive status updates (see the commit
  message / final response for exact content).

**Not changed:** `Header.tsx`, `Layout.tsx`, any locked file, any route
definition, any backend/database/Supabase file, `MODULE_LOCKS.md`.

## 18. Tests and browser verification

No test or lint infrastructure exists in this repo for the frontend
(confirmed via `package.json` — only `crawler-worker/` has tests, unrelated
and untouched). Verification was performed via `tsc`, `npm run build`, and
live browser checks:

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.app.json` | **PASS** (0 errors) |
| `npm run build` | **PASS** (same pre-existing chunk-size advisory) |
| Help Center content validation | **PASS**, 0 findings, 31/30/1/10 (unchanged) |
| SEO module toggle hides/shows all groups + Dashboard | **PASS** (live: 0 `nav a` elements when collapsed) |
| Group toggle hides/shows only its own children | **PASS** (live: Setup expand/collapse independent of other groups) |
| SEO Dashboard is the first link | **PASS** (live, both accessibility-snapshot and DOM order) |
| Deep-link auto-expansion | **PASS** (fresh load of `/seo/decline-diagnosis` → SEO module + Audit & Optimization expand; all other groups stay collapsed) |
| Active-route highlighting | **PASS** (`NavLink` active class applied to the correct link; module button shows the accent-active indicator when collapsed while inside SEO) |
| "later"-status items excluded | **PASS** (live: "Guardrail"/"Content Trust" absent from rendered nav text) |
| No "Visibility Dashboard" text anywhere | **PASS** (repo-wide grep, zero matches; live DOM check, `false`) |
| No duplicate Dashboard link / no duplicate SEO module button | **PASS** (live: counts of 1 and 1) |
| Browser Back | **PASS** |
| Protected routes remain protected | **PASS** (`/seo/dashboard` → `/seo/login?returnTo=...` on the Supabase-mode server) |
| Public Help Center remains public | **PASS** (loads signed-out, no redirect) |
| No console errors | **PASS** (checked on both preview servers throughout) |
| No horizontal overflow at 375px / 768px / 1280px | **PASS** (`scrollWidth <= innerWidth` at all three; screenshots confirm no clipped text — long labels truncate with ellipsis by design) |
| `aria-expanded`/`aria-controls` correctness | **PASS** (structurally verified; content region id always resolves when expanded) |

## 19. Known limitations

- **No mobile navigation drawer exists** (§10) — this is a pre-existing gap,
  not a regression; building one is out of this task's safe scope (a
  shell-level redesign, explicitly out of scope) and was not attempted. The
  existing `hidden md:block` mobile behavior is preserved exactly.
- **No icon-collapsed sidebar-width mode exists** (§9) — a different,
  separate feature from module/group disclosure; not invented here.
- **No genuine hardware-keyboard walkthrough was performed** (§14) — no
  connected browser in this environment; accessibility attributes were
  verified structurally instead.
- **Text truncation, not wrapping, for long labels** (e.g. "Decline
  Diagnosis Engine" → "Decline Diagnosis En…") — a deliberate, minimal choice
  to prevent overflow without adding new CSS complexity; the full label is
  still present in the DOM/accessible name, only the visual line is
  truncated.

## 20. Future-module extensibility

The architecture was deliberately built so a second module could be added
without touching SEO's own configuration: `navigationGroups.ts` and
`Sidebar.tsx`'s `usePersistedDisclosure` hook are not SEO-specific in
implementation (only in the data they're fed), and the `digibility_seo_nav:`
localStorage key prefix leaves room for a distinct `digibility_<module>_nav:`
prefix per future module without collision. No non-SEO module scaffolding
was added — per the task's explicit instruction not to assume future modules
beyond ensuring coexistence — but nothing in this implementation would need
to be reworked to add one.
