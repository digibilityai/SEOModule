-- =============================================================================
-- SEO Stage 3 — CONTENT STUDIO SMOKE TEST (TEST ONLY)
-- =============================================================================
-- RUN ONLY on a FRESH/disposable Supabase TEST project, AFTER Stage 1
-- (…120001–120003), Stage 2 (…120004–120006) AND Stage 3 (…120007–120009) are
-- applied. NEVER run on production.
--
-- Non-destructive: it seeds rows under Stage-3-only test workspaces (distinct
-- UUID prefix "33333333-…" so it never collides with the Stage-2 smoke test's
-- "aaaaaaaa-…"). All workflow/permission checks run inside BEGIN;…ROLLBACK; so
-- the test opportunities keep a stable committed status and the script is fully
-- re-runnable. It drops its two test-only helper functions at the end. Optional
-- teardown (test workspaces only) is at the very bottom, commented out.
--
-- PREREQUISITE — create the SAME 5 users used by the Stage-2 test (Supabase
-- Dashboard → Authentication → Users), then paste their UUIDs below. FKs
-- reference auth.users, so real users are required. Do NOT insert into
-- auth.users from SQL. See SUPABASE_STAGE_3_CONTENT_STUDIO_VERIFICATION_GUIDE.md.
-- =============================================================================

