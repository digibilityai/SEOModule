-- =============================================================================
-- SEO Stage 6 (Phase 15E) — seo_authority_campaign_transition RPC — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on the disposable Supabase TEST project (Digi_SEO_Test,
-- ref snyzotgwwfomgafrsvfm), AFTER Stage 1-6 migrations are applied. This
-- script does NOT create or alter the RPC — it exercises the existing,
-- already-applied seo_authority_campaign_transition (migration
-- 20260711120020). It changes NO migration, seed, RLS, or frontend code.
--
-- Proves the campaign approval state machine's transition RPC:
--   1.  Draft -> Pending Approval (submit_for_approval): owner/admin/team OK;
--       client + non-member rejected; activity row correct (subject_type,
--       activity_type, from/to, actor_role_snapshot).
--   2.  Pending Approval -> Approved (approve): owner/admin OK; team_member,
--       client, non-member rejected; activity row correct.
--   3.  Pending Approval -> Rejected (reject): owner/admin OK; team_member,
--       client, non-member rejected; activity row correct.
--   4.  Rejected -> Draft (return_to_draft): owner/admin/team OK; client +
--       non-member rejected; activity row correct.
--   5.  Pending Approval -> Draft (return_to_draft, the RPC's other legal
--       from-status): owner/admin/team OK; client + non-member rejected.
--   6.  Illegal transitions rejected (submit from pending_approval; approve
--       from draft; reject from draft; approve from rejected; reject from
--       approved; return_to_draft from approved; unknown action; missing
--       campaign id; plus terminal/unsupported: submit/approve from approved).
--   7.  Data integrity: after a successful transition, workspace_id/website_id/
--       junction links/tasks are unchanged, and exactly one activity row was
--       written (no duplicate).
--   8.  Append-only activity: a direct UPDATE/DELETE of seo_authority_activity
--       is denied under RLS; successful RPC calls still append.
--   9.  Cleanup: every disposable a8000000- row is removed (cascade), helpers
--       dropped, zero rows remain across all affected Stage 6 tables.
--
-- EXECUTION MODEL (same as the campaign-create verification): the
-- `supabase db query --linked -f` runner wraps the WHOLE file in ONE
-- transaction, so this script uses NO explicit BEGIN/COMMIT/ROLLBACK (an inner
-- ROLLBACK would discard the shared setup). Everything runs as the `postgres`
-- connection role; the acting SEO user is switched per test via jwt claims
-- (set_config). This is faithful because the RPC's authorization is driven by
-- auth.uid() (the jwt sub), NOT by the current DB role. Scenario 8 (activity
-- append-only) additionally switches to the `authenticated` role IN-BLOCK so
-- RLS is genuinely enforced for the direct UPDATE/DELETE attempts. The
-- complementary fact that RPC EXECUTE is granted to `authenticated` is a
-- structural grant (migration 20's GRANT), not re-proven here. No service-role
-- key is used. Each transition test sets the campaign's from-status directly
-- (privileged test setup) before invoking the RPC, so tests are order-
-- independent. The final teardown DELETEs every a8000000- row.
--
-- PREREQUISITE — the five shared TEST auth users must already exist (they do on
-- Digi_SEO_Test): seo-owner/admin/team/client/nonmember-test@example.com.
-- =============================================================================

-- ---------- 0. TEST USER UUIDS + jwt-claims login helper ---------------------
SELECT set_config('seo8.owner_id',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seo8.admin_id',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('seo8.team_id',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('seo8.client_id',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('seo8.nonmember_id', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

DO $guard$
DECLARE
  v_pat text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_keys text[] := ARRAY['owner_id','admin_id','team_id','client_id','nonmember_id'];
  v_k text; v_v text;
BEGIN
  FOREACH v_k IN ARRAY v_keys LOOP
    v_v := current_setting('seo8.' || v_k, true);
    IF v_v IS NULL OR v_v !~ v_pat THEN
      RAISE EXCEPTION 'seo8.% ("%") is not a valid auth.users UUID.', v_k, v_v;
    END IF;
  END LOOP;
END $guard$;

-- Refuse to run unless the target RPC actually exists (avoids a confusing
-- "function does not exist" mid-run).
DO $rpc_guard$
BEGIN
  IF to_regprocedure('public.seo_authority_campaign_transition(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'seo_authority_campaign_transition RPC not found — apply Stage 6 migration 20260711120020 first.';
  END IF;
END $rpc_guard$;

-- Sets the jwt sub so the RPC's auth.uid()/role check evaluates for p_uid.
CREATE OR REPLACE FUNCTION public._seo8_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $fn$;

-- Privileged test setup: force a campaign's from-status before a test (this is
-- setup, NOT the behavior under test — the RPC is the only thing being verified).
CREATE OR REPLACE FUNCTION public._seo8_set_status(p_camp uuid, p_status text)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  UPDATE public.seo_authority_campaigns SET approval_status = p_status WHERE id = p_camp;
END $fn$;

-- Assert a transition SUCCEEDS with the expected target status + activity row.
-- Finds the single newly-inserted activity row via an id-delta (now() is
-- constant within one transaction, so time ordering can't disambiguate).
CREATE OR REPLACE FUNCTION public._seo8_assert_ok(
  p_camp uuid, p_action text, p_exp_from text, p_exp_to text, p_exp_role text, p_label text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_prior uuid[];
  v_ret text;
  v_status text;
  v_new_count int;
  a public.seo_authority_activity%ROWTYPE;
BEGIN
  SELECT array_agg(id) INTO v_prior FROM public.seo_authority_activity WHERE campaign_id = p_camp;

  v_ret := public.seo_authority_campaign_transition(p_camp, p_action, 'note-' || p_label);

  IF v_ret <> p_exp_to THEN
    RAISE EXCEPTION 'FAIL %: RPC returned "%" (expected "%")', p_label, v_ret, p_exp_to;
  END IF;

  SELECT approval_status INTO v_status FROM public.seo_authority_campaigns WHERE id = p_camp;
  IF v_status <> p_exp_to THEN
    RAISE EXCEPTION 'FAIL %: campaign status "%" (expected "%")', p_label, v_status, p_exp_to;
  END IF;

  SELECT count(*) INTO v_new_count FROM public.seo_authority_activity
    WHERE campaign_id = p_camp AND NOT (id = ANY(COALESCE(v_prior, '{}'::uuid[])));
  IF v_new_count <> 1 THEN
    RAISE EXCEPTION 'FAIL %: % new activity rows (expected exactly 1 — no duplicates)', p_label, v_new_count;
  END IF;

  SELECT * INTO a FROM public.seo_authority_activity
    WHERE campaign_id = p_camp AND NOT (id = ANY(COALESCE(v_prior, '{}'::uuid[])));

  IF a.subject_type <> 'campaign' THEN RAISE EXCEPTION 'FAIL %: subject_type "%"', p_label, a.subject_type; END IF;
  IF a.activity_type <> p_action THEN RAISE EXCEPTION 'FAIL %: activity_type "%" (expected "%")', p_label, a.activity_type, p_action; END IF;
  IF a.from_status <> p_exp_from THEN RAISE EXCEPTION 'FAIL %: from_status "%" (expected "%")', p_label, a.from_status, p_exp_from; END IF;
  IF a.to_status <> p_exp_to THEN RAISE EXCEPTION 'FAIL %: to_status "%" (expected "%")', p_label, a.to_status, p_exp_to; END IF;
  IF a.actor_role_snapshot <> p_exp_role THEN RAISE EXCEPTION 'FAIL %: actor_role_snapshot "%" (expected "%")', p_label, a.actor_role_snapshot, p_exp_role; END IF;
  IF a.opportunity_id IS NOT NULL THEN RAISE EXCEPTION 'FAIL %: opportunity_id must be NULL on campaign activity', p_label; END IF;
  IF a.campaign_id <> p_camp THEN RAISE EXCEPTION 'FAIL %: campaign_id mismatch', p_label; END IF;

  RAISE NOTICE 'PASS %: % as % (% -> %); one activity row, actor_role_snapshot=%', p_label, p_action, p_exp_role, p_exp_from, p_exp_to, a.actor_role_snapshot;
END $fn$;

-- Assert a transition is REJECTED (RPC raises) AND leaves no side effects:
-- campaign status unchanged, no activity row appended.
CREATE OR REPLACE FUNCTION public._seo8_assert_denied(p_camp uuid, p_action text, p_label text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_status_before text; v_status_after text;
  v_cnt_before int; v_cnt_after int;
  v_raised boolean := false;
BEGIN
  SELECT approval_status INTO v_status_before FROM public.seo_authority_campaigns WHERE id = p_camp;
  SELECT count(*) INTO v_cnt_before FROM public.seo_authority_activity WHERE campaign_id = p_camp;

  BEGIN
    PERFORM public.seo_authority_campaign_transition(p_camp, p_action, 'note-' || p_label);
  EXCEPTION WHEN others THEN v_raised := true;
  END;

  IF NOT v_raised THEN RAISE EXCEPTION 'FAIL %: transition "%" was NOT rejected', p_label, p_action; END IF;

  SELECT approval_status INTO v_status_after FROM public.seo_authority_campaigns WHERE id = p_camp;
  SELECT count(*) INTO v_cnt_after FROM public.seo_authority_activity WHERE campaign_id = p_camp;

  IF v_status_after IS DISTINCT FROM v_status_before THEN
    RAISE EXCEPTION 'FAIL %: status changed on a rejected transition (% -> %)', p_label, v_status_before, v_status_after;
  END IF;
  IF v_cnt_after <> v_cnt_before THEN
    RAISE EXCEPTION 'FAIL %: activity row written on a rejected transition', p_label;
  END IF;

  RAISE NOTICE 'PASS %: % rejected (no status change, no activity)', p_label, p_action;
END $fn$;

-- ---------- PRE-CLEAN leftovers from a prior run ----------------------------
DELETE FROM public.seo_workspaces WHERE id = 'a8000000-0000-0000-0000-000000000001';

-- =============================================================================
-- A. SETUP — one workspace (owner auto-added as an 'owner' member by the Stage
--    1 trigger — do NOT insert that member row), admin/team/client members,
--    one website, two opportunities, one campaign (CAMP1) with 2 junction links
--    + 2 tasks. Seeded as postgres (RLS bypassed for setup).
-- =============================================================================
INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seo8.' || k)::uuid, 'seo', true
FROM (VALUES ('owner_id'),('admin_id'),('team_id'),('client_id'),('nonmember_id')) v(k)
ON CONFLICT (user_id, module_name) DO NOTHING;

INSERT INTO public.seo_workspaces (id, name, owner_user_id) VALUES
  ('a8000000-0000-0000-0000-000000000001', 'P15E Campaign-Transition Verify WS', current_setting('seo8.owner_id')::uuid);

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status) VALUES
  ('a8000000-0000-0000-0000-000000000001', current_setting('seo8.admin_id')::uuid,  'admin',       'active'),
  ('a8000000-0000-0000-0000-000000000001', current_setting('seo8.team_id')::uuid,   'team_member', 'active'),
  ('a8000000-0000-0000-0000-000000000001', current_setting('seo8.client_id')::uuid, 'client',      'active');

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name) VALUES
  ('a8000000-0000-0000-0000-0000000000b1', 'a8000000-0000-0000-0000-000000000001',
   'https://p15e-verify.example', 'P15E Verify Site', 'P15E Verify Co');

INSERT INTO public.seo_authority_opportunities
  (id, workspace_id, website_id, website_url, opportunity_type, title, source_platform,
   suggested_action, why_it_matters)
VALUES
  ('a8000000-0000-0000-0000-0000000000a1', 'a8000000-0000-0000-0000-000000000001',
   'a8000000-0000-0000-0000-0000000000b1', 'https://p15e-verify.example',
   'backlink', 'Opportunity A1', 'blogA.example', 'Pitch a guest article', 'Builds authority'),
  ('a8000000-0000-0000-0000-0000000000a2', 'a8000000-0000-0000-0000-000000000001',
   'a8000000-0000-0000-0000-0000000000b1', 'https://p15e-verify.example',
   'citation', 'Opportunity A2', 'dirB.example', 'Add a NAP citation', 'Improves local trust');

INSERT INTO public.seo_authority_campaigns
  (id, workspace_id, website_id, website_url, name, goal, approval_status) VALUES
  ('a8000000-0000-0000-0000-0000000000c1', 'a8000000-0000-0000-0000-000000000001',
   'a8000000-0000-0000-0000-0000000000b1', 'https://p15e-verify.example',
   'P15E Transition Campaign', 'Exercise the campaign transition RPC', 'draft');

INSERT INTO public.seo_authority_campaign_opportunities
  (workspace_id, website_id, website_url, campaign_id, opportunity_id) VALUES
  ('a8000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-0000000000b1', 'https://p15e-verify.example',
   'a8000000-0000-0000-0000-0000000000c1', 'a8000000-0000-0000-0000-0000000000a1'),
  ('a8000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-0000000000b1', 'https://p15e-verify.example',
   'a8000000-0000-0000-0000-0000000000c1', 'a8000000-0000-0000-0000-0000000000a2');

INSERT INTO public.seo_authority_campaign_tasks
  (id, workspace_id, website_id, website_url, campaign_id, opportunity_id, label, is_complete, position) VALUES
  ('a8000000-0000-0000-0000-0000000000d1', 'a8000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-0000000000b1',
   'https://p15e-verify.example', 'a8000000-0000-0000-0000-0000000000c1', 'a8000000-0000-0000-0000-0000000000a1',
   'Pitch a guest article', true, 0),
  ('a8000000-0000-0000-0000-0000000000d2', 'a8000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-0000000000b1',
   'https://p15e-verify.example', 'a8000000-0000-0000-0000-0000000000c1', 'a8000000-0000-0000-0000-0000000000a2',
   'Add a NAP citation', false, 1);

-- Confirm the owner IS an active 'owner' member (Stage 1 trigger) so the
-- actor_role_snapshot='owner' assertions below are valid.
DO $owner_guard$
DECLARE v_role text;
BEGIN
  SELECT seo_role INTO v_role FROM public.seo_workspace_members
    WHERE workspace_id = 'a8000000-0000-0000-0000-000000000001'
      AND user_id = current_setting('seo8.owner_id')::uuid AND status = 'active';
  IF v_role IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'SETUP FAIL: workspace owner is not an active owner member (seo_role=%)', v_role;
  END IF;
END $owner_guard$;

-- Shorthand: the disposable campaign + a never-inserted "missing" id.
--   CAMP  = a8000000-...-0000000000c1
--   GHOST = a8000000-...-0000000000ff

-- =============================================================================
-- 1. Draft -> Pending Approval (submit_for_approval) — base check (o/a/team).
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', 'draft', 'pending_approval', 'owner', '1-owner');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.admin_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', 'draft', 'pending_approval', 'admin', '1-admin');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.team_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', 'draft', 'pending_approval', 'team_member', '1-team');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.client_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', '1-client');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.nonmember_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', '1-nonmember');

-- =============================================================================
-- 2. Pending Approval -> Approved (approve) — owner/admin only.
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'approve', 'pending_approval', 'approved', 'owner', '2-owner');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.admin_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'approve', 'pending_approval', 'approved', 'admin', '2-admin');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.team_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'approve', '2-team');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.client_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'approve', '2-client');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.nonmember_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'approve', '2-nonmember');

