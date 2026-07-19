-- =============================================================================
-- SEO UI TEST DATASET — STAGE 5 DECLINE DIAGNOSIS EXTENSION (TEST DATA ONLY)
-- =============================================================================
--                          ****  TEST DATA ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Purpose: add realistic Decline Diagnosis Engine data (diagnoses + evidence)
-- under the EXISTING base UI seed workspace/website, tied to the EXISTING
-- Stage 4 Page Performance seed extension's page/keyword/snapshot rows, so
-- Supabase-mode UI has non-empty Decline Diagnosis data once that service is
-- wired. This is a plain data seed extension, NOT a correctness/RLS test
-- (see supabase/test/seo_stage5_decline_diagnosis_smoke_test.sql for that) —
-- run once as the privileged SQL Editor ("postgres") role, which bypasses
-- RLS by design for seeding.
--
-- This script:
--   - REQUIRES Stage 1-5 migrations already applied to the target project
--     (20260711120001 through 20260711120016).
--   - REQUIRES the base UI seed dataset (supabase/test/seo_seed_ui_test_dataset.sql)
--     already applied — this script attaches to that seed's workspace/website
--     and will refuse to run if they are missing (see SECTION 0.5 below).
--   - REQUIRES the Stage 4 Page Performance seed extension
--     (supabase/test/seo_seed_stage4_page_performance_ui_extension.sql)
--     already applied — this script attaches Stage 5 diagnoses to that
--     extension's page inventory / keyword / snapshot rows and will refuse
--     to run if they are missing (see SECTION 0.5 below).
--   - Does NOT create Supabase Auth users and does NOT insert into auth.users.
--     It requires two EXISTING auth.users UUIDs to be pasted in below.
--   - Does NOT use, require, or mention a service role key. It is meant to be
--     pasted into the Supabase Dashboard SQL Editor and run there (the SQL
--     Editor already runs as a privileged Postgres role on your own project;
--     no key of any kind is entered into this script).
--   - Does NOT modify any migration file and does NOT alter table/RLS/trigger
--     definitions — pure DML (INSERT/ON CONFLICT) against already-applied
--     Stage 5 tables.
--   - Does NOT TRUNCATE or DROP anything, does NOT disable RLS anywhere, and
--     does NOT delete or modify any existing row from the base UI seed, the
--     Stage 4 extension, or any other seed/smoke test.
--   - Does NOT touch or reference production. Target the TEST project only.
--   - Is idempotent: every INSERT uses a fixed literal UUID with
--     ON CONFLICT (id) DO NOTHING, so re-running this script is safe and
--     will not create duplicates or delete anything.
--   - Uses the UUID prefix "88888888-" for every row it creates — a prefix
--     not used by the Stage 2 smoke test ("aaaaaaaa-"/"bbbbbbbb-"/etc.), the
--     Stage 3 smoke test ("33333333-"), the Stage 4 smoke test ("55555555-"),
--     the Stage 5 smoke test ("77777777-"), the base UI seed dataset
--     ("44444444-"), or the Stage 4 seed extension ("66666666-"), so this
--     extension cannot collide with or overwrite any of them.
--   - Does NOT call the seo_create_decline_diagnosis_from_snapshot RPC —
--     rows are inserted directly (same privileged-seeding pattern as every
--     other seed script) so exact demo narrative/classification values can
--     be controlled precisely. The RPC itself is already exercised by the
--     Stage 5 smoke test.
--   - Does NOT call any real GSC/GA4/crawler/LLM. All rows are manual demo
--     data (`source='manual_seed'` on evidence; diagnoses have no `source`
--     column but are equally manual/demo).
--
-- See SUPABASE_STAGE5_DECLINE_DIAGNOSIS_SEED_EXTENSION_GUIDE.md for full run
-- instructions, how to find test user UUIDs, expected verification counts,
-- and how to exercise this data in the local UI once Decline Diagnosis
-- service wiring lands (not part of this script).
-- =============================================================================

