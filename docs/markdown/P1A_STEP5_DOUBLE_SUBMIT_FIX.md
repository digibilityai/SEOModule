# P1a Step 5 — Double-submit fix (operator Step 2.8) — record

**Status:** `RESOLVED — Step 2.8 PASS (authenticated operator acceptance, final visible bounded post-action lock)` (2026-07-17). Final design + accepted criteria in §9 (authoritative). §§3, 6a, 8 record the two superseded interim guards (synchronous latch, then leading-edge throttle) and are retained for history only.

**Superseded-status note (2026-07-16):** `FIX IMPLEMENTED + type/build + MOCK-browser verified; authenticated Step 2.8 re-test PENDING (operator)`.
**Type:** approved, one-file, UI-only, backward-compatible defect fix. No DB/RPC/RLS/
migration/worker/crawl/locked change. Production untouched. P1a still not accepted/locked.

## 1. Defect (operator Step 2.8)
During authenticated owner acceptance, rapid clicks on **Check again** issued
**multiple** `seo_ownership_verification_recheck` RPCs. Backend integrity stayed
correct (one row, valid state) → frontend submission-guard issue only.

## 2. Root cause (Confirmed)
`OwnershipVerificationPanel.tsx` guarded the action buttons **only** with
`disabled={anyPending}`, where `anyPending` derives from React Query `isPending`.
Those flags flip to `true` only **after** the first `mutate()` schedules a state
update and React commits a re-render (async/batched). Rapid clicks landing before
that commit each ran the bare `onClick={() => recheck.mutate()}` while the DOM
button was still enabled — firing one RPC per click. There was **no synchronous
early-return guard** and no debounce; React Query does not dedupe concurrent
`mutate()` calls. Same pattern applied to `initiate`, `recheck`, `reverify`, and
the `Confirm revoke` click. Purely frontend — the service/RPC/RLS were correct.

## 3. Fix (one file: `src/pages/seo/websites/OwnershipVerificationPanel.tsx`)
Added a **synchronous in-flight latch** (`useRef<boolean> submittingRef`) and a
`submitOnce(mutation)` helper: it returns immediately if the latch is set, sets
the latch **synchronously before** `mutation.mutate(undefined, { onSettled })`,
and clears it in `onSettled` (runs on **both** success and failure — never
sticks). All four write actions (`initiate`/`recheck`/`reverify` + the
`Confirm revoke` click) now route through `submitOnce`. `disabled={anyPending}`,
labels, single-click behaviour, error surfacing, and query invalidation are
unchanged. No debounce/throttle, no timer guard, no service/hook signature
change, no new API/DB behaviour, no locked file. (Revoke's two-step confirm flow
is unchanged; the latch only prevents a double-fire on the confirm click, which
inspection showed shares the same race — benign since revoke is idempotent.)

## 4. Verification evidence (executed 2026-07-16)
- `npx tsc --noEmit -p tsconfig.app.json` — **clean.** `npm run build` — **OK.**
- **Static sweep:** only `OwnershipVerificationPanel.tsx` changed (10-min mtime);
  no direct Supabase/service-role/claims/lease/internal added; still only the
  Step 4 hooks + `submitOnce`; no debounce/throttle; no crawl/worker file changed.
- **Mock-mode browser (in-session, deterministic):** a **rapid burst of 5
  synchronous "Re-verify" clicks rotated the mock challenge by exactly ONE**
  (counter 1→2, not 1→6) → exactly one mutation; the latch then **cleared** (a
  single subsequent click advanced 2→3); a **5-click "Check again" burst reused
  the token** (3→3), staying pending; **no console errors; no Supabase request**
  (all network Vite/localhost).
- **Non-regression:** P1a **Step 1 ALL PASS**; **Phase 16C–16H ALL PASS**; **Stage 6
  smoke PASSED + campaign-create + campaign-transition ALL PASS**; **worker `tsc`
  clean + suite 74/74**; **root `tsc` clean + build OK**.