-- =============================================================================
-- 3. Pending Approval -> Rejected (reject) — owner/admin only.
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'reject', 'pending_approval', 'rejected', 'owner', '3-owner');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.admin_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'reject', 'pending_approval', 'rejected', 'admin', '3-admin');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.team_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'reject', '3-team');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.client_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'reject', '3-client');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.nonmember_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'reject', '3-nonmember');

-- =============================================================================
-- 4. Rejected -> Draft (return_to_draft) — base check (o/a/team).
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'rejected');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', 'rejected', 'draft', 'owner', '4-owner');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'rejected');
SELECT public._seo8_login(current_setting('seo8.admin_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', 'rejected', 'draft', 'admin', '4-admin');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'rejected');
SELECT public._seo8_login(current_setting('seo8.team_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', 'rejected', 'draft', 'team_member', '4-team');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'rejected');
SELECT public._seo8_login(current_setting('seo8.client_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', '4-client');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'rejected');
SELECT public._seo8_login(current_setting('seo8.nonmember_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', '4-nonmember');

-- =============================================================================
-- 5. Pending Approval -> Draft (return_to_draft, the RPC's other legal from).
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', 'pending_approval', 'draft', 'owner', '5-owner');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.admin_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', 'pending_approval', 'draft', 'admin', '5-admin');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.team_id')::uuid);
SELECT public._seo8_assert_ok('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', 'pending_approval', 'draft', 'team_member', '5-team');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.client_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', '5-client');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_login(current_setting('seo8.nonmember_id')::uuid);
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', '5-nonmember');

-- =============================================================================
-- 6. Illegal / unsupported transitions — rejected. Acting as owner so the
--    STATUS guard (not the role guard) is what rejects (except the last two
--    which are structural). No activity row, no status change on any of them.
-- =============================================================================
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'pending_approval');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', '6-submit-from-pending');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'approve', '6-approve-from-draft');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'reject', '6-reject-from-draft');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'rejected');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'approve', '6-approve-from-rejected');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'approved');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'reject', '6-reject-from-approved');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'approved');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'return_to_draft', '6-return-from-approved');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'approved');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', '6-submit-from-approved');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'approved');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'approve', '6-approve-from-approved');

SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000c1', 'frobnicate', '6-unknown-action');

-- Missing campaign id (GHOST never inserted). Status independent.
SELECT public._seo8_assert_denied('a8000000-0000-0000-0000-0000000000ff', 'submit_for_approval', '6-missing-campaign');

-- =============================================================================
-- 7. Data integrity — a successful transition must not touch workspace_id,
--    website_id, junction links, or tasks, and must write exactly one activity
--    row (no duplicate — already covered by _seo8_assert_ok, re-checked here
--    around a fresh transition together with the child-row invariants).
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
DO $s7$
DECLARE
  v_ws_b uuid; v_web_b uuid; v_junc_b text; v_task_b text; v_act_b int;
  v_ws_a uuid; v_web_a uuid; v_junc_a text; v_task_a text; v_act_a int;
BEGIN
  SELECT workspace_id, website_id INTO v_ws_b, v_web_b FROM public.seo_authority_campaigns WHERE id = 'a8000000-0000-0000-0000-0000000000c1';
  SELECT string_agg(opportunity_id::text, ',' ORDER BY opportunity_id::text) INTO v_junc_b
    FROM public.seo_authority_campaign_opportunities WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';
  SELECT string_agg(label || ':' || is_complete::text, ',' ORDER BY position) INTO v_task_b
    FROM public.seo_authority_campaign_tasks WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';
  SELECT count(*) INTO v_act_b FROM public.seo_authority_activity WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';

  PERFORM public.seo_authority_campaign_transition('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', 'integrity');

  SELECT workspace_id, website_id INTO v_ws_a, v_web_a FROM public.seo_authority_campaigns WHERE id = 'a8000000-0000-0000-0000-0000000000c1';
  SELECT string_agg(opportunity_id::text, ',' ORDER BY opportunity_id::text) INTO v_junc_a
    FROM public.seo_authority_campaign_opportunities WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';
  SELECT string_agg(label || ':' || is_complete::text, ',' ORDER BY position) INTO v_task_a
    FROM public.seo_authority_campaign_tasks WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';
  SELECT count(*) INTO v_act_a FROM public.seo_authority_activity WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';

  IF v_ws_a <> v_ws_b OR v_web_a <> v_web_b THEN RAISE EXCEPTION 'FAIL 7: workspace/website changed by transition'; END IF;
  IF v_junc_a IS DISTINCT FROM v_junc_b THEN RAISE EXCEPTION 'FAIL 7: junction links changed ("%" -> "%")', v_junc_b, v_junc_a; END IF;
  IF v_task_a IS DISTINCT FROM v_task_b THEN RAISE EXCEPTION 'FAIL 7: tasks changed ("%" -> "%")', v_task_b, v_task_a; END IF;
  IF v_act_a <> v_act_b + 1 THEN RAISE EXCEPTION 'FAIL 7: expected exactly one new activity row (% -> %)', v_act_b, v_act_a; END IF;

  RAISE NOTICE 'PASS 7: workspace/website/junction/tasks unchanged; exactly one activity row added';