-- =============================================================================
-- SECTION 0 — TEST USER UUIDS (REQUIRED — fill these in before running)
-- =============================================================================
-- Paste two EXISTING Supabase Auth user UUIDs below. These are only used to
-- stamp `created_by` on the rows this script inserts — they do not need to
-- be the exact same users as the base UI seed or Stage 4 extension used, but
-- reusing the same owner/team_member test users from those seeds is
-- recommended for consistency. Must already exist in auth.users on the TEST
-- project (Dashboard -> Authentication -> Users, or the lookup query in
-- SUPABASE_STAGE5_DECLINE_DIAGNOSIS_SEED_EXTENSION_GUIDE.md §3). This script
-- does NOT create users and does NOT accept an email address here — only a
-- UUID. Pasting an email instead of a UUID will be rejected by the guard
-- below.
--
--   owner_user_id -> stamped as created_by on the highest-severity/critical
--                    diagnoses and their evidence
--   team_user_id  -> stamped as created_by on everything else
-- =============================================================================

SELECT set_config('seoseed5.owner_user_id', '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seoseed5.team_user_id',  '0723d21f-c02c-4725-851f-575f93f2f58c',  false);

-- Guard: refuse to run until every UUID above has been replaced with a real,
-- correctly-formatted UUID. Raises a clear, specific exception naming exactly
-- which value is still a placeholder or is not UUID-shaped (e.g. an email
-- pasted by mistake) — this script never silently proceeds with a bad value.
DO $$
DECLARE
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_pairs text[][] := ARRAY[
    ARRAY['owner_user_id', '48c479db-aedf-452e-af43-05ed1180baaa'],
    ARRAY['team_user_id',  '0723d21f-c02c-4725-851f-575f93f2f58c']
  ];
  v_key text;
  v_placeholder text;
  v_value text;
  i int;
BEGIN
  FOR i IN 1 .. array_upper(v_pairs, 1) LOOP
    v_key := v_pairs[i][1];
    v_placeholder := v_pairs[i][2];
    v_value := current_setting('seoseed5.' || v_key, true);
    IF v_value IS NULL OR v_value = v_placeholder THEN
      RAISE EXCEPTION 'seoseed5.% is still a placeholder — paste a real auth.users UUID at the top of this script before running (see SUPABASE_STAGE5_DECLINE_DIAGNOSIS_SEED_EXTENSION_GUIDE.md).', v_key;
    END IF;
    IF v_value !~ v_uuid_pattern THEN
      RAISE EXCEPTION 'seoseed5.% ("%") is not a valid UUID. Paste the user''s UUID from auth.users, not an email address.', v_key, v_value;
    END IF;
  END LOOP;
END $$;

-- =============================================================================
-- SECTION 0.5 — DEPENDENCY GUARDS (REQUIRED)
-- =============================================================================
-- This extension attaches Stage 5 rows to (a) the workspace/website created
-- by supabase/test/seo_seed_ui_test_dataset.sql and (b) the Stage 4 page
-- inventory / performance snapshot rows created by
-- supabase/test/seo_seed_stage4_page_performance_ui_extension.sql. Refuse to
-- proceed if any is missing, with a clear message pointing at the
-- prerequisite script — never silently create workspace/website/page rows of
-- our own.
-- =============================================================================
DO $$
DECLARE
  v_workspace_count int;
  v_website_count int;
BEGIN
  SELECT count(*) INTO v_workspace_count
  FROM public.seo_workspaces
  WHERE id = '44444444-0000-0000-0001-000000000001';

  SELECT count(*) INTO v_website_count
  FROM public.seo_websites
  WHERE id = '44444444-0000-0000-0002-000000000001'
    AND workspace_id = '44444444-0000-0000-0001-000000000001';

  IF v_workspace_count = 0 OR v_website_count = 0 THEN
    RAISE EXCEPTION 'Base UI seed dataset must be applied before this Stage 5 extension. Run supabase/test/seo_seed_ui_test_dataset.sql first (see SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md), then re-run this script.';
  END IF;
END $$;

DO $$
DECLARE
  v_page_count int;
  v_snapshot_count int;
BEGIN
  SELECT count(*) INTO v_page_count
  FROM public.seo_page_inventory
  WHERE website_id = '44444444-0000-0000-0002-000000000001';

  SELECT count(*) INTO v_snapshot_count
  FROM public.seo_page_performance_snapshots
  WHERE website_id = '44444444-0000-0000-0002-000000000001';

  IF v_page_count = 0 OR v_snapshot_count = 0 THEN
    RAISE EXCEPTION 'Stage 4 Page Performance seed extension must be applied before this Stage 5 extension. Run supabase/test/seo_seed_stage4_page_performance_ui_extension.sql first (see SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md), then re-run this script.';
  END IF;
