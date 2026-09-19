# SEO Production Promotion Plan — Future Planning Reference

> ## ⚠ DOCUMENT CLASSIFICATION: FUTURE PRODUCTION-PLANNING REFERENCE — NOT A STATEMENT OF PRODUCTION READINESS
>
> **This document does not describe current production state, and it does not
> authorize or initiate any production planning or deployment.** It is a
> planning-only reference written 2026-07-24 against `main` `71ac8fd`; it was
> originally headed "Authoritative" and described as "the single source of truth
> for promoting" — **that framing is withdrawn.** Nothing in it means the module
> is ready for production. Any future promotion still needs a separate,
> explicitly-approved task, and this document's evidence sections would have to be
> re-verified at that time.
>
> **Corrected factual state (2026-09-19; the plan is not redesigned):**
>
> | Fact | Value |
> |---|---|
> | SEO production Supabase project | **Does not exist / has not been identified.** No production rollout of any kind has occurred. (The 2026-07-24 project listing this plan cites showed only `Digi_SEO_Test` and `Digi_Visi`, whose role is unknown and which this module has never touched.) |
> | Migration files in the repository | **42** in `supabase/migrations/` (the plan below was written when there were 41) |
> | Migrations recorded on `Digi_SEO_Test` | **40**, the latest being `20260724120040`; TEST is `ACTIVE_HEALTHY` |
> | Repo migrations **not** recorded on TEST | **Two:** (1) `20260720121000` — SSO identity bridge, **deliberately deferred** (`SEO_DECISIONS.md` A14); (2) `20260724130000` — Recommendation Generation, **deliberately absent after its documented 2026-07-24 rollback** (locally verified; locked in Git; needs separate approval before TEST re-application) |
> | Canonical `main` | `9cb3676` (Recommendation Generation Stages 1–2 locked and merged) |
> | Roadmap Backend | Design only; not implemented (`SEO_ROADMAP_BACKEND_ARCHITECTURE.md`) |
>
> **How to read the rest of this document:** numbers such as "41 files", "40/41
> applied", "the one pending migration" and "40 (or 41)" are the 2026-07-24 snapshot
> unless a section carries a 2026-09-19 correction note; use the table above.
> Current status of the project: `SEO_CONTEXT_HANDOVER.md` §0.

**Original role statement (withdrawn — see banner):** described itself as the
single source of truth for promoting the Digibility SEO Intelligence module from
`Digi_SEO_Test` to a production environment. **Planning-only** — no
database, migration, runtime-config, deployment, or code change was made while
producing this document; it was produced by reading the existing authoritative
documents and inspecting local migration/config/CI state, not by contacting any
Supabase project or cloud resource beyond a read-only project listing.

**Created:** 2026-07-24. **Based on `main` commit:**
`71ac8fd0fd6087bb5435bea4cca865025bc27967`
(`docs(seo): lock competitor benchmarking module`).

**Rule followed throughout this document:** every claim is either (a) grounded in
a specific file/command inspected during authoring, or (b) explicitly marked
**UNKNOWN** or **REQUIRES OPERATOR DECISION**. Nothing about production is
invented. Where the existing docs already flag something as undecided (e.g.
`DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` §12), that flag is
preserved here rather than resolved.

**Governs:** any future production-promotion *execution* task must satisfy every
gate in this document before touching production, and must update this
document's evidence sections as each gate is satisfied. This document does not
itself authorize any production action — every step below still requires
separate, explicit operator approval at the point it is executed (§12).

---

# 1. Current State

## 1.1 Current `main` commit

`71ac8fd0fd6087bb5435bea4cca865025bc27967` — `docs(seo): lock competitor
benchmarking module` *(2026-07-24 snapshot — canonical `main` is now `9cb3676`,
five commits later: `808d54d`, `e7b1fbe`, `c1de7fe`, `36d32af`, `9cb3676`)*. Direct
ancestry at the snapshot (most recent first):

| Commit | Subject |
|---|---|
| `71ac8fd` | `docs(seo): lock competitor benchmarking module` |
| `a594d1d` | `feat(seo): integrate competitor benchmark generation` |
| `2d5ff89` | `feat(seo): add guarded competitor benchmark generation` |
| `e00caa2` | `feat(seo): add competitor benchmarking read path` |
| `b976340` | Reports v1 complete + locked |
| `420f9ca` | cloudbuild (TEST-only Cloud Build pipeline added) |
| `e1a918a` | SSO (cross-project identity bridge migration added, unapplied) |
| `2b9537b` | SEO Intelligence module import |

## 1.2 Locked modules (formal `docs/markdown/MODULE_LOCKS.md` entries)

| Module | Locked on | Scope |
|---|---|---|
| Page Performance Tracker | 2026-07-10 | Full |
| Stage 6 — Off-Page Authority Workflows + AI Visibility Reads | 2026-07-13 | Implemented scope only (writes for AI Visibility, real crawler/GSC/GA4 ingestion, real LLM ingestion remain unlocked/unbuilt) |
| Crawler customer UI + crawl/audit/publishing contracts (Phase 16C–16H) | 2026-07-15 | Implemented scope only |
| P1a — Domain Ownership Verification (DNS-TXT) | 2026-07-19 | Implemented scope only |
| P1b — Verified-only Crawl Enqueue Enforcement | 2026-07-19 | Full |
| Reports v1 (persisted read + guarded generation + PDF export, Stages 1–3) | 2026-07-20 | Approved scope; CSV/history/scheduling/email/sharing/period-comparison deferred |
| Competitor Benchmarking (persisted read + guarded generation + frontend integration, Stages 1–2) | 2026-07-24 | Approved scope; real external provider integration, scheduled regeneration, plan-tier limits, CSV export, trend history deferred |
| *(added 2026-09-19)* Recommendation Generation — Stage 1 backend only | 2026-07-24 | Additive schema + guarded generation RPC (`20260724130000`); **not recorded on TEST** |
| *(added 2026-09-19)* Recommendation Generation — Stage 2 frontend integration | 2026-07-24 | Approved frontend scope; on `main` at `9cb3676` since 2026-09-19 |

**Informally treated as locked** (per `MODULE_LOCKS.md`'s "Other modules marked
locked in `PROJECT_BOOTSTRAP.md`" section — passed the general completion rule
but have **no formal per-file lock entry, locked-file list, or evidence bar**
in `MODULE_LOCKS.md` yet): Website Setup + Business Onboarding; Technical Audit
+ Recommendations; Approval Queue; Content Studio; Dashboard + Admin Preview;
Decline Diagnosis Engine. **Treat these as locked under the general rule, but a
formal entry should be authored the next time one of them is touched** — this
plan does not do that (out of scope for a planning-only document).

## 1.3 Unlocked / explicitly deferred modules

