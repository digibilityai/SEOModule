# Digibility SEO Module — MVP Release-Readiness & Next-Scope Decision

**Type:** Planning / evidence-gathering only (no code, migration, DB, or
production change). **Date:** 2026-07-13.
**Authoritative sources:** `STAGE_6_FINAL_REGRESSION_SIGNOFF.md`,
`PHASE_15C/15D` sign-offs, `MODULE_LOCKS.md`, `SERVICE_LAYER_WIRING_PLAN.md`,
`CURRENT_PROJECT_STATUS.md`, `SEO_PRODUCT_BLUEPRINT_REAL_APP.md` (product
vision). Where documents differ, the most recently confirmed decision wins.

> **Update — Phase 16A (2026-07-13):** the two architecture gates blocking the
> next milestone now have **proposed decisions** (awaiting operator approval):
> **Authentication = Option C hybrid** (standalone Supabase Auth for MVP + a
> future parent-identity adapter seam) — see
> `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md`; **Crawler runtime = Option C hybrid**
> (guarded enqueue RPC/thin Edge Function control plane + a dedicated
> service-role background worker; RLS-scoped reads) — see
> `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`. The dependency-ordered build plan and
> the exact next task (**customer auth + route protection, before any crawler
> migration/worker**) are in `CRAWLER_PHASE_1_IMPLEMENTATION_PLAN.md`. Runtime
> host, budgets/consent/retention, subscription limits, and new table/column
> names remain open operator gates.
>
> **Update — Phase 16H (2026-07-14):** the **website crawler vertical slice is now
> functionally complete end-to-end on TEST** — control plane (16C), worker
> lifecycle (16D), secure discovery (16E), extraction + deterministic issues
> (16F), Page-Inventory + Audit publishing (16G), and now the **customer crawl
> request/status/freshness/cancel/result UI (16H, implemented + automated-verified;
> operator acceptance pending)**. Still required before the crawler is
> customer-operational: **production worker deployment, domain-ownership
> verification, and subscription/usage-limit enforcement** (the exact next
> milestone), plus GSC (next real data source). Recommendations remain deferred.
> See `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`.
>
> **Update — Phase 16B (2026-07-13):** the **P0 customer authentication + route
> protection** item (§6, §8) is now **implemented + TEST-validated** (login-only)
> — see `PHASE_16B_CUSTOMER_AUTH_ROUTE_PROTECTION_SIGNOFF.md`. Still open toward
> Option B: the **website crawler** (next), **GSC**, subscription/usage
> enforcement, and data-freshness UI; and the remaining P0 **production
> baseline** (deploy/CI, security/privacy, monitoring, backup). Self-service
> signup + password reset remain deferred product decisions.

---

## 0. Preflight snapshot

- **Locked modules:** Page Performance Tracker (2026-07-10); **Stage 6 —
  Off-Page Authority Workflows + AI Visibility Reads** (2026-07-13, implemented
  scope only).
- **Implemented + wired (Supabase reads/writes behind the adapter):** Website
  setup, Business Onboarding, Technical Audit + Recommendations, Approval Queue,
  Content Studio, Dashboard summaries + Admin Preview (read-only), Page
  Performance (reads), Decline Diagnosis (reads), Off-Page Authority
  (reads + opportunity + campaign workflow writes), AI Visibility (reads).
- **Partially implemented:** Page Optimizer (consumes wired `recommendationService`
  reads, no dedicated workflow); Audit (runs a `seo_run_audit` RPC that leaves a
  run "running" until a future service-role/crawler completes it — no real issue
  generation today).
- **Mock-only:** Competitor Analysis, Roadmap, Reports, Support (dedicated
  mock services); Keyword Research, Content Gaps, Blog Briefs, Settings (UI
  shells / mock).
- **Deferred integrations (none present):** website crawler, GSC, GA4, LLM/AI
  ingestion. `.env.example` contains **only** `VITE_SUPABASE_URL`,
  `VITE_SUPABASE_ANON_KEY`, `VITE_SEO_DATA_MODE` — no integration credentials.
- **Production status:** never deployed; no deploy config (`vercel.json` /
  `Dockerfile` / CI absent); no production auth/login flow (only the dev
  `/seo/dev/auth-test` harness); routes have **no `ProtectedRoute`**.
