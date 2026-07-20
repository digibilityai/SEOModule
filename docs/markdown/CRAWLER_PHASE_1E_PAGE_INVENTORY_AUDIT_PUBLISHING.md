# Crawler Phase 1E — Controlled Page Inventory & Audit Publishing (Phase 16G)

**Status: Implemented + TEST-verified.** An additive, transactional, idempotent
publishing layer that connects the verified crawler domain (Phase 16C–16F) to the
existing customer **Page Inventory** (Stage 4) and **Audit** (Stage 2) contracts
via one explicit crawl-job→audit-run association and one service-role-only
transactional publish RPC that reads the persisted crawler-domain records
**server-side**. It writes **NOTHING** to `seo_recommendations`, computes **no**
score, adds **no** customer crawl UI, and touches **no** locked Page Performance /
Stage 6 table. Publication contract **VERSION 1**. Migration `20260714120029`.
Not deployed; crawler not customer-operational; **production untouched.**
**Date:** 2026-07-14.

## 1. Scope & exclusions

**In:** additive `audit_run_id` on crawl jobs; a guarded customer orchestration
RPC (`seo_crawl_request_audit`) that atomically creates + binds an audit run and
a crawl job and returns both ids; a deterministic 29-code issue→Audit mapping
table; additive nullable provenance on `seo_page_inventory` + `seo_audit_issues`;
a `seo_crawl_publications` evidence table; one service-role-only transactional
publish RPC (`seo_crawl_worker_publish_results`); a worker publication
coordinator; worker pipeline placement before terminal completion.
**Out (deferred):** `seo_recommendations` generation, AI remediation, audit
scoring, customer crawl-request/status/freshness/retry UI, worker deployment,
recurring scheduling, stale-page/removal detection, GSC/GA4/LLM, Page Performance
writes, Stage 6 writes, parent-Digibility integration, new issue rules, changes
to Phase 1D thresholds/severities, changes to role strings/permissions.

## 2. Explicit audit-run association (no latest-run guessing)

**Chosen: Option A** — additive nullable `seo_crawl_jobs.audit_run_id`
(`REFERENCES seo_audit_runs ON DELETE SET NULL`) populated **only** by the new
guarded orchestration RPC. `seo_crawl_request` and `seo_run_audit` are preserved
**unchanged** (the orchestration RPC *reuses* `seo_crawl_request` verbatim, then
creates the run and binds it). One crawl job ↔ at most one audit run; workspace +
website must match; association is set before publishing and never silently
reassigned after results (idempotent replay returns the existing pair; a
terminal-but-unassociated job is refused). Every publish derives the run from
this persisted link — it never selects "the latest".

**Rejected:** *Option B (association table)* — unnecessary indirection for a 1:1
link. *Option C (new request/run RPC replacing the generic ones)* — larger blast
radius; the generic `seo_crawl_request` must stay unchanged. *Any timestamp /
website-only / latest-running heuristic* — unsafe (could target the wrong run).

`seo_crawl_request_audit(p_website_id, p_idempotency_key, p_config)` →
`(audit_run_id, crawl_job_id, job_status)`. `EXECUTE` = `authenticated` only
(anon revoked); in-function `auth.uid()` + `has_seo_module_access` +
owner/admin/team_member-or-global-admin gate (clients denied — same matrix as
`seo_crawl_request`). No customer UI calls it yet (SQL/worker-verified).

## 3. Publishing architecture & version

Ownership split: the **database** owns the final product-table mapping + integrity
(one transactional `SECURITY DEFINER` function, `search_path=public`, no dynamic
SQL); the **worker** only orchestrates the call, validates returned counts/status,
logs safe metrics, and classifies failures. The worker sends **no** page/issue
payload, **no** status, **no** counts, **no** target row ids — the RPC reads
`seo_crawl_page_snapshots` + `seo_crawl_issues` server-side and derives
workspace/website from the job. **Publication contract = VERSION 1** (recorded in
evidence); it covers the Page-Inventory mapping, the issue mapping, the severity
conversion, provenance behaviour and audit-run update semantics. A future mapping
change must bump the version, not reinterpret history.

