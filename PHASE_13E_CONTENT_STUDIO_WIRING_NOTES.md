# Phase 13E — Content Studio Service Wiring

Wires `contentStudioService` to real Supabase (Stage 3) tables behind the Phase 13A mock/Supabase data-mode switch. In mock mode the app behaves exactly as before. In Supabase mode, reads and content-authoring writes attempt a real Supabase call and gracefully fall back to mock on failure (missing config, no session, RLS denial, network error); **workflow-status writes go through the Stage 3 `seo_content_transition` RPC and never fall back to mock on a real permission/state rejection** — see §4.

**No real LLM generation exists yet.** **No competitor scraping exists yet.** **No CMS publishing exists yet.** Storage/asset upload is deferred entirely this phase (the current UI never uploads real bytes). Production remains untouched.

---

## 1. Files Changed

**Created:**
- `src/services/supabase/seoContentStudioSupabaseService.ts` — the full Stage 3 read/write surface (opportunities, keyword plan, competitor summaries, wireframe, format input, draft + sections + revisions), `ContentTransitionError`.
- `PHASE_13E_CONTENT_STUDIO_WIRING_NOTES.md` — this file.

**Changed:**
- `src/services/contentStudioService.ts` — all 15 exported functions wired. Same function signatures and return types as before.
- `src/pages/seo/dev/SupabaseAuthTestPage.tsx` — added "Test content opportunity service", "Test content detail service", "Create dev content opportunity", and "Run safe content transition" dev-only buttons/results.
- `SERVICE_LAYER_WIRING_PLAN.md` — status update (§12); corrected §10/§11's "Content Studio is NOT wired" notes to point here.

**Not changed:** any Page Performance / Decline Diagnosis / Off-Page / AI Visibility / Competitor / Roadmap / Reports / Admin service, `src/services/serviceAdapter.ts`, any `src/mocks/*` file, any customer-facing page beyond what already called the now-wired service, any type, any migration, the reference Digibility app.

---

## 2. Services Wired

| Service function | Mock path | Supabase path (new) | Adapter |
|---|---|---|---|
| `fetchContentOpportunities(websiteId)` | `listContentOpportunities()` | `fetchSupabaseContentOpportunities()` | standard fallback |
| `createCustomContentOpportunity(website, input)` | `createCustomOpportunity()` | `createSupabaseCustomContentOpportunity()` — direct INSERT | standard fallback |
| `startContentPlan(id)` | advances to `plan_started` | RPC `mark_plan_ready` | **never masked** |
| `fetchKeywordPlan(id)` | `ensureKeywordPlan()` (auto-creates) | `fetchSupabaseKeywordPlan()` (auto-creates) | standard fallback |
| `fetchCompetitorContentSummary(id, website)` | `ensureCompetitorSummaries()` (auto-creates) | `fetchSupabaseCompetitorContentSummary()` (auto-creates) | standard fallback |
| `fetchWireframe(id)` | `getWireframe()` | `fetchSupabaseWireframe()` | standard fallback |
| `generateWireframe(id, website)` | `generateWireframeMock()` | `generateSupabaseWireframe()` — UPSERT content + tolerant `start_wireframe` | standard fallback |
| `approveWireframe(id)` | `approveWireframeMock()` | `approveSupabaseWireframe()` — RPC `approve_wireframe_internal` then UPDATE `is_approved` | **never masked** |
| `fetchFormatInput(id)` | `getFormatInput()` | `fetchSupabaseFormatInput()` | standard fallback |
| `saveFormatInput(id, input)` | `saveFormatInputMock()` | `saveSupabaseFormatInput()` — UPSERT | standard fallback |
| `fetchDraft(id)` | `getDraft()` | `fetchSupabaseDraft()` | standard fallback |
| `generateDraft(id)` | `generateDraftMock()` | `generateSupabaseDraft()` — INSERT draft+sections + tolerant `start_draft` | standard fallback |
| `updateDraftSection(id, sectionId, action, content?)` | `updateDraftSectionMock()` | `updateSupabaseDraftSection()` — direct UPDATE | standard fallback |
| `regenerateDraftSection(id, sectionId)` | `regenerateDraftSectionMock()` | `regenerateSupabaseDraftSection()` — UPDATE + append `seo_content_section_revisions` row | standard fallback |
| `addDraftFeedback(id, role, text)` | pushes to `opportunity.comments` | RPC `comment` action | **never masked** |
| `updateContentStatus(id, status)` | sets the field directly | RPC (status-mapped, see §3) | **never masked** |

