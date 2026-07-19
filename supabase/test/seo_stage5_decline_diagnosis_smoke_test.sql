-- =============================================================================
-- SEO Stage 5 — Decline Diagnosis Engine — SMOKE TEST DRAFT (TEST ONLY)
-- =============================================================================
-- DRAFT — written alongside the Stage 5 migrations for review. NOT executed as
-- part of Phase 14B.1. RUN ONLY on a FRESH/disposable Supabase TEST project,
-- AFTER Stage 1 (…120001–120003), Stage 2 (…120004–120006), Stage 4
-- (…120010–120013), and Stage 5 (…120014–120016) migrations are applied.
-- NEVER run on production. (Stage 3 is not required by this smoke test, but
-- applying stages in order is still recommended.)
--
-- This script is NON-DESTRUCTIVE to Core data. It seeds test rows under one
-- disposable test workspace (UUID prefix 77777777-, distinct from Stage 2's
-- aaaaaaaa-…ffffffff-, Stage 3's 33333333-, the UI dataset seed's 44444444-,
-- and Stage 4's smoke-test 55555555-) and drops one test-only helper function
-- at the end. Optional teardown (deletes ONLY the test workspace) is at the
-- very bottom, commented out. The Stage 5 view + RPC are permanent schema from
-- the migrations and are NOT dropped.
--
-- PREREQUISITE — five users must already exist in Supabase Auth (Dashboard →
-- Authentication → Users), then paste their UUIDs below. FKs reference
-- auth.users, so real users are required. Do NOT insert into auth.users from
-- SQL. Do NOT use a service role key anywhere in this script.
--
-- RLS NOTE (the Stage 4 lesson): setting the JWT-claim GUCs via _seo5_login()
-- alone makes auth.uid() resolve correctly, but it does NOT change the actual
-- database ROLE the script runs as. In the Supabase SQL Editor that role is
-- `postgres`, which has BYPASSRLS — so a bare DO block that only sets JWT
-- claims still sees/writes every row regardless of policy. Every RLS check
-- below therefore runs inside its own `BEGIN; … SET LOCAL ROLE authenticated;
-- … ROLLBACK;` (or COMMIT for the persistent positive inserts) so RLS is
-- genuinely exercised as `authenticated`, not bypassed.
-- =============================================================================

-- ---------- 0. PASTE TEST USER UUIDS HERE (session-scoped GUCs) --------------
SELECT set_config('seo5.owner_id',     '48c479db-aedf-452e-af43-05ed1180baaa',     false);
SELECT set_config('seo5.admin_id',     '9830c4d7-167b-4d78-9179-37b60511bd73',     false);
SELECT set_config('seo5.team_id',      '0723d21f-c02c-4725-851f-575f93f2f58c',      false);
SELECT set_config('seo5.client_id',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c',    false);
SELECT set_config('seo5.nonmember_id', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

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
    v_value := current_setting('seo5.' || v_key, true);
    IF v_value IS NULL OR v_value = v_placeholder THEN
      RAISE EXCEPTION 'seo5.% is still a placeholder — paste a real auth.users UUID at the top of this script before running.', v_key;
    END IF;
    IF v_value !~ v_uuid_pattern THEN
      RAISE EXCEPTION 'seo5.% ("%") is not a valid UUID. Paste the user''s UUID from auth.users, not an email address.', v_key, v_value;
    END IF;
  END LOOP;
END $$;

-- ---------- Test-only login helper (dropped at the end) ---------------------
-- Sets the JWT-claim GUCs so auth.uid() resolves to the given user inside the
-- current transaction. Combine with: SET LOCAL ROLE authenticated;
CREATE OR REPLACE FUNCTION public._seo5_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $$;

-- Fixed UUIDs for disposable test entities (readable + re-referenceable).
--   Workspace: 77777777-…01   Website: 77777777-…b1
--   Page:      77777777-…c1   Keyword: 77777777-…d1
--   Snapshot:  77777777-…e1   (has previous_* metrics so the RPC derives
--                              4 evidence rows deterministically)
--   Diagnosis: 77777777-…f1   (manual insert in §2)

-- =============================================================================
-- 1. SETUP — workspace, members, website, module access, plus the Stage 4
--    prerequisites (one page, one keyword, one performance snapshot). Seeded
--    as the privileged editor role; RLS is bypassed for seeding, same as every
--    existing smoke test. The Stage 4 tables' own RLS is already covered by
--    the Stage 4 smoke test — here they are just fixtures for Stage 5.
-- =============================================================================
SELECT '=== SETUP: workspace, members, website, page, keyword, snapshot ===' AS step;

INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seo5.' || k)::uuid, 'seo', true
FROM (VALUES ('owner_id'), ('admin_id'), ('team_id'), ('client_id'), ('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

-- Owner is auto-added as an active 'owner' member by the Stage 1 AFTER INSERT
-- trigger — do NOT insert that member row manually.
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('77777777-0000-0000-0000-000000000001', 'Stage5 Decline Diagnosis Smoke Test WS',
        current_setting('seo5.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES
  ('77777777-0000-0000-0000-000000000001', current_setting('seo5.admin_id')::uuid,  'admin',       'active'),
  ('77777777-0000-0000-0000-000000000001', current_setting('seo5.team_id')::uuid,   'team_member', 'active'),
  ('77777777-0000-0000-0000-000000000001', current_setting('seo5.client_id')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES ('77777777-0000-0000-0000-0000000000b1', '77777777-0000-0000-0000-000000000001',
        'https://stage5-smoke-test.example', 'Stage5 Smoke Test Site', 'Stage5 Smoke Test Co')
ON CONFLICT (workspace_id, website_url) DO NOTHING;

INSERT INTO public.seo_page_inventory
  (id, workspace_id, website_id, website_url, page_url, page_title, page_type,
   content_status, indexability_status, is_tracked, is_active)
VALUES ('77777777-0000-0000-0000-0000000000c1', '77777777-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-0000000000b1', 'https://stage5-smoke-test.example',
        'https://stage5-smoke-test.example/services/seo-audits', 'SEO Audits', 'service_page',
        'aging', 'indexable', true, true)
ON CONFLICT DO NOTHING;

INSERT INTO public.seo_page_keywords
  (id, workspace_id, website_id, website_url, page_id, page_url, keyword, keyword_type, is_primary)
VALUES ('77777777-0000-0000-0000-0000000000d1', '77777777-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-0000000000b1', 'https://stage5-smoke-test.example',
        '77777777-0000-0000-0000-0000000000c1', 'https://stage5-smoke-test.example/services/seo-audits',
        'seo audit services', 'primary', true)
ON CONFLICT DO NOTHING;

-- Snapshot with previous_* metrics: a CTR + ranking decline, so the RPC can
-- deterministically derive 4 evidence rows (clicks, impressions, ctr, position).
INSERT INTO public.seo_page_performance_snapshots
  (id, workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, keyword,
   snapshot_date, period_start, period_end, source,
   clicks, impressions, ctr, average_position,
   previous_clicks, previous_impressions, previous_ctr, previous_average_position,
   movement_status)
VALUES ('77777777-0000-0000-0000-0000000000e1', '77777777-0000-0000-0000-000000000001',
        '77777777-0000-0000-0000-0000000000b1', 'https://stage5-smoke-test.example',
        '77777777-0000-0000-0000-0000000000c1', '77777777-0000-0000-0000-0000000000d1',
        'https://stage5-smoke-test.example/services/seo-audits', 'seo audit services',
        current_date, current_date - interval '30 days', current_date, 'manual_seed',
        60, 2000, 0.03, 8.5,
        100, 2100, 0.0476, 6.2,
        'declining')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 2. Diagnosis insert — as team_member (positive). Persisted (COMMIT) so the
--    later read/RLS checks can see it.
-- =============================================================================
SELECT '=== 2. decline diagnosis insert (team_member) ===' AS step;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_decline_diagnoses
    (id, workspace_id, website_id, website_url, page_id, page_url,
     page_keyword_id, keyword, performance_snapshot_id,
     diagnosis_type, severity, confidence_percentage, movement_status,
     business_summary, likely_cause, technical_explanation,
     recommended_next_action, suggested_owner, priority, status)
  VALUES
    ('77777777-0000-0000-0000-0000000000f1', '77777777-0000-0000-0000-000000000001',
     '77777777-0000-0000-0000-0000000000b1', 'https://stage5-smoke-test.example',
     '77777777-0000-0000-0000-0000000000c1', 'https://stage5-smoke-test.example/services/seo-audits',
     '77777777-0000-0000-0000-0000000000d1', 'seo audit services', NULL,
     'ranking_decline', 'high', 68, 'declining',
     'This page is slipping down the results for its main search, so fewer people are finding it.',
     'A competitor appears to have strengthened their page for this search recently.',
     'Average position moved from ~6 to ~8 over the last 30 days for the primary keyword.',
     'Review the competing pages and plan a focused content refresh.',
     'digibility_expert', 'high', 'open')
  ON CONFLICT DO NOTHING;
COMMIT;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_decline_diagnoses WHERE id = '77777777-0000-0000-0000-0000000000f1';
  IF n = 1 THEN RAISE NOTICE 'PASS: team_member inserted 1 decline diagnosis row';
  ELSE RAISE EXCEPTION 'FAIL: expected 1 diagnosis row, found %', n; END IF;
END $$;

-- =============================================================================
-- 3. Evidence insert — as admin (positive). Persisted (COMMIT).
-- =============================================================================
SELECT '=== 3. diagnosis evidence insert (admin) ===' AS step;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_decline_diagnosis_evidence
    (workspace_id, website_id, website_url, diagnosis_id, evidence_type,
     metric_name, current_value, previous_value, delta_value, evidence_summary, source)
  VALUES
    ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
     'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000f1', 'ranking',
     'average_position', '8.5', '6.2', '2.3',
     'Average position fell by ~2.3 places for the primary keyword.', 'performance_snapshot')
  ON CONFLICT DO NOTHING;
COMMIT;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_decline_diagnosis_evidence WHERE diagnosis_id = '77777777-0000-0000-0000-0000000000f1';
  IF n = 1 THEN RAISE NOTICE 'PASS: admin inserted 1 diagnosis evidence row';
  ELSE RAISE EXCEPTION 'FAIL: expected 1 evidence row for f1, found %', n; END IF;
END $$;

-- =============================================================================
-- 4. RPC — seo_create_decline_diagnosis_from_snapshot as team_member
--    (positive). Deterministically snapshots page/keyword/url/movement from
--    snapshot e1 and auto-derives evidence from its stored metrics (4 rows:
--    clicks, impressions, ctr, average_position). Persisted (COMMIT).
-- =============================================================================
SELECT '=== 4. safe creation RPC (team_member) ===' AS step;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE v_id uuid; n_ev int; v_ws uuid; v_page uuid;
  BEGIN
    -- 10-arg call, matching seo_create_decline_diagnosis_from_snapshot exactly:
    --   (p_snapshot_id, p_diagnosis_type, p_severity, p_priority,
    --    p_suggested_owner, p_business_summary, p_likely_cause,
    --    p_recommended_next_action, p_confidence_percentage,
    --    p_technical_explanation).
    -- Explicit ::uuid / ::text casts remove any `unknown`-type resolution
    -- ambiguity in the SQL Editor.
    v_id := public.seo_create_decline_diagnosis_from_snapshot(
      '77777777-0000-0000-0000-0000000000e1'::uuid,
      'ctr_drop', 'high', 'high', 'client_action',
      'Your page is shown just as often but is being clicked less.',
      'The title and description may be less compelling than competitors right now.',
      'Refresh the page title and meta description to better match what searchers want.',
      74, NULL::text);

    SELECT count(*) INTO n_ev FROM public.seo_decline_diagnosis_evidence WHERE diagnosis_id = v_id;
    SELECT workspace_id, page_id INTO v_ws, v_page FROM public.seo_decline_diagnoses WHERE id = v_id;

    IF v_id IS NOT NULL
       AND n_ev = 4
       AND v_ws = '77777777-0000-0000-0000-000000000001'
       AND v_page = '77777777-0000-0000-0000-0000000000c1' THEN
      RAISE NOTICE 'PASS: RPC created diagnosis % (auto-snapshotted ws/page) with % auto evidence rows', v_id, n_ev;
    ELSE
      RAISE EXCEPTION 'FAIL: RPC diagnosis id=% evidence=% ws=% page=% (expected 4 evidence, seeded ws/page)', v_id, n_ev, v_ws, v_page;
    END IF;
  END $$;
COMMIT;

-- Active-combo uniqueness: a SECOND open diagnosis for the same
-- page+keyword+type+snapshot must be rejected by the partial unique index.
-- (Snapshot e1 → keyword d1; re-running the same 'ctr_drop' classification
-- targets the identical active combo.)
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnoses
      (workspace_id, website_id, website_url, page_id, page_url, page_keyword_id, keyword,
       performance_snapshot_id, diagnosis_type, business_summary, likely_cause,
       recommended_next_action, suggested_owner, status)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
            'https://stage5-smoke-test.example/services/seo-audits', '77777777-0000-0000-0000-0000000000d1',
            'seo audit services', '77777777-0000-0000-0000-0000000000e1', 'ctr_drop',
            'dup', 'dup', 'dup', 'system_suggestion', 'open');
    RAISE EXCEPTION 'FAIL: duplicate active diagnosis (page+keyword+type+snapshot) was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: duplicate active diagnosis rejected (%)', SQLERRM;
  END;
END $$;

-- =============================================================================
-- 5. RLS — SELECT access for owner/admin/team/client (all should see the
--    seeded diagnoses + evidence); non-member sees nothing. After §2–4 there
--    are 2 diagnoses (f1 + the RPC row) and 5 evidence rows (1 manual + 4 RPC).
--    Each check runs in its own BEGIN/SET LOCAL ROLE/ROLLBACK (see RLS NOTE).
-- =============================================================================
SELECT '=== 5. RLS select access per role ===' AS step;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_diag int; n_ev int; n_cur int;
  BEGIN
    SELECT count(*) INTO n_diag FROM public.seo_decline_diagnoses WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_ev FROM public.seo_decline_diagnosis_evidence WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_cur FROM public.seo_decline_diagnoses_current WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    IF n_diag = 2 AND n_ev = 5 AND n_cur = 2 THEN
      RAISE NOTICE 'PASS: owner_id can read diagnoses(%) evidence(%) current-view(%)', n_diag, n_ev, n_cur;
    ELSE
      RAISE EXCEPTION 'FAIL: owner_id read diagnoses=% evidence=% current=% (expected 2/5/2)', n_diag, n_ev, n_cur;
    END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_diag int; n_ev int; n_cur int;
  BEGIN
    SELECT count(*) INTO n_diag FROM public.seo_decline_diagnoses WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_ev FROM public.seo_decline_diagnosis_evidence WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_cur FROM public.seo_decline_diagnoses_current WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    IF n_diag = 2 AND n_ev = 5 AND n_cur = 2 THEN
      RAISE NOTICE 'PASS: admin_id can read diagnoses(%) evidence(%) current-view(%)', n_diag, n_ev, n_cur;
    ELSE
      RAISE EXCEPTION 'FAIL: admin_id read diagnoses=% evidence=% current=% (expected 2/5/2)', n_diag, n_ev, n_cur;
    END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_diag int; n_ev int; n_cur int;
  BEGIN
    SELECT count(*) INTO n_diag FROM public.seo_decline_diagnoses WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_ev FROM public.seo_decline_diagnosis_evidence WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_cur FROM public.seo_decline_diagnoses_current WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    IF n_diag = 2 AND n_ev = 5 AND n_cur = 2 THEN
      RAISE NOTICE 'PASS: team_id can read diagnoses(%) evidence(%) current-view(%)', n_diag, n_ev, n_cur;
    ELSE
      RAISE EXCEPTION 'FAIL: team_id read diagnoses=% evidence=% current=% (expected 2/5/2)', n_diag, n_ev, n_cur;
    END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_diag int; n_ev int; n_cur int;
  BEGIN
    SELECT count(*) INTO n_diag FROM public.seo_decline_diagnoses WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_ev FROM public.seo_decline_diagnosis_evidence WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_cur FROM public.seo_decline_diagnoses_current WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    IF n_diag = 2 AND n_ev = 5 AND n_cur = 2 THEN
      RAISE NOTICE 'PASS: client_id can READ diagnoses(%) evidence(%) current-view(%)', n_diag, n_ev, n_cur;
    ELSE
      RAISE EXCEPTION 'FAIL: client_id read diagnoses=% evidence=% current=% (expected 2/5/2)', n_diag, n_ev, n_cur;
    END IF;
  END $$;
ROLLBACK;

-- Non-member: RLS filters every row out (0, not an error).
BEGIN;
  SELECT public._seo5_login(current_setting('seo5.nonmember_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_diag int; n_ev int; n_cur int;
  BEGIN
    SELECT count(*) INTO n_diag FROM public.seo_decline_diagnoses WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_ev FROM public.seo_decline_diagnosis_evidence WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_cur FROM public.seo_decline_diagnoses_current WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    IF n_diag = 0 AND n_ev = 0 AND n_cur = 0 THEN
      RAISE NOTICE 'PASS: non-member sees 0 rows across diagnoses/evidence/current-view (workspace isolation)';
    ELSE
      RAISE EXCEPTION 'FAIL: non-member read diagnoses=% evidence=% current=% (expected all 0)', n_diag, n_ev, n_cur;
    END IF;
  END $$;
ROLLBACK;

-- =============================================================================
-- 6. RLS — client cannot insert/update diagnoses or evidence, and cannot use
--    the creation RPC (the in-function role check rejects them even though
--    EXECUTE is granted to authenticated).
-- =============================================================================
SELECT '=== 6. RLS write denial for client ===' AS step;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n int;
  BEGIN
    -- INSERT diagnosis: RLS WITH CHECK failure raises.
    BEGIN
      INSERT INTO public.seo_decline_diagnoses
        (workspace_id, website_id, website_url, page_id, page_url, diagnosis_type,
         business_summary, likely_cause, recommended_next_action, suggested_owner)
      VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
              'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
              'https://stage5-smoke-test.example/services/seo-audits', 'no_data',
              'client attempt', 'client attempt', 'client attempt', 'system_suggestion');
      RAISE EXCEPTION 'FAIL: client inserted a diagnosis row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting diagnoses (%)', SQLERRM;
    END;

    -- INSERT evidence: RLS WITH CHECK failure raises.
    BEGIN
      INSERT INTO public.seo_decline_diagnosis_evidence
        (workspace_id, website_id, website_url, diagnosis_id, evidence_type, metric_name, evidence_summary)
      VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
              'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000f1',
              'system_note', 'client_attempt', 'client attempt evidence');
      RAISE EXCEPTION 'FAIL: client inserted an evidence row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting evidence (%)', SQLERRM;
    END;

    -- RPC: the in-function manage-role check rejects the client.
    BEGIN
      -- 8-arg call: the two trailing params (p_confidence_percentage,
      -- p_technical_explanation) use their DEFAULT NULL. ::uuid cast keeps the
      -- snapshot-id resolution explicit.
      PERFORM public.seo_create_decline_diagnosis_from_snapshot(
        '77777777-0000-0000-0000-0000000000e1'::uuid,
        'impressions_decline', 'medium', 'medium', 'system_suggestion',
        'client attempt', 'client attempt', 'client attempt');
      RAISE EXCEPTION 'FAIL: client created a diagnosis via the RPC';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from the creation RPC (%)', SQLERRM;
    END;

    -- UPDATE diagnosis: RLS silently affects 0 rows (no exception).
    UPDATE public.seo_decline_diagnoses SET status = 'dismissed' WHERE id = '77777777-0000-0000-0000-0000000000f1';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN RAISE NOTICE 'PASS: client direct UPDATE on diagnoses blocked by RLS (0 rows)';
    ELSE RAISE EXCEPTION 'FAIL: client updated % diagnosis row(s)', n; END IF;
  END $$;
ROLLBACK;

-- =============================================================================
-- 7. Constraint checks — invalid enum-like values are rejected (run as the
--    privileged editor role; these are plain CHECK violations, not RLS).
-- =============================================================================
SELECT '=== 7. CHECK constraint rejection ===' AS step;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnoses
      (workspace_id, website_id, website_url, page_id, page_url, diagnosis_type,
       business_summary, likely_cause, recommended_next_action, suggested_owner)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
            'https://stage5-smoke-test.example/services/seo-audits', 'meltdown',
            'x', 'x', 'x', 'system_suggestion');
    RAISE EXCEPTION 'FAIL: invalid diagnosis_type was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid diagnosis_type rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnoses
      (workspace_id, website_id, website_url, page_id, page_url, diagnosis_type, severity,
       business_summary, likely_cause, recommended_next_action, suggested_owner)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
            'https://stage5-smoke-test.example/services/seo-audits', 'no_data', 'apocalyptic',
            'x', 'x', 'x', 'system_suggestion');
    RAISE EXCEPTION 'FAIL: invalid severity was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid severity rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnoses
      (workspace_id, website_id, website_url, page_id, page_url, diagnosis_type, status,
       business_summary, likely_cause, recommended_next_action, suggested_owner)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
            'https://stage5-smoke-test.example/services/seo-audits', 'no_data', 'vanished',
            'x', 'x', 'x', 'system_suggestion');
    RAISE EXCEPTION 'FAIL: invalid status was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid status rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnoses
      (workspace_id, website_id, website_url, page_id, page_url, diagnosis_type,
       business_summary, likely_cause, recommended_next_action, suggested_owner)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
            'https://stage5-smoke-test.example/services/seo-audits', 'no_data',
            'x', 'x', 'x', 'the_intern');
    RAISE EXCEPTION 'FAIL: invalid suggested_owner was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid suggested_owner rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnoses
      (workspace_id, website_id, website_url, page_id, page_url, diagnosis_type, confidence_percentage,
       business_summary, likely_cause, recommended_next_action, suggested_owner)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000c1',
            'https://stage5-smoke-test.example/services/seo-audits', 'no_data', 150,
            'x', 'x', 'x', 'system_suggestion');
    RAISE EXCEPTION 'FAIL: confidence_percentage=150 (out of 0..100) was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: confidence_percentage out of range rejected (%)', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_decline_diagnosis_evidence
      (workspace_id, website_id, website_url, diagnosis_id, evidence_type, metric_name, evidence_summary, source)
    VALUES ('77777777-0000-0000-0000-000000000001', '77777777-0000-0000-0000-0000000000b1',
            'https://stage5-smoke-test.example', '77777777-0000-0000-0000-0000000000f1',
            'ranking', 'average_position', 'bad source evidence', 'psychic');
    RAISE EXCEPTION 'FAIL: invalid evidence source was accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid evidence source rejected (%)', SQLERRM;
  END;
END $$;

-- =============================================================================
-- 8. Current view — excludes resolved/dismissed. Done inside a manager
--    (team_member) transaction that dismisses f1, asserts the view drops it,
--    then ROLLBACKs so no committed state changes.
-- =============================================================================
SELECT '=== 8. current view excludes non-live statuses ===' AS step;

BEGIN;
  SELECT public._seo5_login(current_setting('seo5.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_before int; n_after int;
  BEGIN
    SELECT count(*) INTO n_before FROM public.seo_decline_diagnoses_current
      WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    UPDATE public.seo_decline_diagnoses SET status = 'dismissed' WHERE id = '77777777-0000-0000-0000-0000000000f1';
    SELECT count(*) INTO n_after FROM public.seo_decline_diagnoses_current
      WHERE workspace_id = '77777777-0000-0000-0000-000000000001';
    IF n_before = 2 AND n_after = 1 THEN
      RAISE NOTICE 'PASS: current view dropped the dismissed diagnosis (% -> %)', n_before, n_after;
    ELSE
      RAISE EXCEPTION 'FAIL: current view before=% after-dismiss=% (expected 2 -> 1)', n_before, n_after;
    END IF;
  END $$;
ROLLBACK;

-- ---------- cleanup of the test-only helper --------------------------------
DROP FUNCTION IF EXISTS public._seo5_login(uuid);

SELECT '=== STAGE 5 SMOKE TEST COMPLETE — check the Messages/Notices tab for PASS/FAIL ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the one test workspace and
-- everything that cascades from it: website, page, keyword, snapshot,
-- diagnoses, evidence). Uncomment and run manually if you want a clean project.
-- =============================================================================
-- DELETE FROM public.seo_workspaces WHERE id = '77777777-0000-0000-0000-000000000001';
-- DELETE FROM public.user_module_access WHERE module_name='seo' AND user_id IN (
--   current_setting('seo5.owner_id')::uuid, current_setting('seo5.admin_id')::uuid,
--   current_setting('seo5.team_id')::uuid, current_setting('seo5.client_id')::uuid,
--   current_setting('seo5.nonmember_id')::uuid);
