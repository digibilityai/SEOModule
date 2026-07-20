> ## ⚠️ SUPERSEDED — this handover has been consolidated
>
> **As of 2026-07-20, the authoritative context package is the four `SEO_*` files.
> START A NEW SESSION FROM [`SEO_CONTEXT_HANDOVER.md`](SEO_CONTEXT_HANDOVER.md)**,
> then follow its reading order (`SEO_IMPLEMENTATION_STATUS.md` →
> `SEO_PROJECT_CONTEXT.md` → `SEO_DECISIONS.md` → `MODULE_LOCKS.md`).
>
> This file is **retained as historical evidence** (a dated running handover log
> maintained across earlier sessions). Its detailed dated entries remain a useful
> record, but for *current* state the four authoritative files and
> `CURRENT_PROJECT_STATUS.md` win. Do not treat the body below as the current
> frontier. See `PROJECT_DOCUMENTATION_INDEX.md` for the full authority hierarchy.

---

# ChatGPT Context Handover — Digibility SEO Intelligence Module

**Purpose:** a compact, self-contained brief so a fresh ChatGPT development-oversight
thread can recover this project without reading the whole documentation library.
**Last updated:** 2026-07-20 (**Collapsible SEO Navigation Information
Architecture — IMPLEMENTED AND VERIFIED**, frontend-only. Replaced the flat
20-item sidebar with SEO as one collapsible top-level module (default
expanded — currently the only module) containing **SEO Dashboard standalone
first**, then 7 collapsible groups in journey order: Setup, Research &
Strategy, Audit & Optimization, Content, Off-Page & AI Visibility, Reports &
Workflow, Settings & Support. New `src/registry/navigationGroups.ts`
(additive, doesn't touch `SeoModule`'s type/other consumers);
`Sidebar.tsx` rewritten with native-button disclosure (`aria-expanded`/
`aria-controls`, no new dependency), state persisted via the existing
`ActiveWebsiteContext` localStorage convention, auto-expand-only-never-
auto-collapse on active route. **"Visibility Dashboard" → "SEO Dashboard"**
in `moduleRegistry.ts` (only occurrence in code; "Visibility" is a separate
Digibility module) — internal `id: "visibility-dashboard"` deliberately kept
for backward compatibility (not user-visible). Legitimate unrelated
"visibility" terms (`VisibilityScoreCard`s search-visibility metric, "AI
Visibility / GEO Engine" SEO/GEO concept) left untouched; new group named
"Off-Page & AI Visibility" (not "Authority & Visibility") so "Visibility"
never stands alone as a module reference. No plan/role filtering added — only
pre-existing `status === "active"` filter, live-verified unchanged. **No
mobile nav drawer exists in this codebase** (verified, not assumed) — building
one was correctly treated as out of scope (shell-level redesign); existing
`hidden md:block` mobile behavior preserved exactly, verified at 375px. Help
Center: audited all 30 public articles (zero existing "Visibility Dashboard"
occurrences); added an additive "Finding your way around" section to
`getting-started-with-digibility-seo` + `"visibility dashboard"` as a
search-only synonym; content validation PASS, 0 findings, unchanged corpus.
Verified: `tsc`/build clean; live module/group toggle + deep-link
auto-expansion + active-route highlighting + no duplicate links + protected
routes still protected + public Help Center still public + no console errors
+ no overflow at 375/768/1280px. See
`DIGIBILITY_SEO_COLLAPSIBLE_NAVIGATION_INFORMATION_ARCHITECTURE.md`. Prior
update — 2026-07-20 (Help Center **Wave 3 — Deferred Surfaces & Final
Sign-Off — COMPLETE; Help Center is DEVELOPMENT-COMPLETE**. Zero-code-change
sign-off wave. Re-audited the four Wave-2C-deferred candidates against current
code + locks and **closed all four without implementation**, each with
evidence: Roadmap header (no dedicated article; own `ROADMAP_SAFETY_NOTICE`
inline; adjacent Generate mutation button), Competitor header (no competitor
article; the only general option `preview-data-versus-live-data` is redundant —
the surface already states its mock-data provenance twice inline; adjacent
Refresh mutation button), Audit header (no audit article; audit is crawl-derived
and crawl help belongs on the **locked `<CrawlPanel>`** directly below;
`AuditHeader` unlocked but adjacent to the locked integration; own honesty line +
Run-Audit button), and RouteStates admin variant (no public article explains
**global-admin** access; module variant already served in Wave 2C; admin variant
correctly link-less via `{!isAdmin && ...}`). None of the four files is locked
(re-checked). Verified: `tsc`/build clean; content validator PASS (0 findings,
31/30/1/10, unchanged); live mock-mode confirmation all three header pages render
with zero `/help/*` links and the locked crawl panel intact; protected routes
still redirect signed-out; public Help Center articles still load signed-out.
`git diff` confirms zero code change in Wave 3. **Final decision: Help Center
DEVELOPMENT-COMPLETE**, with four surfaces intentionally link-less by
evidence-based decision. **Still NOT covered:** locked-module contextual links
(P1a panel / crawl UI / Page Performance / Stage 6) remain a separate future
per-module effort with their own approvals; Cloud Run runtime verification
remains deferred to the TEST gate (not done); Help Drawer/analytics/CMS/AI
assistant out of scope. See
`DIGIBILITY_SEO_HELP_CENTER_WAVE3_DEFERRED_SURFACES_AND_FINAL_SIGNOFF.md`
(now includes a "Future Expansion Triggers" section: 7 specific conditions —
a dedicated Roadmap/Competitor/Audit/Platform-Admin article authored, the
CrawlPanel unlocked, material page UX change, or evidenced user/support/
accessibility need — under which the 4 closed candidates should be
re-evaluated, not automatically re-implemented; same strong-fit/low-risk/
lock-boundary bar + separate per-module approval still required. Wave 3
decisions and DEVELOPMENT-COMPLETE status unchanged; documentation-only,
2026-07-20).
Prior update — 2026-07-19 (Help Center **Wave 2C — Remaining Unlocked
Contextual-Help Placements — IMPLEMENTED AND VERIFIED**, frontend-only,
additive. Extended Wave 2B's pattern to: Page Optimizer (→
`the-approval-workflow`), Decline Diagnosis (→
`investigating-traffic-ranking-decline`), Progress Reports (→
`how-digibility-connects-insights-actions-approvals-reporting`), Approval
Queue (→ `the-approval-workflow`), and 4 `PlaceholderPage` sites (Settings/
Keyword Research/Blog Briefs/Content Gaps → `preview-data-versus-live-data`)
via a new additive `helpRoute`/`helpLabel` prop pair on `PlaceholderPage.tsx`
(omitted → renders exactly as before). One conditional candidate implemented,
scoped: `RouteStates.tsx`'s `AccessRequiredState` module variant only (strong
article fit, purely presentational file, no auth-resolution logic touched).
Four candidates deferred with reasons (`RoadmapSummaryHeader.tsx`,
`CompetitorOverviewHeader.tsx` — mutation-button-adjacent + no fitting
article; `AuditHeader.tsx` — same plus locked-`<CrawlPanel>` proximity;
`RouteStates.tsx`'s `ResolutionErrorState`/admin variant — no fitting
article). `ModulePlaceholderPage.tsx` found unreachable (dead code), left
untouched. Applied the Wave 2B.5 spacing lesson proactively on Decline
Diagnosis and Approval Queue (`space-y-1.5` added alongside each new nested
link). Verified: `tsc`/build clean; content validator still PASS (0
findings, unchanged corpus); all 8 new/reused placements checked live; no
console errors; no overflow; protected routes and public Help Center routes
reconfirmed; zero locked file or form/mutation/filter/role-switching logic
touched. See `DIGIBILITY_SEO_HELP_CENTER_WAVE2C_UNLOCKED_CONTEXTUAL_LINKS.md`.
Cloud Run runtime verification remains deferred to the TEST promotion gate
(unchanged). Prior update — 2026-07-19 (Help Center **Wave 2B.5 — Contextual-Help UX
Refinements — IMPLEMENTED AND VERIFIED**, frontend-only, additive. Small
approved follow-up closing the one real finding from the post-Wave-2B UX
review: `BusinessOnboardingPage.tsx`'s help link was nested one level deeper
than `WebsitesPage.tsx`/`SeoLoginPage.tsx`, so it didn't inherit
`CardHeader`'s `space-y-1.5` (6px) rhythm. Fixed with one class addition
(`className="space-y-1.5"` on the existing inner title/description/link
`<div>`) — verified via `getComputedStyle` that `marginTop` is now `6px` on
both the description and the link, matching Websites exactly. Link target,
text, and shared class string unchanged; stays inside `CardHeader`, outside
the `<form>`; no field/validation/submit/mutation logic touched. Also
established a placement guideline for Wave 2C (header-level pages, empty-state
pages, shared/complex pages — see
`DIGIBILITY_SEO_HELP_CENTER_WAVE2B_FIRST_CONTEXTUAL_LINKS.md` §11) — **no tab
order was changed**, and the guideline explicitly says DOM-order-before-a-
primary-action on header-level pages is not, by itself, a defect. No article
content changed. Verified: `tsc`/build clean; content validator still PASS (0
findings, unchanged corpus); all 4 pages/6 states re-checked live; no console
errors; no overflow; focus classes unchanged; zero locked file or
form/mutation/auth logic touched. See
`DIGIBILITY_SEO_HELP_CENTER_WAVE2B_FIRST_CONTEXTUAL_LINKS.md` §11. Cloud Run
runtime verification remains deferred to the TEST promotion gate (unchanged).
Prior update — 2026-07-19 (Help Center **Wave 2B — First Contextual-Help
Rollout — IMPLEMENTED AND VERIFIED**, frontend-only, additive. Added contextual
help links to exactly 4 approved unlocked pages: Websites, Business Onboarding
(outside the form), Dashboard's zero-website empty state only, and Login (both
mock-mode and real-auth branches, both outside their forms). New file
`src/help/routes.ts` (`HELP_ROUTES`, 4 slug constants only, no builder, no
component) — all 4 slugs verified published+public against the real corpus.
`PlaceholderPage.tsx` and every other Wave 2C/locked-module candidate
deliberately not touched. Verified: `tsc`/build clean; content validator still
PASS (0 findings, corpus unchanged); all 4 placements checked live (mock-mode
preview + the primary Supabase-mode preview for Login's real branch); each
link resolves to the correct article; browser-back works; protected routes
still redirect signed-out; no console errors; no locked file or form/mutation
code touched (cross-checked against every `MODULE_LOCKS.md` list). One
disclosed, unresolved JS-side viewport-measurement anomaly (not visually
corroborated) and one disclosed tooling limitation (synthetic focus doesn't
trigger real `:focus-visible` in the automated browser — class list confirmed
correct; live keyboard walkthrough remains an operator follow-up) — both
documented, not hidden. See
`DIGIBILITY_SEO_HELP_CENTER_WAVE2B_FIRST_CONTEXTUAL_LINKS.md`. Cloud Run
runtime verification remains deferred to the TEST promotion gate (unchanged).
No locked module, backend, DB, routing, or Supabase-config change; nothing
staged/committed/pushed. Prior update — 2026-07-19 (Frontend **Cloud Run
Deployment Readiness — LOCAL
READINESS ESTABLISHED; NOT DEPLOYED.** Added a repo-root multi-stage `Dockerfile`
(`node:20.18-alpine` build → `nginxinc/nginx-unprivileged:1.27-alpine` runtime
serving only the compiled `dist/`), `docker/nginx.conf.template` (`${PORT}`-substituted
at container start, listens `0.0.0.0:${PORT}`), `docker/security-headers.conf`, and
`.dockerignore`. Correct SPA routing: real/missing static assets get a genuine `404`
via ordered `location` blocks; every other path (including all `/help*` and `/seo/*`
routes) falls back to `index.html` so the existing unmodified React Router/auth
logic resolves it client-side. `index.html` always `no-cache`; hashed `/assets/*`
immutable/1yr; low-risk security headers only (no new CSP, no HSTS — Cloud Run
terminates TLS upstream). **No container build/run was performed — Docker is not
installed in this environment**; `tsc`/`build` are clean and a logic-trace script
confirmed the nginx routing rules against the real `dist/` output for all 12
required paths, but this is not a substitute for an actual container run (exact
operator commands documented). Env-var strategy documented: Vite bakes `VITE_*` at
BUILD time, so Cloud Run runtime env vars don't reach the bundle — default build
uses no Supabase args (mock mode). Cloud Run project/region/service/ingress/scaling
remain genuinely undecided, not fabricated. No locked module, backend, worker, DB,
or Supabase config touched; no GCP resource created/contacted; nothing
staged/committed/pushed. See
`DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md`. Prior update — 2026-07-19
(Help Center **Slice 1A — Decline Diagnosis article,
search refinement, deployment-readiness docs, UX/a11y acceptance — IMPLEMENTED AND
VERIFIED**, frontend-only additive follow-up to Slice 1. Added one new public article
(`investigating-traffic-ranking-decline`) in a new `reports-decline-diagnosis`
category (data-only; no new route); resolved Slice 1's one documented content-coverage
gap ("why did my traffic drop" now lands precisely). 9 new search queries verified to
top-rank the new article via its own `searchAliases` (no shared `synonyms.ts` change);
all 14 original Slice 1 fixtures re-verified with **zero regressions**. Deployment
target still not identifiable in-repo (documented only, nothing created). Two small
pre-existing UI defects found + fixed during UX review: audience-role label
humanization in `HelpArticlePage.tsx`, and `relatedLink` block-display spacing in
`BodyRenderer.tsx`. Verified: `tsc`/build clean; content-integrity validator PASS (0
findings, 31/30/1/10). No locked module touched; no DB/backend/production change;
nothing staged/committed/pushed. See `DIGIBILITY_SEO_HELP_CENTER_SLICE1A_COMPLETION.md`.
Prior update — 2026-07-19 (Help Center **Slice 1 — Public Static Foundation —
IMPLEMENTED AND VERIFIED**, frontend-only. A new authentication-free, Supabase-independent
public documentation surface lives at `/help`, `/help/search`, `/help/category/:slug`,
`/help/article/:slug` (+ dev-only `/help/dev/content-check`), registered as top-level route
siblings **before** the `ShellLayout`/`ProtectedRoute` block in `src/routes/SeoRoutes.tsx`; no
Help Center file imports Supabase, `useSeoAccess`, `useResolvedActiveWebsite`, or any
role/session hook (statically audited + confirmed live in-browser — no Supabase request fires
signed-out). New `src/help/**` (types, categories, synonyms, hand-rolled client-side search,
pure `validateHelpContent()` integrity check, 30-article bundled corpus — 29 public + 1
internal) and `src/pages/help/**` (public shell + pages + components; no
`dangerouslySetInnerHTML`). Two additive touches to existing files: `Sidebar.tsx` (new "Help
Center" nav link) and `ExpertSupportPage.tsx` (one cross-link paragraph; support workflow
unchanged). Verified: `tsc`/`build` clean; content-integrity validator PASS (0 findings, after
narrowing an over-broad `service_role` regex that false-flagged legitimate support-safety
prose); all 14 representative search fixtures checked live (13/14 exact match, 1 honest
content-coverage gap; a real ranking bug — stopword noise + word-repetition inflating score —
was found and fixed with query-only stopword filtering + a per-token match-strength cap).
**No locked module touched** (Page Performance, Stage 6, Crawler 16C–16H, P1a, P1b all
untouched); no DB/migration/RPC/worker/production change; nothing staged/committed/pushed.
Static-hosting SPA-fallback for an eventual production host is not yet configured — an open
item, not fabricated. Help Drawer, other-module contextual links, analytics, CMS, and a
grounded AI assistant are out of scope for this slice. See
`DIGIBILITY_SEO_HELP_CENTER_SLICE1_PUBLIC_FOUNDATION.md`. Prior update — 2026-07-19 (P1b
**Verified-only Crawl Enqueue Enforcement — TEST-APPLIED,
VERIFIED, and MODULE-LOCKED** on `Digi_SEO_Test`. Migration `20260719120034` applied; deployed
`seo_crawl_request` contract verified unchanged except the added `FOR SHARE` verified-ownership
guard (plain `P0001`; `seo_crawl_request_audit` unchanged); P1b acceptance verification + all
six 16C–16H regressions + worker suite (74/74) **ALL PASS**; `FOR SHARE` write-time atomicity
proven with a **live two-session** run (revoke-wins rejects; enqueue-wins commits); 0 fixture
residue; rollback not used. A formal P1b lock entry is now in `MODULE_LOCKS.md`. P1a remains
LOCKED and untouched; production untouched. See §8/§15. Prior update retained below.).
**Authoritative status source:** `CURRENT_PROJECT_STATUS.md`
(this file summarizes it; if they ever disagree, that file wins and this one is stale).
**This file is documentation only — it changed no code/DB/config/test/production.**

---

## 1. Product & repository overview
The **Digibility SEO Intelligence Module** is a standalone SEO product being built to
later plug into the existing Digibility platform. Frontend: **Vite + React + TypeScript**
(TanStack Query, shadcn/Radix UI, Tailwind). Data: **Supabase Postgres** with **RLS +
`SECURITY DEFINER` RPCs**, accessed **directly from the browser via the anon key**. A
permanent **mock data mode** (`VITE_SEO_DATA_MODE=mock`) mirrors every service for
preview/testing. Current working dir is the SEO module repo:
`/Users/amitguptaamit/gitrepo/user_guide/Digibility-SEO-Module`.

## 2. Repositories / projects involved & how they connect
- **SEO module frontend** (`src/**`) — browser app; talks **directly to Supabase**
  (reads via RLS; writes via guarded RPCs); never holds service-role credentials.
- **`crawler-worker/**`** — a **separate Node/TS package** in the same repo tree; a
  dedicated **service-role background ingestion worker** (crawl + DNS-TXT ownership
  `verify-once`). Runs **outside the browser/frontend**; not customer-callable.
- **Supabase project `Digi_SEO_Test`** (ref `snyzotgwwfomgafrsvfm`) — the **TEST**
  database. All migrations/verification run here. **Production is a separate, untouched
  project.**
- **Existing Digibility app** (reference only, not in this repo) — source of
  architecture/UI/auth conventions; **must not be modified**; future integration target.

## 3. Confirmed architecture & security boundaries
- **Browser → Supabase directly.** Authorization is owned by **RLS + `SECURITY DEFINER`
  RPCs**; the frontend gates are accessible affordances only (never authoritative).
- **Service-role key lives only in `crawler-worker` runtime** — never in the frontend,
  never in an anon-callable path. The worker **trusts the already-authorized job/claim
  row** and adds execution-safety guardrails (SSRF/DNS-rebind/robots/budgets).
- **Data minimization:** customer reads expose only customer-safe columns; internal
  claim/lease/worker-diagnostic fields are global-admin-only; the worker never logs raw
  challenge/lease tokens.
- **Mock mode is permanent** and must never call Supabase.

## 4. BFF requirements & the one narrowly-scoped exception
- **Current confirmed model = NO customer-facing BFF.** The SEO module is
  **Supabase-direct / RLS-authoritative** (`SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`
  §B/§F/§G/§L). There is no app-server/BFF between browser and data today.
- **The crawler worker is a deliberate trusted-server exception, not a BFF.** Per
  `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md` (Option C, lines 79–81, 92–95): the frontend
  still talks to Supabase directly for all reads and the guarded enqueue RPC; the worker
  is an **internal ingestion process, not a frontend API layer**. The crawler "does not
  break the 'no BFF' rule, but it requires a runtime host"
  (`MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md:166`).
- **Future parent-Digibility "BFF integration" is DEFERRED, additive, and out of current
  scope** (`MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` lines 333/342; `MODULE_LOCKS.md:155`).
  When the module later plugs into the parent platform, an identity-adapter / BFF seam
  may be introduced additively — it does **not** govern today's build and does **not**
  contradict the no-BFF-today model.
- **Resolution:** the ADR's "no-BFF" is scoped consistently with the module-wide
  Supabase-direct model; browser/application traffic stays behind RLS + guarded RPCs, the
  worker is the only trusted-server component, and any BFF is future integration work.
  **No authoritative document is contradictory; no doc edit was required.**

## 5. Backward-compatibility requirements
All new work is **additive** and must preserve: existing routes/URLs, Supabase
users/IDs, workspace memberships, SEO role strings, existing RPCs + signatures, service
read-shape types, status/action enum values, existing records, permanent mock mode, and
**both module locks** (Page Performance Tracker; Stage 6). No applied migration is edited;
read services keep their current shapes while real data flows underneath.

## 6. Documentation source-of-truth hierarchy
1. **`CURRENT_PROJECT_STATUS.md`** — single source of truth for *current status* (top
   line is authoritative; older lines are historical "Prior line —" chain).
2. **`PROJECT_DOCUMENTATION_INDEX.md`** — the map: which doc to read for what.
3. **`DOCUMENTATION_WORKFLOW_RULES.md`** — how docs are maintained; if any doc disagrees
   with `CURRENT_PROJECT_STATUS.md`, treat that file as authoritative and flag the other
   as stale.
4. Domain docs (architecture plan, ADRs, `MODULE_LOCKS.md`, per-phase/step records) are
   authoritative for their own scope.

## 7. Overall development plan & current release phase
Per `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` (**Option B — Minimum Customer-Usable
MVP**): customer auth + route protection → **real-data ingestion** (crawler → GSC/GA4) →
subscription/usage enforcement, all additive over the locked foundations.
**Current phase:** **Production Readiness A → P1b Verified-only Crawl Enqueue Enforcement —
COMPLETE: TEST-APPLIED, VERIFIED, and MODULE-LOCKED (2026-07-19).** P1a Domain Ownership
Verification is COMPLETE and MODULE-LOCKED (the source of the verified state P1b consumes).
P1b added a verified-ownership precondition inside `seo_crawl_request` (additive migration
`20260719120034`; `FOR SHARE`; plain `P0001`; worker untouched) under the Crawler 16C–16H
additive-extension procedure — applied to TEST and fully verified (acceptance + 16C–16H
regression + worker 74/74 + live two-session `FOR SHARE` concurrency). Next: production
promotion of the whole crawler + P1a/P1b stack (separately approved, not started) and the
optional P1b UI defense-in-depth (separately approved).

## 8. Completed & locked modules
- **Locked (implemented-scope locks; see `MODULE_LOCKS.md`):**
  **Page Performance Tracker**, **Stage 6 — Off-Page Authority workflows + AI
  Visibility reads**, **Crawler customer UI + crawl/audit/publishing contracts
  (Phase 16C–16H implemented scope)**, **P1a — Domain Ownership Verification**
  (locked 2026-07-19), and **P1b — Verified-only Crawl Enqueue Enforcement**
  (locked 2026-07-19; TEST-applied + verified). Shared files may receive only
  separately-authorized, additive, backward-compatible changes that re-run the relevant
  regression.
- **Completed & TEST-verified (not all customer-operational):** Stages 1–6 backend;
  service wiring through Phase 15; customer auth + route protection (Phase 16B); the
  **crawler control-plane → worker → discovery → extraction → publishing → customer UI**
  (Phases 16C–16H, **fully accepted on TEST**, worker not deployed).
- **P1a Steps 1–6** (DNS-TXT domain ownership verification) implemented + TEST-verified,
  full operator acceptance PASS (backend SQL matrix, authenticated browser role matrix,
  real `verify-once` worker-binary run — see §9). **P1a is now MODULE-LOCKED.**

## 9. Current P1a Domain Ownership Verification status  *(latest confirmed facts)*
- **Step 2.8 authenticated UI acceptance = PASS** under the final **AT-1..AT-4** criteria.
- **Final double-submit guard** in `src/pages/seo/websites/OwnershipVerificationPanel.tsx`:
  per-action state machine **`idle → in_flight → cooldown → idle`**.
  - First click **fires immediately**.
  - A **synchronous per-action phase ref (`phaseRef`)** blocks concurrent/same-frame
    duplicate submissions (before `disabled` re-renders).
  - The button stays **visibly disabled through the mutation + refetch lifecycle + a
    fixed 3000 ms cooldown** (`disabled = anyPending || lockedActions[action]`).
  - **No keep-alive / no timer rescheduling.**
  - A **deliberate click after re-enable is a valid new request.**
  - Temporary `[OVP]` diagnostics fully removed.
- **Retired as unsound:** the "**exactly one RPC across an arbitrarily long manual
  burst**" criterion — a pause longer than any finite cooldown is indistinguishable from
  a deliberate later recheck. **Earlier long-burst runs are invalid tests, NOT failures.**
- **A3 DB integrity proof (TEST):** `digibility.ai`
  (`website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`, `method=dns_txt`) = **exactly one
  row** (`row_count=1`), `status=pending`, `2026-07-17 16:25:18.663042+00`.
- **Cleanup via authenticated customer revoke UI (not delete; append-only audit kept):**
  - `digibility.ai` → **revoked**, `updated_at=2026-07-17 16:33:13.804585+00`.
  - Stage-5 smoke fixture `stage5-smoke-test.example`
    (`website_id=77777777-0000-0000-0000-0000000000b1`, source
    `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql`; was `pending`,
    `has_open_claim=false`) → **revoked**, `updated_at=2026-07-17 16:43:24.935897+00`.
- **Step 2B + Step 3 SQL regressions — RE-RUN COMPLETE = PASS (2026-07-18).** A read-only
  eligibility diagnostic confirmed **0** `pending`/`failed` ownership-verification rows on
  `Digi_SEO_Test` before execution. `seo_p1a_step2b_ownership_verification_service_rpcs_verification.sql`
  returned `ALL PASS — seo_p1a_step2b service-role + global-admin ownership-verification
  verification complete`; `seo_p1a_step3_worker_dns_verification_integration.sql` returned
  `ALL PASS — seo_p1a_step3 worker DNS-verification TEST integration complete`. Both scripts'
  own teardown + locked-module isolation assertions passed; both are self-cleaning,
  single-transaction, net-nothing on success. No source/migration/SQL/worker/frontend/config
  change; production untouched.
- **Authenticated browser role matrix — COMPLETE = PASS (2026-07-18, `Digi_SEO_Test`).**
  Operator-executed logged-in click-through of the Step 5 UI against the real Supabase-mode
  app, each role followed by sign-out:
  - **Owner:** authenticated successfully; on `/seo/websites` saw `digibility.ai` with
    ownership controls enabled; **Verify ownership** issued exactly one
    `seo_ownership_verification_initiate` request (HTTP 200); UI changed to
    **Verification pending** and remained pending after a hard refresh; sign-out
    redirected to `/seo/login` and removed protected content.
  - **Admin:** authenticated successfully; saw the persisted **pending** status with
    **Check again / Re-verify / Revoke** enabled; **Check again** issued exactly one
    `seo_ownership_verification_recheck` request (HTTP 200); status remained **pending**;
    sign-out removed protected content.
  - **team_member:** authenticated successfully; saw **pending** status, **no** ownership
    action buttons, and the read-only role message; Network evidence confirmed **no**
    initiate/recheck/reverify/revoke request fired; sign-out removed protected content.
  - **client:** authenticated successfully; identical read-only affordance to team_member;
    Network evidence confirmed **no** write RPC fired; sign-out removed protected content.
  - **Cross-role/session isolation:** status read live from Supabase across every role
    switch (no stale/cached cross-user state); protected routes inaccessible after every
    sign-out. **No defect found; no file changed** during this browser acceptance.
- **Real `verify-once` worker-binary run — COMPLETE = PASS (2026-07-19, `Digi_SEO_Test`).**
  Operator ran `npm start -- --mode=verify-once` from `crawler-worker/` after exporting
  `crawler-worker/.env` into the shell; `environment=test`, `mode=verify-once`;
  `serviceRoleKey` logged **only as `[REDACTED]`**. Claimed the only eligible verification
  (`id=41d2a3e8-3c7e-4b55-a282-6682a8349b69`, `website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`,
  host `digibility.ai`); performed a **real Node DNS TXT lookup** (not fixture) against
  `_digibility-site-verification.digibility.ai` → no record found; persisted via the real
  `seo_ownership_verification_record_result` RPC: `status=failed`, reason `dns_not_found`,
  `last_checked_at=updated_at=2026-07-19 05:18:27.369182+00`; one new
  `seo_ownership_verification_events` row (`event_type=failed`, `from_status=pending`,
  `to_status=failed`, `actor=worker`, `created_at=2026-07-19 05:18:27.369182+00`); worker
  logged `verify_once` completion and **exited code 0**. No challenge value, lease token,
  or service-role key was ever exposed. **The legitimate `failed`/`dns_not_found` DNS
  business outcome is not a defect** — the acceptance criterion is the trusted end-to-end
  worker-binary path (real service-role client → real claim RPC → real DNS resolution →
  real result RPC, none simulated), independent of the DNS business result. No
  source/migration/SQL/worker/config/crawl-contract/production change occurred.
- **P1a is COMPLETE and MODULE-LOCKED (2026-07-19).** A formal lock entry now exists in
  `MODULE_LOCKS.md`. **P1b — verified-only crawl enqueue enforcement — is now the next
  implementation stage** (not started). Production untouched.

## 10. Accepted implementation decisions
- Simple, predictable, **visible bounded post-action lock** over clever timing logic.
- Cooldown is legitimately part of the native `disabled` (the keep-alive design that
  required it *out* of `disabled` is retired).
- Fixed **3000 ms** cooldown — spans mutation+refetch, absorbs impatient bursts, and is
  negligible vs DNS-TXT propagation timelines (so it never blocks a legitimate recheck).
- Customer `recheck` is non-destructive (reuses the token, no new row) → a **UI-only**
  guard is sufficient; **no server-side rate limiting** added for P1a.

## 11. Rejected / superseded approaches
- **Synchronous in-flight latch only** (blocked overlap but not spaced clicks) — superseded.
- **Leading-edge throttle + keep-alive cooldown** (proved correct on a single persistent
  instance; still couldn't satisfy the unsound "one-RPC-per-arbitrary-burst" goal) — retired.
- **The "one RPC across an arbitrarily long burst" acceptance criterion itself** — retired
  as technically unsound.
- **Increasing the cooldown blindly / trailing debounce / delayed first click /
  module-global guard / DB-server rate limiting** — explicitly not adopted.

## 12. Completed verification & evidence
- Static: root `tsc --noEmit` clean; `npm run build` clean; one-file frontend scope for the
  fix; all `[OVP]` removed (grep = none); security sweep clean (no service-role/secret/env/
  direct-DB/console in the panel; Step 4 hooks only).
- Mock quantitative proof: recheck counted **directly via the mock store's
  `lastCheckedAt`** (not token rotation) → 8 rapid clicks = **exactly 1** accepted recheck;
  +1 deliberate after cooldown = 2 total; same guard confirmed for initiate/reverify/revoke;
  no console errors; **zero Supabase calls** in mock.
- Authenticated operator: **AT-1** rapid double/triple click → exactly 1 recheck POST (200);
  **AT-2** disabled ≈3.5 s then re-enables; **AT-3** deliberate click after re-enable → 1
  new POST (200); **AT-4** no overlapping duplicates; UI stayed `Verification pending`.
- Regression baseline (from Step 6): P1a Steps 1/2A/2B SQL + Step 3 integration SQL;
  locked crawler 16C–16H; Stage 6 smoke/create/transition; worker suite 74/74; backend role
  matrix (SQL) — **all PASS**.
- **Regression re-run (2026-07-18):** P1a Step 2B SQL + Step 3 integration SQL re-executed
  on TEST after the A3/revoke cleanup — **both ALL PASS** (explicit sentinels; locked-module
  isolation counts unchanged; self-cleaning). See §9.
- **Authenticated browser role matrix (2026-07-18):** owner/admin/team_member/client
  click-through on `Digi_SEO_Test` — **PASS** (see §9 for full per-role evidence).
- **Real `verify-once` worker-binary run (2026-07-19):** real service-role client, real
  claim RPC, real Node DNS resolution, real result RPC against `Digi_SEO_Test` — **PASS**
  (see §9 for full evidence). **This closes P1a acceptance; P1a is now LOCKED.**

## 13. Remaining blockers & unresolved verification
**None outstanding for P1a** — all acceptance items (backend SQL matrix, authenticated
browser role matrix, real worker-binary run) are PASS and P1a is module-locked.
1. Legacy Stage 2–5 psql-style smokes — tooling limitation (documented; not a defect;
   unrelated to P1a acceptance).

## 14. Production / test environment status
All work is on **`Digi_SEO_Test`** only. **Production is untouched** (no migration, code,
RPC, RLS, worker, config, or data change in production at any point). The crawler worker is
**not deployed**; the module is not customer-operational.

## 15. Exact next step
P1a and **P1b are both COMPLETE and MODULE-LOCKED** on TEST (2026-07-19). P1b was applied to
`Digi_SEO_Test` and fully verified (acceptance + 16C–16H regression + worker 74/74 + live
two-session `FOR SHARE` concurrency); the formal P1b lock is in `MODULE_LOCKS.md`; sign-off in
`P1B_VERIFIED_ONLY_CRAWL_ENQUEUE_SIGNOFF.md`. **No production change.** The **exact next steps
are separately-approved and not started:** (a) production promotion of the crawler + P1a/P1b
stack (deployment/runtime, secrets, migration + rollback plan, monitoring); (b) optional P1b
**UI defense-in-depth** (disable/explain Start-crawl + surface the RPC message — touches the
locked crawl-UI files, needs the additive-extension procedure). Nothing committed/pushed/staged.

## 16. Actions that must NOT be taken yet
Do **not**: start P1b implementation without an explicit approved plan; modify any locked
module (Page Performance, Stage 6, Crawler 16C–16H, or **P1a**) without explicit
authorization; deploy the worker; touch production; edit applied migrations; delete
operator/fixture data by direct SQL (use the customer revoke path); commit or push; expose
any credential/token.

## 17. ChatGPT ↔ Claude working protocol
- **ChatGPT owns:** planning, sequencing, risk review, acceptance-criteria interpretation,
  and generating the prompts given to Claude.
- **Claude (Claude Code) owns:** repository inspection and approved implementation/
  documentation execution in this repo.
- **Prompt discipline:** prompts must be **token-efficient** — refer to confirmed
  architecture/docs (by repo-relative path) instead of restating the whole project.
- **Claude must:** inspect before editing; **list expected files + module-lock
  implications before implementing**; preserve **BFF boundaries** (browser→Supabase direct;
  service-role only in the worker) and **backward compatibility**; **not modify locked
  modules without explicit authorization**; after an accepted checkpoint, **update all
  relevant authoritative docs** and **identify/reconcile stale or contradictory docs**; and
  **not commit, push, touch production, or expose credentials** unless explicitly instructed.
- **Operator actions** (shell/DB/browser steps) are given **one step at a time**, waiting
  for evidence, **unless a complete runbook is explicitly requested**.
- **Review loop:** after **every** Claude response, ChatGPT reviews the returned evidence
  before issuing the next prompt.

## 18. Required Claude model-selection protocol
ChatGPT must **recommend exactly one model for every Claude prompt**, chosen from:
**Opus 4.8, Opus 4.7, Opus 4.6, Sonnet 5, Sonnet 4.6, Fable 5, Haiku 4.5**.
Guidance:
- **Opus 4.8 / 4.7** — hard architecture/root-cause/security/acceptance-risk reasoning,
  ambiguous multi-file changes, anything touching locked-module boundaries.
- **Opus 4.6** — solid deep reasoning when 4.8/4.7 are unavailable.
- **Sonnet 5** — routine, well-specified implementation and verification with clear scope.
- **Sonnet 4.6** — lighter well-specified edits / mid-size doc reconciliation.
- **Fable 5 / Haiku 4.5** — mechanical/low-ambiguity doc or status edits, greps, quick
  inspections. Prefer **Haiku 4.5** for the cheapest fast passes.
State the recommended model **with a one-line reason** at the top of each Claude prompt.

## 19. Minimum files to upload into a fresh ChatGPT thread
1. `CHATGPT_CONTEXT_HANDOVER.md`  *(this file — start here)*
2. `CURRENT_PROJECT_STATUS.md`  *(authoritative current status)*
3. `PROJECT_CONTEXT.md`  *(product goals, non-negotiable rules, build constraints)*
4. `MODULE_LOCKS.md`  *(what is locked and the additive-extension procedure)*
5. `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`  *(P1a verdict + acceptance log §10)*
6. `P1A_STEP5_DOUBLE_SUBMIT_FIX.md`  *(final guard §9 + A3/cleanup §10)*

Optional next reads if deeper context is needed: `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md`,
`ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`, `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md`,
`BACKEND_MILESTONE_HANDOFF.md`, `PROJECT_DOCUMENTATION_INDEX.md`.

## 20. Repository-relative paths for every referenced document/artifact
- `CHATGPT_CONTEXT_HANDOVER.md` — this handover.
- `CURRENT_PROJECT_STATUS.md` — authoritative status.
- `PROJECT_CONTEXT.md` — product/build context + non-negotiable rules.
- `PROJECT_DOCUMENTATION_INDEX.md` — documentation map.
- `DOCUMENTATION_WORKFLOW_RULES.md` — doc maintenance rules.
- `MODULE_LOCKS.md` — locked modules + additive-extension procedure.
- `SUPABASE_BACKEND_ARCHITECTURE_PLAN.md` — no-BFF / Supabase-direct / RLS-authoritative.
- `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md` — crawler worker = trusted-server exception.
- `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md` — auth approach.
- `MVP_RELEASE_READINESS_AND_NEXT_SCOPE.md` — Option B plan; BFF/parent-integration deferred.
- `BACKEND_MILESTONE_HANDOFF.md` — backend-state addendum + 2026-07-17 checkpoint.
- `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` — P1a sign-off + acceptance log (§10).
- `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` — final double-submit guard (§9) + A3/cleanup (§10).
- `P1A_STEP5_OWNERSHIP_VERIFICATION_UI.md` — Step 5 UI record (final guard §6c).
- `P1A_STEP1_OWNERSHIP_VERIFICATION_DB_CONTRACT.md`,
  `P1A_STEP2A_OWNERSHIP_VERIFICATION_RPCS.md`,
  `P1A_STEP2B_OWNERSHIP_VERIFICATION_SERVICE_RPCS.md`,
  `P1A_STEP3_OWNERSHIP_VERIFICATION_WORKER.md`,
  `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md` — P1a step records.
- `src/pages/seo/websites/OwnershipVerificationPanel.tsx` — the guarded UI panel (final fix).
- `src/hooks/useOwnershipVerification.ts`, `src/services/ownershipVerificationService.ts`,
  `src/services/supabase/seoOwnershipVerificationSupabaseService.ts`,
  `src/mocks/ownershipVerificationMockData.ts` — P1a Step 4 service layer.
- `crawler-worker/src/verification/{dns,verificationGateway,runner}.ts`,
  `crawler-worker/src/modes.ts` — isolated `verify-once` worker module.
- `supabase/migrations/20260716120031…120033_*` — P1a Steps 1/2A/2B migrations (TEST).
- `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql` — Stage-5 smoke fixture.

---
*End of handover. Production untouched; no code/DB/config/test change was made to produce
this file.*