- **Known unresolved risks:** all "intelligence" runs on `manual_seed` data; no
  live ingestion; no customer auth/route gate; subscription/usage enforcement
  status unverified; benign favicon 404, sign-out `ERR_ABORTED`, ~20px mobile
  overflow (non-blocking).
- **Documentation contradictions:** none material — status docs, locks, and
  sign-offs are consistent (Stage 6 implemented-scope locked; deferred work
  open). The product blueprint describes the *target* app, not current state.

---

## 1. Current stage

**The module is a WORKFLOW / DEMO MVP — not customer-usable, not
production-ready.** It has a polished, RLS-secured, role-gated set of SEO
workflows (audit → recommendations → approvals → content → page performance →
decline diagnosis → off-page opportunities/campaigns → AI visibility) that
operate correctly — but **over seeded `manual_seed` data**. A customer who
"connects" a real website today would receive **no real, current, or actionable
data** without engineering manually seeding the database. That is the
demo-vs-customer line.

## 2. Locked foundation (protected; do not disturb)

- **Page Performance Tracker** (LOCKED).
- **Stage 6 — Off-Page Authority Workflows + AI Visibility Reads** (LOCKED,
  implemented scope): opportunity workflow, campaign creation + approval
  workflow, client/manager permission UX (create gate + shared
  `RoleGateTooltip`), AI Visibility reads (`manual_seed`); protected statuses,
  actions, roles, the 3 RPCs, 8 tables + append-only activity, service
  signatures, read-shape types, immutable migrations.
- Deferred Stage 6 work (task-completion writes, AI Visibility writes) is
  **unlocked** and open for separately-authorized **additive** extension.

## 3. Full remaining-scope route inventory

| Route | Data source | Writes | Can a real customer complete the job today? | Missing dependency | Release impact |
|---|---|---|---|---|---|
| Dashboard | wired reads (seeded) | — | No — summaries reflect seed | live data | needs data |
| Websites | wired (real) | yes | Partially — can register a site | crawler to make it useful | foundational |
| Onboarding | wired (real) | yes | Yes — captures business context | — | ready |
| Approvals | wired (real) | yes (RPC) | Workflow yes; content is seeded | upstream real data | needs data |
| Audit | wired reads + `seo_run_audit` | run RPC | No — run never produces real issues | **crawler** | blocker for value |
| Keyword Research | mock/shell | — | No | keyword data source | P2/P3 |
| Competitor Analysis | mock-only | — | No | competitor data source | P2/P3 |
| Content Gaps | mock/shell | — | No | analysis source | P2/P3 |
| Blog Briefs | mock/shell | — | No | content pipeline | P2/P3 |
| Content Studio | wired (real) | yes (RPC) | Workflow yes; inputs seeded | real opportunities | needs data |
| Page Optimizer | wired recommendation reads | — | Partial | crawler/recs source | P2 |
| Page Performance | wired reads (LOCKED, seeded) | — | No — snapshots seeded | **GSC/GA4** | blocker for value |
| Decline Diagnosis | wired reads (seeded) | — | No — needs real history | **GSC** | blocker for value |
| Off-Page Authority | LOCKED, wired reads + writes (seeded) | yes (RPC) | **Workflow yes**; opportunities seeded | opportunity source | strong demo; needs data |
| AI Visibility | wired reads (LOCKED, `manual_seed`) | mock demo | No — seeded/read-only | **LLM ingestion** | cannot market as live |
| Roadmap | mock-only | — | No | backend | P3 |
| Support | mock-only | — | No | backend/ops | P3 |
| Reports | mock-only | — | No | reporting pipeline | P2/P3 |
| Settings | mock/shell | — | No | settings backend | P2 |
| Admin Preview | wired read-only summary (temporary) | — | Internal only | final admin panel | admin track |
| Dev routes | dev harness | n/a | Dev only | remove/guard for prod | P0 (guard) |

**Key finding:** even the "wired" intelligence modules read tables that are
currently filled by `manual_seed`, not by real ingestion. Rendering ≠ wired to
live data.

## 4. Deferred workflow writes

### 4.1 Campaign task-completion writes
- **Customer value:** moderate. Campaigns are usable for *planning + approval*
  today; checklist completion adds execution tracking ("work through together").