## 4. Page Inventory mapping (identity, ownership, staleness)

**Identity:** existing canonical `(website_id, page_url) WHERE is_active`
(`page_url` = the snapshot's normalized `requested_url`). Never title; never
canonical; distinct pages never merged.

| Target column | Source | Ownership |
|---|---|---|
| `page_title` | snapshot `title` | crawler (updated) |
| `meta_description` | snapshot `description` | crawler |
| `indexability_status` | `effective_index ? 'indexable' : 'noindex'` | crawler |
| `canonical_url` | `canonical_resolved` | crawler |
| `last_seen_at` | `extracted_at` | crawler |
| `http_status`,`word_count`,`content_type`,`first_h1` | snapshot (additive nullable cols) | crawler |
| `source`,`source_crawl_job_id`,`crawler_extracted_at`,`crawler_extractor_version` | provenance (additive) | crawler |
| `page_type`,`priority`,`is_tracked`,`content_status`,`is_active`,`first_seen_at` | — | **user-owned; never written** |

**Stale-job protection (DB-level):** a crawler upsert updates a row only when
`crawler_extracted_at IS NULL OR incoming >= existing` — an older/retried job
cannot overwrite newer facts; a replay of the same job converges. **Non-crawler
preservation:** the update WHERE also requires `source IS NULL OR source='crawler'`
— rows explicitly tagged `manual`/`seed` are never modified. **Missing pages** are
never marked removed/inactive/deleted (partial crawls omit valid pages;
page-removal semantics remain deferred). Redirects: `page_url` is the requested
URL; `final_url`/canonical are recorded but do not change identity.

## 5. Audit Issue mapping (all 29 stable codes)

The registry has **29** stable codes (**26 page** + **3 site**) — the earlier
"26 total" figure undercounted by omitting the digit-bearing `H1_MISSING`,
`H1_MULTIPLE`, `H1_EMPTY`; corrected here and in the Phase 1D doc. All 29 are
mapped in `seo_crawl_issue_audit_map` (no silent drops; the publish RPC **refuses**
to publish if any crawler code is unmapped). Audit categories are chosen so only
genuinely high-risk crawler findings map to a high-risk Audit category
(`canonical`/`indexability`/`redirects` → `is_high_risk_category=true` via the
existing trigger); metadata/heading/content/image findings map to non-high-risk
`crawl` (or `duplicate_content`). The **original** crawler category + severity +
rule version + fingerprint are preserved in provenance (`source_category`,
`source_severity`, `source_rule_version`, `source_issue_fingerprint`).

**Severity map** (crawler→Audit, rank-preserving, no inflation):
`critical→critical`, `error→high`, `warning→medium`, `info→low`.
**Deterministic non-AI fields** (to satisfy the Audit NOT-NULL contract):
`impact` from severity; `effort='medium'`; `risk = high-risk-category ? 'high' :
'low'`; `confidence_percentage=90`; `fix_owner='system_suggestion'`;
`title`/`simple_explanation`/`why_it_matters`/`technical_explanation`/
`suggested_next_action` are static customer-safe strings from the map (not AI, not
recommendations).

| Crawler code(s) | Audit category | Audit severity (from crawler) | Scope |
|---|---|---|---|
| TITLE_MISSING, TITLE_EMPTY | crawl | high (error) | page |
| TITLE_MULTIPLE | crawl | medium (warning) | page |
| TITLE_TOO_SHORT/LONG | crawl | low (info) | page |
| DESCRIPTION_MISSING/EMPTY/MULTIPLE | crawl | medium (warning) | page |
| DESCRIPTION_TOO_SHORT/LONG | crawl | low (info) | page |
| H1_MISSING, H1_EMPTY | crawl | medium (warning) | page |
| H1_MULTIPLE | crawl | low (info) | page |
| HTML_LANG_MISSING, LOW_CONTENT, IMAGES_MISSING_ALT | crawl | low (info) | page |
| DECODE_UNSUPPORTED | crawl | medium (warning) | page |
| CANONICAL_MISSING/CROSS_ORIGIN/NON_SELF | canonical (**high-risk**) | low (info) | page |
| CANONICAL_MULTIPLE/INVALID/UNSAFE | canonical (**high-risk**) | medium (warning) | page |
| EFFECTIVE_NOINDEX | indexability (**high-risk**) | low (info) | page |
| CONFLICTING_ROBOTS | indexability (**high-risk**) | medium (warning) | page |
| REDIRECT_CHAIN_LONG | redirects (**high-risk**) | medium (warning) | page |
| DUPLICATE_TITLE, DUPLICATE_CONTENT | duplicate_content | medium (warning) | site |
| DUPLICATE_DESCRIPTION | duplicate_content | low (info) | site |

All 29 are publishable in VERSION 1 (no exclusions).

## 6. Site-level issues (no fabricated pages)

`seo_audit_issues.affected_page_url` stays **NOT NULL** (unchanged). Site issues
(`DUPLICATE_TITLE/DESCRIPTION/CONTENT`) set `affected_page_url` = the run's real
`website_url` and the additive `issue_scope='site'` — a legitimate website-level
representation with **no synthetic page URL and no fake page-inventory row**. Page
issues set `issue_scope='page'` and `affected_page_url` = the snapshot URL.

## 7. Provenance, identity & idempotency

Crawler audit issues carry `source='crawler'`, `crawl_job_id`,
`source_issue_fingerprint = '<CODE>::<crawler fingerprint>'`, `source_rule_version`.
Idempotency = partial unique index `(audit_run_id, source_issue_fingerprint)
WHERE source_issue_fingerprint IS NOT NULL` — republishing the same job converges
(no duplicates); a **new** audit run may hold a fresh copy of the same logical
issue (a new point in time). The composite `CODE::fingerprint` correctly
separates different codes that share a page-URL fingerprint. Manual issues have a
NULL fingerprint → excluded from the index and **never** touched (the upsert
`DO UPDATE ... WHERE source='crawler'`).

## 8. Persistence contract (`seo_crawl_publications`)

One authoritative record per `(job_id, audit_run_id, publication_version)`
(UNIQUE): workspace/website ids, `source_ruleset_version`, `status`
(`running|published|failed`), `pages_eligible/pages_published`,
`issues_eligible/issues_published`, `crawl_partial`, timestamps, customer-safe
`error_code`. RLS: `SELECT` for workspace member + global admin; **no customer
write policy** (writes only via the service-role RPC). Indexes on run + website.

## 9. Publishing RPC (`seo_crawl_worker_publish_results`)

`(p_job_id, p_worker_id, p_lease_token, p_publication_version=1) → jsonb`.
Service-role only (`PUBLIC`/`anon`/`authenticated` revoked). One transaction:
1. lock job `FOR UPDATE`; require status `claimed|running` (pre-terminal); assert
   lease ownership (`_seo_crawl_assert_owner` — the lease token is the ownership
   secret, consistent with all Phase 16D RPCs).
2. no `audit_run_id` → return `skipped_no_association` (generic-crawl path).
3. load + lock the run; require same workspace+website; publishable while
   `running` (or `completed` only for an idempotent replay of this job+version;
   any other state refused).
4. refuse if any crawler issue code is unmapped (no silent drops).
5. `pages_eligible=0` → mark publication `failed` + run `failed`; return
   `no_results` (publish nothing).
6. upsert Page Inventory (crawler-owned fields; stale + non-crawler guards).
7. upsert Audit Issues (mapped; page/site; provenance; idempotent).
8. update the run → `completed`, `completed_at`, `issue_count` (all issues); **no
   score change**.
9. finalize publication evidence → `published` with counts.
Atomicity is the single transaction: any raise rolls back **all** product writes
(verified). Worker sends no ids/status/counts.

## 10. Worker integration

Pipeline: claim → discovery → extraction → issue detection → persist
crawler-domain snapshots/issues → **cancellation/lease re-check** → **publish**
(`publishing/publisher.ts` → `gateway.publishResults`) → terminal via the existing
Phase 16D lifecycle RPCs. Publishing runs **before** completion; a publish DB
failure is an execution failure/retry — **never** an SEO issue. The coordinator:
treats idempotent replay as success; maps `lease lost/reassigned`→`LeaseLostError`
(no terminal write), cancellation-status→`CancellationRequestedError`,
deterministic contract violations (mismatch/unmapped/wrong-state)→non-retryable,
transient DB errors→retryable; on `no_results` the crawl fails honestly (the run
was already marked failed in-transaction). No direct product-table writes; no
mapping logic duplicated in the worker.

## 11. Outcome semantics

Crawl job terminal states are unchanged (Phase 16D). **Audit run** (existing
statuses `not_started|running|completed|failed` only — **no** `partially_completed`):
usable results → `completed` (SEO issues present do not fail the run); no usable
output / permanent publish failure → `failed`; cancelled → not published, run
untouched. A **partial crawl** with usable pages publishes and the run is
`completed` (least-misleading valid status); the true partial detail (eligible vs
published counts + `crawl_partial`) is preserved in publication evidence — a
documented limitation of the existing audit contract, not an invented status.

## 12. RLS & permissions

Publications: member/global-admin `SELECT`; no customer write. Page Inventory &
Audit Issues RLS unchanged (member read incl. client; owner/admin/team_member +
global-admin direct write; service role bypasses for publishing). Customers
cannot spoof crawler provenance (writes go through the RPC; direct
`INSERT/UPDATE` still governed by existing policies), cannot invoke the worker
publish RPC (grant denied), cannot read cross-workspace rows. Site issues follow
workspace isolation. No policy weakened.

## 13. Verification evidence

- Worker `tsc` clean; **worker unit tests 47/47** (15 new publishing tests);
  `npm audit` **0 vulnerabilities**. Frontend `tsc` + `build` clean.
- **DB verification `seo_phase16g_publishing_verification.sql` = ALL PASS**
  (structure/grants/mapping=29; association incl. cross-workspace + terminal-job
  denial + no-latest-guess; publish authz incl. stale-lease + cancelled + wrong
  state; Page-Inventory mapped fields + idempotent replay + newer-vs-older stale
  protection + manual/user-owned preservation + seed isolation + no
  Page-Performance write; Audit-Issue mapping/severity/scope/provenance +
  idempotent replay + manual preservation + sibling-run untouched + no
  Recommendation write + run completed/count/score; transactional rollback of a
  mid-publish failure; RLS member/customer/non-member; self-cleaning).
- **Regression:** Phase 16C / 16D / 16E / 16F verifications all still **ALL PASS**.
- **End-to-end worker integration** (fixture transport, real service-role
  one-shot, key `[REDACTED]` in logs): associated job → discovery → extraction →
  **published 3 Page-Inventory rows + 8 Audit Issues (7 page + 1 site
  `DUPLICATE_TITLE`)**, audit run `completed` (issue_count 8, score still 0),
  publication `published` (3/8), crawl job `completed`; **0 recommendations**, **0
  Page-Performance rows**; seed Page-Inventory/Audit unchanged (7/7); disposable
  fixtures self-cleaned (0 residual).
- **Browser/read regression:** not executed as a live customer login — the app
  defaults to **mock** data mode (real TEST reads need non-default
  `VITE_SEO_DATA_MODE=supabase`), the Page-Inventory surface is the **locked**
  Page Performance page, and no TEST-user password is available here. Render
  compatibility is instead guaranteed structurally: **no frontend page/service
  changed**; the Audit + Page-Inventory read services use `select("*")` and map
  explicit fields, so the additive nullable columns cannot alter existing shapes;
  and the E2E confirmed publishing populates exactly the existing customer-facing
  columns the services already read.

## 14. Data integrity

Manual/seed rows preserved (source guard + user-owned fields never written; no
deletes). Stale jobs cannot overwrite newer facts (DB-level ordering). Missing
pages never marked removed. Historical audit runs never mutated by a newer crawl;
sibling runs untouched. No score computed. `seo_recommendations` never written.

## 15. Backward compatibility

Additive only. Preserved: `seo_run_audit`, `seo_crawl_request`, Phase 16C
request/cancel/claim, Phase 16D lifecycle, Phase 16E discovery, Phase 16F
extraction/issue contracts + all their verifications; existing Audit /
Page-Inventory records, service return shapes, frontend types/routes, roles/RLS,
auth + mock mode; locked Page Performance + Stage 6. No field/column/status
renamed or removed; no constraint dropped; no applied migration edited (the new
provenance columns are nullable with safe defaults for existing rows).

## 16. Known limitations

No JavaScript rendering; no authenticated-site crawling; **no recommendations**;
no customer crawl-request/status/freshness/retry UI; no customer-facing result
UI; audit run cannot express `partially_completed` (partial detail lives in
publication evidence); no audit scoring; page-removal/stale-page semantics
deferred; no live public-domain fixture test; no production deployment; ownership
is enforced by the lease token (worker id is informational, consistent with all
Phase 16D RPCs).

## 17. Files changed

- **Migration:** `supabase/migrations/20260714120029_seo_phase16g_publishing.sql`.
- **Worker:** `crawler-worker/src/publishing/publisher.ts` (new);
  `crawler-worker/src/jobGateway.ts` (+`publishResults`);
  `crawler-worker/src/discovery/discoveryProcessor.ts` (publish step);
  `crawler-worker/test/publishing.test.ts` (new).
- **TEST SQL:** `supabase/test/seo_phase16g_publishing_verification.sql`,
  `supabase/test/seo_phase16g_rollback_TEST_ONLY.sql`.
- **Registry:** `src/services/supabase/supabaseTypes.ts` (additive constants).
- **Docs:** this file + updates to the plan, 1A/1C/1D docs, ADR, status, wiring
  plan, documentation index.
- **No locked file changed.**

## 18. Rollback

- **Worker:** revert the publish step in `discoveryProcessor.ts`, the
  `publishResults` gateway method, and delete `publishing/publisher.ts` +
  `test/publishing.test.ts` (restores the Phase 1D crawler-domain-only completion
  path; discovery/extraction/issues preserved).
- **Database:** `supabase/test/seo_phase16g_rollback_TEST_ONLY.sql` — drop the
  publish RPC → orchestration RPC → `seo_crawl_publications` →
  `seo_crawl_issue_audit_map` → the additive audit/inventory provenance columns +
  the `audit_run_id` column (after confirming no dependency). Preserves Phase
  16C–16F objects. **Do not execute unless instructed.**
- **Product data:** delete only Phase 1E-tagged published TEST rows; never seed/
  manual data; production untouched.
- **Docs/registry:** revert Phase 1E references + constants.

## 19. Phase boundary

Phase 1E ends with deterministic crawler findings **published** into the existing
Audit + Page-Inventory contracts (readable through their existing services), with
provenance, idempotency and stale protection. **Not** in 1E: recommendations,
customer crawl UI, production crawling.

**Update — Phase 16H / Crawler 1F (2026-07-14): the customer crawl UI is now
implemented + automated-verified (operator acceptance pending).** The published
Audit + Page-Inventory results are surfaced through their **existing** services
from a new crawl workflow on `/seo/audit` (request via `seo_crawl_request_audit`
returning both ids; Supabase-only status polling; cancel via `seo_crawl_cancel`;
freshness). No DB change; no recommendations; worker not deployed. See
`PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`. Next: **`Production crawler
deployment, ownership verification and usage-limit enforcement`** — not started.
