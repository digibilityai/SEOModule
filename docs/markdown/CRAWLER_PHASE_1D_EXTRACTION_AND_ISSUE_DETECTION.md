# Crawler Phase 1D — Page Extraction & Basic Issue Detection (Phase 16F)

**Status: Implemented + TEST-verified.** A deterministic extraction +
issue-detection pipeline that extracts bounded technical facts from the HTML
already fetched during Phase 1C (no second fetch), normalizes them, persists
customer-safe page snapshots, detects a conservative set of deterministic
technical-SEO issues + site-level duplicates, and stores stable issue codes with
bounded evidence. **It writes NOTHING to Page Inventory / Audit Issues /
Recommendations / locked tables (that is Phase 1E), produces no SEO score / AI
judgment, and the crawler remains unavailable to customers.** Not deployed;
production untouched. **Date:** 2026-07-14.

## Scope & exclusions

In: bounded HTML fact extraction, charset decoding, text normalization,
canonical + robots-directive classification, deterministic page-issue rules,
site-level duplicate (title/description/content-hash) detection, and worker-only
persistence. **Out (deferred):** publishing into `seo_page_inventory` /
`seo_audit_issues` / `seo_recommendations` (Phase 1E), audit/health scoring, AI
explanations, Page Performance / keyword / GSC / GA4 / AI-visibility ingestion,
JS rendering / headless / screenshots, auth/cookie crawling, content-quality /
intent / E-E-A-T / backlink / CWV analysis, fuzzy similarity, customer UI,
production deployment.

## Extraction architecture (no second fetch)

The Phase 1C `DiscoveryEngine` now hands its already-fetched, bounded HTML body
to an `onHtml(ctx, html)` hook (the engine itself does no analysis). The
`DiscoveryProcessor` runs `pageExtractor.extractPageFacts(html, …)` on that body,
collects facts in memory, and **releases the HTML** when the callback returns —
the body is never re-fetched, logged, or persisted. Every outbound request still
flows through `SafeHttpTransport`. Layer ownership: transport/discovery
(retrieval), `pageExtractor` (facts, no DB), `issueDetector` (rules, no
network/lifecycle), gateway/RPCs (persistence), processor (orchestration +
lifecycle RPCs). Phase 1E will own mapping to Audit/Page-Inventory.

## Extracted facts (data-minimized)

Identity/fetch: requested/final URL, http status, redirect count, content-type,
declared charset, decode status, response bytes, discovery source, depth, robots
decision. Document: `<title>` count/text/len, meta-description count/text/len,
`<h1>` count + first text, H1–H6 counts, `<html lang>`, canonical count/raw
(bounded)/resolved/classification, meta-robots + `X-Robots-Tag` (allowlisted
header) → effective index/follow, visible-text word count, **sha-256 content
hash** (of the normalized comparison key), bounded HTML-size metric,
internal/external link counts, image count + images-missing-alt, structured-data
block **count** only. **Never persisted:** full HTML, full text, scripts,
JSON-LD contents, forms, cookies, non-allowlisted headers, PII, or stack traces
(verified: 0 body/html/text columns in the snapshot table).

## Charset handling

`charset.ts` (Node built-in `TextDecoder`, ICU — **no i18n dependency**): HTTP
charset → bounded meta-charset sniff → utf-8 default. An unknown/unsupported
label falls back to utf-8 and is reported honestly as `decodeStatus:
"unsupported"` (never silently treated as valid; surfaces the `DECODE_UNSUPPORTED`
issue). Bounded input; malformed declarations never crash the worker.

## Text normalization

`textNormalize.ts`: strips control/null chars, collapses whitespace, trims,
bounds length with explicit truncation, preserves case + Unicode for display; a
separate lowercased `comparisonKey` is used for duplicate detection only.

## Canonical & indexability

Canonical classified with the same URL-safety primitives (never fetched, never
widens crawl scope): `missing | self | same_origin_other | cross_origin |
invalid | unsafe | multiple`. Robots directives combine `<meta name=robots>` +
allowlisted `X-Robots-Tag` with **restrictive precedence** (`none`/`noindex`
win); original bounded directives + effective index/follow are recorded. robots.txt
crawl permission is kept distinct from page indexing directives.

## Issue-rule registry (`issueRegistry.ts`, RULESET_VERSION 1.0.0)

