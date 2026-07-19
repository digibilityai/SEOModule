# Phase 15A — Off-Page Authority + AI Visibility/GEO Service Wiring

Wires the Off-Page Authority Builder and AI Visibility / GEO frontend **read**
paths to the Stage 6 Supabase backend (`seo_authority_opportunities`,
`seo_authority_campaigns`, `seo_authority_campaign_tasks`,
`seo_authority_campaign_opportunities`, `seo_authority_activity`,
`seo_ai_prompt_tracking`, `seo_ai_content_gaps`, `seo_ai_mentions` — applied,
structurally verified, smoke-tested, and UI-seeded on the TEST project; see
`SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md` and
`SUPABASE_STAGE6_OFFPAGE_AI_VISIBILITY_SEED_EXTENSION_GUIDE.md`). **Read-only**
— mirrors the Phase 14A.2 / 14B.2 wiring pattern. No migrations, seed
scripts, or the reference Digibility app were touched.

> **Implemented, pending live test.** Static validation (`tsc --noEmit`,
> `npm run build`) passed and the mock-mode/no-session-Supabase-mode paths
> were verified in a browser preview (see §8). A full signed-in live test
> against the TEST project's seeded data was **not** performed in this task
> — no test-user password is stored anywhere in this repo (by design, see
> `PHASE_13B1_DEV_AUTH_TEST_NOTES.md`), so there was no credential available
> to sign in with. See §10 for the exact steps to complete that verification.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/seoOffPageAuthoritySupabaseService.ts` — reads Stage 6 Off-Page tables, maps rows into the app's existing `OffPageOpportunity`/`AuthorityCampaign` shapes.
- `src/services/supabase/seoAiVisibilitySupabaseService.ts` — reads Stage 6 AI Visibility tables, maps rows into the app's existing `PromptTrackingRecord`/`AiContentGap`/`BrandMentionSummary`/`CompetitorMentionSummary` shapes.
- `PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md` — this file.

**Changed:**
- `src/services/offPageService.ts` — `fetchAuthorityOpportunities`/`fetchAuthorityCampaigns` now use `runWithServiceAdapter`; `fetchSpamRiskReview`/`fetchAuthorityOverview` now derive from those (instead of importing mock data directly), so they're correct in both modes automatically.
- `src/services/aiVisibilityService.ts` — `fetchPromptTrackingRecords`/`fetchBrandMentionSummary`/`fetchCompetitorMentionSummary`/`fetchAiContentGaps` now use `runWithServiceAdapter`; `fetchAiVisibilityOverview` now derives from those.
- `src/pages/seo/AuthorityBuilderPage.tsx` — added the same page-local cross-workspace fallback pattern as `DeclineDiagnosisPage.tsx` (Phase 14B.2), applied from the start with the corrected (§11-style) trigger conditions.
- `src/pages/seo/AiVisibilityPage.tsx` — same fallback pattern.
- `src/pages/seo/dev/SupabaseAuthTestPage.tsx` — added a "Phase 15A — Off-Page Authority + AI Visibility/GEO" diagnostic section (4 new buttons, read-only).
- `src/services/supabase/supabaseTypes.ts` — added 8 Stage 6 table names to `SEO_TABLES` and 2 Stage 6 RPC names to `SEO_RPCS` (named for documentation/future use — neither RPC is called this phase, see §7).

**Not touched:** any migration file, any `supabase/test/*.sql` seed/smoke-test script, `src/mocks/offPageMockData.ts`, `src/mocks/aiVisibilityMockData.ts`, `src/types/offpage.ts`, `src/types/aiVisibility.ts`, any `offpage/`/`ai-visibility/` presentational component (`OpportunityCard.tsx`, `CampaignBuilder.tsx`, `CampaignList.tsx`, `PromptTrackingCard.tsx`, `BrandMentionCard.tsx`, `CompetitorMentionCard.tsx`, `AiContentGapCard.tsx`, etc.), `src/services/reportService.ts`, `src/services/seoAdminService.ts`, `src/services/roadmapService.ts`, `src/pages/seo/SeoDashboardPage.tsx` (all four already call the now-wired functions with unchanged signatures, so they inherit correct mock/Supabase behavior for free — no code change needed), or the reference Digibility app.

---

## 2. Functions Wired

`offPageService.ts` (adapter-facing, unchanged signatures):

- `fetchAuthorityOpportunities(websiteId)` — mock: `listAuthorityOpportunities` (unchanged). Supabase: `fetchSupabaseAuthorityOpportunities` (new).
- `fetchAuthorityCampaigns(websiteId)` — mock: `listAuthorityCampaigns` (unchanged). Supabase: `fetchSupabaseAuthorityCampaigns` (new) — derives `opportunity_ids` from the junction table and `progress_percentage`/`tasks` from the tasks table (see §6).
- `fetchSpamRiskReview(websiteId)` — **not adapter-wired directly**; now derives from the adapter-wired `fetchAuthorityOpportunities` (same "derive from the wired read" pattern as `performanceService.fetchPerformanceSummary`, Phase 14A.2), so it's correct in both modes with no Supabase-specific code of its own.
- `fetchAuthorityOverview(websiteId, websiteUrl)` — same derive-from-wired-reads pattern (`fetchAuthorityOpportunities` + `fetchAuthorityCampaigns` + `fetchLatestAudit`).
- `updateAuthorityOpportunityStatus`, `createAuthorityCampaign` — **NOT wired this phase, mock-only in every mode.** See §7.

`aiVisibilityService.ts` (adapter-facing, unchanged signatures):

- `fetchPromptTrackingRecords(websiteId)` — mock: `listPromptTracking` (unchanged). Supabase: `fetchSupabasePromptTrackingRecords` (new).
- `fetchBrandMentionSummary(websiteId, websiteUrl)` — mock: `buildBrandMentionSummary` (unchanged). Supabase: `fetchSupabaseBrandMentionSummary` (new) — prefers normalized `seo_ai_mentions` over re-deriving from prompt arrays (Stage 6 D2).
- `fetchCompetitorMentionSummary(websiteId, websiteUrl)` — mock: `buildCompetitorMentionSummaries` (unchanged). Supabase: `fetchSupabaseCompetitorMentionSummaries` (new), same D2 preference.
- `fetchAiContentGaps(websiteId)` — mock: `listAiContentGaps` (unchanged). Supabase: `fetchSupabaseAiContentGaps` (new).
- `fetchAiVisibilityOverview(websiteId, websiteUrl)` — derives from the four wired reads above + `fetchLatestAudit`.
- `updateAiVisibilityItemStatus`, `generateMockAiVisibilityRefresh` — **NOT wired this phase, mock-only in every mode.** See §7.

`seoOffPageAuthoritySupabaseService.ts` (new, all read-only):

- `fetchSupabaseAuthorityOpportunityRows(websiteId)` / `fetchSupabaseAuthorityOpportunities(websiteId)` — raw rows / mapped `OffPageOpportunity[]`.
- `fetchSupabaseAuthorityCampaignRows(websiteId)` / `fetchSupabaseAuthorityCampaigns(websiteId)` — raw rows / mapped `AuthorityCampaign[]` (with derived `opportunity_ids`/`tasks`/`progress_percentage`).
- `fetchSupabaseAuthorityActivity(websiteId)` — raw `seo_authority_activity` rows (append-only audit trail). No frontend activity/history UI exists yet — exposed for the dev harness and any future timeline component, same precedent as Stage 5's evidence read.
- `findAccessibleWebsiteWithAuthorityData()` — cross-workspace search, ranks by opportunity count (not first match), same shape as Phase 14B.2's `findAccessibleWebsiteWithDeclineDiagnosisData`.

`seoAiVisibilitySupabaseService.ts` (new, all read-only):

- `fetchSupabasePromptTrackingRows(websiteId)` / `fetchSupabasePromptTrackingRecords(websiteId)` — raw rows (newest observation first) / mapped `PromptTrackingRecord[]`.
- `fetchSupabaseContentGapRows(websiteId)` / `fetchSupabaseAiContentGaps(websiteId)` — raw rows / mapped `AiContentGap[]`.
- `fetchSupabaseMentionRows(websiteId)` — raw `seo_ai_mentions` rows.
- `fetchSupabaseBrandMentionSummary(websiteId, websiteUrl)` / `fetchSupabaseCompetitorMentionSummaries(websiteId, websiteUrl)` — derived summaries (see §6).
- `findAccessibleWebsiteWithAiVisibilityData()` — cross-workspace search, ranks by prompt-tracking row count.

All ten read functions in the two new Supabase service files call `requireAuthenticatedUser` and `requireValidUuid` (existing `supabaseServiceUtils.ts` guards) before any query — same defense-in-depth pattern as every other Supabase-backed SEO service. RLS on the underlying tables remains the real authorization boundary.

---

## 3. Supabase Tables Used

| Object | Used by |
| --- | --- |
| `seo_authority_opportunities` | `fetchSupabaseAuthorityOpportunityRows` → `fetchSupabaseAuthorityOpportunities`, `findAccessibleWebsiteWithAuthorityData` |
| `seo_authority_campaigns` | `fetchSupabaseAuthorityCampaignRows` → `fetchSupabaseAuthorityCampaigns` |
| `seo_authority_campaign_tasks` | `fetchSupabaseAuthorityCampaigns` (progress/tasks derivation) |
| `seo_authority_campaign_opportunities` (junction) | `fetchSupabaseAuthorityCampaigns` (`opportunity_ids` derivation — source of truth, D1) |
| `seo_authority_activity` | `fetchSupabaseAuthorityActivity` (dev-harness/future-UI only — no live page caller yet) |
| `seo_ai_prompt_tracking` | `fetchSupabasePromptTrackingRows` → `fetchSupabasePromptTrackingRecords`, both mention summaries, `findAccessibleWebsiteWithAiVisibilityData` |
| `seo_ai_content_gaps` | `fetchSupabaseContentGapRows` → `fetchSupabaseAiContentGaps` |
| `seo_ai_mentions` | `fetchSupabaseMentionRows`, both mention summaries (preferred source, D2) |

`seo_authority_opportunity_transition` and `seo_authority_campaign_transition` (the two Stage 6 RPCs) are **not** called anywhere in this phase — see §7.

---

## 4. Mapping Summary

### Off-Page Authority

Stage 6's `opportunity_type`/`status` and campaign `approval_status`/`owner` vocabularies were deliberately authored 1:1 against the pre-existing frontend types (see `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md` §7, deviation 1), so every mapping below is a validated pass-through with a safe fallback — never a throw.

| Backend field | Frontend field | Rule |
| --- | --- | --- |
| `opportunity_type` (7 values) | `opportunity_type` (7 values, same domain) | Validated pass-through; unrecognized → `backlink`. |
| `status` (8 values) | `status` (8 values, same domain) | Validated pass-through; unrecognized → `suggested`. |
| `expected_authority_impact`/`effort`/`risk` (low/medium/high) | `ImpactLevel`/`EffortLevel`/`RiskLevel` | Validated pass-through; unrecognized → `medium`. |
| `confidence_percentage` (nullable) | `confidence_percentage: number` | `null` → `0`. |
| `fix_owner` / campaign `owner` (4 values) | `OwnerType` (4 values, same domain) | Validated pass-through; unrecognized → `system_suggestion`. |
| `spam_risk_flags` (text[], already DB-CHECK-constrained) | `SpamRiskFlag[]` (same domain) | Filtered defensively against the known set anyway. |
| `target_url` (nullable) | `target_url?: string` | `null` → `undefined`. |
| *(no frontend field)* | — | `target_domain`, `recommended_next_action`, `notes`, `source`, `campaign_type`, `started_at`, `completed_at`, `task_type`, `owner_type`, `external_action_required` — read into raw row types for dev-harness/future use, never mapped (no invented frontend behavior). |
| `seo_authority_campaign_opportunities` junction | `AuthorityCampaign.opportunity_ids: string[]` | **Derived**, not stored — one extra per-website query, grouped by `campaign_id` (D1: junction is the source of truth). |
| `seo_authority_campaign_tasks` | `AuthorityCampaign.tasks: CampaignTask[]` + `progress_percentage` | **Derived**, not stored — `tasks` mapped to `{id, label, is_complete}`; `progress_percentage = round(complete/total*100)`, `0` if no tasks (D6: progress is computed, never a stored column). |
| campaign `approval_status` (4 values) | `CampaignApprovalStatus` (4 values, same domain) | Validated pass-through; unrecognized → `draft`. |

### AI Visibility / GEO

| Backend field | Frontend field | Rule |
| --- | --- | --- |
| `prompt_text`, `topic`, `brand_mentioned`, `competitors_mentioned`, `citation_sources`, `our_site_cited`, `gap_summary`, `recommended_next_step` | Same-named fields | Direct 1:1 pass-through. |
| `visibility_status` (4 values) | `PromptVisibilityStatus` (4 values, same domain) | Validated pass-through; unrecognized → `unknown`. |
| *(no frontend field)* | — | `brand_position`, `observed_on`, `source` — read into the raw row type, not mapped. |
| `topic`, `missing_answer_angle`, `suggested_content_type`, `related_keyword_or_question`, `recommended_next_action` | Same-named `AiContentGap` fields | Direct 1:1 pass-through. |
| `priority` (low/medium/high) | `ImpactLevel` | Validated pass-through; unrecognized → `medium`. |
| *(no frontend field)* | — | `related_prompt_id`, `gap_type`, `status`, `source` — read into the raw row type, not mapped. |
| `seo_ai_mentions` (`mention_type='brand'`, `is_our_site`) | `BrandMentionSummary` | `total_prompts_tracked`/`brand_mention_count`/`mention_rate_percentage` computed from `seo_ai_prompt_tracking.brand_mentioned` (authoritative per-observation flag, same math the mock uses). `where_brand_appears` **prefers** normalized `mention_type='brand'` rows (D2), enriched with the linked prompt's text/visibility via `prompt_tracking_id` when present; falls back to deriving directly from `brand_mentioned` prompt rows only if a website has prompts but zero mention rows. |
| `seo_ai_mentions` (`mention_type='competitor'`) | `CompetitorMentionSummary[]` | Grouped by `entity_name`. **Prefers** normalized mention rows (D2), enriched via `prompt_tracking_id`; falls back to deriving from `seo_ai_prompt_tracking.competitors_mentioned[]` (same shape/copy as the mock's own derivation) only when a website has prompts but zero competitor mention rows. |

Full code-level detail and rationale is in the extensive comments in `seoOffPageAuthoritySupabaseService.ts` and `seoAiVisibilitySupabaseService.ts`.

---

## 5. Cross-Workspace Fallback

Both `AuthorityBuilderPage.tsx` and `AiVisibilityPage.tsx` gained the same page-local `displayWebsite` override pattern as `DeclineDiagnosisPage.tsx` (Phase 14B.2) and `PagePerformancePage.tsx` (Phase 14A.2):

- **Supabase mode only.** Never touches mock mode, where a website with zero opportunities/prompts can be an intentional empty-state demo.
- **Finder ranks by data count, not first match** — `findAccessibleWebsiteWithAuthorityData()`/`findAccessibleWebsiteWithAiVisibilityData()` scan every accessible workspace/website and pick the one with the most rows, same rationale as Phase 14B.2 §10 (a test user can legitimately belong to a disposable smoke-test workspace alongside the richer UI seed workspace; "first found" would be non-deterministic).
- **Trigger conditions applied from the start** (learned from Phase 14B.2 §11's post-launch fix, not re-discovered here): the search effect fires when **either** the active website's onboarding is incomplete (nothing to wait for) **or** onboarding is complete but the relevant read settled with zero rows. This avoids the original Decline Diagnosis bug where requiring onboarding-complete-first meant the search could never fire for the common case (an auto-selected, never-onboarded smoke-test website).
- **Never mutates the shared `ActiveWebsiteContext`** — only a page-local `useState` override, exactly as the precedent pages do, since the active-website context cannot represent a cross-workspace switch.
- Does **not** hardcode any workspace/website id, name, or URL anywhere.

---

## 6. Derivation Details (Off-Page Campaigns + AI Mentions)

Two non-trivial derivations, both documented at length in code comments:

1. **`AuthorityCampaign.opportunity_ids` / `.tasks` / `.progress_percentage`** — `fetchSupabaseAuthorityCampaigns` issues one extra query each (junction rows, task rows) for the whole website, not per-campaign, to avoid N+1. Junction rows are grouped by `campaign_id` into an `opportunity_ids` map; task rows are grouped by `campaign_id`, mapped to `CampaignTask[]`, and used to compute `progress_percentage` per campaign.
2. **Brand/competitor mention summaries** — both `fetchSupabaseBrandMentionSummary` and `fetchSupabaseCompetitorMentionSummaries` fetch prompt rows and mention rows in parallel, then prefer the normalized `seo_ai_mentions` table (Stage 6 D2's intended replacement for "derive from prompt arrays") while falling back to the prompt-array derivation — with the *same output shape and fallback copy as the mock adapter* — only when a website genuinely has zero mention rows yet. In practice, the Stage 6 UI seed (13 mention rows: 4 brand / 5 competitor / 4 citation_source) exercises the preferred normalized path.

---

## 7. Writes/Mutations — None Wired (Deliberate, Task-Approved)

This phase is **read-only**, matching the task's explicit escape hatch ("if current UI only reads, keep this phase read-only and explicitly document which writes remain mock-only"):

- **`updateAuthorityOpportunityStatus`** (Off-Page) stays mock-only in every mode. The current UI's status buttons (`OpportunityCard.tsx`) fire target `status` values that do **not** provide a complete, legal path through Stage 6's guarded `seo_authority_opportunity_transition` RPC's state machine. Concretely: "Mark in progress" fires `status: "in_progress"` from whatever state a non-risky opportunity is currently in (`suggested` or `shortlisted`, since those are the only reachable states given the button set), but the RPC's `start` action only accepts `from_status IN ('approval_required', 'expert_review_requested')` — there is no "Request approval" or "Request expert review" button in the current UI to legally reach one of those states first. Wiring this write now would mean every "Mark in progress" click raises a real "Illegal transition" error — not a genuine permission denial (which the task correctly says must never be masked), but a UI/workflow mismatch that needs new buttons to fix, which is out of this phase's "do not rewrite pages unless necessary to render Supabase data" scope. The same reasoning applies to "Reject"/"Send to Expert Review"/"Mark as Avoided" for opportunities not already in a state those actions accept.
- **`createAuthorityCampaign`** stays mock-only. The mock creates a campaign + its `opportunity_ids`/`tasks` in one call; Stage 6 needs a campaign INSERT plus separate junction and task INSERTs (and the junction's integrity trigger enforces same-workspace/website — fine, but it's still a multi-statement write with its own error-handling shape not designed this phase).
- **`updateAiVisibilityItemStatus`** (AI Visibility) stays mock-only. **No live UI caller exists** — `AiVisibilityPage.tsx` never invokes it (verified by reading the page) — so unlike the Off-Page case there is no user-facing behavior to preserve or break; it is simply unwired, matching the precedent of `performanceService.fetchDiagnosisForPage` being adapter-wired but caller-less in Phase 14B.2. (Note: Stage 6 AI Visibility writes are plain-RLS, no transition RPC needed — this is a scope/priority choice, not a workflow-mismatch one.)
- **`generateMockAiVisibilityRefresh`** stays mock-only in every mode — it is explicitly a mock-data generator by name and design, same precedent as `performanceService.generateMockPerformanceRefresh` (Phase 14A.2), which also stayed mock-only.

**Recommended follow-up** (not done here): a future phase could add explicit "Request approval" / "Request expert review" buttons to `OpportunityCard.tsx` that call the RPC's `request_approval`/`request_expert_review` actions, completing the legal path so "Mark in progress"/"Mark completed"/"Reject" can then be safely wired through `seo_authority_opportunity_transition` without masking real denials — following the exact non-masking write pattern established in Phase 13D (`ApprovalTransitionError`) and Phase 13E (`ContentTransitionError`).

---

## 8. Verification Performed (Static + No-Session Browser)

- **`npx tsc --noEmit -p tsconfig.app.json`** — passed, no errors.
- **`npm run build`** — passed, no errors (pre-existing chunk-size warning only, unrelated).
- **Mock mode, browser preview:** `/seo/off-page` renders identically to before this phase (9 mock opportunities, spam risk review, filters, campaign list — verified via accessibility snapshot). `/seo/ai-visibility` renders identically (4 mock prompts, brand/competitor summaries, content gaps). Zero console errors on either page.
- **Supabase mode, no session, browser preview:** `/seo/dev/auth-test` → all four new Phase 15A buttons render and are click-guarded correctly (disabled until a website id is available, same as every prior phase's diagnostics). Clicking "Test Off-Page Authority Service" / "Test AI Visibility Service" with no signed-in session produced the expected graceful warnings — `seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityRows: no authenticated Supabase user (session missing).` and the AI Visibility equivalent — with **zero console errors**, matching the established no-session fallback behavior exactly.
- **Not performed:** a signed-in live test against the TEST project's seeded Stage 6 data. See §10.

---

## 9. Manual Test Steps — Mock Mode

1. No `.env` needed (or `VITE_SEO_DATA_MODE=mock`).
2. `npm run dev`, visit `/seo/off-page` and `/seo/ai-visibility`.
3. Confirm identical behavior to before Phase 15A: seeded mock opportunities/campaigns/prompts/content gaps, filters, spam risk review, status buttons, campaign builder all work exactly as before.

---

## 10. Recommended Live-Test Steps (Not Completed This Task)

**Prerequisite:** `.env` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (pointing at `Digi_SEO_Test`), `VITE_SEO_DATA_MODE=supabase` — already configured in this environment's `.env.local`. A real password for one of the 5 shared TEST auth users (`seo-owner-test@example.com`, `seo-admin-test@example.com`, `seo-team-test@example.com`, `seo-client-test@example.com`, `seo-nonmember-test@example.com`) is required and was not available in this task (by design, no password is ever stored in this repo).

1. Sign in at `/seo/dev/auth-test` as a user who is a member of workspace `44444444-0000-0000-0001-000000000001` (the base UI seed workspace).
2. Click **"Find website with Off-Page Authority data"** — expect it to report the UI seed workspace, website `https://ui-seed-digibility.example`, opportunity count **9**.
3. Click **"Test Off-Page Authority Service"** — expect `9 opportunities`, a status breakdown matching the seed (suggested: 2, shortlisted/approval_required/in_progress/expert_review_requested/completed/rejected/avoided: 1 each), `4 campaign(s)`, `5 activity row(s)`.
4. Click **"Find website with AI Visibility data"** — expect the same website, prompt count **9**.
5. Click **"Test AI Visibility Service"** — expect `9 prompt(s)`, a visibility breakdown (not_visible: 3, partially_visible: 3, visible: 2, unknown: 1), `6 content gap(s)`, `13 mention(s)` with a type breakdown (brand: 4, competitor: 5, citation_source: 4).
6. Visit `/seo/off-page` — expect it to render the 9 seeded opportunities on "UI Seed Demo Site" (via the cross-workspace fallback if that isn't the auto-selected active website), including the 2 safety-demo rows (`avoided`/`rejected` with `spam_risk_flags`), 4 campaigns with derived progress percentages, no console errors.
7. Visit `/seo/ai-visibility` — expect it to render the 9 seeded prompt observations (including the 3-point time-series for `"best seo agency for small business"`), brand/competitor mention summaries sourced from the 13 seeded mention rows, and 6 content gaps.
8. Confirm the write-side buttons (status changes, campaign creation) still succeed via mock fallback in Supabase mode (per §7, they are intentionally not wired to Supabase this phase) — this is expected, not a bug.

---

## 11. Known Limitations

- **Demo/manual seed data only.** All Stage 6 rows on the TEST project come from `seo_seed_stage6_offpage_ai_visibility_ui_extension.sql` — hand-written demo content, not derived from real signals.
- **No real crawler/GSC/GA4/LLM/scraper/outreach/review-generation/backlink-automation/external-API anywhere** — every row's `source` is `manual_seed`; nothing in this phase or Stage 6 calls an external API or model.
- **No production apply.** This phase only reads from the TEST Supabase project; production is untouched and remains gated per `BACKEND_MILESTONE_HANDOFF.md`.
- **Writes remain 100% mock-only** — see §7 for the full reasoning and the recommended follow-up phase.
- **No live signed-in browser test performed this task** — see §10 for the exact steps to complete it once a test-user password is available.
- **`seo_authority_activity` has no frontend history/timeline UI** — the raw read exists (`fetchSupabaseAuthorityActivity`) for the dev harness and any future component, but nothing renders it in the app yet.
- **The two Stage 6 transition RPCs are unused by the frontend** — `seo_authority_opportunity_transition` / `seo_authority_campaign_transition` exist and are smoke-tested but not called from any UI (see §7).
