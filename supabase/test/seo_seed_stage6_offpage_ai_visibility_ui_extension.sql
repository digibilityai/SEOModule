-- =============================================================================
-- SEO UI TEST DATASET — STAGE 6 OFF-PAGE AUTHORITY + AI VISIBILITY/GEO EXTENSION
-- =============================================================================
--                          ****  TEST DATA ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Purpose: add realistic, business-friendly Off-Page Authority + AI Visibility /
-- GEO demo data under the EXISTING base UI seed workspace/website, so that once
-- the Off-Page + AI Visibility services are wired to Supabase, the UI has
-- non-empty data to render. This is a plain DATA seed extension, NOT a
-- correctness/RLS test (see supabase/test/seo_stage6_offpage_ai_visibility_smoke_test.sql
-- for that) — run once as the privileged SQL Editor ("postgres") role, which
-- bypasses RLS by design for seeding.
--
-- This script:
--   - REQUIRES Stage 1 + Stage 6 migrations already applied to the target
--     project (20260711120001-…003 for the base workspace/website tables, and
--     20260711120017-…023 for the 8 Stage 6 tables). It fails fast if either the
--     base UI seed workspace/website or the Stage 6 tables are missing.
--   - REQUIRES the base UI seed dataset (supabase/test/seo_seed_ui_test_dataset.sql)
--     already applied — it attaches to that seed's workspace/website
--     (44444444-…) and refuses to run if they are missing (SECTION 0).
--   - DERIVES created_by from the base workspace's existing
--     seo_workspace_members (owner + team_member) — NO manual UUID paste is
--     required, and it does NOT create Supabase Auth users or insert into
--     auth.users.
--   - Does NOT use, require, or mention a service role key.
--   - Does NOT modify any migration file and does NOT alter table/RLS/trigger
--     definitions — pure DML (INSERT / ON CONFLICT) against already-applied
--     Stage 6 tables.
--   - Does NOT TRUNCATE or DROP anything, does NOT disable RLS, and does NOT
--     delete or modify any existing row from the base UI seed, the Stage 4/5
--     extensions, or any smoke test.
--   - Does NOT touch or reference production. Target the TEST project only.
--   - Is idempotent: every INSERT uses a fixed literal UUID (or the junction PK)
--     with ON CONFLICT DO NOTHING, so re-running is safe and creates no
--     duplicates.
--   - Uses the UUID prefix "a6000000-" for every row it creates — a prefix not
--     used by the base UI seed ("44444444-"), the Stage 4 seed extension
--     ("66666666-"), the Stage 5 seed extension ("88888888-"), or any smoke
--     test ("33333333-"/"55555555-"/"77777777-"/"99999999-"/"aaaaaaaa-"/
--     "bbbbbbbb-"), so it cannot collide with or overwrite any of them.
--   - Contains NO real crawler / GSC / GA4 / LLM / scraping / cron / outreach /
--     review-generation / backlink-automation / external-API behavior. Every row
--     is manual demo data (`source = 'manual_seed'` on every table that has a
--     source column). Off-page rows are OPPORTUNITIES + DECISIONS only; the
--     `avoided`/`rejected` + spam_risk_flags rows exist to demonstrate steering
--     AWAY from risky tactics.
--
-- See SUPABASE_STAGE6_OFFPAGE_AI_VISIBILITY_SEED_EXTENSION_GUIDE.md for full run
-- instructions, expected verification counts, and how to exercise this data in
-- the local UI once Off-Page / AI Visibility service wiring lands (not part of
-- this script).
-- =============================================================================

-- =============================================================================
-- SECTION 0 — DEPENDENCY GUARDS (REQUIRED) + created_by DERIVATION
-- =============================================================================
-- 0a. Base UI seed workspace + website must exist.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.seo_workspaces
        WHERE id = '44444444-0000-0000-0001-000000000001') = 0
     OR (SELECT count(*) FROM public.seo_websites
        WHERE id = '44444444-0000-0000-0002-000000000001'
          AND workspace_id = '44444444-0000-0000-0001-000000000001') = 0 THEN
    RAISE EXCEPTION 'Base UI seed dataset must be applied before this Stage 6 extension. Run supabase/test/seo_seed_ui_test_dataset.sql first (see SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md), then re-run this script.';
  END IF;
END $$;