One versioned registry (no scattered code strings, no AI, no overall score). Each
rule: stable code, title, customer-safe description, category, severity
(`critical|error|warning|info`), scope (`page|site`), impact
(`blocks_indexing|degrades_quality|informational`), future audit-map. **Stable
page codes:** REDIRECT_CHAIN_LONG, EFFECTIVE_NOINDEX, CONFLICTING_ROBOTS,
DECODE_UNSUPPORTED, TITLE_MISSING/EMPTY/MULTIPLE/TOO_SHORT/TOO_LONG,
DESCRIPTION_MISSING/EMPTY/MULTIPLE/TOO_SHORT/TOO_LONG, H1_MISSING/MULTIPLE/EMPTY,
CANONICAL_MISSING/MULTIPLE/INVALID/UNSAFE/CROSS_ORIGIN/NON_SELF,
HTML_LANG_MISSING, LOW_CONTENT, IMAGES_MISSING_ALT. **Site codes:**
DUPLICATE_TITLE, DUPLICATE_DESCRIPTION, DUPLICATE_CONTENT.

**Complete registry (29 stable codes as implemented — 26 page + 3 site;
fingerprint = page URL for page rules, `sha256(code:groupKey)` for site rules;
rule_version = 1.0.0):**

> **Count correction (Phase 16G):** an earlier draft of this doc stated "26
> codes"; that undercounted by omitting the digit-bearing `H1_MISSING`,
> `H1_MULTIPLE`, `H1_EMPTY`. The verified total is **29** (26 page + 3 site); the
> table below and the Phase 1E `seo_crawl_issue_audit_map` both cover all 29.

| Code | Category | Severity | Scope | Detection | Evidence |
|---|---|---|---|---|---|
| REDIRECT_CHAIN_LONG | indexability | warning | page | redirect_count > 3 | redirectCount |
| EFFECTIVE_NOINDEX | indexability | info | page | effective index = false | metaRobots |
| CONFLICTING_ROBOTS | indexability | warning | page | directives contain both index and noindex | metaRobots |
| DECODE_UNSUPPORTED | content | warning | page | decodeStatus = unsupported | declaredCharset |
| TITLE_MISSING | metadata | error | page | titleCount = 0 | — |
| TITLE_EMPTY | metadata | error | page | title present but empty | — |
| TITLE_MULTIPLE | metadata | warning | page | titleCount > 1 | count |
| TITLE_TOO_SHORT | metadata | info | page | titleLen < 15 | length, min |
| TITLE_TOO_LONG | metadata | info | page | titleLen > 60 | length, max |
| DESCRIPTION_MISSING | metadata | warning | page | descriptionCount = 0 | — |
| DESCRIPTION_EMPTY | metadata | warning | page | description present but empty | — |
| DESCRIPTION_MULTIPLE | metadata | warning | page | descriptionCount > 1 | count |
| DESCRIPTION_TOO_SHORT | metadata | info | page | descriptionLen < 50 | length, min |
| DESCRIPTION_TOO_LONG | metadata | info | page | descriptionLen > 160 | length, max |
| H1_MISSING | headings | warning | page | h1Count = 0 | — |
| H1_MULTIPLE | headings | info | page | h1Count > 1 | count |
| H1_EMPTY | headings | warning | page | first H1 empty | — |
| CANONICAL_MISSING | canonical | info | page | no canonical element | — |
| CANONICAL_MULTIPLE | canonical | warning | page | > 1 canonical element | count |
| CANONICAL_INVALID | canonical | warning | page | canonical not a valid URL | raw |
| CANONICAL_UNSAFE | canonical | warning | page | canonical uses unsafe scheme | raw |
| CANONICAL_CROSS_ORIGIN | canonical | info | page | canonical on a different host | resolved |
| CANONICAL_NON_SELF | canonical | info | page | canonical to a different same-origin URL | resolved |
| HTML_LANG_MISSING | content | info | page | `<html lang>` absent | — |
| LOW_CONTENT | content | info | page | indexable and wordCount < 100 | wordCount, min |
| IMAGES_MISSING_ALT | images | info | page | ≥1 image with empty/no alt | missing, total |
| DUPLICATE_TITLE | duplicate | warning | site | ≥2 indexable pages share a normalized title | pageCount, sampleUrls |
| DUPLICATE_DESCRIPTION | duplicate | info | site | ≥2 indexable pages share a normalized description | pageCount, sampleUrls |
| DUPLICATE_CONTENT | duplicate | warning | site | ≥2 indexable pages share a content hash | pageCount, sampleUrls |

