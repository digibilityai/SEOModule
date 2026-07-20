# Digibility SEO Intelligence — End-to-End User Journey & Support-Content Blueprint

> **DRAFT for ChatGPT review — not yet authoritative.** This is the master
> customer-journey and support-content source for the Digibility SEO Intelligence
> module. It is a documentation/product-analysis artifact only; it changed no
> code, DB, or production state.

---

## 1. Document status and purpose

- **This is the master customer-journey and support-content source** for the SEO
  module. Help-center articles, onboarding docs, role manuals, in-app guidance,
  FAQs, troubleshooting, videos, and report-reading guides should be derived from
  it (see the decomposition plan in §26 and the production matrix file).
- **Repository behaviour is authoritative.** Every capability below was validated
  against routes, components, hooks, services, RPCs, role gates, and states in the
  code — not inferred from names. The implementation-evidence appendix (§27) maps
  each journey to its source.
- **`CURRENT_PROJECT_STATUS.md` controls current implementation status.** Where
  this document and that file disagree about *status*, that file wins.
  `MODULE_LOCKS.md` controls protected scope; owner/sign-off docs control accepted
  behaviour.
- **Honesty labels are mandatory.** Every feature is tagged with one of:
  - **OPERATIONAL (TEST)** — Supabase-wired and working on the `Digi_SEO_Test`
    project, reading/writing real rows, but over **seeded `manual_seed` demo
    data**; not promoted to production.
  - **MOCK-ONLY** — runs entirely on a local deterministic mock adapter; writes
    nothing to Supabase.
  - **PLACEHOLDER** — a stub page that states "Feature work has not started yet."
  - **PREVIEW / SEEDED** — reads exist but the data is hand-seeded demo content,
    not live market/AI intelligence.
  - **DEFERRED** — designed but not built (e.g. live ingestion, production deploy).
- **No undocumented capability may be presented as available.** In particular:
  **the whole module is TEST-only and not production-deployed; the crawler worker
  is not deployed; there is no live crawler / GSC / GA4 / LLM ingestion.** These
  constraints are repeated wherever they affect the user.

### 1.1 The single most important honesty caveat

Across every section, remember and repeat to users where relevant:

> Digibility SEO is currently a **test/preview build**. Data you see is
> **seeded demo data** unless you have just entered it yourself. Real website
> crawling, Google Search Console / GA4 metrics, backlink data, and AI-model
> visibility are **not yet live**. A crawl you start is recorded correctly, but
> it will remain **Queued** until an operator runs the background worker — it is
> not yet a self-service, always-on crawl.

---

## 2. Product orientation

**What it is (user language).** Digibility SEO Intelligence is an *SEO execution
cockpit*: a place where a business, agency, or team turns SEO findings into
tracked, approvable actions. It is organised around **websites** — every audit,
page, keyword, recommendation, diagnosis, content draft, off-page opportunity,
and report is attached to one website.

**Who it is for.** Founders and businesses running their own SEO; agencies
managing SEO for multiple client websites; team members executing work; and
clients who need visibility and light participation. It is a paid add-on that can
run standalone (SEO-only) or alongside Digibility Visibility Management.

**Website-centric data model.** You always work "inside" one **active website**
within a **workspace**. Switching the active website changes what every module
shows. Nothing is global — everything is scoped to the selected website.

**How it differs from a simple SEO dashboard.** It is not just charts. It adds:
a **role-and-approval layer** (recommendations and authority campaigns move
through submit/approve/reject states with an append-only activity trail);
**domain-ownership verification** before crawling; a **crawl → audit → page
inventory** pipeline; a **decline-diagnosis** interpretation layer; and
**content** and **off-page authority** workflows.

**How insights become actions.** Audit issues → recommendations → approval queue
→ (content or on-page work) → tracked in reports. Performance drops → decline
diagnoses → recommendations/owners. Off-page opportunities → authority campaigns
→ approval.

**Major product areas.** Dashboard; Websites & onboarding; Domain ownership;
Website Audit + Crawl; Page Performance + Page Inventory; Decline Diagnosis;
Recommendations + Approval Queue; Content Studio; Off-Page Authority + Campaigns;
AI Visibility; Competitors; Roadmap; Reports; Support; Settings; Admin preview.

**First day / week / month expectation.**
- **Day 1:** sign in → add/select a website → complete business onboarding →
  verify domain ownership → start a first crawl (understanding it stays Queued in
  this build).
- **Week 1:** review the seeded audit, page inventory, and performance; walk the
  approval queue; explore Content Studio and Off-Page opportunities in preview.
- **Month 1:** establish a weekly review rhythm; interpret decline diagnoses;
  run authority campaigns through approval; read the (mock) reports as a format
  preview. Treat all data as demo until live ingestion ships.

---

## 3. Personas and permission model

Authorization is enforced by **Supabase RLS + `SECURITY DEFINER` RPCs**; the
frontend role gates are *affordances only* (they hide/disable controls but never
grant permission). SEO roles live in `seo_workspace_members`
(`owner` / `admin` / `team_member` / `client`) and are **workspace-scoped**.

### 3.1 Role capability matrix (verified against RPC/RLS gates)

| Capability | Owner | Admin | Team Member | Client | Global Admin |
|---|---|---|---|---|---|
| View all website-scoped modules (member read) | ✅ | ✅ | ✅ | ✅ (read) | ✅ |
| Add / manage websites | ✅ | ✅ | ✅* | ❌ | ✅ |
| Edit business onboarding | ✅ | ✅ | ✅* | ❌ (read) | ✅ |
| Initiate/recheck/reverify/revoke **domain ownership** | ✅ | ✅ | ❌ (read-only) | ❌ (read-only) | (not exposed in customer UI) |
| **Start / cancel a crawl** | ✅ | ✅ | ✅ | ❌ (disabled + tooltip) | ✅ |
| Approve/reject recommendations & campaigns | ✅ | ✅ | ❌ | ❌ | ✅ |
| Submit / create / return-to-draft (workflow) | ✅ | ✅ | ✅ | ❌ | ✅ |
| Off-page opportunity **reject** | ✅ | ✅ | ❌ | ❌ | ✅ |
| Off-page other transitions (shortlist/start/complete/etc.) | ✅ | ✅ | ✅ | ❌ | ✅ |
| Global-admin override / admin preview (`/seo/admin-preview`) | ❌ | ❌ | ❌ | ❌ | ✅ |

