# Supabase Stage 6 — Off-Page Authority + AI Visibility/GEO — UI Seed Extension Guide

**Purpose:** how to apply and verify the Stage 6 UI seed extension
(`supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`) on a
**disposable TEST Supabase project**, what it creates, expected counts, how to
exercise it in the UI later, and how to remove it.

> **TEST / demo / manual_seed data only.** Every row this seed creates is
> hand-written demo content with `source = 'manual_seed'`. There is **no real
> crawler, GSC/GA4, LLM, scraping, cron, outreach, review generation, backlink
> automation, or external API** anywhere in this seed. Off-page rows are
> **opportunities and decisions only**; the `avoided`/`rejected` rows (with
> `spam_risk_flags`) exist specifically to demonstrate steering **away** from
> risky tactics. **Never run on production.**

---

## 1. Purpose

Populate the eight Stage 6 tables under the **existing base UI seed
workspace/website** so that, once the Off-Page Authority and AI Visibility
services are wired to Supabase (a later phase), the UI renders realistic,
business-friendly data instead of empty states. This is a **data seed**, not a
correctness/RLS test — that is covered by
`supabase/test/seo_stage6_offpage_ai_visibility_smoke_test.sql`.

---

## 2. Prerequisites

Applied to the **TEST** project, in order:

1. **Stage 1 migrations** (`20260711120001`–`…003`) — base workspace/website/
   members tables + RLS helpers.
2. **Stage 6 migrations** (`20260711120017`–`…023`) — the 8 Off-Page + AI
   Visibility tables (+ 2 transition RPCs + junction integrity trigger).
3. **Base UI seed dataset** (`supabase/test/seo_seed_ui_test_dataset.sql`) —
   creates the workspace/website this seed attaches to and the owner/team_member
   members it derives `created_by` from.

The seed **fails fast with a clear error** if the base UI seed workspace/website
or the Stage 6 tables are missing (see its SECTION 0 guards). It does **not**
require the Stage 4 or Stage 5 seed extensions.

**No manual UUID paste is required.** The seed **derives** `created_by` from the
base workspace's existing `seo_workspace_members` (owner + team_member). It does
not create Supabase Auth users and does not insert into `auth.users`.

---

## 3. What it creates

All rows use the fixed UUID prefix **`a6000000-`** (unused by any prior seed or
smoke test), attached to:

- workspace `44444444-0000-0000-0001-000000000001`
- website `44444444-0000-0000-0002-000000000001`
  (`https://ui-seed-digibility.example`)

| Table | Rows | Coverage |
| --- | --- | --- |
| `seo_authority_opportunities` | **9** | all 7 `opportunity_type`s; all 8 statuses; varied impact/effort/risk/confidence/fix_owner; 2 safety rows (`avoided`/`rejected` with `spam_risk_flags`); mix of `target_url` + URL-less |
| `seo_authority_campaigns` | **4** | `approval_status` = draft / pending_approval / approved / rejected; **no** `progress_percentage` (derived on read) |
| `seo_authority_campaign_tasks` | **11** | across 3 campaigns; complete/incomplete; `external_action_required` true/false; `owner_type` variety; unique `position` per campaign |
| `seo_authority_campaign_opportunities` | **6** | campaign↔opportunity links (all same workspace/website → junction integrity passes) |
| `seo_authority_activity` | **5** | demo history (opportunity + campaign transitions), append-only, one subject each |
| `seo_ai_prompt_tracking` | **9** | all 4 `visibility_status`; a **3-point time-series** (same `prompt_text`, three `observed_on` dates); varied brand_mentioned/brand_position/competitors/citations/our_site_cited |
| `seo_ai_content_gaps` | **6** | priority low/medium/high; status open/planned/addressed/dismissed; several linked to prompts |
| `seo_ai_mentions` | **13** | `mention_type` brand/competitor/citation_source; our-site + competitor/source citations; varied position/sentiment/prominence/is_our_site; several linked to prompts |

---

## 4. How to run

