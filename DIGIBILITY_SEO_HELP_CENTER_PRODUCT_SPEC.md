# Digibility SEO — Help Center & Contextual Tutorial System — Product Spec

> **DRAFT (Phase 1, documentation-only) — not yet authoritative.** Grounded in the
> repository (routes, components, services, locks) and in
> `DIGIBILITY_SEO_END_TO_END_USER_JOURNEY_AND_SUPPORT_BLUEPRINT.md` +
> `..._SUPPORT_CONTENT_PRODUCTION_MATRIX.md`. No code/DB/production changed.
> `CURRENT_PROJECT_STATUS.md` controls status; `MODULE_LOCKS.md` controls scope.

## 1. Purpose and scope

**Purpose.** A single in-product **Help Center** + **contextual help** layer that
lets Digibility SEO users learn SEO/AEO/GEO, complete product tasks, interpret
outputs, troubleshoot safely, find help from the exact screen they are stuck on,
search in natural language, and escalate cleanly when self-service fails.

**Customer problems solved.** "I don't know what this status/metric means"; "how do
I verify my domain / start a crawl?"; "why is my crawl stuck / rejected?"; "is this
data real?"; "why can't I do this (role)?"; "what should I do next?".

**Audiences.** Owner, Admin, Team Member, Client, Agency operator, SEO-only user,
SEO+Visibility user, and internal support/global-admin.

**Relationship to `/seo/support`.** `/seo/support` is today a **mock-only**
"Expert Support Desk" request flow. The Help Center is **self-service learning +
troubleshooting**; support remains the human-escalation channel. Recommended
model in §3 (keep `/seo/support` as *Contact Support*; add `/seo/help` for
self-service; cross-link both).

**Relationship to contextual in-product help.** The Help Center is the
destination; contextual links (per-screen, per-status, per-error, per-disabled-
action) are the *entry points* that deep-link into the right article/anchor.

**Relationship to future chat/AI support.** A grounded AI assistant is an
**additive Phase 3** layer that answers **only** from published articles with
source links; it is explicitly out of the MVP.

**Non-goals (first release).** No external search SaaS; no LLM/vector search; no
Supabase content tables; no analytics implementation; no multilingual; no
public-web documentation; no changes to locked-module behaviour beyond
separately-approved additive contextual links (Wave 3).

## 2. User outcomes (measurable)

1. **Fast answers** — a user finds a relevant article in ≤ 2 searches or 1 category
   drill-down (target: search-success rate; §12).
2. **Self-service completion** — users add a website, complete onboarding, verify
   ownership, and start a crawl using articles alone.
3. **Understanding outputs** — users correctly read statuses/metrics/diagnoses.
4. **Next action known** — every task/report article ends with an explicit next
   step.
5. **Preview/demo awareness** — users can tell seeded/mock/preview data from live
   data (a mandatory honesty label on every affected article).
6. **Role clarity** — users understand why a control is disabled and who to ask.
7. **Better escalations** — support receives structured, secret-free context.

## 3. Help Center entry points

| Entry point | Where | Behaviour |
|---|---|---|
| Sidebar entry | `Sidebar.tsx` fixed links (near Settings) | Route to `/seo/help` |
| Header help icon | `Header.tsx` (next to Sign out) | Route to `/seo/help` (or open Help Drawer, Phase 2) |
| Direct route | `/seo/help` | Help Center home |
| Support compatibility | `/seo/support` | Stays "Contact Support"; add a prominent "Browse the Help Center" link; Help articles link back to it for escalation |
| Contextual "How to" links | per screen (§ File 3) | Deep-link to article/anchor |
| Empty-state help | e.g., no website, no audit | Link to the relevant getting-started article |
| Error-state help | resolver error, RPC error, crawl rejected | Link to the matching troubleshooting article |
| Disabled-action help | role-gated buttons | "Why can't I do this?" → role article |
| Status help | ownership/crawl/campaign/performance badges | "What does this mean?" → status anchor |
| Onboarding links | `/seo/onboarding`, `/seo/websites` | Task articles |
| Report links | metric labels | Metric-definition anchors |
| Keyboard access | all entry points | Focusable, activatable via Enter/Space |
| Mobile access | sidebar/header collapse | Help reachable from the mobile nav |