\* Manager write roles (`owner`/`admin`/`team_member`) can write most workspace
content; **domain ownership** is the stricter exception — **owner/admin only**
(tooltip: *"Requires the owner or admin role."*). **Crawl** allows
`owner`/`admin`/`team_member` (tooltip for client: *"Requires the owner, admin,
or team member role."*).

### 3.2 Per-persona notes

- **Owner** — full control incl. ownership verification, billing (parent, not in
  this module), team/client management (parent). Daily: check crawls/approvals.
  Weekly: review performance + approvals. Escalation target for others.
- **Admin** — same as owner for SEO operations incl. ownership + approvals.
- **Team Member** — executes: can add websites, edit onboarding, start crawls,
  create/submit content and campaigns, act on off-page opportunities — but
  **cannot verify domain ownership**, **cannot approve/reject**, and cannot
  reject off-page opportunities. Escalates approvals + ownership to owner/admin.
- **Client** — **read-only** across the app. Sees status, reports, published
  results; **cannot** start crawls, verify ownership, approve, or write. Disabled
  controls show accessible tooltips. Escalates any action to owner/admin/team.
- **Global Admin** — internal; the only role that can open `/seo/admin-preview`
  and (at the DB layer) perform ownership admin-override. Not a customer-facing
  everyday role; relevant to support only as "an internal operator."
- **SEO-only user** — identical experience; SEO does not require Visibility
  Management. Access is gated by `has_seo_module_access`.
- **User with SEO + Visibility Management** — same SEO experience; cross-module
  data exchange is **DEFERRED** (documented intent, not built here).
- **Agency managing multiple client websites** — uses the **workspace + active
  website** model: one workspace per client (or per portfolio), switching the
  active website to move between clients. All data is scoped to the selected
  website; there is no cross-client aggregate dashboard in this build.

**Escalation route when an action is unavailable:** if a control is disabled with
a role tooltip, the user must ask a workspace **owner or admin** (for
ownership/approvals) or an **owner/admin/team member** (for crawls/content) to
perform it. If the whole module is inaccessible, it is an entitlement
(`has_seo_module_access`) or workspace-membership issue → owner/admin/support.

---

## 4. End-to-end journey map

Legend: **OPERATIONAL (TEST)** · **MOCK-ONLY** · **PLACEHOLDER** · **PREVIEW/SEEDED** · **DEFERRED**

| # | Stage | Prerequisite | Responsible role | Expected output | Next action | Blocking conditions | Status |
|---|---|---|---|---|---|---|---|
| 1 | Receive access | Digibility account + SEO entitlement | Owner/Admin (grants), parent platform | Able to reach `/seo/login` | Sign in | No `has_seo_module_access` | OPERATIONAL (TEST) |
| 2 | Sign in | Existing Supabase user | Any | Session; land on dashboard | Select/add website | Wrong credentials; no entitlement | OPERATIONAL (TEST) |
| 3 | Select/create workspace | Session | Owner/Admin | Active workspace | Add website | No workspace → onboarding/setup | OPERATIONAL (TEST) |
| 4 | Add/select website | Workspace | Owner/Admin/Team | Active website set | Onboarding | Client cannot add | OPERATIONAL (TEST) |
| 5 | Business onboarding | Website | Owner/Admin/Team | Saved onboarding profile | Verify ownership | Client read-only | OPERATIONAL (TEST) |
| 6 | Verify domain ownership | Website | **Owner/Admin only** | Status → verified | Start crawl | Team/Client read-only; DNS not propagated | OPERATIONAL (TEST) |
| 7 | Start first crawl | **Ownership = verified** | Owner/Admin/Team | Crawl job = Queued | Monitor | **Unverified → rejected**; client disabled | OPERATIONAL (TEST); worker not deployed |
| 8 | Monitor crawl | A crawl job | Any (read) | Live status | Review audit on completion | Stays Queued (no worker running) | OPERATIONAL (TEST); DEFERRED live run |
| 9 | Review audit output | A completed audit (seeded) | Any (read) | Issue list | Prioritize issues | No completed audit yet | PREVIEW/SEEDED |
| 10 | Prioritize issues | Audit issues | Owner/Admin/Team | Ranked work | Recommendations | — | PREVIEW/SEEDED |
| 11 | Review Page Inventory | Seeded/crawled pages | Any (read) | Page list | Analyze performance | No pages | PREVIEW/SEEDED |
| 12 | Analyze Page Performance | Snapshots (seeded) | Any (read) | Metrics + movement | Investigate declines | No data | OPERATIONAL (TEST), data seeded |
| 13 | Investigate decline | Diagnoses (seeded) | Owner/Admin/Team | Diagnosis interpretation | Recommendations | No diagnoses | PREVIEW/SEEDED (read-only) |
| 14 | Review recommendations | Recommendations (seeded) | Owner/Admin/Team | Action candidates | Approval | — | OPERATIONAL (TEST) reads |
| 15 | Submit/approve work | Approval items | Owner/Admin approve; Team submit | State transition | Content/on-page work | Client read-only | OPERATIONAL (TEST) |
| 16 | Build SEO content | Content records (seeded) | Owner/Admin/Team | Draft workflow | Off-page | Client read-only | OPERATIONAL (TEST); generation not real |
| 17 | Review Off-Page opportunities | Opportunities (seeded) | Owner/Admin/Team | Shortlist/actions | Campaigns | Client read-only | OPERATIONAL (TEST) |
| 18 | Create/approve campaigns | Opportunities | Owner/Admin approve; Team create | Campaign workflow | AI Visibility | Client read-only | OPERATIONAL (TEST) |
| 19 | Review AI Visibility | Seeded reads | Any (read) | Prompt/mention/gap views | Reports | — | PREVIEW/SEEDED (reads only) |
| 20 | Review reports/progress | — | Any (read) | Report format | Set cadence | — | MOCK-ONLY |
| 21 | Operating rhythm | Above | All roles | Daily/weekly/monthly habit | Repeat | — | Guidance (§20) |

---

## 5. Authentication and access journey

**Login route:** `/seo/login` (public, chromeless — rendered outside the app
shell). All other `/seo/*` routes are wrapped in `<ProtectedRoute>` (Supabase
mode). **Mock mode bypasses protection entirely.**

| State | What the user sees | Meaning | User should | Support should check |
|---|---|---|---|---|
| Login page | Card "Sign in to Digibility SEO", email + password, "Sign in" button | Start of session | Enter existing Digibility credentials | Route is `/seo/login`; app in Supabase mode |
| Valid login | Redirect to `/seo/dashboard` (or `returnTo`) | Authenticated + entitled | Proceed | Session established |
| Invalid login | Inline: *"Invalid email or password. Please try again."* | Bad credentials | Re-enter / reset via parent | Not a lockout; credentials only |
| Anonymous deep-link | Redirect to `/seo/login?returnTo=<path>` | Not signed in | Sign in; will return to intended page | `returnTo` preserved; no content leaked |
| Session restore (refresh) | Same page reloads, still signed in | Session persisted | Continue | Query cache re-reads from Supabase |
| Sign-out | Header "Sign out" → `/seo/login`; protected content gone | Ended session | Sign back in | `useSeoSignOut` clears user-scoped cache + active website |
| Cross-user isolation | New sign-in shows only that user's data | `SessionSync` cleared prior cache | — | No stale cross-user data/selection |
| Access-required (module) | "Access required" state (variant=module) with Retry/Sign out | No `has_seo_module_access` | Request SEO entitlement | Entitlement flag on the account |
| No workspace | Setup routes render; feature routes redirect to website setup | User has no workspace | Complete setup/onboarding | Workspace membership |
| No active website | Redirect to `/seo/websites` (setup) | Zero accessible websites | Add a website | Website exists + active |
| Resolution error | Error state with Retry/Sign out | Access resolver failed (network/RPC) | Retry; if persists, support | Supabase connectivity |
| Global-admin preview | `/seo/admin-preview` renders only for global admins; others get access-required (variant=admin) | Internal preview | (internal only) | `seo_is_global_admin` |
| Dev routes | `/seo/dev/supabase-readiness`, `/seo/dev/auth-test` — **development builds only** | Not in production | Ignore in prod | `import.meta.env.DEV` |
| Mock-mode bypass | No login required; deterministic preview; "Preview" labels | `VITE_SEO_DATA_MODE=mock` | Understand nothing is saved to Supabase | Data mode |

**Login screen shot requirements:** capture the login card; a failed-login inline
message; the post-login dashboard. **Blur** any real email. Video: 30–60s
"How to sign in" micro-guide.

---

## 6. Navigation and website context

- **App shell** = Sidebar + Header wrapping every protected route (`ShellLayout`).
- **Sidebar** header reads **"SEO Intelligence"**. **(Updated 2026-07-20 —
  superseded description below; this paragraph originally described a flat
  list and is retained only for the registry's item inventory, not for
  navigation structure.)** As of the collapsible-navigation information
  architecture, the sidebar renders SEO as one top-level collapsible module
  (SEO Dashboard first, then 7 collapsible logical groups: Setup, Research &
  Strategy, Audit & Optimization, Content, Off-Page & AI Visibility, Reports
  & Workflow, Settings & Support) rather than a flat list — see
  `DIGIBILITY_SEO_COLLAPSIBLE_NAVIGATION_INFORMATION_ARCHITECTURE.md` for the
  authoritative structure. The underlying item inventory (module registry,
  status `active`, plus the fixed extra pages: Keyword Research, Content
  Gaps, Blog Briefs, Settings, Help Center) is unchanged: SEO Setup &
  Connections (`/seo/websites`), Business Onboarding (`/seo/onboarding`),
  **SEO Dashboard** (`/seo/dashboard` — renamed from "Visibility Dashboard";
  "Visibility" is a separate Digibility module and must not be used as a
  synonym for SEO), Technical SEO
  Audit (`/seo/audit`), On-Page SEO Autopilot (`/seo/page-optimizer`), Approval
  Queue (`/seo/approvals`), Content Studio (`/seo/content-studio`), Page
  Performance Tracker (`/seo/page-performance`), Decline Diagnosis Engine
  (`/seo/decline-diagnosis`), Off-Page Authority Builder (`/seo/off-page`), AI
  Visibility / GEO Engine (`/seo/ai-visibility`), Competitor Benchmarking
  (`/seo/competitor-analysis`), 90-Day SEO Roadmap (`/seo/roadmap`), Expert
  Support Desk (`/seo/support`), Progress Reports (`/seo/reports`). Registry
  status `later` (not shown / not built): SEO Guardrail Monitor
  (`/seo/guardrail`), Content Trust Review (`/seo/content-trust`).
- **Header** exposes **Sign out** (via `useSeoSignOut`). The **active website** is
  resolved via `ActiveWebsiteContext`/`useResolvedActiveWebsite`; website-scoped
  routes require an active website or redirect to `/seo/websites`.
- **Active-website behaviour:** every website-scoped module reads the currently
  active website; switching it changes all module data. Refresh persists the
  selection (context + user-scoped cache).
- **Empty state (no website):** feature routes redirect to `/seo/websites` to add
  one; setup routes (`/seo/onboarding`, `/seo/websites`) remain reachable.
- **Agency multi-client workflow:** switch the active website to move between
  clients; confirm the website name shown before acting.

> **⚠️ Repeat on every website-scoped screen:** *All data shown belongs to the
> currently selected website. Confirm the website name before acting.*

**Incorrect-site troubleshooting:** if numbers look wrong, first confirm the
active website matches the intended one; switching site + refresh resolves most
"wrong data" reports.

---

## 7. Website setup and business onboarding

### 7.1 Add a website — `WebsiteForm` (on `/seo/websites`)

| Field | Label | Type | Required | Format / example | Validation | Later use |
|---|---|---|---|---|---|---|
| website_url | Website URL | text | ✅ | `https://www.example.com` | Non-empty; http(s) enforced server-side at crawl time | Crawl target; ownership host; audits/pages scope |
| name | Website name | text | ✅ | `Acme Plumbing - Main Site` | Non-empty | Display label |
| business_name | Business name | text | ✅ | `Acme Plumbing` | Non-empty | Reporting/context |
| website_type | Website type | select | (default `service`) | service/other | Enum | Context |

Validation message when a required field is blank: *"Website URL, website name and
business name are required."* Roles: owner/admin/team_member may add (client
cannot). Save creates the website in Supabase (OPERATIONAL, TEST). Loading/success
states via the mutation; refresh persists.