---

## 3. Supabase Tables/RPCs/Storage Used

Stage 3 only, all previously test-verified (see `BACKEND_MILESTONE_HANDOFF.md`):
- `seo_content_opportunities` (read; direct INSERT for custom titles; **never** a direct status UPDATE)
- `seo_content_keyword_plans`, `seo_content_competitor_summaries` (read + auto-create on first read — deterministic template text only)
- `seo_content_wireframes` (read; UPSERT content; UPDATE `is_approved` only after the RPC's `approve_wireframe_internal` succeeds)
- `seo_content_format_inputs` (read; UPSERT — `uploaded_file_name` never persisted, see §7)
- `seo_content_drafts`, `seo_content_draft_sections` (read; INSERT on first generate; per-section UPDATE for approve/reject/edit/regenerate)
- `seo_content_section_revisions` (INSERT only — append-only regeneration trail)
- `seo_content_comments` (read only — every write goes through the RPC's `comment` action)
- `seo_content_transition(uuid, text, text)` RPC — the only path for opportunity status changes and for comments

**Not used this phase:** `seo_content_assets`, the private `seo-content-assets` Storage bucket, `seo_content_activity` (written server-side by the RPC; no UI surface reads it back yet), `seo_content_client_can_see_draft()` / `seo_content_assert_same_workspace()` (both used internally by Stage 3 RLS/triggers — never called directly from the frontend).

### Status mapping (the one non-trivial design decision this phase)

The app's `ContentWorkflowStatus` (12 values, no internal/client-review split) is mapped both ways against Stage 3's status enum (14 values, tracks internal vs. client review separately):

| Direction | Mapping |
|---|---|
| **DB → app** (read) | `idea`→`idea_suggested` · `plan_ready`/`wireframe_in_progress`→`plan_started` · `wireframe_internal_review`/`wireframe_client_review`→`wireframe_ready` · `wireframe_changes_requested`→`rejected` · `wireframe_approved`→`wireframe_approved` · `draft_in_progress`→`draft_ready` · `draft_internal_review`/`draft_client_review`→`draft_in_review` · `draft_changes_requested`→`rejected` · `draft_approved`→`draft_approved` · `ready_for_manual_publish`→`ready_for_publish` · `archived`→`completed` |
| **App → RPC action** (write, via `updateContentStatus`) | `draft_approved`→`approve_draft_internal` · `rejected`→`request_draft_changes` · `ready_for_publish`→`mark_ready_for_manual_publish` · `completed`→`archive` · `expert_review_requested`→ **no mapping; throws `ContentTransitionError`** (see §7) |

---

## 4. Mock Fallback Behavior

Same two-tier pattern established in Phase 13D:

**Reads and content-authoring writes** (fetches, `createCustomContentOpportunity`, `generateWireframe`, `saveFormatInput`, `generateDraft`, `updateDraftSection`, `regenerateDraftSection`) use the standard `runWithServiceAdapter()` — missing config → mock; no session → clear throw → mock + one console warning; authenticated with zero rows → legitimate empty state, not a fallback.

**Explicit workflow-transition writes** (`startContentPlan`, `approveWireframe`, `updateContentStatus`, `addDraftFeedback`) go through a dedicated `runContentWrite()` helper in `contentStudioService.ts`:

1. **Config missing/invalid, or no session** → falls back to mock (infra-level failure).
2. **Authenticated + the RPC itself rejects the call** (invalid transition for the current status, unsupported action, not a member) → throws `ContentTransitionError`, which **propagates as a real error** — never masked by mock success. A workflow rule that Stage 3 enforces must be visible, not silently bypassed.

`generateSupabaseWireframe`/`generateSupabaseDraft` additionally use a `tryTransition()` helper internally: it tolerates Stage 3's own "Invalid transition ... from ..." message as a benign no-op (needed because "Regenerate wireframe" reuses the same generate action, and `start_wireframe`/`start_draft` aren't re-callable once the opportunity is already past that step) — any other error still propagates normally.

No raw Supabase error message reaches customer-facing UI as-is.

---

## 5. Manual Test Steps — Mock Mode

1. No `.env` needed (or `VITE_SEO_DATA_MODE=mock`).
2. `npm run dev`, visit `/seo/content-studio`.
3. Confirm identical behavior to before Phase 13E: seeded opportunities, start plan → keyword plan/competitor summary appear → generate/approve wireframe → save format input → generate draft → approve/reject/edit/regenerate sections → approve/reject draft → publish queue actions all work exactly as before.

---

## 6. Manual Test Steps — Supabase Mode via `/seo/dev/auth-test`

**Prerequisite:** `.env` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (test project), `VITE_SEO_DATA_MODE=supabase`; Stage 1–3 applied.

1. Sign in with a test-project user that has `user_module_access(module='seo')` granted.
2. **"Test website service"** → **"Create test website"** if needed → **"Test website service"** again to confirm a real website id.
3. **"Test content opportunity service"** — on a fresh site this legitimately reports `0 content opportunity(ies) found`. Not a failure.
4. **"Create dev content opportunity"** — creates "Dev Test Content Opportunity" (status `idea_suggested`). Click **"Test content opportunity service"** again to confirm `1 content opportunity(ies) found`.
5. **"Test content detail service"** — on the fresh opportunity, expect `Keyword plan: no · Wireframe: no · Draft: no` (nothing generated yet — this button only reads, it doesn't create).
6. **"Run safe content transition"** (dev-only, `mark_plan_ready` only) — expect `Transition applied — new status: plan_started.`
7. To exercise the full workflow, drive `/seo/content-studio` directly against the same test website: select the opportunity, generate the wireframe (auto-creates a keyword plan + advances to `wireframe_in_progress` internally), approve it, save a format input, generate the draft, approve/reject sections, approve or reject the draft, then use the Publish Queue actions.
8. To see the "real rejection surfaces, not masked" behavior: attempt "Send to expert review" on a draft — Stage 3 has no manager-facing equivalent yet, so this surfaces `ContentTransitionError: Stage 3 has no workflow transition for status "expert_review_requested" yet...` instead of silently succeeding.
9. Sign out — all test-panel results reset.

---

## 7. Known Limitations

- **No real LLM generation.** Wireframe/keyword-plan/competitor-summary/draft content is deterministic template text, identical in spirit to the mock adapter's own placeholder content — never a real AI/crawler call.
- **No real competitor scraping.** Competitor summary URLs are clearly `example-competitor-*.com` placeholders.
- **No CMS publishing.** `ready_for_manual_publish`/`archive` are status markers only — no action anywhere reaches a live website or CMS.
- **Storage/assets deferred entirely.** `seo_content_assets` and the private bucket are untouched this phase — the current `FormatInputSection` UI only stores a filename **string** for a "file_reference" format ("Only the filename is stored for now — file contents aren't processed yet"), so `uploaded_file_name` is silently **not persisted** in Supabase mode (format_type/reference_url/custom_instructions are fully preserved). Wiring real Storage requires an upload flow the UI doesn't have yet — a future phase.
- **`expert_review_requested` has no Stage 3 equivalent yet.** The RPC's own `request_expert_review` action is gated to client-review states and doesn't apply to this manager-driven flow (Expert Support is a later stage per the migration's own comment). Requesting this status throws a clear `ContentTransitionError` rather than silently no-op'ing or masking with mock success. `ContentStudioPage`'s `statusMutation` has no `onError` handler, so this currently surfaces via the browser console/React Query devtools rather than a visible banner — a pre-existing UI limitation, not something this phase changes (matches Phase 13D's identical limitation for approval mutations).
- **`"rejected"` status is a best-effort mapping.** Stage 3 has no literal "rejected" status; both `wireframe_changes_requested` and `draft_changes_requested` read back as the app's `"rejected"` (closest semantic match — sent back for rework), and a write-side "reject" maps to `request_draft_changes`. This round-trips correctly for drafts but is an approximation, not an exact model match.
- **Keyword plan / competitor summaries auto-create on first read.** This differs from Stage 2's stricter precedent (`generateRecommendationsFromAudit` stays mock-only in every mode) because keyword-plan/competitor-summary content is genuinely template-only (not crawler/LLM-dependent) and the real UI's `WireframeSection` only renders once a keyword plan exists — without auto-create, Supabase mode would have no way to reach the wireframe/draft workflow at all.
- Same auth/session prerequisites as Phase 13B/13C/13D — no in-app login UI exists yet; use `/seo/dev/auth-test` to establish a session for testing.

---

## 8. Recommended Next Phase

**Phase 13F: wire dashboard summaries** (read-only aggregation over the now-wired services), then **admin preview (read-only)**, completing the recommended wiring order in `SERVICE_LAYER_WIRING_PLAN.md` §6. Real Storage/asset upload for Content Studio format inputs remains a separate, later scope item.