**`/seo/support` disposition — options considered:**
- **A. Support becomes the Help Center** — loses the human-escalation identity;
  conflates self-service and ticketing.
- **B. `/seo/support` redirects to `/seo/help`** — breaks the existing (mock)
  support-request flow and the sidebar "Expert Support Desk" expectation.
- **C. Keep "Contact Support" at `/seo/support`; add `/seo/help` for self-service;
  cross-link.** ✅ **Primary recommendation.**
- **D. Merge into one "Help & Support" experience** — viable later, but couples a
  locked-adjacent mock flow with new content; more change than MVP needs.

**Why C:** it is the *smallest additive* change — it introduces `/seo/help`
(brand-new, touches no locked module), preserves the existing `/seo/support`
route/flow verbatim (backward compatible), and gives a clean self-service →
escalation path. A future merge (D) remains open without rework.

## 4. Help Center homepage design (`/seo/help`)

Ordered blocks. Layout uses existing primitives (Card/Badge/Input/Button); no new
UI library required.

| # | Block | Title | Purpose | Format | Data source | Sorting | Desktop | Mobile | Empty state | Accessibility |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Hero + search | "How can we help?" | Primary search | Large `Input` + button; popular searches as chips; optional "You're viewing: `<website>` · role: `<role>`" | bundled index; role/site from context | popular by static rank | full-width | full-width, sticky search | show popular searches only | labelled search landmark; live-region result count |
| 2 | Quick-start row | "Get started" | 6 top tasks | Card grid (6) | curated ids: Getting started, Add a website, Verify ownership, Start a crawl, Read your audit, Understand reports | fixed | 6 across (3×2) | 1–2 across | always present | list semantics, focus ring |
| 3 | Category index | "Browse by topic" | Full taxonomy (IA §1) | Card grid (A–T) | category registry | taxonomy order | 3–4 across | 1 across | — | headings per card |
| 4 | Learn SEO academy | "Learn SEO, AEO & GEO" | Concept education | Card list + "Start learning path" | academy corpus (§7) | level then order | 2–3 across | 1 across | — | — |
| 5 | Use Digibility | "How-to & workflows" | Task tutorials | Card list grouped by area | how-to/workflow corpus | product-area order | 2–3 across | 1 across | — | — |
| 6 | Understand your data | "Reports & metrics" | Interpretation | Card list | report-interpretation corpus | area order | 2–3 across | 1 across | — | — |
| 7 | Solve a problem | "Troubleshooting" | Symptom index | Symptom list linking anchors | troubleshooting corpus | priority | 2 across | 1 across | — | — |
| 8 | For your role | "For your role" | Role-scoped picks | Card list filtered by role | role→article map | role relevance | 2–3 across | 1 across | show generic set if role unknown | announce role badge in text |
| 9 | Featured / new | "New & updated" | Freshness | Card row w/ "New"/"Updated" badge | `lastReviewed`/`version` | newest first | horizontal row | scroll | hide if none | badges have text |
| 10 | Recently viewed | "Recently viewed" | Continuity | Card row | client-local (localStorage), user-scoped | recency | horizontal row | scroll | hide if none | — |
| 11 | Still need help | "Still need help?" | Escalation | Panel → `/seo/support` w/ safe context | static | — | full-width | full-width | always | button labelled |
| 12 | Product-status notice | "About this preview build" | Honesty | Notice card | static | — | full-width footer | full-width | always | text, non-colour-only |

## 5. Help Center feature requirements

### 5.1 Search
Search-as-you-type; typo tolerance (edit-distance ≤1–2 on tokens); synonym
expansion (IA §4 map); natural-language questions (match against per-article
`question`/aliases); match title/summary/body/tags; query suggestions
(autocomplete from titles + aliases); popular searches (static curated); recent
searches (client-local, user-scoped); full keyboard navigation (↑/↓/Enter/Esc);
highlighted matching text in results; grouped results (by category/product area);
no-result recovery (suggested categories + "Contact support"); filters (category,
content type, role, feature status); role + feature-status relevance boosting;
search analytics **designed only** (§12, no implementation in MVP).

### 5.2 Search-result ranking (proposed weights, tune later)
| Field | Weight |
|---|---|
| Title exact/prefix | 10 |
| Aliases / question match | 8 |
| Summary | 5 |
| Tags | 4 |
| Body | 3 |
| Product-area match to current route | +3 (context boost) |
| Role match | +2 |
| Popularity (curated) | +2 |
| Helpfulness (Phase 2 data) | +2 |
| Freshness (recently reviewed) | +1 |
Penalty: feature-status = placeholder/deferred → −2 (demote, never hide — honesty
articles about those states are still findable).

