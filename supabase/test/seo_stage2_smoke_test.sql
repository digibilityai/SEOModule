-- =============================================================================
-- SEO Stage 2 — SMOKE TEST (TEST ONLY)
-- =============================================================================
-- RUN ONLY on a FRESH Supabase TEST project, AFTER Stage 1 (…120001–120003)
-- and Stage 2 (…120004–120006) migrations are applied. NEVER run on production.
--
-- This script is NON-DESTRUCTIVE to Core data. It seeds test rows under two
-- disposable test workspaces and drops one test-only helper function at the end.
-- Optional teardown (deletes ONLY the test workspaces) is at the very bottom,
-- commented out. See SUPABASE_STAGE_2_VERIFICATION_GUIDE.md for full steps.
--
-- PREREQUISITE — create 5 users in the Supabase Dashboard (Authentication →
-- Users), then paste their UUIDs below. FKs reference auth.users, so real users
-- are required. Do NOT insert into auth.users from SQL.
-- =============================================================================

-- ---------- 0. PASTE TEST USER UUIDS HERE (session-scoped GUCs) --------------
SELECT set_config('seotest.owner_id',     'seo-owner-test@example.com',      false);
SELECT set_config('seotest.admin_id',     'seo-admin-test@example.com',      false);
SELECT set_config('seotest.team_id',      'seo-team-test@example.com',false);
SELECT set_config('seotest.client_id',    'seo-client-test@example.com',     false);
SELECT set_config('seotest.nonmember_id', 'seo-nonmember-test@example.com',  false);

-- Guard: refuse to run until UUIDs are filled in.
DO $$
BEGIN
  IF current_setting('seotest.owner_id') LIKE 'REPLACE_WITH_%' THEN
    RAISE EXCEPTION 'Fill in the test user UUIDs at the top of the script first.';
  END IF;
END $$;

-- ---------- Test-only login helper (dropped at the end) ---------------------
-- Sets the JWT-claim GUCs so auth.uid() resolves to the given user inside the
-- current transaction. Combine with: SET LOCAL ROLE authenticated;
CREATE OR REPLACE FUNCTION public._seo_test_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $$;

-- Fixed UUIDs for disposable test entities (readable + re-referenceable).
--   Workspaces:  W1=aaaa…01  W2=aaaa…02
--   Websites:    bbbb…01 / bbbb…02        Seed audit run: cccc…01
--   Issues:      dddd…01 schema/low · 02 speed/med · 03 speed/high · 04 robots_txt · 05 (W2)
--   Recs:        eeee…0x   Approval items: ffff…0x

-- =============================================================================
-- 1–3. SETUP (run as the privileged editor role; RLS bypassed for seeding).
-- =============================================================================
SELECT '=== SETUP: workspaces, members, website, module access ===' AS step;

