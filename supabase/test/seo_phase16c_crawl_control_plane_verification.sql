-- =============================================================================
-- SEO Phase 16C — Crawler Control Plane — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on the disposable Supabase TEST project (Digi_SEO_Test,
-- ref snyzotgwwfomgafrsvfm), AFTER migration 20260713120025
-- (seo_phase16c_crawl_control_plane) is applied.
--
-- EXECUTION MODEL: the `supabase db query --linked -f` runner wraps the WHOLE
-- file in ONE transaction, so this script uses NO explicit BEGIN/COMMIT/
-- ROLLBACK. It runs as the `postgres` connection role; the acting SEO user is
-- switched via jwt claims (set_config) so the RPCs' auth.uid()/role checks
-- evaluate per user. RLS direct-write tests additionally `SET LOCAL ROLE
-- authenticated` so row-level policies actually apply (postgres bypasses RLS).
-- The worker-claim function is service_role-only; postgres (superuser) may call
-- it to simulate the worker, and the authenticated/anon EXECUTE denial is proven
-- via has_function_privilege. All test rows are tagged with idempotency key
-- prefix 'PHASE16C-VERIFY-' and a disposable inactive website
-- (ac000000-…-099); teardown deletes them, so a successful run commits
-- net-nothing. Any failed assertion RAISEs and the runner rolls everything back.
-- No password/service-role key is used anywhere.
--
-- PREREQUISITE: the five shared TEST auth users exist on Digi_SEO_Test
-- (owner/admin/team/client/nonmember) and the UI-seed workspace/website exist.
-- =============================================================================