### 5.3 Article experience
Title; summary; audience; estimated reading time; last reviewed; **feature-status
badge**; prerequisites; numbered steps; expected result; troubleshooting block;
screenshots/video slots; related articles; previous/next (within category or
learning path); copy link; print; "Was this helpful?" (yes/no + optional reason);
"Contact support" escalation carrying safe context.

### 5.4 Discovery features
Popular articles (curated MVP); related articles (per-article `relatedIds`);
recently viewed (client-local); recommended-for-this-page (route→article map, §
File 3); recommended-for-this-role; new/updated (freshness); learning paths (IA
§3); continue-where-you-left-off (client-local, Phase 2).

### 5.5 Feedback & analytics (design only)
Helpful/not-helpful (+ optional reason); failed-search + zero-result tracking;
article exits; completion; contextual-link clicks; escalation-after-reading;
stale-content reports. **No analytics is implemented in MVP** (event catalogue in
the Implementation Plan §11).

### 5.6 Accessibility
Keyboard navigation everywhere; semantic headings (one `h1`, ordered `h2/h3`);
managed focus (search → results → article); screen-reader search announcements
(`aria-live` result count); non-colour-only status labels (badges carry text);
`prefers-reduced-motion` respected; responsive down to mobile.

## 6. Help content types (templates)

Each template defines mandatory fields + structure. **Common mandatory metadata
(all types):** `id`, `slug`, `title`, `summary`, `category`, `contentType`,
`audienceRoles`, `productArea`, `featureStatus`, `level`, `estimatedTime`, `tags`,
`aliases`, `relatedIds`, `relevantRoutes`, `lastReviewed`, `version`, `published`.

| Type | Extra mandatory fields | Structure |
|---|---|---|
| Concept/education | learnerQuestion, objective, externalReviewFlag | Intro → why it matters → how it works → Digibility connection → caveats → related |
| Quick start | prerequisite, outcome | 3–6 steps → expected result → next |
| How-to | prerequisite, role, outcome | Steps → validation → troubleshooting → next |
| Workflow | states, roles | Overview → state-by-state → decisions → next |
| Report interpretation | metrics, dataSource | What it measures → healthy/warning/critical → misreading → action |
| Role guide | role, capabilities | Can/can't → tooltips → escalation |
| Troubleshooting | symptom, safeChecks | Symptom → meaning → user checks → support checks → safe fix → don't → escalation evidence |
| FAQ | questions[] | Q/A pairs |
| Checklist | cadence, role | Ordered checks → record → cadence |
| Glossary | terms[] | Term → definition |
| Video tutorial | length, fixture, blurList | Shot list → narration → related article |
| Micro-video | length ≤60s | Single-concept shot |
| Support runbook | audience=internal | Safe sequence → safe asks → never-ask |
| Product-status notice | featureStatus | Plain statement of what is/ isn't live |

## 7. SEO, AEO & GEO education academy

Learning path (beginner → advanced). Each tutorial: working title · learner
question · level · objective · outline · reading time · video duration · Digibility
feature links · caveats · related. **`externalReviewFlag = true`** on any tutorial
that describes how search engines / AI systems rank or answer — those require SME
review before publication and must **not** assert proprietary algorithm details.

