-- =============================================================================
-- SEO P1a Step 2B — Service-role ownership-verification RPCs + global-admin
--                    override — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER migrations
-- 20260716120031 / 120032 / 120033 are applied.
--
-- EXECUTION MODEL (same as Phase 16C): the `supabase db query --linked -f`
-- runner wraps the whole file in ONE transaction; NO explicit BEGIN/COMMIT.
-- Runs as the `postgres` connection role; the acting SEO user is switched via
-- jwt claims (set_config). Service-role RPCs are service_role-only; postgres
-- (superuser) may call them to simulate the worker, and the
-- authenticated/anon/PUBLIC denial is proven via has_function_privilege.
--
-- GLOBAL-ADMIN test: `seo_is_global_admin` reads public.profiles(id, role). That
-- table is ABSENT on TEST, so the override DENY path is tested first (nobody is a
-- global admin); then a SELF-CLEANING temporary `profiles` stub is created (only
-- if absent) and the existing `nonmember` auth user is elevated to super_admin to
-- exercise the ALLOW path with valid FKs. The stub + row are dropped in teardown.
--
-- All fixtures (disposable websites af000000-…-a3/a4/a5, tokens, claims, the
-- profiles stub) are removed in teardown → a successful run commits net-nothing.
-- No password/service-role key is used.
-- =============================================================================