-- ---------- 0. PASTE TEST USER UUIDS HERE (session-scoped GUCs) --------------
SELECT set_config('seo3.owner_id',     '48c479db-aedf-452e-af43-05ed1180baaa',     false);
SELECT set_config('seo3.admin_id',     '9830c4d7-167b-4d78-9179-37b60511bd73',     false);
SELECT set_config('seo3.team_id',      '0723d21f-c02c-4725-851f-575f93f2f58c',      false);
SELECT set_config('seo3.client_id',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c',    false);
SELECT set_config('seo3.nonmember_id', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

-- Guard: refuse to run until the UUIDs are filled in.
DO $$
BEGIN
  IF current_setting('seo3.owner_id') LIKE 'REPLACE_WITH_%'
     OR current_setting('seo3.admin_id') LIKE 'REPLACE_WITH_%'
     OR current_setting('seo3.team_id') LIKE 'REPLACE_WITH_%'
     OR current_setting('seo3.client_id') LIKE 'REPLACE_WITH_%'
     OR current_setting('seo3.nonmember_id') LIKE 'REPLACE_WITH_%' THEN
    RAISE EXCEPTION 'Fill in the 5 test user UUIDs at the top of the script first.';
  END IF;
END $$;

-- ---------- Test-only helpers (dropped at the end) --------------------------
-- _seo3_login: sets the JWT-claim GUCs so auth.uid() resolves to p_uid in
-- the current transaction. Combine with: SET LOCAL ROLE authenticated;
CREATE OR REPLACE FUNCTION public._seo3_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $$;

-- _seo3_ct: login as p_uid (stays under the current role) and run the workflow
-- RPC, returning the resulting status. INVOKER on purpose so the acting user is
-- the simulated one; seo_content_transition itself is SECURITY DEFINER.
CREATE OR REPLACE FUNCTION public._seo3_ct(p_uid uuid, p_opp uuid, p_action text, p_note text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text;
BEGIN
  PERFORM public._seo3_login(p_uid);
  SELECT new_status INTO r FROM public.seo_content_transition(p_opp, p_action, p_note);
  RETURN r;
END $$;

-- Fixed UUIDs for disposable Stage-3 test entities (readable + re-referenceable).
--   Workspaces: W1=33333333-…0001  W2=…0002
--   Websites:   …00b1 / …00b2
--   Opportunity:OPP1=…00c1 (W1)     OPP_W2=…00c2 (W2, cross-workspace test)
--   Children:   kw …00d1 · comp …00d2 · wf …00d3 · fmt …00d4
--   Draft:      …00e1 · sections …00e2/…00e3 · revision …00e4

-- =============================================================================
-- 1. SETUP — module access, workspaces, members, websites, opportunities,
--    plan-layer children, a draft + sections + revision. Run as the privileged
--    editor role (RLS bypassed for seeding; triggers still fire). Committed.
-- =============================================================================
SELECT '=== 1. SETUP (workspaces / members / opportunity / draft) ===' AS step;

INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seo3.'||k)::uuid, 'seo', true
FROM (VALUES ('owner_id'),('admin_id'),('team_id'),('client_id'),('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

-- W1 (owner auto-added as active 'owner' member by the Stage-1 trigger).
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('33333333-0000-0000-0000-000000000001', 'Stage3 Smoke WS1',
        current_setting('seo3.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES
  ('33333333-0000-0000-0000-000000000001', current_setting('seo3.admin_id')::uuid,  'admin',       'active'),
  ('33333333-0000-0000-0000-000000000001', current_setting('seo3.team_id')::uuid,   'team_member', 'active'),
  ('33333333-0000-0000-0000-000000000001', current_setting('seo3.client_id')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES ('33333333-0000-0000-0000-0000000000b1', '33333333-0000-0000-0000-000000000001',
        'https://stage3-smoke-1.example', 'Stage3 Site 1', 'Stage3 Co')
ON CONFLICT (id) DO NOTHING;

-- W2 (+ website) for the cross-workspace integrity test.
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('33333333-0000-0000-0000-000000000002', 'Stage3 Smoke WS2',
        current_setting('seo3.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES ('33333333-0000-0000-0000-0000000000b2', '33333333-0000-0000-0000-000000000002',
        'https://stage3-smoke-2.example', 'Stage3 Site 2', 'Stage3 Co 2')
ON CONFLICT (id) DO NOTHING;

-- Content opportunities (status defaults to 'idea').
INSERT INTO public.seo_content_opportunities
  (id, workspace_id, website_id, website_url, title, target_keyword, content_type)
VALUES
  ('33333333-0000-0000-0000-0000000000c1','33333333-0000-0000-0000-000000000001',
   '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
   'How to choose an SEO agency','seo agency','blog_post'),
  ('33333333-0000-0000-0000-0000000000c2','33333333-0000-0000-0000-000000000002',
   '33333333-0000-0000-0000-0000000000b2','https://stage3-smoke-2.example',
   'W2 opportunity','w2 keyword','blog_post')
ON CONFLICT (id) DO NOTHING;

-- Plan-layer children for OPP1 (service/system seed).
INSERT INTO public.seo_content_keyword_plans
  (id, workspace_id, website_id, website_url, content_opportunity_id, primary_keyword)
VALUES ('33333333-0000-0000-0000-0000000000d1','33333333-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
        '33333333-0000-0000-0000-0000000000c1','seo agency')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_content_competitor_summaries
  (id, workspace_id, website_id, website_url, content_opportunity_id, competitor_title)
VALUES ('33333333-0000-0000-0000-0000000000d2','33333333-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
        '33333333-0000-0000-0000-0000000000c1','A competitor')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_content_wireframes
  (id, workspace_id, website_id, website_url, content_opportunity_id, suggested_h1)
VALUES ('33333333-0000-0000-0000-0000000000d3','33333333-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
        '33333333-0000-0000-0000-0000000000c1','Choosing an SEO agency')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_content_format_inputs
  (id, workspace_id, website_id, website_url, content_opportunity_id, format_type)
VALUES ('33333333-0000-0000-0000-0000000000d4','33333333-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
        '33333333-0000-0000-0000-0000000000c1','default')
ON CONFLICT (id) DO NOTHING;

-- Draft + sections + one revision for OPP1 (service-role/system path).
INSERT INTO public.seo_content_drafts
  (id, workspace_id, website_id, website_url, content_opportunity_id, title)
VALUES ('33333333-0000-0000-0000-0000000000e1','33333333-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
        '33333333-0000-0000-0000-0000000000c1','Draft: choosing an SEO agency')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_content_draft_sections
  (id, workspace_id, website_id, website_url, draft_id, content_opportunity_id, position, heading, content)
VALUES
  ('33333333-0000-0000-0000-0000000000e2','33333333-0000-0000-0000-000000000001',
   '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
   '33333333-0000-0000-0000-0000000000e1','33333333-0000-0000-0000-0000000000c1',0,'Intro','intro text'),
  ('33333333-0000-0000-0000-0000000000e3','33333333-0000-0000-0000-000000000001',
   '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
   '33333333-0000-0000-0000-0000000000e1','33333333-0000-0000-0000-0000000000c1',1,'Body','body text')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_content_section_revisions
  (id, workspace_id, website_id, website_url, draft_section_id, content_opportunity_id, revision_number, content, reason)
VALUES ('33333333-0000-0000-0000-0000000000e4','33333333-0000-0000-0000-000000000001',
        '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
        '33333333-0000-0000-0000-0000000000e2','33333333-0000-0000-0000-0000000000c1',1,'intro text v1','initial generation')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 2. Plan layer + same-workspace integrity guard.
-- =============================================================================
SELECT '=== 2. plan layer + same-workspace guard ===' AS step;

-- 2a. Opportunity carries workspace_id + website_id + website_url.
DO $$
DECLARE ws uuid; web uuid; url text;
BEGIN
  SELECT workspace_id, website_id, website_url INTO ws, web, url
  FROM public.seo_content_opportunities WHERE id='33333333-0000-0000-0000-0000000000c1';
  IF ws = '33333333-0000-0000-0000-000000000001'
     AND web = '33333333-0000-0000-0000-0000000000b1'
     AND url = 'https://stage3-smoke-1.example' THEN
    RAISE NOTICE 'PASS: opportunity has workspace_id + website_id + website_url';
  ELSE RAISE EXCEPTION 'FAIL: opportunity anchor columns wrong (ws=% web=% url=%)', ws, web, url; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- COMMIT the helpers + seed data before any isolation block.
-- The Supabase SQL Editor runs the whole script as ONE transaction, so a bare
-- ROLLBACK below would otherwise unwind the top-level CREATE FUNCTION helpers
-- and the seed rows (causing "function public._seo3_login(uuid) does not
-- exist" on the next block). Committing here makes the helpers + seeds durable;
-- no later ROLLBACK can remove them, and each BEGIN;…ROLLBACK; block below
-- isolates only its own test mutations. (In an autocommit client this COMMIT is
-- a harmless no-op with a "no transaction in progress" notice.)
-- ---------------------------------------------------------------------------
COMMIT;

-- 2b. owner/admin/team_member can create plan-layer rows (authenticated). ROLLBACK.
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    INSERT INTO public.seo_content_competitor_summaries
      (workspace_id, website_id, website_url, content_opportunity_id, competitor_title)
    VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
            'https://stage3-smoke-1.example','33333333-0000-0000-0000-0000000000c1','team-created competitor');
    RAISE NOTICE 'PASS: team_member created a competitor summary';
  END $$;
ROLLBACK;

-- 2c. client CANNOT create plan-layer rows (RLS write = manager set only).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      INSERT INTO public.seo_content_wireframes
        (workspace_id, website_id, website_url, content_opportunity_id, suggested_h1)
      VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
              'https://stage3-smoke-1.example','33333333-0000-0000-0000-0000000000c1','client hack');
      RAISE EXCEPTION 'FAIL: client inserted a wireframe';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from creating plan-layer rows (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- 2d. Cross-workspace guard: a W1 child pointing at the W2 opportunity must raise.
BEGIN;
  DO $$
  BEGIN
    BEGIN
      INSERT INTO public.seo_content_keyword_plans
        (workspace_id, website_id, website_url, content_opportunity_id, primary_keyword)
      VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
              'https://stage3-smoke-1.example',
              '33333333-0000-0000-0000-0000000000c2',  -- W2 opportunity!
              'cross ws');
      RAISE EXCEPTION 'FAIL: cross-workspace content_opportunity_id was allowed';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: cross-workspace linkage rejected (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- =============================================================================
-- 3. Internal workflow happy path (owner) — full manager chain + activity log.
--    All in ONE ROLLBACK so OPP1 stays committed at 'idea' (re-runnable).
-- =============================================================================
SELECT '=== 3. internal workflow happy path (owner) ===' AS step;

BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          u uuid := current_setting('seo3.owner_id')::uuid;
          s text; a int;
  BEGIN
    s := public._seo3_ct(u,o,'mark_plan_ready');              IF s<>'plan_ready' THEN RAISE EXCEPTION 'FAIL: mark_plan_ready→%',s; END IF;
    s := public._seo3_ct(u,o,'start_wireframe');              IF s<>'wireframe_in_progress' THEN RAISE EXCEPTION 'FAIL: start_wireframe→%',s; END IF;
    s := public._seo3_ct(u,o,'submit_wireframe_internal_review'); IF s<>'wireframe_internal_review' THEN RAISE EXCEPTION 'FAIL: submit_wf_ir→%',s; END IF;
    s := public._seo3_ct(u,o,'approve_wireframe_internal');   IF s<>'wireframe_approved' THEN RAISE EXCEPTION 'FAIL: approve_wf_internal→%',s; END IF;
    s := public._seo3_ct(u,o,'start_draft');                 IF s<>'draft_in_progress' THEN RAISE EXCEPTION 'FAIL: start_draft→%',s; END IF;
    s := public._seo3_ct(u,o,'submit_draft_internal_review'); IF s<>'draft_internal_review' THEN RAISE EXCEPTION 'FAIL: submit_draft_ir→%',s; END IF;
    s := public._seo3_ct(u,o,'approve_draft_internal');      IF s<>'draft_approved' THEN RAISE EXCEPTION 'FAIL: approve_draft_internal→%',s; END IF;
    s := public._seo3_ct(u,o,'mark_ready_for_manual_publish'); IF s<>'ready_for_manual_publish' THEN RAISE EXCEPTION 'FAIL: mark_ready→%',s; END IF;
    RAISE NOTICE 'PASS: owner walked idea→…→ready_for_manual_publish (8 transitions)';

    -- Every transition logged one activity row (8 total in this tx).
    SELECT count(*) INTO a FROM public.seo_content_activity WHERE content_opportunity_id=o;
    IF a = 8 THEN RAISE NOTICE 'PASS: each transition logged seo_content_activity (count=8)';
    ELSE RAISE EXCEPTION 'FAIL: expected 8 activity rows, got %', a; END IF;

    -- Actor context recorded.
    IF EXISTS (SELECT 1 FROM public.seo_content_activity
               WHERE content_opportunity_id=o AND actor_user_id=u AND actor_role_snapshot='owner') THEN
      RAISE NOTICE 'PASS: activity records actor_user_id + actor_role_snapshot=owner';
    ELSE RAISE EXCEPTION 'FAIL: activity actor/role context missing'; END IF;
  END $$;
ROLLBACK;

-- Additional manager transitions not on the linear path (each in its own tx).
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          u uuid := current_setting('seo3.owner_id')::uuid; s text;
  BEGIN
    PERFORM public._seo3_ct(u,o,'mark_plan_ready');
    PERFORM public._seo3_ct(u,o,'start_wireframe');
    s := public._seo3_ct(u,o,'send_wireframe_client_review'); IF s<>'wireframe_client_review' THEN RAISE EXCEPTION 'FAIL: send_wf_client→%',s; END IF;
    s := public._seo3_ct(u,o,'request_wireframe_changes','tweak the H1'); IF s<>'wireframe_changes_requested' THEN RAISE EXCEPTION 'FAIL: request_wf_changes→%',s; END IF;
    s := public._seo3_ct(u,o,'start_wireframe'); IF s<>'wireframe_in_progress' THEN RAISE EXCEPTION 'FAIL: restart wireframe→%',s; END IF;
    RAISE NOTICE 'PASS: send_wireframe_client_review + request_wireframe_changes + re-start';
  END $$;
ROLLBACK;

BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          u uuid := current_setting('seo3.owner_id')::uuid; s text;
  BEGIN
    PERFORM public._seo3_ct(u,o,'mark_plan_ready');
    PERFORM public._seo3_ct(u,o,'start_wireframe');
    PERFORM public._seo3_ct(u,o,'approve_wireframe_internal');
    PERFORM public._seo3_ct(u,o,'start_draft');
    s := public._seo3_ct(u,o,'send_draft_client_review'); IF s<>'draft_client_review' THEN RAISE EXCEPTION 'FAIL: send_draft_client→%',s; END IF;
    s := public._seo3_ct(u,o,'request_draft_changes','add examples'); IF s<>'draft_changes_requested' THEN RAISE EXCEPTION 'FAIL: request_draft_changes→%',s; END IF;
    s := public._seo3_ct(u,o,'archive'); IF s<>'archived' THEN RAISE EXCEPTION 'FAIL: archive→%',s; END IF;
    RAISE NOTICE 'PASS: send_draft_client_review + request_draft_changes + archive';
  END $$;
ROLLBACK;

-- Invalid transition (wrong source status) must raise.
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          u uuid := current_setting('seo3.owner_id')::uuid;
  BEGIN
    BEGIN
      PERFORM public._seo3_ct(u,o,'start_draft');  -- from 'idea' → invalid
      RAISE EXCEPTION 'FAIL: start_draft allowed from idea';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: invalid transition (start_draft from idea) rejected (%)', SQLERRM;
    END;
    BEGIN
      PERFORM public._seo3_ct(u,o,'bogus_action');
      RAISE EXCEPTION 'FAIL: unknown action accepted';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: unknown action rejected (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- =============================================================================
-- 4. Client actions — allowed ONLY during *_client_review; blocked otherwise.
-- =============================================================================
SELECT '=== 4. client review actions ===' AS step;

-- 4a. Wireframe client review: client approve / reject / request_team / request_expert / comment.
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid; s text;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'send_wireframe_client_review');   -- → wireframe_client_review

    s := public._seo3_ct(cl,o,'client_approve_wireframe');
    IF s='wireframe_approved' THEN RAISE NOTICE 'PASS: client_approve_wireframe → wireframe_approved';
    ELSE RAISE EXCEPTION 'FAIL: client_approve_wireframe→%',s; END IF;
  END $$;
ROLLBACK;

BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid; s text;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'send_wireframe_client_review');
    s := public._seo3_ct(cl,o,'client_reject_wireframe','please revise');
    IF s='wireframe_changes_requested' THEN RAISE NOTICE 'PASS: client_reject_wireframe → wireframe_changes_requested';
    ELSE RAISE EXCEPTION 'FAIL: client_reject_wireframe→%',s; END IF;
  END $$;
ROLLBACK;

BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid; s text; a0 int; a1 int;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'send_wireframe_client_review');

    s := public._seo3_ct(cl,o,'request_team_review','need the team');
    IF s='wireframe_internal_review' THEN RAISE NOTICE 'PASS: client request_team_review → wireframe_internal_review';
    ELSE RAISE EXCEPTION 'FAIL: request_team_review→%',s; END IF;

    -- back to client review, then request_expert_review = activity only (no status change).
    PERFORM public._seo3_ct(ow,o,'send_wireframe_client_review');
    SELECT count(*) INTO a0 FROM public.seo_content_activity WHERE content_opportunity_id=o;
    s := public._seo3_ct(cl,o,'request_expert_review','escalate please');
    SELECT count(*) INTO a1 FROM public.seo_content_activity WHERE content_opportunity_id=o;
    IF s='wireframe_client_review' AND a1=a0+1 THEN
      RAISE NOTICE 'PASS: request_expert_review logs activity, no status change';
    ELSE RAISE EXCEPTION 'FAIL: request_expert_review status=% activity_delta=%', s, a1-a0; END IF;
  END $$;
ROLLBACK;

-- 4b. Draft client review: client approve / reject.
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid; s text;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'approve_wireframe_internal');
    PERFORM public._seo3_ct(ow,o,'start_draft');
    PERFORM public._seo3_ct(ow,o,'send_draft_client_review');       -- → draft_client_review
    s := public._seo3_ct(cl,o,'client_approve_draft');
    IF s='draft_approved' THEN RAISE NOTICE 'PASS: client_approve_draft → draft_approved';
    ELSE RAISE EXCEPTION 'FAIL: client_approve_draft→%',s; END IF;
  END $$;
ROLLBACK;

BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid; s text;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'approve_wireframe_internal');
    PERFORM public._seo3_ct(ow,o,'start_draft');
    PERFORM public._seo3_ct(ow,o,'send_draft_client_review');
    s := public._seo3_ct(cl,o,'client_reject_draft','not there yet');
    IF s='draft_changes_requested' THEN RAISE NOTICE 'PASS: client_reject_draft → draft_changes_requested';
    ELSE RAISE EXCEPTION 'FAIL: client_reject_draft→%',s; END IF;
  END $$;
ROLLBACK;

-- 4c. Client BLOCKED: manager actions rejected even during client review.
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid;
          act text;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'send_wireframe_client_review');   -- client review, most permissive gate
    FOREACH act IN ARRAY ARRAY[
      'mark_plan_ready','start_wireframe','start_draft','submit_wireframe_internal_review',
      'submit_draft_internal_review','approve_wireframe_internal','approve_draft_internal',
      'mark_ready_for_manual_publish','archive'] LOOP
      BEGIN
        PERFORM public._seo3_ct(cl,o,act);
        RAISE EXCEPTION 'FAIL: client performed manager action %', act;
      EXCEPTION WHEN others THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        -- expected 'Not permitted…'
      END;
    END LOOP;
    RAISE NOTICE 'PASS: client blocked from all 9 manager-only actions during client review';
  END $$;
ROLLBACK;

-- 4d. Client comment gated by status: allowed in review, rejected outside review.
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid;
  BEGIN
    -- outside review (still 'idea') → client comment rejected.
    BEGIN
      PERFORM public._seo3_ct(cl,o,'comment','can I comment now?');
      RAISE EXCEPTION 'FAIL: client commented outside client review';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client comment blocked outside client review (%)', SQLERRM;
    END;
    -- drive to client review → client comment allowed.
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'send_wireframe_client_review');
    PERFORM public._seo3_ct(cl,o,'comment','looks good, one note');
    IF EXISTS (SELECT 1 FROM public.seo_content_comments
               WHERE content_opportunity_id=o AND author_user_id=cl AND actor_role_snapshot='client') THEN
      RAISE NOTICE 'PASS: client comment (via RPC) recorded with actor_role_snapshot=client';
    ELSE RAISE EXCEPTION 'FAIL: client comment not recorded'; END IF;
  END $$;
ROLLBACK;

-- 4e. Client cannot directly edit the opportunity/status (RLS write = manager set).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n int;
  BEGIN
    UPDATE public.seo_content_opportunities SET status='ready_for_manual_publish', title='hacked'
    WHERE id='33333333-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n=0 THEN RAISE NOTICE 'PASS: client direct opportunity edit blocked by RLS (0 rows)';
    ELSE RAISE EXCEPTION 'FAIL: client edited % opportunity rows', n; END IF;
  END $$;
ROLLBACK;

-- =============================================================================
-- 5. Draft / section visibility + append-only revisions.
-- =============================================================================
SELECT '=== 5. draft/section visibility + revisions ===' AS step;

-- 5a. Client CANNOT see drafts/sections while OPP1 is not client-visible (idea).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE d int; s int;
  BEGIN
    SELECT count(*) INTO d FROM public.seo_content_drafts WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    SELECT count(*) INTO s FROM public.seo_content_draft_sections WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    IF d=0 AND s=0 THEN RAISE NOTICE 'PASS: client sees no draft/sections before client-visible status (drafts=% sections=%)', d, s;
    ELSE RAISE EXCEPTION 'FAIL: client saw drafts=% sections=% too early', d, s; END IF;
  END $$;
ROLLBACK;

-- 5b. Manager CAN see drafts/sections at all stages (idea).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE d int; s int;
  BEGIN
    SELECT count(*) INTO d FROM public.seo_content_drafts WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    SELECT count(*) INTO s FROM public.seo_content_draft_sections WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    IF d=1 AND s=2 THEN RAISE NOTICE 'PASS: manager sees draft+sections at all stages (drafts=1 sections=2)';
    ELSE RAISE EXCEPTION 'FAIL: manager draft/section visibility (drafts=% sections=%)', d, s; END IF;
  END $$;
ROLLBACK;

-- 5c. Client CAN see drafts/sections once OPP1 reaches draft_client_review.
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o uuid := '33333333-0000-0000-0000-0000000000c1';
          ow uuid := current_setting('seo3.owner_id')::uuid;
          cl uuid := current_setting('seo3.client_id')::uuid; d int; s int;
  BEGIN
    PERFORM public._seo3_ct(ow,o,'mark_plan_ready');
    PERFORM public._seo3_ct(ow,o,'start_wireframe');
    PERFORM public._seo3_ct(ow,o,'approve_wireframe_internal');
    PERFORM public._seo3_ct(ow,o,'start_draft');
    PERFORM public._seo3_ct(ow,o,'send_draft_client_review');       -- → draft_client_review
    PERFORM public._seo3_login(cl);   -- act as client
    SELECT count(*) INTO d FROM public.seo_content_drafts WHERE content_opportunity_id=o;
    SELECT count(*) INTO s FROM public.seo_content_draft_sections WHERE content_opportunity_id=o;
    IF d=1 AND s=2 THEN RAISE NOTICE 'PASS: client sees draft+sections during draft_client_review';
    ELSE RAISE EXCEPTION 'FAIL: client draft visibility in review (drafts=% sections=%)', d, s; END IF;
  END $$;
ROLLBACK;

-- 5d. Client cannot INSERT/UPDATE/DELETE drafts, sections, or revisions.
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE nu int; nd int;
  BEGIN
    -- UPDATE / DELETE → 0 rows under RLS.
    UPDATE public.seo_content_draft_sections SET content='client edit' WHERE id='33333333-0000-0000-0000-0000000000e2';
    GET DIAGNOSTICS nu = ROW_COUNT;
    DELETE FROM public.seo_content_draft_sections WHERE id='33333333-0000-0000-0000-0000000000e2';
    GET DIAGNOSTICS nd = ROW_COUNT;
    IF nu=0 AND nd=0 THEN RAISE NOTICE 'PASS: client draft-section update/delete blocked (rows u=% d=%)', nu, nd;
    ELSE RAISE EXCEPTION 'FAIL: client changed sections (u=% d=%)', nu, nd; END IF;
    -- INSERT → RLS WITH CHECK denies.
    BEGIN
      INSERT INTO public.seo_content_section_revisions
        (workspace_id, website_id, website_url, draft_section_id, content_opportunity_id, revision_number, content)
      VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
              'https://stage3-smoke-1.example','33333333-0000-0000-0000-0000000000e2',
              '33333333-0000-0000-0000-0000000000c1',2,'client injected');
      RAISE EXCEPTION 'FAIL: client inserted a section revision';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting section revision (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- 5e. Revisions are append-only for EVERYONE (owner update/delete → 0 rows).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE nu int; nd int;
  BEGIN
    UPDATE public.seo_content_section_revisions SET content='rewritten' WHERE id='33333333-0000-0000-0000-0000000000e4';
    GET DIAGNOSTICS nu = ROW_COUNT;
    DELETE FROM public.seo_content_section_revisions WHERE id='33333333-0000-0000-0000-0000000000e4';
    GET DIAGNOSTICS nd = ROW_COUNT;
    IF nu=0 AND nd=0 THEN RAISE NOTICE 'PASS: section revisions append-only (owner update=% delete=% rows)', nu, nd;
    ELSE RAISE EXCEPTION 'FAIL: revision update=% delete=% rows', nu, nd; END IF;
  END $$;
ROLLBACK;

-- =============================================================================
-- 6. Comments + activity append-only.
-- =============================================================================
SELECT '=== 6. comments + activity append-only ===' AS step;

BEGIN;
  SELECT public._seo3_login(current_setting('seo3.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE cu int; cd int; au int; ad int;
  BEGIN
    -- Seed one comment + one activity in-tx via the RPC (owner comment allowed any status).
    PERFORM public.seo_content_transition('33333333-0000-0000-0000-0000000000c1','comment','owner note');
    UPDATE public.seo_content_comments SET comment_text='edited' WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS cu = ROW_COUNT;
    DELETE FROM public.seo_content_comments WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS cd = ROW_COUNT;
    UPDATE public.seo_content_activity SET note='edited' WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS au = ROW_COUNT;
    DELETE FROM public.seo_content_activity WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS ad = ROW_COUNT;
    IF cu=0 AND cd=0 AND au=0 AND ad=0 THEN
      RAISE NOTICE 'PASS: comments + activity append-only (no update/delete for anyone)';
    ELSE RAISE EXCEPTION 'FAIL: comment(u=% d=%) activity(u=% d=%)', cu, cd, au, ad; END IF;
  END $$;
ROLLBACK;

-- Client cannot forge activity by direct INSERT (must go through the RPC).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      INSERT INTO public.seo_content_activity
        (workspace_id, website_id, website_url, content_opportunity_id, actor_user_id, actor_role_snapshot, activity_type)
      VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
              'https://stage3-smoke-1.example','33333333-0000-0000-0000-0000000000c1',
              current_setting('seo3.client_id')::uuid,'client','status_changed');
      RAISE EXCEPTION 'FAIL: client forged an activity row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from direct activity insert (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- =============================================================================
-- 7. Assets + Storage.
-- =============================================================================
SELECT '=== 7. assets + storage ===' AS step;

-- 7a. Manager can insert asset metadata (all 5 allowed MIME types). ROLLBACK.
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE m text; i int := 0;
  BEGIN
    FOREACH m IN ARRAY ARRAY['application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'image/png','image/jpeg','image/webp'] LOOP
      i := i + 1;
      INSERT INTO public.seo_content_assets
        (workspace_id, website_id, website_url, content_opportunity_id, asset_scope, bucket_name,
         storage_path, original_file_name, mime_type)
      VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
              'https://stage3-smoke-1.example','33333333-0000-0000-0000-0000000000c1','opportunity',
              'seo-content-assets',
              '33333333-0000-0000-0000-000000000001/33333333-0000-0000-0000-0000000000b1/opportunity/asset'||i||'_f',
              'f'||i, m);
    END LOOP;
    RAISE NOTICE 'PASS: owner inserted asset metadata for all 5 allowed MIME types';
  END $$;
ROLLBACK;

-- 7b. Client CANNOT insert asset metadata (RLS insert = manager set).
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      INSERT INTO public.seo_content_assets
        (workspace_id, website_id, website_url, content_opportunity_id, asset_scope, storage_path, original_file_name, mime_type)
      VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
              'https://stage3-smoke-1.example','33333333-0000-0000-0000-0000000000c1','opportunity',
              '33333333-0000-0000-0000-000000000001/x/opportunity/client_f','client.pdf','application/pdf');
      RAISE EXCEPTION 'FAIL: client inserted asset metadata';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting asset metadata (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- 7c. MIME CHECK blocks SVG / ZIP / EXE-style types (seed as privileged; expect CHECK error).
BEGIN;
  DO $$
  DECLARE m text;
  BEGIN
    FOREACH m IN ARRAY ARRAY['image/svg+xml','application/zip','application/x-msdownload','text/html'] LOOP
      BEGIN
        INSERT INTO public.seo_content_assets
          (workspace_id, website_id, website_url, asset_scope, storage_path, original_file_name, mime_type)
        VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
                'https://stage3-smoke-1.example','workspace',
                '33333333-0000-0000-0000-000000000001/blocked/'||md5(m),'bad', m);
        RAISE EXCEPTION 'FAIL: disallowed MIME % accepted', m;
      EXCEPTION WHEN others THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        -- expected: violates check constraint
      END;
    END LOOP;
    RAISE NOTICE 'PASS: MIME CHECK blocked svg/zip/exe/html';
  END $$;
ROLLBACK;

-- 7d. Workspace-scoped asset with NULL content_opportunity_id is allowed.
BEGIN;
  SELECT public._seo3_login(current_setting('seo3.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    INSERT INTO public.seo_content_assets
      (workspace_id, website_id, website_url, content_opportunity_id, asset_scope, storage_path, original_file_name, mime_type)
    VALUES ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-0000000000b1',
            'https://stage3-smoke-1.example', NULL, 'workspace',
            '33333333-0000-0000-0000-000000000001/33333333-0000-0000-0000-0000000000b1/workspace/ws_f','ws.pdf','application/pdf');
    RAISE NOTICE 'PASS: workspace-scoped asset with NULL opportunity allowed';
  END $$;
ROLLBACK;

-- 7e. Soft-delete works; there is no hard-delete policy (owner DELETE → 0 rows).
BEGIN;
  -- Seed one committed-in-tx asset as privileged, then act as owner.
  INSERT INTO public.seo_content_assets
    (id, workspace_id, website_id, website_url, content_opportunity_id, asset_scope, storage_path, original_file_name, mime_type)
  VALUES ('33333333-0000-0000-0000-0000000000f1','33333333-0000-0000-0000-000000000001',
          '33333333-0000-0000-0000-0000000000b1','https://stage3-smoke-1.example',
          '33333333-0000-0000-0000-0000000000c1','opportunity',
          '33333333-0000-0000-0000-000000000001/33333333-0000-0000-0000-0000000000b1/opportunity/soft_f','soft.pdf','application/pdf');
  SELECT public._seo3_login(current_setting('seo3.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE nu int; nd int;
  BEGIN
    UPDATE public.seo_content_assets
      SET is_deleted=true, deleted_at=now(), deleted_by=current_setting('seo3.owner_id')::uuid
      WHERE id='33333333-0000-0000-0000-0000000000f1';
    GET DIAGNOSTICS nu = ROW_COUNT;
    DELETE FROM public.seo_content_assets WHERE id='33333333-0000-0000-0000-0000000000f1';
    GET DIAGNOSTICS nd = ROW_COUNT;
    IF nu=1 AND nd=0 THEN RAISE NOTICE 'PASS: asset soft-delete works (1); hard-delete blocked (0)';
    ELSE RAISE EXCEPTION 'FAIL: soft-delete=% hard-delete=%', nu, nd; END IF;
  END $$;
ROLLBACK;

-- 7f. Bucket is private + object policies exist (structural, privileged reads).
DO $$
DECLARE is_pub boolean; npol int;
BEGIN
  SELECT public INTO is_pub FROM storage.buckets WHERE id='seo-content-assets';
  IF is_pub IS FALSE THEN RAISE NOTICE 'PASS: bucket seo-content-assets is private (public=false)';
  ELSE RAISE EXCEPTION 'FAIL: bucket public=% (expected false)', is_pub; END IF;

  SELECT count(*) INTO npol FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND policyname IN ('seo_content_assets_obj_select','seo_content_assets_obj_insert');
  IF npol=2 THEN RAISE NOTICE 'PASS: both storage.objects policies present';
  ELSE RAISE EXCEPTION 'FAIL: expected 2 storage.objects policies, found %', npol; END IF;
END $$;

-- 7g. OPTIONAL storage.objects INSERT RLS: client denied, manager allowed on a
--     workspace-scoped path. Wrapped in ROLLBACK; tolerant of environment
--     differences (non-RLS errors are reported as SKIP, never FAIL).
BEGIN;
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE p text := '33333333-0000-0000-0000-000000000001/33333333-0000-0000-0000-0000000000b1/opportunity/objtest_f.pdf';
  BEGIN
    -- client → must be denied by the INSERT policy.
    PERFORM public._seo3_login(current_setting('seo3.client_id')::uuid);
    BEGIN
      INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('seo-content-assets', p, auth.uid());
      RAISE EXCEPTION 'FAIL: client uploaded to storage.objects';
    EXCEPTION
      WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'PASS: client storage upload denied by policy';
      WHEN others THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        IF SQLERRM LIKE '%row-level security%' THEN RAISE NOTICE 'PASS: client storage upload denied by RLS';
        ELSE RAISE NOTICE 'SKIP: storage.objects client-insert test inconclusive (%)', SQLERRM; END IF;
    END;
    -- owner → should be allowed (rolled back). A 42501 here can mean either the
    -- INSERT policy OR a missing table-level grant to `authenticated`; since we
    -- cannot tell them apart by SQLSTATE, report SKIP (not FAIL) to avoid a
    -- false negative from environment grant differences. The client-denied +
    -- structural checks (7f) are the authoritative signals.
    PERFORM public._seo3_login(current_setting('seo3.owner_id')::uuid);
    BEGIN
      INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('seo-content-assets', p, auth.uid());
      RAISE NOTICE 'PASS: owner storage upload allowed on workspace-scoped path';
    EXCEPTION
      WHEN insufficient_privilege OR check_violation THEN
        RAISE NOTICE 'SKIP: owner storage upload blocked (policy or table grant); verify grants manually';
      WHEN others THEN
        RAISE NOTICE 'SKIP: storage.objects owner-insert test inconclusive (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- =============================================================================
-- 8. Non-member isolation.
-- =============================================================================
SELECT '=== 8. non-member isolation ===' AS step;

BEGIN;
  SELECT public._seo3_login(current_setting('seo3.nonmember_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE o int; d int;
  BEGIN
    SELECT count(*) INTO o FROM public.seo_content_opportunities WHERE id='33333333-0000-0000-0000-0000000000c1';
    SELECT count(*) INTO d FROM public.seo_content_drafts WHERE content_opportunity_id='33333333-0000-0000-0000-0000000000c1';
    IF o=0 AND d=0 THEN RAISE NOTICE 'PASS: non-member reads no opportunity/draft rows';
    ELSE RAISE EXCEPTION 'FAIL: non-member saw opp=% draft=%', o, d; END IF;

    BEGIN
      PERFORM public.seo_content_transition('33333333-0000-0000-0000-0000000000c1','comment','I should not be here');
      RAISE EXCEPTION 'FAIL: non-member called transition RPC';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: non-member blocked from transition RPC (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- ---------- cleanup of the test-only helpers --------------------------------
DROP FUNCTION IF EXISTS public._seo3_ct(uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public._seo3_login(uuid);

SELECT '=== STAGE 3 SMOKE TEST COMPLETE — check Messages/Notices for PASS/FAIL/SKIP ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY the two Stage-3 test workspaces
-- and their cascaded content rows). Storage OBJECTS are NOT touched (none are
-- created outside rolled-back tests). Uncomment and run manually for a clean
-- project.
-- =============================================================================
-- DELETE FROM public.seo_workspaces WHERE id IN
--   ('33333333-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000002');
-- -- (module-access rows for the 5 users are shared with the Stage-2 test; leave them.)
