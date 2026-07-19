-- =============================================================================
-- SEO Stage 6 — Off-Page Authority + AI Visibility/GEO — SMOKE TEST (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on a FRESH/disposable Supabase TEST project, AFTER Stage 1
-- (…120001-120003), Stage 2 (…120004-120006), Stage 4 (…120010-120013),
-- Stage 5 (…120014-120016) AND Stage 6 (…120017-120023) migrations are applied.
-- NEVER run on production. (Stage 3 is not required by this smoke test.)
--
-- This script is NON-DESTRUCTIVE to Core / Stage 1-5 data. It creates its own
-- disposable rows under TWO test workspaces (UUID prefix 99999999-, distinct
-- from Stage 2's aaaaaaaa-…ffffffff-, Stage 3's 33333333-, the UI dataset
-- 44444444-, Stage 4's 55555555-, and Stage 5's 77777777-). It PRE-CLEANS any
-- leftover 99999999- rows at the top and FULLY TEARS DOWN its own rows at the
-- bottom, so it is safe to re-run and leaves NOTHING behind except the shared
-- helper auth users (project convention — those are reused by every stage's
-- smoke test) and their idempotent user_module_access grants.
--
-- PREREQUISITE — five users must already exist in Supabase Auth. On this TEST
-- project they already do (seo-owner/admin/team/client/nonmember-test@example.com);
-- their UUIDs are pasted below. FKs reference auth.users, so real users are
-- required. Do NOT insert into auth.users from SQL. Do NOT use a service role
-- key anywhere in this script.
--
-- RLS NOTE (the Stage 4/5 lesson): in the Supabase SQL Editor / Management-API
-- query the connection role is `postgres`, which has BYPASSRLS — so setting JWT
-- claims alone does NOT exercise RLS. Every RLS check below therefore runs inside
-- its own `BEGIN; SET LOCAL ROLE authenticated; … ROLLBACK;` (or COMMIT for
-- persistent positive writes) so RLS is genuinely enforced as `authenticated`.
--
-- OUTPUT NOTE: per-assertion PASS/FAIL are RAISE NOTICE / RAISE EXCEPTION (visible
-- in the SQL Editor Messages tab). Any FAIL raises and aborts. The final SELECT
-- prints the obvious success banner; a final DO re-asserts key end-state before
-- teardown so a programmatic run (which swallows NOTICEs) still fails loudly on
-- any regression.
-- =============================================================================

-- ---------- 0. TEST USER UUIDS (session-scoped GUCs) ------------------------
SELECT set_config('seo6.owner_id',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seo6.admin_id',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('seo6.team_id',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('seo6.client_id',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('seo6.nonmember_id', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

-- Guard: refuse to run until every UUID above is a real, valid UUID.
DO $guard$
DECLARE
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_keys text[] := ARRAY['owner_id','admin_id','team_id','client_id','nonmember_id'];
  v_key text; v_value text;
BEGIN
  FOREACH v_key IN ARRAY v_keys LOOP
    v_value := current_setting('seo6.' || v_key, true);
    IF v_value IS NULL OR v_value !~ v_uuid_pattern THEN
      RAISE EXCEPTION 'seo6.% ("%") is not a valid auth.users UUID.', v_key, v_value;
    END IF;
  END LOOP;
END $guard$;

-- Prerequisite: Stage 1-6 objects must exist (fail fast on wrong project/order).
DO $prereq$
BEGIN
  IF to_regclass('public.seo_workspaces') IS NULL
     OR to_regclass('public.seo_websites') IS NULL
     OR to_regclass('public.seo_page_inventory') IS NULL
     OR to_regclass('public.seo_decline_diagnoses') IS NULL
     OR to_regclass('public.seo_authority_opportunities') IS NULL
     OR to_regclass('public.seo_authority_campaigns') IS NULL
     OR to_regclass('public.seo_authority_campaign_tasks') IS NULL
     OR to_regclass('public.seo_authority_campaign_opportunities') IS NULL
     OR to_regclass('public.seo_authority_activity') IS NULL
     OR to_regclass('public.seo_ai_prompt_tracking') IS NULL
     OR to_regclass('public.seo_ai_content_gaps') IS NULL
     OR to_regclass('public.seo_ai_mentions') IS NULL
     OR to_regprocedure('public.seo_authority_opportunity_transition(uuid,text,text)') IS NULL
     OR to_regprocedure('public.seo_authority_campaign_transition(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Prerequisite missing: apply Stages 1-6 before running this smoke test.';
  END IF;
  RAISE NOTICE 'PASS: Stage 1-6 objects present.';
END $prereq$;

-- ---------- Test-only login helper (dropped in teardown) --------------------
CREATE OR REPLACE FUNCTION public._seo6_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $fn$;

-- ---------- PRE-CLEAN any leftover rows from a prior aborted run -------------
-- Deleting the workspaces cascades to websites + every Stage 6 child row.
-- Committed explicitly so a re-run starts from a genuinely clean slate.
BEGIN;
  DELETE FROM public.seo_workspaces WHERE id IN (
    '99999999-0000-0000-0000-000000000001',
    '99999999-0000-0000-0000-000000000002');
COMMIT;

-- Disposable UUID map (all 99999999-prefixed):
--   WS1 …0001  WS2 …0002   WEB1 …00b1 (ws1)  WEB3 …00b3 (ws1)  WEB2 …00b2 (ws2)
--   Opportunities …00a1 workflow · …00a2 illegal/junction/delete · …00a3 reject-role
--     · …00a4 dup-active-base · …00a6 terminal(avoided) · …00a7 active-same-url
--     · …00a8/…00a9 url-less · …00aa cross-website(WEB3) · …00ab cross-workspace(WS2)
--     · …00ac delete-opp
--   Campaigns …00c1 happy · …00c2 reject-path · …00c3 team-cannot-approve · …00cd delete
--   Task …00d1   Prompts …00e1 main · …00e2 same-text-later · …00e9 delete-prompt
--   Gaps …00f1 main · …00f9 delete-prompt   Mentions …000b/000c/000d main · …000e delete-prompt

-- =============================================================================
-- A. SETUP — two workspaces, members, three websites, module access.
--    Created as the privileged role (RLS bypassed for seeding), same as every
--    prior smoke test. The owner is auto-added as an 'owner' member by the
--    Stage 1 AFTER INSERT trigger — do NOT insert that member row manually.
-- =============================================================================
SELECT '=== A. SETUP: workspaces, members, websites, module access ===' AS step;

INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seo6.' || k)::uuid, 'seo', true
FROM (VALUES ('owner_id'),('admin_id'),('team_id'),('client_id'),('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

INSERT INTO public.seo_workspaces (id, name, owner_user_id) VALUES
  ('99999999-0000-0000-0000-000000000001', 'Stage6 OffPage/AI Smoke WS1', current_setting('seo6.owner_id')::uuid),
  ('99999999-0000-0000-0000-000000000002', 'Stage6 OffPage/AI Smoke WS2', current_setting('seo6.owner_id')::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status) VALUES
  ('99999999-0000-0000-0000-000000000001', current_setting('seo6.admin_id')::uuid,  'admin',       'active'),
  ('99999999-0000-0000-0000-000000000001', current_setting('seo6.team_id')::uuid,   'team_member', 'active'),
  ('99999999-0000-0000-0000-000000000001', current_setting('seo6.client_id')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name) VALUES
  ('99999999-0000-0000-0000-0000000000b1', '99999999-0000-0000-0000-000000000001',
   'https://stage6-smoke-ws1.example', 'Stage6 Smoke Site WS1', 'Stage6 Smoke Co WS1'),
  ('99999999-0000-0000-0000-0000000000b3', '99999999-0000-0000-0000-000000000001',
   'https://stage6-smoke-ws1-b.example', 'Stage6 Smoke Site WS1-B', 'Stage6 Smoke Co WS1'),
  ('99999999-0000-0000-0000-0000000000b2', '99999999-0000-0000-0000-000000000002',
   'https://stage6-smoke-ws2.example', 'Stage6 Smoke Site WS2', 'Stage6 Smoke Co WS2')
ON CONFLICT (workspace_id, website_url) DO NOTHING;

-- =============================================================================
-- B. BASIC MANAGER INSERTS — as owner/admin/team_member, inside authenticated
--    transactions (proves the RLS write policy allows managers) and COMMITted so
--    later read/RLS/RPC checks can see them.
-- =============================================================================
SELECT '=== B. manager inserts across all writable Stage 6 tables ===' AS step;

-- B1: opportunity a1 as team_member (default status 'suggested').
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform,
     target_url, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a1', '99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
          'backlink', 'Guest post on industry blog', 'industryblog.example',
          'https://industryblog.example/write-for-us', 'Pitch a guest article', 'Builds topical authority');
COMMIT;

-- B2: opportunity a2 as admin (used for junction + illegal-jump + delete tests).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform,
     target_url, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a2', '99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
          'citation', 'Local directory listing', 'localdir.example',
          'https://localdir.example/add', 'Add a NAP-consistent citation', 'Improves local trust');
COMMIT;

-- B3: campaign c1 as team_member (draft).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_authority_campaigns
    (id, workspace_id, website_id, website_url, name, goal)
  VALUES ('99999999-0000-0000-0000-0000000000c1', '99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
          'Q3 Local Trust Push', 'Improve local authority signals');
COMMIT;

-- B4: task t1 under c1 as team_member.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_authority_campaign_tasks
    (id, workspace_id, website_id, website_url, campaign_id, opportunity_id, label, position)
  VALUES ('99999999-0000-0000-0000-0000000000d1', '99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
          '99999999-0000-0000-0000-0000000000c1', '99999999-0000-0000-0000-0000000000a2',
          'Submit local directory citation', 0);
COMMIT;

-- B5: junction c1 <-> a2 as team_member (valid link, same ws/website).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_authority_campaign_opportunities
    (workspace_id, website_id, website_url, campaign_id, opportunity_id)
  VALUES ('99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-0000000000b1',
          'https://stage6-smoke-ws1.example', '99999999-0000-0000-0000-0000000000c1',
          '99999999-0000-0000-0000-0000000000a2');
COMMIT;

-- B6: prompt tracking e1 as team_member.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_ai_prompt_tracking
    (id, workspace_id, website_id, website_url, prompt_text, topic, visibility_status,
     brand_mentioned, competitors_mentioned, our_site_cited, observed_on)
  VALUES ('99999999-0000-0000-0000-0000000000e1', '99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
          'best seo agency for local business', 'seo services', 'partially_visible',
          true, ARRAY['CompetitorA','CompetitorB'], false, current_date);
COMMIT;

-- B7: content gap f1 (linked to prompt e1) as admin.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_ai_content_gaps
    (id, workspace_id, website_id, website_url, related_prompt_id, topic, missing_answer_angle,
     suggested_content_type, related_keyword_or_question, recommended_next_action)
  VALUES ('99999999-0000-0000-0000-0000000000f1', '99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
          '99999999-0000-0000-0000-0000000000e1', 'local seo pricing',
          'No transparent pricing explanation', 'pricing guide',
          'how much does local seo cost', 'Publish a pricing explainer page');
COMMIT;

-- B8: mentions (brand / competitor / citation_source) linked to prompt e1 as team_member.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_ai_mentions
    (id, workspace_id, website_id, website_url, prompt_tracking_id, mention_type, entity_name,
     is_our_site, sentiment, prominence)
  VALUES
    ('99999999-0000-0000-0000-00000000000b', '99999999-0000-0000-0000-000000000001',
     '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
     '99999999-0000-0000-0000-0000000000e1', 'brand', 'Stage6 Smoke Co WS1', true, 'positive', 'medium'),
    ('99999999-0000-0000-0000-00000000000c', '99999999-0000-0000-0000-000000000001',
     '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
     '99999999-0000-0000-0000-0000000000e1', 'competitor', 'CompetitorA', false, 'neutral', 'high'),
    ('99999999-0000-0000-0000-00000000000d', '99999999-0000-0000-0000-000000000001',
     '99999999-0000-0000-0000-0000000000b1', 'https://stage6-smoke-ws1.example',
     '99999999-0000-0000-0000-0000000000e1', 'citation_source', 'reviewsite.example', false, 'neutral', 'low');
COMMIT;

DO $b$
DECLARE n_opp int; n_camp int; n_task int; n_junc int; n_prm int; n_gap int; n_men int;
BEGIN
  SELECT count(*) INTO n_opp  FROM public.seo_authority_opportunities WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  SELECT count(*) INTO n_camp FROM public.seo_authority_campaigns     WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  SELECT count(*) INTO n_task FROM public.seo_authority_campaign_tasks WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  SELECT count(*) INTO n_junc FROM public.seo_authority_campaign_opportunities WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  SELECT count(*) INTO n_prm  FROM public.seo_ai_prompt_tracking      WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  SELECT count(*) INTO n_gap  FROM public.seo_ai_content_gaps         WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  SELECT count(*) INTO n_men  FROM public.seo_ai_mentions             WHERE workspace_id='99999999-0000-0000-0000-000000000001';
  IF n_opp=2 AND n_camp=1 AND n_task=1 AND n_junc=1 AND n_prm=1 AND n_gap=1 AND n_men=3 THEN
    RAISE NOTICE 'PASS: manager inserts persisted (opp=% camp=% task=% junc=% prompt=% gap=% mentions=%)',
      n_opp,n_camp,n_task,n_junc,n_prm,n_gap,n_men;
  ELSE
    RAISE EXCEPTION 'FAIL: manager insert counts opp=% camp=% task=% junc=% prompt=% gap=% mentions=% (expected 2/1/1/1/1/1/3)',
      n_opp,n_camp,n_task,n_junc,n_prm,n_gap,n_men;
  END IF;
END $b$;

-- =============================================================================
-- C. RLS ROLE BEHAVIOR — members (incl. client) read; nonmember isolated;
--    client cannot write; managers can. Each runs as `authenticated`.
-- =============================================================================
SELECT '=== C. RLS role read/write behavior ===' AS step;

-- C1: owner/admin/team/client all SEE the seeded opportunity a1 + campaign c1
--     + prompt e1 + a mention; nonmember sees none. (RLS reads must be real
--     transactions with SET LOCAL ROLE — done explicitly per role.)
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_o int; n_c int; n_p int; n_m int;
  BEGIN
    SELECT count(*) INTO n_o FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a1';
    SELECT count(*) INTO n_c FROM public.seo_authority_campaigns     WHERE id='99999999-0000-0000-0000-0000000000c1';
    SELECT count(*) INTO n_p FROM public.seo_ai_prompt_tracking      WHERE id='99999999-0000-0000-0000-0000000000e1';
    SELECT count(*) INTO n_m FROM public.seo_ai_mentions             WHERE workspace_id='99999999-0000-0000-0000-000000000001';
    IF n_o=1 AND n_c=1 AND n_p=1 AND n_m=3 THEN RAISE NOTICE 'PASS: owner reads opp/camp/prompt/mentions (1/1/1/3)';
    ELSE RAISE EXCEPTION 'FAIL: owner read opp=% camp=% prompt=% mentions=% (expected 1/1/1/3)', n_o,n_c,n_p,n_m; END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo6_login(current_setting('seo6.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_o int;
  BEGIN
    SELECT count(*) INTO n_o FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a1';
    IF n_o=1 THEN RAISE NOTICE 'PASS: admin reads opportunity a1'; ELSE RAISE EXCEPTION 'FAIL: admin read a1=%',n_o; END IF;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_o int; n_act int;
  BEGIN
    SELECT count(*) INTO n_o FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a1';
    SELECT count(*) INTO n_act FROM public.seo_authority_activity WHERE workspace_id='99999999-0000-0000-0000-000000000001';
    IF n_o=1 THEN RAISE NOTICE 'PASS: team_member reads opportunity a1 + activity(%)', n_act;
    ELSE RAISE EXCEPTION 'FAIL: team read a1=%',n_o; END IF;
  END $$;
ROLLBACK;

-- C2: client is READ-ONLY — can SELECT, cannot INSERT/UPDATE/DELETE.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_o int; n int;
  BEGIN
    -- client CAN read
    SELECT count(*) INTO n_o FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a1';
    IF n_o=1 THEN RAISE NOTICE 'PASS: client can READ opportunity a1'; ELSE RAISE EXCEPTION 'FAIL: client read a1=%',n_o; END IF;

    -- client INSERT denied (RLS WITH CHECK raises)
    BEGIN
      INSERT INTO public.seo_authority_opportunities
        (workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
      VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
              'https://stage6-smoke-ws1.example','review','client attempt','x','x','x');
      RAISE EXCEPTION 'FAIL: client inserted an opportunity';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from INSERT opportunity (%)', SQLERRM;
    END;

    -- client UPDATE denied (RLS -> 0 rows)
    UPDATE public.seo_authority_opportunities SET title='hacked' WHERE id='99999999-0000-0000-0000-0000000000a1';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n=0 THEN RAISE NOTICE 'PASS: client UPDATE opportunity blocked (0 rows)'; ELSE RAISE EXCEPTION 'FAIL: client updated % opp row(s)',n; END IF;

    -- client DELETE denied (RLS -> 0 rows)
    DELETE FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a1';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n=0 THEN RAISE NOTICE 'PASS: client DELETE opportunity blocked (0 rows)'; ELSE RAISE EXCEPTION 'FAIL: client deleted % opp row(s)',n; END IF;
  END $$;
ROLLBACK;

-- C3: nonmember is fully isolated (0 rows on read; write denied).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.nonmember_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_o int; n_c int; n_p int;
  BEGIN
    SELECT count(*) INTO n_o FROM public.seo_authority_opportunities WHERE workspace_id='99999999-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_c FROM public.seo_authority_campaigns     WHERE workspace_id='99999999-0000-0000-0000-000000000001';
    SELECT count(*) INTO n_p FROM public.seo_ai_prompt_tracking      WHERE workspace_id='99999999-0000-0000-0000-000000000001';
    IF n_o=0 AND n_c=0 AND n_p=0 THEN RAISE NOTICE 'PASS: nonmember isolated (0 rows across Stage 6)';
    ELSE RAISE EXCEPTION 'FAIL: nonmember saw opp=% camp=% prompt=% (expected 0/0/0)', n_o,n_c,n_p; END IF;

    BEGIN
      INSERT INTO public.seo_ai_prompt_tracking (workspace_id, website_id, website_url, prompt_text, topic)
      VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
              'https://stage6-smoke-ws1.example','nonmember attempt','x');
      RAISE EXCEPTION 'FAIL: nonmember inserted a prompt row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: nonmember blocked from INSERT (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- =============================================================================
-- D. AUTHORITY OPPORTUNITY WORKFLOW RPC — legal path, illegal jumps, terminal
--    guard, reject role gating, client/nonmember denial, activity logging.
-- =============================================================================
SELECT '=== D. seo_authority_opportunity_transition ===' AS step;

-- D1: legal path on a1 as team_member: suggested -> shortlisted ->
--     approval_required -> in_progress -> completed. COMMITted (final state used later).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE v text;
  BEGIN
    v := public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a1','shortlist','step1');
    IF v<>'shortlisted' THEN RAISE EXCEPTION 'FAIL: shortlist -> %', v; END IF;
    v := public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a1','request_approval',NULL);
    IF v<>'approval_required' THEN RAISE EXCEPTION 'FAIL: request_approval -> %', v; END IF;
    v := public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a1','start',NULL);
    IF v<>'in_progress' THEN RAISE EXCEPTION 'FAIL: start -> %', v; END IF;
    v := public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a1','complete','done');
    IF v<>'completed' THEN RAISE EXCEPTION 'FAIL: complete -> %', v; END IF;
    RAISE NOTICE 'PASS: opportunity legal path suggested->shortlisted->approval_required->in_progress->completed';
  END $$;
COMMIT;

-- D2: activity rows for a1 are correct (4 rows, server-derived actor role snapshot).
DO $$
DECLARE n int; n_bad_actor int; n_start_ok int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_authority_activity
   WHERE opportunity_id='99999999-0000-0000-0000-0000000000a1' AND subject_type='opportunity';
  SELECT count(*) INTO n_bad_actor FROM public.seo_authority_activity
   WHERE opportunity_id='99999999-0000-0000-0000-0000000000a1' AND actor_role_snapshot IS DISTINCT FROM 'team_member';
  -- the 'start' transition must record from_status=approval_required, to_status=in_progress
  SELECT count(*) INTO n_start_ok FROM public.seo_authority_activity
   WHERE opportunity_id='99999999-0000-0000-0000-0000000000a1'
     AND activity_type='start' AND from_status='approval_required' AND to_status='in_progress';
  IF n=4 AND n_bad_actor=0 AND n_start_ok=1 THEN
    RAISE NOTICE 'PASS: 4 activity rows, actor_role_snapshot=team_member, start from/to correct';
  ELSE
    RAISE EXCEPTION 'FAIL: activity rows=% bad_actor=% start_ok=% (expected 4/0/1)', n, n_bad_actor, n_start_ok;
  END IF;
END $$;

-- D3: illegal jump — start from 'suggested' (a2 is still suggested) must raise.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a2','start',NULL);
      RAISE EXCEPTION 'FAIL: illegal start-from-suggested was allowed';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: illegal jump suggested->in_progress rejected (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- D4: terminal guard — a1 is 'completed'; complete again / reject must raise.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a1','reject','x');
      RAISE EXCEPTION 'FAIL: reopening/reject of terminal completed was allowed';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: terminal opportunity cannot be reject-reopened (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- D5: reject is owner/admin-only — team_member reject on a3 raises; owner reject succeeds.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  -- create a3 as team (suggested), then attempt reject as team (must raise)
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a3','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
          'pr','Risky PR pitch','pr.example','Pitch a story','Coverage');
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a3','reject','team try');
      RAISE EXCEPTION 'FAIL: team_member was allowed to reject';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: team_member reject rejected (owner/admin-only) (%)', SQLERRM;
    END;
  END $$;
COMMIT;

BEGIN;
  SELECT public._seo6_login(current_setting('seo6.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE v text;
  BEGIN
    v := public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a3','reject','owner ok');
    IF v='rejected' THEN RAISE NOTICE 'PASS: owner reject -> rejected'; ELSE RAISE EXCEPTION 'FAIL: owner reject -> %', v; END IF;
  END $$;
COMMIT;

-- D6: client and nonmember cannot call the opportunity RPC (in-function role check).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a2','shortlist','client');
      RAISE EXCEPTION 'FAIL: client called opportunity RPC successfully';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from opportunity RPC (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

BEGIN;
  SELECT public._seo6_login(current_setting('seo6.nonmember_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_opportunity_transition('99999999-0000-0000-0000-0000000000a2','shortlist','nonmember');
      RAISE EXCEPTION 'FAIL: nonmember called opportunity RPC successfully';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: nonmember blocked from opportunity RPC (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- =============================================================================
-- E. AUTHORITY CAMPAIGN WORKFLOW RPC — submit/approve/reject/return, role gating.
-- =============================================================================
SELECT '=== E. seo_authority_campaign_transition ===' AS step;

-- E1: c1 draft -> pending_approval (team) -> approved (owner). COMMITted.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE v text;
  BEGIN
    v := public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c1','submit_for_approval','ready');
    IF v<>'pending_approval' THEN RAISE EXCEPTION 'FAIL: submit -> %', v; END IF;
    RAISE NOTICE 'PASS: team submitted campaign c1 -> pending_approval';
  END $$;
COMMIT;

-- E1b: team_member cannot approve (manager-only) — must raise.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c1','approve','team try');
      RAISE EXCEPTION 'FAIL: team_member approved a campaign';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: team_member approve rejected (manager-only) (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- E1c: owner approves c1 -> approved.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE v text;
  BEGIN
    v := public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c1','approve','approved by owner');
    IF v='approved' THEN RAISE NOTICE 'PASS: owner approved c1 -> approved'; ELSE RAISE EXCEPTION 'FAIL: approve -> %', v; END IF;
  END $$;
COMMIT;

-- E2: c2 reject path — submit (team) -> reject (admin) -> return_to_draft (team).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.seo_authority_campaigns (id, workspace_id, website_id, website_url, name, goal)
  VALUES ('99999999-0000-0000-0000-0000000000c2','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example','Reject Path Campaign','test reject');
  DO $$
  DECLARE v text;
  BEGIN
    v := public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c2','submit_for_approval',NULL);
    IF v<>'pending_approval' THEN RAISE EXCEPTION 'FAIL: c2 submit -> %', v; END IF;
  END $$;
COMMIT;

BEGIN;
  SELECT public._seo6_login(current_setting('seo6.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE v text;
  BEGIN
    v := public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c2','reject','not yet');
    IF v<>'rejected' THEN RAISE EXCEPTION 'FAIL: admin reject -> %', v; END IF;
    v := public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c2','return_to_draft','reworking');
    IF v<>'draft' THEN RAISE EXCEPTION 'FAIL: return_to_draft -> %', v; END IF;
    RAISE NOTICE 'PASS: admin reject then return_to_draft on c2';
  END $$;
COMMIT;

-- E3: invalid campaign transition — approve from draft must raise.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.owner_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      -- c2 is back to draft; approve directly is illegal
      PERFORM public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c2','approve','skip');
      RAISE EXCEPTION 'FAIL: approve-from-draft was allowed';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: invalid campaign transition (approve from draft) rejected (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- E4: client/nonmember cannot transition a campaign.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      PERFORM public.seo_authority_campaign_transition('99999999-0000-0000-0000-0000000000c2','submit_for_approval','client');
      RAISE EXCEPTION 'FAIL: client transitioned a campaign';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from campaign RPC (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- E5: campaign activity rows have subject_type='campaign'.
DO $$
DECLARE n int; n_bad int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_authority_activity
   WHERE campaign_id IN ('99999999-0000-0000-0000-0000000000c1','99999999-0000-0000-0000-0000000000c2')
     AND subject_type='campaign';
  SELECT count(*) INTO n_bad FROM public.seo_authority_activity
   WHERE campaign_id IS NOT NULL AND (subject_type<>'campaign' OR opportunity_id IS NOT NULL);
  IF n>=4 AND n_bad=0 THEN RAISE NOTICE 'PASS: campaign activity rows correct (count=% subject_type=campaign)', n;
  ELSE RAISE EXCEPTION 'FAIL: campaign activity count=% bad=% (expected >=4 / 0)', n, n_bad; END IF;
END $$;

-- =============================================================================
-- F. JUNCTION INTEGRITY — duplicate PK rejection, cross-workspace + cross-website
--    integrity-trigger rejection, cascade delete behavior.
-- =============================================================================
SELECT '=== F. junction integrity + cascades ===' AS step;

-- F1: duplicate link c1<->a2 rejected by PK.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_authority_campaign_opportunities
      (workspace_id, website_id, website_url, campaign_id, opportunity_id)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','99999999-0000-0000-0000-0000000000c1','99999999-0000-0000-0000-0000000000a2');
    RAISE EXCEPTION 'FAIL: duplicate campaign-opportunity link was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: duplicate junction link rejected by PK (%)', SQLERRM;
  END;
END $$;

-- F2: cross-workspace link rejected by integrity trigger.
--     Create an opportunity ab in WS2, then try to link c1 (WS1) <-> ab (WS2).
INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
VALUES ('99999999-0000-0000-0000-0000000000ab','99999999-0000-0000-0000-000000000002',
        '99999999-0000-0000-0000-0000000000b2','https://stage6-smoke-ws2.example',
        'backlink','WS2 opportunity','other.example','x','x')
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_authority_campaign_opportunities
      (workspace_id, website_id, website_url, campaign_id, opportunity_id)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','99999999-0000-0000-0000-0000000000c1','99999999-0000-0000-0000-0000000000ab');
    RAISE EXCEPTION 'FAIL: cross-workspace junction link was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cross-workspace junction link rejected by trigger (%)', SQLERRM;
  END;
END $$;

-- F3: cross-website (same workspace) link rejected by integrity trigger.
--     Create opportunity aa on WEB3 (WS1) and try to link c1 (WEB1) <-> aa (WEB3).
INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
VALUES ('99999999-0000-0000-0000-0000000000aa','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b3','https://stage6-smoke-ws1-b.example',
        'mention','WEB3 opportunity','blog.example','x','x')
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_authority_campaign_opportunities
      (workspace_id, website_id, website_url, campaign_id, opportunity_id)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','99999999-0000-0000-0000-0000000000c1','99999999-0000-0000-0000-0000000000aa');
    RAISE EXCEPTION 'FAIL: cross-website junction link was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cross-website junction link rejected by trigger (%)', SQLERRM;
  END;
END $$;

-- F4: cascade delete — deleting a campaign removes its tasks + junction + activity;
--     deleting an opportunity removes its junction rows. Uses temp cd + ac.
INSERT INTO public.seo_authority_campaigns (id, workspace_id, website_id, website_url, name, goal)
VALUES ('99999999-0000-0000-0000-0000000000cd','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example','Delete Cascade Campaign','test cascade')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
VALUES ('99999999-0000-0000-0000-0000000000ac','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
        'partnership','Cascade opp','partner.example','x','x')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_authority_campaign_tasks (workspace_id, website_id, website_url, campaign_id, label, position)
VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
        'https://stage6-smoke-ws1.example','99999999-0000-0000-0000-0000000000cd','cascade task',0)
ON CONFLICT DO NOTHING;
INSERT INTO public.seo_authority_campaign_opportunities (workspace_id, website_id, website_url, campaign_id, opportunity_id)
VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
        'https://stage6-smoke-ws1.example','99999999-0000-0000-0000-0000000000cd','99999999-0000-0000-0000-0000000000ac')
ON CONFLICT DO NOTHING;
-- an activity row on cd (manager insert)
INSERT INTO public.seo_authority_activity (workspace_id, website_id, website_url, subject_type, campaign_id, activity_type)
VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
        'https://stage6-smoke-ws1.example','campaign','99999999-0000-0000-0000-0000000000cd','note')
ON CONFLICT DO NOTHING;

DO $$
DECLARE n_task int; n_junc int; n_act int;
BEGIN
  DELETE FROM public.seo_authority_campaigns WHERE id='99999999-0000-0000-0000-0000000000cd';
  SELECT count(*) INTO n_task FROM public.seo_authority_campaign_tasks WHERE campaign_id='99999999-0000-0000-0000-0000000000cd';
  SELECT count(*) INTO n_junc FROM public.seo_authority_campaign_opportunities WHERE campaign_id='99999999-0000-0000-0000-0000000000cd';
  SELECT count(*) INTO n_act  FROM public.seo_authority_activity WHERE campaign_id='99999999-0000-0000-0000-0000000000cd';
  IF n_task=0 AND n_junc=0 AND n_act=0 THEN RAISE NOTICE 'PASS: deleting campaign cascaded tasks/junction/activity to 0';
  ELSE RAISE EXCEPTION 'FAIL: after campaign delete tasks=% junc=% act=% (expected 0/0/0)', n_task,n_junc,n_act; END IF;
END $$;

DO $$
DECLARE n_junc int; n_camp int;
BEGIN
  -- deleting opportunity ac removes its junction rows but leaves campaigns intact
  DELETE FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000ac';
  SELECT count(*) INTO n_junc FROM public.seo_authority_campaign_opportunities WHERE opportunity_id='99999999-0000-0000-0000-0000000000ac';
  SELECT count(*) INTO n_camp FROM public.seo_authority_campaigns WHERE id='99999999-0000-0000-0000-0000000000c1';
  IF n_junc=0 AND n_camp=1 THEN RAISE NOTICE 'PASS: deleting opportunity removed its junction rows, campaigns intact';
  ELSE RAISE EXCEPTION 'FAIL: after opp delete junc=% camp=% (expected 0/1)', n_junc,n_camp; END IF;
END $$;

-- =============================================================================
-- G. SOFT DUPLICATE GUARD (D7) — active URL dup rejected; URL-less repeats OK;
--    terminal duplicates do not block a future active one.
-- =============================================================================
SELECT '=== G. opportunity soft duplicate guard ===' AS step;

-- a4: active opportunity with a target_url.
INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, target_url, suggested_action, why_it_matters)
VALUES ('99999999-0000-0000-0000-0000000000a4','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
        'citation','Dup base','dir.example','https://dir.example/listing','x','x')
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  BEGIN
    -- same website + opportunity_type + lower(target_url), both active -> rejected.
    INSERT INTO public.seo_authority_opportunities
      (workspace_id, website_id, website_url, opportunity_type, title, source_platform, target_url, suggested_action, why_it_matters)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','citation','Dup attempt','dir.example','https://DIR.example/listing','x','x');
    RAISE EXCEPTION 'FAIL: duplicate active opportunity (same url) was allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: duplicate active opportunity rejected by partial unique index (%)', SQLERRM;
  END;
END $$;

-- URL-less opportunities may repeat freely (no guard when target_url IS NULL).
DO $$
DECLARE n int;
BEGIN
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a8','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example','review','Urlless 1','g.example','x','x');
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a9','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example','review','Urlless 2','g.example','x','x');
  SELECT count(*) INTO n FROM public.seo_authority_opportunities
   WHERE id IN ('99999999-0000-0000-0000-0000000000a8','99999999-0000-0000-0000-0000000000a9');
  IF n=2 THEN RAISE NOTICE 'PASS: two URL-less opportunities of same type allowed';
  ELSE RAISE EXCEPTION 'FAIL: URL-less repeat count=% (expected 2)', n; END IF;
END $$;

-- Terminal (avoided) duplicate does not block a future active one with same url.
DO $$
DECLARE n int;
BEGIN
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, target_url, status, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a6','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
          'pr','Avoided base','pr2.example','https://pr2.example/x','avoided','x','x');
  -- now an ACTIVE one with the same type+url succeeds (terminal excluded from index)
  INSERT INTO public.seo_authority_opportunities
    (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, target_url, suggested_action, why_it_matters)
  VALUES ('99999999-0000-0000-0000-0000000000a7','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
          'pr','Active same url','pr2.example','https://pr2.example/x','x','x');
  SELECT count(*) INTO n FROM public.seo_authority_opportunities
   WHERE id IN ('99999999-0000-0000-0000-0000000000a6','99999999-0000-0000-0000-0000000000a7');
  IF n=2 THEN RAISE NOTICE 'PASS: terminal (avoided) dup does not block a future active opportunity with same url';
  ELSE RAISE EXCEPTION 'FAIL: terminal-dup allowance count=% (expected 2)', n; END IF;
END $$;

-- =============================================================================
-- H. AI PROMPT TRACKING — time-series (same prompt_text on different dates),
--    no prompt_text uniqueness, CHECK rejections.
-- =============================================================================
SELECT '=== H. AI prompt tracking time-series + CHECKs ===' AS step;

-- same prompt_text as e1, earlier observed_on -> allowed (no uniqueness).
-- Committed so it persists past the later BEGIN;…ROLLBACK; RLS blocks (this
-- runner treats the whole script as one transaction; a ROLLBACK discards
-- uncommitted bare inserts back to the last COMMIT).
BEGIN;
  INSERT INTO public.seo_ai_prompt_tracking
    (id, workspace_id, website_id, website_url, prompt_text, topic, observed_on, visibility_status)
  VALUES ('99999999-0000-0000-0000-0000000000e2','99999999-0000-0000-0000-000000000001',
          '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
          'best seo agency for local business', 'seo services', current_date - 7, 'not_visible');
COMMIT;
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_ai_prompt_tracking
   WHERE workspace_id='99999999-0000-0000-0000-000000000001'
     AND prompt_text='best seo agency for local business';
  IF n=2 THEN RAISE NOTICE 'PASS: same prompt_text tracked on two observed_on dates (time-series, no uniqueness)';
  ELSE RAISE EXCEPTION 'FAIL: time-series prompt count=% (expected 2)', n; END IF;
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_ai_prompt_tracking (workspace_id, website_id, website_url, prompt_text, topic, visibility_status)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','bad vis','t','glowing');
    RAISE EXCEPTION 'FAIL: invalid visibility_status accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid visibility_status rejected (%)', SQLERRM;
  END;
  BEGIN
    INSERT INTO public.seo_ai_prompt_tracking (workspace_id, website_id, website_url, prompt_text, topic, source)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','bad source','t','telepathy');
    RAISE EXCEPTION 'FAIL: invalid prompt source accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid prompt source rejected (%)', SQLERRM;
  END;
  BEGIN
    INSERT INTO public.seo_ai_prompt_tracking (workspace_id, website_id, website_url, prompt_text, topic, brand_position)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','bad pos','t',0);
    RAISE EXCEPTION 'FAIL: brand_position=0 accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: brand_position < 1 rejected (%)', SQLERRM;
  END;
END $$;

-- =============================================================================
-- I. AI CONTENT GAPS + MENTIONS — inserts, CHECK rejections, prompt-delete
--    behavior (mentions cascade, gaps set-null).
-- =============================================================================
SELECT '=== I. content gaps + mentions + prompt-delete behavior ===' AS step;

-- gap f1 already links related_prompt_id=e1 (created in B7); confirm it.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_ai_content_gaps
   WHERE id='99999999-0000-0000-0000-0000000000f1' AND related_prompt_id='99999999-0000-0000-0000-0000000000e1';
  IF n=1 THEN RAISE NOTICE 'PASS: content gap linked to prompt e1'; ELSE RAISE EXCEPTION 'FAIL: gap-prompt link=%', n; END IF;
END $$;

-- mention CHECK rejections.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_ai_mentions (workspace_id, website_id, website_url, mention_type, entity_name)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','rival','X');
    RAISE EXCEPTION 'FAIL: invalid mention_type accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid mention_type rejected (%)', SQLERRM;
  END;
  BEGIN
    INSERT INTO public.seo_ai_mentions (workspace_id, website_id, website_url, mention_type, entity_name, source)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','brand','X','crystal_ball');
    RAISE EXCEPTION 'FAIL: invalid mention source accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid mention source rejected (%)', SQLERRM;
  END;
  BEGIN
    INSERT INTO public.seo_ai_mentions (workspace_id, website_id, website_url, mention_type, entity_name, sentiment)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','brand','X','ecstatic');
    RAISE EXCEPTION 'FAIL: invalid sentiment accepted';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: invalid sentiment rejected (%)', SQLERRM;
  END;
END $$;

-- prompt-delete behavior: mentions CASCADE, gaps SET NULL.
INSERT INTO public.seo_ai_prompt_tracking (id, workspace_id, website_id, website_url, prompt_text, topic)
VALUES ('99999999-0000-0000-0000-0000000000e9','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example','delete-me prompt','t')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_ai_mentions (id, workspace_id, website_id, website_url, prompt_tracking_id, mention_type, entity_name)
VALUES ('99999999-0000-0000-0000-00000000000e','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
        '99999999-0000-0000-0000-0000000000e9','brand','DeleteLinked')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_ai_content_gaps
  (id, workspace_id, website_id, website_url, related_prompt_id, topic, missing_answer_angle,
   suggested_content_type, related_keyword_or_question, recommended_next_action)
VALUES ('99999999-0000-0000-0000-0000000000f9','99999999-0000-0000-0000-000000000001',
        '99999999-0000-0000-0000-0000000000b1','https://stage6-smoke-ws1.example',
        '99999999-0000-0000-0000-0000000000e9','t','a','type','q','act')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE n_men int; n_gap int; v_link uuid;
BEGIN
  DELETE FROM public.seo_ai_prompt_tracking WHERE id='99999999-0000-0000-0000-0000000000e9';
  SELECT count(*) INTO n_men FROM public.seo_ai_mentions WHERE id='99999999-0000-0000-0000-00000000000e';
  SELECT count(*) INTO n_gap FROM public.seo_ai_content_gaps WHERE id='99999999-0000-0000-0000-0000000000f9';
  SELECT related_prompt_id INTO v_link FROM public.seo_ai_content_gaps WHERE id='99999999-0000-0000-0000-0000000000f9';
  IF n_men=0 AND n_gap=1 AND v_link IS NULL THEN
    RAISE NOTICE 'PASS: deleting prompt cascaded its mention and set the gap link NULL (gap survives)';
  ELSE
    RAISE EXCEPTION 'FAIL: prompt-delete behavior mention=% gap=% gap_link=% (expected 0/1/NULL)', n_men, n_gap, v_link;
  END IF;
END $$;

-- =============================================================================
-- J. APPEND-ONLY ACTIVITY — manager INSERT allowed; client INSERT denied;
--    UPDATE/DELETE blocked for everyone (no policy); RPC-created rows persist.
-- =============================================================================
SELECT '=== J. append-only activity ===' AS step;

-- J1: manager (team) can INSERT an activity row (subject opportunity a2).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.team_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n int;
  BEGIN
    INSERT INTO public.seo_authority_activity
      (workspace_id, website_id, website_url, subject_type, opportunity_id, activity_type, note)
    VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
            'https://stage6-smoke-ws1.example','opportunity','99999999-0000-0000-0000-0000000000a2','manual_note','team note');
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n=1 THEN RAISE NOTICE 'PASS: manager inserted an activity row'; ELSE RAISE EXCEPTION 'FAIL: manager activity insert rows=%', n; END IF;
  END $$;
ROLLBACK;  -- keep committed activity limited to the RPC-generated rows

-- J2: client cannot INSERT activity.
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.client_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  BEGIN
    BEGIN
      INSERT INTO public.seo_authority_activity
        (workspace_id, website_id, website_url, subject_type, opportunity_id, activity_type)
      VALUES ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-0000000000b1',
              'https://stage6-smoke-ws1.example','opportunity','99999999-0000-0000-0000-0000000000a2','client_note');
      RAISE EXCEPTION 'FAIL: client inserted an activity row';
    EXCEPTION WHEN others THEN
      IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: client blocked from inserting activity (%)', SQLERRM;
    END;
  END $$;
ROLLBACK;

-- J3: activity is immutable — UPDATE and DELETE blocked for a manager (no policy -> 0 rows).
BEGIN;
  SELECT public._seo6_login(current_setting('seo6.admin_id')::uuid);
  SET LOCAL ROLE authenticated;
  DO $$
  DECLARE n_upd int; n_del int;
  BEGIN
    UPDATE public.seo_authority_activity SET note='tampered'
      WHERE opportunity_id='99999999-0000-0000-0000-0000000000a1';
    GET DIAGNOSTICS n_upd = ROW_COUNT;
    DELETE FROM public.seo_authority_activity
      WHERE opportunity_id='99999999-0000-0000-0000-0000000000a1';
    GET DIAGNOSTICS n_del = ROW_COUNT;
    IF n_upd=0 AND n_del=0 THEN RAISE NOTICE 'PASS: activity UPDATE/DELETE blocked (append-only, 0/0 rows)';
    ELSE RAISE EXCEPTION 'FAIL: activity update=% delete=% (expected 0/0)', n_upd, n_del; END IF;
  END $$;
ROLLBACK;

-- J4: RPC-created activity persists (a1 still has its 4 rows).
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_authority_activity WHERE opportunity_id='99999999-0000-0000-0000-0000000000a1';
  IF n=4 THEN RAISE NOTICE 'PASS: RPC-created activity rows persist (4)';
  ELSE RAISE EXCEPTION 'FAIL: RPC activity persistence=% (expected 4)', n; END IF;
END $$;

-- =============================================================================
-- K. FINAL END-STATE RE-ASSERTION (loud even when NOTICEs are swallowed), then
--    teardown, then the success banner.
-- =============================================================================
SELECT '=== K. final end-state assertion ===' AS step;

DO $final$
DECLARE
  v_a1_status text; v_a3_status text; v_c1_status text;
  n_junc int; n_prompts int;
BEGIN
  SELECT status INTO v_a1_status FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a1';
  SELECT status INTO v_a3_status FROM public.seo_authority_opportunities WHERE id='99999999-0000-0000-0000-0000000000a3';
  SELECT approval_status INTO v_c1_status FROM public.seo_authority_campaigns WHERE id='99999999-0000-0000-0000-0000000000c1';
  SELECT count(*) INTO n_junc FROM public.seo_authority_campaign_opportunities WHERE campaign_id='99999999-0000-0000-0000-0000000000c1';
  SELECT count(*) INTO n_prompts FROM public.seo_ai_prompt_tracking
    WHERE workspace_id='99999999-0000-0000-0000-000000000001' AND prompt_text='best seo agency for local business';
  IF v_a1_status='completed' AND v_a3_status='rejected' AND v_c1_status='approved' AND n_junc=1 AND n_prompts=2 THEN
    RAISE NOTICE 'PASS: end-state a1=completed a3=rejected c1=approved junc(c1)=1 timeseries=2';
  ELSE
    RAISE EXCEPTION 'FAIL: end-state a1=% a3=% c1=% junc=% timeseries=% (expected completed/rejected/approved/1/2)',
      v_a1_status, v_a3_status, v_c1_status, n_junc, n_prompts;
  END IF;
END $final$;

-- ---------- TEARDOWN — remove ONLY this smoke test's own rows ----------------
-- Deleting the two workspaces cascades to their websites and every Stage 6 child
-- row created above, leaving the Stage 6 tables clean (as before this run).
-- Helper auth users + their module_access grants are intentionally KEPT (shared
-- test infrastructure, project convention).
-- Committed explicitly so the cleanup is durable regardless of how the runner
-- frames the trailing statements.
BEGIN;
  DELETE FROM public.seo_workspaces WHERE id IN (
    '99999999-0000-0000-0000-000000000001',
    '99999999-0000-0000-0000-000000000002');
  DROP FUNCTION IF EXISTS public._seo6_login(uuid);
COMMIT;

-- Post-teardown sanity: zero Stage 6 rows remain for the smoke-test workspaces.
DO $post$
DECLARE n int;
BEGIN
  SELECT
    (SELECT count(*) FROM public.seo_authority_opportunities WHERE workspace_id IN
       ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000002'))
  + (SELECT count(*) FROM public.seo_authority_campaigns WHERE workspace_id IN
       ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000002'))
  + (SELECT count(*) FROM public.seo_ai_prompt_tracking WHERE workspace_id IN
       ('99999999-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000002'))
  INTO n;
  IF n=0 THEN RAISE NOTICE 'PASS: teardown removed all smoke-test Stage 6 rows (0 remain)';
  ELSE RAISE EXCEPTION 'FAIL: % smoke-test Stage 6 rows remain after teardown', n; END IF;
END $post$;

SELECT 'STAGE 6 OFF-PAGE + AI VISIBILITY SMOKE TEST PASSED' AS result;

-- =============================================================================
-- Re-runnable: the PRE-CLEAN at the top + this teardown make the script safe to
-- run repeatedly. It leaves behind only the shared helper auth users and their
-- user_module_access grants (project convention). Nothing else persists.
-- =============================================================================