END $s7$;

-- =============================================================================
-- 8. Append-only activity — a direct UPDATE/DELETE of seo_authority_activity
--    is denied under RLS (no UPDATE/DELETE policy exists for anyone). Runs the
--    tamper attempts as the `authenticated` role IN-BLOCK so RLS is enforced,
--    then verifies (as postgres) nothing changed. Successful RPC appends are
--    already proven by scenarios 1-5.
-- =============================================================================
SELECT public._seo8_set_status('a8000000-0000-0000-0000-0000000000c1', 'draft');
SELECT public._seo8_login(current_setting('seo8.owner_id')::uuid);
SELECT public.seo_authority_campaign_transition('a8000000-0000-0000-0000-0000000000c1', 'submit_for_approval', 'append-seed');
DO $s8$
DECLARE v_upd int := -1; v_del int := -1; v_tampered int; v_cnt int;
BEGIN
  -- act as `authenticated` (RLS enforced) for the tamper attempts.
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    UPDATE public.seo_authority_activity SET note = 'TAMPERED-8' WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS v_upd = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN v_upd := 0;   -- a hard grant-level deny is also "0 effective"
  END;
  BEGIN
    DELETE FROM public.seo_authority_activity WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';
    GET DIAGNOSTICS v_del = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN v_del := 0;
  END;
  -- back to the privileged role to verify no damage.
  PERFORM set_config('role', 'postgres', true);
  SELECT count(*) INTO v_tampered FROM public.seo_authority_activity
    WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1' AND note = 'TAMPERED-8';
  SELECT count(*) INTO v_cnt FROM public.seo_authority_activity
    WHERE campaign_id = 'a8000000-0000-0000-0000-0000000000c1';

  IF v_upd <> 0 THEN RAISE EXCEPTION 'FAIL 8: activity UPDATE affected % rows (append-only violated)', v_upd; END IF;
  IF v_del <> 0 THEN RAISE EXCEPTION 'FAIL 8: activity DELETE affected % rows (append-only violated)', v_del; END IF;
  IF v_tampered <> 0 THEN RAISE EXCEPTION 'FAIL 8: % tampered activity rows found', v_tampered; END IF;
  IF v_cnt = 0 THEN RAISE EXCEPTION 'FAIL 8: activity rows unexpectedly removed'; END IF;

  RAISE NOTICE 'PASS 8: append-only enforced (UPDATE=% / DELETE=% rows affected); % rows intact', v_upd, v_del, v_cnt;
