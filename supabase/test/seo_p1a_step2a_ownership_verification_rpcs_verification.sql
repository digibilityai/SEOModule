-- =============================================================================
-- SEO P1a Step 2A — Guarded CUSTOMER ownership-verification RPCs — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER migrations
-- 20260716120031 (Step 1 tables) and 20260716120032 (Step 2A RPCs) are applied.
--
-- EXECUTION MODEL (same as Phase 16C): the `supabase db query --linked -f`
-- runner wraps the whole file in ONE transaction; NO explicit BEGIN/COMMIT.
-- Runs as the `postgres` connection role; the acting SEO user is switched via
-- jwt claims (set_config) so each RPC's auth.uid()/role checks evaluate per user.
-- Direct-write RLS tests additionally `SET LOCAL ROLE authenticated`. All
-- fixtures are tagged (challenge_token prefix 'digibility-site-verification='
-- on a disposable website); teardown removes them → a successful run commits
-- net-nothing. No password/service-role key is used.
--
-- PREREQUISITE: the five shared TEST auth users exist (owner/admin/team/client/
-- nonmember) and the UI-seed workspace exists.
-- =============================================================================

-- ---------- 0. Fixture ids + jwt login helper -------------------------------
SELECT set_config('o2.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('o2.dispsite',  'af000000-0000-0000-0002-0000000000a2', false);
SELECT set_config('o2.owner',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('o2.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('o2.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('o2.client',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('o2.nonmember', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo_o2_login(p_uid uuid)
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
  -- 4 customer RPCs + 3 helpers present
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('seo_ownership_verification_initiate','seo_ownership_verification_recheck',
      'seo_ownership_verification_reverify','seo_ownership_verification_revoke',
      '_seo_ownership_authorize','seo_ownership_extract_host','seo_ownership_new_challenge_token');
  IF n <> 7 THEN RAISE EXCEPTION 'STRUCT: expected 7 Step 2A functions, got %', n; END IF;

  -- all 4 RPCs are SECURITY DEFINER with search_path=public
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('seo_ownership_verification_initiate','seo_ownership_verification_recheck',
      'seo_ownership_verification_reverify','seo_ownership_verification_revoke')
     AND p.prosecdef
     AND (SELECT bool_or(c = 'search_path=public') FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c);
  IF n <> 4 THEN RAISE EXCEPTION 'STRUCT: not all 4 RPCs are SECURITY DEFINER + search_path=public (got %)', n; END IF;
  RAISE NOTICE 'STRUCT ok';
END $t$;

-- ---------- 2. GRANTS -------------------------------------------------------
DO $t$
BEGIN
  -- authenticated may execute all 4 RPCs; anon may not
  IF NOT has_function_privilege('authenticated','public.seo_ownership_verification_initiate(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.seo_ownership_verification_recheck(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.seo_ownership_verification_reverify(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.seo_ownership_verification_revoke(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated must execute all 4 Step 2A RPCs';
  END IF;
  IF has_function_privilege('anon','public.seo_ownership_verification_initiate(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.seo_ownership_verification_revoke(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: anon must NOT execute Step 2A RPCs';
  END IF;
  -- internal helpers not callable by authenticated/anon
  IF has_function_privilege('authenticated','public._seo_ownership_authorize(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.seo_ownership_new_challenge_token()','EXECUTE')
     OR has_function_privilege('authenticated','public.seo_ownership_extract_host(text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: internal helpers must NOT be executable by authenticated';
  END IF;
  RAISE NOTICE 'GRANT ok';
END $t$;

-- baseline other-module counts (isolation proof, req #22)
SELECT set_config('o2.base_crawl', (SELECT count(*)::text FROM public.seo_crawl_jobs), false);
SELECT set_config('o2.base_inv',   (SELECT count(*)::text FROM public.seo_page_inventory), false);
SELECT set_config('o2.base_opp',   (SELECT count(*)::text FROM public.seo_authority_opportunities), false);

-- disposable ACTIVE website in the seed workspace
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('o2.dispsite')::uuid, current_setting('o2.workspace')::uuid,
        'https://p1a-step2a.example', 'P1A Step2A Disposable', 'P1A Step2A', 'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- 3. INITIATE (create) + idempotency ------------------------------
DO $t$
DECLARE v_site uuid := current_setting('o2.dispsite')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; ev int;
BEGIN
  PERFORM public._seo_o2_login(current_setting('o2.owner')::uuid);
  r := public.seo_ownership_verification_initiate(v_site);
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'INIT: status % (expected pending)', r.status; END IF;
  IF r.verification_host <> 'p1a-step2a.example' THEN RAISE EXCEPTION 'INIT: host % (expected p1a-step2a.example)', r.verification_host; END IF;
  IF r.challenge_token NOT LIKE 'digibility-site-verification=%' THEN RAISE EXCEPTION 'INIT: token format wrong (%)', r.challenge_token; END IF;
  IF r.verified_at IS NOT NULL THEN RAISE EXCEPTION 'INIT: verified_at should be null on create'; END IF;
  PERFORM set_config('o2.vid', r.id::text, false);
  PERFORM set_config('o2.t1',  r.challenge_token, false);
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=r.id;
  IF ev <> 1 THEN RAISE EXCEPTION 'INIT: expected 1 event, got %', ev; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_ownership_verification_events
                 WHERE verification_id=r.id AND event_type='initiated' AND actor='customer'
                   AND to_status='pending') THEN RAISE EXCEPTION 'INIT: initiated event missing'; END IF;

  -- idempotent initiate (pending, same host) → same row, same token, NO new event
  r := public.seo_ownership_verification_initiate(v_site);
  IF r.id::text <> current_setting('o2.vid') THEN RAISE EXCEPTION 'INIT idem: different record id'; END IF;
  IF r.challenge_token <> current_setting('o2.t1') THEN RAISE EXCEPTION 'INIT idem: token rotated on idempotent initiate'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=r.id;
  IF ev <> 1 THEN RAISE EXCEPTION 'INIT idem: event added on no-op (total %)', ev; END IF;
  RAISE NOTICE 'INITIATE ok';
END $t$;

-- ---------- 4. RECHECK (reuse token) + REVERIFY (rotate) --------------------
DO $t$
DECLARE v_site uuid := current_setting('o2.dispsite')::uuid;
        v_vid uuid := current_setting('o2.vid')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; ev int;
BEGIN
  PERFORM public._seo_o2_login(current_setting('o2.owner')::uuid);

  -- recheck: token reused, stays pending, +1 check_started, last_checked_at set
  r := public.seo_ownership_verification_recheck(v_site);
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'RECHECK: status % (expected pending)', r.status; END IF;
  IF r.challenge_token <> current_setting('o2.t1') THEN RAISE EXCEPTION 'RECHECK: token must be reused (not rotated)'; END IF;
  IF r.last_checked_at IS NULL THEN RAISE EXCEPTION 'RECHECK: last_checked_at not set'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF ev <> 2 THEN RAISE EXCEPTION 'RECHECK: expected 2 events, got %', ev; END IF;

  -- reverify: token rotates, pending, +1 re_verification_requested
  r := public.seo_ownership_verification_reverify(v_site);
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'REVERIFY: status % (expected pending)', r.status; END IF;
  IF r.challenge_token = current_setting('o2.t1') THEN RAISE EXCEPTION 'REVERIFY: token did NOT rotate'; END IF;
  IF r.challenge_rotated_at IS NULL THEN RAISE EXCEPTION 'REVERIFY: challenge_rotated_at not set'; END IF;
  PERFORM set_config('o2.t2', r.challenge_token, false);
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF ev <> 3 THEN RAISE EXCEPTION 'REVERIFY: expected 3 events, got %', ev; END IF;
  RAISE NOTICE 'RECHECK + REVERIFY ok';
END $t$;

-- ---------- 5. ROLE DENIALS (team/client/nonmember/anon) --------------------
DO $t$
DECLARE v_site uuid := current_setting('o2.dispsite')::uuid;
        v_vid uuid := current_setting('o2.vid')::uuid; ok boolean; ev int;
BEGIN
  -- team_member denied (recheck)
  PERFORM public._seo_o2_login(current_setting('o2.team')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_recheck(v_site); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'DENY: team_member was allowed to re-check'; END IF;
  -- client denied (initiate)
  PERFORM public._seo_o2_login(current_setting('o2.client')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_initiate(v_site); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'DENY: client was allowed to initiate'; END IF;
  -- non-member / cross-workspace denied (initiate)
  PERFORM public._seo_o2_login(current_setting('o2.nonmember')::uuid);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_initiate(v_site); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'DENY: non-member (cross-workspace) was allowed to initiate'; END IF;
  -- anonymous denied
  PERFORM public._seo_o2_login(NULL);
  ok:=false; BEGIN PERFORM public.seo_ownership_verification_initiate(v_site); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'DENY: anonymous was allowed to initiate'; END IF;

  -- state unchanged by all denials (still pending, still t2, still 3 events)
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF ev <> 3 THEN RAISE EXCEPTION 'DENY: denied calls mutated audit (events=%)', ev; END IF;
  IF (SELECT status FROM public.seo_ownership_verifications WHERE id=v_vid) <> 'pending' THEN
    RAISE EXCEPTION 'DENY: denied calls changed status'; END IF;
  IF (SELECT challenge_token FROM public.seo_ownership_verifications WHERE id=v_vid) <> current_setting('o2.t2') THEN
    RAISE EXCEPTION 'DENY: denied calls rotated token'; END IF;
  RAISE NOTICE 'ROLE denials ok';
END $t$;

-- ---------- 6. REVOKE (admin) + idempotency + admin re-initiate -------------
DO $t$
DECLARE v_site uuid := current_setting('o2.dispsite')::uuid;
        v_vid uuid := current_setting('o2.vid')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; ev int;
BEGIN
  -- admin revoke → revoked + 1 event (proves admin authorized + revoke behaviour)
  PERFORM public._seo_o2_login(current_setting('o2.admin')::uuid);
  r := public.seo_ownership_verification_revoke(v_site);
  IF r.status <> 'revoked' THEN RAISE EXCEPTION 'REVOKE: status % (expected revoked)', r.status; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF ev <> 4 THEN RAISE EXCEPTION 'REVOKE: expected 4 events, got %', ev; END IF;

  -- idempotent revoke (owner) → revoked, NO new event
  PERFORM public._seo_o2_login(current_setting('o2.owner')::uuid);
  r := public.seo_ownership_verification_revoke(v_site);
  IF r.status <> 'revoked' THEN RAISE EXCEPTION 'REVOKE idem: status %', r.status; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF ev <> 4 THEN RAISE EXCEPTION 'REVOKE idem: added an event (total %)', ev; END IF;

  -- admin initiate FROM revoked → restart: pending + token rotates + 1 event
  PERFORM public._seo_o2_login(current_setting('o2.admin')::uuid);
  r := public.seo_ownership_verification_initiate(v_site);
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'RESTART: status % (expected pending)', r.status; END IF;
  IF r.challenge_token = current_setting('o2.t2') THEN RAISE EXCEPTION 'RESTART: token did NOT rotate from revoked'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=v_vid;
  IF ev <> 5 THEN RAISE EXCEPTION 'RESTART: expected 5 events, got %', ev; END IF;
  RAISE NOTICE 'REVOKE + idempotency + admin restart ok';
END $t$;

-- ---------- 7. DIRECT-WRITE RLS DENIAL + reads (#18, #19, #20) --------------
SET LOCAL ROLE authenticated;
SELECT public._seo_o2_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner
DO $t$
DECLARE v_ws uuid := current_setting('o2.workspace')::uuid;
        v_site uuid := current_setting('o2.dispsite')::uuid;
        v_vid uuid := current_setting('o2.vid')::uuid; ok boolean; rc int; n int;
BEGIN
  PERFORM public._seo_o2_login(current_setting('o2.owner')::uuid);
  -- cannot INSERT/UPDATE/DELETE verifications directly
  ok:=false; BEGIN INSERT INTO public.seo_ownership_verifications
    (workspace_id,website_id,website_url,verification_host,method,challenge_token)
    VALUES (v_ws,v_site,'https://x','x','dns_txt','digibility-site-verification=direct');
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated directly INSERTed a verification'; END IF;
  UPDATE public.seo_ownership_verifications SET status='verified' WHERE id=v_vid; GET DIAGNOSTICS rc=ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated UPDATEd a verification (% rows)', rc; END IF;
  DELETE FROM public.seo_ownership_verifications WHERE id=v_vid; GET DIAGNOSTICS rc=ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated DELETEd a verification (% rows)', rc; END IF;
  -- cannot write audit events
  ok:=false; BEGIN INSERT INTO public.seo_ownership_verification_events
    (verification_id,workspace_id,website_id,event_type,actor)
    VALUES (v_vid,v_ws,v_site,'verified','customer'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated INSERTed an audit event'; END IF;
  UPDATE public.seo_ownership_verification_events SET note='x' WHERE verification_id=v_vid; GET DIAGNOSTICS rc=ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated UPDATEd an audit event'; END IF;

  -- customer-safe reads still work: owner + client read; non-member sees nothing
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid;
  IF n <> 1 THEN RAISE EXCEPTION 'READ: owner cannot read own verification'; END IF;
  PERFORM public._seo_o2_login(current_setting('o2.client')::uuid);
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid;
  IF n <> 1 THEN RAISE EXCEPTION 'READ: client member cannot read verification status'; END IF;
  PERFORM public._seo_o2_login(current_setting('o2.nonmember')::uuid);
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE id=v_vid;
  IF n <> 0 THEN RAISE EXCEPTION 'READ: non-member read a verification (%)', n; END IF;
  RAISE NOTICE 'RLS direct-write denial + reads ok';
END $t$;
RESET ROLE;

-- #20 internal-field guard: the customer-readable table exposes NO internal cols
DO $t$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad FROM information_schema.columns
   WHERE table_schema='public' AND table_name='seo_ownership_verifications'
     AND column_name IN ('correlation_id','worker_id','lease_token','internal_error_code',
                         'internal_error_detail','service_role_key','service_role_metadata');
  IF bad <> 0 THEN RAISE EXCEPTION 'FIELDS: internal-only column(s) present on customer table (%).', bad; END IF;
  RAISE NOTICE 'internal-field guard ok';
END $t$;

-- ---------- 8. CRAWLER RPC NON-REGRESSION (#21) -----------------------------
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('seo_crawl_request','seo_crawl_cancel','seo_crawl_request_audit','seo_crawl_claim_job');
  IF n < 4 THEN RAISE EXCEPTION 'CRAWL: expected the 4 crawler RPCs to still exist (got %)', n; END IF;
  IF NOT has_function_privilege('authenticated','public.seo_crawl_request(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CRAWL: seo_crawl_request authenticated grant regressed'; END IF;
  IF NOT has_function_privilege('authenticated','public.seo_crawl_cancel(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'CRAWL: seo_crawl_cancel authenticated grant regressed'; END IF;
  IF has_function_privilege('authenticated','public.seo_crawl_claim_job(text,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'CRAWL: seo_crawl_claim_job must remain service-role-only'; END IF;
  RAISE NOTICE 'crawler RPC non-regression ok';
END $t$;

-- ---------- 9. TEARDOWN + ISOLATION (#22, #23) ------------------------------
DELETE FROM public.seo_ownership_verifications
 WHERE website_id = current_setting('o2.dispsite')::uuid
   AND challenge_token LIKE 'digibility-site-verification=%';  -- events cascade
DELETE FROM public.seo_websites WHERE id = current_setting('o2.dispsite')::uuid;
DROP FUNCTION IF EXISTS public._seo_o2_login(uuid);

DO $t$
DECLARE nv int; nw int; c_crawl int; c_inv int; c_opp int;
BEGIN
  SELECT count(*) INTO nv FROM public.seo_ownership_verifications
    WHERE website_id='af000000-0000-0000-0002-0000000000a2';
  SELECT count(*) INTO nw FROM public.seo_websites WHERE id='af000000-0000-0000-0002-0000000000a2';
  IF nv+nw <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual verifications=% dispsite=%', nv, nw; END IF;

  SELECT count(*) INTO c_crawl FROM public.seo_crawl_jobs;
  SELECT count(*) INTO c_inv   FROM public.seo_page_inventory;
  SELECT count(*) INTO c_opp   FROM public.seo_authority_opportunities;
  IF c_crawl <> current_setting('o2.base_crawl')::int THEN RAISE EXCEPTION 'ISOLATION: seo_crawl_jobs count changed'; END IF;
  IF c_inv   <> current_setting('o2.base_inv')::int   THEN RAISE EXCEPTION 'ISOLATION: seo_page_inventory count changed'; END IF;
  IF c_opp   <> current_setting('o2.base_opp')::int   THEN RAISE EXCEPTION 'ISOLATION: seo_authority_opportunities count changed'; END IF;
  RAISE NOTICE 'TEARDOWN + isolation ok';
END $t$;

SELECT 'ALL PASS — seo_p1a_step2a ownership-verification customer RPCs verification complete' AS result;
