-- =============================================================================
-- SEO P1a Step 1 — Domain Ownership Verification DB Contract — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on the disposable Supabase TEST project (Digi_SEO_Test,
-- ref snyzotgwwfomgafrsvfm), AFTER migration
-- 20260716120031_seo_p1a_step1_ownership_verification is applied.
--
-- EXECUTION MODEL (same as the Phase 16C verification): the
-- `supabase db query --linked -f` runner wraps the WHOLE file in ONE
-- transaction, so this script uses NO explicit BEGIN/COMMIT/ROLLBACK. It runs as
-- the `postgres` connection role; the acting SEO user is switched via jwt claims
-- (set_config) so RLS evaluates per user. Direct-write RLS tests additionally
-- `SET LOCAL ROLE authenticated` so row-level policies actually apply (postgres
-- bypasses RLS). All fixtures are tagged (challenge_token prefix 'OWNVERIFY-'
-- and a disposable website af000000-…-099); teardown removes them, so a
-- successful run commits net-nothing. No password/service-role key is used.
--
-- PREREQUISITE: the five shared TEST auth users exist on Digi_SEO_Test
-- (owner/admin/team/client/nonmember) and the UI-seed workspace/website exist.
-- =============================================================================

-- ---------- 0. Fixture ids + jwt-claims login helper -------------------------
SELECT set_config('ov.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('ov.dispsite',  'af000000-0000-0000-0002-000000000099', false);
SELECT set_config('ov.owner',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('ov.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('ov.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('ov.client',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('ov.nonmember', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo_ov_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF p_uid IS NULL THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  ELSE
    PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  END IF;
END $fn$;

-- ---------- 1. STRUCTURE ----------------------------------------------------
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.tables
   WHERE table_schema='public'
     AND table_name IN ('seo_ownership_verifications','seo_ownership_verification_events');
  IF n <> 2 THEN RAISE EXCEPTION 'STRUCT: expected 2 ownership tables, got %', n; END IF;

  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='public'
     AND c.relname IN ('seo_ownership_verifications','seo_ownership_verification_events')
     AND c.relrowsecurity;
  IF n <> 2 THEN RAISE EXCEPTION 'STRUCT: RLS not enabled on both tables (got %)', n; END IF;

  -- integrity trigger function present
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
                 WHERE ns.nspname='public' AND p.proname='seo_ownership_verification_integrity') THEN
    RAISE EXCEPTION 'STRUCT: integrity trigger function missing'; END IF;

  -- unique (website_id, method)
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='seo_ownership_verifications_website_method_uniq') THEN
    RAISE EXCEPTION 'STRUCT: (website_id, method) unique constraint missing'; END IF;

  -- append-only + read-only: EXACTLY ONE (SELECT) policy on each table
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_ownership_verifications';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: seo_ownership_verifications must have exactly 1 (SELECT) policy, got %', n; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_ownership_verification_events';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: seo_ownership_verification_events must have exactly 1 (SELECT) policy, got %', n; END IF;
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname='public'
     AND tablename IN ('seo_ownership_verifications','seo_ownership_verification_events')
     AND cmd <> 'SELECT';
  IF n <> 0 THEN RAISE EXCEPTION 'STRUCT: found % non-SELECT policy(ies) — customer writes must be default-denied', n; END IF;
  RAISE NOTICE 'STRUCT ok';
END $t$;

-- ---------- baseline counts of OTHER modules (isolation proof, req #11) ------
SELECT set_config('ov.base_crawl', (SELECT count(*)::text FROM public.seo_crawl_jobs), false);
SELECT set_config('ov.base_inv',   (SELECT count(*)::text FROM public.seo_page_inventory), false);
SELECT set_config('ov.base_opp',   (SELECT count(*)::text FROM public.seo_authority_opportunities), false);

-- disposable ACTIVE website in the seed workspace to attach fixtures to
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('ov.dispsite')::uuid, current_setting('ov.workspace')::uuid,
        'https://p1a-ownverify.example', 'P1A OwnVerify Disposable', 'P1A OwnVerify', 'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- 2. PRIVILEGED FIXTURE CREATE (req #9) ---------------------------
DO $t$
DECLARE v_ws uuid := current_setting('ov.workspace')::uuid;
        v_site uuid := current_setting('ov.dispsite')::uuid;
        v_owner uuid := current_setting('ov.owner')::uuid;
        v_vid uuid; n int;
BEGIN
  INSERT INTO public.seo_ownership_verifications
    (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, created_by)
  VALUES
    (v_ws, v_site, 'https://p1a-ownverify.example', 'p1a-ownverify.example',
     'dns_txt', 'pending', 'OWNVERIFY-tok-1', v_owner)
  RETURNING id INTO v_vid;
  PERFORM set_config('ov.vid', v_vid::text, false);

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status, actor, actor_user_id, note)
  VALUES
    (v_vid, v_ws, v_site, 'initiated', NULL, 'pending', 'customer', v_owner, 'OWNVERIFY- fixture initiated');

  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid AND status='pending' AND method='dns_txt';
  IF n <> 1 THEN RAISE EXCEPTION 'FIXTURE: verification row not created as pending/dns_txt'; END IF;
  SELECT count(*) INTO n FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF n <> 1 THEN RAISE EXCEPTION 'FIXTURE: expected exactly 1 audit event, got %', n; END IF;
  RAISE NOTICE 'FIXTURE create ok';
END $t$;

-- ---------- 3. CONSTRAINTS: uniqueness + integrity + FK (req #10) ------------
DO $t$
DECLARE v_ws uuid := current_setting('ov.workspace')::uuid;
        v_site uuid := current_setting('ov.dispsite')::uuid; ok boolean;
BEGIN
  -- 3a. duplicate (website_id, method) rejected
  ok := false;
  BEGIN
    INSERT INTO public.seo_ownership_verifications
      (workspace_id, website_id, website_url, verification_host, method, challenge_token)
    VALUES (v_ws, v_site, 'https://p1a-ownverify.example', 'p1a-ownverify.example', 'dns_txt', 'OWNVERIFY-dup');
  EXCEPTION WHEN unique_violation THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CONSTRAINT: duplicate (website_id, method) verification was allowed'; END IF;

  -- 3b. integrity trigger: workspace mismatch rejected
  ok := false;
  BEGIN
    INSERT INTO public.seo_ownership_verifications
      (workspace_id, website_id, website_url, verification_host, method, challenge_token)
    VALUES ('11111111-1111-1111-1111-111111111111'::uuid, v_site,
            'https://p1a-ownverify.example', 'p1a-ownverify.example', 'dns_txt', 'OWNVERIFY-wsmismatch');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CONSTRAINT: workspace/website mismatch was allowed'; END IF;

  -- 3c. FK: non-existent website rejected
  ok := false;
  BEGIN
    INSERT INTO public.seo_ownership_verifications
      (workspace_id, website_id, website_url, verification_host, method, challenge_token)
    VALUES (v_ws, '99999999-0000-0000-0000-0000000000ff'::uuid,
            'https://x.example', 'x.example', 'dns_txt', 'OWNVERIFY-badsite');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CONSTRAINT: verification for a non-existent website was allowed'; END IF;

  -- 3d. bad status / bad method rejected by CHECK
  ok := false;
  BEGIN
    INSERT INTO public.seo_ownership_verifications
      (workspace_id, website_id, website_url, verification_host, method, status, challenge_token)
    VALUES (v_ws, v_site, 'https://p1a-ownverify.example', 'p1a-ownverify.example', 'dns_txt', 'expired', 'OWNVERIFY-badstatus');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CONSTRAINT: unknown status value was allowed (no auto-expiry state must exist)'; END IF;
  RAISE NOTICE 'CONSTRAINT ok';
END $t$;

-- ---------- 4. RLS READ ISOLATION (req #3, #4, #5) --------------------------
SET LOCAL ROLE authenticated;
SELECT public._seo_ov_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner
DO $t$
DECLARE v_vid uuid := current_setting('ov.vid')::uuid; n int;
BEGIN
  -- owner (member) reads verification + its event
  PERFORM public._seo_ov_login(current_setting('ov.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid;
  IF n <> 1 THEN RAISE EXCEPTION 'RLS: owner member cannot read own-workspace verification'; END IF;
  SELECT count(*) INTO n FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF n < 1 THEN RAISE EXCEPTION 'RLS: owner member cannot read verification events'; END IF;

  -- client (member) reads verification (read-only status)
  PERFORM public._seo_ov_login(current_setting('ov.client')::uuid);
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid;
  IF n <> 1 THEN RAISE EXCEPTION 'RLS: client member cannot read verification status'; END IF;

  -- non-member (cross-workspace) sees NOTHING
  PERFORM public._seo_ov_login(current_setting('ov.nonmember')::uuid);
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid;
  IF n <> 0 THEN RAISE EXCEPTION 'RLS: non-member read a verification (%)', n; END IF;
  SELECT count(*) INTO n FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF n <> 0 THEN RAISE EXCEPTION 'RLS: non-member read verification events (%)', n; END IF;
  RAISE NOTICE 'RLS reads ok';
END $t$;

-- ---------- 5. RLS DIRECT-WRITE DENIAL (req #6, #7, #8) ---------------------
SELECT public._seo_ov_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner (member)
DO $t$
DECLARE v_ws uuid := current_setting('ov.workspace')::uuid;
        v_site uuid := current_setting('ov.dispsite')::uuid;
        v_vid uuid := current_setting('ov.vid')::uuid; ok boolean; rc int;
BEGIN
  PERFORM public._seo_ov_login(current_setting('ov.owner')::uuid);

  -- cannot INSERT a verification directly (no INSERT policy)
  ok := false;
  BEGIN INSERT INTO public.seo_ownership_verifications
    (workspace_id, website_id, website_url, verification_host, method, challenge_token)
    VALUES (v_ws, v_site, 'https://x', 'x', 'dns_txt', 'OWNVERIFY-direct');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated directly INSERTed a verification'; END IF;

  -- cannot UPDATE (no update policy → 0 rows)
  UPDATE public.seo_ownership_verifications SET status='verified' WHERE id=v_vid; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated UPDATEd a verification (% rows)', rc; END IF;

  -- cannot DELETE (0 rows)
  DELETE FROM public.seo_ownership_verifications WHERE id=v_vid; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated DELETEd a verification (% rows)', rc; END IF;

  -- cannot INSERT an audit event (append-only, no insert policy)
  ok := false;
  BEGIN INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, actor)
    VALUES (v_vid, v_ws, v_site, 'verified', 'customer');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated INSERTed an audit event'; END IF;

  -- cannot UPDATE/DELETE audit events (immutable)
  UPDATE public.seo_ownership_verification_events SET note='x' WHERE verification_id=v_vid; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated UPDATEd an audit event'; END IF;
  DELETE FROM public.seo_ownership_verification_events WHERE verification_id=v_vid; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated DELETEd an audit event'; END IF;
  RAISE NOTICE 'RLS direct-write denial ok';
END $t$;
RESET ROLE;

-- ---------- 6. TEARDOWN + ISOLATION ASSERTIONS ------------------------------
DELETE FROM public.seo_ownership_verifications WHERE challenge_token LIKE 'OWNVERIFY-%';  -- events cascade
DELETE FROM public.seo_websites WHERE id = current_setting('ov.dispsite')::uuid;
DROP FUNCTION IF EXISTS public._seo_ov_login(uuid);

DO $t$
DECLARE nv int; ne int; nw int;
        c_crawl int; c_inv int; c_opp int;
BEGIN
  SELECT count(*) INTO nv FROM public.seo_ownership_verifications WHERE challenge_token LIKE 'OWNVERIFY-%';
  SELECT count(*) INTO ne FROM public.seo_ownership_verification_events e
    WHERE e.website_id = 'af000000-0000-0000-0002-000000000099';
  SELECT count(*) INTO nw FROM public.seo_websites WHERE id = 'af000000-0000-0000-0002-000000000099';
  IF nv+ne+nw <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual rows verifications=% events=% dispsite=%', nv, ne, nw; END IF;

  -- req #11: other-module data unchanged
  SELECT count(*) INTO c_crawl FROM public.seo_crawl_jobs;
  SELECT count(*) INTO c_inv   FROM public.seo_page_inventory;
  SELECT count(*) INTO c_opp   FROM public.seo_authority_opportunities;
  IF c_crawl <> current_setting('ov.base_crawl')::int THEN RAISE EXCEPTION 'ISOLATION: seo_crawl_jobs count changed'; END IF;
  IF c_inv   <> current_setting('ov.base_inv')::int   THEN RAISE EXCEPTION 'ISOLATION: seo_page_inventory count changed'; END IF;
  IF c_opp   <> current_setting('ov.base_opp')::int   THEN RAISE EXCEPTION 'ISOLATION: seo_authority_opportunities count changed'; END IF;
  RAISE NOTICE 'TEARDOWN + isolation ok';
END $t$;

SELECT 'ALL PASS — seo_p1a_step1 ownership-verification DB contract verification complete' AS result;