- **Operationally incomplete without them?** No for a planning/approval MVP;
  yes if campaigns are sold as execution trackers.
- **Dependencies:** a guarded task-transition/complete path + activity row;
  likely a small additive RPC (or reuse) + append-only activity.
- **Impact on locked Stage 6:** touches the LOCKED module → **additive
  extension only**, must preserve all protected contracts, re-run Phase 15D +
  Stage 6 regression.
- **Verdict:** **Not required before release; safely post-MVP (P2).**

### 4.2 AI Visibility writes
- **What "writes" means (design intent, partially confirmed):** create/edit
  tracked prompts; run a visibility analysis; create AI content-gaps; record
  mentions. **Confirmed:** reads work; writes + real ingestion are deferred;
  service has no insert/update/delete/rpc; the "Generate" button is an explicit
  **mock** generator. **Unknown:** which of these are user-initiated vs
  system-ingested, and the exact intended UX.
- **Marketable while seeded/read-only?** **No.** Advertising "track your AI
  visibility" on demo data would be misleading. AI Visibility should be labeled
  *preview/coming-soon* until LLM ingestion exists.
- **Verdict:** writes depend on ingestion; **P2**, gated behind LLM ingestion.

## 5. Live-data roadmap (assessed independently)

### 5.1 Website crawler — **highest-leverage, build first**
Likely responsibilities: site discovery, page inventory, technical-issue
detection, metadata/content extraction, internal-link analysis, crawl status +
errors, scheduling/recrawl, ownership + crawl-safety controls. **Dependencies
on it:** Audit (issues), Page Optimizer/Recommendations, Page Inventory,
Off-Page opportunity discovery all ultimately need crawler output; without it
"connect your site" delivers nothing. **Architecture note:** a crawler is a
background service-role ingestion job — it does **not** violate the frontend
"no BFF" rule, but it requires a runtime host (Supabase Edge Function or an
external worker) → **decision gate**.

### 5.2 Google Search Console — **build second**
Value: real queries, impressions, clicks, CTR, average position, page/query
mapping, performance history. **Consumers:** Page Performance and Decline
Diagnosis (which today read seeded snapshots). Moderate effort (OAuth + periodic
pull). Highest-signal *real SEO* source after the crawler.

### 5.3 Google Analytics 4 — **later (P2), not automatic**
Traffic/behaviour/conversion context. **Not required** for the core SEO promise;
few current modules strictly need it. Recommend **only** when a module's
customer value genuinely depends on it — do not add it reflexively.

### 5.4 LLM / AI-visibility ingestion — **separate track (P2)**
Real AI Visibility needs external LLM observations (prompt runs, brand/competitor
mention extraction, content-gap detection) rather than seeded demo rows.
Required before AI Visibility can be sold as live.

### 5.5 Recommended ingestion sequence
**Crawler → GSC → (GA4 and LLM ingestion later, in parallel).**
Crawler first: it is the foundation the audit/opportunity/inventory modules
depend on and the "connect a site and get *something* real" unlock. GSC second:
highest-value real SEO data with manageable OAuth, and it makes Page Performance
+ Decline Diagnosis real. GA4/LLM after, as value-add tracks.

## 6. Operational release gaps

- **P0 — Customer authentication + route protection:** no login flow, no
  `ProtectedRoute` (routes rely solely on data-layer RLS). Approach is a
  **decision gate** (standalone auth vs reuse parent Digibility auth — currently
  deferred). Dev routes must be guarded/removed for prod.
- **P0 — Production baseline:** deploy config/CI-CD (absent), security review,
  privacy/legal for crawling + external integrations (consent, robots, PII),
  backup/rollback, monitoring/logging, error recovery. Mostly **unknown/absent**.
- **P1 — Subscription/usage enforcement:** Stage 1 tables exist
  (`seo_plan_limits`, `seo_subscriptions`, `seo_usage_events`,
  `user_module_access`); enforcement wiring is **unverified** → required for a
  *paid* MVP.
- **P1 — Data-freshness + integration-status UI:** once live data exists, users
  must see source, last-updated, and connection health.
- **Present/adequate today:** loading/empty/error states and workspace/website
  selection (observed working in regression); background jobs, rate limits,
  notifications = absent (tie to ingestion tracks).

## 7. Marketing / customer-value test (strict)