### 7.2 Business onboarding — `/seo/onboarding` (`BusinessOnboardingPage`)

Fields (labels verified): **Services / products**, **Target audience**, **Main
SEO goal** (select), **Target locations** (one per line), **Competitors** (one per
line, URLs), **Proof / trust signals**, **Important pages** (one URL per line),
**Preferred content tone** (select), **Sensitive industry** (toggle/select),
**Notes / context**. All are edited by owner/admin/team_member; client is
read-only. Saved to Supabase (OPERATIONAL, TEST); refresh persists.

**Downstream use — honest scope:** onboarding is stored and surfaced as context
in several modules that read it (e.g., competitor/roadmap/support pages import
`fetchOnboardingByWebsiteId`). **Do NOT claim** that onboarding automatically
drives audit findings, keyword research, or AI generation — those consumers are
mock/placeholder or seeded. Onboarding is currently a **stored profile + context
seam**, not an automation input, in this build.

**Shots:** empty form; filled form; save success; a validation error. Video:
2–4 min "Complete your business profile."

---

## 8. Domain ownership verification — **OPERATIONAL (TEST), LOCKED (P1a)**

Panel: `OwnershipVerificationPanel` inside each `WebsiteCard` on `/seo/websites`.
Source of truth: `seo_ownership_verifications` (`method='dns_txt'`). Writes go
only through the Step-2A RPCs (`initiate`/`recheck`/`reverify`/`revoke`).

### 8.1 Lifecycle states

| Status | Badge | Explanatory text | Owner/Admin actions | Team/Client |
|---|---|---|---|---|
| unverified | "Not verified" | "…hasn't been verified yet." | **Verify ownership** (initiate) | read-only + role note |
| pending | "Verification pending" | DNS TXT instructions shown | **Check again** (recheck), **Re-verify (new record)**, **Revoke** | read-only |
| verified | "Verified" | "Ownership verified for `<host>` on `<date>`." | **Re-verify**, **Revoke** | read-only |
| failed | "Verification failed" | customer-safe reason + DNS instructions | **Check again**, **Re-verify** | read-only |
| revoked | "Verification revoked" | "Start a fresh verification…" | **Verify ownership** | read-only |

### 8.2 DNS instructions & actions

- **Type:** `TXT`. **Host:** `_digibility-site-verification.<host>` (copyable).
  **Value:** the challenge token (copyable). Copy buttons announce "Copied"
  (accessible). Propagation note: *"DNS changes can take some time to propagate.
  After adding the record, choose 'Check again'."*
- **Verify ownership** creates the pending challenge. **Check again** re-checks
  **reusing** the same token (no new record). **Re-verify (new record)** rotates
  the token (use when the DNS host changed or the token was lost). **Revoke** is a
  two-step confirm (destructive; append-only history preserved).
- **Double-submit protection:** a per-action lock (`idle → in_flight → cooldown →
  idle`, fixed 3000 ms) — the first click fires immediately; rapid repeat clicks
  are ignored; after ~3.5 s the control re-enables and a deliberate later click is
  a *legitimate new* recheck.

> **🔒 Security note for users and support:** the DNS TXT **Value/challenge token**
> is a verification secret for this website. It is safe to place in your DNS zone,
> but **never paste it into a support chat, email, or screenshot.** Support must
> never request it.

### 8.3 UI-accepted vs worker-executed vs actually-verified (critical)

Three distinct things — keep them separate:
1. **UI action accepted** — the RPC recorded your initiate/recheck (HTTP 200).
2. **Worker path executed** — the background `verify-once` worker actually
   performed a **real DNS lookup**. In this build the worker is **not deployed**;
   a recheck records intent but a real DNS resolution only happens when an
   operator runs the worker.