-- Grant SEO module access to every test user (idempotent).
INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seotest.'||k)::uuid, 'seo', true
FROM (VALUES ('owner_id'),('admin_id'),('team_id'),('client_id'),('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

-- Workspace W1 (owner). The Stage-1 AFTER INSERT trigger auto-adds the owner
-- as an active 'owner' member — so we do NOT insert that member manually.
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Smoke Test WS1',
        current_setting('seotest.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- Additional members: admin / team_member / client.
INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', current_setting('seotest.admin_id')::uuid,  'admin',       'active'),
  ('aaaaaaaa-0000-0000-0000-000000000001', current_setting('seotest.team_id')::uuid,   'team_member', 'active'),
  ('aaaaaaaa-0000-0000-0000-000000000001', current_setting('seotest.client_id')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

-- Website in W1.
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'https://smoke-test-1.example', 'Smoke Test Site 1', 'Smoke Test Co')
ON CONFLICT (id) DO NOTHING;

-- Second workspace + website + issue (for the cross-workspace integrity test).
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('aaaaaaaa-0000-0000-0000-000000000002', 'Smoke Test WS2',
        current_setting('seotest.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002',
        'https://smoke-test-2.example', 'Smoke Test Site 2', 'Smoke Test Co 2')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 4. seo_run_audit — all member roles may trigger; creates a RUN ONLY; keeps
--    exactly one is_latest per website; non-member is rejected.
-- =============================================================================
SELECT '=== 4. seo_run_audit ===' AS step;

-- Capture issue/rec counts to prove run_audit does not create them.
DO $$
DECLARE i_before int; r_before int; i_after int; r_after int; rec record;
BEGIN
  SELECT count(*) INTO i_before FROM public.seo_audit_issues;
  SELECT count(*) INTO r_before FROM public.seo_recommendations;

  -- Each role triggers a run (as authenticated) — all should succeed.
  FOR rec IN SELECT unnest(ARRAY['owner_id','admin_id','team_id','client_id']) AS k LOOP
    PERFORM set_config('request.jwt.claim.sub', current_setting('seotest.'||rec.k), true);
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', current_setting('seotest.'||rec.k), 'role','authenticated')::text, true);
    PERFORM public.seo_run_audit('bbbbbbbb-0000-0000-0000-000000000001'::uuid);
    RAISE NOTICE 'PASS: % triggered seo_run_audit', rec.k;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);

  SELECT count(*) INTO i_after FROM public.seo_audit_issues;
  SELECT count(*) INTO r_after FROM public.seo_recommendations;
  IF i_after = i_before AND r_after = r_before THEN
    RAISE NOTICE 'PASS: seo_run_audit created no issues/recommendations';
  ELSE
    RAISE EXCEPTION 'FAIL: run_audit created issues(%%) or recs(%%)', i_after-i_before, r_after-r_before;
  END IF;
END $$;

-- Exactly one latest run per website.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_audit_runs
  WHERE website_id = 'bbbbbbbb-0000-0000-0000-000000000001' AND is_latest;
  IF n = 1 THEN RAISE NOTICE 'PASS: exactly one is_latest run per website';
  ELSE RAISE EXCEPTION 'FAIL: % latest runs (expected 1)', n; END IF;
END $$;

-- Non-member cannot trigger an audit.
DO $$
BEGIN
  PERFORM public._seo_test_login(current_setting('seotest.nonmember_id')::uuid);
  BEGIN
    PERFORM public.seo_run_audit('bbbbbbbb-0000-0000-0000-000000000001'::uuid);
    RAISE EXCEPTION 'FAIL: non-member was allowed to run audit';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: non-member blocked from run_audit (%)', SQLERRM;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END $$;

-- =============================================================================
-- 5. Seed service-role/system style issues + recommendations + approval items.
--    (Run as privileged editor role = the "service role" path; RLS bypassed.)
-- =============================================================================
SELECT '=== 5. seed issues / recommendations / approval items ===' AS step;

-- A completed seed run (is_latest=false to avoid clashing with run_audit runs).
INSERT INTO public.seo_audit_runs (id, workspace_id, website_id, website_url, status, is_latest, completed_at)
VALUES ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001', 'https://smoke-test-1.example', 'completed', false, now())
ON CONFLICT (id) DO NOTHING;

-- Issues: note is_high_risk_category is intentionally passed WRONG (false) to
-- prove the trigger forces the correct value from category.
INSERT INTO public.seo_audit_issues
  (id, workspace_id, website_id, website_url, audit_run_id, category, severity, title,
   simple_explanation, why_it_matters, technical_explanation, affected_page_url,
   impact, effort, risk, fix_owner, suggested_next_action, is_high_risk_category)
VALUES
  ('dddddddd-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','cccccccc-0000-0000-0000-000000000001','schema','low','Schema low','x','x','x','https://smoke-test-1.example/','low','low','low','system_suggestion','x', false),
  ('dddddddd-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','cccccccc-0000-0000-0000-000000000001','speed','medium','Speed medium','x','x','x','https://smoke-test-1.example/','medium','medium','medium','developer_needed','x', false),
  ('dddddddd-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','cccccccc-0000-0000-0000-000000000001','speed','high','Speed high','x','x','x','https://smoke-test-1.example/','high','medium','high','developer_needed','x', false),
  ('dddddddd-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','cccccccc-0000-0000-0000-000000000001','robots_txt','high','Robots dangerous','x','x','x','https://smoke-test-1.example/robots.txt','high','low','low','digibility_expert','x', false)
ON CONFLICT (id) DO NOTHING;

-- W2 issue (for cross-workspace test).
INSERT INTO public.seo_audit_runs (id, workspace_id, website_id, website_url, status, is_latest)
VALUES ('cccccccc-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000002','https://smoke-test-2.example','completed', false)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_audit_issues
  (id, workspace_id, website_id, website_url, audit_run_id, category, severity, title,
   simple_explanation, why_it_matters, technical_explanation, affected_page_url,
   impact, effort, risk, fix_owner, suggested_next_action)
VALUES
  ('dddddddd-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000002','https://smoke-test-2.example','cccccccc-0000-0000-0000-000000000002','speed','low','W2 issue','x','x','x','https://smoke-test-2.example/','low','low','low','system_suggestion','x')
ON CONFLICT (id) DO NOTHING;

-- Recommendations (one per approval item). issue_id links drive the hrc trigger.
INSERT INTO public.seo_recommendations
  (id, workspace_id, website_id, website_url, issue_id, area, title, suggested_change, why_it_helps, action_type, impact, effort, risk)
VALUES
  ('eeeeeeee-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','dddddddd-0000-0000-0000-000000000001','schema','Rec low','x','x','auto_suggest','low','low','low'),
  ('eeeeeeee-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','dddddddd-0000-0000-0000-000000000002','technical','Rec medium','x','x','approval_required','medium','medium','medium'),
  ('eeeeeeee-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','dddddddd-0000-0000-0000-000000000003','technical','Rec high','x','x','approval_required','high','medium','high'),
  ('eeeeeeee-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','dddddddd-0000-0000-0000-000000000004','technical','Rec dangerous','x','x','expert_review','medium','low','low'),
  ('eeeeeeee-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','dddddddd-0000-0000-0000-000000000001','schema','Rec owner','x','x','auto_suggest','low','low','low')
ON CONFLICT (id) DO NOTHING;

-- Approval items. risk is set explicitly per test; hrc derives from issue_id.
INSERT INTO public.seo_approval_items
  (id, workspace_id, website_id, website_url, recommendation_id, issue_id, title, simple_explanation, suggested_change, action_type, impact, effort, risk, fix_owner)
VALUES
  ('ffffffff-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','eeeeeeee-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001','Item low','x','x','auto_suggest','low','low','low','system_suggestion'),
  ('ffffffff-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','eeeeeeee-0000-0000-0000-000000000002','dddddddd-0000-0000-0000-000000000002','Item medium','x','x','approval_required','medium','medium','medium','developer_needed'),
  ('ffffffff-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','eeeeeeee-0000-0000-0000-000000000003','dddddddd-0000-0000-0000-000000000003','Item high','x','x','approval_required','high','medium','high','developer_needed'),
  ('ffffffff-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','eeeeeeee-0000-0000-0000-000000000004','dddddddd-0000-0000-0000-000000000004','Item dangerous','x','x','expert_review','medium','low','low','digibility_expert'),
  ('ffffffff-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example','eeeeeeee-0000-0000-0000-000000000005','dddddddd-0000-0000-0000-000000000001','Item owner','x','x','auto_suggest','low','low','low','system_suggestion')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 6. High-risk category trigger + cross-workspace integrity.
-- =============================================================================
SELECT '=== 6. hrc trigger + cross-workspace integrity ===' AS step;

-- Dangerous category forced to true despite being seeded false.
DO $$
DECLARE b boolean;
BEGIN
  SELECT is_high_risk_category INTO b FROM public.seo_audit_issues WHERE id='dddddddd-0000-0000-0000-000000000004';
  IF b THEN RAISE NOTICE 'PASS: robots_txt issue forced is_high_risk_category=true';
  ELSE RAISE EXCEPTION 'FAIL: dangerous issue hrc=false'; END IF;

  SELECT is_high_risk_category INTO b FROM public.seo_approval_items WHERE id='ffffffff-0000-0000-0000-000000000004';
  IF b THEN RAISE NOTICE 'PASS: dangerous approval item resolved hrc=true (from linked issue)';
  ELSE RAISE EXCEPTION 'FAIL: dangerous approval item hrc=false'; END IF;

  SELECT is_high_risk_category INTO b FROM public.seo_audit_issues WHERE id='dddddddd-0000-0000-0000-000000000001';
  IF NOT b THEN RAISE NOTICE 'PASS: schema issue hrc=false';
  ELSE RAISE EXCEPTION 'FAIL: non-dangerous issue hrc=true'; END IF;
END $$;

-- Cross-workspace issue_id on a W1 recommendation must raise.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_recommendations
      (workspace_id, website_id, website_url, issue_id, area, title, suggested_change, why_it_helps, action_type, impact, effort, risk)
    VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','https://smoke-test-1.example',
            'dddddddd-0000-0000-0000-000000000005', -- W2 issue!
            'technical','bad link','x','x','approval_required','low','low','low');
    RAISE EXCEPTION 'FAIL: cross-workspace issue_id was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cross-workspace issue_id rejected (%)', SQLERRM;
  END;
END $$;

-- =============================================================================
-- 7. Approval matrix via seo_approval_transition (per role, ROLLBACK so items
--    stay reusable). Helper below asserts allow/deny for an (role, item, action).
-- =============================================================================
SELECT '=== 7. approval permission matrix ===' AS step;

-- team_member: approve low OK, approve medium OK, approve high DENY, approve dangerous DENY, completed DENY.
BEGIN;
  SELECT public._seo_test_login(current_setting('seotest.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000001','approve',NULL);
    RAISE NOTICE 'PASS: team_member approved LOW';
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000002','approve',NULL);
    RAISE NOTICE 'PASS: team_member approved MEDIUM';
    BEGIN PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000003','approve',NULL);
      RAISE EXCEPTION 'FAIL: team_member approved HIGH';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: team_member blocked on HIGH'; END;
    BEGIN PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000004','approve',NULL);
      RAISE EXCEPTION 'FAIL: team_member approved DANGEROUS';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: team_member blocked on DANGEROUS'; END;
    BEGIN PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000001','completed',NULL);
      RAISE EXCEPTION 'FAIL: team_member marked completed';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: team_member blocked on COMPLETED'; END;
  END $$;
ROLLBACK;

-- client: approve low-simple OK, approve high DENY, approve dangerous DENY, completed DENY, direct edit DENY (RLS 0 rows).
BEGIN;
  SELECT public._seo_test_login(current_setting('seotest.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n int;
  BEGIN
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000001','approve',NULL);
    RAISE NOTICE 'PASS: client approved LOW-SIMPLE';
    BEGIN PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000003','approve',NULL);
      RAISE EXCEPTION 'FAIL: client approved HIGH';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: client blocked on HIGH'; END;
    BEGIN PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000004','approve',NULL);
      RAISE EXCEPTION 'FAIL: client approved DANGEROUS';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: client blocked on DANGEROUS'; END;
    BEGIN PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000001','completed',NULL);
      RAISE EXCEPTION 'FAIL: client marked completed';
    EXCEPTION WHEN others THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: client blocked on COMPLETED'; END;
    -- direct edit blocked by RLS (no client UPDATE policy → 0 rows).
    UPDATE public.seo_approval_items SET suggested_change='hacked' WHERE id='ffffffff-0000-0000-0000-000000000001';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN RAISE NOTICE 'PASS: client direct edit blocked by RLS (0 rows)';
    ELSE RAISE EXCEPTION 'FAIL: client edited % rows', n; END IF;
  END $$;
ROLLBACK;

-- owner: full lifecycle allowed (approve → developer_needed → expert_review → completed).
BEGIN;
  SELECT public._seo_test_login(current_setting('seotest.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000003','approve',NULL);          -- high OK for owner
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000004','expert_review',NULL);    -- dangerous → expert review
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000002','developer_needed',NULL);
    PERFORM public.seo_approval_transition('ffffffff-0000-0000-0000-000000000005','completed',NULL);
    RAISE NOTICE 'PASS: owner performed approve/expert_review/developer_needed/completed';
  END $$;
ROLLBACK;

-- =============================================================================
-- 8 & 9. Comments append-only + activity logging + actor_role_snapshot.
--        (COMMITTED so we can inspect the rows afterwards.)
-- =============================================================================
SELECT '=== 8/9. comments (append-only) + activity ===' AS step;

BEGIN;
  SELECT public._seo_test_login(current_setting('seotest.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  -- Client comments via RPC (allowed for all members); also a status transition.
  SELECT public.seo_approval_transition('ffffffff-0000-0000-0000-000000000005','comment','client says hi');
  SELECT public.seo_approval_transition('ffffffff-0000-0000-0000-000000000005','expert_review','please review');
COMMIT;

-- Verify a comment + activity rows exist with actor_role_snapshot set.
DO $$
DECLARE c int; a int; role_ok boolean;
BEGIN
  SELECT count(*) INTO c FROM public.seo_approval_comments WHERE approval_item_id='ffffffff-0000-0000-0000-000000000005';
  SELECT count(*) INTO a FROM public.seo_approval_activity WHERE approval_item_id='ffffffff-0000-0000-0000-000000000005';
  SELECT bool_and(actor_role_snapshot = 'client') INTO role_ok
    FROM public.seo_approval_comments WHERE approval_item_id='ffffffff-0000-0000-0000-000000000005';
  IF c >= 1 AND a >= 1 AND role_ok THEN
    RAISE NOTICE 'PASS: comments(%) + activity(%) logged with actor_role_snapshot=client', c, a;
  ELSE
    RAISE EXCEPTION 'FAIL: comments=% activity=% role_ok=%', c, a, role_ok;
  END IF;
END $$;

-- Comments are append-only: UPDATE/DELETE denied for everyone (0 rows under RLS).
BEGIN;
  SELECT public._seo_test_login(current_setting('seotest.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE nu int; nd int;
  BEGIN
    UPDATE public.seo_approval_comments SET comment_text='edited' WHERE approval_item_id='ffffffff-0000-0000-0000-000000000005';
    GET DIAGNOSTICS nu = ROW_COUNT;
    DELETE FROM public.seo_approval_comments WHERE approval_item_id='ffffffff-0000-0000-0000-000000000005';
    GET DIAGNOSTICS nd = ROW_COUNT;
    IF nu = 0 AND nd = 0 THEN RAISE NOTICE 'PASS: comments append-only (update=%, delete=% rows)', nu, nd;
    ELSE RAISE EXCEPTION 'FAIL: comment update=% delete=% rows', nu, nd; END IF;
  END $$;
ROLLBACK;

-- ---------- cleanup of the test-only helper --------------------------------
DROP FUNCTION IF EXISTS public._seo_test_login(uuid);

SELECT '=== SMOKE TEST COMPLETE — check the Messages/Notices tab for PASS/FAIL ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the two test workspaces and all
-- their cascaded rows). Uncomment and run manually if you want a clean project.
-- =============================================================================
-- DELETE FROM public.seo_workspaces WHERE id IN
--   ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002');
-- DELETE FROM public.user_module_access WHERE module_name='seo' AND user_id IN (
--   current_setting('seotest.owner_id')::uuid, current_setting('seotest.admin_id')::uuid,
--   current_setting('seotest.team_id')::uuid, current_setting('seotest.client_id')::uuid,
--   current_setting('seotest.nonmember_id')::uuid);
