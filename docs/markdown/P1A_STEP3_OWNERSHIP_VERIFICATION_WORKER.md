# P1a Step 3 — Isolated DNS-TXT ownership-verification worker module (record)

**Status:** `IMPLEMENTED + TEST-VERIFIED (Digi_SEO_Test) — code-only additive extension of the LOCKED crawler-worker; production untouched` (2026-07-16).
**Scope:** Step 3 — a standalone DNS-TXT verification runner inside the
existing crawler-worker runtime host. This record covers Step 3 only; Frontend
Steps 4–5, Step 6 sign-off, and this worker's own real-binary acceptance were
completed in later steps. **P1a is now COMPLETE and MODULE-LOCKED** (2026-07-19 —
see the 2026-07-19 addendum below, `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`,
and `MODULE_LOCKS.md`). P1b is the next implementation stage (not started).
**No migration, no schema, no new RPC** (reuses the Step 2B RPCs). Approved as a
narrowly-scoped additive extension inside `crawler-worker/**` (see the dated
notes in `MODULE_LOCKS.md`).

**Builds on:** `…120033` Step 2B RPCs (`seo_ownership_verification_claim` /
`record_result`).

---

## 1. What was delivered (code-only, additive)
**New files (isolated module):**
- `crawler-worker/src/verification/dns.ts` — injectable `DnsTxtResolver`
  (`NodeDnsTxtResolver` with bounded timeout + `FixtureDnsTxtResolver`, test-env
  only), exact multi-string/multi-record TXT match (`txtRecordsMatch`),
  deterministic `classifyDnsError`, and the customer-safe failure map
  (`DNS_FAILURES`). DNS only — **no HTTP, no SSRF surface**.
- `crawler-worker/src/verification/verificationGateway.ts` — reaches Supabase
  ONLY via the Step 2B RPCs (`claim` + `recordResult`); never reads/writes the
  `seo_ownership_*` tables directly; a stale/mismatched claim raises
  `VerificationResultRejected` (safe stop).
- `crawler-worker/src/verification/runner.ts` — `runVerificationOnce`: claim →
  resolve → exact-match → persist `verified`|`failed`; no auto-retry/scheduling;
  cooperative shutdown; **imports nothing from the crawl processor/worker/job
  gateway**.
- `crawler-worker/src/modes.ts` — `Mode` + `parseMode` extracted from `index.ts`
  (adds the `verify-once` mode; crawl modes unchanged), so mode parsing is unit-
  testable.
- `crawler-worker/test/ownershipVerification.test.ts` — 20+ deterministic tests
  (injected fake resolver + fake Supabase; no public DNS).

**Minimal additive edits (locked entry/config — approved):**
- `crawler-worker/src/index.ts` — imports `parseMode` from `modes.ts`; adds a
  `verify-once` branch **before** any crawl `JobGateway`/health-check/stale-
  recovery is constructed, so verification never touches the crawl control plane.
  Crawl `dry-run`/`one-shot`/`poll` paths byte-for-byte unchanged.
- `crawler-worker/src/config.ts` — 2 **optional** additive fields
  (`verificationLeaseSeconds?` default 120 via env `CRAWLER_VERIFICATION_LEASE_SECONDS`;
  `verificationFixtureDnsPath?` honoured only in a test env). No existing field
  or default changed (kept optional so existing crawler `WorkerConfig` literals
  and tests remain valid).

## 2. DNS verification contract (as implemented)
- **Lookup:** DNS TXT only; uses the exact `dns_txt_name` returned by the claim
  RPC (`_digibility-site-verification.<host>`) — never reconstructed locally;
  bounded 5 s timeout; multi-string chunks flattened (joined); multiple records
  supported.
- **Match:** exact, case-sensitive equality of a flattened record to the expected
  challenge value — no substring/case-normalized/cross-record reconstruction.
- **Success → `verified`:** via the Step 2B result RPC; challenge token preserved;
  no unnecessary internal diagnostic; logs only safe identifiers + outcome.
- **Failure → `failed`:** deterministic mapping to a customer-safe reason with an
  internal code/detail stored ONLY on the admin-only claim row (via Step 2B):
  not-found/NXDOMAIN → `dns_not_found`; records-but-no-match → `dns_mismatch`;
  timeout → `dns_timeout`; temporary resolver → `dns_temporary`; malformed →
  `dns_malformed`; unexpected → `internal_error`. **No auto-retry** (the customer
  re-triggers `recheck`).
- **Claim/result:** claim + result ONLY through the Step 2B RPCs; Step 2B lease/
  claim contract preserved; stale/mismatched claim → safe stop; duplicate result
  idempotent (server-side); no work → clean no-work exit; one item per run.