| Feature | Solves | Real result today? | Data basis | Honestly advertisable today? | Minimum to make marketable |
|---|---|---|---|---|---|
| Off-Page workflow | organize authority work | Workflow yes, data no | seed | as a *workflow/demo* only | real opportunity source |
| Technical Audit | find site issues | No | seed | No | crawler |
| Page Performance | track rankings/traffic | No | seed | No | GSC (+GA4) |
| Decline Diagnosis | explain drops | No | seed | No | GSC history |
| AI Visibility | track AI/LLM presence | No | seed | No | LLM ingestion |
| Content Studio | plan/produce content | Workflow yes, inputs no | seed | as a *workflow* only | real inputs |
| Onboarding/Websites | set up account | Yes | real | Yes | — |

**Bottom line:** a polished UI over seeded data is **not** a customer outcome.
Today's only honest external claim is "a structured SEO workflow platform
(demo/seeded data)."

## 8. P0–P3 roadmap (dependency-ordered)

> For each: *touches-locked* flagged; all DB work **additive migrations only**;
> all changes must preserve existing APIs/routes/types/status/action/role values.

### P0 — Required before ANY customer release
1. **Customer auth + route protection** (login flow or parent-auth integration +
   `ProtectedRoute`; guard/remove dev routes). *Value:* prevents unauthorized
   use; real accounts. *Deps:* auth-approach decision. *Modules:* `SeoRoutes.tsx`,
   a new auth/guard layer. *DB:* none or additive session/profile mapping.
   *API:* none (Supabase auth). *Frontend:* additive (route wrappers).
   *Permissions:* aligns UI with existing RLS. *Backward-compat:* additive.
   *Tests:* auth + gated-route tests. *Rollback:* remove guards. *Touches locked:* no.
2. **Production baseline** (deploy/CI, security review, crawl/privacy compliance,
   backup/rollback, monitoring). *Value:* safe operation. *Deps:* infra decision.
   *Mostly ops, not app code.* *Touches locked:* no.

### P1 — Required for a credible paid MVP
3. **Website crawler (ingestion foundation)** — see §5.1. *Value:* the core
   "connect your site, get real audit/inventory." *Deps:* crawler-host decision.
   *Modules:* new ingestion job (Edge Function/worker) + additive tables/columns
   feeding Audit/Page-Inventory reads. *DB:* additive migrations. *API:* none for
   frontend (reads unchanged). *Frontend:* freshness/status UI (additive).
   *Touches locked:* Page Performance reads (LOCKED) consume inventory — **read
   contract unchanged; additive only**. *Tests:* ingestion + smoke against
   existing read shapes. *Rollback:* disable job; drop additive tables.
4. **GSC integration** — see §5.2. *Value:* real performance + decline history.
   *Deps:* OAuth + crawler-independent. *Modules:* ingestion job + additive
   snapshot rows consumed by the LOCKED Page Performance / Decline reads —
   **additive, read shape preserved**. *Touches locked:* yes (read-only, additive).
5. **Subscription/usage enforcement** (wire Stage 1 plan/usage tables). *Value:*
   monetization + limits. *DB:* likely additive checks/RPCs. *Touches locked:* no.
6. **Data-freshness + integration-status UI.** *Frontend additive.* *Touches locked:* no.

### P2 — Shortly after launch
7. **GA4 integration** (only where value justifies). 8. **LLM / AI-visibility
   ingestion** → unlocks real AI Visibility (additive extension of the LOCKED
   AI-Visibility reads + new writes). 9. **Campaign task-completion writes**
   (additive Stage 6 extension). 10. Real data for keyword/competitor/content-gap/
   blog-brief/reports modules (or keep clearly labeled "preview").

### P3 — Later expansion
Notifications; scheduling/recrawl orchestration; advanced admin ops; deeper
parent-platform integration; Roadmap/Support real backends; mobile-overflow +
polish.

## 9. Release-path options

### Option A — Ship the Workflow/Demo MVP (as-is)
- **Included:** all current workflows over seeded data. **Excluded:** all live
  data. **Promise:** "structured SEO workflow platform (demo)." **Risks:**
  misleading if positioned as real intelligence. **Audience:** internal, sales
  demos, design partners. **Paid customers:** **No.** **Exit criteria:** demo
  script + clear "demo data" labeling + dev routes guarded.