| # | Working title | Learner question | Level | Objective | Reading | Video | Digibility links | Caveat / review |
|---|---|---|---|---|---|---|---|---|
| 1 | What is SEO? | "What is SEO?" | Beginner | Define SEO in business terms | 4m | 2–4m | Audit, Page Performance | — |
| 2 | Why search visibility matters | "Why does SEO matter?" | Beginner | Tie visibility to outcomes | 4m | 2–4m | Dashboard | — |
| 3 | Business goals SEO supports | "What can SEO do for my business?" | Beginner | Map goals to SEO levers | 5m | — | Roadmap (preview) | mark preview |
| 4 | How search engines discover, understand & rank | "How does Google rank pages?" | Beginner | Conceptual model | 6m | 5–10m | Audit, Content | **externalReview** — no proprietary claims |
| 5 | Technical SEO basics | "What is technical SEO?" | Intermediate | Crawl/index/health | 6m | 5–10m | Audit, Crawl, Page Inventory | — |
| 6 | On-page SEO | "What is on-page SEO?" | Intermediate | Titles/meta/structure | 6m | 5–10m | Page Optimizer, Content | — |
| 7 | Content strategy | "How do I plan SEO content?" | Intermediate | Intent + planning | 6m | 5–10m | Content Studio (preview) | mark generation preview |
| 8 | Authority & links | "How do backlinks work?" | Intermediate | Authority basics + risk | 6m | 5–10m | Off-Page Authority | seeded/preview |
| 9 | Measurement & iteration | "How do I measure SEO?" | Intermediate | Metrics + cadence | 6m | 5–10m | Page Performance, Reports | seeded data caveat |
| 10 | What is AEO? | "What is answer-engine optimization?" | Intermediate | Define AEO | 5m | 2–4m | AI Visibility (preview) | **externalReview** |
| 11 | What is GEO? | "What is generative-engine optimization?" | Intermediate | Define GEO | 5m | 2–4m | AI Visibility (preview) | **externalReview** |
| 12 | SEO vs AEO vs GEO | "How do these differ?" | Intermediate | Distinguish 3 | 6m | 5–10m | AI Visibility | **externalReview** |
| 13 | How they overlap | "Do I do them separately?" | Intermediate | Shared foundations | 5m | — | — | **externalReview** |
| 14 | Why structured, trustworthy, useful content helps all three | "What content wins?" | Intermediate | E-E-A-T-style principles (described generically) | 6m | — | Content Studio | **externalReview** — no algorithm claims |
| 15 | Brand authority & citations | "How does brand visibility affect AI answers?" | Advanced | Authority + citations | 6m | — | Off-Page, AI Visibility | **externalReview** |
| 16 | How Digibility connects it all | "How does Digibility tie this together?" | Beginner | The operating-system view | 5m | 2–4m | all modules | grounded in blueprint |
| 17 | What Digibility does today | "What's actually live?" | Beginner | Honest current scope | 5m | — | Feature availability | grounded in status |
| 18 | What Digibility plans later | "What's coming?" | Beginner | Roadmap direction | 4m | — | Roadmap | mark direction, not dates |
| 19 | Common SEO misconceptions | "Is this myth true?" | Beginner | Debunk myths | 5m | — | — | **externalReview** |
| 20 | Beginner→advanced path | "Where do I start?" | Beginner | Guided path | 3m | — | learning paths | — |

## 8. Digibility value-proposition education (truthful framework)

Content angle (grounded in confirmed capabilities): businesses struggle when SEO
lives across **disconnected tools, spreadsheets, and providers**; reports without
an execution/approval workflow don't drive change; scattered data loses history
and accountability. **Digibility is designed to** centralize *website-centric*
work — technical audit, content, approvals, page performance, decline diagnosis,
off-page authority, and AI-visibility planning — into **one operating system**
with **role-based collaboration, client visibility, append-only history, and
insights connected to actions**, and multi-client workspace support, with a future
connection between SEO/AEO/GEO and Digibility Visibility Management.

**Approved phrasing:** "Digibility is designed to…", "Unlike a disconnected
collection of tools…", "Compared with workflows that rely on separate
spreadsheets, consultants, and point solutions…", "The intended advantage is…",
"Digibility combines…".

**How Digibility complements a team/freelancer/agency:** it can be the shared
system of record and approval layer that an internal team, freelancer, or agency
all work inside — improving visibility and accountability rather than replacing
expertise.

**Do NOT claim (explicit):**
- that Digibility is universally "better/cheaper/faster/more effective" than any
  named tool, freelancer, or agency;
- any disparagement of freelancers, agencies, consultants, or competitors;
- superiority backed only by opinion;
- that preview/mock/seeded/deferred features are live;
- any proprietary claim about how Google or AI engines rank/answer.

## 9. User roles and personalization

Frontend role is **advisory for relevance only**, never an authorization
substitute (RLS/RPC remain authoritative).

