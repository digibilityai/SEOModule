# Digibility SEO — Contextual Help Mapping

> **DRAFT (Phase 1) — not authoritative.** Maps contextual help across every
> `/seo/*` route, with exact placements, article targets, roles, states, and
> **locked-module impact**. Grounded in `SeoRoutes.tsx`, the module registry, and
> the verified component list. No code/DB/production changed.

## 1. Contextual-help UX patterns (small, consistent set)

Constraint: the repo has **only** these UI primitives — badge, button, card,
input, label, select, separator, skeleton, textarea (no dialog/drawer/tooltip/
popover/tabs). Patterns must be buildable from these or as plain links. Avoid help-
icon clutter: **max one page-level help affordance + targeted state/error links.**

| # | Pattern | When | Visual | Desktop/Mobile | Accessibility | Opens as | Later analytics |
|---|---|---|---|---|---|---|---|
| 1 | Page-level "Learn how this works" | Once per page header | Text link/`Button` variant=link | inline header / stacked | focusable link, aria-label | article route (new tab optional) | `contextual_help_clicked` |
| 2 | Section-level info link | Complex section | Small "ⓘ Help" text link (built from text, not an icon lib) | inline | link role | article anchor | same |
| 3 | Empty-state help link | Empty list/no data | Link inside the existing empty state | inline | link | getting-started article | same |
| 4 | Error-state troubleshooting link | Error/denied state | Link inside the existing `role="alert"` block | inline | in alert | troubleshooting article | same |
| 5 | Disabled-action "Why can't I do this?" | Role-gated control | Text link beside the disabled control/tooltip | inline | link, near control | role article | same |
| 6 | Status "What does this mean?" | Status badges | Link beside the badge | inline | link | status anchor | same |
| 7 | Confirmation-dialog guidance | Two-step confirms (crawl/revoke) | One extra line + link in the existing confirm block | inline | in group | task article | same |
| 8 | Report-metric definition link | Metric labels | Link/anchor on the metric header | inline | link | metric anchor | same |
| 9 | First-use guided checklist | New workspace/website | A dismissible checklist card on dashboard/websites | card | list semantics | learning path | `help_center_opened` |
| 10 | Optional Help Drawer | Global (Phase 2) | Slide-over panel (must be **built**; no primitive exists) | drawer / full-screen | focus trap, Esc | in-place | `help_center_opened` |

## 2. Route-by-route mapping

