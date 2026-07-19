-- =============================================================================
-- SEO UI TEST DATASET — STAGE 4 PAGE PERFORMANCE EXTENSION (TEST DATA ONLY)
-- =============================================================================
--                          ****  TEST DATA ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Purpose: add realistic Page Performance Tracker data (page inventory,
-- mapped keywords, performance snapshots) under the EXISTING base UI seed
-- workspace/website so Supabase-mode UI has non-empty Page Performance data
-- once that service is wired. This is a plain data seed extension, NOT a
-- correctness/RLS test (see supabase/test/seo_stage4_page_performance_smoke_test.sql
-- for that) — run once as the privileged SQL Editor ("postgres") role, which
-- bypasses RLS by design for seeding.
--
-- This script:
--   - REQUIRES Stage 1-4 migrations already applied to the target project
--     (20260711120001 through 20260711120013).
--   - REQUIRES the base UI seed dataset (supabase/test/seo_seed_ui_test_dataset.sql)
--     already applied — this script attaches to that seed's workspace/website
--     and will refuse to run if they are missing (see SECTION 0.5 below).
--   - Does NOT create Supabase Auth users and does NOT insert into auth.users.
--     It requires two EXISTING auth.users UUIDs to be pasted in below.
--   - Does NOT use, require, or mention a service role key. It is meant to be
--     pasted into the Supabase Dashboard SQL Editor and run there (the SQL
--     Editor already runs as a privileged Postgres role on your own project;
--     no key of any kind is entered into this script).
--   - Does NOT modify any migration file and does NOT alter table/RLS/trigger
--     definitions — pure DML (INSERT/ON CONFLICT) against already-applied
--     Stage 4 tables.
--   - Does NOT TRUNCATE or DROP anything, does NOT disable RLS anywhere, and
--     does NOT delete or modify any existing row from the base UI seed or
--     any other seed/smoke test.
--   - Does NOT touch or reference production. Target the TEST project only.
--   - Is idempotent: every INSERT uses a fixed literal UUID with
--     ON CONFLICT (id) DO NOTHING, so re-running this script is safe and
--     will not create duplicates or delete anything.
--   - Uses the UUID prefix "66666666-" for every row it creates — a prefix
--     not used by the Stage 2 smoke test ("aaaaaaaa-"/"bbbbbbbb-"/etc.), the
--     Stage 3 smoke test ("33333333-"), the Stage 4 smoke test ("55555555-"),
--     or the base UI seed dataset ("44444444-"), so this extension cannot
--     collide with or overwrite any of them.
--   - Does NOT call any real GSC/GA4 API, does NOT run a crawler, and does
--     NOT create a cron job. All rows use source='manual_seed'.
--
-- See SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md for full run
-- instructions, how to find test user UUIDs, expected verification counts,
-- and how to exercise this data in the local UI once Page Performance
-- service wiring lands (not part of this script).
-- =============================================================================

-- =============================================================================
-- SECTION 0 — TEST USER UUIDS (REQUIRED — fill these in before running)
-- =============================================================================
-- Paste two EXISTING Supabase Auth user UUIDs below. These are only used to
-- stamp `created_by` on the rows this script inserts — they do not need to
-- be the exact same users as the base UI seed used, but reusing the same
-- owner/team_member test users from that seed is recommended for
-- consistency. Must already exist in auth.users on the TEST project
-- (Dashboard -> Authentication -> Users, or the lookup query in
-- SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md §3). This script
-- does NOT create users and does NOT accept an email address here — only a
-- UUID. Pasting an email instead of a UUID will be rejected by the guard
-- below.
--
--   owner_user_id -> stamped as created_by on the two highest-priority pages
--   team_user_id  -> stamped as created_by on everything else (keywords,
--                    snapshots, and the remaining pages)
-- =============================================================================

SELECT set_config('seoseed4.owner_user_id', '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seoseed4.team_user_id',  '0723d21f-c02c-4725-851f-575f93f2f58c',  false);

-- Guard: refuse to run until every UUID above has been replaced with a real,
-- correctly-formatted UUID. Raises a clear, specific exception naming exactly
-- which value is still a placeholder or is not UUID-shaped (e.g. an email
-- pasted by mistake) — this script never silently proceeds with a bad value.
DO $$
DECLARE
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_pairs text[][] := ARRAY[
    ARRAY['owner_user_id', 'REPLACE_WITH_OWNER_USER_UUID'],
    ARRAY['team_user_id',  'REPLACE_WITH_TEAM_USER_UUID']
  ];
  v_key text;
  v_placeholder text;
  v_value text;
  i int;