-- 0b. Stage 6 backend tables must exist.
DO $$
BEGIN
  IF to_regclass('public.seo_authority_opportunities') IS NULL
     OR to_regclass('public.seo_authority_campaigns') IS NULL
     OR to_regclass('public.seo_authority_campaign_tasks') IS NULL
     OR to_regclass('public.seo_authority_campaign_opportunities') IS NULL
     OR to_regclass('public.seo_authority_activity') IS NULL
     OR to_regclass('public.seo_ai_prompt_tracking') IS NULL
     OR to_regclass('public.seo_ai_content_gaps') IS NULL
     OR to_regclass('public.seo_ai_mentions') IS NULL THEN
    RAISE EXCEPTION 'Stage 6 migrations (20260711120017-…023) must be applied before this seed. Apply them to the TEST project first, then re-run.';
  END IF;
END $$;

-- 0c. Derive created_by from the base workspace's existing members (no paste).
--     owner_user_id -> stamped on owner-driven rows; team_user_id -> the rest
--     (falls back to owner if the workspace has no active team_member).
SELECT set_config('seoseed6.owner_user_id',
  coalesce((SELECT user_id::text FROM public.seo_workspace_members
            WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
              AND seo_role = 'owner' AND status = 'active'
            ORDER BY created_at LIMIT 1), ''), false);

SELECT set_config('seoseed6.team_user_id',
  coalesce((SELECT user_id::text FROM public.seo_workspace_members
            WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
              AND seo_role = 'team_member' AND status = 'active'
            ORDER BY created_at LIMIT 1),
           nullif(current_setting('seoseed6.owner_user_id', true), '')), false);

-- 0d. Guard: the derived owner must be a real UUID (i.e. the base seed created
--     its members). Never proceed with an empty/invalid created_by.
DO $$
DECLARE
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
BEGIN
  IF coalesce(current_setting('seoseed6.owner_user_id', true), '') !~ v_uuid_pattern THEN
    RAISE EXCEPTION 'Could not derive an owner user from seo_workspace_members for the base UI seed workspace. Ensure the base UI seed dataset (with its owner member) is applied, then re-run.';
  END IF;
  IF coalesce(current_setting('seoseed6.team_user_id', true), '') !~ v_uuid_pattern THEN
    -- fall back to owner (already guaranteed valid above)
    PERFORM set_config('seoseed6.team_user_id', current_setting('seoseed6.owner_user_id'), false);
  END IF;
END $$;

SELECT '=== STAGE 6 OFF-PAGE + AI VISIBILITY SEED EXTENSION — starting ===' AS step;

-- =============================================================================
-- UUID MAP (all fixed, prefix a6000000- ; 4th group's leading nibble groups
-- rows by category). Attaches to base workspace 44444444-0000-0000-0001-…001
-- and website 44444444-0000-0000-0002-…001 (https://ui-seed-digibility.example):
--   0001 = authority opportunities (9)
--   0002 = authority campaigns (4)
--   0003 = campaign tasks (11)
--   0004 = (junction has no id; PK = campaign_id + opportunity_id)
--   0005 = authority activity (5, demo history)
--   0006 = AI prompt tracking (9, incl. a 3-point time-series)
--   0007 = AI content gaps (6)
--   0008 = AI mentions (13)
-- =============================================================================

-- =============================================================================
-- SECTION A1 — AUTHORITY OPPORTUNITIES (9). Covers all 7 opportunity_type
-- values and all 8 statuses; varied impact/effort/risk/confidence/fix_owner;
-- two safety examples (avoided / rejected with spam_risk_flags); a mix of
-- target_url and URL-less rows.
-- =============================================================================
SELECT '=== A1: authority opportunities ===' AS step;

INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform,
   target_url, target_domain, suggested_action, why_it_matters, expected_authority_impact,
   effort, risk, confidence_percentage, requires_approval, fix_owner, status,
   spam_risk_flags, recommended_next_action, notes, source, created_by)