END $s8$;

-- =============================================================================
-- 9. TEARDOWN — delete the disposable workspace (cascades to website /
--    opportunities / campaigns / tasks / junctions / activity), drop helpers,
--    and assert zero disposable rows remain across all affected Stage 6 tables.
-- =============================================================================
DELETE FROM public.seo_workspaces WHERE id = 'a8000000-0000-0000-0000-000000000001';

DROP FUNCTION IF EXISTS public._seo8_assert_ok(uuid, text, text, text, text, text);
DROP FUNCTION IF EXISTS public._seo8_assert_denied(uuid, text, text);
DROP FUNCTION IF EXISTS public._seo8_set_status(uuid, text);
DROP FUNCTION IF EXISTS public._seo8_login(uuid);

DO $done$
DECLARE
  v_ws int; v_web int; v_opp int; v_camp int; v_task int; v_junc int; v_act int;
BEGIN
  SELECT count(*) INTO v_ws   FROM public.seo_workspaces                     WHERE id::text          LIKE 'a8000000-%';
  SELECT count(*) INTO v_web  FROM public.seo_websites                       WHERE id::text          LIKE 'a8000000-%';
  SELECT count(*) INTO v_opp  FROM public.seo_authority_opportunities        WHERE workspace_id::text LIKE 'a8000000-%';
  SELECT count(*) INTO v_camp FROM public.seo_authority_campaigns            WHERE workspace_id::text LIKE 'a8000000-%';
  SELECT count(*) INTO v_task FROM public.seo_authority_campaign_tasks       WHERE workspace_id::text LIKE 'a8000000-%';
  SELECT count(*) INTO v_junc FROM public.seo_authority_campaign_opportunities WHERE workspace_id::text LIKE 'a8000000-%';
  SELECT count(*) INTO v_act  FROM public.seo_authority_activity             WHERE workspace_id::text LIKE 'a8000000-%';
  IF v_ws + v_web + v_opp + v_camp + v_task + v_junc + v_act <> 0 THEN
    RAISE EXCEPTION 'FAIL 9: leftover disposable rows ws=% web=% opp=% camp=% task=% junc=% act=%',
      v_ws, v_web, v_opp, v_camp, v_task, v_junc, v_act;
  END IF;
  RAISE NOTICE 'PASS 9: all disposable rows removed (cascade); zero leftover across all Stage 6 tables';
END $done$;

SELECT 'ALL PASS — seo_authority_campaign_transition verification complete' AS result;