3. **Domain actually verified** — status flips to **verified** only when a real
   TXT record matching the challenge is found by that worker run.

So "Verification pending" after adding your TXT record is expected here — it does
not mean failure; it means the automated checker has not run against your DNS yet.

**Common DNS mistakes:** wrong host (must be the exact
`_digibility-site-verification.<host>`), value altered/truncated, record on the
wrong domain/subdomain, or checking before propagation. Real failures show a
**customer-safe reason** (e.g., record not found / value mismatch); resolver
internals are never shown.

**How ownership affects crawl eligibility (P1b):** a crawl can only be started
when ownership status is currently **verified**. Unverified/pending/failed/revoked
→ the crawl request is **rejected** by the server with: *"Domain ownership must be
verified before this website can be crawled."*

**Shots:** each of the 5 states; DNS instruction block (blur the token value);
the revoke two-step confirm; team-member/client read-only view. Video: 2–4 min
"Verify your domain ownership" (blur token).

---

## 9. Website crawl journey — **OPERATIONAL (TEST); worker NOT deployed**

Panel: `CrawlPanel` + `StartCrawlControl` on `/seo/audit`. Enqueue RPC:
`seo_crawl_request_audit` (returns both audit-run and crawl-job ids). Status
source: Supabase only, polled every 4 s while active.

- **Prerequisite:** ownership = **verified** (P1b). **Roles:** owner/admin/team
  may Start/Cancel; **client** sees the button disabled + tooltip *"Requires the
  owner, admin, or team member role."*
- **Start crawl** opens a two-step confirmation ("Start a crawl of `<url>`?"
  with scope notes) → **Confirm crawl**.
- If ownership is not verified, the confirm returns the P1b rejection message.

### 9.1 Status meanings (customer language)

| Status | Label | System is doing | User should | Next transition |
|---|---|---|---|---|
| queued | Queued | Job recorded, waiting for a worker | Wait; in this build it stays queued until an operator runs the worker | claimed |
| claimed | Preparing | A worker took the job | Wait | running |
| running | Crawling | Fetching public pages within budget | Wait; don't start another (blocked) | completed/partial/failed |
| retry_wait | Waiting to retry | A transient issue; scheduled retry | Wait | running or failed |
| cancellation_requested | Cancelling | Your cancel is being acknowledged | Wait | cancelled |
| completed | Completed | Results published to Audit + Page Inventory | Review audit/pages | terminal |
| partially_completed | Partially completed | Some pages done; results published | Review; consider re-crawl later | terminal |
| failed | Failed | Crawl could not complete | Check status; re-crawl later; contact support if persistent | terminal |
| cancelled | Cancelled | You cancelled it | Prior published results remain | terminal |

- **Freshness** is computed from **real timestamps** (never the browser clock).
  Counters shown are customer-safe (pages discovered/crawled, issues) — never
  lease tokens/worker ids.
- **Polling:** 4 s while active, **stops at terminal**, **pauses on a hidden
  tab**, reconciles on refresh. Refresh restores the true status from Supabase.
- **Cancellation** is only offered in legal states and is idempotent
  (`cancellation_requested → cancelled`).
- **Single-active-job:** only one active crawl per website; a second start while
  one is active is refused ("An active crawl already exists for this website").
- **Prior published results are preserved:** a failed/cancelled attempt never
  deletes the newest previously-completed audit/inventory.

> **Worker-retry vs new crawl:** a **worker retry** is the system re-attempting an
> *existing* job (same crawl, `retry_wait → running`). **Starting a new crawl** is
> a *new* job that must pass ownership + single-active-job checks. They are
> different; a retry does not require you to click anything.

**Shots:** confirm dialog; each status badge; a rejected start on an unverified
site; client disabled button + tooltip. Video: 2–4 min "Start and monitor a
crawl" + a 30–60s "What the crawl statuses mean" micro-guide.

---

## 10. Audit journey — **PREVIEW/SEEDED (reads OPERATIONAL on TEST)**

Page: `WebsiteAuditPage` (`/seo/audit`), which also hosts the crawl panel.

- Shows the **most recent completed audit** for the active website; a crawl is
  **explicitly linked** to its audit run (no "latest guess").
- **Audit issues** are presented with **severity** (critical/high/medium/low
  mapped from crawler severities), **category**, **page vs site scope**, and
  bounded **evidence**. Site-level issues use the real website URL (no fabricated
  page).
- **Filters / empty states:** an empty audit shows a no-data state until a crawl
  publishes results. A failed/cancelled crawl does not overwrite a prior completed
  audit.
- **Audit score limitation:** publishing writes technical facts and issues but
  **does not compute a headline SEO score** in this build — do not present a
  numeric "SEO score" as authoritative.
- Links out to **Page Inventory / Page Performance**.

**Severity interpretation:** critical/high = fix first, likely needs owner/admin
approval if it touches URLs/redirects/canonical/robots; medium/low = backlog.

**Honesty:** current audit data is **seeded demo** unless a real worker crawl has
published — treat findings as illustrative.

---

## 11. Recommendations and approval workflow — **OPERATIONAL (TEST)**

- **Recommendations** are read from Supabase (seeded) and surfaced on the audit /
  page-optimizer surfaces (`recommendationService`, `PageOptimizerPage` reads
  on-page recommendations). **There is no live automatic recommendation
  generation** (no crawler/LLM producing them) — they are seeded/service-role
  content in this build.
- **Approval Queue** (`/seo/approvals`, `ApprovalQueuePage`): approval items with
  **comments** and **activity** that are **append-only**. Implemented transitions
  move items through their states via the guarded RPC; **owner/admin** approve/
  reject, managers submit; **client is read-only**. Invalid transitions are
  rejected by the backend (surfaced verbatim). Refresh persists.

**Separate clearly:** the *approval workflow* is implemented; *automatic
recommendation generation* is not.

**Shots:** approval list; a comment thread; an approve and a reject; client
read-only. Video: 2–4 min "Approve or reject recommendations."

---

## 12. Content Studio journey — **OPERATIONAL (TEST); generation is placeholder**

Page: `ContentStudioPage` (`/seo/content-studio`). Backed by the Stage 3 Content
Studio tables + `seo_content_transition` RPC (`contentStudioService`).

Implemented areas (seeded/real records): **opportunities, keyword plan,
competitor summary, wireframe, formatting inputs, draft, sections, section
revisions, comments, activity, assets**. Workflow uses **review states** and
**transition actions**; client visibility is limited to specific review states
(`wireframe_client_review` / `draft_client_review`); comments/activity/section
revisions are **append-only**.

**Assets / private storage:** files live in a **private** Storage bucket
(`seo-content-assets`); MIME allow-list (PDF/DOCX/PNG/JPEG/WEBP allowed;
SVG/ZIP/EXE blocked). **No real upload flow is wired in the UI yet** — treat
asset upload as **DEFERRED**; asset metadata/policies exist at the DB layer.

> **Label honestly:** drafts/wireframes are **placeholders/seeded**, not
> AI-generated content. "Generate" style actions do not call a real LLM in this
> build.

**Shots:** the studio surface + each content area; a state transition; client
review-only view. Video: 5–10 min "Content Studio workflow" (label preview data).

---

## 13. Page Inventory and Page Performance — **OPERATIONAL (TEST), LOCKED; data SEEDED**

Page: `PagePerformancePage` (`/seo/page-performance`). LOCKED module (Page
Performance Tracker). Reads `seo_page_inventory` + `seo_page_performance_snapshots`
via `performanceService`.

