-- =============================================================================
-- SEO Stage 4 — Page Performance Tracker — SMOKE TEST DRAFT (TEST ONLY)
-- =============================================================================
-- DRAFT — written alongside the Stage 4 migrations for review. NOT executed
-- as part of Phase 14A.1. RUN ONLY on a FRESH/disposable Supabase TEST
-- project, AFTER Stage 1 (…120001–120003), Stage 2 (…120004–120006), and
-- Stage 4 (…120010–120013) migrations are applied. NEVER run on production.
-- (Stage 3 is not required by this smoke test, but applying stages in order
-- is still recommended.)
--
-- This script is NON-DESTRUCTIVE to Core data. It seeds test rows under one
-- disposable test workspace (UUID prefix 55555555-, distinct from Stage 2's
-- aaaaaaaa-/bbbbbbbb-/cccccccc-/dddddddd-/eeeeeeee-/ffffffff-, Stage 3's
-- 33333333-, and the UI dataset seed's 44444444- — cannot collide with any of
-- them) and drops one test-only helper function at the end. Optional teardown
-- (deletes ONLY the test workspace) is at the very bottom, commented out.
--
-- PREREQUISITE — five users must already exist in Supabase Auth (Dashboard →
-- Authentication → Users), then paste their UUIDs below. FKs reference
-- auth.users, so real users are required. Do NOT insert into auth.users from
-- SQL. Do NOT use a service role key anywhere in this script.
-- =============================================================================