BEGIN
  FOR i IN 1 .. array_upper(v_pairs, 1) LOOP
    v_key := v_pairs[i][1];
    v_placeholder := v_pairs[i][2];
    v_value := current_setting('seoseed4.' || v_key, true);
    IF v_value IS NULL OR v_value = v_placeholder THEN
      RAISE EXCEPTION 'seoseed4.% is still a placeholder — paste a real auth.users UUID at the top of this script before running (see SUPABASE_STAGE4_PAGE_PERFORMANCE_SEED_EXTENSION_GUIDE.md).', v_key;
    END IF;
    IF v_value !~ v_uuid_pattern THEN
      RAISE EXCEPTION 'seoseed4.% ("%") is not a valid UUID. Paste the user''s UUID from auth.users, not an email address.', v_key, v_value;
    END IF;
  END LOOP;
END $$;

-- =============================================================================
-- SECTION 0.5 — BASE UI SEED DEPENDENCY GUARD (REQUIRED)
-- =============================================================================
-- This extension attaches Stage 4 rows to the workspace/website created by
-- supabase/test/seo_seed_ui_test_dataset.sql. Refuse to proceed if either is
-- missing, with a clear message pointing at the prerequisite script — never
-- silently create a new workspace/website of our own.
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
    RAISE EXCEPTION 'Base UI seed dataset must be applied before this Stage 4 extension. Run supabase/test/seo_seed_ui_test_dataset.sql first (see SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md), then re-run this script.';
  END IF;
END $$;

SELECT '=== STAGE 4 PAGE PERFORMANCE SEED EXTENSION — starting ===' AS step;