Columns/data: **page URL**, **crawler-owned vs user-owned** fields, **mapped
keywords**, **clicks**, **impressions**, **CTR**, **average position**, **period
comparisons (deltas)**, **movement status** (improving/stable/declining/new/
no_data), **freshness**, and **source** (`manual_seed`/`gsc`/`ga4`/`system`/
`import` — **all seeded rows are `manual_seed`; there is no live GSC/GA4**).

- **Website selection + filters** scope the list; **empty/no-data** states appear
  when a page/keyword has no snapshot.
- **Why a page may be missing:** it was never seeded/crawler-discovered.
- **Why prior page data remains after a later crawl:** publishing is
  preservation-safe (crawler updates only crawler-owned facts, never deletes
  unseen pages, preserves user-owned fields).

### 13.1 Metric interpretation

| Metric | Plain-English | ↑ means | ↓ means | False-signal risk | Compare with | Action | Don't conclude |
|---|---|---|---|---|---|---|---|
| Clicks | Visits from search | More search traffic | Less traffic | Seasonality; seeded demo data | Prior period; same page | Investigate declines | Cause from clicks alone |
| Impressions | Times shown in results | More visibility | Less visibility | Query-mix shifts | Prior period | Check ranking/coverage | That CTR is fine |
| CTR | Clicks ÷ impressions | More compelling listing | Listing less compelling | Small sample; position change | Position + title/meta | Improve title/meta | Content is bad |
| Avg position | Mean ranking | Better ranking | Worse ranking | Volatile for new pages | Impressions + clicks | Content/technical/links | Traffic will follow 1:1 |
| Movement | Direction label | Positive trend | Negative trend | `no_data`/`new` noise | Underlying metrics | Prioritize decliners | It's live if source=`manual_seed` |

> **Repeat:** Page Performance data here is **seeded (`manual_seed`)**, not live
> Google data. Use it to learn the format, not to make real business decisions yet.

**Shots:** inventory list; a page's metrics with deltas + movement; empty state;
the `manual_seed` source label. Video: 5–10 min "Reading Page Performance."

---

## 14. Decline Diagnosis journey — **PREVIEW/SEEDED, read-only**

Page: `DeclineDiagnosisPage` (`/seo/decline-diagnosis`). Reads Stage 5
`seo_decline_diagnoses` (+ current view) via the Supabase decline service.

Shows diagnosis cards/rows: **diagnosis type** (ctr_drop / ranking_decline /
clicks_decline / impressions_decline / content_freshness / indexing_issue /
cannibalization_risk / intent_mismatch / competitor_improvement /
technical_performance / no_data / mixed_signals), **severity**, **confidence**,
**priority**, **status**, **suggested owner**, structured **evidence** +
snapshot metrics, a **current view** (excludes dismissed), and a nullable link to
a recommendation.

> **Honesty:** these are **deterministic, hand-seeded demo diagnoses**, not live
> AI diagnoses. `linked_recommendation_id` is a seam; **no create/update/delete
> is wired** in the UI — it is **read-only**.

### 14.1 Interpretation decision process
1. Confirm data freshness (seeded here).
2. Identify the affected page + keyword.
3. Classify the decline (clicks / impressions / CTR / ranking / technical /
   content / intent / competitor / cannibalization / mixed).
4. Compare the evidence rows/snapshot metrics.
5. Decide the owner (use the suggested owner as a hint).
6. Decide urgency from severity/priority/confidence.
7. Decide the next action (usually a recommendation or content/technical task).
8. Track the outcome in the approval/reporting flow.

**Shots:** diagnosis list; one card's evidence; the current-view vs dismissed
behavior. Video: 5–10 min "Diagnosing a ranking/traffic decline" (label seeded).

---

## 15. Off-Page Authority journey — **OPERATIONAL (TEST), LOCKED (Stage 6)**

Page: `AuthorityBuilderPage` (`/seo/off-page`). Reads via `offPageService`;
transitions via `seo_authority_opportunity_transition`.

- **Overview + opportunity cards** with statuses: `suggested`, `shortlisted`,
  `approval_required`, `in_progress`, `expert_review_requested`, `completed`,
  `rejected`, `avoided`.
- **Actions:** `shortlist`, `request_approval`, `request_expert_review`, `start`,
  `complete`, **`reject`** (owner/admin **only**), `avoid`. Other actions:
  owner/admin/team_member. **Client is read-only.** Append-only activity records
  each transition with the actor's role snapshot.
- **Spam-risk review** section and **filters**; refresh persists.

**Evaluate an opportunity:** relevance to the business; domain quality; spam/risk
(use the spam-risk review); estimated effort; strategic fit → then choose
shortlist / request approval / request expert review / avoid; **reject** if
clearly unsuitable (owner/admin). Approval is required where the status path
demands it.

**Shots:** opportunity board; each action; the reject role restriction; client
read-only + tooltip. Video: 5–10 min "Evaluating off-page opportunities."

---

## 16. Authority Campaign journey — **OPERATIONAL (TEST), LOCKED (Stage 6)**

Builder: `CampaignBuilder` / `CampaignList` on the same page. Create via
`seo_authority_campaign_create`; transitions via
`seo_authority_campaign_transition`.

- **Select opportunities** (role-gated selection: client cannot select/create) →
  **campaign builder inputs** → **Create campaign** (atomic; creates a **draft**
  with linked opportunities + generated tasks; **no** creation activity row).
- **Transitions:** `submit_for_approval`, `approve` (owner/admin only), `reject`
  (owner/admin only), `return_to_draft`. **"Return to Draft" is exposed only from
  `rejected`.** Role tooltips gate disabled buttons; double-submit is prevented;
  refresh persists; activity is append-only.
- **Not available:** campaign **editing/deletion** and **task-completion writes**
  are **DEFERRED** (not built).

### 16.1 State diagram (text)
```
draft ──submit_for_approval──▶ pending_approval ──approve──▶ approved (terminal)
                                     │
                                     └──reject──▶ rejected ──return_to_draft──▶ draft
```
(owner/admin: approve/reject; owner/admin/team_member: create/submit/return;
client: read-only.)

**Shots:** opportunity selection (gated for client); builder; create → draft;
submit → pending; approve and reject; return-to-draft from rejected. Video:
5–10 min "Create and approve an authority campaign."

---

## 17. AI Visibility journey — **PREVIEW/SEEDED, read-only**

Page: `AiVisibilityPage` (`/seo/ai-visibility`). Reads via `aiVisibilityService`
(Stage 6 read-only, LOCKED).

- **Read-only views:** prompt tracking (incl. a time-series), mentions, content
  gaps. **Filters + empty states.** Data source label is **`manual_seed`**.
- There is a clearly separated **mock-generation control** (preview), distinct
  from the seeded reads.
- **Writes and real LLM ingestion are NOT implemented** — AI Visibility must be
  treated as a **preview**.

> **Do not present** prompt-tracking/mentions/content-gaps here as live market or
> AI-model intelligence. It is seeded demo content until LLM ingestion ships.

**Shots:** each read view; the time-series; the `manual_seed`/Preview labels.
Video: 2–4 min "AI Visibility (preview)" — clearly labelled preview.

---

## 18. Competitors, Roadmap, Reports, integrations, settings — status by module

