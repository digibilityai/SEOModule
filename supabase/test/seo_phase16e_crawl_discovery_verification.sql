-- =============================================================================
-- SEO Phase 16E — Crawl Discovery Storage — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
-- RUN ONLY on Digi_SEO_Test, AFTER migration 20260714120027. Single-transaction
-- runner. Worker RPCs are service_role-only (postgres/superuser simulates the
-- worker; the authenticated/anon denial is proven via has_function_privilege).
-- Jobs tagged 'PHASE16E-VERIFY-'; teardown removes them (cascades discovery rows).
-- =============================================================================
SELECT set_config('seo16e.website', '44444444-0000-0000-0002-000000000001', false);
SELECT set_config('seo16e.workspace','44444444-0000-0000-0001-000000000001', false);
SELECT set_config('seo16e.owner',   '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seo16e.client',  '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('seo16e.nonmember','8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo16e_login(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role','authenticated')::text, true);
END $fn$;

-- 1. STRUCTURE + GRANTS
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.tables WHERE table_schema='public'
    AND table_name IN ('seo_crawl_discovered_pages','seo_crawl_sitemaps');
  IF n <> 2 THEN RAISE EXCEPTION 'STRUCT: expected 2 discovery tables, got %', n; END IF;
  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
    WHERE ns.nspname='public' AND c.relname IN ('seo_crawl_discovered_pages','seo_crawl_sitemaps') AND c.relrowsecurity;
  IF n <> 2 THEN RAISE EXCEPTION 'STRUCT: RLS not enabled on both discovery tables'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='seo_crawl_discovered_pages_uniq') THEN
    RAISE EXCEPTION 'STRUCT: unique(job_id,normalized_url) missing'; END IF;
  -- each discovery table: exactly one SELECT policy, no write policy
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_crawl_discovered_pages';
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: discovered_pages must have 1 policy'; END IF;
  IF has_function_privilege('authenticated','public.seo_crawl_worker_record_discovery(uuid,text,uuid,jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.seo_crawl_worker_record_discovery(uuid,text,uuid,jsonb,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: record_discovery must not be executable by authenticated/anon'; END IF;
  IF NOT has_function_privilege('service_role','public.seo_crawl_worker_update_discovery_progress(uuid,text,uuid,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: service_role must execute progress RPC'; END IF;
  RAISE NOTICE 'STRUCT+GRANTS ok';
END $t$;

-- P1b fixture: seed VERIFIED domain-ownership for the seed website so
-- seo_crawl_request passes the P1b verified-only gate (migration 20260719120034).
-- Idempotent; token-marked for self-cleaning teardown; runs as postgres (setup).
INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at)
SELECT w.workspace_id, w.id, w.website_url, 'p1b-fixture.example', 'dns_txt', 'verified', 'P1B-FIXTURE-TOKEN', now()
  FROM public.seo_websites w WHERE w.id = current_setting('seo16e.website')::uuid
ON CONFLICT (website_id, method) DO UPDATE
  SET status='verified', challenge_token='P1B-FIXTURE-TOKEN', verified_at=now(), updated_at=now();

-- 2. HAPPY PATH: claim → record pages+sitemaps → progress
DO $t$
DECLARE v_job uuid; v_tok uuid; v_ws uuid := current_setting('seo16e.workspace')::uuid; n int; st text;
BEGIN
  PERFORM public._seo16e_login(current_setting('seo16e.owner')::uuid);
  v_job := public.seo_crawl_request(current_setting('seo16e.website')::uuid, 'PHASE16E-VERIFY-happy', NULL);
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-E', 60);

  n := public.seo_crawl_worker_record_discovery(v_job,'worker-E',v_tok,
    '[{"normalizedUrl":"https://ui-seed-digibility.example/","discoveredUrl":"https://ui-seed-digibility.example/","discoverySource":"start","depth":0,"queueOrder":0,"robotsDecision":"allowed","fetchStatus":"fetched","httpStatus":200,"contentType":"text/html","responseBytes":10},
      {"normalizedUrl":"https://ui-seed-digibility.example/a","discoveredUrl":"https://ui-seed-digibility.example/a","discoverySource":"sitemap","depth":0,"queueOrder":1,"fetchStatus":"queued"}]'::jsonb,
    '[{"sitemapUrl":"https://ui-seed-digibility.example/sitemap.xml","sitemapType":"urlset","fetchStatus":"parsed","urlsDiscovered":1,"depth":0}]'::jsonb);
  IF n <> 2 THEN RAISE EXCEPTION 'RECORD: expected 2 pages upserted, got %', n; END IF;
  -- workspace/website derived server-side, not from caller
  SELECT count(*) INTO n FROM public.seo_crawl_discovered_pages WHERE job_id=v_job AND workspace_id=v_ws;
  IF n <> 2 THEN RAISE EXCEPTION 'RECORD: pages not scoped to job workspace (%)', n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_sitemaps WHERE job_id=v_job AND fetch_status='parsed') THEN
    RAISE EXCEPTION 'RECORD: sitemap row missing'; END IF;

  -- idempotent upsert: re-record the same normalized_url updates, no duplicate
  PERFORM public.seo_crawl_worker_record_discovery(v_job,'worker-E',v_tok,
    '[{"normalizedUrl":"https://ui-seed-digibility.example/a","discoveredUrl":"x","discoverySource":"sitemap","fetchStatus":"fetched","httpStatus":200}]'::jsonb, '[]'::jsonb);
  SELECT count(*) INTO n FROM public.seo_crawl_discovered_pages WHERE job_id=v_job AND normalized_url='https://ui-seed-digibility.example/a';
  IF n <> 1 THEN RAISE EXCEPTION 'RECORD: upsert created a duplicate URL row (%)', n; END IF;
  IF (SELECT fetch_status FROM public.seo_crawl_discovered_pages WHERE job_id=v_job AND normalized_url='https://ui-seed-digibility.example/a') <> 'fetched' THEN
    RAISE EXCEPTION 'RECORD: upsert did not update fetch_status'; END IF;

  -- progress update (bounded; does not change status/ownership)
  PERFORM public.seo_crawl_worker_update_discovery_progress(v_job,'worker-E',v_tok,'{"urlsDiscovered":5,"pagesFetched":2}'::jsonb);
  SELECT status INTO st FROM public.seo_crawl_jobs WHERE id=v_job;
  IF st <> 'running' THEN RAISE EXCEPTION 'PROGRESS: status changed to %', st; END IF;
  IF (SELECT pages_crawled FROM public.seo_crawl_jobs WHERE id=v_job) <> 2 THEN RAISE EXCEPTION 'PROGRESS: pages_crawled not updated'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'RECORD/PROGRESS ok';