-- ---------- 0. PASTE TEST USER UUIDS HERE (session-scoped GUCs) --------------
SELECT set_config('seo4.owner_id',     '48c479db-aedf-452e-af43-05ed1180baaa',     false);
SELECT set_config('seo4.admin_id',     '9830c4d7-167b-4d78-9179-37b60511bd73',     false);
SELECT set_config('seo4.team_id',      '0723d21f-c02c-4725-851f-575f93f2f58c',      false);
SELECT set_config('seo4.client_id',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c',    false);
SELECT set_config('seo4.nonmember_id', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

-- Guard: refuse to run until every UUID above has been replaced with a real,
-- correctly-formatted UUID (not left as a placeholder, not an email).
DO $$
DECLARE
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_pairs text[][] := ARRAY[
    ARRAY['owner_id',     'REPLACE_WITH_OWNER_TEST_UUID'],
    ARRAY['admin_id',     'REPLACE_WITH_ADMIN_TEST_UUID'],
    ARRAY['team_id',      'REPLACE_WITH_TEAM_TEST_UUID'],
    ARRAY['client_id',    'REPLACE_WITH_CLIENT_TEST_UUID'],
    ARRAY['nonmember_id', 'REPLACE_WITH_NONMEMBER_TEST_UUID']
  ];
  v_key text;
  v_placeholder text;
  v_value text;
  i int;
BEGIN
  FOR i IN 1 .. array_upper(v_pairs, 1) LOOP
    v_key := v_pairs[i][1];
    v_placeholder := v_pairs[i][2];
    v_value := current_setting('seo4.' || v_key, true);
    IF v_value IS NULL OR v_value = v_placeholder THEN
      RAISE EXCEPTION 'seo4.% is still a placeholder — paste a real auth.users UUID at the top of this script before running.', v_key;
    END IF;
    IF v_value !~ v_uuid_pattern THEN
      RAISE EXCEPTION 'seo4.% ("%") is not a valid UUID. Paste the user''s UUID from auth.users, not an email address.', v_key, v_value;
    END IF;
  END LOOP;
END $$;

-- ---------- Test-only login helper (dropped at the end) ---------------------
-- Sets the JWT-claim GUCs so auth.uid() resolves to the given user inside the
-- current transaction. Combine with: SET LOCAL ROLE authenticated;
CREATE OR REPLACE FUNCTION public._seo4_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $$;

-- Fixed UUIDs for disposable test entities (readable + re-referenceable).
--   Workspace: 55555555-…01   Website: 55555555-…b1
--   Pages:     55555555-…c1 (tracked/active) · …c2 (second page, for the
--              active-URL-uniqueness check)
--   Keywords:  55555555-…d1 (primary, page c1) · …d2 (secondary, page c1)
--   Snapshots: 55555555-…e1 (older, keyword d1) · …e2 (newer, keyword d1,
--              same page/keyword — proves the "latest" view picks this one)
--              · …e3 (page-level aggregate, page_keyword_id NULL)

-- =============================================================================
-- 1. SETUP — workspace, members, website, module access (run as the
--    privileged editor role; RLS bypassed for seeding, same as both existing
--    smoke tests).
-- =============================================================================
SELECT '=== SETUP: workspace, members, website, module access ===' AS step;

INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seo4.' || k)::uuid, 'seo', true
FROM (VALUES ('owner_id'), ('admin_id'), ('team_id'), ('client_id'), ('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

-- Owner is auto-added as an active 'owner' member by the Stage 1 AFTER INSERT
-- trigger — do NOT insert that member row manually.
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('55555555-0000-0000-0000-000000000001', 'Stage4 Smoke Test WS',
        current_setting('seo4.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES
  ('55555555-0000-0000-0000-000000000001', current_setting('seo4.admin_id')::uuid,  'admin',       'active'),
  ('55555555-0000-0000-0000-000000000001', current_setting('seo4.team_id')::uuid,   'team_member', 'active'),
  ('55555555-0000-0000-0000-000000000001', current_setting('seo4.client_id')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES ('55555555-0000-0000-0000-0000000000b1', '55555555-0000-0000-0000-000000000001',
        'https://stage4-smoke-test.example', 'Stage4 Smoke Test Site', 'Stage4 Smoke Test Co')
ON CONFLICT (workspace_id, website_url) DO NOTHING;

-- =============================================================================
-- 2. Page inventory insert — as team_member (positive case). Also proves the
--    active-URL uniqueness partial index accepts a second, different URL.
-- =============================================================================
SELECT '=== 2. page inventory insert (team_member) ===' AS step;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_page_inventory
    (id, workspace_id, website_id, website_url, page_url, page_title, page_type, is_tracked, is_active)
  VALUES
    ('55555555-0000-0000-0000-0000000000c1', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     'https://stage4-smoke-test.example/services/seo-audits', 'SEO Audits', 'service_page', true, true),
    ('55555555-0000-0000-0000-0000000000c2', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     'https://stage4-smoke-test.example/blog/local-seo-tips', 'Local SEO Tips', 'blog', true, true)
  ON CONFLICT DO NOTHING;
COMMIT;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_page_inventory
  WHERE id IN ('55555555-0000-0000-0000-0000000000c1', '55555555-0000-0000-0000-0000000000c2');
  IF n = 2 THEN RAISE NOTICE 'PASS: team_member inserted 2 page inventory rows';
  ELSE RAISE EXCEPTION 'FAIL: expected 2 page rows, found %', n; END IF;
END $$;

-- Active-URL uniqueness: a second ACTIVE row for the same website+URL must
-- be rejected by the partial unique index (run as privileged editor role).
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_page_inventory
      (workspace_id, website_id, website_url, page_url, is_active)
    VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
            'https://stage4-smoke-test.example',
            'https://stage4-smoke-test.example/services/seo-audits', true);
    RAISE EXCEPTION 'FAIL: duplicate active page_url was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: duplicate active page_url rejected (%)', SQLERRM;
  END;
END $$;

-- =============================================================================
-- 3. Page keyword insert — as team_member (positive case).
-- =============================================================================
SELECT '=== 3. page keyword insert (team_member) ===' AS step;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_page_keywords
    (id, workspace_id, website_id, website_url, page_id, page_url, keyword, keyword_type, is_primary)
  VALUES
    ('55555555-0000-0000-0000-0000000000d1', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     '55555555-0000-0000-0000-0000000000c1', 'https://stage4-smoke-test.example/services/seo-audits',
     'seo audit services', 'primary', true),
    ('55555555-0000-0000-0000-0000000000d2', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     '55555555-0000-0000-0000-0000000000c1', 'https://stage4-smoke-test.example/services/seo-audits',
     'website seo audit', 'secondary', false)
  ON CONFLICT DO NOTHING;
COMMIT;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_page_keywords WHERE page_id = '55555555-0000-0000-0000-0000000000c1';
  IF n = 2 THEN RAISE NOTICE 'PASS: team_member inserted 2 page keyword rows';
  ELSE RAISE EXCEPTION 'FAIL: expected 2 keyword rows, found %', n; END IF;
END $$;

-- =============================================================================
-- 4. Performance snapshot insert — as team_member. Two dated snapshots for
--    the same page+keyword (proves "latest" resolution), plus one page-level
--    aggregate snapshot (page_keyword_id NULL).
-- =============================================================================
SELECT '=== 4. performance snapshot insert (team_member) ===' AS step;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_page_performance_snapshots
    (id, workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, keyword,
     snapshot_date, period_start, period_end, source, clicks, impressions, ctr, average_position,
     movement_status)
  VALUES
    -- older snapshot (14 days ago)
    ('55555555-0000-0000-0000-0000000000e1', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     '55555555-0000-0000-0000-0000000000c1', '55555555-0000-0000-0000-0000000000d1',
     'https://stage4-smoke-test.example/services/seo-audits', 'seo audit services',
     current_date - interval '14 days', current_date - interval '20 days', current_date - interval '14 days',
     'manual_seed', 40, 900, 0.044, 12.5, 'no_data'),
    -- newer snapshot (today) — same page + keyword, must win as "latest"
    ('55555555-0000-0000-0000-0000000000e2', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     '55555555-0000-0000-0000-0000000000c1', '55555555-0000-0000-0000-0000000000d1',
     'https://stage4-smoke-test.example/services/seo-audits', 'seo audit services',
     current_date, current_date - interval '13 days', current_date,
     'manual_seed', 58, 1100, 0.0527, 9.8, 'improving'),
    -- page-level aggregate (no specific keyword)
    ('55555555-0000-0000-0000-0000000000e3', '55555555-0000-0000-0000-000000000001',
     '55555555-0000-0000-0000-0000000000b1', 'https://stage4-smoke-test.example',
     '55555555-0000-0000-0000-0000000000c1', NULL,
     'https://stage4-smoke-test.example/services/seo-audits', NULL,
     current_date, current_date - interval '13 days', current_date,
     'manual_seed', 70, 1500, 0.0467, 11.2, 'stable')
  ON CONFLICT DO NOTHING;
COMMIT;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_page_performance_snapshots WHERE page_id = '55555555-0000-0000-0000-0000000000c1';
  IF n = 3 THEN RAISE NOTICE 'PASS: team_member inserted 3 performance snapshot rows';
  ELSE RAISE EXCEPTION 'FAIL: expected 3 snapshot rows, found %', n; END IF;
END $$;

-- Duplicate (page_id, page_keyword_id, snapshot_date, source) must be rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_page_performance_snapshots
      (workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, keyword,
       snapshot_date, period_start, period_end, source)
    VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
            'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
            '55555555-0000-0000-0000-0000000000d1', 'https://stage4-smoke-test.example/services/seo-audits',
            'seo audit services', current_date, current_date - interval '13 days', current_date, 'manual_seed');
    RAISE EXCEPTION 'FAIL: duplicate page+keyword+date+source snapshot was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: duplicate page+keyword+date+source snapshot rejected (%)', SQLERRM;
  END;
END $$;

-- =============================================================================
-- 5. seo_page_performance_latest view — resolves to the newest snapshot per
--    (page_id, page_keyword_id).
-- =============================================================================
SELECT '=== 5. seo_page_performance_latest view ===' AS step;

DO $$
DECLARE v_id uuid; v_clicks int; v_status text;
BEGIN
  SELECT id, clicks, movement_status INTO v_id, v_clicks, v_status
  FROM public.seo_page_performance_latest
  WHERE page_id = '55555555-0000-0000-0000-0000000000c1' AND page_keyword_id = '55555555-0000-0000-0000-0000000000d1';

  IF v_id = '55555555-0000-0000-0000-0000000000e2' AND v_clicks = 58 AND v_status = 'improving' THEN
    RAISE NOTICE 'PASS: latest view resolved to the newer snapshot (id=%, clicks=%, status=%)', v_id, v_clicks, v_status;
  ELSE
    RAISE EXCEPTION 'FAIL: latest view returned id=% clicks=% status=% (expected e2/58/improving)', v_id, v_clicks, v_status;
  END IF;
END $$;

DO $$
DECLARE n int;
BEGIN
  -- One row for (c1, d1) + one row for (c1, NULL aggregate) = 2 distinct groups.
  SELECT count(*) INTO n FROM public.seo_page_performance_latest WHERE page_id = '55555555-0000-0000-0000-0000000000c1';
  IF n = 2 THEN RAISE NOTICE 'PASS: latest view returns exactly one row per (page, keyword) group (%)', n;
  ELSE RAISE EXCEPTION 'FAIL: latest view returned % rows for page c1 (expected 2)', n; END IF;
END $$;

-- =============================================================================
-- 6. RLS — SELECT access for owner/admin/team/client (all should see the
--    seeded rows); non-member sees nothing.
--
-- IMPORTANT: setting the JWT-claim GUCs via _seo4_login()/set_config() alone
-- makes auth.uid() resolve correctly, but it does NOT change the actual
-- database ROLE the script is running as. In the Supabase SQL Editor that
-- role is `postgres`, which has BYPASSRLS — so a bare DO block that only
-- sets JWT claims still sees every row regardless of policy, because RLS is
-- never evaluated for that role in the first place. Each role check below
-- must run inside its own `BEGIN; ... SET LOCAL ROLE authenticated; ...
-- ROLLBACK;` transaction (exactly like §7 below and both Stage 2/3 smoke
-- tests' table-level RLS checks) so the SELECTs are actually executed as
-- `authenticated` and RLS is genuinely exercised, not bypassed.
-- =============================================================================
SELECT '=== 6. RLS select access per role ===' AS step;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_inv int; n_kw int; n_snap int; n_view int;
  BEGIN
    SELECT count(*) INTO n_inv FROM public.seo_page_inventory WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_kw FROM public.seo_page_keywords WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_snap FROM public.seo_page_performance_snapshots WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_view FROM public.seo_page_performance_latest WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    IF n_inv = 2 AND n_kw = 2 AND n_snap = 3 AND n_view = 2 THEN
      RAISE NOTICE 'PASS: owner_id can read inventory(%) keywords(%) snapshots(%) latest-view(%)', n_inv, n_kw, n_snap, n_view;
    ELSE
      RAISE EXCEPTION 'FAIL: owner_id read inventory=% keywords=% snapshots=% view=% (expected 2/2/3/2)', n_inv, n_kw, n_snap, n_view;
    END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_inv int; n_kw int; n_snap int; n_view int;
  BEGIN
    SELECT count(*) INTO n_inv FROM public.seo_page_inventory WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_kw FROM public.seo_page_keywords WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_snap FROM public.seo_page_performance_snapshots WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_view FROM public.seo_page_performance_latest WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    IF n_inv = 2 AND n_kw = 2 AND n_snap = 3 AND n_view = 2 THEN
      RAISE NOTICE 'PASS: admin_id can read inventory(%) keywords(%) snapshots(%) latest-view(%)', n_inv, n_kw, n_snap, n_view;
    ELSE
      RAISE EXCEPTION 'FAIL: admin_id read inventory=% keywords=% snapshots=% view=% (expected 2/2/3/2)', n_inv, n_kw, n_snap, n_view;
    END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_inv int; n_kw int; n_snap int; n_view int;
  BEGIN
    SELECT count(*) INTO n_inv FROM public.seo_page_inventory WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_kw FROM public.seo_page_keywords WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_snap FROM public.seo_page_performance_snapshots WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_view FROM public.seo_page_performance_latest WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    IF n_inv = 2 AND n_kw = 2 AND n_snap = 3 AND n_view = 2 THEN
      RAISE NOTICE 'PASS: team_id can read inventory(%) keywords(%) snapshots(%) latest-view(%)', n_inv, n_kw, n_snap, n_view;
    ELSE
      RAISE EXCEPTION 'FAIL: team_id read inventory=% keywords=% snapshots=% view=% (expected 2/2/3/2)', n_inv, n_kw, n_snap, n_view;
    END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_inv int; n_kw int; n_snap int; n_view int;
  BEGIN
    SELECT count(*) INTO n_inv FROM public.seo_page_inventory WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_kw FROM public.seo_page_keywords WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_snap FROM public.seo_page_performance_snapshots WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_view FROM public.seo_page_performance_latest WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    IF n_inv = 2 AND n_kw = 2 AND n_snap = 3 AND n_view = 2 THEN
      RAISE NOTICE 'PASS: client_id can read inventory(%) keywords(%) snapshots(%) latest-view(%)', n_inv, n_kw, n_snap, n_view;
    ELSE
      RAISE EXCEPTION 'FAIL: client_id read inventory=% keywords=% snapshots=% view=% (expected 2/2/3/2)', n_inv, n_kw, n_snap, n_view;
    END IF;
  END $$;
ROLLBACK;

-- Non-member: RLS filters every row out (0, not an error). Same
-- BEGIN/SET LOCAL ROLE/ROLLBACK requirement as above — this is the exact
-- block that previously ran as postgres/BYPASSRLS and therefore falsely
-- saw every row.
BEGIN;
  SELECT public._seo4_login(current_setting('seo4.nonmember_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_inv int; n_kw int; n_snap int; n_view int;
  BEGIN
    SELECT count(*) INTO n_inv FROM public.seo_page_inventory WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_kw FROM public.seo_page_keywords WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_snap FROM public.seo_page_performance_snapshots WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_view FROM public.seo_page_performance_latest WHERE workspace_id = '55555555-0000-0000-0000-000000000001';
    IF n_inv = 0 AND n_kw = 0 AND n_snap = 0 AND n_view = 0 THEN
      RAISE NOTICE 'PASS: non-member sees 0 rows across inventory/keywords/snapshots/latest-view (workspace isolation)';
    ELSE
      RAISE EXCEPTION 'FAIL: non-member read inventory=% keywords=% snapshots=% view=% (expected all 0)', n_inv, n_kw, n_snap, n_view;
    END IF;
  END $$;
ROLLBACK;

-- =============================================================================
-- 7. RLS — client cannot insert/update page inventory, keywords, or snapshots.
-- =============================================================================
SELECT '=== 7. RLS write denial for client ===' AS step;

BEGIN;
  SELECT public._seo4_login(current_setting('seo4.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n int;
  BEGIN
    -- INSERT: RLS WITH CHECK failure raises, it does not silently insert 0 rows.
    BEGIN
      INSERT INTO public.seo_page_inventory (workspace_id, website_id, website_url, page_url)
      VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
              'https://stage4-smoke-test.example', 'https://stage4-smoke-test.example/client-attempt');
      RAISE EXCEPTION 'FAIL: client inserted a page inventory row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting page inventory (%)', SQLERRM;
    END;

    BEGIN
      INSERT INTO public.seo_page_keywords (workspace_id, website_id, website_url, page_id, page_url, keyword)
      VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
              'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
              'https://stage4-smoke-test.example/services/seo-audits', 'client attempt keyword');
      RAISE EXCEPTION 'FAIL: client inserted a page keyword row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting page keywords (%)', SQLERRM;
    END;

    BEGIN
      INSERT INTO public.seo_page_performance_snapshots
        (workspace_id, website_id, website_url, page_id, page_url, snapshot_date, period_start, period_end)
      VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
              'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
              'https://stage4-smoke-test.example/services/seo-audits',
              current_date + 1, current_date, current_date + 1);
      RAISE EXCEPTION 'FAIL: client inserted a performance snapshot row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting performance snapshots (%)', SQLERRM;
    END;

    -- UPDATE: RLS silently affects 0 rows (no exception) — same pattern as
    -- Stage 2's client-direct-edit check on seo_approval_items.
    UPDATE public.seo_page_inventory SET page_title = 'hacked' WHERE id = '55555555-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN RAISE NOTICE 'PASS: client direct UPDATE on page inventory blocked by RLS (0 rows)';
    ELSE RAISE EXCEPTION 'FAIL: client updated % page inventory row(s)', n; END IF;
  END $$;
ROLLBACK;

-- =============================================================================
-- 8. Constraint checks — invalid ctr / movement_status / device / source are
--    all rejected (run as privileged editor role; these are plain CHECK
--    constraint violations, unrelated to RLS).
-- =============================================================================
SELECT '=== 8. CHECK constraint rejection ===' AS step;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_page_performance_snapshots
      (workspace_id, website_id, website_url, page_id, page_url, snapshot_date, period_start, period_end, ctr)
    VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
            'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
            'https://stage4-smoke-test.example/services/seo-audits', current_date + 2, current_date, current_date + 2, 1.5);
    RAISE EXCEPTION 'FAIL: ctr=1.5 (out of 0..1 range) was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: ctr out of range rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_page_performance_snapshots
      (workspace_id, website_id, website_url, page_id, page_url, snapshot_date, period_start, period_end, movement_status)
    VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
            'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
            'https://stage4-smoke-test.example/services/seo-audits', current_date + 3, current_date, current_date + 3, 'skyrocketing');
    RAISE EXCEPTION 'FAIL: invalid movement_status was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid movement_status rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_page_keywords (workspace_id, website_id, website_url, page_id, page_url, keyword, device)
    VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
            'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
            'https://stage4-smoke-test.example/services/seo-audits', 'bad device keyword', 'tablet');
    RAISE EXCEPTION 'FAIL: invalid device was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid device rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_page_performance_snapshots
      (workspace_id, website_id, website_url, page_id, page_url, snapshot_date, period_start, period_end, source)
    VALUES ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-0000000000b1',
            'https://stage4-smoke-test.example', '55555555-0000-0000-0000-0000000000c1',
            'https://stage4-smoke-test.example/services/seo-audits', current_date + 4, current_date, current_date + 4, 'web_scraper');
    RAISE EXCEPTION 'FAIL: invalid source was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid source rejected (%)', SQLERRM;
  END;
END $$;

-- ---------- cleanup of the test-only helper --------------------------------
DROP FUNCTION IF EXISTS public._seo4_login(uuid);

SELECT '=== STAGE 4 SMOKE TEST COMPLETE — check the Messages/Notices tab for PASS/FAIL ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the one test workspace and
-- everything that cascades from it: website, page inventory, keywords,
-- snapshots). Uncomment and run manually if you want a clean project.
-- =============================================================================
-- DELETE FROM public.seo_workspaces WHERE id = '55555555-0000-0000-0000-000000000001';
-- DELETE FROM public.user_module_access WHERE module_name='seo' AND user_id IN (
--   current_setting('seo4.owner_id')::uuid, current_setting('seo4.admin_id')::uuid,
--   current_setting('seo4.team_id')::uuid, current_setting('seo4.client_id')::uuid,
--   current_setting('seo4.nonmember_id')::uuid);