| Module | Route | Status | Current UX (honest) |
|---|---|---|---|
| Competitor Benchmarking | `/seo/competitor-analysis` | **MOCK-ONLY** | Reads/writes a local mock (`competitorService`); imports onboarding for context; nothing saved to Supabase |
| 90-Day Roadmap | `/seo/roadmap` | **MOCK-ONLY** | `roadmapService` mock; onboarding context |
| Progress Reports | `/seo/reports` | **MOCK-ONLY** | `reportService` mock; a report *format* preview, not real analytics |
| Expert Support Desk | `/seo/support` | **MOCK-ONLY** | `supportService` mock request flow |
| Keyword Research | `/seo/keyword-research` | **PLACEHOLDER** | "Feature work has not started yet." |
| Content Gaps | `/seo/content-gaps` | **PLACEHOLDER** | Placeholder |
| Blog Briefs | `/seo/blog-briefs` | **PLACEHOLDER** | Placeholder |
| On-Page SEO Autopilot | `/seo/page-optimizer` | **OPERATIONAL (TEST) read** | Reads on-page recommendations (seeded); no live rewriting |
| Settings | `/seo/settings` | see §18.1 | Connection status placeholders |
| Admin preview | `/seo/admin-preview` | Internal, global-admin only | Temporary read-only composition; final Admin Panel is the parent platform (DEFERRED) |
| GSC / GA4 / backlinks | — | **DEFERRED** | Not integrated; `seo_connection_status` holds placeholders; `source` accepts `gsc`/`ga4` as placeholder values only |
| File upload | Content Studio | **DEFERRED** | Bucket/policies exist; no UI upload flow |
| Billing / subscription / usage limits | — | **DEFERRED** | Tables exist; no enforcement/gateway wired |
| Parent Digibility integration / BFF | — | **DEFERRED** | Future additive seam |

### 18.1 Settings & connection status
`SeoSettingsPage` surfaces connection status; real GSC/GA4/CMS/GBP connections are
**not** wired (placeholders). Present Settings as configuration + status display,
not as a live integration hub.

---

## 19. Report interpretation framework

Reusable method for any report/dashboard widget:
1. Confirm the **website** and date range.
2. Confirm the **data source** (here: usually `manual_seed` / mock — flag it).
3. Confirm **freshness** (timestamp).
4. Check **crawl/audit status** (is the underlying data current?).
5. Identify **critical/high** issues.
6. Review **page-level** performance changes (deltas + movement).
7. Review **diagnosis** evidence.
8. Review **pending approvals**.
9. Review **content + authority** work in progress.
10. Decide **actions, owners, deadlines**.
11. Record follow-up.
12. Recheck on the correct cadence (§20).

Per-widget template (apply to each dashboard card / report):
what it measures · source · calculation (if discoverable) · freshness · healthy
reading · warning reading · critical reading · next action · common
misinterpretation · role that should act. **Always annotate mock/seeded widgets
as "preview/demo data" so no one reports on it as real.**

Dashboard: `SeoDashboardPage` reads summaries via `dashboardService`
(Supabase-wired on TEST over seeded data). Treat dashboard numbers as demo.

---

## 20. Recommended operating cadence

Because the build is TEST/preview, cadence guidance is about **learning the
workflow and format**; mark data as demo in any real report.

### Daily (owner/admin/team)
- Open `/seo/audit` → check for **failed/running** crawls on active sites.
- Open `/seo/approvals` → new items to approve/reject (owner/admin) or submit
  (team).
- Off-page/campaigns: any awaiting approval.
- Note: crawls will sit **Queued** without a worker — that is expected here.

### Weekly (owner/admin/team)
- Start/review a crawl per active site (understanding the worker caveat).
- Review technical issue movement in the audit.
- Review Page Inventory + Page Performance movement; list decliners.
- Review Decline Diagnosis current view.
- Advance the content pipeline (Content Studio).
- Triage Off-Page opportunities/campaigns.
- Glance at AI Visibility **(labelled preview)**.

### Monthly (owner/admin)
- Compare reporting periods (format preview).
- Identify wins/losses (demo data caveat).
- Prioritize technical fixes into recommendations/approvals.
- Update the content plan; review completed/overdue actions.
- Prepare client reporting (mark as preview).

### Quarterly (owner/admin)
- Website architecture review; competitor reassessment (mock);
  content portfolio review; authority strategy; integration/data-quality review
  (note deferred integrations); business-goal alignment.

For each item record: role owner, exact page(s) to open, filter/date range, what
to record, recommended action, and evidence to save. **Decision thresholds** are
only asserted where the product defines them (e.g., single-active-job, verified-
only enqueue, approval role gates); otherwise treat thresholds as judgment.

---

## 21. Troubleshooting catalogue

Format: **Symptom · Likely meaning · User checks · Support checks · Safe
resolution · What not to do · Escalation evidence.**

1. **Cannot log in** · bad credentials · re-enter; reset via parent · confirm
   Supabase mode + account exists · retry/reset · don't share password · route,
   timestamp, "Invalid email or password" seen.
2. **Redirected to login on a deep link** · not signed in · sign in (returnTo
   returns you) · confirm `returnTo` preserved · sign in · — · route attempted.
3. **"Access required" (module)** · no `has_seo_module_access` · request
   entitlement · check entitlement flag · grant entitlement (parent) · don't
   re-create account · account id, timestamp.
4. **Wrong workspace/site data** · active website mismatch · switch site + refresh
   · confirm active website · switch site · don't assume data is wrong · site name
   shown.
5. **No website** · zero websites · add one (`/seo/websites`) · confirm role can
   add · add website · client can't add → escalate · role, route.
6. **Onboarding required** · missing profile · complete `/seo/onboarding` ·
   confirm read/write role · save onboarding · — · —.
7. **Ownership pending after adding TXT** · worker hasn't checked yet (not
   deployed) · wait; "Check again" · confirm worker run scheduled · operator runs
   verify-once · **don't share the token** · host, status, timestamp.
8. **Ownership failed** · TXT not found/mismatch · re-check host/value; propagation
   · confirm reason (customer-safe) · fix DNS; Check again/Re-verify · don't paste
   token · failure reason text, host.
9. **Ownership action missing** · team_member/client (read-only) · ask owner/admin
   · confirm role · owner/admin acts · — · role.
10. **Crawl button unavailable** · client role or active job exists · ask owner/
    admin/team; wait for active job · confirm role/active job · appropriate role
    starts · — · role, current crawl status.
11. **Crawl rejected (ownership unverified)** · P1b gate · verify ownership first ·
    confirm ownership status · verify then retry · don't retry repeatedly · exact
    message, ownership status.
12. **Crawl queued too long** · **worker not deployed** in this build · expected;
    wait/operator · confirm environment · operator runs worker · don't assume
    failure · job status, timestamp.
13. **Retry wait** · transient issue; auto-retry scheduled · wait · confirm retry
    scheduling · none needed · don't cancel prematurely · status, attempt count.
14. **Crawl failed** · could not complete · re-crawl later · check event trail
    (internal) · re-crawl · don't spam start · status, timestamp.
15. **Cancellation still pending** · `cancellation_requested` acknowledgement in
    progress · wait · confirm worker ack · wait · don't force · status.
16. **Audit empty** · no completed crawl/seed · run/await crawl · confirm audit
    link · await results · — · site, audit status.
17. **Page inventory empty** · no seeded/crawled pages · await crawl/seed · confirm
    site · — · — · site.
18. **Performance "no data"** · no snapshot / `no_data` movement · expected for
    unseeded pages · confirm source=`manual_seed` · — · don't read as a real drop ·
    page, source.
19. **Stale metrics** · seeded/older snapshot · check freshness label · confirm
    source · — · don't treat as live · freshness timestamp.
20. **Diagnosis missing** · none seeded / dismissed · check current view · confirm
    seed · — · — · page.
