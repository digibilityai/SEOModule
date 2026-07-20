# Phase 14B.2 — Decline Diagnosis Engine Service Wiring

Wires the Decline Diagnosis Engine's frontend read path to the Stage 5
Supabase backend (`seo_decline_diagnoses`, `seo_decline_diagnosis_evidence`,
`seo_decline_diagnoses_current` view — applied, structurally verified,
smoke-tested, and UI-seeded on the TEST project; see
`SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` and
`SUPABASE_STAGE5_DECLINE_DIAGNOSIS_SEED_EXTENSION_GUIDE.md`). Read-only —
mirrors the Phase 14A.2 Page Performance wiring pattern exactly. No
migrations, seed scripts, or the reference Digibility app were touched.

> **✅ Live-verified on TEST.** After two post-launch fixes (§10, §11), this
> wiring was confirmed working end-to-end in a signed-in browser session —
> see §12 for the checkpoint.

---

## 1. Files Changed

| File | Change |
| --- | --- |
| `src/services/supabase/seoDeclineDiagnosisSupabaseService.ts` | **New.** Reads Stage 5 tables/view, maps rows into the app's existing `DeclineDiagnosis` shape. |
| `src/services/performanceService.ts` | `fetchDeclineDiagnoses` and `fetchDiagnosisForPage` now use `runWithServiceAdapter` (previously mock-only via `toAsync`). |
| `src/pages/seo/DeclineDiagnosisPage.tsx` | Added the same page-local cross-workspace fallback pattern as `PagePerformancePage.tsx` (Phase 14A.2). |
| `src/pages/seo/dev/SupabaseAuthTestPage.tsx` | Added a "Phase 14B.2 — Decline Diagnosis Engine" diagnostic section (4 new buttons, read-only). |
| `src/services/supabase/supabaseTypes.ts` | Added 3 Stage 5 table/view names to `SEO_TABLES`. |

**Not touched:** any migration file, any `supabase/test/*.sql` seed/smoke-test script, `RefreshRecommendation`-related code (`fetchRefreshRecommendationsForWebsite`/`fetchRefreshRecommendationForPage`/`generateMockPerformanceRefresh` — Stage 5 has no backend equivalent for refresh recommendations, see §7), `src/mocks/performanceMockData.ts`, `src/types/*`, `DiagnosisCard.tsx`, or the reference Digibility app.

---

## 2. Functions Wired

`performanceService.ts` (adapter-facing, unchanged signatures):

- `fetchDeclineDiagnoses(websiteId)` — mock: `listDeclineDiagnoses` (unchanged). Supabase: `fetchSupabaseDeclineDiagnoses` (new).
- `fetchDiagnosisForPage(pageId)` — mock: `listDiagnosesForPage` (unchanged). Supabase: `fetchSupabaseDiagnosesForPage` (new). Not currently called by any UI component (same as before this phase) but now adapter-wired for when it is.

`seoDeclineDiagnosisSupabaseService.ts` (new, all read-only):

- `fetchSupabaseCurrentDiagnosisRows(websiteId)` — raw `seo_decline_diagnoses_current` rows (live statuses only).
- `fetchSupabaseDeclineDiagnoses(websiteId)` — the above, mapped to `DeclineDiagnosis[]`.
- `fetchSupabaseDiagnosesForPage(pageId)` — raw `seo_decline_diagnoses` (base table, any status) for one page, mapped to `DeclineDiagnosis[]`.
- `fetchSupabaseDiagnosisEvidence(diagnosisId)` — raw `seo_decline_diagnosis_evidence` rows for one diagnosis.
- `findAccessibleWebsiteWithDeclineDiagnosisData()` — cross-workspace search. Unlike `findAccessibleWebsiteWithPerformanceData` (Phase 14A.2), this does **not** stop at the first website with any data — it scans every accessible website and ranks by live diagnosis count (see §10, added after an initial live-test finding).

All five call `requireAuthenticatedUser` and `requireValidUuid` (existing `supabaseServiceUtils.ts` guards) before any query — same defense-in-depth pattern as every other Supabase-backed SEO service. RLS on the underlying tables/view remains the real authorization boundary.

---

## 3. Supabase Tables/View Used

