# P1a Step 5 — Websites/onboarding ownership-verification UI (record)

**Status:** `IMPLEMENTED + type/build-verified + MOCK-validated; authenticated operator Step 2.8 (double-submit) ACCEPTED — PASS (2026-07-17, final visible bounded post-action lock, §6c); authenticated browser role matrix ACCEPTED — PASS (2026-07-18, owner/admin/team_member/client + sign-out isolation on Digi_SEO_Test); real verify-once worker-binary run ACCEPTED — PASS (2026-07-19); P1a Domain Ownership Verification COMPLETE and MODULE-LOCKED; additive UI; production untouched`.
**Scope:** Step 5 — the customer-facing Domain Ownership Verification UI in the
Websites area. **P1a is now COMPLETE and MODULE-LOCKED** (2026-07-19; Step 6
sign-off and full operator acceptance done — see `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md`
and `MODULE_LOCKS.md`). P1b (verified-only crawl enqueue enforcement) is the next
implementation stage, not started.
**No DB/migration/RPC/RLS change; no worker change; no crawl UI change.**

**Builds on:** Step 4 hooks/service (`useOwnershipVerification`, `ownershipVerificationService`).

---

## 1. Files added / edited
- **New:** `src/pages/seo/websites/OwnershipVerificationPanel.tsx` — the full
  workflow panel (status + DNS-TXT instructions + owner/admin actions + read-only
  role explanation + copy controls + revoke confirm + a local accessible role
  tooltip). Uses **only** the Step 4 hooks.
- **Additive edit:** `src/pages/seo/WebsiteCard.tsx` — imports the panel and renders
  `<OwnershipVerificationPanel websiteId={website.id} websiteUrl={website.website_url} />`
  after `WebsiteConnectionHealth` (+ a `Separator`). Smallest appropriate
  Websites/onboarding surface; no new route; no page redesign.
- **No** crawl UI / `StartCrawlControl` / `CrawlPanel` / crawl hook/service / worker
  / DB / RPC / `MODULE_LOCKS.md` change. The locked Stage 6 `RoleGateTooltip` is
  **not** edited — a local equivalent (`RoleTooltip`) lives in the new file.

## 2. States & actions (per the Step 2A lifecycle)
- **Unverified:** explanation + owner/admin "Verify ownership" (initiate);
  read-only + role note for others.
- **Pending:** DNS TXT instructions (Type=TXT, exact Host `_digibility-site-
  verification.<host>`, exact Value = challenge token) with copy controls; honest
  propagation note; "Check again" (recheck) + "Re-verify (new record)" (reverify).
  No fake progress, no automatic checking.
- **Verified:** verified host + verified timestamp; owner/admin re-verify / revoke.
- **Failed:** customer-safe failure reason (no resolver diagnostics) + DNS
  instructions; "Check again" (same token) + "Re-verify" (rotated).
- **Revoked:** read-only revoked note + "Verify ownership" (fresh). The **derived**
  approximate revoked timestamp is **not** displayed (omitted, per its accuracy).
- **Loading/errors:** loading text; genuine RPC authorization/validation/lifecycle
  errors surfaced verbatim via the Step 4 non-masking write helper (never masked by
  mock); read errors shown honestly.
- **Double-submit / conflicts:** all actions disabled while any mutation is pending;
  explicit two-step revoke confirmation; mutation success refreshes only the
  matching ownership-verification query (no polling, no browser DNS).

## 3. Permissions & accessibility
- Owner/admin: initiate/recheck/reverify/revoke. team_member/client: **read-only**
  status + an accessible role explanation ("Requires the owner or admin role.").
  **No** Step 2B global-admin override exposed. Gating is affordance-only via
  `getCurrentSeoRole` (Supabase mode); mock has no real role (actions open in
  preview, matching Stage 6/crawl UX). RLS + the Step 2A RPCs remain authoritative;
  no role simulation / client-supplied role trust.
- Accessibility: status is text-labelled (never colour-only); a labelled
  `section[aria-label="Domain ownership verification"]`; the disabled-control
  tooltip works on hover **and** keyboard focus; copy buttons have `aria-label` +
  an `aria-live` "Copied" announcement; mutation/read errors use `role="alert"`;
  the revoke confirmation is keyboard-operable; headings follow the card hierarchy.

## 4. Mock mode
Permanent, deterministic preview: a "Preview" badge + an explicit "no real domain
is verified" note; per-website isolated state; all states reachable via
initiate/recheck/reverify/revoke; no Supabase call, no DNS, no timers driving
state. Does not affect other mocks/services.

## 5. Verification evidence (executed 2026-07-16)
| Check | Result |
|---|---|
| Root `tsc --noEmit -p tsconfig.app.json` | **PASS** (clean) |
| Root `npm run build` | **PASS** |
| Frontend lint/test | **N/A** — repo has no frontend lint/test script (none added) |
| Static security sweep | **PASS** — no service-role key; no claims/events/lease/internal-diag field; no direct table write / raw Supabase in the UI (uses Step 4 hooks only); only the `seo-ownership-verification[-role]` query keys (no crawl-key collision); no crawl/worker file edited |
| Step 1 / 2A / 2B SQL verification | **ALL PASS** (non-regression) |
| Standalone Phase 16C/16D/16E/16F/16G/16H | **ALL PASS** (non-regression) |
| Worker suite | **74/74 pass, 0 fail** (non-regression) |

