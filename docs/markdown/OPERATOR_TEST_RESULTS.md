# Operator Test Results — Crawler Customer UI (Phase 16H / Crawler 1F)

**Acceptance state:** `FULLY ACCEPTED ON TEST — PRODUCTION READINESS NOT STARTED` (all 7 operator scenarios PASS; Scenario 7 = PASS accepted with three low-risk administrative evidence notes — tooltip screenshot, hydration-flash recording, timed polling-stop window — observed but not saved as artifacts; documentation-only, no implementation defect, no code change). This acceptance covers the **TEST** project (`Digi_SEO_Test`) only. **Production readiness has not started**; the crawler is not deployed and is not customer-operational.

> **Evidence provenance note.** Scenario 1 and Scenarios 2–5, 7 are **operator browser results** (attested by the operator on the recorded dates). Scenarios 6A/6B/6C are **controlled DB-level executions** performed in-session against `Digi_SEO_Test` with full row evidence. Read-only database correlation supports the browser results where noted; it does not replace them.

Fill one block per scenario from `OPERATOR_USER_ACCEPTANCE_TEST_GUIDE.md`. Never
record passwords. Screenshots go in a local (git-ignored) folder; record only the
filename here.

| Field | Value |
|---|---|
| Tester | Operator using the owner test account |
| Environment | Digi_SEO_Test (ref snyzotgwwfomgafrsvfm) |
| App data mode | supabase |
| Commit | N/A — local working copy has no `.git` metadata |

---

## Scenario 1 — Owner complete journey
- Date: 2026-07-14
- Commit: N/A — local working copy has no `.git` metadata
- Browser: Google Chrome
- Role: owner
- Route: /seo/audit
- Starting state: One queued TEST crawl job for `https://digibility.ai`, job id `63c72384-a86f-4696-9e8b-e428958d4734`; no worker running persistently.
- Expected result: queued → completed; audit + page inventory published; refresh persists; freshness shown; no recommendation
- Actual result: The one-shot TEST worker claimed the exact queued job and completed it. The customer UI showed 3 pages discovered, 3 fetched, 3 extracted, 3 pages published and 3 issues published. Audit results and all three Page Inventory records rendered. No recommendation was created. Navigation and hard-refresh persistence passed after the approved refresh-race bug fix described below.
- Network result (RPCs seen): Browser DevTools RPC capture was not recorded during this run. The customer request succeeded, the exact queued job was claimed by the worker, and Supabase-backed terminal state/results rendered in the UI.
- Database result (job/run/publication): The crawl reached `completed`; the onboarding row for website `fb98d59c-0f7d-4724-9f60-9db385bf2592` remained `completed` at 100%; the website had 3 active published Page Inventory rows; the UI reported 3 published Audit issues.
- Screenshot filename: Operator-chat screenshots captured on 2026-07-14 between 23:03 and 23:35; screenshots were not copied into the repository.
- Result: PASS
- Notes: Initial refresh exposed a reproduced race condition in the locked Page Performance Tracker: the cross-workspace fallback could run before the current website onboarding/page query completed and incorrectly replace the valid website. Explicit human approval was recorded. Only `src/pages/seo/PagePerformancePage.tsx` was changed so fallback evaluation waits for completed onboarding and a completed page fetch. No database, service signature, adapter, mock behaviour or Stage 6 change. `npm run build` passed. Hard refresh then retained all 3 published pages. Separate UX observations remain: legacy “Mock audit” wording, a legacy Run Audit button, and data-source wording on Page Performance.
- Retest date / result: 2026-07-14 / PASS

## Scenario 2 — Team-member request
- Date: 2026-07-14 / Browser: Chrome / Role: team_member / Route: /seo/audit
- Objective: a team_member may request a crawl and cancel it (queued cancellation); Stage 6 role restrictions unchanged.
- Operator result: **PASS** — team_member could Start crawl and cancel a queued crawl through the UI.
- Browser verification: operator-observed (request + queued cancel succeeded; Stage 6 campaign gates unchanged).
- Database correlation (read-only): the crawl-request/cancel RPCs are `authenticated`-executable with an in-function owner/admin/team_member gate (matches contract).
- Status: **PASS**