| Area | State |
|---|---|
| Customer authentication + route protection (Phase 16B) | Implemented (login-only, reuses Digibility auth); not locked (deferred) |
| Help Center (public docs surface) | Development-complete; not locked (frontend, additive) |
| Collapsible SEO Navigation IA | Implemented + verified; not locked (frontend, additive) |
| Cloud Run frontend container readiness | Prepared + statically verified; **not deployed, not runtime-verified**; not locked |
| Roadmap, Expert Support | Mock-only; no backend stage exists |
| AI Visibility writes; real LLM ingestion | Not implemented (Stage 6 lock covers reads only) |
| Real crawler/GSC/GA4/GBP/CMS integration | Not implemented anywhere in the product |
| Usage/subscription billing enforcement | Schema exists (`seo_subscriptions`, `seo_plan_limits`) but no gateway/enforcement wiring |
| Locked-UI defense-in-depth for verified-only crawl initiation | Optional, deferred (server-side P1b enforcement already mandatory) |

## 1.4 Production status

**UNTOUCHED — hard invariant.** No migration, RPC, worker, or frontend config
has ever been applied to a production project; Cloud Run has never been
deployed. Concretely verified during this planning task:

- `supabase projects list` (read-only) shows exactly **two** Supabase projects
  in the accessible organization: `Digi_Visi` (ref `boclpogcwwnyvrtgabtt`, not
  linked to this repo) and `Digi_SEO_Test` (ref `snyzotgwwfomgafrsvfm`,
  linked). **No project is named or otherwise identifiable as a dedicated SEO
  production project.** Whether `Digi_Visi` is the Digibility Core production
  project, a Core staging project, or something else entirely is **UNKNOWN**
  from this repository alone — it was never contacted, configured, or written
  to by the SEO module.
- `cloudbuild.yaml` (repo root) defines exactly **one** Cloud Build pipeline,
  and its own header comment labels it **"staging (test) Cloud Build
  pipeline"** — it deploys to Cloud Run service `digi-seo-frontend-test`,
  wires `DIGIBILITY_APP_URL=https://testapp.digibility.ai` (a **TEST** Core
  host) and reads TEST-prefixed secrets (`seo-test-supabase-url`,
  `seo-test-supabase-anon-key`, `seo-test-digibility-anon-key`). **No
  production Cloud Build config exists in the repository.**
- `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` confirms the
  container artifacts (`Dockerfile`, `docker/nginx.conf.template`, etc.) were
  authored and statically verified but **no `docker build`, no container
  start, and no `gcloud` command was ever run** (Docker was unavailable in
  that authoring environment).
- `BACKEND_MILESTONE_HANDOFF.md` §5 lists five production pre-conditions,
  none of which have been satisfied: target-project confirmation,
  branch/backup strategy, final migration review, developer/technical
  sign-off, rollback/restore plan.

## 1.5 TEST status (`Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm`)

Confirmed live via `supabase migration list` during this planning task:

- **2026-09-19 corrected state:** **42** migration files in
  `supabase/migrations/`; **40 recorded** on `Digi_SEO_Test` (latest
  `20260724120040`; TEST `ACTIVE_HEALTHY`); **two not recorded:**
  - `20260720121000_seo_cross_project_identity_bridge.sql` — intentionally
    deferred (`SEO_DECISIONS.md` A14); must not be applied without a separate,
    explicitly-approved SSO task.
  - `20260724130000_seo_recommendation_generate.sql` — deliberately absent after
    its documented 2026-07-24 rollback; locally verified and locked in Git;
    re-applying it to TEST needs a separately recorded approval.
- *(2026-07-24 snapshot, superseded: 41 files, 40 applied, 1 pending — the
  pending one being the SSO migration.)*
- No fixture residue reported by any retained verification script (Stage
  1–6, P1a, P1b, Reports v1, Competitor Benchmarking, Recommendation Generation).

---

# 2. Environment Comparison

