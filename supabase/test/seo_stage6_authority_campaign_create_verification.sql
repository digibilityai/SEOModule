-- =============================================================================
-- SEO Stage 6 (Phase 15D) — seo_authority_campaign_create RPC — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on the disposable Supabase TEST project (Digi_SEO_Test,
-- ref snyzotgwwfomgafrsvfm), AFTER Stage 1-6 migrations AND migration
-- 20260712120024 (the seo_authority_campaign_create RPC) are applied.
--
-- Proves the atomic draft-campaign-creation RPC:
--   1.  owner   can create a draft campaign
--   2.  admin   can create a draft campaign
--   3.  team_member can create a draft campaign
--   4.  client  is rejected
--   5.  non-member is rejected
--   6.  created campaign approval_status = 'draft'
--   7.  correct junction rows are created
--   8.  correct task rows are created (label = opportunity.suggested_action)
--   9.  cross-workspace opportunity input is rejected
--   10. invalid owner input is rejected
--   11. duplicate opportunity ids do NOT create duplicate junction/task rows
--   12. a forced child-write failure leaves ZERO net campaign/junction/task rows
--       (true function-level atomicity — one PL/pgSQL transaction)
--   13. all disposable test rows are cleaned up (teardown at the end)
--
-- EXECUTION MODEL: the `supabase db query --linked -f` runner wraps the WHOLE
-- file in ONE transaction, so this script uses NO explicit BEGIN/COMMIT/
-- ROLLBACK (an inner ROLLBACK would discard the shared setup). Everything runs
-- as the `postgres` connection role in that single transaction; the acting SEO
-- user is switched per test via jwt claims (set_config). This is faithful
-- because the RPC's authorization is driven by auth.uid() (the jwt sub), NOT by
-- the current DB role — a client/non-member jwt makes the in-function role
-- check reject the call exactly as it would for a real authenticated caller.
-- The complementary fact that EXECUTE is granted to `authenticated` only (not
-- anon) is proven separately by the structural grantee check in the migration
-- notes, not re-proven here. No service-role key is used anywhere. The final
-- teardown DELETEs every a7000000- row, so a successful run commits net-nothing;
-- any failed assertion RAISEs and the runner rolls the whole transaction back.
--
-- PREREQUISITE — the five shared TEST auth users must already exist (they do on
-- Digi_SEO_Test): seo-owner/admin/team/client/nonmember-test@example.com.
-- =============================================================================

-- ---------- 0. TEST USER UUIDS + jwt-claims login helper ---------------------
SELECT set_config('seo7.owner_id',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seo7.admin_id',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('seo7.team_id',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('seo7.client_id',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('seo7.nonmember_id', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

DO $guard$
DECLARE
  v_pat text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_keys text[] := ARRAY['owner_id','admin_id','team_id','client_id','nonmember_id'];
  v_k text; v_v text;
BEGIN
  FOREACH v_k IN ARRAY v_keys LOOP
    v_v := current_setting('seo7.' || v_k, true);
    IF v_v IS NULL OR v_v !~ v_pat THEN
      RAISE EXCEPTION 'seo7.% ("%") is not a valid auth.users UUID.', v_k, v_v;
    END IF;
  END LOOP;
END $guard$;

-- Sets the jwt sub so the RPC's auth.uid()/role check evaluates for p_uid.
CREATE OR REPLACE FUNCTION public._seo7_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $fn$;

-- ---------- PRE-CLEAN leftovers (bare; part of the single transaction) -------
DELETE FROM public.seo_workspaces WHERE id IN (
  'a7000000-0000-0000-0000-000000000001',
  'a7000000-0000-0000-0000-000000000002');

-- =============================================================================
-- A. SETUP — two workspaces, members, two websites, opportunities. Owner is
--    auto-added as an 'owner' member by the Stage 1 trigger (do NOT insert it).
-- =============================================================================
INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seo7.' || k)::uuid, 'seo', true
FROM (VALUES ('owner_id'),('admin_id'),('team_id'),('client_id'),('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

INSERT INTO public.seo_workspaces (id, name, owner_user_id) VALUES
  ('a7000000-0000-0000-0000-000000000001', 'P15D Campaign-Create Verify WS1', current_setting('seo7.owner_id')::uuid),
  ('a7000000-0000-0000-0000-000000000002', 'P15D Campaign-Create Verify WS2', current_setting('seo7.owner_id')::uuid);

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status) VALUES
  ('a7000000-0000-0000-0000-000000000001', current_setting('seo7.admin_id')::uuid,  'admin',       'active'),
  ('a7000000-0000-0000-0000-000000000001', current_setting('seo7.team_id')::uuid,   'team_member', 'active'),
  ('a7000000-0000-0000-0000-000000000001', current_setting('seo7.client_id')::uuid, 'client',      'active');

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name) VALUES
  ('a7000000-0000-0000-0000-0000000000b1', 'a7000000-0000-0000-0000-000000000001',
   'https://p15d-verify-ws1.example', 'P15D Verify Site WS1', 'P15D Verify Co WS1'),
  ('a7000000-0000-0000-0000-0000000000b2', 'a7000000-0000-0000-0000-000000000002',
   'https://p15d-verify-ws2.example', 'P15D Verify Site WS2', 'P15D Verify Co WS2');

INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform,
   suggested_action, why_it_matters)