## Scenario 3 — Client (read-only)
- Date: 2026-07-14 (baseline) + 2026-07-15 (client-isolation confirmation) / Browser: Chrome / Role: client / Route: /seo/audit
- Objective: client can read published Audit + Page Inventory; Start crawl disabled with the role tooltip; no request/cancel RPC issued; Stage 6 client restrictions unchanged.
- Operator result: **PASS after a narrow approved fix** (the Scenario 1 Page Performance refresh-race fix; see Scenario 1 notes) — client saw published results; Start crawl disabled; no crawl RPC issued.
- Browser verification: operator-observed. Client-role UI isolation re-confirmed on 2026-07-15 (client login as workspace-77777777 client `6c7a04e0…`; Start crawl disabled; no internal worker data). See administrative note under Scenario 7 for the tooltip-screenshot artifact.
- Database correlation (read-only): member `6c7a04e0-9985-47c3-aad4-f2f0cc5e092c` = `seo_role='client'` in workspace `77777777…`; RLS grants members SELECT and denies client writes.
- Status: **PASS**

## Scenario 4 — Active cancellation and worker acknowledgement
- Date: 2026-07-14 / Browser: Chrome / Role: owner|admin|team_member / Route: /seo/audit
- Objective: cancelling an active crawl shows `cancellation_requested` and finalizes to `cancelled` after worker acknowledgement; no false completion; linked running audit finalized.
- Operator result: **PASS** — active cancel → Cancelling → Cancelled after the worker acknowledged.
- Browser verification: operator-observed.
- Database correlation (read-only): `seo_crawl_cancel` (claimed/running→`cancellation_requested`; queued/retry_wait→`cancelled`) + `seo_crawl_worker_acknowledge_cancellation`; the queued-cancel path also finalizes the linked running audit to `failed` (confirmed on the Scenario 7 crawl `2e5c10f2…` → linked audit `5e2998ab…` = `failed`).
- Status: **PASS**

## Scenario 5 — Partial result and inventory preservation
- Date: 2026-07-14 / Browser: Chrome / Role: owner / Route: /seo/audit
- Objective: a partially-completed crawl shows "Partially completed", keeps usable Audit + Page Inventory results, and does not mark absent pages as removed.
- Operator result: **PASS** — partial status shown; usable results remained; no page removals.
- Browser verification: operator-observed.
- Database correlation (read-only): job `3aa18a9a-c43a-43e3-ac45-bfbe2e58783e` on digibility.ai = `partially_completed`; the 3 active Page Inventory rows persisted (no removal); publishing is stale-safe and preserves user-owned fields.
- Status: **PASS**

## Scenario 6 — Failure / retry (6A retry_wait · 6B recovery · 6C exhaustion)
- Date: 2026-07-15 / Method: controlled DB-level executions against `Digi_SEO_Test` (real one-shot worker + a temporary, job-scoped, first-attempt-only BEFORE-INSERT trigger to induce a retryable persistence failure; trigger removed after each). No source/migration change; fault removed and verified absent.
- Objective: prove the real retry lifecycle — retryable persistence failure → `RetryableExecutionError` → `seo_crawl_worker_schedule_retry` → `retry_wait`; recovery on retry; and max-attempt exhaustion → terminal `failed` + linked audit `failed`; with customer-safe errors and no damage to prior published results.