**Technical facts** (not issues): the extracted snapshot fields (see §4).
**Informational** (`info`): the guidance/length + canonical-info + lang/low-content/
alt findings. **Warnings** (`warning`): missing description/H1, multiples,
canonical problems, redirect chain, decode + robots conflicts, duplicate
title/content. **Errors** (`error`): TITLE_MISSING, TITLE_EMPTY. No `critical`
code is emitted in 1.0.0 (the vocabulary reserves it). All three duplicate checks
(title/description/content) are implemented + unit-tested; the integration
fixture happened to trigger only DUPLICATE_TITLE.

## Thresholds (guidance, versioned — NOT search-engine laws)

One typed `DEFAULT_THRESHOLDS` (title 15–60, description 50–160, low-content 100
words, redirect chain 3, duplicate-evidence sample 10), snapshotted via
`RULESET_VERSION` on every finding; not caller-controlled in 1D; documented as
display guidance, additive/changeable later (a future version won't silently
reinterpret historical results). These are **not** described as Google rules.

## Duplicate analysis

After extraction, `detectSiteDuplicates` groups **indexable, reliably-decoded,
non-empty** pages by normalized title / normalized description / content hash;
groups of ≥2 emit a site issue with a stable `sha256(code:groupKey)` fingerprint
and bounded sample-URL evidence. Empty values + `noindex` pages excluded; no
cross-job/website/customer comparison; no fuzzy similarity; not called
plagiarism. Idempotent (stable fingerprint → converges on rerun).

## Severity mapping

Crawler-domain severity `critical|error|warning|info` (CHECK-constrained),
mapped deliberately to the future `seo_audit_issues` contract. Informational
facts (e.g. CANONICAL_NON_SELF, H1_MULTIPLE, LOW_CONTENT) stay `info`; genuine
defects (TITLE_MISSING) are `error`; the rest `warning`. Normal optimization
opportunities are not inflated to critical.

## Persistence contract (additive; migration `20260714120028`)

- **`seo_crawl_page_snapshots`** (UNIQUE `(job_id, requested_url)`): technical
  metadata + counts + content hash + extractor_version; indexes on
  `(website_id, extracted_at)`, `(job_id, content_hash)`, `(job_id, title)`.
- **`seo_crawl_issues`** (UNIQUE `(job_id, issue_code, fingerprint)`): code
  (CHECK `^[A-Z][A-Z0-9_]{2,63}$`), category, severity (CHECK), scope (CHECK),
  rule_version, fingerprint, summary, `evidence jsonb` (CHECK object +
  `octet_length ≤ 8192`); CHECK enforces page-scope ⇒ snapshot present /
  site-scope ⇒ null; indexes on `(job_id, severity)`, `page_snapshot_id`,
  `(job_id, issue_code)`.
- Additive `seo_crawl_jobs.extraction_stats jsonb`.

## RLS & worker contracts

Snapshots + issues: SELECT for `is_seo_workspace_member OR seo_is_global_admin`;
**no customer INSERT/UPDATE/DELETE** (verified). Writes only via **service-role-
only** SECURITY DEFINER RPCs `seo_crawl_worker_record_snapshots` (bulk upsert),
`seo_crawl_worker_record_issues` (idempotent; page-scope snapshot must belong to
the job; unknown code / oversized evidence rejected by CHECKs), and
`seo_crawl_worker_update_extraction_progress` (bounded; never touches
status/ownership). All validate the Phase 16D lease_token, derive
workspace/website server-side, avoid dynamic SQL, and REVOKE
PUBLIC/anon/authenticated + GRANT service_role.

## Worker pipeline & outcomes

Claim/start → discovery (fetch) → extract per fetched HTML → persist snapshots
(batched) → detect + persist page issues (idempotent) → site-duplicate detection
→ persist site issues → update extraction progress → terminal via the Phase 16D
lifecycle RPC. Outcomes: **completed** (discovery + extraction produced usable
results; non-fatal issues allowed), **partially_completed** (budget reached or a
subset failed extraction/decoding), **failed** (invalid origin or no usable
result), **retry** (transient execution/persistence only), **cancelled**
(acknowledged). **A detected SEO issue is a crawl result, never a retry/failure.**
Idempotent: snapshot + issue upserts + duplicate fingerprints converge on rerun;
a stale lease token cannot persist (Phase 16D ownership).

## Tests

- **Worker unit tests: 32/32 pass** (Phase 1B 10 + discovery 12 + extraction 10):
  normalization; charset (header/meta/default/unsupported); extraction
  (title/desc/H1–H6/lang/canonical classes/robots precedence/links/images/
  structured-data/word/hash; malformed + empty tolerated; script excluded);
  registry known-codes; page-issue positive+negative + severity/scope/fingerprint;
  redirect/noindex; duplicate title/description/content with empty+noindex
  exclusion + stable idempotent fingerprints.