-- =============================================================================
-- UUID MAP (all fixed, prefix 66666666- ; 4th group's leading nibble groups
-- rows by category):
--   1 = page inventory (7 pages)
--   2 = page keywords (13 keywords)
--   3 = performance snapshots (20 snapshots)
-- Attaches to the base seed's workspace 44444444-0000-0000-0001-000000000001
-- and website 44444444-0000-0000-0002-000000000001
-- (https://ui-seed-digibility.example).
-- =============================================================================

-- =============================================================================
-- SECTION 1 — PAGE INVENTORY (7 pages, varied type/indexability/content/priority)
-- =============================================================================
SELECT '=== Section 1: page inventory ===' AS step;

INSERT INTO public.seo_page_inventory
  (id, workspace_id, website_id, website_url, page_url, normalized_page_path,
   page_title, meta_description, page_type, indexability_status, content_status,
   priority, is_tracked, is_active, created_by)
VALUES
  -- Homepage — flagship, high priority, fresh content, fully indexable.
  ('66666666-0000-0000-0001-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/', '/',
   'UI Seed Demo Site | SEO Audits & Local Visibility',
   'SEO audits, content strategy, and technical optimization for small business websites.',
   'homepage', 'indexable', 'fresh', 'high', true, true,
   current_setting('seoseed4.owner_user_id')::uuid),

  -- Services page — flagship, high priority.
  ('66666666-0000-0000-0001-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/services', '/services',
   'SEO Services for Small Businesses',
   'See our full range of SEO services for small businesses — audits, content, and technical fixes.',
   'service_page', 'indexable', 'fresh', 'high', true, true,
   current_setting('seoseed4.owner_user_id')::uuid),

  -- Blog listing — aging, medium priority.
  ('66666666-0000-0000-0001-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/blog', '/blog',
   'SEO Blog | Insights for Small Business Owners',
   'Guides and insights on SEO for small business owners.',
   'blog', 'indexable', 'aging', 'medium', true, true,
   current_setting('seoseed4.team_user_id')::uuid),

  -- Flagship blog post — fresh, medium priority, matches the Content Studio seed topic.
  ('66666666-0000-0000-0001-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/blog/seo-checklist-small-business', '/blog/seo-checklist-small-business',
   'SEO Checklist for Small Business Websites',
   'A practical SEO checklist small business owners can follow step by step.',
   'blog', 'indexable', 'fresh', 'medium', true, true,
   current_setting('seoseed4.owner_user_id')::uuid),

  -- Local SEO landing page — newly published, high priority.
  ('66666666-0000-0000-0001-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/local-seo', '/local-seo',
   'Local SEO Services in Austin, TX',
   'Improve your local search visibility with Digibility''s local SEO services.',
   'landing_page', 'indexable', 'fresh', 'high', true, true,
   current_setting('seoseed4.team_user_id')::uuid),

  -- Contact page — low priority, not keyword-tracked, blocked from indexing
  -- (e.g. a form-heavy page with tracking query params intentionally excluded).
  ('66666666-0000-0000-0001-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/contact', '/contact',
   'Contact Us', 'Get in touch with the Digibility SEO team.',
   'other', 'blocked', 'stale', 'low', false, true,
   current_setting('seoseed4.team_user_id')::uuid),

  -- Pricing page — low priority, not yet keyword-tracked, deliberately noindexed
  -- (e.g. behind an active pricing experiment).
  ('66666666-0000-0000-0001-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'https://ui-seed-digibility.example/pricing', '/pricing',
   'Pricing', 'SEO plans and pricing for small businesses and agencies.',
   'other', 'noindex', 'unknown', 'low', false, true,
   current_setting('seoseed4.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION 2 — MAPPED KEYWORDS (13 keywords across 5 tracked pages, all
-- keyword_type/device/search_engine values represented at least once).
-- =============================================================================
SELECT '=== Section 2: mapped keywords ===' AS step;

INSERT INTO public.seo_page_keywords
  (id, workspace_id, website_id, website_url, page_id, page_url, keyword,
   keyword_type, search_intent, target_location, device, search_engine,
   priority, is_primary, created_by)
VALUES
  -- Homepage keywords.
  ('66666666-0000-0000-0002-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', 'https://ui-seed-digibility.example/',
   'seo audits for small business', 'primary', 'commercial', 'Austin, TX', 'all', 'google',
   'high', true, current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', 'https://ui-seed-digibility.example/',
   'business visibility score', 'secondary', 'informational', NULL, 'all', 'other',
   'medium', false, current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000012', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', 'https://ui-seed-digibility.example/',
   'digibility seo services', 'branded', 'navigational', NULL, 'all', 'google',
   'medium', false, current_setting('seoseed4.owner_user_id')::uuid),

  -- Services page keywords.
  ('66666666-0000-0000-0002-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', 'https://ui-seed-digibility.example/services',
   'local seo services austin', 'primary', 'commercial', 'Austin, TX', 'all', 'google',
   'high', true, current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', 'https://ui-seed-digibility.example/services',
   'technical seo audit', 'secondary', 'informational', NULL, 'desktop', 'google',
   'medium', false, current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000013', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', 'https://ui-seed-digibility.example/services',
   'seo services near me', 'local', 'transactional', 'Austin, TX', 'mobile', 'google',
   'high', false, current_setting('seoseed4.owner_user_id')::uuid),

  -- Blog listing keywords.
  ('66666666-0000-0000-0002-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', 'https://ui-seed-digibility.example/blog',
   'seo blog for small business owners', 'primary', 'informational', NULL, 'all', 'google',
   'medium', true, current_setting('seoseed4.team_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', 'https://ui-seed-digibility.example/blog',
   'small business seo tips', 'semantic', 'informational', NULL, 'mobile', 'bing',
   'low', false, current_setting('seoseed4.team_user_id')::uuid),

  -- Flagship blog post keywords.
  ('66666666-0000-0000-0002-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000004', 'https://ui-seed-digibility.example/blog/seo-checklist-small-business',
   'seo checklist for small business', 'primary', 'informational', NULL, 'all', 'google',
   'high', true, current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000004', 'https://ui-seed-digibility.example/blog/seo-checklist-small-business',
   'what should be on an seo checklist', 'question', 'informational', NULL, 'mobile', 'ai_overview',
   'medium', false, current_setting('seoseed4.owner_user_id')::uuid),

  -- Local SEO landing page keywords.
  ('66666666-0000-0000-0002-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000005', 'https://ui-seed-digibility.example/local-seo',
   'improve local search visibility', 'primary', 'informational', 'United States', 'all', 'google',
   'high', true, current_setting('seoseed4.team_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000005', 'https://ui-seed-digibility.example/local-seo',
   'google business profile optimization', 'secondary', 'transactional', 'Austin, TX', 'mobile', 'google',
   'medium', false, current_setting('seoseed4.team_user_id')::uuid),
  ('66666666-0000-0000-0002-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000005', 'https://ui-seed-digibility.example/local-seo',
   'ai search visibility guide', 'semantic', 'informational', NULL, 'all', 'ai_overview',
   'low', false, current_setting('seoseed4.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION 3 — PERFORMANCE SNAPSHOTS (20 rows: 8 page/keyword combinations
-- with an older + newer snapshot to show real movement, plus 4 single-date
-- combinations for "new" and "no_data" states). All source='manual_seed'.
-- All 5 movement_status values are represented across the resulting
-- "latest" rows: improving, stable, declining, new, no_data.
-- =============================================================================
SELECT '=== Section 3: performance snapshots ===' AS step;

INSERT INTO public.seo_page_performance_snapshots
  (id, workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, keyword,
   snapshot_date, period_start, period_end, source, clicks, impressions, ctr, average_position,
   previous_clicks, previous_impressions, previous_ctr, previous_average_position,
   clicks_delta, impressions_delta, ctr_delta, position_delta, movement_status, diagnosis_hint, created_by)
VALUES
  -- --- Homepage aggregate (page-level, page_keyword_id NULL) — improving ---
  ('66666666-0000-0000-0003-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', NULL, 'https://ui-seed-digibility.example/', NULL,
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 180, 4200, 0.0429, 8.2,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', NULL, 'https://ui-seed-digibility.example/', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 230, 4500, 0.0511, 6.9,
   180, 4200, 0.0429, 8.2, 50, 300, 0.0082, -1.3, 'improving',
   'Homepage visibility trending upward after a recent title-tag update.',
   current_setting('seoseed4.owner_user_id')::uuid),

  -- --- Homepage / "seo audits for small business" (primary keyword) — improving ---
  ('66666666-0000-0000-0003-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', '66666666-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example/', 'seo audits for small business',
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 45, 900, 0.05, 9.1,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000001', '66666666-0000-0000-0002-000000000001',
   'https://ui-seed-digibility.example/', 'seo audits for small business',
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 62, 980, 0.0633, 7.4,
   45, 900, 0.05, 9.1, 17, 80, 0.0133, -1.7, 'improving',
   'Ranking improved after the homepage title tag update.',
   current_setting('seoseed4.owner_user_id')::uuid),

  -- --- Services page aggregate — stable ---
  ('66666666-0000-0000-0003-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', NULL, 'https://ui-seed-digibility.example/services', NULL,
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 310, 6100, 0.0508, 5.5,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', NULL, 'https://ui-seed-digibility.example/services', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 305, 6050, 0.0504, 5.6,
   310, 6100, 0.0508, 5.5, -5, -50, -0.0004, 0.1, 'stable', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),

  -- --- Services / "local seo services austin" (primary keyword) — improving ---
  ('66666666-0000-0000-0003-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', '66666666-0000-0000-0002-000000000003',
   'https://ui-seed-digibility.example/services', 'local seo services austin',
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 80, 1400, 0.0571, 4.8,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000002', '66666666-0000-0000-0002-000000000003',
   'https://ui-seed-digibility.example/services', 'local seo services austin',
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 95, 1450, 0.0655, 3.9,
   80, 1400, 0.0571, 4.8, 15, 50, 0.0084, -0.9, 'improving',
   'Local pack visibility is increasing for this keyword.',
   current_setting('seoseed4.owner_user_id')::uuid),

  -- --- Blog listing aggregate — declining ---
  ('66666666-0000-0000-0003-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', NULL, 'https://ui-seed-digibility.example/blog', NULL,
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 520, 15000, 0.0347, 11.2,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.team_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', NULL, 'https://ui-seed-digibility.example/blog', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 410, 14200, 0.0289, 13.8,
   520, 15000, 0.0347, 11.2, -110, -800, -0.0058, 2.6, 'declining',
   'Blog listing page is losing visibility — content freshness may need review.',
   current_setting('seoseed4.team_user_id')::uuid),

  -- --- Blog / "seo blog for small business owners" (primary keyword) — declining ---
  ('66666666-0000-0000-0003-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', '66666666-0000-0000-0002-000000000005',
   'https://ui-seed-digibility.example/blog', 'seo blog for small business owners',
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 60, 1800, 0.0333, 10.5,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.team_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000012', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000003', '66666666-0000-0000-0002-000000000005',
   'https://ui-seed-digibility.example/blog', 'seo blog for small business owners',
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 41, 1650, 0.0248, 13.1,
   60, 1800, 0.0333, 10.5, -19, -150, -0.0085, 2.6, 'declining',
   'Ranking dropped; consider refreshing the blog index page content.',
   current_setting('seoseed4.team_user_id')::uuid),

  -- --- Flagship blog post aggregate — stable ---
  ('66666666-0000-0000-0003-000000000013', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000004', NULL,
   'https://ui-seed-digibility.example/blog/seo-checklist-small-business', NULL,
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 140, 3100, 0.0452, 6.8,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000014', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000004', NULL,
   'https://ui-seed-digibility.example/blog/seo-checklist-small-business', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 138, 3080, 0.0448, 6.9,
   140, 3100, 0.0452, 6.8, -2, -20, -0.0004, 0.1, 'stable', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),

  -- --- Flagship blog post / "seo checklist for small business" — improving ---
  ('66666666-0000-0000-0003-000000000015', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000004', '66666666-0000-0000-0002-000000000007',
   'https://ui-seed-digibility.example/blog/seo-checklist-small-business', 'seo checklist for small business',
   current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
   'manual_seed', 95, 1600, 0.0594, 4.2,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.owner_user_id')::uuid),
  ('66666666-0000-0000-0003-000000000016', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000004', '66666666-0000-0000-0002-000000000007',
   'https://ui-seed-digibility.example/blog/seo-checklist-small-business', 'seo checklist for small business',
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 124, 1720, 0.0721, 2.9,
   95, 1600, 0.0594, 4.2, 29, 120, 0.0127, -1.3, 'improving',
   'Strong upward movement — this is a flagship content piece.',
   current_setting('seoseed4.owner_user_id')::uuid),

  -- --- Local SEO landing page aggregate — new (single snapshot, no prior data) ---
  ('66666666-0000-0000-0003-000000000017', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000005', NULL, 'https://ui-seed-digibility.example/local-seo', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 28, 650, 0.0431, 15.3,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'new',
   'Newly published page — not enough history yet for a trend.',
   current_setting('seoseed4.team_user_id')::uuid),

  -- --- Local SEO / "improve local search visibility" (primary keyword) — new ---
  ('66666666-0000-0000-0003-000000000018', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000005', '66666666-0000-0000-0002-000000000009',
   'https://ui-seed-digibility.example/local-seo', 'improve local search visibility',
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 12, 310, 0.0387, 17.1,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'new', NULL,
   current_setting('seoseed4.team_user_id')::uuid),

  -- --- Contact page aggregate — no_data (untracked page, minimal signal) ---
  ('66666666-0000-0000-0003-000000000019', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000006', NULL, 'https://ui-seed-digibility.example/contact', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 0, 4, 0, NULL,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data',
   'Not enough search data collected for this page yet.',
   current_setting('seoseed4.team_user_id')::uuid),

  -- --- Pricing page aggregate — no_data (untracked page, minimal signal) ---
  ('66666666-0000-0000-0003-000000000020', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '66666666-0000-0000-0001-000000000007', NULL, 'https://ui-seed-digibility.example/pricing', NULL,
   current_date, current_date - interval '6 days', current_date,
   'manual_seed', 0, 2, 0, NULL,
   NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'no_data', NULL,
   current_setting('seoseed4.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION 4 — VERIFICATION (compact row counts, scoped to the base seed's
-- workspace, plus a movement_status breakdown of the "latest" view).
-- =============================================================================
SELECT '=== Section 4: verification counts ===' AS step;

SELECT entity, count FROM (
  SELECT 1 AS ord, 'page inventory rows'   AS entity, count(*) AS count FROM public.seo_page_inventory           WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%'
  UNION ALL
  SELECT 2, 'page keywords',              count(*) FROM public.seo_page_keywords              WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%'
  UNION ALL
  SELECT 3, 'performance snapshots',      count(*) FROM public.seo_page_performance_snapshots WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%'
  UNION ALL
  SELECT 4, 'latest view rows',           count(*) FROM public.seo_page_performance_latest    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%'
  UNION ALL
  SELECT 5, 'latest: improving',          count(*) FROM public.seo_page_performance_latest    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%' AND movement_status = 'improving'
  UNION ALL
  SELECT 6, 'latest: stable',             count(*) FROM public.seo_page_performance_latest    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%' AND movement_status = 'stable'
  UNION ALL
  SELECT 7, 'latest: declining',          count(*) FROM public.seo_page_performance_latest    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%' AND movement_status = 'declining'
  UNION ALL
  SELECT 8, 'latest: new',                count(*) FROM public.seo_page_performance_latest    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%' AND movement_status = 'new'
  UNION ALL
  SELECT 9, 'latest: no_data',            count(*) FROM public.seo_page_performance_latest    WHERE workspace_id = '44444444-0000-0000-0001-000000000001' AND id::text LIKE '66666666-%' AND movement_status = 'no_data'
) v
ORDER BY ord;

SELECT '=== STAGE 4 PAGE PERFORMANCE SEED EXTENSION — complete. See counts above. ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the rows this script created,
-- identified by the 66666666- prefix; does NOT touch the base UI seed's
-- workspace/website/onboarding/audit/approval/content rows or any other
-- seed/smoke test). Commented out on purpose — uncomment and run manually
-- only if you want to remove this extension's data from the test project.
-- =============================================================================
-- DELETE FROM public.seo_page_performance_snapshots WHERE id::text LIKE '66666666-%';
-- DELETE FROM public.seo_page_keywords WHERE id::text LIKE '66666666-%';
-- DELETE FROM public.seo_page_inventory WHERE id::text LIKE '66666666-%';