| Object | Used by |
| --- | --- |
| `seo_decline_diagnoses_current` (view, `security_invoker`) | `fetchSupabaseCurrentDiagnosisRows` → `fetchSupabaseDeclineDiagnoses` → `DeclineDiagnosisPage`'s "current" list, `findAccessibleWebsiteWithDeclineDiagnosisData` |
| `seo_decline_diagnoses` (base table) | `fetchSupabaseDiagnosesForPage` (all statuses, page-level history) |
| `seo_decline_diagnosis_evidence` | `fetchSupabaseDiagnosisEvidence` |

`seo_create_decline_diagnosis_from_snapshot` (the Stage 5 RPC) is **not** called anywhere in this phase — see §7.

---

## 4. Mapping Summary

Backend CHECK values (Stage 5, migration 14/15) → frontend domain values (pre-existing, `src/types/performance.ts` / `src/types/common.ts`). Full detail and rationale is in code comments in `seoDeclineDiagnosisSupabaseService.ts`.

| Backend field | Frontend field | Rule |
| --- | --- | --- |
| `diagnosis_type` (12 values) | `likely_cause: DeclineCause` (10 values) | Explicit lookup table; several backend values intentionally collapse onto one frontend cause (`ranking_decline`/`clicks_decline`/`impressions_decline` → `ranking_loss`; `content_freshness` → `freshness_issue`; `indexing_issue` → `indexing_issue`; `cannibalization_risk` → `cannibalization`; `intent_mismatch` → `intent_mismatch`; `competitor_improvement` → `competitor_improvement`; `technical_performance` → `technical_issue`; `ctr_drop` → `ctr_drop`). **Unrecognized values** (`no_data`, `mixed_signals`, or any future/unlisted value) fall back to `technical_issue` — a deliberately neutral, non-alarming default that doesn't assert an unproven specific claim. Never throws. |
| `priority` (low/medium/high) + `severity` (low/medium/high/**critical**) | `priority: ImpactLevel` (low/medium/high) | `priority` passes through 1:1 (already the same domain); a `severity='critical'` row is forced to `priority='high'` regardless of its own `priority` value, so the most urgent items are never under-prioritized by a 3-value UI that has no `critical` concept. Any unrecognized `priority` string falls back to `'medium'`. |
| `suggested_owner` (4 values) | `fix_owner: OwnerType` (4 values, same domain) | Validated pass-through (`client_action`/`developer_needed`/`digibility_expert`/`system_suggestion`); any unrecognized value falls back to `'system_suggestion'`. |
| `status` (5 values) | *(no frontend field)* | Not mapped — instead, the "current" list read queries `seo_decline_diagnoses_current`, whose own view filter already excludes `resolved`/`dismissed` rows. The page-level history read (`fetchSupabaseDiagnosesForPage`) queries the base table directly and can surface all 5 statuses. |
| `movement_status` (5 values) | *(no frontend field)* | Read (on both the diagnosis row and the view's `latest_movement_status`) but not mapped into `DeclineDiagnosis` — passed through unmapped on the raw row types for dev-harness/future use, same precedent as Stage 4. |
| `evidence_type` (10 values), `source` (6 values) | *(no frontend field yet)* | No frontend evidence domain type exists, so `SeoDeclineDiagnosisEvidenceRow` exposes them as raw strings — dev-harness/future-UI consumption only. |
| `page_id` | `page_performance_id` | Direct pass-through — `seo_decline_diagnoses.page_id` **is** `seo_page_inventory.id`, which is exactly what `PagePerformance.id` already equals (Phase 14A.2's `mapToPagePerformance`). This is what keeps `pages.find((p) => p.id === diagnosis.page_performance_id)` in `DeclineDiagnosisPage.tsx` working unchanged. |
| `keyword` | `related_keyword` | Direct pass-through (`null` → `undefined`). |
| `business_summary` / `technical_explanation` / `recommended_next_action` | `business_explanation` / `technical_explanation` / `recommended_fix` | Direct pass-through (renamed fields only). |
| *(derived)* | `needs_expert_support: boolean` | `suggested_owner === 'digibility_expert'` — ties the existing "Request expert support" button in `DiagnosisCard.tsx` directly to the backend's own classification. |

---

## 5. Fallback Behavior

- **Adapter-level:** `runWithServiceAdapter` (unchanged, existing foundation) — mock mode never touches Supabase; Supabase mode calls the new service and, on any thrown error (network, RLS denial, missing config), logs one console warning and falls back to mock data. This is the same "errors degrade to mock" behavior already used by every other Phase 13/14A service — Phase 14B.2 does not change or add a new fallback policy, per the task's "do not mask true Supabase permission failures... unless existing serviceAdapter does so intentionally" — it already does, intentionally, project-wide.
- **Page-level (`DeclineDiagnosisPage.tsx`):** a **new**, page-local cross-workspace fallback, structurally identical to `PagePerformancePage.tsx`'s (Phase 14A.2). In Supabase mode only, if the app-wide active website has zero *live* diagnoses **or its onboarding is incomplete**, the page searches every accessible workspace/website for one with live diagnosis data (`findAccessibleWebsiteWithDeclineDiagnosisData`) and, if found, fetches that website's full record (`fetchWebsiteById`) and uses it as a page-local `displayWebsite` override — never mutating the shared `ActiveWebsiteContext` (which cannot represent a cross-workspace switch; see `PagePerformancePage.tsx`'s code comment for the full rationale). See §11 for a post-launch correction to this effect's trigger conditions.
- **Mock/demo generation button:** `DeclineDiagnosisPage.tsx` has no mock-generation button at all (unlike `PagePerformancePage.tsx`'s "Generate performance data") — nothing needed hiding.

---

## 6. Mock Mode Preserved

- `listDeclineDiagnoses` / `listDiagnosesForPage` in `src/mocks/performanceMockData.ts` are byte-for-byte unchanged.
- `roadmapService.ts`'s existing call to `fetchDeclineDiagnoses` is unaffected — it already goes through the (now adapter-wired) `performanceService` function and continues to receive the same `DeclineDiagnosis[]` shape in both modes.
- Verified: `npx tsc --noEmit -p tsconfig.app.json` and `npm run build` both pass with `VITE_SEO_DATA_MODE` unset (mock mode is the default resolution).

---

## 7. Writes/Mutations — None Wired

This phase is **read-only**, matching the task scope:

- No `INSERT`/`UPDATE`/`DELETE` against any Stage 5 table from the frontend.
- The `seo_create_decline_diagnosis_from_snapshot` RPC exists in the backend (Stage 5, migration 16) but is **not called** — nothing in the current UI has a "create a diagnosis" action, so wiring the RPC now would be unused surface area. Revisit if/when a write UI is designed.
- No diagnosis-to-recommendation conversion (`linked_recommendation_id` remains write-only from the backend seed's perspective; the frontend never reads or sets it).
- No status-transition UI (open → in_review → resolved, etc.) — Stage 5's `status` lifecycle is read (implicitly, via the current view's filter) but never written from the frontend.

---

## 8. Manual Test Steps

**Mock mode** (`.env` → `VITE_SEO_DATA_MODE=mock` or unset):
1. Navigate to `/seo/decline-diagnosis` for the seeded mock website (Acme Plumbing).
2. Confirm the 3 mock diagnoses render exactly as before this phase (business explanation, technical detail, recommended fix, priority badge, owner badge, "Request expert support" button on the competitor-improvement one).
3. Confirm `/seo/roadmap` still includes decline-diagnosis-derived items (unaffected downstream consumer).

**Supabase mode, no session** (`.env` → `VITE_SEO_DATA_MODE=supabase`, not signed in):
1. Navigate to `/seo/decline-diagnosis` — Supabase calls fail with "no authenticated Supabase user," `runWithServiceAdapter` catches it and falls back to mock; page renders identically to mock mode (same as the established Phase 13/14A no-session behavior).
2. `/seo/dev/auth-test` → click "Find website with Decline Diagnosis data" — expect the warning `seoDeclineDiagnosisSupabaseService.findAccessibleWebsiteWithDeclineDiagnosisData: no authenticated Supabase user (session missing).`

**Supabase mode, signed in as a seeded test user** (✅ executed live in the browser — see §12 for the checkpoint; steps below are the repeatable retest procedure):
1. Sign in at `/seo/dev/auth-test` as a user who is a member of workspace `44444444-0000-0000-0001-000000000001`.
2. Click "Find website with Decline Diagnosis data" — expect it to report workspace `"UI Seed Workspace"` (or whatever the seed's workspace name is), website `https://ui-seed-digibility.example`, live diagnosis count **6** (highest among however many accessible websites have diagnoses — e.g. "6 (highest among 2 accessible websites with diagnoses)" if the Stage 5 smoke-test workspace, with its 2 diagnoses, is also accessible to this test user). See §10 for why this is a ranked pick, not just the first match.
3. Click "Test Decline Diagnosis Current View" — expect 6 rows, a type-count breakdown across the seeded types, and a first-record summary line.
4. Click "Test Diagnosis Evidence" — expect a non-zero evidence row count (2-4) for the first diagnosis.
5. Visit `/seo/decline-diagnosis` — expect it to show 6 diagnoses (not the smoke-test workspace's empty state), each rendering a valid `likely_cause` label, `priority` badge, and `fix_owner` badge (no console errors, no "undefined" labels — confirms the mapping never produces an out-of-domain value).
6. Confirm the 2 `resolved`/`dismissed` seed diagnoses do **not** appear on this page (view-level filter working).

---

## 9. Known Limitations

- **Demo/manual seed data only.** All Stage 5 rows on the test project come from `seo_seed_stage5_decline_diagnosis_ui_extension.sql` — hand-written narrative content, not derived from real signals.
- **No real GSC/GA4/crawler/LLM.** Nothing in this phase or Stage 5 calls an external API or model.
- **No production apply.** This phase only reads from the TEST Supabase project; production is untouched and remains gated per `BACKEND_MILESTONE_HANDOFF.md`.
- **Diagnosis-to-recommendation conversion not wired.** `linked_recommendation_id` exists on the backend but has no frontend read/write path.
- **RPC creation flow not wired.** `seo_create_decline_diagnosis_from_snapshot` is unused by the frontend (see §7) — no UI currently needs it.
- **Refresh recommendations remain 100% mock.** Stage 5 has no backend table for `RefreshRecommendation` — `fetchRefreshRecommendationsForWebsite`/`fetchRefreshRecommendationForPage`/`generateMockPerformanceRefresh` are unchanged and out of scope for this phase.
- **`fetchDiagnosisForPage` has no live caller** in the current UI (same as before this phase) — it is adapter-wired for correctness/future use but not exercised by any page today.
- Real signed-in Supabase verification **has since been performed and passed** — see §12 for the checkpoint. §8's signed-in steps are the repeatable retest procedure.

---

## 10. Post-Launch Fix — Website Selection Ranking

A live signed-in test after initial wiring found `findAccessibleWebsiteWithDeclineDiagnosisData()` selecting the Stage 5 **smoke-test** workspace/website (`Stage5 Decline Diagnosis Smoke Test WS`, `https://stage5-smoke-test.example`, 2 live diagnoses) instead of the intended UI seed workspace/website (`https://ui-seed-digibility.example`, 6 live diagnoses).

**Root cause:** the original implementation returned on the **first** accessible website with `diagnosisCount > 0`. `listAccessibleSeoWorkspaces()` orders workspaces `created_at DESC` (most recently created first) — since the Stage 5 smoke test workspace was created after the base UI seed workspace, it was checked first and, having 2 diagnosis rows, the search stopped there without ever reaching the richer UI seed workspace.

**Fix:** `findAccessibleWebsiteWithDeclineDiagnosisData()` now scans **every** accessible workspace/website (no early return), collects a candidate list, and picks the one with the **highest live diagnosis count**. Ties fall back to discovery order, which is itself workspace-`created_at`-DESC (from `listAccessibleSeoWorkspaces`, unchanged) then whatever order `fetchSupabaseWebsitesForWorkspace` returns within a workspace (unchanged) — `Array.prototype.sort` is stable, so this ordering is preserved as the deterministic fallback without a second query or any change to either shared helper. No workspace/website name or URL is hardcoded or special-cased (e.g. nothing checks for the literal string "smoke") — selection is purely by count. The returned object gained one new field, `candidateCount` (how many accessible websites had ≥1 live diagnosis), shown in the dev harness result text (e.g. "6 (highest among 2 accessible websites with diagnoses)") so it's visible *why* a candidate won, not just which one did.

**Scope of the fix:** isolated entirely to `seoDeclineDiagnosisSupabaseService.ts` and the dev-harness display string in `SupabaseAuthTestPage.tsx`. `listAccessibleSeoWorkspaces()` and `fetchSupabaseWebsitesForWorkspace()` (both shared with Page Performance's `findAccessibleWebsiteWithPerformanceData`) were **not modified** — Page Performance's own "first match wins" fallback behavior from Phase 14A.2 is unchanged and out of scope for this fix. `DeclineDiagnosisPage.tsx` required no code change: it already only reads `found.websiteId` from the finder's return value, which is unaffected by the additional `candidateCount` field.

---

## 11. Post-Launch Fix — Onboarding Gate Blocked the Fallback Search

After §10's fix, `/seo/dev/auth-test` correctly found the UI seed website (6 diagnoses), but `/seo/decline-diagnosis` itself still showed "Complete business onboarding first" instead of rendering that data.

**Root cause:** `DeclineDiagnosisPage.tsx`'s fallback-search `useEffect` required the *currently active* website's onboarding to already be `isOnboardingComplete === true` before it would even attempt the search (`if (isLoadingWebsite || isLoadingOnboarding || !isOnboardingComplete) return;`). This was written as a deliberate safety check in the original Phase 14B.2 wiring (see the now-corrected §5 note above), but it backfired: the auto-selected active website in this scenario is a disposable Stage 5 smoke-test website whose onboarding was never completed (smoke-test seeds don't create onboarding rows), so `isOnboardingComplete` was permanently `false` for it — and the search that would have found a better, already-onboarded website never ran at all. `PagePerformancePage.tsx`'s equivalent effect never had this gate, which is why its fallback worked correctly in the analogous scenario.

**Fix:** the effect no longer requires the active website's onboarding to already be complete before searching. It now searches when **either** condition holds: the active website's onboarding is incomplete (its diagnoses query never even runs in that case, so there's nothing to wait for), **or** onboarding is complete but there are zero live diagnoses once that query has settled. Once the search finds a better, already-onboarded website and applies the `displayWebsite` override, that website's own onboarding/diagnoses queries load fresh and the onboarding gate re-evaluates against it — a website with real seeded data (and completed onboarding) now correctly renders instead of being blocked by the original wrong website's incomplete onboarding.

**Preserved:** a real website whose onboarding is genuinely incomplete, with no other accessible website having diagnosis data, still correctly shows "Complete business onboarding first" (the search runs, finds nothing better, `diagnosisOverrideWebsite` stays `null`, `displayWebsite` remains the original website) — per requirement 8 of the fix task, this does not hide legitimate onboarding requirements for real websites; it only corrects which website's status the page ultimately checks. No workspace/website name or URL is hardcoded. The global active-website context is still never mutated — only the page-local override, exactly as before.

---

## 12. Live Verification Checkpoint (Browser, Signed-In)

Following the §10 and §11 fixes and a dev-server restart, Decline Diagnosis
Supabase wiring was **live-tested successfully in the browser**, signed in
against the TEST Supabase project:

- [x] **Stage 5 backend** — applied to the TEST Supabase project, structurally
      verified, smoke-tested (see `SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_NOTES.md` §12).
- [x] **Stage 5 UI seed** — applied and verified on TEST (8 diagnoses / 20
      evidence rows / 6 current-view rows; see
      `SUPABASE_STAGE5_DECLINE_DIAGNOSIS_SEED_EXTENSION_GUIDE.md`).
- [x] **Decline Diagnosis Supabase service wiring** — implemented
      (`seoDeclineDiagnosisSupabaseService.ts`, §1–§4 above) and adapter-wired
      into `performanceService.ts`.
- [x] **Static validation** — `npx tsc --noEmit -p tsconfig.app.json` passed;
      `npm run build` passed.
- [x] **Dev harness finder** — `/seo/dev/auth-test` → "Find website with
      Decline Diagnosis data" passed after the §10 ranking fix, correctly
      selecting workspace `UI Seed Workspace`, website
      `https://ui-seed-digibility.example`, live diagnosis count **6**
      (highest among 2 accessible websites with diagnoses).
- [x] **`/seo/decline-diagnosis` live browser test** — passed after the §11
      onboarding-gate-order fix. The page rendered on **UI Seed Demo Site**
      and showed the seeded decline diagnosis cards (no "Complete business
      onboarding first" block, no red console errors).
- [x] **Expected UI seed data visible** — the 6 live (open/in_review/
      action_planned) diagnosis cards from the Stage 5 seed rendered with
      valid `likely_cause`/`priority`/`fix_owner` labels.
- [x] **Production untouched** — all verification targeted the TEST Supabase
      project only; no production migration, data, or connection at any point.

**Status: Decline Diagnosis Supabase wiring is live-verified on TEST.**

**Remaining limitations (unchanged by this checkpoint):**
- Demo/manual seed data only (hand-written Stage 5 seed content, not derived
  from real signals).
- No real GSC/GA4/crawler/LLM ingestion.
- No production apply — TEST project only, gated per `BACKEND_MILESTONE_HANDOFF.md`.
- No diagnosis-to-recommendation conversion wired (`linked_recommendation_id`
  is a backend seam only).
- No RPC write flow wired — `seo_create_decline_diagnosis_from_snapshot`
  exists and is smoke-tested but is not called from any UI.