-- ---------- 0. Fixture ids + jwt-claims login helper -------------------------
SELECT set_config('seo16c.website',   '44444444-0000-0000-0002-000000000001', false);
SELECT set_config('seo16c.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('seo16c.inactive',  'ac000000-0000-0000-0002-000000000099', false);
SELECT set_config('seo16c.owner',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seo16c.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('seo16c.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('seo16c.client',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('seo16c.nonmember', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo16c_login(p_uid uuid)
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
   WHERE table_schema='public' AND table_name IN ('seo_crawl_jobs','seo_crawl_attempts','seo_crawl_events');
  IF n <> 3 THEN RAISE EXCEPTION 'STRUCT: expected 3 crawl tables, got %', n; END IF;

  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='public' AND c.relname IN ('seo_crawl_jobs','seo_crawl_attempts','seo_crawl_events') AND c.relrowsecurity;
  IF n <> 3 THEN RAISE EXCEPTION 'STRUCT: RLS not enabled on all 3 tables (got %)', n; END IF;

  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('seo_crawl_request','seo_crawl_cancel','seo_crawl_claim_job','seo_crawl_normalize_config','seo_crawl_job_integrity');
  IF n <> 5 THEN RAISE EXCEPTION 'STRUCT: expected 5 crawl functions, got %', n; END IF;

  -- active-per-website unique index + idempotency unique constraint
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_seo_crawl_jobs_active_per_website') THEN
    RAISE EXCEPTION 'STRUCT: active-per-website unique index missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='seo_crawl_jobs_idempotency_uniq') THEN
    RAISE EXCEPTION 'STRUCT: idempotency unique constraint missing'; END IF;

  -- events + attempts append-only: exactly one SELECT policy each, no ins/upd/del policy
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_crawl_events';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: seo_crawl_events must have exactly 1 (SELECT) policy, got %', n; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_crawl_attempts';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: seo_crawl_attempts must have exactly 1 (admin SELECT) policy, got %', n; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_crawl_jobs';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: seo_crawl_jobs must have exactly 1 (SELECT) policy, got %', n; END IF;

  -- grants: request/cancel = authenticated (not anon); claim = NOT authenticated/anon
  IF has_function_privilege('anon', 'public.seo_crawl_request(uuid,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: anon must NOT execute seo_crawl_request'; END IF;
  IF NOT has_function_privilege('authenticated', 'public.seo_crawl_request(uuid,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated must execute seo_crawl_request'; END IF;
  IF has_function_privilege('authenticated', 'public.seo_crawl_claim_job(text,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated must NOT execute seo_crawl_claim_job'; END IF;
  IF has_function_privilege('anon', 'public.seo_crawl_claim_job(text,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: anon must NOT execute seo_crawl_claim_job'; END IF;
  RAISE NOTICE 'STRUCT ok';
END $t$;

-- disposable inactive website in the seed workspace (for eligibility test)
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('seo16c.inactive')::uuid, current_setting('seo16c.workspace')::uuid,
        'https://phase16c-verify-inactive.example', 'PHASE16C Verify Inactive', 'PHASE16C Verify', 'other', 'pending', false)
ON CONFLICT (id) DO NOTHING;

-- ---------- 2. ENQUEUE ------------------------------------------------------
-- 2a. owner allowed → queued + correct snapshots + exactly one 'queued' event
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid;
        v_ws uuid := current_setting('seo16c.workspace')::uuid;
        v_uid uuid := current_setting('seo16c.owner')::uuid;
        v_job uuid; r public.seo_crawl_jobs%ROWTYPE; ev int;
BEGIN
  PERFORM public._seo16c_login(v_uid);
  v_job := public.seo_crawl_request(v_site, 'PHASE16C-VERIFY-owner', NULL);
  SELECT * INTO r FROM public.seo_crawl_jobs WHERE id = v_job;
  IF r.status <> 'queued' THEN RAISE EXCEPTION 'ENQ owner: status % (expected queued)', r.status; END IF;
  IF r.workspace_id <> v_ws THEN RAISE EXCEPTION 'ENQ owner: workspace not resolved server-side'; END IF;
  IF r.website_url <> 'https://ui-seed-digibility.example' THEN RAISE EXCEPTION 'ENQ owner: website_url snapshot wrong'; END IF;
  IF r.requested_by <> v_uid THEN RAISE EXCEPTION 'ENQ owner: requested_by not auth.uid()'; END IF;
  IF r.requested_role_snapshot <> 'owner' THEN RAISE EXCEPTION 'ENQ owner: role snapshot % (expected owner)', r.requested_role_snapshot; END IF;
  IF (r.config->>'max_pages') IS NULL OR (r.config->>'respect_robots') <> 'true' THEN RAISE EXCEPTION 'ENQ owner: config snapshot missing defaults'; END IF;
  SELECT count(*) INTO ev FROM public.seo_crawl_events WHERE job_id=v_job;
  IF ev <> 1 THEN RAISE EXCEPTION 'ENQ owner: expected exactly 1 event, got %', ev; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='queued' AND actor='customer') THEN
    RAISE EXCEPTION 'ENQ owner: initial queued/customer event missing'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id = v_job;  -- free the website for next test
  RAISE NOTICE 'ENQ owner ok';
END $t$;

-- 2b. admin allowed ; 2c. team_member allowed
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid; v_job uuid; v_role text;
BEGIN
  PERFORM public._seo16c_login(current_setting('seo16c.admin')::uuid);
  v_job := public.seo_crawl_request(v_site, 'PHASE16C-VERIFY-admin', NULL);
  SELECT requested_role_snapshot INTO v_role FROM public.seo_crawl_jobs WHERE id=v_job;
  IF v_role <> 'admin' THEN RAISE EXCEPTION 'ENQ admin: role snapshot %', v_role; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;

  PERFORM public._seo16c_login(current_setting('seo16c.team')::uuid);
  v_job := public.seo_crawl_request(v_site, 'PHASE16C-VERIFY-team', NULL);
  SELECT requested_role_snapshot INTO v_role FROM public.seo_crawl_jobs WHERE id=v_job;
  IF v_role <> 'team_member' THEN RAISE EXCEPTION 'ENQ team: role snapshot %', v_role; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'ENQ admin+team ok';
END $t$;

-- 2d. client denied ; 2e. non-member denied (== wrong-workspace: not a member of website's ws)
-- 2f. anonymous denied ; 2g. invalid website ; 2h. inactive website ineligible
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid;
        v_inactive uuid := current_setting('seo16c.inactive')::uuid; ok boolean;
BEGIN
  -- client
  PERFORM public._seo16c_login(current_setting('seo16c.client')::uuid);
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_site,'PHASE16C-VERIFY-client',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ENQ: client was allowed to request a crawl'; END IF;
  -- non-member / wrong workspace
  PERFORM public._seo16c_login(current_setting('seo16c.nonmember')::uuid);
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_site,'PHASE16C-VERIFY-nonmember',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ENQ: non-member was allowed (wrong-workspace not blocked)'; END IF;
  -- anonymous
  PERFORM public._seo16c_login(NULL);
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_site,'PHASE16C-VERIFY-anon',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ENQ: anonymous was allowed'; END IF;
  -- invalid website
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  ok := false; BEGIN PERFORM public.seo_crawl_request('99999999-0000-0000-0000-0000000000ff'::uuid,'PHASE16C-VERIFY-badsite',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ENQ: invalid website was accepted'; END IF;
  -- inactive website ineligible
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_inactive,'PHASE16C-VERIFY-inactive',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ENQ: inactive website was accepted'; END IF;
  RAISE NOTICE 'ENQ denials ok';
END $t$;

-- 2i. config validation: unsupported key + disabling robots rejected
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid; ok boolean;
BEGIN
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_site,'PHASE16C-VERIFY-cfg1','{"evil":1}'::jsonb); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CFG: unsupported config key accepted'; END IF;
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_site,'PHASE16C-VERIFY-cfg2','{"respect_robots":false}'::jsonb); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CFG: disabling respect_robots accepted'; END IF;
  RAISE NOTICE 'CFG validation ok';
END $t$;

-- 2j. duplicate active rejected ; same idempotency key returns SAME job
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid; j1 uuid; j2 uuid; ok boolean;
BEGIN
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  j1 := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-dup',NULL);
  -- same idempotency key → same job (idempotent)
  j2 := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-dup',NULL);
  IF j1 <> j2 THEN RAISE EXCEPTION 'DUP: same idempotency key did not return same job'; END IF;
  -- different key, still active → rejected by partial unique index
  ok := false; BEGIN PERFORM public.seo_crawl_request(v_site,'PHASE16C-VERIFY-dup2',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'DUP: a second active job for the same website was allowed'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=j1;
  RAISE NOTICE 'ENQ dedup/idempotency ok';
END $t$;

-- ---------- 3. DIRECT-WRITE RLS (customers cannot write job/attempt/event) --
-- create a target job as owner (RPC), then attempt direct writes as authenticated
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid; v_job uuid;
BEGIN
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  v_job := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-rls',NULL);
  PERFORM set_config('seo16c.rls_job', v_job::text, false);
END $t$;

SET LOCAL ROLE authenticated;
SELECT public._seo16c_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner
DO $t$
DECLARE v_ws uuid := current_setting('seo16c.workspace')::uuid;
        v_site uuid := current_setting('seo16c.website')::uuid;
        v_job uuid := current_setting('seo16c.rls_job')::uuid; ok boolean; rc int;
BEGIN
  -- cannot INSERT a job directly (no INSERT policy)
  ok := false; BEGIN INSERT INTO public.seo_crawl_jobs(workspace_id,website_id,website_url,requested_role_snapshot,idempotency_key)
    VALUES(v_ws,v_site,'https://x','owner','PHASE16C-VERIFY-direct'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated directly INSERTed a job'; END IF;
  -- cannot UPDATE status (no update policy → 0 rows)
  UPDATE public.seo_crawl_jobs SET status='completed' WHERE id=v_job; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated UPDATEd a job (% rows)', rc; END IF;
  -- cannot DELETE (0 rows)
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated DELETEd a job (% rows)', rc; END IF;
  -- cannot INSERT an event (append-only, no insert policy)
  ok := false; BEGIN INSERT INTO public.seo_crawl_events(job_id,workspace_id,website_id,event_type,actor)
    VALUES(v_job,v_ws,v_site,'progress','customer'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated INSERTed an event'; END IF;
  -- cannot UPDATE/DELETE events
  UPDATE public.seo_crawl_events SET note='x' WHERE job_id=v_job; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated UPDATEd an event'; END IF;
  DELETE FROM public.seo_crawl_events WHERE job_id=v_job; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated DELETEd an event'; END IF;
  -- cannot INSERT an attempt; cannot READ attempts (internal diagnostics, admin-only)
  ok := false; BEGIN INSERT INTO public.seo_crawl_attempts(job_id,workspace_id,attempt_number) VALUES(v_job,v_ws,1); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated INSERTed an attempt'; END IF;
  RAISE NOTICE 'RLS direct-write denial ok';
END $t$;

-- data isolation reads (still as authenticated)
DO $t$
DECLARE v_job uuid := current_setting('seo16c.rls_job')::uuid; n int;
BEGIN
  -- owner (member) sees the job + its event
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE id=v_job;
  IF n <> 1 THEN RAISE EXCEPTION 'ISO: owner member cannot read own-workspace job'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=v_job;
  IF n < 1 THEN RAISE EXCEPTION 'ISO: owner member cannot read job events'; END IF;
  -- owner (non-global-admin) cannot read internal attempts
  SELECT count(*) INTO n FROM public.seo_crawl_attempts WHERE job_id=v_job;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: non-admin read internal attempts (%)', n; END IF;
  -- client (member) sees the job
  PERFORM public._seo16c_login(current_setting('seo16c.client')::uuid);
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE id=v_job;
  IF n <> 1 THEN RAISE EXCEPTION 'ISO: client member cannot read workspace job'; END IF;
  -- non-member sees nothing
  PERFORM public._seo16c_login(current_setting('seo16c.nonmember')::uuid);
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE id=v_job;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: non-member read a job (%)', n; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=v_job;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: non-member read job events (%)', n; END IF;
  RAISE NOTICE 'ISO reads ok';
END $t$;
RESET ROLE;
DELETE FROM public.seo_crawl_jobs WHERE id = current_setting('seo16c.rls_job')::uuid;

-- ---------- 4. CANCELLATION -------------------------------------------------
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid; v_job uuid; st text; ev int; ok boolean;
BEGIN
  -- 4a. owner cancels a queued job → cancelled + exactly one cancel event; idempotent repeat
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  v_job := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-cancel',NULL);
  st := public.seo_crawl_cancel(v_job);
  IF st <> 'cancelled' THEN RAISE EXCEPTION 'CANCEL: queued cancel → % (expected cancelled)', st; END IF;
  SELECT count(*) INTO ev FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='cancelled';
  IF ev <> 1 THEN RAISE EXCEPTION 'CANCEL: expected 1 cancelled event, got %', ev; END IF;
  -- idempotent repeat: terminal → same status, NO new event (total events unchanged = 2: queued+cancelled)
  st := public.seo_crawl_cancel(v_job);
  IF st <> 'cancelled' THEN RAISE EXCEPTION 'CANCEL: idempotent repeat → %', st; END IF;
  SELECT count(*) INTO ev FROM public.seo_crawl_events WHERE job_id=v_job;
  IF ev <> 2 THEN RAISE EXCEPTION 'CANCEL: idempotent repeat added an event (total %)', ev; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;

  -- 4b. client denied ; non-member denied
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  v_job := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-cancel2',NULL);
  PERFORM public._seo16c_login(current_setting('seo16c.client')::uuid);
  ok:=false; BEGIN PERFORM public.seo_crawl_cancel(v_job); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CANCEL: client was allowed to cancel'; END IF;
  PERFORM public._seo16c_login(current_setting('seo16c.nonmember')::uuid);
  ok:=false; BEGIN PERFORM public.seo_crawl_cancel(v_job); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CANCEL: non-member was allowed to cancel'; END IF;

  -- 4c. running job → cancellation_requested (worker finalizes), one event
  UPDATE public.seo_crawl_jobs SET status='running', claimed_at=now(), started_at=now() WHERE id=v_job;
  PERFORM public._seo16c_login(current_setting('seo16c.admin')::uuid);
  st := public.seo_crawl_cancel(v_job);
  IF st <> 'cancellation_requested' THEN RAISE EXCEPTION 'CANCEL: running cancel → % (expected cancellation_requested)', st; END IF;
  SELECT count(*) INTO ev FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='cancellation_requested';
  IF ev <> 1 THEN RAISE EXCEPTION 'CANCEL: expected 1 cancellation_requested event, got %', ev; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'CANCEL ok';
END $t$;

-- ---------- 5. WORKER CLAIM (service-role contract; postgres simulates) -----
DO $t$
DECLARE v_site uuid := current_setting('seo16c.website')::uuid; v_job uuid; n int; st text; att int;
BEGIN
  -- 5a. atomic claim of a queued job → running, attempt #1, lease, 'claimed' event
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  v_job := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-claim',NULL);
  SELECT count(*) INTO n FROM public.seo_crawl_claim_job('worker-A', 300);
  IF n <> 1 THEN RAISE EXCEPTION 'CLAIM: expected to claim 1 job, got %', n; END IF;
  SELECT status, attempt_count INTO st, att FROM public.seo_crawl_jobs WHERE id=v_job;
  IF st <> 'running' OR att <> 1 THEN RAISE EXCEPTION 'CLAIM: job status/attempt = %/% (expected running/1)', st, att; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_attempts WHERE job_id=v_job AND attempt_number=1 AND worker_id='worker-A' AND lease_expires_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CLAIM: attempt/lease row missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='claimed' AND actor='worker') THEN
    RAISE EXCEPTION 'CLAIM: claimed/worker event missing'; END IF;
  -- 5b. second claim cannot re-claim (no queued/retry job left)
  SELECT count(*) INTO n FROM public.seo_crawl_claim_job('worker-B', 300);
  IF n <> 0 THEN RAISE EXCEPTION 'CLAIM: a running job was re-claimed (%)', n; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;

  -- 5c. cancellation_requested job is NOT claimed
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  v_job := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-claimcancel',NULL);
  UPDATE public.seo_crawl_jobs SET status='cancellation_requested', cancellation_requested_at=now() WHERE id=v_job;
  SELECT count(*) INTO n FROM public.seo_crawl_claim_job('worker-C', 300);
  IF n <> 0 THEN RAISE EXCEPTION 'CLAIM: cancellation_requested job was claimed'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;

  -- 5d. retry filtering: future retry_after not claimed; past retry_after claimed
  PERFORM public._seo16c_login(current_setting('seo16c.owner')::uuid);
  v_job := public.seo_crawl_request(v_site,'PHASE16C-VERIFY-retry',NULL);
  UPDATE public.seo_crawl_jobs SET status='retry_wait', retry_after=now()+interval '1 hour' WHERE id=v_job;
  SELECT count(*) INTO n FROM public.seo_crawl_claim_job('worker-D', 300);
  IF n <> 0 THEN RAISE EXCEPTION 'CLAIM: retry_wait with future retry_after was claimed'; END IF;
  UPDATE public.seo_crawl_jobs SET retry_after=now()-interval '1 minute' WHERE id=v_job;
  SELECT count(*) INTO n FROM public.seo_crawl_claim_job('worker-E', 300);
  IF n <> 1 THEN RAISE EXCEPTION 'CLAIM: retry-ready job (past retry_after) was NOT claimed'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'CLAIM ok';
END $t$;

-- ---------- 6. TEARDOWN -----------------------------------------------------
DELETE FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16C-VERIFY-%';
DELETE FROM public.seo_websites WHERE id = current_setting('seo16c.inactive')::uuid;
DROP FUNCTION IF EXISTS public._seo16c_login(uuid);

DO $t$
DECLARE nj int; ne int; na int; nw int;
BEGIN
  SELECT count(*) INTO nj FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16C-VERIFY-%';
  SELECT count(*) INTO ne FROM public.seo_crawl_events e JOIN public.seo_crawl_jobs j ON j.id=e.job_id WHERE j.idempotency_key LIKE 'PHASE16C-VERIFY-%';
  SELECT count(*) INTO na FROM public.seo_crawl_attempts a JOIN public.seo_crawl_jobs j ON j.id=a.job_id WHERE j.idempotency_key LIKE 'PHASE16C-VERIFY-%';
  SELECT count(*) INTO nw FROM public.seo_websites WHERE id = 'ac000000-0000-0000-0002-000000000099';
  IF nj+ne+na+nw <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual rows jobs=% events=% attempts=% inactive_site=%', nj, ne, na, nw; END IF;
END $t$;

SELECT 'ALL PASS — seo_phase16c crawl control-plane verification complete' AS result;