-- ---------- 0. Fixture ids + jwt login helper -------------------------------
SELECT set_config('o3.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('o3.site',      'af000000-0000-0000-0002-0000000000a3', false);  -- main
SELECT set_config('o3.site2',     'af000000-0000-0000-0002-0000000000a4', false);  -- mismatch FK
SELECT set_config('o3.site3',     'af000000-0000-0000-0002-0000000000a5', false);  -- override
SELECT set_config('o3.owner',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('o3.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('o3.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('o3.client',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('o3.nonmember', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo_o3_login(p_uid uuid)
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

-- ---------- 1. STRUCTURE + GRANTS (#1–#6 struct/grants) ---------------------
DO $t$
DECLARE n int;
BEGIN
  -- claims table + RLS
  SELECT count(*) INTO n FROM information_schema.tables
   WHERE table_schema='public' AND table_name='seo_ownership_verification_claims';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: claims table missing'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
          WHERE ns.nspname='public' AND c.relname='seo_ownership_verification_claims') THEN
    RAISE EXCEPTION 'STRUCT: RLS not enabled on claims table'; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public'
    AND tablename='seo_ownership_verification_claims';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: claims table must have exactly 1 (admin SELECT) policy, got %', n; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND indexname='uq_seo_ownership_claims_open_per_verification') THEN
    RAISE EXCEPTION 'STRUCT: open-claim unique index missing'; END IF;

  -- 3 RPCs SECURITY DEFINER + search_path=public
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('seo_ownership_verification_claim','seo_ownership_verification_record_result',
      'seo_ownership_verification_admin_override')
     AND p.prosecdef
     AND (SELECT bool_or(c='search_path=public') FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) c);
  IF n <> 3 THEN RAISE EXCEPTION 'STRUCT: 3 RPCs must be SECURITY DEFINER + search_path=public (got %)', n; END IF;

  -- grants: service-role functions = service_role only
  IF NOT has_function_privilege('service_role','public.seo_ownership_verification_claim(text,integer)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.seo_ownership_verification_record_result(uuid,text,uuid,text,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: service_role must execute claim + record_result'; END IF;
  IF has_function_privilege('authenticated','public.seo_ownership_verification_claim(text,integer)','EXECUTE')
     OR has_function_privilege('anon','public.seo_ownership_verification_claim(text,integer)','EXECUTE')
     OR has_function_privilege('authenticated','public.seo_ownership_verification_record_result(uuid,text,uuid,text,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.seo_ownership_verification_record_result(uuid,text,uuid,text,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated/anon must NOT execute service-role functions'; END IF;
  -- override: authenticated yes, anon no
  IF NOT has_function_privilege('authenticated','public.seo_ownership_verification_admin_override(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated must execute admin_override'; END IF;
  IF has_function_privilege('anon','public.seo_ownership_verification_admin_override(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: anon must NOT execute admin_override'; END IF;
  RAISE NOTICE 'STRUCT + GRANTS ok';
END $t$;

-- baseline other-module counts (isolation, #31-#33)
SELECT set_config('o3.base_crawl', (SELECT count(*)::text FROM public.seo_crawl_jobs), false);
SELECT set_config('o3.base_inv',   (SELECT count(*)::text FROM public.seo_page_inventory), false);
SELECT set_config('o3.base_opp',   (SELECT count(*)::text FROM public.seo_authority_opportunities), false);

-- disposable ACTIVE websites in the seed workspace
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES
 (current_setting('o3.site')::uuid,  current_setting('o3.workspace')::uuid, 'https://p1a-step2b.example',   'P1A Step2B Main',     'P1A S2B', 'other','pending',true),
 (current_setting('o3.site2')::uuid, current_setting('o3.workspace')::uuid, 'https://p1a-step2b-b.example', 'P1A Step2B Mismatch', 'P1A S2B', 'other','pending',true),
 (current_setting('o3.site3')::uuid, current_setting('o3.workspace')::uuid, 'https://p1a-step2b-c.example', 'P1A Step2B Override', 'P1A S2B', 'other','pending',true)
ON CONFLICT (id) DO NOTHING;

-- ---------- 2. CLAIM + RESULT core (#7,#8,#9,#10,#12,#14,#15,#17,#18,#20) ----
DO $t$
DECLARE v_site uuid := current_setting('o3.site')::uuid;
        r public.seo_ownership_verifications%ROWTYPE;
        cl record; vid uuid; t0 text; l1 uuid; l2 uuid; n int; ev int; ok boolean;
BEGIN
  PERFORM public._seo_o3_login(current_setting('o3.owner')::uuid);
  r := public.seo_ownership_verification_initiate(v_site);
  vid := r.id; t0 := r.challenge_token;
  PERFORM set_config('o3.vid', vid::text, false);
  PERFORM set_config('o3.t0',  t0, false);

  -- #7 claim eligible pending
  SELECT * INTO cl FROM public.seo_ownership_verification_claim('vw1', 120);
  IF cl.verification_id <> vid THEN RAISE EXCEPTION 'CLAIM: did not claim the pending verification'; END IF;
  IF cl.expected_challenge_value <> t0 THEN RAISE EXCEPTION 'CLAIM: expected value != challenge token'; END IF;
  IF cl.dns_txt_name <> '_digibility-site-verification.p1a-step2b.example' THEN RAISE EXCEPTION 'CLAIM: dns_txt_name wrong (%)', cl.dns_txt_name; END IF;
  IF cl.verification_host <> 'p1a-step2b.example' THEN RAISE EXCEPTION 'CLAIM: host wrong'; END IF;
  l1 := cl.lease_token;

  -- #10 duplicate concurrent claim prevented
  SELECT count(*) INTO n FROM public.seo_ownership_verification_claim('vw2', 120);
  IF n <> 0 THEN RAISE EXCEPTION 'CLAIM: a second concurrent claim was allowed (%)', n; END IF;

  -- #15 result → failed (customer-safe reason)
  r := public.seo_ownership_verification_record_result(vid,'vw1',l1,'failed','TXT record not found','dns_nxdomain','resolver detail internal');
  IF r.status <> 'failed' THEN RAISE EXCEPTION 'RESULT: status % (expected failed)', r.status; END IF;
  IF r.failure_reason <> 'TXT record not found' THEN RAISE EXCEPTION 'RESULT: customer-safe reason not persisted'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid AND event_type='failed';
  IF ev <> 1 THEN RAISE EXCEPTION 'RESULT: expected 1 failed event, got %', ev; END IF;

  -- #18 duplicate identical result idempotent (no NEW failed event)
  r := public.seo_ownership_verification_record_result(vid,'vw1',l1,'failed','TXT record not found',NULL,NULL);
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid AND event_type='failed';
  IF ev <> 1 THEN RAISE EXCEPTION 'RESULT idem: duplicate failed added a second failed event (%)', ev; END IF;

  -- #8 failed work claimable again
  SELECT * INTO cl FROM public.seo_ownership_verification_claim('vw3', 120);
  IF cl.verification_id <> vid THEN RAISE EXCEPTION 'CLAIM: failed verification not re-claimable'; END IF;
  l2 := cl.lease_token;
  IF l2 = l1 THEN RAISE EXCEPTION 'CLAIM: lease token not regenerated on re-claim'; END IF;

  -- #17 stale claim rejected (old worker/lease)
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_record_result(vid,'vw1',l1,'verified',NULL,NULL,NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RESULT: stale (old-lease) result was accepted'; END IF;

  -- #14 result → verified; #20 token NOT rotated
  r := public.seo_ownership_verification_record_result(vid,'vw3',l2,'verified',NULL,NULL,NULL);
  IF r.status <> 'verified' THEN RAISE EXCEPTION 'RESULT: status % (expected verified)', r.status; END IF;
  IF r.verified_at IS NULL THEN RAISE EXCEPTION 'RESULT: verified_at not set'; END IF;
  IF r.challenge_token <> t0 THEN RAISE EXCEPTION 'RESULT: challenge token was rotated by result persistence'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid AND event_type='verified';
  IF ev <> 1 THEN RAISE EXCEPTION 'RESULT: expected 1 verified event, got %', ev; END IF;

  -- #9 verified work not claimable
  SELECT count(*) INTO n FROM public.seo_ownership_verification_claim('vw4', 120);
  IF n <> 0 THEN RAISE EXCEPTION 'CLAIM: verified verification was claimable (%)', n; END IF;
  RAISE NOTICE 'CLAIM + RESULT core ok';
END $t$;

-- ---------- 3. STALE / EXPIRED CLAIM RECOVERY (#11) + CROSS-WEBSITE (#13) ----
DO $t$
DECLARE v_site uuid := current_setting('o3.site')::uuid;
        v_site2 uuid := current_setting('o3.site2')::uuid;
        v_ws uuid := current_setting('o3.workspace')::uuid;
        vid uuid := current_setting('o3.vid')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; cl record; n int; ok boolean; ghost uuid;
BEGIN
  PERFORM public._seo_o3_login(current_setting('o3.owner')::uuid);
  -- reset to pending via customer re-verify (rotates token)
  r := public.seo_ownership_verification_reverify(v_site);
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'RECOVERY setup: reverify did not set pending'; END IF;

  -- insert an EXPIRED open claim (ghost worker)
  ghost := gen_random_uuid();
  INSERT INTO public.seo_ownership_verification_claims
    (verification_id, workspace_id, website_id, worker_id, lease_token, claimed_at, lease_expires_at)
  VALUES (vid, v_ws, v_site, 'ghost', ghost, now()-interval '10 min', now()-interval '5 min');

  -- #11 claim recovers: releases the expired claim + opens a new one
  SELECT * INTO cl FROM public.seo_ownership_verification_claim('vw5', 120);
  IF cl.verification_id <> vid THEN RAISE EXCEPTION 'RECOVERY: expired-lease verification not re-claimed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_ownership_verification_claims
                 WHERE verification_id=vid AND lease_token=ghost AND released_at IS NOT NULL AND outcome='lease_expired') THEN
    RAISE EXCEPTION 'RECOVERY: expired ghost claim was not released as lease_expired'; END IF;
  -- ghost worker result now rejected (stale)
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_record_result(vid,'ghost',ghost,'verified',NULL,NULL,NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RECOVERY: released ghost lease still accepted a result'; END IF;
  -- close the fresh recovery claim
  PERFORM public.seo_ownership_verification_record_result(vid, 'vw5', cl.lease_token, 'failed', 'still missing', NULL, NULL);

  -- #13 cross-website mismatch: open claim with a DIFFERENT (valid) website id
  INSERT INTO public.seo_ownership_verification_claims
    (verification_id, workspace_id, website_id, worker_id, lease_token, lease_expires_at)
  VALUES (vid, v_ws, v_site2, 'mm', '00000000-0000-0000-0000-0000000000ab', now()+interval '5 min');
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_record_result(vid,'mm','00000000-0000-0000-0000-0000000000ab','verified',NULL,NULL,NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'MISMATCH: cross-website claim was accepted'; END IF;
  UPDATE public.seo_ownership_verification_claims SET released_at=now(), outcome='released'
   WHERE verification_id=vid AND worker_id='mm';
  RAISE NOTICE 'RECOVERY + cross-website ok';
END $t$;

-- ---------- 4. OVERRIDE DENIALS (#23) — before any global admin exists -------
DO $t$
DECLARE v_site uuid := current_setting('o3.site')::uuid; ok boolean;
BEGIN
  PERFORM public._seo_o3_login(current_setting('o3.owner')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_admin_override(v_site,'mark_verified','x'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'OVERRIDE: owner was allowed to override'; END IF;
  PERFORM public._seo_o3_login(current_setting('o3.admin')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_admin_override(v_site,'mark_verified','x'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'OVERRIDE: admin was allowed to override'; END IF;
  PERFORM public._seo_o3_login(current_setting('o3.team')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_admin_override(v_site,'mark_verified','x'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'OVERRIDE: team_member was allowed to override'; END IF;
  PERFORM public._seo_o3_login(current_setting('o3.client')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_admin_override(v_site,'mark_verified','x'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'OVERRIDE: client was allowed to override'; END IF;
  PERFORM public._seo_o3_login(current_setting('o3.nonmember')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_admin_override(v_site,'mark_verified','x'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'OVERRIDE: non-member was allowed to override'; END IF;
  RAISE NOTICE 'OVERRIDE denials ok';
END $t$;

-- ---------- 5. GLOBAL-ADMIN ALLOW (#21,#22,#24,#25,#26) ----------------------
-- Self-cleaning profiles stub: create only if absent; elevate nonmember → GA.
SELECT set_config('o3.had_profiles',
  (SELECT (count(*) > 0)::text FROM information_schema.tables
   WHERE table_schema='public' AND table_name='profiles'), false);
DO $t$
BEGIN
  IF current_setting('o3.had_profiles') <> 'true' THEN
    CREATE TABLE public.profiles (id uuid PRIMARY KEY, role text);
  END IF;
END $t$;
INSERT INTO public.profiles (id, role)
VALUES (current_setting('o3.nonmember')::uuid, 'super_admin')
ON CONFLICT (id) DO UPDATE SET role = 'super_admin';

DO $t$
DECLARE v_site3 uuid := current_setting('o3.site3')::uuid;
        v_ws uuid := current_setting('o3.workspace')::uuid;
        v_ga uuid := current_setting('o3.nonmember')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; ev int; vid3 uuid;
BEGIN
  PERFORM public._seo_o3_login(v_ga);  -- now a global admin

  -- #21 mark_verified (creates record for a website with none) + #24 server-side resolve
  r := public.seo_ownership_verification_admin_override(v_site3,'mark_verified','manual owner approval');
  IF r.status <> 'verified' THEN RAISE EXCEPTION 'OVERRIDE: mark_verified did not verify'; END IF;
  IF r.workspace_id <> v_ws THEN RAISE EXCEPTION 'OVERRIDE: workspace not resolved server-side'; END IF;
  IF r.verification_host <> 'p1a-step2b-c.example' THEN RAISE EXCEPTION 'OVERRIDE: host not resolved server-side'; END IF;
  vid3 := r.id;

  -- #25 audit records action + actor
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events
   WHERE verification_id=vid3 AND event_type='admin_override' AND actor='global_admin'
     AND actor_user_id=v_ga AND note LIKE '%manual owner approval%';
  IF ev <> 1 THEN RAISE EXCEPTION 'OVERRIDE: admin_override audit event missing/incorrect (%)', ev; END IF;

  -- #26 idempotent repeat mark_verified (no new event)
  r := public.seo_ownership_verification_admin_override(v_site3,'mark_verified','again');
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid3;
  IF ev <> 1 THEN RAISE EXCEPTION 'OVERRIDE: idempotent mark_verified added an event (total %)', ev; END IF;

  -- #22 invalidate/revoke with reason
  r := public.seo_ownership_verification_admin_override(v_site3,'invalidate','compliance takedown');
  IF r.status <> 'revoked' THEN RAISE EXCEPTION 'OVERRIDE: invalidate did not revoke'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid3;
  IF ev <> 2 THEN RAISE EXCEPTION 'OVERRIDE: invalidate did not add exactly one event (total %)', ev; END IF;
  -- idempotent invalidate
  r := public.seo_ownership_verification_admin_override(v_site3,'invalidate','again');
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid3;
  IF ev <> 2 THEN RAISE EXCEPTION 'OVERRIDE: idempotent invalidate added an event (total %)', ev; END IF;

  -- empty reason rejected
  DECLARE ok2 boolean := false;
  BEGIN
    BEGIN PERFORM public.seo_ownership_verification_admin_override(v_site3,'mark_verified','   ');
    EXCEPTION WHEN OTHERS THEN ok2 := true; END;
    IF NOT ok2 THEN RAISE EXCEPTION 'OVERRIDE: empty reason was accepted'; END IF;
  END;
  RAISE NOTICE 'GLOBAL-ADMIN allow ok';
END $t$;

-- ---------- 6. NON-REGRESSION: Step 2A + RLS (#16,#27,#28,#29,#30) -----------
DO $t$
DECLARE v_site uuid := current_setting('o3.site')::uuid; r public.seo_ownership_verifications%ROWTYPE; ok boolean;
BEGIN
  -- #27 Step 2A owner customer RPC still works
  PERFORM public._seo_o3_login(current_setting('o3.owner')::uuid);
  r := public.seo_ownership_verification_initiate(v_site);
  IF r.status NOT IN ('pending','verified','failed','revoked') THEN RAISE EXCEPTION 'REG: Step 2A initiate broken'; END IF;
  -- #28 team + client customer-write denial intact
  PERFORM public._seo_o3_login(current_setting('o3.team')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_recheck(v_site); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'REG: team_member Step 2A write not denied'; END IF;
  PERFORM public._seo_o3_login(current_setting('o3.client')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_initiate(v_site); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'REG: client Step 2A write not denied'; END IF;
  RAISE NOTICE 'REG Step 2A ok';
END $t$;

SET LOCAL ROLE authenticated;
SELECT public._seo_o3_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner
DO $t$
DECLARE v_ws uuid := current_setting('o3.workspace')::uuid;
        v_site uuid := current_setting('o3.site')::uuid;
        vid uuid := current_setting('o3.vid')::uuid; ok boolean; rc int; n int;
BEGIN
  PERFORM public._seo_o3_login(current_setting('o3.owner')::uuid);
  -- #29 direct customer writes to verifications denied
  UPDATE public.seo_ownership_verifications SET status='verified' WHERE id=vid; GET DIAGNOSTICS rc=ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'REG: authenticated UPDATEd a verification'; END IF;
  -- #16 internal claims table NOT customer-readable + not customer-writable
  SELECT count(*) INTO n FROM public.seo_ownership_verification_claims WHERE verification_id=vid;
  IF n <> 0 THEN RAISE EXCEPTION 'REG: internal claims readable by a customer (%)', n; END IF;
  ok:=false; BEGIN INSERT INTO public.seo_ownership_verification_claims
    (verification_id,workspace_id,website_id,worker_id,lease_token,lease_expires_at)
    VALUES (vid,v_ws,v_site,'x',gen_random_uuid(),now()+interval '5 min'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'REG: authenticated INSERTed into internal claims table'; END IF;
  -- #30 customer-safe RLS read still works
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=vid;
  IF n <> 1 THEN RAISE EXCEPTION 'REG: owner cannot read own verification'; END IF;
  RAISE NOTICE 'REG RLS ok';
END $t$;
RESET ROLE;

-- ---------- 7. CRAWLER RPC NON-REGRESSION (#31) -----------------------------
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('seo_crawl_request','seo_crawl_cancel','seo_crawl_request_audit','seo_crawl_claim_job');
  IF n < 4 THEN RAISE EXCEPTION 'CRAWL: crawler RPCs missing (%)', n; END IF;
  IF NOT has_function_privilege('authenticated','public.seo_crawl_request(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CRAWL: seo_crawl_request grant regressed'; END IF;
  IF has_function_privilege('authenticated','public.seo_crawl_claim_job(text,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'CRAWL: seo_crawl_claim_job must remain service-role-only'; END IF;
  RAISE NOTICE 'crawler RPC non-regression ok';
END $t$;

-- ---------- 8. TEARDOWN + ISOLATION (#32,#33,#34,#35) -----------------------
DELETE FROM public.seo_ownership_verifications
 WHERE website_id IN (current_setting('o3.site')::uuid, current_setting('o3.site2')::uuid, current_setting('o3.site3')::uuid);  -- claims + events cascade
DELETE FROM public.seo_websites
 WHERE id IN (current_setting('o3.site')::uuid, current_setting('o3.site2')::uuid, current_setting('o3.site3')::uuid);
DELETE FROM public.profiles WHERE id = current_setting('o3.nonmember')::uuid;
DO $t$
BEGIN
  IF current_setting('o3.had_profiles') <> 'true' THEN
    DROP TABLE IF EXISTS public.profiles;   -- only drop the stub we created
  END IF;
END $t$;
DROP FUNCTION IF EXISTS public._seo_o3_login(uuid);

DO $t$
DECLARE nv int; nc int; nw int; c_crawl int; c_inv int; c_opp int; prof int;
BEGIN
  SELECT count(*) INTO nv FROM public.seo_ownership_verifications
   WHERE website_id IN ('af000000-0000-0000-0002-0000000000a3','af000000-0000-0000-0002-0000000000a4','af000000-0000-0000-0002-0000000000a5');
  SELECT count(*) INTO nc FROM public.seo_ownership_verification_claims
   WHERE website_id IN ('af000000-0000-0000-0002-0000000000a3','af000000-0000-0000-0002-0000000000a4','af000000-0000-0000-0002-0000000000a5');
  SELECT count(*) INTO nw FROM public.seo_websites
   WHERE id IN ('af000000-0000-0000-0002-0000000000a3','af000000-0000-0000-0002-0000000000a4','af000000-0000-0000-0002-0000000000a5');
  IF nv+nc+nw <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual verifications=% claims=% websites=%', nv, nc, nw; END IF;

  SELECT count(*) INTO prof FROM information_schema.tables WHERE table_schema='public' AND table_name='profiles';
  IF current_setting('o3.had_profiles') <> 'true' AND prof <> 0 THEN
    RAISE EXCEPTION 'TEARDOWN: profiles stub not dropped'; END IF;

  SELECT count(*) INTO c_crawl FROM public.seo_crawl_jobs;
  SELECT count(*) INTO c_inv   FROM public.seo_page_inventory;
  SELECT count(*) INTO c_opp   FROM public.seo_authority_opportunities;
  IF c_crawl <> current_setting('o3.base_crawl')::int THEN RAISE EXCEPTION 'ISOLATION: seo_crawl_jobs changed'; END IF;
  IF c_inv   <> current_setting('o3.base_inv')::int   THEN RAISE EXCEPTION 'ISOLATION: seo_page_inventory changed'; END IF;
  IF c_opp   <> current_setting('o3.base_opp')::int   THEN RAISE EXCEPTION 'ISOLATION: seo_authority_opportunities changed'; END IF;
  RAISE NOTICE 'TEARDOWN + isolation ok';
END $t$;

SELECT 'ALL PASS — seo_p1a_step2b service-role + global-admin ownership-verification verification complete' AS result;
