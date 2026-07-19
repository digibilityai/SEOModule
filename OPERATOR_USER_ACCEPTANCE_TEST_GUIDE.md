# Operator User-Acceptance Test Guide — Crawler Customer UI (Phase 16H / Crawler 1F)

This customer-facing phase is **implemented and automated-verified**; final
acceptance requires the manual checklist below. Record outcomes in
`OPERATOR_TEST_RESULTS.md`.

> **Safety:** target only the TEST project `Digi_SEO_Test`
> (ref `snyzotgwwfomgafrsvfm`). Never run against production. Never paste
> secrets or passwords into any file. The crawler worker is **not deployed** —
> a crawl stays honestly `Queued` until you run the one-shot worker command.

---

## 1. Environment startup

### Frontend (Supabase mode)
```bash
cd /Users/amitguptaamit/gitrepo/user_guide/Digibility-SEO-Module
# .env.local must set (do NOT commit real values):
#   VITE_SEO_DATA_MODE=supabase
#   VITE_SUPABASE_URL=https://snyzotgwwfomgafrsvfm.supabase.co
#   VITE_SUPABASE_ANON_KEY=<anon key from Keychain / Supabase dashboard>
npm run dev            # serves http://localhost:8090
```
- **Verify healthy:** the login page loads at `http://localhost:8090/seo/login`.
- **Verify TEST target:** DevTools → Network → any Supabase request host is
  `snyzotgwwfomgafrsvfm.supabase.co` (never a production ref).
- **Verify not production:** confirm the URL above; do not point `.env.local` at
  any other project.

### Mock-mode variant (no login, no Supabase)
```bash
# .env.local: VITE_SEO_DATA_MODE=mock   (or unset — mock is the default)
npm run dev
```
Mock mode shows a clearly labelled **Preview** crawl that writes nothing.

### Worker (controlled TEST scenario only — never in production UI)
Provide the worker environment **without printing secrets** (source, don't echo):
```bash
cd crawler-worker
# Write a scratch env file whose SUPABASE_SERVICE_ROLE_KEY comes from your
# secret store / Keychain (never printed to the terminal), e.g.:
#   SUPABASE_URL=https://snyzotgwwfomgafrsvfm.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY=<service_role key — from Keychain>
#   CRAWLER_WORKER_ID=operator-uat
#   CRAWLER_ENV=test
#   CRAWLER_TEST_JOB_PREFIX=<match the requested job's prefix, see below>
#   CRAWLER_FIXTURE_TRANSPORT=<absolute path to a TEST fixture JSON>
set -a; . /path/to/scratch.env; set +a
npx tsx src/index.ts --mode=one-shot
```
> Customer-requested jobs use an auto-generated idempotency key. For a controlled
> UAT run, the requested job must be tagged with the worker's
> `CRAWLER_TEST_JOB_PREFIX` (the processor refuses non-test jobs). Use the
> fixture-transport JSON so no arbitrary public site is crawled.

### Cleanup (after testing)
```bash
# Remove only disposable UAT crawler fixtures for the TEST website you used;
# never delete seed/manual rows. Example (adjust website_url):
supabase db query --linked "DELETE FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'UAT-16H-%';"
rm -f /path/to/scratch.env      # remove the service-role env file
```

---

## 2. Test accounts (roles only — never passwords)
Use the existing TEST users referenced by the browser-validation harness. Retrieve
credentials from the macOS **Keychain** entries used by prior phase validations
(see `PHASE_16B_CUSTOMER_AUTH_ROUTE_PROTECTION_SIGNOFF.md`). Roles required:
- **Owner** — full crawler request/cancel.
- **Admin** — full crawler request/cancel.
- **Team member** — request + cancel permitted.
- **Client** — read-only (no request, no cancel).

Never place passwords in this guide or in `OPERATOR_TEST_RESULTS.md`.

---

## 3. Scenarios

### Scenario 1 — Owner complete journey
1. Sign in as owner.
2. Select/confirm the TEST website.
3. Open **/seo/audit**.
4. Press **Start crawl** → confirm the crawl confirmation copy → **Confirm crawl**.
5. Confirm the status shows **Queued** immediately (no IDs exposed in the UI).
6. Run the approved worker one-shot command.
7. Observe status progress (Preparing → Crawling → Completed).
8. Confirm **Completed**.
9. Confirm **View audit results** shows the published audit.
10. Confirm **Open Page Inventory** shows published pages.
11. Refresh the browser.
12. Confirm the workflow + results persist.
13. Confirm freshness ("Crawled on…", "Results published…").
14. Confirm **no recommendation** was generated.

### Scenario 2 — Team-member request
- Request permitted; status readable; cancellation permitted per the role matrix.
- Confirm existing campaign role restrictions (Stage 6) are unchanged.

### Scenario 3 — Client
- Results readable (audit + page inventory).
- **Start crawl** absent/disabled (role tooltip on focus/hover).
- **Cancel** unavailable.
- Network tab: **no** `seo_crawl_request_audit` and **no** `seo_crawl_cancel` request issued.
- Existing Stage 6 client restrictions unchanged.

### Scenario 4 — Cancellation
- Start a controlled job.
- Request cancellation while permitted → confirm honest **Cancelling**
  (`cancellation_requested`) when the job is active.
- Run/allow the worker to acknowledge → confirm final **Cancelled**.
- Confirm no false "Completed".

### Scenario 5 — Partial result
- Use a controlled TEST fixture that yields a partial crawl.
- Confirm **Partially completed** status + explanation.
- Confirm usable Audit + Page Inventory results remain visible.
- Confirm absent pages are **not** marked removed.

### Scenario 6 — Failure / retry
- Use a controlled TEST fixture that fails.
- Confirm a customer-safe error message (no stack/secret/worker id/lease token).
- Confirm **Waiting to retry** where applicable.

### Scenario 7 — Refresh & sign-out
- Refresh during an active status → confirm state restores.
- Sign out → confirm prior customer crawl data disappears.
- Sign in as a different role → confirm no cross-user state leak.

---

## 4. Required evidence (per scenario)
Record in `OPERATOR_TEST_RESULTS.md`: Date · Commit · Browser · Role · Route ·
Starting state · Expected result · Actual result · Network result · Database
result · Screenshot filename · PASS/FAIL/BLOCKED · Notes · Retest date/result.