### Option B — Minimum Customer-Usable MVP (recommended)
- **Included:** P0 (auth + route protection + prod baseline) + **crawler** +
  **GSC** + subscription/usage enforcement + freshness/status UI, on top of the
  locked workflow foundation. **Excluded:** live AI Visibility, GA4, campaign
  task-completion, mock modules (labeled "preview"). **Promise:** "connect your
  site → real technical audit + real Search Console performance → guided
  fix/opportunity/campaign workflow." **Risks:** crawler/GSC integration effort;
  crawl privacy/compliance. **Audience:** real paying SMBs/agencies (scoped
  promise). **Paid customers:** **Yes**, honestly scoped. **Exit criteria:**
  crawler + GSC produce real per-site data; auth/route protection live;
  usage/subscription enforced; freshness visible; regression green.

### Option C — Broader Production-Ready Launch
- **Included:** Option B + GA4 + LLM/AI-visibility ingestion + campaign
  task-completion + real content/keyword modules + full ops (monitoring,
  notifications, support, admin). **Excluded:** none material. **Promise:** full
  "SEO + AI-visibility intelligence suite." **Risks:** longest timeline, most
  integration + compliance surface, higher delay vs B. **Audience:** broad paid
  GA. **Paid customers:** Yes. **Exit criteria:** all live sources + ops SLAs.

## 10. Recommendation

**Choose Option B — the Minimum Customer-Usable MVP.**
Rationale: the locked workflow foundation is solid and honestly demoable, but the
product's *promise* ("SEO Intelligence") requires **real data**; the smallest
honest path to a paid product is the two highest-value real SEO sources
(**crawler → GSC**) plus the **P0 auth/route-protection + production baseline**,
with subscription enforcement. GA4, LLM/AI-visibility writes, campaign
task-completion, and mock modules can follow post-launch without breaking the
core promise. This maximizes honest marketability and time-to-market while
respecting the locked Stage 6 foundation and backward compatibility (everything
additive). Option A risks a misleading launch; Option C over-invests before
validating demand.

## 11. Exact next implementation milestone (do not start yet)

**Website Crawler — Phase 1: authenticated, additive crawl-ingestion foundation.**
Bounded scope: site discovery + page inventory + basic technical-issue detection
for a customer-owned website, written to **new additive tables/columns** consumed
by the already-wired **Audit** and **Page Inventory / Page Performance** reads —
**without changing any locked read shape or Stage 6 contract**. Explicitly
in-scope: crawl status/error surfacing and website-ownership + crawl-safety
(robots/rate) controls. Explicitly out-of-scope for this milestone: GSC/GA4/LLM,
scheduling/recrawl orchestration, and any change to locked workflow behaviour.
**Hard prerequisite decision gate:** the crawler runtime host (Supabase Edge
Function vs external worker) and the customer-auth approach — both require
operator approval before implementation.

## 12. Explicit deferred scope (unchanged, not defects)

Campaign task-completion writes; AI Visibility writes; GA4; LLM ingestion;
external/scheduled jobs; parent-platform/BFF integration; production deployment;
Competitors/Roadmap/Reports/Keyword/Content-Gap/Blog-Brief real backends;
mobile-overflow; favicon/sign-out observations.

## 13. Known unknowns

- Subscription/usage-limit **enforcement** wiring status (tables exist; behavior
  unverified).
- Intended AI Visibility **write** UX (user-initiated vs system-ingested).
- Crawler + integration **runtime host** and infra (no BFF/app-server today).
- Customer **auth** approach (standalone vs parent Digibility).
- Production infra: CI/CD, monitoring, backup, security/privacy review — absent
  or unverified.

## 14. Decision gates requiring operator approval

1. **Release path** — approve Option A / **B** / C.
2. **Customer auth approach** — standalone vs reuse parent Digibility auth.
3. **Crawler runtime host** — Supabase Edge Function vs external worker.
4. **Compliance** — crawl consent/robots/PII + external-integration privacy.
5. **Scope of the paid promise** — which modules ship "live" vs "preview."
6. Approval to begin the §11 next milestone (crawler Phase 1).

_No implementation performed. No application code, migration, SQL, locked
behaviour, or production configuration changed._