- **DB verification** `seo_phase16f_...` — **ALL PASS** (structure/grants,
  worker-only snapshot+issue+progress, lease-token mismatch, idempotent upserts,
  unknown-code + oversized-evidence + scope-integrity rejection, member read +
  non-member isolation + customer direct-write denial; self-cleaning).
- **Integration** (real one-shot, TEST-only fixture transport, service-role key
  never printed): completed — 3 snapshots extracted with correct facts; issues
  `DESCRIPTION_MISSING`/`H1_MISSING`/`HTML_LANG_MISSING`/`TITLE_TOO_SHORT`/
  `CANONICAL_MISSING` + site **`DUPLICATE_TITLE`**; **0 body/HTML columns**;
  **Page-Inventory + Audit unchanged (7/7)**; 0 secret in logs.
- **Regression:** worker `tsc`; `npm audit` **0 vulnerabilities**; frontend
  `tsc`/`build`; **16C + 16D + 16E + 16F DB verifications all ALL PASS**.

## Security & privacy review

No full HTML/text persisted (only metadata + hash; 0 body columns); no secrets/
tokens/headers (beyond allowlisted x-robots effective directives)/cookies/stack
traces stored or logged; `node:http(s)` used only in `SafeHttpTransport`; TLS
never disabled; XML entities off; canonicals never fetched; fixture transport
gated to `CRAWLER_ENV=test`; no worker import in the frontend; no writes to
protected existing SEO tables.

## Dependencies

No new dependency (charset via Node's built-in `TextDecoder`; extraction via the
existing `node-html-parser`; sitemap via existing `fast-xml-parser@5`). `npm
audit` = **0 vulnerabilities**.

## Backward compatibility

Additive only. Phase 16C/16D/16E RPCs + behaviour, crawl-job records, status
values, role matrix, customer RLS, route protection, frontend/types, mock mode,
and locked Page Performance + Stage 6 all preserved (all prior verifications
still ALL PASS; frontend clean). No existing field/function renamed; no locked
read table written.

## Known limitations

Charset decoding uses replacement chars for bad bytes (reported). HTML link/fact
extraction is bounded (`node-html-parser`, no JS). Thresholds are guidance
defaults. Client/server-error and robots-blocked-but-discovered facts live in the
discovered-pages table (Phase 1C), not re-derived as issues here. **No
audit/page-inventory publishing; crawler not customer-ready.**

## Files changed

- **Worker:** new `src/discovery/charset.ts`, `src/extraction/{textNormalize,
  pageExtractor,issueRegistry,issueDetector}.ts`; edited `src/discovery/
  {transport,safeHttpTransport,fixtureTransport,discovery,discoveryProcessor}.ts`,
  `src/jobGateway.ts`; new `test/extraction.test.ts`.
- **Migration:** `supabase/migrations/20260714120028_seo_phase16f_crawl_extraction.sql`.
- **TEST SQL:** `seo_phase16f_crawl_extraction_verification.sql`,
  `seo_phase16f_rollback_TEST_ONLY.sql`.
- **Registry:** `src/services/supabase/supabaseTypes.ts` (additive constants).
- **Docs:** this file + the crawler roadmap/status docs.

## Rollback

- **Worker:** revert the extraction + persistence edits (restore the Phase 1C
  discovery-only processor); no package changes to revert.
- **Database:** `seo_phase16f_rollback_TEST_ONLY.sql` (drop extraction RPCs →
  issues table → snapshots table → `extraction_stats`; preserves 16C/16D/16E) —
  do not execute unless instructed.
- **Docs/registry:** revert Phase 1D references + constants. No Page-Inventory/
  Audit/Recommendation/Stage-6/Page-Performance data needs rollback.

## Phase 1E boundary

**Update — Phase 16G / Crawler 1E (2026-07-14): publishing is now implemented +
TEST-verified.** These crawler-domain snapshots/issues are published into the
existing `seo_page_inventory` + `seo_audit_issues` contracts via an explicit
crawl-job→audit-run association and one service-role-only transactional RPC
(migration `20260714120029`) — additive, idempotent, stale-safe, provenance-
preserving; all 29 codes mapped; **no `seo_recommendations` write, no scoring, no
customer UI**; locked Page Performance / Stage 6 untouched. See
`CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`. Next milestone: **Crawler
Phase 1F — authenticated crawl request, status, freshness and published-result
UI**.