## 3. Independence from the crawler (proven)
The verification module imports nothing from `processor.ts`/`worker.ts`/
`jobGateway.ts` (unit test #16 scans import lines); `verify-once` is handled
before the crawl `JobGateway` is built and never calls a crawl RPC, the crawl
health check, stale recovery, or the processor; it reuses only the service-role
client, the redaction logger, config validation, and graceful-shutdown patterns.
No crawler job/attempt/event/lease/status is read or written.

## 4. Security & logging
No service-role key in the module or logs (reuses the existing service-role
client; key only from server-side env); the challenge token, lease token, and
raw TXT response are NEVER logged (proven by executed tests #9/#10 that capture
stdout/stderr); structured logs carry only verificationId/websiteId/outcome/
reasonCode; graceful shutdown abandons a claim (lease expiry recovers it) rather
than writing a false state; DNS-only (no HTTP → no new SSRF surface).

## 5. Verification evidence (executed 2026-07-16)
| Command | Result |
|---|---|
| Worker `tsc --noEmit -p tsconfig.json` | **PASS** (clean) |
| Full worker test suite (`npm test`) | **PASS — 74 tests, 74 pass, 0 fail** (47 pre-existing crawler + 27 new ownership-verification) |
| Step 2B / 2A / 1 SQL verification | **ALL PASS** (self-cleaning; 0 residual) |
| Standalone Phase 16C/16D/16E/16F/16G/16H | **ALL PASS** (each self-cleaning) |
| Root `tsc --noEmit -p tsconfig.app.json` | **PASS** (clean) |
| Root `npm run build` | **PASS** |
| Security sweep (grep) | **PASS** — no service-role key / raw token in logs; no direct ownership-table write; no crawl-processor import; only `seo_ownership_verification_claim`/`record_result` RPCs called; no HTTP |

**TEST integration proof** (`supabase/test/seo_p1a_step3_worker_dns_verification_integration.sql`,
executed on Digi_SEO_Test): **ALL PASS** — using the **real Step 2B claim/result
RPCs** with a deterministic (script-simulated) resolver decision (match→verified,
not-found→failed): pending claimed; verified + failed persisted; audit events
written; challenge token unchanged; internal diagnostics stored on the admin-only
claim row and **not** customer-readable; **no** crawl-job/attempt/event, audit-
issue, Page-Inventory, Page-Performance, recommendation, or Stage-6 row changed;
disposable fixtures removed (0 residual). Idempotent + self-cleaning.

**Known limitation at original authoring (2026-07-16), now RESOLVED (2026-07-19):**
at the time this record was written, the Node worker **binary** had not been run
against `Digi_SEO_Test` because no `SUPABASE_SERVICE_ROLE_KEY` was present in that
environment. The worker↔RPC wiring (runner + gateway) was instead proven by an
executed Node integration test with a fake Supabase client (asserts only the two
ownership RPCs are called, in order), and the RPC↔DB behaviour + all
"no-other-module-change" assertions were proven by the executed integration SQL
above against the real Step 2B RPCs. Live public-DNS resolution was intentionally
not exercised in those automated tests (injected/fixture resolver only). **The real
worker binary has since been run successfully — see the 2026-07-19 addendum below.**

## 6. Rollback (code-only; no DB rollback)
Delete `crawler-worker/src/verification/**`, `crawler-worker/src/modes.ts`, and
`crawler-worker/test/ownershipVerification.test.ts`; revert the additive
`index.ts` (restore its local `parseMode`, remove the `verify-once` branch) and
the 2 additive `config.ts` fields. No migration/RPC/schema was created, so **no
database rollback is required**; Step 1/2A/2B objects remain; existing crawler
worker behaviour is intact after rollback.

## 7. Next step
**P1a Step 4 — frontend ownership-verification service, types, hooks, and mock
adapter** is now **✅ done + type/build-verified** (frontend-only; no DB change) —
see `P1A_STEP4_OWNERSHIP_VERIFICATION_FRONTEND_SERVICE.md`. The **exact next task
is P1a Step 5 — Websites/onboarding ownership-verification UI.** Step 6 (P1a
sign-off) and P1b remain excluded.

**Addendum (2026-07-18):** this Step 3 TEST integration SQL was re-run on TEST
(as part of a post-Step-6 regression checkpoint) and returned **ALL PASS** again —
see `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §10 (2026-07-18 entry) for the
full evidence. No file in this record changed.

**Addendum (2026-07-19) — real worker binary COMPLETE, P1a MODULE-LOCKED:** the
`verify-once` mode documented in this record was run as the **real Node binary**
(`npm start -- --mode=verify-once`) against `Digi_SEO_Test`, closing the known
limitation noted above. Real service-role client, real
`seo_ownership_verification_claim`/`record_result` RPCs, and a real Node DNS TXT
lookup (not fixture) all executed end-to-end; the legitimate business outcome was
a customer-safe `failed`/`dns_not_found` (no TXT record present) — not a defect.
No file in this record changed. Full evidence:
`P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §4 + §10 (2026-07-19 entry). This
was the last outstanding P1a acceptance item — **P1a is now formally locked** in
`MODULE_LOCKS.md`, which now governs any future change to this file.