21. **Action disabled due to role** · role gate · read the tooltip; escalate ·
    confirm role · correct role acts · — · tooltip text, role.
22. **Campaign transition unavailable** · illegal transition or role · check state
    (e.g., Return-to-Draft only from rejected) · confirm state/role · correct
    role/state · — · campaign state, role.
23. **Client cannot write** · by design (read-only) · escalate to owner/admin/team
    · confirm role · manager acts · — · role.
24. **Mock/preview data confusion** · app in mock mode or seeded data · look for
    "Preview"/`manual_seed` labels · confirm data mode · explain preview · don't
    report demo data as real · data mode.
25. **Seeded AI Visibility confusion** · preview data · note `manual_seed` ·
    confirm · explain preview · don't present as live · —.
26. **Refresh doesn't show expected result** · action not committed / different
    site / eventual read · refresh; confirm site · confirm write succeeded · re-do
    action · — · action, site, timestamp.
27. **Cross-user/session concern** · sign-out clears cache; SessionSync isolates ·
    sign out/in · confirm isolation · — · — · —.
28. **Generic backend error** · RPC/validation/authorization error surfaced
    verbatim · read message; retry · check RLS/RPC error · fix inputs/role · don't
    retry blindly · exact message, route.
29. **Production feature not yet available** · DEFERRED (GSC/GA4/LLM/live crawl/
    billing) · set expectations · confirm roadmap status · communicate timeline ·
    don't promise dates · feature name.

---

## 22. Glossary

Workspace; Active website; Owner/Admin/Team member/Client/Global admin; Domain
ownership verification; DNS TXT challenge/token; Verified/Pending/Failed/Revoked;
Crawl; Crawl statuses (Queued/Preparing/Crawling/Waiting to retry/Cancelling/
Completed/Partially completed/Failed/Cancelled); Single-active-job; Verified-only
enqueue; Audit run; Audit issue; Severity; Page Inventory; Snapshot; Clicks/
Impressions/CTR/Average position; Movement status; Source (`manual_seed`/gsc/ga4);
Freshness; Decline diagnosis; Recommendation; Approval item; Append-only activity;
Content Studio; Draft/Section/Revision/Asset; Off-page opportunity; Authority
campaign; AI Visibility; `manual_seed`; Preview/Mock mode; Deferred. (Each term
gets a one-line customer definition in the derived glossary article.)

---

## 23. Support-agent diagnostic checklist

**Never ask a user to share:** passwords, service-role keys, DNS challenge/TXT
values, lease tokens, or internal worker diagnostics.

**Safe to request:** affected workspace + website name; the route/URL; the user's
role; the visible status/label; a timestamp; a screenshot **with secrets hidden**;
the **name + HTTP status** of a failing network request (not its body); a browser
console message; the last successful action; and whether they tried refresh /
sign-out-and-in.

**Safe sequence:** confirm data mode (mock vs Supabase) → confirm active website →
confirm role → reproduce the state → read the on-screen message → map to the
troubleshooting entry (§21) → resolve or escalate with the evidence above.

---

## 24. Documentation and video-production requirements

For each journey section, the derived assets need: screenshots (states listed per
section), video shots (cursor actions through the happy path + key error), a
narration outline, **sensitive values blurred** (emails, DNS token, any ids that
look secret), the **role/account** required, the **starting fixture/state**, the
**expected end state**, and a **reset procedure** (e.g., revoke ownership;
cancel/await crawl; delete disposable content). Video length guidance:
- **30–60s micro-guide:** login; crawl-status meanings; ownership badge meanings.
- **2–4 min task guide:** add website; onboarding; verify ownership; start crawl;
  approve/reject; AI Visibility preview.
- **5–10 min workflow guide:** Content Studio; Page Performance; Decline Diagnosis;
  Off-page + campaigns; reading a report.
- **Full onboarding webinar:** day-1 → month-1 end-to-end (with the TEST/preview
  caveats stated up front).

Each video must open with the honesty caveat (§1.1) when it shows seeded/preview
data.

---

## 25. Known limitations and future updates (consolidated, evidence-based)

- **MOCK-ONLY:** Competitors, Roadmap, Reports, Support; mock data mode overall.
- **PLACEHOLDER (not started):** Keyword Research, Content Gaps, Blog Briefs;
  registry `later` items (SEO Guardrail Monitor, Content Trust Review).
- **PREVIEW/SEEDED:** Audit results, Page Performance (`manual_seed`), Decline
  Diagnosis, AI Visibility reads, dashboard summaries — real, but demo data.
- **TEST-VERIFIED, not production-promoted:** entire module; crawler control-plane
  → worker → discovery/extraction/publishing (16C–16H); P1a domain ownership
  (LOCKED); P1b verified-only enqueue (LOCKED). Nothing is in production.
- **DEFERRED integrations:** live website crawling (worker not deployed), GSC,
  GA4, backlinks, real LLM/AI-visibility ingestion, real recommendation/content
  generation, file upload UI, billing/subscription/usage enforcement, parent-
  Digibility/BFF integration, cross-module data exchange.
- **Unimplemented writes:** Decline Diagnosis (read-only), AI Visibility writes,
  campaign edit/delete + task completion, Content Studio real generation/upload.
- **Optional enhancement:** the P1b UI defense-in-depth (disable Start crawl when
  unverified) is designed but not built (server enforcement is authoritative).

---

## 26. Support-document decomposition plan

Generate these standalone documents from this master (see File 2 for the full
production backlog): Getting started · Login and access · Website setup ·
Business onboarding · Domain ownership · Starting and monitoring a crawl ·
Understanding crawl statuses · Reading an audit · Fixing technical issues · Page
Inventory · Page Performance · Decline Diagnosis · Recommendations · Approval
workflow · Content Studio · Off-Page opportunities · Authority campaigns · AI
Visibility · Reports · Role and permissions · Agency/multi-client workflow ·
Troubleshooting · FAQ · Glossary · Daily/weekly/monthly checklist.

---

## Required interaction table (actionable screens)

Secrets are never shown. "Data source" reflects the *current* build.