**Production does not exist as a configured environment today.** This section
compares `Digi_SEO_Test`'s *actual, verified* configuration against what a
production environment would need — the production column states either the
TEST-parity requirement or **UNKNOWN**/**REQUIRES OPERATOR DECISION** where no
production value has ever been chosen.

| Dimension | `Digi_SEO_Test` (verified) | Production |
|---|---|---|
| **Supabase project** | `Digi_SEO_Test`, ref `snyzotgwwfomgafrsvfm` (Southeast Asia region, per prior TEST-apply evidence) | **UNKNOWN — no dedicated SEO production Supabase project has been created or identified.** REQUIRES OPERATOR DECISION: create a new dedicated project, or is a project already provisioned outside this repo's visibility? |
| **Migrations** | 40 of 42 recorded (2026-09-19); `20260720121000` (SSO, deferred) and `20260724130000` (Recommendation Generation, absent after rollback) not recorded *(2026-07-24 snapshot: 40/41)* | **No SEO production project exists; none applied.** A promotion would apply whichever subset is decided at that time — up to all 42 files — via the same additive-only migration set; see §4. |
| **Auth** | Standalone TEST/local password login is the working fallback; the cross-project SSO bridge (`seo-bridge` Edge Function + `20260720121000`) exists in code but is **unapplied and unused** | **REQUIRES OPERATOR DECISION:** does production launch with standalone SEO login, or does it require the SSO bridge live from day one? If SSO is required, that is a **separate, not-yet-scoped task** per `SEO_DECISIONS.md` A14 — this plan does not design or approve it. |
| **Storage** | One private bucket, `seo-content-assets` (`public=false`, 20 MB limit, 5-MIME allowlist), created by migration `20260711120009_seo_stage3_content_assets.sql` | Same bucket definition ships via the same migration; no production-specific storage config exists yet. **UNKNOWN:** production storage quota/CDN/backup policy. |
| **Functions (Edge Functions / RPCs)** | All RPCs are Postgres `SECURITY DEFINER` functions inside the repository migrations (41 at the 2026-07-24 snapshot, 42 now) — no separate Edge Function deployment for SEO itself. The **`seo-bridge` Edge Function is Digibility Core's**, not this repo's; a TEST instance is referenced in `cloudbuild.yaml` (`https://szxdfmcexafiwlgestpl.supabase.co/functions/v1/seo-bridge`) | **UNKNOWN:** whether Digibility Core has a production `seo-bridge` Edge Function deployed; that is outside this repository's control and must be confirmed with whoever owns Digibility Core. |
| **Runtime config (frontend)** | `public/runtime-config.js` (tracked, forces `SEO_DATA_MODE:"mock"` by default) + Vite build-time `VITE_*` args baked into the JS bundle at image-build time (not Cloud Run runtime env vars — see `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` §13) | Same mechanism would apply; a **separate production image build** (separate `--build-arg` values) is required — the TEST image cannot be relabeled and pointed at production, per Vite's build-time bundling. **REQUIRES OPERATOR DECISION:** production `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`/`VITE_DIGIBILITY_*` values. |
| **Feature flags** | None exist as a formal mechanism. The closest analogues are `VITE_SEO_DATA_MODE` (`mock`/`supabase`) and the per-module lock state itself (locked modules ship; unlocked/mock-only modules stay mock in the UI regardless of data mode). | No production-specific feature-flag system exists to compare. **UNKNOWN** whether one is wanted before launch (e.g. to dark-launch specific modules). |
| **Service-role secrets (worker)** | `crawler-worker/.env` (gitignored, local-only) holds `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` for TEST; `CRAWLER_ENV=test`, `CRAWLER_ALLOW_NON_TEST_JOBS=false` | **No production worker deployment exists.** `crawler-worker/Dockerfile` exists (pre-existing, read but not modified per the Cloud Run readiness doc) but has never been built/deployed anywhere. **REQUIRES OPERATOR DECISION:** worker runtime target (Cloud Run Job, GKE, Compute Engine, other), scheduling mechanism, and where the production service-role key is stored (must be a secret manager, never a repo file). |
| **CI/CD** | `cloudbuild.yaml` — one pipeline, TEST-only, deploys `digi-seo-frontend-test` in `asia-southeast1`, recommended trigger = push to a `release/test` branch (not `main`) per the file's own header comment. Runtime service account referenced: `digi-frontend-runner@digibility-frontend.iam.gserviceaccount.com` (GCP project context implied, not independently confirmed by this repo) | **No production Cloud Build config exists.** Would require a new `cloudbuild.production.yaml` (or equivalent) with its own project/region/service/secrets/trigger-branch — **REQUIRES OPERATOR DECISION** for every one of those values. |

---

# 3. Deployment Order

The order below follows the dependency direction already established by the
architecture (`SEO_PROJECT_CONTEXT.md` §4): the RPC + RLS layer inside
Supabase **is** the trusted boundary, so the database must be correct and
authoritative before anything that calls it goes live.

```
1. DATABASE  (Supabase production project: schema + RLS + RPCs)
        ↓
2. BACKEND   (crawler-worker: deployed but held idle/disabled)
        ↓
3. FRONTEND  (Cloud Run image: built, deployed, but traffic-gated or dark)
        ↓
4. RUNTIME CONFIG  (point the deployed frontend at the production Supabase project)
        ↓
5. VERIFICATION  (smoke tests — §6 — against the now-live production stack)
        ↓
6. ENABLEMENT  (open traffic / remove the dark-launch gate; announce)
```

**Why this order:**

1. **Database first, always.** Every RPC's authorization logic, every RLS
   policy, and the entire trusted-boundary model live in Postgres
   (`SEO_PROJECT_CONTEXT.md` §4). Nothing above the database can be
   meaningfully verified until the schema, RLS, and guarded RPCs exist and
   are byte-verified equivalent to what passed on `Digi_SEO_Test`. Applying
   migrations does not, by itself, expose anything to end users (no frontend
   points at it yet) — the lowest-risk point to apply is before any traffic
   exists.
2. **Backend (worker) second, held idle.** The crawler-worker is a
   service-role background process with no customer-facing entry point of
   its own — it only *claims* work that the database already gates
   (P1b's verified-ownership precondition, `FOR UPDATE SKIP LOCKED` claim
   model). Deploying it before the frontend is live is safe **only if it is
   deployed in a disabled/zero-instance/paused state** — there must be no
   crawl jobs to claim yet, since no customer has been able to enqueue one.
   This order lets the worker's own health/connectivity be verified against
   production Supabase before any real job exists.
3. **Frontend third.** Only after the database contract is proven correct
   and the worker's connectivity is proven should the browser-facing SPA be
   deployed — it is the only component real users can reach directly, so it
   is the last piece introduced, and even then behind a gate (see step 4/6).
4. **Runtime config fourth, deliberately separated from "deploy."** Per
   `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` §13, Vite bakes
   `VITE_*` values into the JS bundle **at build time**, not at Cloud Run
   runtime — so "deploying the frontend" and "pointing it at production
   Supabase" are two different, sequenced actions: the image can be built
   and even deployed to a Cloud Run revision while still configured for
   `mock` mode (or for TEST), verified there is no crash, and only then
   rebuilt/redeployed with production `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`.
   This gives one more safe checkpoint before any real Supabase traffic is
   possible.
5. **Verification fifth.** Only once database + worker + frontend + runtime
   config are all pointed at the same production stack does a smoke-test
   pass mean anything — testing any subset earlier would not prove the
   integrated system works.
6. **Enablement last.** "Verification passing" and "customers can reach it"
   are kept as separate, explicit steps so that a failed smoke test never
   requires a rollback of *traffic* — only a rollback (or hold) of the
   deployment, with zero real users ever exposed to a broken state. This
   also allows a dark-launch/soft-launch window before the public
   announcement, if desired (**REQUIRES OPERATOR DECISION** — see §13).

---

# 4. Migration Plan

Every file in `supabase/migrations/` (**42 total as of 2026-09-19**; the table below
was written for the 41 that existed at the 2026-07-24 snapshot, and row 42 was
added afterwards), in order, with a
promotion-risk classification. All are **additive-only** by repo
convention (`SEO_DECISIONS.md` C1) — none of them alters or drops an existing
Core table, and all were verified via structural checks + SQL smoke/regression
tests on `Digi_SEO_Test` before being recorded as applied there.

**Classification key:** Safe = no data risk, no locking concern, no
sequencing dependency beyond normal file order. Breaking = would be breaking
*if applied out of order or to a schema that skipped a prior file* (i.e.
sequencing-sensitive, not "breaking" in the sense of harming existing data).
Requires downtime = none identified (see note below). Requires sequencing =
must follow a specific earlier file.

| # | File | Class | Notes |
|---|---|---|---|
| 1 | `20260711120001_seo_stage1_access_module.sql` | Safe | First migration; no dependency |
| 2 | `20260711120002_seo_stage1_workspaces.sql` | Requires sequencing | Depends on `seo_plan_limits`/`seo_usage_events` forward-refs from #1 |
| 3 | `20260711120003_seo_stage1_websites.sql` | Requires sequencing | Depends on `seo_workspaces` (#2) |
| 4–6 | Stage 2 (audit/recommendations/approval) | Requires sequencing | Depend on `seo_websites`/`seo_workspaces` |
| 7–9 | Stage 3 (Content Studio + private storage bucket) | Requires sequencing | Depends on Stage 1/2; creates `seo-content-assets` bucket |
| 10–13 | Stage 4 (Page Performance + latest-snapshot view) | Requires sequencing | View (#13) depends on the snapshot table (#12) |
| 14–16 | Stage 5 (Decline Diagnosis + current view) | Requires sequencing | View (#16) depends on tables (#14/#15) |
| 17–23 | Stage 6 (Off-Page Authority + AI Visibility, 8 tables) | Requires sequencing | Internally ordered (opportunities → campaigns → children → activity → AI tracking/gaps/mentions) |
| 24 | `20260712120024_seo_stage6_authority_campaign_create_rpc.sql` | Requires sequencing | Depends on all of #17–23 |
| 25 | `20260713120025_seo_phase16c_crawl_control_plane.sql` | Requires sequencing | New crawler domain; depends on `seo_websites` |
| 26–29 | Phase 16D–16G (worker lifecycle, discovery, extraction, publishing) | Requires sequencing | Each extends #25's tables |
| 30 | `20260715120030_seo_crawl_audit_finalization.sql` | Requires sequencing | Depends on #25–29 + Stage 2's audit tables |
| 31 | `20260716120031_seo_p1a_step1_ownership_verification.sql` | Safe | New additive tables; no existing-row impact |
| 32 | `20260716120032_seo_p1a_step2a_ownership_verification_rpcs.sql` | Requires sequencing | Depends on #31 |
| 33 | `20260716120033_seo_p1a_step2b_ownership_verification_service_rpcs.sql` | Requires sequencing | Depends on #31/#32 |
| 34 | `20260719120034_seo_p1b_verified_only_crawl_enqueue.sql` | **Breaking-if-misapplied** | `CREATE OR REPLACE FUNCTION public.seo_crawl_request(...)` — replaces the Phase 16C function body to add the verified-ownership guard. Safe **only** because it preserves the exact prior signature/grants (proven by static diff, `MODULE_LOCKS.md` P1b entry); applying it before #25 would fail outright (function doesn't exist yet) |
| 35 | `20260720120035_seo_reports_foundation.sql` | Safe | New additive table `seo_reports` |
| 36 | `20260720120036_seo_report_generate.sql` | Requires sequencing | Depends on #35 + the six live source areas |
| 37 | `20260720120037_seo_report_generate_revoke_anon.sql` | Safe | Corrective grant-only migration (defense-in-depth); no schema change |
| 38 | `20260720120038_seo_report_export_data.sql` | Requires sequencing | Depends on #35 |
| 39 | `20260720121000_seo_cross_project_identity_bridge.sql` | **Requires operator decision — DO NOT APPLY without a separate SSO task** | See §4.1 below; this is the sole pending migration |
| 40 | `20260720123000_seo_competitors.sql` | Safe | New additive table `seo_competitors` |
| 41 | `20260724120040_seo_competitor_generate.sql` | Requires sequencing | Depends on #40 + `seo_business_onboarding`/`seo_audit_runs` |
| 42 *(added 2026-09-19)* | `20260724130000_seo_recommendation_generate.sql` | Requires sequencing **+ a TEST gate** | Depends on the Stage 2 `seo_recommendations` and audit tables (`20260711120004`/`…005`, `20260714120029`). Adds two nullable columns and two partial unique indexes to `seo_recommendations` plus one guarded RPC (`RETURNS SETOF seo_recommendations`). **Not recorded on TEST** (rolled back 2026-07-24): it has local verification only, so it should not reach production before a separately approved TEST application + verification. |

## 4.1 The one pending migration: `20260720121000_seo_cross_project_identity_bridge.sql`

> **[2026-09-19 correction]** This section was written when SSO was the *only*
> repository migration not recorded on TEST. There are now **two** (SSO, and
> `20260724130000` Recommendation Generation — absent after rollback, see the
> banner). The SSO analysis below is unchanged. In "Path A", "the 40 already-proven
> migrations" means the 40 recorded on TEST; Recommendation Generation would be an
> additional, separately gated item.

This is the **only** migration not yet applied anywhere, including TEST. Per
`SEO_DECISIONS.md` A14, it is **intentionally deferred** and must not be
applied "as a side effect" of an unrelated migration push. For production
promotion, there are exactly two paths, and **choosing between them is a
REQUIRES OPERATOR DECISION item, not something this plan resolves:**

- **Path A — launch without it.** Production ships with the 40 already-proven
  migrations; SEO continues on standalone TEST/local-style login in
  production too. The cross-project SSO bridge remains a future, separately
  scoped task exactly as it is on TEST today.
- **Path B — apply it as part of this promotion.** This migration has
  **never been applied to any environment**, including TEST — it has zero
  TEST-verification evidence beyond having been statically reviewed at
  authoring time. Applying it to production without first applying and fully
  verifying it on TEST would violate the "TEST first, always" invariant
  (`SEO_PROJECT_CONTEXT.md` §7) that every other migration in this plan
  followed. **If Path B is chosen, the correct sequence is: apply + verify
  on TEST first (a separate, explicitly-approved SSO task), THEN include it
  in a later production promotion — not this one.**

**This plan's recommendation: Path A for the first production promotion.**
Every other migration+RPC in the SEO module has an unbroken TEST-apply →
TEST-verify → lock chain; migration #39 is the only one without that
evidence trail. Bundling it into the *first* production promotion would be
the first time in the project's history that an unverified migration reaches
production.

## 4.2 Downtime

> **[2026-09-19 correction for migration #42]** The blanket statements in this
> section about "no `ALTER TABLE` that rewrites an existing table" and "no index build
> without `CONCURRENTLY`" are true of the 41 files audited on 2026-07-24 but **not**
> of `20260724130000`: it runs `ALTER TABLE public.seo_recommendations ADD COLUMN`
> ×2 (nullable, metadata-only — no rewrite) and two plain (non-`CONCURRENTLY`)
> `CREATE UNIQUE INDEX` statements, which block writes to that table while they
> build. On a fresh production database this is immaterial, but a promotion task
> must not assume "zero downtime for all migrations" for #42 without re-checking.

**No migration in the 40 already-verified files requires downtime.** All are
either pure `CREATE TABLE`/`CREATE POLICY`/`CREATE FUNCTION` additions, or (for
migration #34, the one `CREATE OR REPLACE FUNCTION`) a function-body swap that
Postgres performs without locking the calling table or blocking readers —
proven safe on TEST via the P1b two-session concurrency proof
(`P1B_CONCURRENCY_VERIFICATION_GUIDE.md`). **No `ALTER TABLE` that rewrites an
existing table, no index build without `CONCURRENTLY`, and no data backfill
appear anywhere in the 41 files audited on 2026-07-24 (#42 is the exception noted above)** (confirmed by the additive-only convention
and by every migration's own header comment, all read during this task's
document review). **Expected downtime for the migration step: zero**, subject
to the same real-time verification a promotion-execution task must still
perform against the actual production database (this plan does not run
`EXPLAIN`/lock-analysis against a database that doesn't exist yet).

## 4.3 Rollback strategy (migrations)

- **Per-migration TEST-only rollback scripts exist for several stages**
  (e.g. `supabase/test/seo_competitors_foundation_rollback_TEST_ONLY.sql`,
  `seo_competitor_generate_rollback_TEST_ONLY.sql`,
  `seo_report_generate_rollback_TEST_ONLY.sql`,
  `seo_p1b_verified_only_crawl_enqueue_rollback_TEST_ONLY.sql`) — these were
  authored for TEST-side authoring safety and have **never been run** (every
  TEST apply succeeded). Whether they are safe to run against a
  **populated** production database (vs. the disposable/near-empty TEST
  fixtures they were authored against) is **UNKNOWN** and must be
  re-verified, not assumed, before any production rollback attempt.
- **General principle (matches `SEO_DECISIONS.md` C1):** because every
  migration is additive, the safest rollback for a *newly promoted* module
  with no real customer data yet is to **not roll back schema at all** —
  disable the affected frontend route/RPC grant (see §5 rollback triggers)
  and leave the additive tables in place empty. Schema rollback (`DROP
  TABLE`/`DROP FUNCTION`) should be a last resort, reserved for a
  pre-launch/dark-launch window before any real customer data exists in the
  new tables.
- **No production backup/restore mechanism has been established for this
  project** — **REQUIRES OPERATOR DECISION**: what Supabase backup tier /
  PITR window will the production project have, and has it been confirmed
  *before* the first migration is applied (this must be true before step 1
  of §3, not decided after).

---

# 5. Rollback Plan

## 5.1 How to revert, by layer

| Layer | Revert action |
|---|---|
| Frontend (Cloud Run) | Redeploy the immediately-prior Cloud Run **revision** (Cloud Run keeps prior revisions by default) or reroute 100% traffic back to it — this is the fastest, lowest-risk rollback and requires no database action. |
| Runtime config | If only the `VITE_SUPABASE_*` values are wrong (not the code), rebuild the image with corrected `--build-arg` values and redeploy — again no database action. |
| Backend (worker) | Scale the worker to zero instances / stop the process. It holds no customer-facing state of its own; jobs it would have claimed simply remain unclaimed until it is safely redeployed. |
| Database (RLS/RPC only, no new bad data) | Revert the specific `CREATE OR REPLACE FUNCTION` (only migration #34 in the set is a replace) to its pre-guard body via the authored-but-unrun TEST-style rollback pattern — **re-verify against the actual production schema first**, do not run a TEST rollback script against production unmodified. |
| Database (new tables with real data already written) | **Do not `DROP TABLE`.** Freeze writes (revoke the write-path RPC's `EXECUTE` grant from `authenticated`, or disable the frontend route that calls it) and leave the data in place for forensic/recovery purposes. Schema-level rollback is reserved for the pre-launch window only (§4.3). |

## 5.2 Decision points

1. **Before applying any migration:** has the production project's backup/PITR
   policy been confirmed? If not → **stop, do not proceed** (this is a
   go/no-go gate, not a soft recommendation).
2. **After migrations, before worker deploy:** did every migration apply
   cleanly and does a read-only structural check (tables/RLS/policies/
   functions present, matching the TEST-verified shape) pass? If not →
   roll back to the last known-good schema state per §5.1 (database row) and
   do not proceed to worker deployment.
3. **After worker deploy, before frontend deploy:** is the worker's
   connectivity to production Supabase healthy (claim-loop runs with zero
   jobs available, no crash, no exception) for an observation window (see
   §13)? If not → stop the worker, do not proceed to frontend deploy.
4. **After frontend deploy, before enablement:** does the full smoke-test
   checklist (§6) pass end-to-end against production? If not → do not flip
   the enablement gate; roll back the frontend revision.
5. **After enablement:** are the monitored signals (§8) within acceptable
   bounds for the defined monitoring window (§13)? If not → immediately
   revert traffic to the prior state per §5.1 and reassess.

## 5.3 Maximum acceptable outage

**UNKNOWN — REQUIRES OPERATOR DECISION.** No SLA, uptime target, or maximum
acceptable outage window is recorded anywhere in the authoritative
documentation for this module. Given the deployment order in §3 is designed
so that **zero real customers exist before enablement (step 6)**, the
practical outage risk during promotion itself should be near-zero for
*existing* users (there are none yet on production) — but the operator must
still set an explicit SLA target for the promoted service before go-live,
since that target drives the monitoring window (§13) and the go/no-go
threshold (§11).

---

# 6. Smoke Tests

A complete production checklist, run in the order implied by §3 (steps 1–5).
Every item must be verified **against the actual production project**, not
inferred from TEST evidence — TEST evidence proves the *code and migrations*
are correct; the smoke test proves the *deployed production instance* is
correct.

## 6.1 Database

- [ ] All 40 (or 41, if Path B was chosen — §4.1) migrations show as applied
      in `supabase migration list --linked` against the **production** project
      ref, recorded exactly once each.
- [ ] `20260720121000` status matches the chosen path (pending if Path A;
      applied + independently TEST-verified first if Path B).
- [ ] Structural check: every table from §1.2's locked modules exists with
      RLS enabled (spot-check against the `MODULE_LOCKS.md` locked-table
      lists for Page Performance, Stage 6, Crawler 16C–16H, P1a, P1b,
      Reports v1, Competitor Benchmarking).
- [ ] Every guarded RPC's grants match its documented contract: `authenticated`
      execute where intended, `anon` explicitly revoked where the code
      revokes it (`seo_report_generate`, `seo_report_export_data`,
      `seo_competitor_generate`, the four P1a customer RPCs, `seo_crawl_request`/
      `seo_crawl_cancel`/`seo_crawl_request_audit`).
- [ ] Service-role-only RPCs (worker claim/lifecycle, ownership claim/result)
      are **denied** to `authenticated`/`anon` on production, exactly as on
      TEST.
- [ ] The `seo-content-assets` storage bucket exists, `public=false`, correct
      MIME allowlist and size limit.

## 6.2 Backend (worker)

- [ ] Worker process starts against production Supabase with a valid
      service-role key sourced from a secrets manager (never a repo file).
- [ ] Worker logs a successful claim-loop cycle with **zero eligible jobs**
      (since no customer has enqueued anything yet) and does not crash or
      loop-error.
- [ ] `CRAWLER_ALLOW_NON_TEST_JOBS` and any TEST-only fixture/prefix
      behavior are correctly set for production (must not silently process
      TEST-tagged jobs, and must not default to permissive TEST behavior).
- [ ] No service-role key, lease token, or DNS challenge value appears in
      worker logs.

## 6.3 Frontend

- [ ] Production Cloud Run URL responds `200` for `/`, `/help`, `/seo/login`,
      and a representative `/seo/*` protected route (redirects to login when
      signed out).
- [ ] `curl -i` against a real hashed asset path returns `200` with the
      immutable long-cache header; a missing-asset path returns `404`, never
      the SPA shell (per the logic already proven in
      `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` §7, now
      re-verified against the real running container, not a static trace).
- [ ] `index.html` itself is served with `no-cache`.
- [ ] Security headers present on both `200` and `404` responses
      (`X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`,
      `Permissions-Policy`).
- [ ] No `VITE_*` value leaks a service-role key (the bundle is public by
      design — confirm only the anon key is present, by inspecting the
      built JS if needed).

## 6.4 Runtime config / integration

- [ ] Signed-in read paths (Reports, Competitor Benchmarking, Page
      Performance, etc.) return real production data with **no mock
      fallback** (`fallbackToMockOnError: false` paths must surface a real
      error, not silently show mock data, if something is misconfigured).
- [ ] `SEO_DATA_MODE` resolves to `"supabase"` in the deployed production
      bundle (confirm via a network request to a real Supabase REST/RPC
      endpoint, not a `localStorage` mock read).
- [ ] Cross-project SSO bridge status matches the chosen §4.1 path (either
      absent/inactive for Path A, or verified working for Path B).

## 6.5 End-to-end per locked module (ties into §7)

- [ ] Page Performance Tracker: seed one page/snapshot as an authenticated
      owner/admin/team_member; confirm client read-only.
- [ ] Stage 6 (Off-Page + AI Visibility reads): confirm opportunity/campaign
      reads render; confirm the guarded transition RPCs enforce the
      documented role matrix.
- [ ] Crawler 16C–16H + P1b: confirm `seo_crawl_request` rejects an
      unverified website and accepts a verified one (this requires a real
      DNS-TXT verification to have succeeded on the production website
      first — sequence this after §6.5's ownership-verification item).
- [ ] P1a (DNS-TXT ownership verification): confirm `initiate`/`recheck`
      issue real challenge values and the isolated worker's `verify-once`
      mode resolves them via real DNS.
- [ ] Reports v1: confirm `seo_report_generate` produces a report matching
      live source data; confirm PDF export renders client-side with no
      regeneration.
- [ ] Competitor Benchmarking: confirm `seo_competitor_generate` produces a
      canonical set with `data_provenance='estimated'` only; confirm the
      role gate (owner/admin/team_member allowed, client denied in UI and
      at the RPC).

---

# 7. User Acceptance

Checklist by module — **who** must sign off, mirroring the role-based
acceptance pattern already used for every locked module's TEST verification
(owner/admin/team_member/client, plus the operator/technical-owner role).

| Module | Acceptance owner | Checklist |
|---|---|---|
| Page Performance Tracker | Technical owner + one real owner-role user | Snapshot read renders correctly; role gating matches TEST evidence |
| Stage 6 — Off-Page + AI Visibility | Technical owner + owner/admin/team_member/client accounts | Opportunity/campaign workflow role matrix matches `MODULE_LOCKS.md`'s protected-contract list exactly |
| Crawler 16C–16H + P1b | Technical owner + one verified-ownership production website | Crawl request/cancel/status UI works; unverified-website rejection confirmed |
| P1a (Ownership Verification) | Technical owner + owner/admin/team_member/client accounts | DNS-TXT challenge issuance, recheck, revoke all match the TEST role matrix; **no challenge/lease value visible to client/team_member** |
| Reports v1 | Technical owner + owner/admin account | Generate → renders → PDF export all match TEST evidence; client sees view-only, no generate/export |
| Competitor Benchmarking | Technical owner + owner/admin/team_member/client accounts | Generate/Refresh role gate matches the locked contract exactly; client denied in UI **and** at the RPC (direct-call test, matching the TEST acceptance method already used) |
| Frontend product surfaces (Help Center, navigation) | Technical owner | Renders correctly on the production domain; no broken links to locked-module content |

**Sign-off format:** each row should be closed with the same evidence style
already used throughout this repo's sign-offs — dated, named acceptance
steps, exact requests/responses observed, no fabricated claims. **A future
promotion-execution task must produce this evidence; it does not exist yet
because production does not exist yet.**

---

# 8. Monitoring

What to watch **during and immediately after** rollout (ties to the
monitoring window in §13):

- **Application errors:** Cloud Run request logs for 5xx rates on the
  frontend; any Supabase RPC call returning a genuine error (not the
  intentional non-leaking authorization-denial messages) at an
  unexpectedly high rate.
- **Database:** connection count, query latency, and — specifically for the
  two guarded generation RPCs with advisory locks (`seo_report_generate`,
  `seo_competitor_generate`) — `pg_locks` advisory-wait duration, to confirm
  the concurrency behavior proven on TEST (P1b, Reports Stage 2, Competitor
  Stage 2A) holds under real concurrent load.
- **Worker health:** process uptime, claim-loop cadence, lease-timeout
  rate, and DNS-TXT verification outcome distribution (a spike in
  `dns_not_found`/`dns_mismatch` could indicate a real customer-facing
  configuration problem, not necessarily a code defect — see the
  `verify-once` acceptance precedent where a legitimate `dns_not_found` was
  correctly treated as a non-defect business outcome).
- **RLS/authorization anomalies:** any successful read/write from a role
  that should have been denied (this would indicate an RLS or RPC
  regression, not just an error — treat as a **security incident**, not a
  routine bug).
- **Storage:** `seo-content-assets` bucket usage/quota, and confirm no
  object is ever publicly readable.
- **Cost/usage:** Cloud Run instance count and Supabase compute/bandwidth,
  especially during the initial enablement window when traffic patterns are
  unproven.
- **Monitoring tooling:** **UNKNOWN — REQUIRES OPERATOR DECISION.** No
  monitoring/alerting stack (Cloud Monitoring dashboards, Supabase's own
  observability, a third-party APM) has been selected or configured
  anywhere in this repository. This must be decided and wired **before**
  step 6 (enablement) in §3, not after.

---

# 9. Risks

| # | Risk | Probability | Impact | Mitigation |
|---|---|---|---|---|
| 1 | No dedicated production Supabase project identified yet — promotion cannot begin until one exists | High (currently true) | Blocks all further steps | Operator decision required first (§2); do not schedule a promotion date until resolved |
| 2 | Cross-project SSO bridge migration (`20260720121000`) has zero TEST-apply evidence | Medium (only relevant if Path B is chosen) | High if applied blind — first-ever unverified migration reaching a real environment | Recommend Path A (§4.1); if Path B is ever chosen, require a full TEST apply+verify cycle first |
| 3 | Worker deployed with real jobs already claimable before frontend/enablement gate closes | Low (deployment order in §3 prevents this by design) | Medium — a worker could start processing before smoke tests complete | Deploy worker with zero eligible jobs (no customer has enqueued yet); verify claim-loop is a true no-op before proceeding |
| 4 | `CREATE OR REPLACE FUNCTION` migration (#34, P1b guard) applied out of sequence relative to #25 (Phase 16C) | Low (migration files are naturally ordered by filename/timestamp and every prior promotion used the same ordered-apply tooling) | High if misapplied — function replace would fail outright, not silently corrupt | Apply migrations strictly in filename order via the same tooling already used on TEST (`supabase db push`/`db query -f` + `migration repair`, never manual out-of-order SQL) |
| 5 | Production RLS/RPC grants drift from the TEST-verified contract during the promotion process (e.g. a manual `GRANT`/`REVOKE` typo) | Low–Medium | High — could silently weaken a role gate that every lock's TEST evidence depends on | Run the exact structural + grant checks from §6.1 against production, not just "migrations applied"; treat any grant mismatch as a go/no-go blocker |
| 6 | No backup/PITR policy confirmed before first migration apply | Unknown until confirmed | High — no recovery path if something goes wrong post-launch | Hard gate (§5.2 decision point 1): do not apply the first migration until this is confirmed |
| 7 | Worker service-role key handling on production (no secrets-manager integration currently designed) | Medium (genuinely undecided) | Critical if the key ends up in a repo/log/frontend bundle | Must use a real secrets manager (e.g. GCP Secret Manager, matching the `--set-secrets` pattern already used for the TEST Cloud Build pipeline) — never a `.env` file committed anywhere |
| 8 | No monitoring/alerting stack selected | High (currently true) | Medium–High — issues could go unnoticed post-launch | Resolve before step 6 (enablement) in §3; do not enable production traffic without at least the items in §8 wired |
| 9 | Cloud Run frontend container has never actually been built or run (Docker was unavailable in the authoring environment) | Medium (real but untested risk — the Dockerfile/nginx config were only statically verified) | Medium — a real build/run could surface an issue the static trace couldn't catch | Perform an actual `docker build` + local `docker run` + the full curl-based route table from `DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md` §10–11 *before* any production Cloud Run deploy, even for TEST if not already done |
| 10 | No production-specific Cloud Build pipeline exists | High (currently true — only the TEST pipeline exists) | Blocks step 3 of §3 | Author a separate production `cloudbuild.*.yaml` with its own project/region/service/secrets/trigger, reviewed the same way the TEST pipeline was |
| 11 | Digibility Core's production `seo-bridge` Edge Function status is unknown to this repo | Unknown | High if Path B (SSO) is chosen and the function doesn't exist or isn't production-configured | Confirm with the Digibility Core owner before ever attempting Path B; irrelevant if Path A is chosen |
| 12 | Real external competitor-data / crawler / GSC / GA4 / LLM integrations don't exist — production would still be running 100% on local heuristics / manual seed data for those areas | Certain (by design, documented in every relevant lock) | Low (not a defect — documented, truthful provenance throughout) | No mitigation needed; ensure user-facing copy stays truthful post-launch exactly as it is today (`estimated` provenance, "not connected" for unavailable areas) |

---

# 10. Deferred Work

Everything intentionally excluded from this promotion plan and from the
promotion itself:

- **Cross-project SSO** (migration `20260720121000`) — see §4.1; a separate,
  explicitly-approved task, not part of the recommended first promotion.
- **Real external competitor-data provider integration** (SEMrush/Ahrefs/GSC)
  — Competitor Benchmarking ships with local heuristic estimates only;
  any future provider integration is an additive migration adding a new
  `data_provenance` value, never relabeling existing `estimated` rows
  (`MODULE_LOCKS.md` Competitor Benchmarking entry).
- **Real crawler discovery/GSC/GA4/GBP/CMS ingestion** — none of these exist
  anywhere in the current codebase; Stage 4 (`source` column),
  `seo_connection_status`, and AI Visibility all remain placeholder-only.
- **Real LLM generation** — content drafts/wireframes and AI-visibility
  mention tracking are schema seams and manual-seed data only.
- **Usage/subscription billing enforcement** — `seo_subscriptions`/
  `seo_plan_limits` exist but have no gateway or enforcement wiring; any
  production launch ships without plan-tier limits actually being enforced
  unless that is built first (**REQUIRES OPERATOR DECISION** whether this is
  acceptable for a first production launch).
- **Rate limiting** — no rate-limiting layer exists anywhere in the stack
  (Supabase's own platform-level limits are the only current backstop).
- **CSV export, report history, scheduling, email delivery, public/secure
  sharing, period comparison** (Reports v1 deferred scope).
- **Scheduled/automatic competitor regeneration, competitor-count/plan-tier
  limits, historical trend tracking** (Competitor Benchmarking deferred
  scope).
- **AI Visibility writes; real LLM ingestion** (Stage 6 deferred scope).
- **Locked-UI defense-in-depth for verified-only crawl initiation** — P1b's
  server-side enforcement already makes this non-blocking; the optional
  client-side pre-block remains unbuilt.
- **Mobile navigation drawer** — pre-existing UI gap, out of scope until
  separately prioritized.
- **Formal `MODULE_LOCKS.md` entries for the six informally-locked modules**
  (§1.2) — out of scope for this planning document.
- **This document does not select, build, or configure any monitoring/
  alerting tool** (§8) — that selection is a prerequisite the operator must
  complete, not something this plan performs.
- **This document does not create a production Supabase project, a
  production Cloud Build pipeline, or any GCP resource** — all of that is
  explicitly out of scope per this task's own instructions.

---

# 11. Go / No-Go Checklist

Final release checklist — **every item must be checked before step 6
(enablement) in §3**:

- [ ] Production Supabase project identified/created and target confirmed
      by the technical owner (§2, §9 risk 1).
- [ ] Backup/PITR policy confirmed and active on the production project
      **before** the first migration was applied (§4.3, §5.2).
- [ ] Migration path decision made and documented: Path A (recommended) or
      Path B for `20260720121000` (§4.1).
- [ ] All intended migrations (40 or 41 per the path chosen) applied exactly
      once each, verified via `supabase migration list` against the
      production project ref.
- [ ] §6.1 database structural/grant checks all pass against production.
- [ ] Worker deployed, healthy, connected to production Supabase, service-role
      key sourced from a real secrets manager, zero eligible jobs claimed
      pre-launch (§6.2).
- [ ] Frontend image actually built and run at least once (not just
      statically traced) and passes the full §6.3 route/asset/header
      checklist against the deployed production Cloud Run URL.
- [ ] Production `cloudbuild.*.yaml` (or equivalent) authored, reviewed, and
      used for the actual deploy — not the TEST pipeline pointed at a
      production project by substitution overrides.
- [ ] §6.4 runtime-config/integration checks pass — no mock fallback, no
      service-role leak, SSO status matches the chosen path.
- [ ] §6.5 end-to-end per-module checks pass for every locked module.
- [ ] §7 user acceptance sign-off obtained for every module, by the named
      acceptance owner(s).
- [ ] Monitoring/alerting stack selected, configured, and actively
      receiving data **before** traffic is enabled (§8, §9 risk 8).
- [ ] Rollback plan (§5) reviewed and understood by whoever is on point
      during the launch window; rollback mechanism for each layer confirmed
      *actually available* (e.g. Cloud Run revision history is retained,
      not pruned).
- [ ] Maximum acceptable outage / SLA target explicitly set by the operator
      (§5.3).
- [ ] Approval matrix (§12) fully signed for every stage already executed.
- [ ] No open, unresolved item in §9 (Risks) rated High probability **and**
      High/Critical impact remains unmitigated.

**If any box is unchecked, this is a NO-GO.** This plan does not authorize
proceeding with any box unchecked.

---

# 12. Approval Matrix

| Stage | Who approves | Notes |
|---|---|---|
| Production Supabase project selection/creation | **REQUIRES OPERATOR DECISION** — likely the technical owner / infrastructure owner, name UNKNOWN to this repo | Must happen before any other step |
| Migration path decision (§4.1, Path A vs B) | Technical owner, informed by this plan's recommendation (Path A) | Should be a written decision, not implicit |
| First production migration apply | Technical owner + whoever holds the Supabase project's admin access | Mirrors the "developer/technical owner sign-off" gate already named in `BACKEND_MILESTONE_HANDOFF.md` §5 |
| Worker deployment | Technical owner (infrastructure) | Requires the secrets-manager decision (§9 risk 7) to be resolved first |
| Frontend Cloud Run deploy | Technical owner (infrastructure) | Requires the production `cloudbuild.*.yaml` (§9 risk 10) to exist and be reviewed first |
| Smoke test sign-off (§6) | Technical owner, executing or directly observing every checklist item | No smoke-test item may be marked passed without direct observation — no assumptions carried over from TEST |
| User acceptance (§7) | Named acceptance owner per module (technical owner + role-representative accounts) | Mirrors the per-role acceptance pattern already used for every TEST lock |
| Enablement (opening traffic) | Technical owner, **with explicit go/no-go sign-off against §11** | Final gate; must not be delegated informally |
| Post-launch monitoring window sign-off | Technical owner | Confirms the monitoring window (§13) completed with no unresolved alert |
| Module lock updates reflecting "production-verified" status | Whoever owns `docs/markdown/MODULE_LOCKS.md` edits, following the same additive-note convention used throughout this repo's history | Should not overwrite existing TEST-verification language — add a dated production note, per `DOCUMENTATION_WORKFLOW_RULES.md` §3 |

**All named approvers above are role descriptions, not individuals — this
repository contains no record of who specifically holds these roles.
REQUIRES OPERATOR DECISION to name real people/teams.**

---

# 13. Timeline

**UNKNOWN / REQUIRES OPERATOR DECISION for all concrete dates** — no target
launch date, freeze window, or staffing plan exists anywhere in the
authoritative documentation. What can be stated is the **relative** ideal
shape of the timeline, derived from the deployment order (§3) and the
decision points (§5.2):

## 13.1 Ideal deployment timeline (relative, not dated)

1. **T-minus (preparation phase, duration UNKNOWN):** resolve every
   REQUIRES OPERATOR DECISION item in §2, §4.1, §8, §9, and §12 — none of
   the remaining steps should start until these are closed.
2. **T-0, Step 1 (database):** apply migrations to the confirmed production
   project. Expected to be fast (minutes, given zero downtime per §4.2) but
   should be done during a low-traffic window purely as a precaution, since
   this is the first-ever write to that project from this codebase.
3. **T-0 + short interval, Step 2 (worker):** deploy worker in an idle
   state; observe a claim-loop cycle or two before proceeding (**REQUIRES
   OPERATOR DECISION** on exact observation duration — suggest at least one
   full `CRAWLER_POLL_INTERVAL_SECONDS`-equivalent production interval,
   itself to be chosen).
4. **T-0 + short interval, Step 3–4 (frontend + runtime config):** build and
   deploy the production image; verify it serves correctly before pointing
   it at real Supabase data (the two-stage build/verify pattern from §3
   step 4).
5. **T-0 + verification window, Step 5 (smoke tests):** run the full §6
   checklist. **No fixed duration recommended by this plan** — it should
   take as long as it takes to genuinely execute every item, not be
   time-boxed artificially.
6. **T-0 + enablement, Step 6:** flip the enablement gate only after §11 is
   fully checked.

## 13.2 Rollback window

The rollback mechanisms in §5.1 (Cloud Run revision swap, worker
scale-to-zero, RPC grant revocation) are all **fast, reversible actions on
the order of minutes**, not requiring a scheduled maintenance window,
**provided** the decision to roll back is made promptly per §5.2's decision
points. **No specific rollback time budget (e.g. "must roll back within 30
minutes of detecting an issue") is recorded anywhere** — **REQUIRES OPERATOR
DECISION** if a formal budget is wanted.

## 13.3 Monitoring window

**REQUIRES OPERATOR DECISION** for exact duration. A reasonable minimum,
consistent with the "no real customers exist yet at enablement" design of
this plan, would be an active-watch period immediately following enablement
(long enough to observe at least one full cycle of every item in §8 —
worker claim/lease cycle, a real end-to-end user flow per locked module,
and at least one billing/usage cycle if usage enforcement is ever added) —
but the exact number of hours/days is **not this plan's decision to make**.

---

## Appendix: Documents read to produce this plan

`SEO_CONTEXT_HANDOVER.md`, `SEO_IMPLEMENTATION_STATUS.md`,
`SEO_PROJECT_CONTEXT.md`, `SEO_DECISIONS.md`,
`docs/markdown/MODULE_LOCKS.md`, `docs/markdown/PROJECT_DOCUMENTATION_INDEX.md`,
`docs/markdown/BACKEND_MILESTONE_HANDOFF.md`,
`DIGIBILITY_FRONTEND_CLOUD_RUN_DEPLOYMENT_READINESS.md`, `cloudbuild.yaml`,
`.env.example`, `crawler-worker/.env.example`, `crawler-worker/package.json`,
the full `supabase/migrations/` directory listing, and a live (read-only)
`supabase migration list` + `supabase projects list` against the linked
`Digi_SEO_Test` project. No production project, database, or cloud resource
was contacted.