**Option A — Supabase SQL Editor (recommended for humans).** Open the TEST
project's SQL Editor, paste the full contents of
`supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql`, and run.
Read the verification result grids and the `… SEED EXTENSION — complete` marker.

**Option B — Supabase CLI (linked TEST project).**

```
supabase db query --linked -f supabase/test/seo_seed_stage6_offpage_ai_visibility_ui_extension.sql
```

The script runs as the privileged role (RLS bypassed for seeding, same as every
other seed). It is **idempotent** — every INSERT uses `ON CONFLICT DO NOTHING`,
so re-running does not duplicate or change counts.

---

## 5. Expected verification counts

The seed prints these at the end (and they were confirmed on TEST):

| Entity | Count |
| --- | --- |
| authority opportunities | 9 |
| authority campaigns | 4 |
| campaign tasks | 11 |
| campaign ↔ opportunity links | 6 |
| authority activity | 5 |
| AI prompt tracking | 9 |
| AI content gaps | 6 |
| AI mentions | 13 |

Breakdowns:

- **Opportunity statuses:** suggested ×2; shortlisted, approval_required,
  in_progress, expert_review_requested, completed, rejected, avoided ×1 each.
- **Opportunity types:** backlink ×2, review ×2; citation, mention, partnership,
  pr, social_community ×1 each.
- **Campaign approval statuses:** draft, pending_approval, approved, rejected ×1 each.
- **Prompt visibility statuses:** not_visible ×3, partially_visible ×3,
  visible ×2, unknown ×1.
- **Mention types:** brand ×4, competitor ×5, citation_source ×4.
- **Time-series:** `"best seo agency for small business"` appears as **3**
  observations on different `observed_on` dates.

---

## 6. UI testing note

This seed only populates the backend. The Off-Page Authority and AI Visibility
frontend is still **mock-only** — a later service-wiring phase (per
`SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_PLAN.md` §13) will map these
rows into the existing flat types behind the mock/Supabase data-mode adapter.
Once that lands and `VITE_SEO_DATA_MODE=supabase` is set against this TEST
project, the Off-Page and AI Visibility pages for **"UI Seed Demo Site"** will
render this demo data (opportunities, campaigns + tasks, spam-risk/avoided
examples, prompt-tracking time-series, content gaps, and brand/competitor/
citation mentions). Until then, the data is queryable in SQL but not shown in the
app.

---

## 7. Warnings

- **TEST only — never production.** Demo data with `source = 'manual_seed'`.
- **No real integrations implied.** No crawler/GSC/GA4/LLM/scraping/cron/outreach/
  review-generation/backlink-automation/external-API. The `avoided`/`rejected`
  spam-flagged rows record decisions to steer away from risky tactics; nothing is
  ever executed.
- **Additive + non-destructive.** Pure DML against already-applied Stage 6 tables;
  it does not alter schema/RLS/triggers, does not TRUNCATE/DROP, and does not
  modify any base UI seed, Stage 4/5 seed, or smoke-test row.
- **Not service-wired.** Seeding does not wire the UI; that is a separate phase.

---

## 8. Optional teardown

A commented-out teardown block at the bottom of the seed deletes **only** this
extension's rows (by the `a6000000-` prefix), children before parents. Uncomment
and run manually on TEST to remove the Stage 6 demo data. It does **not** touch
the base UI seed, the Stage 4/5 extensions, smoke-test data, or any other row.

```
-- DELETE FROM public.seo_ai_mentions                     WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_ai_content_gaps                 WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_activity              WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_campaign_opportunities WHERE campaign_id::text LIKE 'a6000000-%' OR opportunity_id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_campaign_tasks        WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_campaigns             WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_opportunities         WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_ai_prompt_tracking              WHERE id::text LIKE 'a6000000-%';
```

---

## 9. Status

Applied + verified on the disposable TEST project `Digi_SEO_Test` on 2026-07-11
(counts above; idempotent re-run confirmed). Stage 6 remains **not service-wired**
and **production untouched**. See `CURRENT_PROJECT_STATUS.md` for authoritative
status and `SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md` §7e for the
seed checkpoint.