- **P1a Step 2B + Step 3 SQL — FAILED THIS RUN (not a regression, not a defect):**
  both failed at the `seo_ownership_verification_claim` step ("did not claim the
  pending verification"). Root cause = **operator-created leftover `pending`
  ownership verifications on TEST** (`https://digibility.ai`,
  `https://stage5-smoke-test.example`, from the authenticated owner Steps 2.1–2.7
  run) with older `updated_at`; the claim RPC correctly returns the
  **globally-oldest** eligible pending row, so these two scripts — which assume
  they are the only pending verification — claim the leftover instead of their own
  fixture. This is a **test-isolation artifact of the operator's own acceptance
  run**, NOT caused by the frontend-only fix and NOT a product/RPC defect (no
  disposable `af000000-` fixtures remain; no open claims). These scripts will PASS
  again once the two leftover pending verifications are cleared. **The operator's
  in-progress acceptance data was NOT deleted.**

## 5. Operator Step 2.8 authenticated re-test — PENDING
Requires the operator's authenticated browser/session on `Digi_SEO_Test` (not
runnable here). Re-test: as owner on a pending verification, rapid-click **Check
again** → expect exactly **one** `seo_ownership_verification_recheck` POST, one
verification row, consistent UI. Apply the same rapid-click check to **Verify
ownership** and **Re-verify**.

## 6. Rollback
Revert the single file `src/pages/seo/websites/OwnershipVerificationPanel.tsx`
(remove `submittingRef`/`submitOnce`; restore the bare `mutation.mutate()`
handlers). No DB rollback. Everything else preserved.

## 8. Second iteration — leading-edge throttle (real-timing fix, 2026-07-17)
**First-fix limitation (confirmed):** the synchronous `submittingRef` latch cleared
on the mutation's `onSettled`, so it only blocked **overlapping** calls. Against a
fast backend each RPC settles between real (spaced) clicks — clearing the latch (and
`isPending`→`disabled`) — so a spaced rapid burst still fired one RPC per click. The
earlier mock "one per burst" proof was an artifact of driving the burst as a single
**synchronous** JS loop (all clicks before any settle).

**Approved fix (one file, `OwnershipVerificationPanel.tsx`):** added a **leading-edge
per-action throttle** alongside the retained in-flight latch: `THROTTLE_MS = 1000`, a
stable `lastAcceptedRef` map keyed by action (`initiate`/`recheck`/`reverify`/
`revoke`). `submitOnce(action, mutation)` returns if the same action was accepted
within the window OR a write is in flight; otherwise records the timestamp
**synchronously** and calls `mutate` (latch cleared on `onSettled`; the accepted
timestamp is **not** cleared on settle). First click runs immediately; a deliberate
click after the window works; throttle is **per-action** (never blocks an unrelated
action). No trailing-edge debounce, no first-click delay, no visual countdown;
`disabled={anyPending}`, labels, lifecycle, error handling, and query invalidation
unchanged. No service/hook/RPC/DB/worker/crawl/locked change.

**Verification (executed 2026-07-17):** root `tsc` clean; `build` OK; static sweep —
only `OwnershipVerificationPanel.tsx` changed, no direct Supabase/service-role/claims,
no debounce, no crawl/worker edit. **Mock SPACED-click proof** (real timers, not a
sync loop): **5 "Re-verify" clicks 120 ms apart → challenge rotated by exactly ONE**
(counter 1→2); a **deliberate click after the 1000 ms window rotated again** (2→3); a
5-click "Check again" spaced burst **reused the token** (3→3), stayed pending; **no
console errors; no Supabase request**. Fix-unaffected non-regression re-run: Step 1 +
Step 2A + Phase 16C–16H + Stage 6 (smoke/create/transition) + worker 74/74 + root
tsc/build **ALL PASS**.

## 7. Status
Throttle fix implemented + verified (static + mock spaced-click). *(Superseded by §9 —
the throttle was itself retired after the diagnostic below.)*

## 9. FINAL resolution — visible bounded post-action lock (2026-07-17) — Step 2.8 PASS

**Why the earlier guards were retired (not "failures"):** temporary `[OVP]` runtime
instrumentation on a fresh authenticated bundle proved the throttle/keep-alive code was
executing correctly on a **single persistent component instance** (no remount). The
operator's multi-second "burst" simply had **inter-click gaps > the cooldown**, so the
lock legitimately released between clicks and each later click was a genuine new action.
The diagnostic therefore invalidated the **acceptance criterion itself**, not the code:
**"exactly one RPC across an arbitrarily long multi-second burst" is unsound** — without
extra UX state a pause longer than any finite cooldown is indistinguishable from a
deliberate later recheck. **The earlier long-burst runs are reclassified as INVALID
TESTS against a retired/unsound criterion — they are not defects and not failures.**

**Final approved semantics (production UX):**
- first click **fires immediately**;
- the action button stays **visibly `disabled`** through the mutation lifecycle + the
  invalidation-driven status refetch + a **fixed 3000 ms** post-settle cooldown;