| Step | Route / screen | User role | Starting state | User action | User input | Frontend validation | Trusted system action / RPC / data source | Loading | Success output | Error/denied output | Meaning | Next action | Refresh persistence | Support evidence | Shot |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `/seo/login` | Any | Signed out | Sign in | email, password | required fields | `supabase.auth.signInWithPassword` | "Signing in…" | Redirect to dashboard/returnTo | "Invalid email or password." | Session established | Select website | Session persists | route, timestamp | login card |
| 2 | `/seo/websites` | Owner/Admin/Team | No/other website | Add website | url, name, business name, type | 3 required fields | insert `seo_websites` (websiteService) | button pending | Website appears/active | required-field message; client disabled | Website created | Onboarding | persists | role, site name | form + success |
| 3 | `/seo/onboarding` | Owner/Admin/Team | Website active | Save onboarding | profile fields | per-field | upsert onboarding (businessOnboardingService) | pending | Saved | validation/denied (client) | Profile stored | Verify ownership | persists | site | form + save |
| 4 | `/seo/websites` (panel) | Owner/Admin | unverified | Verify ownership | — | double-submit lock | `seo_ownership_verification_initiate` | disabled ~3.5s | pending + DNS TXT shown | RPC error verbatim; team/client read-only | Challenge created | Add TXT, Check again | persists | host, status | panel (blur token) |
| 5 | `/seo/websites` (panel) | Owner/Admin | pending | Check again | — | per-action lock | `seo_ownership_verification_recheck` | disabled ~3.5s | still pending (worker not run) | RPC error verbatim | Re-check reused token | Wait for worker | persists | host, status | panel |
| 6 | `/seo/websites` (panel) | Owner/Admin | verified | Revoke (confirm) | confirm | two-step | `seo_ownership_verification_revoke` | pending | revoked | RPC error | Ownership revoked | Re-verify if needed | persists | status | confirm dialog |
| 7 | `/seo/audit` (CrawlPanel) | Owner/Admin/Team | verified, no active job | Start crawl → Confirm | — | confirm step; disabled if client/active | `seo_crawl_request_audit` | "Starting…" | Queued job + linked audit | **"Domain ownership must be verified…"** (unverified); "active crawl already exists"; client disabled+tooltip | Crawl enqueued | Monitor status | persists (Supabase) | site, ownership, status | confirm + badge |
| 8 | `/seo/audit` (CrawlPanel) | Owner/Admin/Team | active job | Cancel | — | legal-state only | `seo_crawl_cancel` | pending | cancellation_requested→cancelled | RPC error | Cancel acknowledged | Await terminal | persists | job status | status card |
| 9 | `/seo/approvals` | Owner/Admin | pending item | Approve/Reject | — | role gate | approval transition RPC | pending | state updated + activity row | denied (team/client); illegal transition | Decision recorded | Next item | persists | item id, role | list + action |
| 10 | `/seo/approvals` | Team | draft/pending | Submit | — | role gate | approval transition RPC | pending | submitted | denied (client) | Submitted for approval | Await approval | persists | item, role | list |
| 11 | `/seo/content-studio` | Owner/Admin/Team | a content item | Transition | — | role/state gate | `seo_content_transition` | pending | state updated + activity | denied/illegal | Content advanced | Next stage | persists | item, state | studio |
| 12 | `/seo/off-page` | Owner/Admin/Team | opportunity | shortlist/start/complete/avoid | — | role/state gate | `seo_authority_opportunity_transition` | pending | status updated + activity | reject denied (team); client read-only | Opportunity advanced | Build campaign | persists | opp id, role | board |
| 13 | `/seo/off-page` | Owner/Admin | opportunity | Reject | — | owner/admin only | `seo_authority_opportunity_transition` (reject) | pending | rejected | denied (team/client) | Opportunity rejected | — | persists | opp id | board |
| 14 | `/seo/off-page` (builder) | Owner/Admin/Team | opportunities selected | Create campaign | builder inputs | client gated; double-submit | `seo_authority_campaign_create` | pending | draft campaign + tasks | denied (client) | Campaign drafted | Submit for approval | persists | campaign id | builder |
| 15 | `/seo/off-page` (list) | Owner/Admin | pending_approval | Approve/Reject | — | owner/admin only | `seo_authority_campaign_transition` | pending | approved/rejected + activity | denied (team/client) | Decision recorded | (rejected→return) | persists | campaign id | list |
| 16 | `/seo/off-page` (list) | Owner/Admin/Team | rejected | Return to Draft | — | shown only from rejected | `seo_authority_campaign_transition` (return_to_draft) | pending | draft | denied (client) | Reopened for edits | Resubmit | persists | campaign id | list |

---

## 27. Appendix — customer journey → implementation evidence

| Journey | Route / component | Service / hook | RPC / table | Owner doc / lock | Status |
|---|---|---|---|---|---|
| Auth / route protection | `SeoLoginPage`, `routes/ProtectedRoute`, `SeoRoutes` | `useSeoAccess`, `useSeoSignOut`, `SessionSync` | `has_seo_module_access`, `seo_is_global_admin` | `PHASE_16B_...SIGNOFF.md` | OPERATIONAL (TEST) |
| Websites / onboarding | `WebsitesPage`, `WebsiteForm`, `BusinessOnboardingPage` | `websiteService`, `businessOnboardingService` | `seo_websites`, `seo_business_onboarding` | Stage 1 | OPERATIONAL (TEST) |
| Domain ownership | `OwnershipVerificationPanel` in `WebsiteCard` | `useOwnershipVerification*`, `ownershipVerificationService` | `seo_ownership_verifications`, Step 2A RPCs | `P1A_..._SIGNOFF.md`; MODULE_LOCKS P1a | OPERATIONAL (TEST), LOCKED |
| Crawl | `audit/crawl/{CrawlPanel,StartCrawlControl,CrawlStatusCard,CrawlStatusBadge}` | `useWebsiteCrawl`, `crawlService` | `seo_crawl_request(_audit)`, `seo_crawl_cancel`, `seo_crawl_jobs` | `PHASE_16H_...SIGNOFF.md`, `OPERATOR_TEST_RESULTS.md`; Crawler lock | OPERATIONAL (TEST); worker DEFERRED |
| Verified-only enqueue | (server) | — | `seo_crawl_request` guard (`20260719120034`) | `P1B_..._SIGNOFF.md`; MODULE_LOCKS P1b | OPERATIONAL (TEST), LOCKED |
| Audit | `WebsiteAuditPage` | `auditService` | `seo_audit_runs`, `seo_audit_issues` | Stage 2 / 16G publishing | PREVIEW/SEEDED |
| Recommendations / approvals | `PageOptimizerPage`, `ApprovalQueuePage` | `recommendationService`, `approvalService` | approval transition RPC; `seo_approval_*` | Stage 2 | OPERATIONAL (TEST) |
| Content Studio | `ContentStudioPage` | `contentStudioService` | `seo_content_transition`; Stage 3 tables; storage bucket | Stage 3 | OPERATIONAL (TEST); generation DEFERRED |
| Page Performance / Inventory | `PagePerformancePage` | `performanceService` | `seo_page_inventory`, `seo_page_performance_snapshots` | `PHASE_14A_...`; MODULE_LOCKS Page Performance | OPERATIONAL (TEST), LOCKED; SEEDED |
| Decline Diagnosis | `DeclineDiagnosisPage` | `seoDeclineDiagnosisSupabaseService` | `seo_decline_diagnoses` (+view) | Stage 5 / `PHASE_14B_...` | PREVIEW/SEEDED, read-only |
| Off-Page + Campaigns | `AuthorityBuilderPage`, `offpage/*` | `offPageService` | `seo_authority_*` + 3 RPCs | `PHASE_15C/15D`, `STAGE_6_...`; MODULE_LOCKS Stage 6 | OPERATIONAL (TEST), LOCKED |
| AI Visibility | `AiVisibilityPage` | `aiVisibilityService` | `seo_ai_*` | Stage 6; MODULE_LOCKS Stage 6 | PREVIEW/SEEDED, reads only |
| Competitors/Roadmap/Reports/Support | respective pages | `competitorService`/`roadmapService`/`reportService`/`supportService` | — (mock) | — | MOCK-ONLY |
| Keyword/Content-Gaps/Blog-Briefs | placeholder pages | — | — | — | PLACEHOLDER |
| Dashboard | `SeoDashboardPage` | `dashboardService` | summary reads | — | OPERATIONAL (TEST), SEEDED |
| Admin preview / dev | `SeoAdminPreviewPage`, `dev/*` | `seoAdminService` | `seo_is_global_admin` | Phase 16B | Internal / dev-only |

### Documentation-conflict handling
Where sources disagree: **`CURRENT_PROJECT_STATUS.md` wins for status**,
**`MODULE_LOCKS.md` for protected scope**, **owner/sign-off docs for accepted
behaviour**. No unresolved conflict was found while drafting; any future conflict
must be flagged here rather than silently resolved.

---
*End of blueprint (draft). No code, database, or production state was changed to
produce this document.*
