# Crawler Phase 1C — URL Safety, Robots, Sitemap & Page Discovery (Phase 16E)

**Status: Implemented + TEST-verified.** A secure, budgeted page-discovery engine
that validates the authorized origin, blocks SSRF/private-network access
(including at connection time — DNS-rebinding-safe), interprets robots.txt,
discovers + parses sitemaps (XXE-safe), fetches permitted HTML for link
discovery, normalizes/dedupes URLs, respects page/depth/time/size budgets, and
persists safe discovery metadata via worker-only RPCs. **It produces NO
customer-facing SEO findings and writes NOTHING to Page Inventory / Audit Issues
/ Recommendations / locked tables.** Not deployed; crawler unavailable to
customers; production untouched. **Date:** 2026-07-14.

## Scope & exclusions

In: origin validation, SSRF + DNS-rebinding protection, robots (RFC 9309),
sitemap (urlset + index, gzip-bounded), HTML `<a>` link discovery, URL
normalization, bounded BFS + budgets, discovery persistence, progress via
lifecycle RPCs. **Out (deferred):** technical-SEO issue detection, title/meta/
heading/content scoring, canonical/structured-data/duplicate analysis, JS
rendering / headless browser, auth-protected crawling, non-GET methods, cookies,
customer UI, writes to page-inventory/audit/recommendations/locked tables,
scheduling, GSC/GA4/LLM, production deployment.

## URL & network security

- **Normalization** (`urlSafety.ts`, one canonical function used by start URL,
  redirects, robots-sitemap directives, sitemap URLs and HTML links): http/https
  only; reject userinfo, non-default ports, control chars, `>2048` chars;
  lowercase scheme+host (WHATWG/IDNA); dot-segment resolution; **fragment
  removed**; query preserved (distinct pages); non-crawlable schemes
  (mailto/tel/javascript/data/…) rejected.
- **IP classifier** (`ipSafety.ts`): treats an address as UNSAFE unless normal
  public. Blocks IPv4 loopback/private/link-local/CGNAT/multicast/reserved/
  TEST-NETs/0.0.0.0-8; IPv6 ::1/::/ULA fc00::7/link-local fe80::10/multicast/
  doc; and **IPv4-mapped + NAT64 IPv6** (re-checks the embedded v4). Unparseable
  ⇒ unsafe.
- **Allowed origin** (from the persisted website record, never a caller value):
  exact host, http(s), default port. Conservative — **apex ≠ www**, no
  subdomain widening, no cross-site, `<base>` cannot widen the origin.

## SSRF & DNS-rebinding controls

All network access goes through the single `SafeHttpTransport` (`safeHttpTransport.ts`);
no module calls a generic HTTP client. **Connection-time DNS validation:** a
custom `lookup` resolves ALL addresses, rejects the whole target if ANY is unsafe
(no "one public one private" bypass), and pins a single validated address for the
socket — so the address connected to is the address validated (no check-then-
connect rebinding window). TLS hostname verification stays **enabled**
(`servername` = hostname; never `rejectUnauthorized:false`). Each **redirect** hop
re-validates the URL and re-runs the safe lookup independently. The URL passes the
gate at acceptance, before DNS, after DNS, before connect, at every redirect, and
before processing sitemap/HTML-discovered URLs.

## Safe HTTP client

Centralized enforcement: GET only, no body; no cookies; no credential/header
forwarding; fixed identifiable user-agent (`DigibilitySEO-Crawler/0.1`, matching
robots evaluation — does not impersonate Googlebot); connection/response/overall
timeouts; **bounded compressed + decompressed** size (`zlib` `maxOutputLength`);
MIME allowlist per purpose; abort signal; secret-safe errors; never stores full
bodies. Response bodies are never logged or persisted.

## Robots.txt (RFC 9309)

`robots.ts`: user-agent group selection (most-specific token match, `*`
fallback), `Allow`/`Disallow`, **longest-match wins / equal ⇒ Allow wins**, `*`
+ `$` patterns, comments/whitespace, empty-rule handling, `Sitemap:` directive
discovery. Missing/4xx robots ⇒ allow-all (standard); errors ⇒ conservative
allow-all, recorded. Size-bounded fetch. `Crawl-delay` treated only as extra
politeness and never lowers the configured minimum delay (documented as an
extension). Robots is a crawl instruction, **not** authorization.

## Sitemap discovery

`sitemap.ts` (fast-xml-parser, `processEntities:false` + explicit DOCTYPE/ENTITY
rejection ⇒ **no XXE**): urlset + sitemapindex only; gzip bounded; URL-count,
nested-index depth, and total-sitemap caps; cycle detection (seen-set);
same-origin revalidation of every URL; dedupe; `lastmod` treated as untrusted
metadata. Sources: robots `Sitemap:` directives + conservative `/sitemap.xml`. A
malformed sitemap yields a safe recorded failure, never a crash.