**Browser/operator validation:**
- **Mock mode — DONE (in-session, `VITE_SEO_DATA_MODE=mock`):** `/seo/websites`
  renders the panel on each website card; "Preview" label + honest note shown;
  initiate → **pending** with correct DNS TXT Host/Value + copy controls; **recheck
  reused** the token (`…000001`→`…000001`); **reverify rotated** it (`…000001`→
  `…000002`); revoke → confirm → **"Verification revoked"** → only "Verify
  ownership" remains; **no console errors**; **no Supabase request** (all network is
  Vite/localhost). Locked crawl UI unchanged; existing Websites/onboarding cards
  render normally.
- **Authenticated TEST (owner/admin/team_member/client) — COMPLETE — PASS (2026-07-18,
  `Digi_SEO_Test`):** operator-executed logged-in click-through against the real
  Supabase-mode app, each role followed by sign-out. Owner: `Verify ownership` on
  `digibility.ai` issued exactly one `seo_ownership_verification_initiate` request
  (HTTP 200), UI moved to **Verification pending** and persisted through a hard
  refresh. Admin: `Check again` on the persisted pending state issued exactly one
  `seo_ownership_verification_recheck` request (HTTP 200), status remained pending.
  team_member and client: pending status shown, **no** action buttons rendered, the
  read-only role message shown, and Network evidence confirmed **no**
  initiate/recheck/reverify/revoke request fired for either role. Every sign-out
  redirected to `/seo/login` and removed protected content; status was read live from
  Supabase across role switches (no stale cross-user state). **No defect found; no
  file changed.** Full evidence: `P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §3 +
  §10 (2026-07-18 entry).

## 6. Rollback (code-only)
Delete `src/pages/seo/websites/OwnershipVerificationPanel.tsx`; revert the 3-line
`WebsiteCard.tsx` integration (import + panel + separator). No DB rollback. Step 4
service/types/hooks/mock and Steps 1–3 backend/worker remain; existing
Websites/onboarding behaviour preserved.

## 6c. Double-submit — FINAL resolution (2026-07-17 — visible bounded post-action lock) — Step 2.8 PASS
The keep-alive/throttle attempts (§6a, §6b) were retired after temporary `[OVP]`
diagnostics proved they ran correctly on a single persistent instance: the operator's
multi-second burst had inter-click gaps > cooldown, so each later click was a legitimate
new action. That invalidated the **acceptance criterion** ("one RPC across an arbitrarily
long burst"), which is unsound; the earlier long-burst runs are **invalid tests against a
retired criterion, not failures.** Final **one-file** guard in
`OwnershipVerificationPanel.tsx`: a per-action state machine **`idle → in_flight →
cooldown → idle`** — synchronous `phaseRef` authoritative + `lockedActions` state driving
`disabled` (`disabled = anyPending || lockedActions[action]`); first click fires
immediately; button stays visibly disabled through mutation + refetch + a **fixed 3000 ms**
cooldown; clicks while locked never mutate/reset the timer; after the window a later click
is intentionally a new recheck. No keep-alive/throttle/debounce/countdown/module-guard; no
service/hook/RPC/DB/worker change. **Accepted criteria AT-1..AT-4** and full evidence:
see `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §9. **Authenticated operator Step 2.8 = PASS.**

## 6b. Double-submit fix — second iteration (2026-07-17 — leading-edge throttle) — SUPERSEDED by §6c
The first synchronous latch (§6a) was a concurrency-only guard; a fast backend
settled between real spaced clicks, so an authenticated rapid burst still sent
multiple `seo_ownership_verification_recheck` RPCs. Fixed **UI-only** by adding a
**leading-edge per-action throttle** (`THROTTLE_MS=1000`, per-action `lastAcceptedRef`)
alongside the retained in-flight latch: first click runs, repeat same-action clicks
within 1 s are ignored, a deliberate click after the window works, per-action (no
global block), no debounce/first-click-delay. Verified by `tsc`/`build` + a mock
**spaced-click** proof (5 "Re-verify" clicks 120 ms apart → exactly one rotation).
Authenticated operator Step 2.8 re-test pending. See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md` §8.

## 6a. Post-implementation fix (2026-07-16 — double-submit, operator Step 2.8)
Operator acceptance Step 2.8 found rapid clicks on "Check again" issued multiple
`seo_ownership_verification_recheck` RPCs (the guard relied only on the async
`disabled={anyPending}`). Fixed **UI-only** in this panel with a synchronous
`useRef` submission latch (`submitOnce`, set before `mutate`, cleared on
`onSettled`) covering initiate/recheck/reverify + the confirm-revoke click;
`disabled={anyPending}`/labels/lifecycle/invalidation unchanged. Verified by
`tsc`/`build` + a mock-browser rapid-burst proof (a 5-click "Re-verify" burst
rotates the challenge exactly once; the latch clears; "Check again" burst reuses
the token). See `P1A_STEP5_DOUBLE_SUBMIT_FIX.md`.

## 7. Operator validation (for Step 6) — COMPLETE (2026-07-18)
Authenticated browser validation on `Digi_SEO_Test` for owner/admin (initiate/recheck,
refresh persistence, real RPC 200s) and team_member/client (read-only, no write RPC
issued, accessible role explanation) is **now complete — PASS**, with cross-user
sign-out isolation confirmed for every role (see §5 above and
`P1A_DOMAIN_OWNERSHIP_VERIFICATION_SIGNOFF.md` §3/§10). Reverify-rotate/revoke and the
locked-crawl-UI/console-error non-regression checks were not part of this specific
browser run's accepted evidence and remain covered by the separately-executed mock-mode
validation (§5) and static/SQL regressions (unaffected by this UI-only acceptance).