Legend for **Opens as**: R = article route (`/seo/help/article/:slug`), A = article
anchor, D = drawer (Phase 2), T = new tab. **Locked**: page belongs to a locked
module (contextual link = additive change requiring that lock's procedure).

| Route | Screen/component | User goal | Likely confusion | Help copy (proposed) | Article | Placement | Trigger/state | Roles | Opens as | Locked impact | Risk |
|---|---|---|---|---|---|---|---|---|---|---|---|
| /seo/login | `SeoLoginPage` | Sign in | invalid login / access | "Trouble signing in?" | A02 | below form | error or idle | All | R/T | none (not locked) | low |
| /seo/dashboard | `SeoDashboardPage` | Orient | is data real | "New here? Start guide" + "Is this data real?" | A01,N01 | header + empty | idle | All | R | none | low |
| /seo/websites | `WebsitesPage`/`WebsiteForm` | Add/manage site | required fields; who can | "How to add a website" | A05 | header + empty | idle/empty | Owner/Admin/Team | R | none | low |
| /seo/websites | `OwnershipVerificationPanel` in `WebsiteCard` | Verify domain | pending vs verified; token | "How to verify ownership" + status link | A07,A08,A38 | panel header + beside badge | per status | Owner/Admin (Team/Client read) | R/A | **P1a LOCKED** | med |
| /seo/onboarding | `BusinessOnboardingPage` | Fill profile | which fields matter | "Completing onboarding" | A06 | header | idle | Owner/Admin/Team | R | none | low |
| /seo/audit | `WebsiteAuditPage` | Read audit | seeded vs real; empty | "Reading your audit" + "Is this real?" | A13,N01 | header + empty | idle/empty | All | R | **Crawler 16H LOCKED** (page hosts `<CrawlPanel>`) | med |
| /seo/audit | `CrawlPanel`/`StartCrawlControl` | Start crawl | rejected; disabled (client) | "How to start a crawl"; "Why can't I?" | A10,A12,A31 | near Start + confirm | idle/denied | Owner/Admin/Team (client disabled) | R | **Crawler 16C–16H LOCKED** | high |
| /seo/audit | `CrawlStatusCard`/`CrawlStatusBadge` | Understand status | queued forever | "What crawl statuses mean" + "Why still queued" | A11,N03,A39 | beside badge | per status | All | A | **Crawler 16C–16H LOCKED** | high |
| /seo/audit | audit issue cards | Prioritize | severity meaning | "Fixing technical issues" | A14 | section link | list | Owner/Admin/Team | R | 16H LOCKED | med |
| /seo/page-optimizer | `PageOptimizerPage` | On-page recs | where recs come from | "Where recommendations come from" | A15 | header | list | All | R | none | low |
| /seo/approvals | `ApprovalQueuePage` | Approve/submit | who can approve | "The approval workflow" + "Roles" | A16,A31 | header + disabled action | idle/denied | Owner/Admin (approve); Team (submit); Client read | R | none | low |
| /seo/content-studio | `ContentStudioPage` | Content workflow | is content AI; upload | "Content Studio workflow" + "Generation is preview" | A17,N04,A18 | header + generate control | idle | Owner/Admin/Team | R | **Stage 6? No — Content Studio = Stage 3, not locked** | low |
| /seo/page-performance | `PagePerformancePage` | Read metrics | live vs seeded; empty | "Reading Page Performance" + "Not live Google data" + metric anchors | A20,N05,A21 | header + metric labels + empty | idle/empty | All | R/A | **Page Performance LOCKED** | high |
| /seo/decline-diagnosis | `DeclineDiagnosisPage` | Interpret decline | seeded vs live AI | "Diagnosing a decline" + "Seeded, not live AI" | A22,N06 | header | list/empty | Owner/Admin/Team (read all) | R | Stage 5 (not in the formal lock registry) | low |
| /seo/off-page | `AuthorityBuilderPage`/`OpportunityCard` | Evaluate opportunity | reject role | "Evaluating opportunities" + "Reject rule" | A23,A24 | header + disabled reject | idle/denied | Owner/Admin/Team (client read) | R | **Stage 6 LOCKED** | high |
| /seo/off-page | `CampaignBuilder` | Create campaign | client gated | "Authority campaigns" | A25 | builder header | idle/denied | Owner/Admin/Team | R | **Stage 6 LOCKED** | high |
| /seo/off-page | `CampaignList` | Transition campaign | return-to-draft only from rejected | "Campaign workflow" + "Limitations today" | A25,A26 | beside actions | per state | Owner/Admin/Team | R/A | **Stage 6 LOCKED** | high |
| /seo/ai-visibility | `AiVisibilityPage` | Read AI views | is it live | "AI Visibility (preview)" + "Seeded" | A27,N07 | header + source label | idle | All | R | **Stage 6 LOCKED** | high |
| /seo/competitor-analysis | `CompetitorAnalysisPage` | Compare | is it live | "Preview modules explained" | A28 | header | idle | All | R | none (mock) | low |
| /seo/roadmap | `RoadmapPage` | Plan | is it live | "Preview modules explained" | A28 | header | idle | All | R | none (mock) | low |
| /seo/reports | `ReportsPage` | Read report | mock vs real | "Report framework" + "Preview modules" | A29,A28 | header | idle | Owner/Admin | R | none (mock) | low |
| /seo/settings | `SeoSettingsPage` | Configure/connect | GSC/GA4 not wired | "Settings & connections status" | N11 | header + connection rows | idle | Owner/Admin | R | none | low |
| /seo/support | `ExpertSupportPage` | Get help | self-serve vs ticket | "Browse the Help Center" | A34,A01 | header | idle | All | R | none (mock) | low |
| /seo/keyword-research, /seo/content-gaps, /seo/blog-briefs | `PlaceholderPage` | — | not built | "Feature availability" | N08,A28 | inside placeholder | idle | All | R | none | low |
| /seo/admin-preview | `SeoAdminPreviewPage` | Internal | internal | (internal runbook link) | A36 | header | idle | Global admin | R | Phase 16B; internal | low |
| any | ProtectedRoute states | Regain access | access states | state-specific links | A03,N02,A05 | inside each state | denied/error | All | R | none | low |

## 3. Status-specific deep links (open the exact article anchor)

| Domain | State | Article#anchor | Copy |
|---|---|---|---|
| Ownership | unverified | A07 | "How to verify ownership" |
| Ownership | pending | A08 | "Why is it still pending?" |
| Ownership | verified | A07#next | "You're verified — start a crawl" |
| Ownership | failed | A07#failed | "Verification failed — fix your DNS" |
| Ownership | revoked | A07#revoked | "Re-verify ownership" |
| Crawl | queued | N03 | "Why is my crawl queued?" |
| Crawl | claimed/preparing | A11#preparing | "Preparing means a worker took the job" |
| Crawl | running | A11#running | "Crawling in progress" |
| Crawl | retry_wait | A39 | "Waiting to retry vs a new crawl" |
| Crawl | cancellation_requested | A11#cancelling | "Cancelling your crawl" |
| Crawl | completed | A13 | "Read your audit" |
| Crawl | partially_completed | A11#partial | "Partial results" |
| Crawl | failed | A11#failed / A33 | "Crawl failed — what to do" |
| Crawl | cancelled | A11#cancelled | "Prior results are preserved" |
| Campaign | draft | A25#draft | "Submit for approval" |
| Campaign | pending_approval | A25#pending | "Awaiting approval" |
| Campaign | approved | A25#approved | "Approved" |
| Campaign | rejected | A25#rejected | "Rejected → Return to Draft" |
| Performance | improving | A20#movement | "Improving" |
| Performance | stable | A20#movement | "Stable" |
| Performance | declining | A22 | "Declining — investigate" |
| Performance | new | A20#new | "New page — limited data" |
| Performance | no_data | N05 | "No data / seeded" |
| Access | anonymous | A02 | "Sign in" |
| Access | no module access | A03 | "SEO access required" |
| Access | no workspace | A05 | "Set up your workspace/website" |
| Access | no website | A05 | "Add a website" |
| Access | role denied | A31 | "Roles & permissions" |
| Access | resolver error | N02 | "Fixing resolution error" |

## 4. Exact link-placement recommendations

| Placement | Component/file (likely) | Locked? | Behaviour to preserve | Minimal additive approach | Article | Proposed copy |
|---|---|---|---|---|---|---|
| Ownership panel help | `src/pages/seo/websites/OwnershipVerificationPanel.tsx` | **P1a LOCKED** | double-submit lock, states, RPC calls, no token exposure | add ONE `<ContextualHelpLink>` in the section header + status link — **no logic touched** | A07/A08 | "How ownership works" |
| Crawl start/status | `src/pages/seo/audit/crawl/{CrawlPanel,StartCrawlControl,CrawlStatusCard,CrawlStatusBadge}.tsx` | **Crawler 16C–16H LOCKED** | polling, statuses, confirm, RPCs, query keys | add a help link in the panel header + a "What does this mean?" beside the badge — display only | A10/A11/N03 | "Crawl help" |
| Page Performance metrics | `src/pages/seo/PagePerformancePage.tsx` + `page-performance/**` | **Page Performance LOCKED** | fallback/adapter/query timing (recall the 14A refresh-race fix) | add a header link + metric-label anchors only; **no change to fetch/fallback** | A20/N05 | "Reading these metrics" |
| Off-Page / Campaigns | `src/pages/seo/AuthorityBuilderPage.tsx`, `offpage/*` | **Stage 6 LOCKED** | transition RPCs, role gates, `RoleGateTooltip`, activity | add header help + status links; do **not** modify the locked `RoleGateTooltip` | A23/A25 | "Off-page & campaigns help" |
| AI Visibility | `src/pages/seo/AiVisibilityPage.tsx` | **Stage 6 LOCKED** | read behaviour + mock-generation control | add a header link + a "seeded" note link | A27/N07 | "About AI Visibility" |
| Approvals | `src/pages/seo/ApprovalQueuePage.tsx` | not in registry | transitions | add header help + disabled-action link | A16/A31 | "Approval help" |
| Websites/onboarding/settings/dashboard/support/placeholders | respective pages | not locked | — | header link + empty/error-state links | per table | — |
| Global nav Help | `src/components/layout/{Sidebar,Header}.tsx` | not locked (shared) | existing nav + sign-out | add ONE Help entry (sidebar) + optional header help link | A34/home | "Help" |

**Rule (explicit):** adding *only a link* into a locked file is **still** a change
to that locked module — it must follow that lock's additive-extension procedure
(state the locked file touched, name the behaviour preserved, run the targeted
locked-scope regression, get approval). This is why locked-page links are **Wave 3**.

## 5. Help Drawer recommendation

**Reality check:** no drawer/sheet/dialog primitive exists; a drawer must be built
from scratch (portal + focus trap + Esc + overlay). That is real, testable work,
not a trivial add.

**Options:**
- **A. Direct article links only for MVP.**
- **B. Reusable Help Drawer for MVP.**
- **C. Direct links first (MVP); Help Drawer in Phase 2.** ✅ **Primary
  recommendation.**

**Why C:** direct links to `/seo/help/article/:slug#anchor` deliver the full
contextual value with **zero new UI machinery** and the least risk to locked
pages (a plain link is the smallest possible additive change). A drawer adds
focus-management, mobile full-screen, caching, and context-plumbing complexity
that is better sequenced after the Help Center itself exists and after locked-page
links are approved. When built (Phase 2), the drawer spec: launch button
(sidebar/header) · current-page suggested articles (route map §2) · in-drawer
search · article preview · "Open full article" · "Contact support" · mobile
full-screen · role/site/status context passed in (advisory only) · client-side
cache · **no service-role or sensitive data** · **works in mock mode** (bundled
content, no network).