END $t$;

-- 3. lease-token mismatch denied (explicit)
DO $t$
DECLARE v_job uuid; v_tok uuid; ok boolean;
BEGIN
  PERFORM public._seo16e_login(current_setting('seo16e.owner')::uuid);
  v_job := public.seo_crawl_request(current_setting('seo16e.website')::uuid, 'PHASE16E-VERIFY-token', NULL);
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-E2', 60);
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_record_discovery(v_job,'worker-E2',gen_random_uuid(),'[]'::jsonb,'[]'::jsonb); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'TOKEN: record with wrong lease token accepted'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'TOKEN mismatch ok';
END $t$;

-- 4. CUSTOMER direct-write denied + read isolation
DO $t$
DECLARE v_job uuid; v_tok uuid;
BEGIN
  PERFORM public._seo16e_login(current_setting('seo16e.owner')::uuid);
  v_job := public.seo_crawl_request(current_setting('seo16e.website')::uuid, 'PHASE16E-VERIFY-rls', NULL);
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-E3', 60);
  PERFORM public.seo_crawl_worker_record_discovery(v_job,'worker-E3',v_tok,
    '[{"normalizedUrl":"https://ui-seed-digibility.example/rls","discoveredUrl":"x","discoverySource":"start","fetchStatus":"fetched"}]'::jsonb,'[]'::jsonb);
  PERFORM set_config('seo16e.rlsjob', v_job::text, false);
END $t$;

SET LOCAL ROLE authenticated;
SELECT public._seo16e_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner (member)
DO $t$
DECLARE v_job uuid := current_setting('seo16e.rlsjob')::uuid; ok boolean; rc int; n int;
BEGIN
  -- member reads own-workspace discovery rows
  SELECT count(*) INTO n FROM public.seo_crawl_discovered_pages WHERE job_id=v_job;
  IF n < 1 THEN RAISE EXCEPTION 'ISO: member cannot read own-workspace discovered pages'; END IF;
  -- cannot INSERT
  ok:=false; BEGIN INSERT INTO public.seo_crawl_discovered_pages(job_id,workspace_id,website_id,normalized_url,discovered_url,discovery_source)
    VALUES(v_job, current_setting('seo16e.workspace')::uuid, current_setting('seo16e.website')::uuid,'https://x/y','y','start'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated inserted a discovered page'; END IF;
  -- cannot UPDATE/DELETE (0 rows)
  UPDATE public.seo_crawl_discovered_pages SET fetch_status='skipped' WHERE job_id=v_job; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated updated discovered pages'; END IF;
  DELETE FROM public.seo_crawl_discovered_pages WHERE job_id=v_job; GET DIAGNOSTICS rc = ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated deleted discovered pages'; END IF;
END $t$;
-- non-member sees nothing
SELECT public._seo16e_login('8ae3b67e-6f00-4e10-905c-3a76281ffde9'::uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_discovered_pages WHERE job_id=current_setting('seo16e.rlsjob')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: non-member read discovered pages (%)', n; END IF;
END $t$;
RESET ROLE;
DELETE FROM public.seo_crawl_jobs WHERE id = current_setting('seo16e.rlsjob')::uuid;

-- 5. TEARDOWN
DELETE FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16E-VERIFY-%';
DROP FUNCTION IF EXISTS public._seo16e_login(uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16E-VERIFY-%';
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual jobs %', n; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_discovered_pages dp JOIN public.seo_crawl_jobs j ON j.id=dp.job_id WHERE j.idempotency_key LIKE 'PHASE16E-VERIFY-%';
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual discovered pages %', n; END IF;
END $t$;
-- P1b fixture cleanup (token-marked; postgres context).
RESET ROLE;
DELETE FROM public.seo_ownership_verifications WHERE challenge_token = 'P1B-FIXTURE-TOKEN';
SELECT 'ALL PASS — seo_phase16e crawl discovery verification complete' AS result;