| Role | Recommended homepage | Demote/hide | Wording | Badge | Escalation |
|---|---|---|---|---|---|
| Owner | Full task + workflow + admin/agency | — | "You can…" | Owner | — (is escalation target) |
| Admin | Same as owner | — | "You can…" | Admin | Owner for billing/parent |
| Team Member | Task + workflow; demote approvals/ownership *actions* (still show "who can") | hide owner-only how-tos as primary | "Ask an owner/admin to…" for gated actions | Team | Owner/Admin |
| Client | Reading/interpreting + "what you can see"; demote all *write* how-tos | demote crawl/ownership/approval *actions* | "This is read-only for your role" | Client | Owner/Admin/Team |
| Agency | Multi-client + role + reporting | — | agency framing | Agency | — |
| SEO-only | Same; no Visibility-Management cross-refs | hide VM cross-module | — | — | — |
| SEO + Visibility | Same + a "future connection" note | — | — | — | — |
| Global admin / support | Add internal runbook (internal-only) | — | internal framing | Internal | — |

## 10. Content status and lifecycle

**Article statuses:** Draft · In review · Published · Needs update · Archived.
**Feature-readiness labels (shown as `FeatureAvailabilityBadge`):** Available ·
Available on TEST · Preview · Demo data · Mock-only · Coming later · Internal only.
**Per-article governance fields:** owner, reviewer, `lastReviewed`, `nextReview`,
`productVersion`, `linkedRoutes`, `linkedComponents`, `updateTrigger`,
`deprecation`/`redirect`. Rule: an article's feature label must match
`CURRENT_PROJECT_STATUS.md`; when a feature promotes (e.g., worker deploys), its
`updateTrigger` fires a review.

## 11. Support escalation

"Still need help?" panel → `/seo/support`. **Safely auto-attached context:** route,
product area, active **website id only if deemed safe** (prefer website *name* the
user already sees; treat the id as low-sensitivity but omit if policy prefers),
visible status label, user role, last article read, last search query.
**Never attached:** passwords, service-role keys, DNS challenge/TXT values, lease
tokens, internal worker diagnostics, raw network bodies.
**Support form fields (reuse the existing mock support flow where possible):**
subject, request type, description, (auto) safe context block, optional screenshot
reminder ("blur secrets"). Safe diagnostics mirror blueprint §23.

## 12. Success metrics (proposed; not implemented)

Search-success rate; zero-result rate; article helpfulness (%); self-service
resolution; support deflection; contextual-help click-through; task completion
after article view; escalation rate; stale-content count; top unanswered
questions. All are Phase-2 analytics; the event catalogue is in the Implementation
Plan §11.

## 13. MVP vs later phases

**MVP (no external search vendor, no AI):** bundled content corpus; client-side
search (typo + synonyms + weighting); Help Center home + category + article +
contact routes; role- and status-aware relevance; direct contextual links (Wave
1–2); feedback UI (local only); honesty labels.
**Phase 2:** richer search analytics; personalized recommendations; learning
progress; video library; feedback workflows; Help Drawer.
**Phase 3:** grounded AI assistant; semantic/vector search; multilingual; public
SEO-indexable docs (business decision); support-agent copilot.
**AI-answer guardrails (Phase 3):** answers grounded **only** in published
articles; always cite source links; feature-status-aware; no invention; safe
escalation on low confidence; never expose sensitive data.

### 13.1 Latest-practice classification
| Practice | Classification |
|---|---|
| Prominent NL search | **MVP** |
| Autocomplete/query suggestions | **MVP** |
| Typo tolerance + synonyms | **MVP** |
| Popular & recent searches | MVP (popular curated; recent local) |
| Grouped/federated results | **MVP** (grouped by category) |
| Contextual suggestions by page | **MVP** (route map) |
| Article helpfulness ratings | MVP (UI) / **Phase 2** (analytics) |
| Zero-result analytics | **Phase 2** |
| Freshness/review metadata | **MVP** (display) |
| Related articles | **MVP** |
| Recently viewed | **MVP** (local) |
| Role-aware recommendations | **MVP** |
| Learning paths | **MVP** (structure) / Phase 2 (progress) |
| Progress tracking | **Phase 2** |
| Short embedded videos | **Phase 2** |
| Article anchors/deep links | **MVP** |
| Escalation after failed self-service | **MVP** |
| Grounded AI answers + sources | **Phase 3** |
| Public SEO-indexable docs | **Phase 3** (business decision) |
| Multilingual | **Phase 3** |
| Federated external search SaaS | **Rejected for MVP** (not needed) |