END $$;

SELECT '=== STAGE 5 DECLINE DIAGNOSIS SEED EXTENSION — starting ===' AS step;

-- =============================================================================
-- UUID MAP (all fixed, prefix 88888888- ; 4th group's leading nibble groups
-- rows by category):
--   1 = decline diagnoses (8 rows)
--   2 = diagnosis evidence (20 rows)
-- Attaches to the base seed's workspace 44444444-0000-0000-0001-000000000001
-- and website 44444444-0000-0000-0002-000000000001
-- (https://ui-seed-digibility.example), and to the Stage 4 extension's
-- existing page/keyword/snapshot rows (prefix 66666666-):
--   Pages used:    ...0001-000000000001 (homepage), ...0003 (blog listing),
--                  ...0006 (contact), ...0007 (pricing)
--   Keywords used: ...0002-000000000002 (homepage secondary "business
--                  visibility score"), ...0005 (blog listing primary "seo
--                  blog for small business owners")
--   Snapshots used: ...0003-000000000002 (homepage aggregate, improving),
--                  ...0010 (blog listing aggregate, declining),
--                  ...0012 (blog listing keyword, declining),
--                  ...0019 (contact aggregate, no_data),
--                  ...0020 (pricing aggregate, no_data)
-- =============================================================================

-- =============================================================================
-- SECTION 1 — DECLINE DIAGNOSES (8 rows, varied type/severity/priority/
-- status/owner). linked_recommendation_id is left NULL throughout by design
-- — Stage 5 does not build the diagnosis-to-recommendation conversion flow
-- yet (see SUPABASE_MIGRATION_STAGE_5_DECLINE_DIAGNOSIS_PLAN.md §7); this
-- seed does not assert a premature link.
-- =============================================================================
SELECT '=== Section 1: decline diagnoses ===' AS step;

INSERT INTO public.seo_decline_diagnoses
  (id, workspace_id, website_id, website_url, page_id, page_url,
   page_keyword_id, keyword, performance_snapshot_id,
   diagnosis_type, severity, confidence_percentage, movement_status,
   business_summary, likely_cause, technical_explanation,
   recommended_next_action, suggested_owner, priority, status, created_by)
VALUES
  -- 1. Blog listing keyword — CTR fell sharply even though impressions held up.
  ('88888888-0000-0000-0001-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', 'https://ui-seed-digibility.example/blog',
   '66666666-0000-0000-0002-000000000005', 'seo blog for small business owners',
   '66666666-0000-0000-0003-000000000012',
   'ctr_drop', 'medium', 70, 'declining',
   'Fewer people are clicking through to your blog for this search, even though it is still being shown.',
   'The search snippet (title/description) may no longer stand out compared to competing results.',
   'Click-through rate fell from 3.33% to 2.48% for "seo blog for small business owners" over the last snapshot period.',
   'Rewrite the blog listing page title and meta description to be more specific and compelling.',
   'client_action', 'medium', 'open',
   current_setting('seoseed5.team_user_id')::uuid),

  -- 2. Blog listing aggregate — overall ranking slipping.
  ('88888888-0000-0000-0001-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', 'https://ui-seed-digibility.example/blog',
   NULL, NULL,
   '66666666-0000-0000-0003-000000000010',
   'ranking_decline', 'high', 75, 'declining',
   'Your blog listing page is showing up lower in search results overall, which is costing you visitors.',
   'Aging content on this page may be losing ground to more recently updated competing pages.',
   'Average position moved from 11.2 to 13.8 and clicks fell from 520 to 410 (-21%) over the last 14 days.',
   'Have an SEO expert review the blog listing page against currently ranking competitors.',
   'digibility_expert', 'high', 'in_review',
   current_setting('seoseed5.owner_user_id')::uuid),

  -- 3. Blog listing keyword — clicks down specifically for the primary keyword.
  ('88888888-0000-0000-0001-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', 'https://ui-seed-digibility.example/blog',
   '66666666-0000-0000-0002-000000000005', 'seo blog for small business owners',
   '66666666-0000-0000-0003-000000000012',
   'clicks_decline', 'medium', 68, 'declining',
   'This specific search term is sending noticeably fewer visitors to your blog than it used to.',
   'The combination of a lower ranking and a weaker snippet is compounding into a bigger traffic loss for this keyword.',
   'Clicks for "seo blog for small business owners" fell from 60 to 41 (-32%) over the last snapshot period.',
   'Plan a content refresh for the blog listing page, prioritized alongside the title/description rewrite.',
   'client_action', 'medium', 'action_planned',
   current_setting('seoseed5.team_user_id')::uuid),

  -- 4. Blog listing aggregate — impressions decline, already resolved (excluded from current view).
  ('88888888-0000-0000-0001-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', 'https://ui-seed-digibility.example/blog',
   NULL, NULL,
   '66666666-0000-0000-0003-000000000010',
   'impressions_decline', 'low', 60, 'declining',
   'Your blog listing page was being shown in search results less often than before.',
   'A minor, temporary dip in how often this page was surfaced for its target searches.',
   'Impressions fell from 15,000 to 14,200 (-5.3%) over the last snapshot period.',
   'No action needed — monitor for now; revisit if the trend continues past the next reporting period.',
   'system_suggestion', 'low', 'resolved',
   current_setting('seoseed5.team_user_id')::uuid),

  -- 5. Contact page — stale content, dismissed as intentionally static.
  ('88888888-0000-0000-0001-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000006', 'https://ui-seed-digibility.example/contact',
   NULL, NULL,
   '66666666-0000-0000-0003-000000000019',
   'content_freshness', 'low', 40, 'no_data',
   'This page has not been updated in a while, which can make it look less relevant to search engines.',
   'content_status is marked "stale" in page inventory — search engines may treat this as lower-value, infrequently maintained content.',
   'No recent edits detected; the page currently receives minimal impressions (4) and no clicks.',
   'Confirm the contact page is intentionally static, or refresh its copy if not.',
   'system_suggestion', 'low', 'dismissed',
   current_setting('seoseed5.team_user_id')::uuid),

  -- 6. Pricing page — deliberately noindexed; flagged to confirm it's intentional.
  ('88888888-0000-0000-0001-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000007', 'https://ui-seed-digibility.example/pricing',
   NULL, NULL,
   '66666666-0000-0000-0003-000000000020',
   'indexing_issue', 'medium', 50, 'no_data',
   'This page is currently hidden from search results by a "noindex" instruction.',
   'indexability_status is "noindex" — this may be an intentional, active pricing experiment, or it may have been left on by mistake.',
   'seo_page_inventory.indexability_status = ''noindex'' for this page as of the last inventory scan.',
   'Confirm with the team whether the pricing page should stay noindexed, or remove the tag if it was left on unintentionally.',
   'developer_needed', 'medium', 'in_review',
   current_setting('seoseed5.owner_user_id')::uuid),

  -- 7. Homepage secondary keyword — informational intent on a commercial page.
  ('88888888-0000-0000-0001-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', 'https://ui-seed-digibility.example/',
   '66666666-0000-0000-0002-000000000002', 'business visibility score',
   NULL,
   'intent_mismatch', 'medium', 55, NULL,
   'This search term may be bringing the wrong kind of visitor to your homepage.',
   'The keyword has informational intent (people looking to learn something), but the homepage is written to sell services — a mismatch that can hurt both ranking and conversion.',
   'seo_page_keywords.search_intent = ''informational'' for this keyword, mapped to a homepage with page_type = ''homepage'' and commercial framing.',
   'Consider creating a dedicated informational page or blog post for this keyword instead of relying on the homepage.',
   'digibility_expert', 'medium', 'open',
   current_setting('seoseed5.owner_user_id')::uuid),

  -- 8. Homepage — known technical (Core Web Vitals) issue capping further gains.
  ('88888888-0000-0000-0001-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', 'https://ui-seed-digibility.example/',
   NULL, NULL,
   '66666666-0000-0000-0003-000000000002',
   'technical_performance', 'critical', 85, 'improving',
   'Your homepage is loading slowly on phones, which puts a ceiling on how well it can rank even as things are improving.',
   'A known page-speed issue (slow mobile load time, largely driven by image weight) likely caps further ranking gains.',
   'Largest Contentful Paint measured at 4.3s under 4G throttling — see the related open audit issue for full detail.',
   'Compress and lazy-load the homepage hero image and defer non-critical scripts.',
   'developer_needed', 'high', 'action_planned',
   current_setting('seoseed5.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION 2 — DIAGNOSIS EVIDENCE (20 rows across the 8 diagnoses above, 2-4
-- per diagnosis, varied evidence_type/source). Two rows (diagnosis 8's
-- technical evidence) reference the base UI seed's existing audit issue
-- "Homepage load time exceeds 4 seconds on mobile"
-- (id 44444444-0000-0000-0004-000000000001) by TITLE ONLY in evidence_summary
-- — seo_decline_diagnosis_evidence has no FK to seo_audit_issues (only a
-- `source` enum), so this is a safe, non-dangling informational reference,
-- not a live foreign key.
-- =============================================================================
SELECT '=== Section 2: diagnosis evidence ===' AS step;

INSERT INTO public.seo_decline_diagnosis_evidence
  (id, workspace_id, website_id, website_url, diagnosis_id, evidence_type,
   metric_name, current_value, previous_value, delta_value, evidence_summary,
   source, created_by)
VALUES
  -- Diagnosis 1 (ctr_drop) — 3 rows.
  ('88888888-0000-0000-0002-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000001', 'ctr', 'ctr', '0.0248', '0.0333', '-0.0085',
   'Click-through rate fell from 3.33% to 2.48% for this keyword.', 'performance_snapshot',
   current_setting('seoseed5.team_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000001', 'traffic', 'clicks', '41', '60', '-19',
   'Clicks dropped alongside the CTR decline.', 'performance_snapshot',
   current_setting('seoseed5.team_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000001', 'content', 'content_status', 'aging', NULL, NULL,
   'The blog listing page content is marked as aging, which may reduce its appeal in search snippets.', 'page_inventory',
   current_setting('seoseed5.team_user_id')::uuid),

  -- Diagnosis 2 (ranking_decline) — 4 rows.
  ('88888888-0000-0000-0002-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000002', 'ranking', 'average_position', '13.8', '11.2', '2.6',
   'Average position moved from 11.2 to 13.8 (lower is better) over the last snapshot period.', 'performance_snapshot',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000002', 'traffic', 'clicks', '410', '520', '-110',
   'Clicks fell 21% alongside the ranking drop.', 'performance_snapshot',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000002', 'impressions', 'impressions', '14200', '15000', '-800',
   'Search impressions also declined, suggesting reduced visibility rather than just lower engagement.', 'performance_snapshot',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000002', 'system_note', 'diagnosis_hint', NULL, NULL, NULL,
   'Blog listing page is losing visibility — content freshness may need review.', 'system',
   current_setting('seoseed5.owner_user_id')::uuid),

  -- Diagnosis 3 (clicks_decline) — 2 rows.
  ('88888888-0000-0000-0002-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000003', 'traffic', 'clicks', '41', '60', '-19',
   'Clicks for this keyword fell from 60 to 41 (-32%).', 'performance_snapshot',
   current_setting('seoseed5.team_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000003', 'ranking', 'average_position', '13.1', '10.5', '2.6',
   'Ranking also slipped for this keyword over the same period.', 'performance_snapshot',
   current_setting('seoseed5.team_user_id')::uuid),

  -- Diagnosis 4 (impressions_decline, resolved) — 2 rows.
  ('88888888-0000-0000-0002-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000004', 'impressions', 'impressions', '14200', '15000', '-800',
   'Impressions fell by roughly 800 over the period.', 'performance_snapshot',
   current_setting('seoseed5.team_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000004', 'system_note', 'resolution_note', NULL, NULL, NULL,
   'Marked resolved after monitoring showed the dip did not continue into the next reporting period.', 'manual_seed',
   current_setting('seoseed5.team_user_id')::uuid),

  -- Diagnosis 5 (content_freshness, dismissed) — 2 rows.
  ('88888888-0000-0000-0002-000000000012', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000005', 'content', 'content_status', 'stale', NULL, NULL,
   'Contact page content_status is marked stale in page inventory.', 'page_inventory',
   current_setting('seoseed5.team_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000013', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000005', 'system_note', 'dismissal_note', NULL, NULL, NULL,
   'Dismissed — contact page content is intentionally static and does not need refreshing.', 'manual_seed',
   current_setting('seoseed5.team_user_id')::uuid),

  -- Diagnosis 6 (indexing_issue) — 2 rows.
  ('88888888-0000-0000-0002-000000000014', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000006', 'indexability', 'indexability_status', 'noindex', NULL, NULL,
   'Pricing page is currently set to noindex.', 'page_inventory',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000015', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000006', 'system_note', 'review_note', NULL, NULL, NULL,
   'Flagged for review to confirm the noindex tag is intentional (active pricing experiment) and not left on by mistake.', 'manual_seed',
   current_setting('seoseed5.owner_user_id')::uuid),

  -- Diagnosis 7 (intent_mismatch) — 2 rows.
  ('88888888-0000-0000-0002-000000000016', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000007', 'query_intent', 'search_intent', 'informational', NULL, NULL,
   'This keyword has informational search intent, but the homepage is written for commercial intent.', 'page_inventory',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000017', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000007', 'content', 'page_type', 'homepage', NULL, NULL,
   'Homepage content is structured around service/commercial messaging, not informational answers.', 'page_inventory',
   current_setting('seoseed5.owner_user_id')::uuid),

  -- Diagnosis 8 (technical_performance) — 3 rows.
  ('88888888-0000-0000-0002-000000000018', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000008', 'technical', 'largest_contentful_paint', '4.3s', NULL, NULL,
   'Largest Contentful Paint measured at 4.3s on 4G throttling, largely image-weight driven.', 'audit_issue',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000019', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000008', 'traffic', 'clicks', '230', '180', '50',
   'Clicks are already improving, but the load-time issue likely caps further gains.', 'performance_snapshot',
   current_setting('seoseed5.owner_user_id')::uuid),
  ('88888888-0000-0000-0002-000000000020', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '88888888-0000-0000-0001-000000000008', 'system_note', 'related_issue', NULL, NULL, NULL,
   'See audit issue "Homepage load time exceeds 4 seconds on mobile" for full technical detail.', 'audit_issue',
   current_setting('seoseed5.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION 3 — VERIFICATION (compact row counts, scoped to the base seed's
-- workspace, plus breakdowns by diagnosis_type / severity / status /
-- suggested_owner, and the current view's row count).
-- =============================================================================
SELECT '=== Section 3: verification counts ===' AS step;

SELECT entity, count FROM (
  SELECT 1 AS ord, 'decline diagnoses' AS entity, count(*) AS count
    FROM public.seo_decline_diagnoses
    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
  UNION ALL
  SELECT 2, 'diagnosis evidence rows', count(*)
    FROM public.seo_decline_diagnosis_evidence
    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
  UNION ALL
  SELECT 3, 'current-view rows (open/in_review/action_planned only)', count(*)
    FROM public.seo_decline_diagnoses_current
    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
) v
ORDER BY ord;

SELECT '--- by diagnosis_type ---' AS breakdown;
SELECT diagnosis_type, count(*) AS count
FROM public.seo_decline_diagnoses
WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
GROUP BY diagnosis_type
ORDER BY diagnosis_type;

SELECT '--- by severity ---' AS breakdown;
SELECT severity, count(*) AS count
FROM public.seo_decline_diagnoses
WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
GROUP BY severity
ORDER BY severity;

SELECT '--- by status ---' AS breakdown;
SELECT status, count(*) AS count
FROM public.seo_decline_diagnoses
WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
GROUP BY status
ORDER BY status;

SELECT '--- by suggested_owner ---' AS breakdown;
SELECT suggested_owner, count(*) AS count
FROM public.seo_decline_diagnoses
WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '88888888-%'
GROUP BY suggested_owner
ORDER BY suggested_owner;

SELECT '=== STAGE 5 DECLINE DIAGNOSIS SEED EXTENSION — complete. See counts above. ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the rows this script created,
-- identified by the 88888888- prefix; does NOT touch the base UI seed's
-- workspace/website/onboarding/audit/approval/content rows, the Stage 4
-- extension's page/keyword/snapshot rows, or any other seed/smoke test).
-- Commented out on purpose — uncomment and run manually only if you want to
-- remove this extension's data from the test project. Evidence rows also
-- cascade-delete automatically if their parent diagnosis is deleted, but both
-- statements are listed explicitly for clarity.
-- =============================================================================
-- DELETE FROM public.seo_decline_diagnosis_evidence WHERE id::text LIKE '88888888-%';
-- DELETE FROM public.seo_decline_diagnoses WHERE id::text LIKE '88888888-%';