- **6A — first retryable failure → retry_wait — PASS.** Job `8137e5b8-d0d7-476f-b09d-8ff3e9f2e585`: attempt 1 `failed/retryable`, one `retry_scheduled` event, `retry_after` = +30s, `error_code='persistence_error'` / `error_message='The crawl results could not be saved.'` (customer-safe), linked audit stayed `running`; 0 publications/snapshots/issues; temporary trigger removed.
- **6B — recovery on attempt 2 → completed + published — PASS.** Same job re-claimed (attempt_count 2) → `completed`; exactly **1** publication; linked audit `completed` (score unchanged 0); user-owned Page Inventory fields preserved (root row updated stale-safe); **no** recommendation/Page-Performance write.
- **6C — max-attempt exhaustion → failed — PASS.** New job `f7e8fe8a-6f33-460e-a565-2d6aaa3ce729`: attempts 1–3 all `failed/retryable`, **2** `retry_scheduled` + **1** terminal `failed` event, `attempt_count=3=max_attempts`, `retry_after` NULL; linked audit `c0c49037…` → `failed`; **0** publications; 3 prior completed audits + 3 Page-Inventory rows preserved; temporary trigger removed.
- Browser verification: not required for 6A–6C (DB-level lifecycle proof); customer-facing labels are code-confirmed (Waiting to retry / Failed).
- Status: **PASS (6A, 6B, 6C)**
- Non-blocking observation (recorded, not fixed): a terminal crawl retains the prior retry `error_code`/`error_message`; the UI shows the error only for `failed` status. Data-cleanliness only.

## Scenario 7 — Refresh, sign-out and user/role isolation
- Date: 2026-07-15 / Browser: Chrome / Roles: owner (User A) + client (User B, `6c7a04e0…`) / Route: /seo/audit
- Objective: active crawl state restores from Supabase after hard refresh; sign-out clears user-scoped data; another role/user cannot see the prior user's cached state; client remains read-only.
- Operator result: **PASS — accepted with administrative evidence notes** — confirmed browser evidence: owner baseline; crawl created via UI; **queued state restored after hard refresh** (from Supabase); **sign-out redirected to `/seo/login` and removed protected content**; **legal UI cancellation → Cancelled**; **cancelled terminal state restored after refresh**; **client login** (client account `seo-client-test@example.com` visibly authenticated, digibility.ai); **client sees published audit** (legitimate shared read); **client Start crawl visibly disabled**; **Cancel crawl absent**; **no internal worker ID/lease token/SQL/stack/secret/attempt detail visible**.
- Database correlation (read-only): the Scenario 7 crawl `2e5c10f2-d09b-488d-882e-4e57b945ba0d` (browser-created `auto-…` key) = `cancelled`; its linked audit `5e2998ab…` correctly finalized `failed`; single-active invariant holds (no duplicate crawl); prior completed audits (3) + Page-Inventory (3) preserved; worker RPCs remain service-role-only (`authenticated`/`anon` denied).
- Status: **PASS (with administrative evidence notes)**
- Administrative notes (documentation only; no code change; no security concern): three low-risk artifacts were observed but not saved — (1) the exact Start-crawl **tooltip screenshot** ("Requires the owner, admin, or team member role."), (2) a **hydration-flash recording** proving no owner-control flash during client hydration, (3) a **timed network window** showing polling stops after terminal. All are supported by the confirmed code paths (`SessionSync.queryClient.clear()`, `StartCrawlControl` role gate, `refetchInterval → false` at terminal) and by the operator's live observations; capturing the artifacts is optional follow-up.

---

## Sign-off
- All scenarios PASS: ☑ (1, 2, 3, 4, 5, 6A, 6B, 6C, 7 — Scenario 7 accepted with administrative evidence notes)
- Operator acceptance: **FULLY ACCEPTED ON TEST — PRODUCTION READINESS NOT STARTED** (three low-risk Scenario 7 artifacts not saved; documentation-only).
- Date: 2026-07-15
- Scope of acceptance: **TEST project `Digi_SEO_Test` only.** Production untouched; the crawler is not deployed / not customer-operational; production-readiness planning is the next milestone.
- Final state recorded in `PHASE_16H_CRAWLER_CUSTOMER_UI_SIGNOFF.md`. No implementation defect found; no code change required.