## HTML page discovery

`htmlLinks.ts` (node-html-parser — no JS/rendering/forms): extracts `<a href>`
navigational links only; honours a `<base>` **only if same-origin** (never
widens); drops fragments; skips mailto/tel/javascript/data/etc.; resolves
relatives; enforces allowed origin + robots; normalizes + dedupes; bounded. No
HTML stored; no SEO analysis.

## URL normalization

Single canonical function (above) used everywhere for crawl identity + DB
uniqueness. Query preserved (no marketing-param stripping in this phase);
distinct query strings = distinct pages; no unsafe collapsing.

## Queue & budgets

`discovery.ts`: deterministic bounded BFS. Seed = start URL + sitemap URLs (depth
0); HTML links enqueued at depth+1. Budgets from the **job's snapshotted config**
(`budgets.ts`): max_pages, max_depth, crawl_timeout, per_host_delay (sequential,
single-origin), plus fixed caps (max_redirects 5, max_sitemaps 50, sitemap depth
5, urls/sitemap 5000, request timeout 15s). Cancellation + heartbeat checkpoints
each iteration; batched page persistence. Budgets are never silently exceeded.

## Persistence schema (additive; migration `20260714120027`)

- **`seo_crawl_discovered_pages`** (UNIQUE `(job_id, normalized_url)`): normalized/
  discovered/final URL, source, parent, sitemap, depth, queue_order,
  robots_decision, fetch_status, http_status, content_type, response_bytes,
  redirect_count, sitemap_lastmod, **customer-safe error_code only**. Indexes:
  `(job_id, queue_order)`, `(job_id, fetch_status)`, `(website_id, created_at)`.
- **`seo_crawl_sitemaps`** (UNIQUE `(job_id, sitemap_url)`): type, fetch_status,
  urls_discovered, parent, depth, error_code.
- Additive `seo_crawl_jobs.discovery_stats jsonb` for the progress snapshot.
- **No full HTML / robots / sitemap XML / headers / cookies / DNS internals /
  raw exceptions are stored.**

## RLS & worker permissions

Discovery tables: SELECT for `is_seo_workspace_member(workspace_id) OR
seo_is_global_admin()` (own-workspace, customer-safe fields); **no customer
INSERT/UPDATE/DELETE** (verified). Writes only via two **service-role-only**
SECURITY DEFINER RPCs — `seo_crawl_worker_record_discovery` (bulk upsert; validates
the Phase 16D lease_token, requires running/claimed, derives workspace/website
server-side) and `seo_crawl_worker_update_discovery_progress` (bounded; never
touches status/ownership). Both REVOKE PUBLIC/anon/authenticated + GRANT
service_role (verified). Chose guarded RPCs (not raw service-role inserts) so
ownership + integrity are enforced in one place.

## Job outcome semantics

`completed` (queue drained within budget, no unresolved failures);
`partially_completed` (budget/time reached with results, or non-fatal sitemap/
page failures with useful output); `failed` (invalid/unsafe origin, or start
unreachable with no useful result); `retry` (transient); `cancelled` (worker acks
a persisted cancellation). Customer errors are safe; internal detail stays in the
attempt record + logs.

## Packages added

`fast-xml-parser@^5` (safe XML parsing; **0 npm advisories**; the earlier
moderate advisory was in its unused XMLBuilder) and `node-html-parser@^6`
(lightweight link extraction, no browser). Both focused, maintained,
lock-pinned. No crawling framework, no browser dependency.

## Tests

- **Worker unit tests: 22/22 pass** (Phase 1B 10 + discovery 12): IP/SSRF
  classification, URL normalization/rules, allowed-origin, robots precedence/
  wildcards/`$`/agent/sitemaps, sitemap urlset/index/**DTD rejection**/malformed,
  HTML same-origin/scheme-skip/unsafe-base, and engine Scenarios **A** (sitemap+
  HTML success, no cross-origin), **B** (robots block), **C** (fetch error
  recorded not crashed), **E** (cancellation), **F** (page budget).
- **DB verification** `seo_phase16e_crawl_discovery_verification.sql` — **ALL
  PASS** (structure/grants, worker-only record + progress, lease-token mismatch
  denied, customer direct-write denied, member read + non-member isolation,
  upsert dedupe; idempotent, self-cleaning).