VALUES
  ('a7000000-0000-0000-0000-0000000000a1', 'a7000000-0000-0000-0000-000000000001',
   'a7000000-0000-0000-0000-0000000000b1', 'https://p15d-verify-ws1.example',
   'backlink', 'Guest post on industry blog', 'industryblog.example',
   'Pitch a guest article on their blog', 'Builds topical authority'),
  ('a7000000-0000-0000-0000-0000000000a2', 'a7000000-0000-0000-0000-000000000001',
   'a7000000-0000-0000-0000-0000000000b1', 'https://p15d-verify-ws1.example',
   'citation', 'Local directory listing', 'localdir.example',
   'Add a NAP-consistent local citation', 'Improves local trust'),
  ('a7000000-0000-0000-0000-0000000000a9', 'a7000000-0000-0000-0000-000000000002',
   'a7000000-0000-0000-0000-0000000000b2', 'https://p15d-verify-ws2.example',
   'backlink', 'WS2 opportunity', 'ws2blog.example',
   'WS2 cross-workspace opportunity', 'Should never be linkable from WS1');

-- =============================================================================
-- B. POSITIVE: owner / admin / team_member each create a DRAFT campaign
--    (#1, #2, #3, #6, #7, #8). Assertions are campaign-id-scoped.
-- =============================================================================
DO $b$
DECLARE
  v_id uuid; v_status text; v_owner text; v_njunc int; v_ntask int; v_ncomplete int;
  v_l0 text; v_p0 int; v_l1 text; v_p1 int;
BEGIN
  PERFORM public._seo7_login(current_setting('seo7.owner_id')::uuid);
  v_id := public.seo_authority_campaign_create(
    'a7000000-0000-0000-0000-0000000000b1',
    '  P15D Owner Draft  ', '  Owner goal  ', 'client_action', '2026-09-01',
    ARRAY['a7000000-0000-0000-0000-0000000000a1','a7000000-0000-0000-0000-0000000000a2']::uuid[]);

  SELECT approval_status, owner INTO v_status, v_owner FROM public.seo_authority_campaigns WHERE id = v_id;
  SELECT count(*) INTO v_njunc     FROM public.seo_authority_campaign_opportunities WHERE campaign_id = v_id;
  SELECT count(*) INTO v_ntask     FROM public.seo_authority_campaign_tasks WHERE campaign_id = v_id;
  SELECT count(*) INTO v_ncomplete FROM public.seo_authority_campaign_tasks WHERE campaign_id = v_id AND is_complete;
  SELECT label, position INTO v_l0, v_p0 FROM public.seo_authority_campaign_tasks
    WHERE campaign_id = v_id AND opportunity_id = 'a7000000-0000-0000-0000-0000000000a1';
  SELECT label, position INTO v_l1, v_p1 FROM public.seo_authority_campaign_tasks
    WHERE campaign_id = v_id AND opportunity_id = 'a7000000-0000-0000-0000-0000000000a2';

  IF v_status <> 'draft' THEN RAISE EXCEPTION 'FAIL #6: status=% (expected draft)', v_status; END IF;
  IF v_owner  <> 'client_action' THEN RAISE EXCEPTION 'FAIL: owner=%', v_owner; END IF;
  IF v_njunc  <> 2 THEN RAISE EXCEPTION 'FAIL #7: junction=% (expected 2)', v_njunc; END IF;
  IF v_ntask  <> 2 THEN RAISE EXCEPTION 'FAIL #8: tasks=% (expected 2)', v_ntask; END IF;
  IF v_ncomplete <> 0 THEN RAISE EXCEPTION 'FAIL: % complete tasks (expected 0)', v_ncomplete; END IF;
  IF v_l0 <> 'Pitch a guest article on their blog' OR v_p0 <> 0 THEN RAISE EXCEPTION 'FAIL #8: task0 %/%', v_l0, v_p0; END IF;
  IF v_l1 <> 'Add a NAP-consistent local citation' OR v_p1 <> 1 THEN RAISE EXCEPTION 'FAIL #8: task1 %/%', v_l1, v_p1; END IF;
  RAISE NOTICE 'PASS #1/#6/#7/#8: owner created DRAFT campaign, 2 junction, 2 tasks (labels+positions correct)';

  -- #2 admin, 1 opportunity
  PERFORM public._seo7_login(current_setting('seo7.admin_id')::uuid);
  v_id := public.seo_authority_campaign_create(
    'a7000000-0000-0000-0000-0000000000b1', 'P15D Admin Draft', 'Admin goal', 'digibility_expert', NULL,
    ARRAY['a7000000-0000-0000-0000-0000000000a1']::uuid[]);
  SELECT approval_status INTO v_status FROM public.seo_authority_campaigns WHERE id = v_id;
  SELECT count(*) INTO v_njunc FROM public.seo_authority_campaign_opportunities WHERE campaign_id = v_id;
  SELECT count(*) INTO v_ntask FROM public.seo_authority_campaign_tasks WHERE campaign_id = v_id;
  IF v_status <> 'draft' OR v_njunc <> 1 OR v_ntask <> 1 THEN
    RAISE EXCEPTION 'FAIL #2: admin status=% junc=% task=%', v_status, v_njunc, v_ntask; END IF;
  RAISE NOTICE 'PASS #2: admin created DRAFT campaign (1 junction, 1 task)';

  -- #3 team_member, empty opportunity set
  PERFORM public._seo7_login(current_setting('seo7.team_id')::uuid);
  v_id := public.seo_authority_campaign_create(
    'a7000000-0000-0000-0000-0000000000b1', 'P15D Team Draft', 'Team goal', 'system_suggestion', NULL,
    ARRAY[]::uuid[]);
  SELECT approval_status INTO v_status FROM public.seo_authority_campaigns WHERE id = v_id;
  SELECT count(*) INTO v_njunc FROM public.seo_authority_campaign_opportunities WHERE campaign_id = v_id;
  SELECT count(*) INTO v_ntask FROM public.seo_authority_campaign_tasks WHERE campaign_id = v_id;
  IF v_status <> 'draft' OR v_njunc <> 0 OR v_ntask <> 0 THEN
    RAISE EXCEPTION 'FAIL #3: team status=% junc=% task=%', v_status, v_njunc, v_ntask; END IF;
  RAISE NOTICE 'PASS #3: team_member created DRAFT campaign (empty, 0 junction, 0 task)';
END $b$;

-- =============================================================================
-- C. NEGATIVE: client (#4), non-member (#5), invalid owner (#10),
--    cross-workspace opportunity (#9) — each must RAISE.
-- =============================================================================
DO $c$
DECLARE v_raised boolean;
BEGIN
  -- #4 client rejected
  PERFORM public._seo7_login(current_setting('seo7.client_id')::uuid);
  v_raised := false;
  BEGIN
    PERFORM public.seo_authority_campaign_create(
      'a7000000-0000-0000-0000-0000000000b1', 'c client', 'g', 'client_action', NULL, ARRAY[]::uuid[]);
  EXCEPTION WHEN others THEN v_raised := true; RAISE NOTICE 'PASS #4: client rejected (%)', SQLERRM;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'FAIL #4: client was NOT rejected'; END IF;

  -- #5 non-member rejected
  PERFORM public._seo7_login(current_setting('seo7.nonmember_id')::uuid);
  v_raised := false;
  BEGIN
    PERFORM public.seo_authority_campaign_create(
      'a7000000-0000-0000-0000-0000000000b1', 'c nonmember', 'g', 'client_action', NULL, ARRAY[]::uuid[]);
  EXCEPTION WHEN others THEN v_raised := true; RAISE NOTICE 'PASS #5: non-member rejected (%)', SQLERRM;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'FAIL #5: non-member was NOT rejected'; END IF;

  -- #10 invalid owner rejected (acting as owner so only the owner-value check fires)
  PERFORM public._seo7_login(current_setting('seo7.owner_id')::uuid);
  v_raised := false;
  BEGIN
    PERFORM public.seo_authority_campaign_create(
      'a7000000-0000-0000-0000-0000000000b1', 'c badowner', 'g', 'not_a_real_owner', NULL, ARRAY[]::uuid[]);
  EXCEPTION WHEN others THEN v_raised := true; RAISE NOTICE 'PASS #10: invalid owner rejected (%)', SQLERRM;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'FAIL #10: invalid owner was NOT rejected'; END IF;

  -- #9 cross-workspace opportunity rejected (WS2 opp into a WS1 campaign)
  v_raised := false;
  BEGIN
    PERFORM public.seo_authority_campaign_create(
      'a7000000-0000-0000-0000-0000000000b1', 'c crossws', 'g', 'client_action', NULL,
      ARRAY['a7000000-0000-0000-0000-0000000000a9']::uuid[]);
  EXCEPTION WHEN others THEN v_raised := true; RAISE NOTICE 'PASS #9: cross-workspace opportunity rejected (%)', SQLERRM;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'FAIL #9: cross-workspace opportunity was NOT rejected'; END IF;
END $c$;

-- =============================================================================
-- D. DEDUP (#11): [o1, o1, o2] -> exactly 2 junction + 2 tasks, o1 exactly once.
-- =============================================================================
DO $d$
DECLARE v_id uuid; v_njunc int; v_ntask int; v_o1_junc int; v_o1_task int;
BEGIN
  PERFORM public._seo7_login(current_setting('seo7.owner_id')::uuid);
  v_id := public.seo_authority_campaign_create(
    'a7000000-0000-0000-0000-0000000000b1', 'P15D Dedup', 'Dedup goal', 'client_action', NULL,
    ARRAY['a7000000-0000-0000-0000-0000000000a1',
          'a7000000-0000-0000-0000-0000000000a1',
          'a7000000-0000-0000-0000-0000000000a2']::uuid[]);
  SELECT count(*) INTO v_njunc FROM public.seo_authority_campaign_opportunities WHERE campaign_id = v_id;
  SELECT count(*) INTO v_ntask FROM public.seo_authority_campaign_tasks WHERE campaign_id = v_id;
  SELECT count(*) INTO v_o1_junc FROM public.seo_authority_campaign_opportunities
    WHERE campaign_id = v_id AND opportunity_id = 'a7000000-0000-0000-0000-0000000000a1';
  SELECT count(*) INTO v_o1_task FROM public.seo_authority_campaign_tasks
    WHERE campaign_id = v_id AND opportunity_id = 'a7000000-0000-0000-0000-0000000000a1';
  IF v_njunc <> 2 OR v_ntask <> 2 OR v_o1_junc <> 1 OR v_o1_task <> 1 THEN
    RAISE EXCEPTION 'FAIL #11: junc=% task=% o1_junc=% o1_task=% (expected 2/2/1/1)', v_njunc, v_ntask, v_o1_junc, v_o1_task;
  END IF;
  RAISE NOTICE 'PASS #11: duplicate ids deduped (2 junction, 2 tasks, o1 exactly once)';
END $d$;

-- =============================================================================
-- E. ATOMICITY (#12): a forced failure of the 3rd write (task insert) rolls the
--    WHOLE RPC back. A temporary BEFORE INSERT trigger on the tasks table
--    raises; the RPC fails; a before/after delta over WS1 proves the failed
--    call added ZERO campaign/junction/task rows (net-zero), even though the
--    campaign + junction inserts had already run inside the function.
-- =============================================================================
CREATE OR REPLACE FUNCTION pg_temp._force_task_fail() RETURNS trigger
LANGUAGE plpgsql AS $ff$
BEGIN RAISE EXCEPTION 'forced task-insert failure (atomicity test)'; END $ff$;

CREATE TRIGGER zzz_p15d_force_task_fail
  BEFORE INSERT ON public.seo_authority_campaign_tasks
  FOR EACH ROW EXECUTE FUNCTION pg_temp._force_task_fail();

DO $e$
DECLARE
  v_camp_before int; v_junc_before int; v_task_before int;
  v_camp_after int;  v_junc_after int;  v_task_after int;
  v_raised boolean := false;
BEGIN
  SELECT count(*) INTO v_camp_before FROM public.seo_authority_campaigns              WHERE workspace_id='a7000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_junc_before FROM public.seo_authority_campaign_opportunities WHERE workspace_id='a7000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_task_before FROM public.seo_authority_campaign_tasks         WHERE workspace_id='a7000000-0000-0000-0000-000000000001';

  PERFORM public._seo7_login(current_setting('seo7.owner_id')::uuid);
  BEGIN
    PERFORM public.seo_authority_campaign_create(
      'a7000000-0000-0000-0000-0000000000b1', 'P15D Atomicity Probe', 'g', 'client_action', NULL,
      ARRAY['a7000000-0000-0000-0000-0000000000a1','a7000000-0000-0000-0000-0000000000a2']::uuid[]);
  EXCEPTION WHEN others THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'FAIL #12: RPC did NOT fail despite the forced task-insert failure'; END IF;

  SELECT count(*) INTO v_camp_after FROM public.seo_authority_campaigns              WHERE workspace_id='a7000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_junc_after FROM public.seo_authority_campaign_opportunities WHERE workspace_id='a7000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_task_after FROM public.seo_authority_campaign_tasks         WHERE workspace_id='a7000000-0000-0000-0000-000000000001';

  IF v_camp_after <> v_camp_before OR v_junc_after <> v_junc_before OR v_task_after <> v_task_before THEN
    RAISE EXCEPTION 'FAIL #12: RPC left partial rows — camp %/%, junc %/%, task %/%',
      v_camp_before, v_camp_after, v_junc_before, v_junc_after, v_task_before, v_task_after;
  END IF;
  RAISE NOTICE 'PASS #12: forced child-write failure rolled back the WHOLE RPC (net 0 campaign/junction/task rows added)';
END $e$;

DROP TRIGGER zzz_p15d_force_task_fail ON public.seo_authority_campaign_tasks;

-- =============================================================================
-- F. TEARDOWN (#13) — remove all a7000000- rows (cascades) + the login helper.
-- =============================================================================
DELETE FROM public.seo_workspaces WHERE id IN (
  'a7000000-0000-0000-0000-000000000001',
  'a7000000-0000-0000-0000-000000000002');
DROP FUNCTION IF EXISTS public._seo7_login(uuid);

DO $done$
DECLARE v_ws int; v_camp int;
BEGIN
  SELECT count(*) INTO v_ws   FROM public.seo_workspaces          WHERE id::text LIKE 'a7000000-%';
  SELECT count(*) INTO v_camp FROM public.seo_authority_campaigns WHERE workspace_id::text LIKE 'a7000000-%';
  IF v_ws <> 0 OR v_camp <> 0 THEN RAISE EXCEPTION 'FAIL #13: teardown left ws=% camp=%', v_ws, v_camp; END IF;
  RAISE NOTICE 'PASS #13: all disposable rows cleaned up';
END $done$;

SELECT 'ALL PASS — seo_authority_campaign_create verification complete' AS result;