- rapid accidental duplicates are blocked (a **synchronous per-action guard** rejects
  same-frame clicks before `disabled` re-renders);
- after the window the action re-enables and a later click is **intentionally a new
  recheck**.

**Final implementation (one file, `OwnershipVerificationPanel.tsx`):** a per-action
explicit state machine **`idle → in_flight → cooldown → idle`**. `phaseRef` (synchronous
`useRef`) is authoritative; `lockedActions` (React state) mirrors it to drive the visible
`disabled` (`disabled = anyPending || lockedActions[action]`). idle-click → synchronously
`in_flight` + `mutate` once; clicks while `in_flight`/`cooldown` never mutate and never
reset the timer; `onSettled` → `cooldown` + one fixed 3000 ms timer; timer expiry → `idle`
+ re-enable. Keep-alive/throttle/latch fully removed. No first-click delay, no debounce,
no visual countdown, no module/global guard, no service/hook/RPC/DB/RLS/worker/config
change. Labels, error surfacing, and query invalidation unchanged.

**Final accepted acceptance criteria (replace the retired "one-RPC-per-burst"):**
- **AT-1 — rapid accidental duplicates:** rapid double/triple click on "Check again"
  → **exactly 1** `seo_ownership_verification_recheck` POST (HTTP 200).
- **AT-2 — visible feedback:** the button is visibly disabled through mutation +
  refetch + the fixed cooldown (~3.5 s observed), then re-enables.
- **AT-3 — deliberate later recheck:** one click after re-enable → **exactly 1** new
  recheck POST (HTTP 200). This is expected/correct, not a duplicate.
- **AT-4 — concurrency:** no overlapping duplicate in-flight requests (supported by
  AT-1 + the synchronous `in_flight` phase gate).

**Verification (2026-07-17):** root `tsc --noEmit` clean; `npm run build` OK; one-file
scope confirmed; all temporary `[OVP]` diagnostics removed (grep = none). **Mock
quantitative proof** (recheck counted **directly via the mock store's `lastCheckedAt`**,
not token rotation): 8 rapid "Check again" clicks → **exactly one** accepted recheck;
disabled during cooldown; re-enabled after the window; one deliberate click after
re-enable → **exactly one** more (2 total). Same guard confirmed for initiate (8 clicks
→ 1 fresh token), reverify (8 clicks → 1 rotation), revoke (single `revoked`, confirm
dialog unmounted). No console errors; **zero Supabase requests** in mock.

**Authenticated operator acceptance — Step 2.8 PASS (2026-07-17):**
- **AT-1 PASS** — rapid double/triple click → exactly **1** recheck POST, HTTP 200.
- **AT-2 PASS** — button disabled for ≈ 3.5 s, then re-enabled.
- **AT-3 PASS** — deliberate click after re-enable → exactly **1** new recheck POST, HTTP 200.
- **AT-4 PASS** — no overlapping duplicate requests (via AT-1 + the synchronous guard).
- UI remained **`Verification pending`** throughout (recheck reuses the challenge).

**Result: Step 2.8 = PASS.** Production untouched. P1b not started. (Overall P1a
module-lock and the remaining separate operator items are tracked in the SIGN-OFF.)

## 10. A3 DB proof + pending-record cleanup — COMPLETE (2026-07-17)
- **A3 integrity proof (TEST, read-only):** the `digibility.ai` ownership row
  (`website_id=fb98d59c-0f7d-4724-9f60-9db385bf2592`, `method=dns_txt`) = **exactly one
  row** (`row_count=1`), `status=pending`, `last_checked_at=updated_at=2026-07-17
  16:25:18.663042+00` → the double-submit testing created **no duplicate rows**.
- **Cleanup via the authenticated customer revoke UI (not direct delete; append-only
  audit preserved):** `digibility.ai` → `revoked` (`updated_at 2026-07-17
  16:33:13.804585+00`); Stage-5 smoke fixture `stage5-smoke-test.example`
  (`77777777-0000-0000-0000-0000000000b1`, source
  `supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql`; was `pending`,
  `has_open_claim=false`) → `revoked` (`updated_at 2026-07-17 16:43:24.935897+00`).
- **Effect:** the earlier §7/§8 "Step 2B/Step 3 SQL DEFERRED until the two leftover
  pending verifications are cleared" note is now **RESOLVED** — TEST has a clean pending
  state. Step 2B + Step 3 SQL regressions are **UNBLOCKED but NOT yet re-executed**
  (follow-up; not claimed PASS). No code/DB-schema/RPC/RLS/worker change.