- **Worker integration** (real one-shot, TEST-only fixture transport, service-role
  key never printed): dry-run no claim; one-shot **completed** — 3 pages fetched
  (`/`,`/a`,`/b`), **1 robots-blocked** (`/secret`), **0 cross-origin** leak,
  1 sitemap parsed; **Page-Inventory + Audit counts unchanged (7/7)**; 0 secret
  in logs.
- **Regression:** worker `tsc`; frontend `tsc`/`build`; **16C + 16D + 16E DB
  verifications all ALL PASS**.

## Security-review evidence

`rejectUnauthorized` never set false (comment only); `node:http(s)` used **only**
inside `safeHttpTransport`; XXE disabled (`processEntities:false` + DOCTYPE
reject); fixture transport gated to `CRAWLER_ENV=test`; no service-role key/
credential in `src` (a fake JWT literal exists only in a redaction *test*); no
worker import in the frontend; no proxy inheritance; no raw body logging; no
shell tracing.

## Known limitations / real-public-network test status

- **Real-public-network crawl: NOT live-tested** (no operator-controlled public
  fixture domain available). The security + discovery logic is covered
  deterministically (unit + fixture-transport integration); the real
  `SafeHttpTransport` network path is exercised only via its SSRF/URL unit-tested
  primitives, not a live outbound fetch. Documented honestly; SSRF rules were not
  weakened to enable tests, and localhost/private targets remain blocked.
- HTML link discovery is intentionally narrow (`<a href>` only). `Crawl-delay`
  is a politeness extension. Non-default ports unsupported (MVP).
- **No technical SEO analysis; crawler not available to customers.**

## Backward compatibility

Additive only. Phase 16C/16D RPC names + behaviour, crawl-job records, status
values, role matrix, customer RLS, route protection, frontend services/types,
mock mode, and locked Page Performance + Stage 6 modules are all preserved
(16C/16D verifications still ALL PASS; frontend `tsc`/`build` clean). No existing
field/function renamed or removed; no locked read table written.

## Files changed

- **Worker:** new `src/discovery/{ipSafety,urlSafety,transport,safeHttpTransport,
  robots,sitemap,htmlLinks,budgets,discovery,fixtureTransport,discoveryProcessor}.ts`;
  edited `config.ts` (fixture flag), `jobGateway.ts` (record/progress/partial),
  `worker.ts` (use DiscoveryProcessor + partial), `package.json`/lock (2 deps);
  new `test/discovery.test.ts`.
- **Migration:** `supabase/migrations/20260714120027_seo_phase16e_crawl_discovery.sql`.
- **TEST SQL:** `seo_phase16e_crawl_discovery_verification.sql`,
  `seo_phase16e_rollback_TEST_ONLY.sql`.
- **Registry:** `src/services/supabase/supabaseTypes.ts` (additive constants).
- **Docs:** this file + the crawler roadmap/status docs.

## Rollback

- **Worker:** revert the `src/discovery/*` modules + the `config`/`jobGateway`/
  `worker` edits (restoring the Phase 1B skeleton processor path), revert the 2
  package additions.
- **Database:** `seo_phase16e_rollback_TEST_ONLY.sql` (drop discovery RPCs → drop
  discovery tables → drop `discovery_stats`; preserves 16C/16D) — do not execute
  unless instructed.
- **Docs/registry:** revert Phase 1C references + constants.
No Page-Inventory/Audit/Stage-6/Page-Performance data needs rollback.

## Phase 1D boundary

**Update — Phase 16F / Crawler 1D (2026-07-14): extraction + issue detection are
now implemented + TEST-verified** (`crawler-worker/src/extraction/*`, migration
`20260714120028`) — see `CRAWLER_PHASE_1D_EXTRACTION_AND_ISSUE_DETECTION.md`. The
discovery engine now hands its bounded HTML body to an extraction layer via an
`onHtml` hook (no second fetch); the transport gained charset decoding +
allowlisted `X-Robots-Tag`.

**Update — Phase 16G / Crawler 1E (2026-07-14): publishing is now implemented.**
Phase 1D consumes the already-fetched bounded HTML (no second fetch is
introduced) and Phase 1E additively publishes the resulting snapshots/issues into
`seo_page_inventory` + `seo_audit_issues` via a service-role-only transactional
RPC (migration `20260714120029`). Discovery's security contract is **unchanged**;
extraction + issue persistence + publishing are all additive; the crawler remains
not customer-available. See `CRAWLER_PHASE_1E_PAGE_INVENTORY_AUDIT_PUBLISHING.md`.

_Original next-milestone note:_ page extraction, normalization and basic technical SEO issue detection
— which will read discovered pages, extract on-page signals, and (later)
integrate with Audit/Page Inventory behind locked-scope regression. Not started.