VALUES
  -- O1 backlink / shortlisted
  ('a6000000-0000-0000-0001-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'backlink', 'Guest article on a respected small-business blog', 'smallbizjournal.example',
   'https://smallbizjournal.example/write-for-us', 'smallbizjournal.example',
   'Pitch a helpful, non-promotional guest article with one contextual link back.',
   'A relevant editorial link from a trusted small-business publication builds durable authority.',
   'high', 'medium', 'low', 72, true, 'digibility_expert', 'shortlisted',
   '{}', 'Draft 3 topic ideas and a short outreach note for review.',
   'Editorial, relevance-first — no paid placement.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- O2 mention / suggested (URL present)
  ('a6000000-0000-0000-0001-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'mention', 'Unlinked brand mention on a local news roundup', 'localnews.example',
   'https://localnews.example/best-local-services', 'localnews.example',
   'Reach out to ask if an existing unlinked mention can become a link.',
   'Turning an existing mention into a link is low-effort authority you have already earned.',
   'medium', 'low', 'low', 60, true, 'client_action', 'suggested',
   '{}', 'Confirm the mention still exists, then send a friendly link request.',
   NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- O3 citation / in_progress
  ('a6000000-0000-0000-0001-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'citation', 'Consistent NAP citation on a major business directory', 'bizdirectory.example',
   'https://bizdirectory.example/add-listing', 'bizdirectory.example',
   'Create/claim the listing with name, address, phone matching the website exactly.',
   'Consistent citations reinforce local trust and help the business appear in local results.',
   'medium', 'low', 'low', 80, false, 'client_action', 'in_progress',
   '{}', 'Verify NAP matches the website footer before submitting.',
   NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- O4 review / approval_required (external-facing -> needs approval)
  ('a6000000-0000-0000-0001-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'review', 'Invite recent happy customers to leave an honest Google review', 'google_business',
   'https://g.page/r/ui-seed-demo/review', 'google.com',
   'Send a simple, no-incentive request to real recent customers to share honest feedback.',
   'Genuine, recent reviews improve trust and local prominence — never incentivized or fake.',
   'high', 'medium', 'medium', 55, true, 'client_action', 'approval_required',
   '{}', 'Approve the request wording, then send to the last 10 real customers.',
   'Honest reviews only — no incentives, no fabrication.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- O5 pr / expert_review_requested
  ('a6000000-0000-0000-0001-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'pr', 'Offer expert commentary to a journalist request (HARO-style)', 'journorequest.example',
   'https://journorequest.example/queries', 'journorequest.example',
   'Respond to a relevant reporter query with a concise, genuinely useful expert quote.',
   'Earned press coverage can produce a high-authority link and real brand visibility.',
   'high', 'high', 'medium', 48, true, 'digibility_expert', 'expert_review_requested',
   '{}', 'Have an expert review the draft quote for accuracy before sending.',
   NULL, 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- O6 social_community / suggested (URL-less pure idea)
  ('a6000000-0000-0000-0001-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'social_community', 'Answer relevant questions in a small-business community', 'smallbizcommunity.example',
   NULL, NULL,
   'Genuinely help in a community where the target audience already asks questions.',
   'Being consistently helpful builds brand recognition and natural referral traffic.',
   'low', 'low', 'low', 40, false, 'client_action', 'suggested',
   '{}', 'Pick one community and answer two questions a week — no link-dropping.',
   'Value-first participation, not link-dropping.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- O7 partnership / completed
  ('a6000000-0000-0000-0001-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'partnership', 'Co-marketing partnership with a complementary local service', 'partnerco.example',
   'https://partnerco.example/partners', 'partnerco.example',
   'Cross-refer and co-publish a genuinely useful resource with a non-competing partner.',
   'A real partnership drives referral traffic and an authentic, relevant link.',
   'high', 'high', 'low', 90, true, 'digibility_expert', 'completed',
   '{}', 'Publish the co-authored resource and add reciprocal partner links.',
   'Completed — resource published and links live.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- O8 backlink / avoided (SAFETY: spam risk flagged, steered away)
  ('a6000000-0000-0000-0001-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'backlink', 'Paid link package on a low-quality link network', 'linkfarm.example',
   'https://linkfarm.example/buy-links', 'linkfarm.example',
   'Do NOT proceed — this is a paid-link scheme on a low-trust network.',
   'Paid links on link farms risk penalties and provide no lasting value — avoided on purpose.',
   'low', 'low', 'high', 20, true, 'system_suggestion', 'avoided',
   ARRAY['paid_link_risk','pbn_like_site','low_trust']::text[],
   'No action — kept as a record of a risky tactic we chose to avoid.',
   'Flagged and avoided — demonstrates steering away from spam.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- O9 review / rejected (SAFETY: fake-review / mass-outreach risk, URL-less)
  ('a6000000-0000-0000-0001-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'review', 'Bulk-buy 5-star reviews from an unknown vendor', 'reviewvendor.example',
   NULL, NULL,
   'Do NOT proceed — buying fake reviews is deceptive and against platform policies.',
   'Fake reviews mislead customers and risk removal/penalties — rejected on principle.',
   'low', 'low', 'high', 15, true, 'system_suggestion', 'rejected',
   ARRAY['fake_review_risk','mass_outreach_risk','low_trust']::text[],
   'No action — rejected; recorded to show what we will not do.',
   'Rejected — fake reviews are never acceptable.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION A2 — AUTHORITY CAMPAIGNS (4). Covers draft / pending_approval /
-- approved / rejected. No progress_percentage column (D6 — derived on read).
-- =============================================================================
SELECT '=== A2: authority campaigns ===' AS step;

INSERT INTO public.seo_authority_campaigns
  (id, workspace_id, website_id, website_url, name, goal, campaign_type, approval_status,
   owner, due_date, started_at, completed_at, source, created_by)
VALUES
  -- C1 approved (in execution)
  ('a6000000-0000-0000-0002-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'Local Trust & Citations — Q3', 'Strengthen local authority via consistent citations and a real partnership.',
   'local_trust', 'approved', 'digibility_expert',
   current_date + 45, now() - interval '10 days', NULL, 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- C2 pending_approval
  ('a6000000-0000-0000-0002-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'Editorial Backlinks & PR', 'Earn a few high-quality editorial links through guest content and press.',
   'content_pr', 'pending_approval', 'digibility_expert',
   current_date + 60, NULL, NULL, 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- C3 draft
  ('a6000000-0000-0000-0002-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'Community & Social Proof', 'Build brand recognition through genuine community participation and reviews.',
   'community', 'draft', 'client_action',
   current_date + 30, NULL, NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- C4 rejected (SAFETY: spammy plan rejected)
  ('a6000000-0000-0000-0002-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'Aggressive Link Buying (rejected)', 'Proposed bulk paid links — rejected as high-risk and non-compliant.',
   'link_building', 'rejected', 'system_suggestion',
   NULL, NULL, NULL, 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION A3 — CAMPAIGN TASKS (11 across C1/C2/C3). Mix of complete/incomplete,
-- external_action_required true/false, and owner_type variety. position is
-- unique within each campaign.
-- =============================================================================
SELECT '=== A3: campaign tasks ===' AS step;

INSERT INTO public.seo_authority_campaign_tasks
  (id, workspace_id, website_id, website_url, campaign_id, opportunity_id, label, task_type,
   owner_type, is_complete, external_action_required, position, due_date, completed_at, created_by)
VALUES
  -- C1 (approved) — 4 tasks
  ('a6000000-0000-0000-0003-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000001', 'a6000000-0000-0000-0001-000000000003',
   'Claim & verify the primary business directory listing', 'citation',
   'client_action', true, true, 0, current_date + 5, now() - interval '6 days',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000001', 'a6000000-0000-0000-0001-000000000003',
   'Audit NAP consistency across the top 5 directories', 'citation',
   'digibility_expert', true, false, 1, current_date + 7, now() - interval '3 days',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000001', 'a6000000-0000-0000-0001-000000000007',
   'Publish the co-authored partner resource', 'partnership',
   'digibility_expert', false, true, 2, current_date + 20, NULL,
   current_setting('seoseed6.owner_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000001', NULL,
   'Add reciprocal partner links to the resource', 'partnership',
   'developer_needed', false, false, 3, current_date + 22, NULL,
   current_setting('seoseed6.owner_user_id')::uuid),

  -- C2 (pending_approval) — 4 tasks
  ('a6000000-0000-0000-0003-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000002', 'a6000000-0000-0000-0001-000000000001',
   'Draft 3 guest-article topic ideas', 'backlink',
   'digibility_expert', false, false, 0, current_date + 10, NULL,
   current_setting('seoseed6.owner_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000002', 'a6000000-0000-0000-0001-000000000001',
   'Send the outreach note to the target blog', 'backlink',
   'client_action', false, true, 1, current_date + 14, NULL,
   current_setting('seoseed6.owner_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000002', 'a6000000-0000-0000-0001-000000000005',
   'Prepare an expert quote for the journalist request', 'pr',
   'digibility_expert', false, true, 2, current_date + 8, NULL,
   current_setting('seoseed6.owner_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000002', NULL,
   'Expert review of all outreach wording before sending', 'review',
   'digibility_expert', false, false, 3, current_date + 9, NULL,
   current_setting('seoseed6.owner_user_id')::uuid),

  -- C3 (draft) — 3 tasks
  ('a6000000-0000-0000-0003-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000003', 'a6000000-0000-0000-0001-000000000006',
   'Choose one community to participate in consistently', 'social_community',
   'client_action', false, false, 0, current_date + 12, NULL,
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000003', 'a6000000-0000-0000-0001-000000000004',
   'Draft the honest customer-review request wording', 'review',
   'client_action', false, false, 1, current_date + 15, NULL,
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0003-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0002-000000000003', 'a6000000-0000-0000-0001-000000000002',
   'Confirm the existing unlinked mention still exists', 'mention',
   'system_suggestion', false, false, 2, current_date + 18, NULL,
   current_setting('seoseed6.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION A4 — CAMPAIGN ↔ OPPORTUNITY JUNCTION (6 links). Source of truth for
-- campaign membership. All campaign + opportunity rows are on the same base
-- workspace/website, so the junction integrity trigger passes. PK
-- (campaign_id, opportunity_id) makes this idempotent.
-- =============================================================================
SELECT '=== A4: campaign ↔ opportunity links ===' AS step;

INSERT INTO public.seo_authority_campaign_opportunities
  (workspace_id, website_id, website_url, campaign_id, opportunity_id, created_by)
VALUES
  -- C1 (Local Trust) <-> citation + partnership
  ('44444444-0000-0000-0001-000000000001', '44444444-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example', 'a6000000-0000-0000-0002-000000000001',
   'a6000000-0000-0000-0001-000000000003', current_setting('seoseed6.owner_user_id')::uuid),
  ('44444444-0000-0000-0001-000000000001', '44444444-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example', 'a6000000-0000-0000-0002-000000000001',
   'a6000000-0000-0000-0001-000000000007', current_setting('seoseed6.owner_user_id')::uuid),
  -- C2 (Editorial Backlinks & PR) <-> backlink + pr
  ('44444444-0000-0000-0001-000000000001', '44444444-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example', 'a6000000-0000-0000-0002-000000000002',
   'a6000000-0000-0000-0001-000000000001', current_setting('seoseed6.owner_user_id')::uuid),
  ('44444444-0000-0000-0001-000000000001', '44444444-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example', 'a6000000-0000-0000-0002-000000000002',
   'a6000000-0000-0000-0001-000000000005', current_setting('seoseed6.owner_user_id')::uuid),
  -- C3 (Community & Social Proof) <-> social_community + mention
  ('44444444-0000-0000-0001-000000000001', '44444444-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example', 'a6000000-0000-0000-0002-000000000003',
   'a6000000-0000-0000-0001-000000000006', current_setting('seoseed6.team_user_id')::uuid),
  ('44444444-0000-0000-0001-000000000001', '44444444-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example', 'a6000000-0000-0000-0002-000000000003',
   'a6000000-0000-0000-0001-000000000002', current_setting('seoseed6.team_user_id')::uuid)
ON CONFLICT (campaign_id, opportunity_id) DO NOTHING;

-- =============================================================================
-- SECTION A5 — AUTHORITY ACTIVITY (5 demo history rows). Append-only audit
-- trail. These are DEMO history rows (source is narrative only; the table has
-- no `source` column) that mirror the kind of rows the transition RPCs write,
-- so the UI history panel is non-empty. Exactly one of opportunity_id /
-- campaign_id is set, matching subject_type.
-- =============================================================================
SELECT '=== A5: authority activity (demo history) ===' AS step;

INSERT INTO public.seo_authority_activity
  (id, workspace_id, website_id, website_url, subject_type, opportunity_id, campaign_id,
   activity_type, from_status, to_status, note, actor_role_snapshot, created_by, created_at)
VALUES
  ('a6000000-0000-0000-0005-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'opportunity', 'a6000000-0000-0000-0001-000000000003', NULL,
   'start', 'approval_required', 'in_progress', 'Started the directory citation.',
   'team_member', current_setting('seoseed6.team_user_id')::uuid, now() - interval '7 days'),
  ('a6000000-0000-0000-0005-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'opportunity', 'a6000000-0000-0000-0001-000000000007', NULL,
   'complete', 'in_progress', 'completed', 'Partner resource published and links live.',
   'owner', current_setting('seoseed6.owner_user_id')::uuid, now() - interval '2 days'),
  ('a6000000-0000-0000-0005-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'opportunity', 'a6000000-0000-0000-0001-000000000008', NULL,
   'avoid', 'suggested', 'avoided', 'Avoided — paid links on a low-trust network.',
   'owner', current_setting('seoseed6.owner_user_id')::uuid, now() - interval '9 days'),
  ('a6000000-0000-0000-0005-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'campaign', NULL, 'a6000000-0000-0000-0002-000000000001',
   'approve', 'pending_approval', 'approved', 'Approved the Local Trust campaign.',
   'owner', current_setting('seoseed6.owner_user_id')::uuid, now() - interval '10 days'),
  ('a6000000-0000-0000-0005-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'campaign', NULL, 'a6000000-0000-0000-0002-000000000004',
   'reject', 'pending_approval', 'rejected', 'Rejected — aggressive link buying is non-compliant.',
   'owner', current_setting('seoseed6.owner_user_id')::uuid, now() - interval '8 days')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION B1 — AI PROMPT TRACKING (9). Covers all 4 visibility_status values;
-- P1/P2/P3 are the SAME prompt_text observed on three different dates (a
-- time-series showing visibility improving over time). Observed/manual only —
-- no LLM/scraper/API. brand_mentioned/brand_position/competitors/citations vary.
-- =============================================================================
SELECT '=== B1: AI prompt tracking (time-series) ===' AS step;

INSERT INTO public.seo_ai_prompt_tracking
  (id, workspace_id, website_id, website_url, prompt_text, topic, observed_on,
   visibility_status, brand_mentioned, brand_position, competitors_mentioned,
   citation_sources, our_site_cited, gap_summary, recommended_next_step, source, created_by)
VALUES
  -- P1/P2/P3 — same prompt, three dates (time-series, most recent first)
  ('a6000000-0000-0000-0006-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'best seo agency for small business', 'seo services', current_date,
   'partially_visible', true, 4, ARRAY['CompeteCo','RankLabs']::text[],
   ARRAY['ui-seed-digibility.example','reviewsite.example']::text[], true,
   'The business now appears in the answer but lower than two competitors.',
   'Strengthen topical content and earn one more trusted citation to move up.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0006-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'best seo agency for small business', 'seo services', current_date - 14,
   'not_visible', false, NULL, ARRAY['CompeteCo','RankLabs','SearchGuru']::text[],
   ARRAY['competeco.example','ranklabs.example']::text[], false,
   'The business did not appear at all; three competitors were named.',
   'Publish a clear services overview page and build initial citations.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0006-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'best seo agency for small business', 'seo services', current_date - 28,
   'not_visible', false, NULL, ARRAY['CompeteCo','SearchGuru']::text[],
   ARRAY['competeco.example']::text[], false,
   'The business was absent from the answer four weeks ago.',
   'Establish foundational content and directory presence first.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- P4 visible
  ('a6000000-0000-0000-0006-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'how to improve local search ranking', 'local seo', current_date - 2,
   'visible', true, 1, ARRAY['RankLabs']::text[],
   ARRAY['ui-seed-digibility.example']::text[], true,
   'The business is cited as a primary source for this how-to question.',
   'Keep the guide updated; it is a strong AI-visibility asset.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- P5 unknown
  ('a6000000-0000-0000-0006-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'seo audit tool for agencies', 'tools', current_date - 5,
   'unknown', false, NULL, ARRAY[]::text[],
   ARRAY[]::text[], false,
   'The answer varied and could not be reliably assessed on this observation.',
   'Re-check on a later date to establish a trend.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- P6 partially_visible
  ('a6000000-0000-0000-0006-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'affordable seo services near me', 'local seo', current_date - 3,
   'partially_visible', true, 6, ARRAY['CompeteCo','RankLabs']::text[],
   ARRAY['directory.example']::text[], false,
   'The business is mentioned but ranked low and not cited as a source.',
   'Improve local citations and gather more recent reviews.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- P7 visible (branded concept)
  ('a6000000-0000-0000-0006-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'what is a business visibility score', 'brand concept', current_date - 1,
   'visible', true, 2, ARRAY[]::text[],
   ARRAY['ui-seed-digibility.example']::text[], true,
   'The business site is cited for this concept it helped popularize.',
   'Expand the explainer with examples to reinforce ownership of the topic.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- P8 not_visible
  ('a6000000-0000-0000-0006-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'best tools to track google rankings', 'tools', current_date - 4,
   'not_visible', false, NULL, ARRAY['CompeteCo','SearchGuru']::text[],
   ARRAY['authorityblog.example']::text[], false,
   'The business is absent; a competitor and an authority blog dominate the answer.',
   'Create a comparison resource targeting this question.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- P9 partially_visible
  ('a6000000-0000-0000-0006-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'seo for small business owners', 'seo services', current_date - 6,
   'partially_visible', true, 5, ARRAY['RankLabs']::text[],
   ARRAY['ui-seed-digibility.example']::text[], true,
   'The business appears mid-answer with a citation but is not the lead source.',
   'Deepen the small-business content hub to become the lead reference.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION B2 — AI CONTENT GAPS (6). Priority low/medium/high; status open/
-- planned/addressed/dismissed; several linked to prompt observations.
-- =============================================================================
SELECT '=== B2: AI content gaps ===' AS step;

INSERT INTO public.seo_ai_content_gaps
  (id, workspace_id, website_id, website_url, related_prompt_id, topic, missing_answer_angle,
   suggested_content_type, related_keyword_or_question, gap_type, priority,
   recommended_next_action, status, source, created_by)
VALUES
  ('a6000000-0000-0000-0007-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000002', 'choosing an seo agency',
   'No clear "how to choose an SEO agency for a small business" explainer exists on the site.',
   'guide', 'how do I choose an seo agency for my small business', 'informational', 'high',
   'Write a plain-language buyer''s guide answering the common selection questions.', 'open',
   'manual_seed', current_setting('seoseed6.owner_user_id')::uuid),
  ('a6000000-0000-0000-0007-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000008', 'rank-tracking tools',
   'No comparison of rank-tracking approaches for small teams.',
   'comparison', 'best tools to track google rankings', 'commercial', 'high',
   'Publish a balanced comparison resource for the rank-tracking question.', 'planned',
   'manual_seed', current_setting('seoseed6.owner_user_id')::uuid),
  ('a6000000-0000-0000-0007-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000005', 'seo audit tooling',
   'The site does not explain what a good SEO audit covers.',
   'article', 'what does an seo audit include', 'informational', 'medium',
   'Add an article outlining what a thorough SEO audit covers.', 'open',
   'manual_seed', current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0007-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   NULL, 'pricing transparency',
   'No transparent explanation of how SEO pricing works for small businesses.',
   'pricing guide', 'how much does small business seo cost', 'commercial', 'medium',
   'Publish a transparent pricing explainer (already drafted).', 'addressed',
   'manual_seed', current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0007-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000006', 'near-me searches',
   'Limited locally-focused content for "near me" style queries.',
   'landing page', 'affordable seo services near me', 'local', 'low',
   'Revisit later; lower priority than the core informational gaps.', 'dismissed',
   'manual_seed', current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0007-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000009', 'small-business seo hub',
   'The small-business content is scattered rather than organized into a hub.',
   'content hub', 'seo for small business owners', 'informational', 'medium',
   'Organize existing posts into a structured small-business SEO hub.', 'open',
   'manual_seed', current_setting('seoseed6.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION B3 — AI MENTIONS (13). Covers brand / competitor / citation_source;
-- our-site citations and competitor/source citations; varied position/sentiment/
-- prominence/is_our_site; several linked to a prompt observation.
-- =============================================================================
SELECT '=== B3: AI mentions ===' AS step;

INSERT INTO public.seo_ai_mentions
  (id, workspace_id, website_id, website_url, prompt_tracking_id, mention_type, entity_name,
   entity_url, citation_url, is_our_site, mention_position, sentiment, prominence,
   where_appears, notes, source, created_by)
VALUES
  -- From P1 (best seo agency..., partially_visible)
  ('a6000000-0000-0000-0008-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000001', 'brand', 'UI Seed Demo Site',
   'https://ui-seed-digibility.example', NULL, true, 4, 'positive', 'medium',
   'Listed as an option in the answer.', 'Our brand appears but ranked 4th.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0008-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000001', 'competitor', 'CompeteCo',
   'https://competeco.example', NULL, false, 1, 'neutral', 'high',
   'Named first in the answer.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0008-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000001', 'competitor', 'RankLabs',
   'https://ranklabs.example', NULL, false, 2, 'neutral', 'medium',
   'Named second in the answer.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0008-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000001', 'citation_source', 'reviewsite.example',
   NULL, 'https://reviewsite.example/best-seo-agencies', false, NULL, 'neutral', 'medium',
   'Cited as a source list.', 'Third-party source the answer cited.', 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0008-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000001', 'citation_source', 'UI Seed Demo Site',
   'https://ui-seed-digibility.example', 'https://ui-seed-digibility.example/blog', true, NULL, 'positive', 'high',
   'Our blog was cited as a source.', 'Our own site cited — good AI-visibility signal.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- From P4 (how to improve local search ranking, visible)
  ('a6000000-0000-0000-0008-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000004', 'brand', 'UI Seed Demo Site',
   'https://ui-seed-digibility.example', NULL, true, 1, 'positive', 'high',
   'Cited as the primary source.', 'Strong result — lead source for this query.', 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- From P2 (not_visible earlier observation)
  ('a6000000-0000-0000-0008-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000002', 'competitor', 'SearchGuru',
   'https://searchguru.example', NULL, false, 1, 'neutral', 'high',
   'Dominated the earlier answer.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- From P8 (best tools to track rankings, not_visible)
  ('a6000000-0000-0000-0008-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000008', 'competitor', 'CompeteCo',
   'https://competeco.example', NULL, false, 1, 'neutral', 'high',
   'Led the tools answer.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),
  ('a6000000-0000-0000-0008-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000008', 'citation_source', 'authorityblog.example',
   NULL, 'https://authorityblog.example/rank-tracking', false, NULL, 'neutral', 'medium',
   'Cited as a source in the tools answer.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- From P7 (visibility score, visible, branded)
  ('a6000000-0000-0000-0008-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000007', 'brand', 'UI Seed Demo Site',
   'https://ui-seed-digibility.example', NULL, true, 2, 'positive', 'medium',
   'Cited for the concept it popularized.', NULL, 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid),

  -- From P6 (affordable seo near me, partially_visible)
  ('a6000000-0000-0000-0008-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000006', 'competitor', 'RankLabs',
   'https://ranklabs.example', NULL, false, 3, 'neutral', 'medium',
   'Appeared above our brand for this query.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- From P5 (audit tool, unknown)
  ('a6000000-0000-0000-0008-000000000012', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000005', 'citation_source', 'directory.example',
   NULL, 'https://directory.example/seo-tools', false, NULL, 'neutral', 'low',
   'Occasionally cited for tool listings.', NULL, 'manual_seed',
   current_setting('seoseed6.team_user_id')::uuid),

  -- From P9 (small business owners, partially_visible)
  ('a6000000-0000-0000-0008-000000000013', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'a6000000-0000-0000-0006-000000000009', 'brand', 'UI Seed Demo Site',
   'https://ui-seed-digibility.example', NULL, true, 5, 'neutral', 'medium',
   'Mentioned mid-answer with a citation.', NULL, 'manual_seed',
   current_setting('seoseed6.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION C — VERIFICATION (row counts scoped to this seed's a6000000- prefix,
-- plus status/type breakdowns). Read the result grids.
-- =============================================================================
SELECT '=== C: verification counts ===' AS step;

SELECT entity, count FROM (
  SELECT 1 AS ord, 'authority opportunities' AS entity, count(*) AS count
    FROM public.seo_authority_opportunities WHERE id::text LIKE 'a6000000-%'
  UNION ALL SELECT 2, 'authority campaigns', count(*)
    FROM public.seo_authority_campaigns WHERE id::text LIKE 'a6000000-%'
  UNION ALL SELECT 3, 'campaign tasks', count(*)
    FROM public.seo_authority_campaign_tasks WHERE id::text LIKE 'a6000000-%'
  UNION ALL SELECT 4, 'campaign ↔ opportunity links', count(*)
    FROM public.seo_authority_campaign_opportunities WHERE campaign_id::text LIKE 'a6000000-%'
  UNION ALL SELECT 5, 'authority activity', count(*)
    FROM public.seo_authority_activity WHERE id::text LIKE 'a6000000-%'
  UNION ALL SELECT 6, 'AI prompt tracking', count(*)
    FROM public.seo_ai_prompt_tracking WHERE id::text LIKE 'a6000000-%'
  UNION ALL SELECT 7, 'AI content gaps', count(*)
    FROM public.seo_ai_content_gaps WHERE id::text LIKE 'a6000000-%'
  UNION ALL SELECT 8, 'AI mentions', count(*)
    FROM public.seo_ai_mentions WHERE id::text LIKE 'a6000000-%'
) v ORDER BY ord;

SELECT '--- opportunity statuses ---' AS breakdown;
SELECT status, count(*) AS count FROM public.seo_authority_opportunities
WHERE id::text LIKE 'a6000000-%' GROUP BY status ORDER BY status;

SELECT '--- campaign approval statuses ---' AS breakdown;
SELECT approval_status, count(*) AS count FROM public.seo_authority_campaigns
WHERE id::text LIKE 'a6000000-%' GROUP BY approval_status ORDER BY approval_status;

SELECT '--- prompt visibility statuses ---' AS breakdown;
SELECT visibility_status, count(*) AS count FROM public.seo_ai_prompt_tracking
WHERE id::text LIKE 'a6000000-%' GROUP BY visibility_status ORDER BY visibility_status;

SELECT '--- mention types ---' AS breakdown;
SELECT mention_type, count(*) AS count FROM public.seo_ai_mentions
WHERE id::text LIKE 'a6000000-%' GROUP BY mention_type ORDER BY mention_type;

SELECT '=== STAGE 6 OFF-PAGE + AI VISIBILITY SEED EXTENSION — complete. See counts above. ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the rows this script created,
-- identified by the a6000000- prefix; does NOT touch the base UI seed, the
-- Stage 4/5 seed extensions, any smoke-test data, or any other row). Commented
-- out on purpose — uncomment and run manually only to remove this extension's
-- data. Order: children before parents (FKs cascade, but explicit for clarity).
-- =============================================================================
-- DELETE FROM public.seo_ai_mentions                     WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_ai_content_gaps                 WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_activity              WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_campaign_opportunities WHERE campaign_id::text LIKE 'a6000000-%' OR opportunity_id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_campaign_tasks        WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_campaigns             WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_authority_opportunities         WHERE id::text LIKE 'a6000000-%';
-- DELETE FROM public.seo_ai_prompt_tracking              WHERE id::text LIKE 'a6000000-%';
