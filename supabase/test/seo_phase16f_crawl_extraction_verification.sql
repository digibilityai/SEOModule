-- =============================================================================
-- SEO Phase 16F — Crawl Extraction + Issues — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****  DO NOT RUN ON PRODUCTION ****
-- RUN ONLY on Digi_SEO_Test, AFTER migration 20260714120028. Single-transaction
-- runner; worker RPCs are service_role-only (postgres simulates the worker; the
-- authenticated/anon denial is proven via has_function_privilege). Jobs tagged
-- 'PHASE16F-VERIFY-'; teardown cascades snapshots/issues.
-- =============================================================================
SELECT set_config('seo16f.website', '44444444-0000-0000-0002-000000000001', false);
SELECT set_config('seo16f.owner',   '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('seo16f.nonmember','8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo16f_login(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role','authenticated')::text, true);
END $fn$;

-- 1. STRUCTURE + GRANTS
DO $t$
DECLARE n int;
BEGIN
  IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('seo_crawl_page_snapshots','seo_crawl_issues')) <> 2
    THEN RAISE EXCEPTION 'STRUCT: expected 2 tables'; END IF;
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='public' AND c.relname IN ('seo_crawl_page_snapshots','seo_crawl_issues') AND c.relrowsecurity) <> 2
    THEN RAISE EXCEPTION 'STRUCT: RLS not enabled'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname IN ('seo_crawl_worker_record_snapshots','seo_crawl_worker_record_issues','seo_crawl_worker_update_extraction_progress')) <> 3
    THEN RAISE EXCEPTION 'STRUCT: expected 3 fns'; END IF;
  IF has_function_privilege('authenticated','public.seo_crawl_worker_record_snapshots(uuid,text,uuid,jsonb)','EXECUTE')
    OR has_function_privilege('anon','public.seo_crawl_worker_record_issues(uuid,text,uuid,jsonb,uuid)','EXECUTE')
    THEN RAISE EXCEPTION 'GRANT: worker fns executable by authenticated/anon'; END IF;
  RAISE NOTICE 'STRUCT+GRANTS ok';
END $t$;

-- P1b fixture: seed VERIFIED domain-ownership for the seed website so
-- seo_crawl_request passes the P1b verified-only gate (migration 20260719120034).
-- Idempotent; token-marked for self-cleaning teardown; runs as postgres (setup).
INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at)
SELECT w.workspace_id, w.id, w.website_url, 'p1b-fixture.example', 'dns_txt', 'verified', 'P1B-FIXTURE-TOKEN', now()
  FROM public.seo_websites w WHERE w.id = current_setting('seo16f.website')::uuid
ON CONFLICT (website_id, method) DO UPDATE
  SET status='verified', challenge_token='P1B-FIXTURE-TOKEN', verified_at=now(), updated_at=now();

-- 2. HAPPY PATH: snapshots + page issue + site issue + idempotency + integrity
DO $t$
DECLARE v_job uuid; v_tok uuid; v_snap uuid; n int; ok boolean;
BEGIN
  PERFORM public._seo16f_login(current_setting('seo16f.owner')::uuid);
  v_job := public.seo_crawl_request(current_setting('seo16f.website')::uuid, 'PHASE16F-VERIFY-happy', NULL);
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-F', 60);

  n := public.seo_crawl_worker_record_snapshots(v_job,'worker-F',v_tok,
    '[{"requestedUrl":"https://ui-seed-digibility.example/","finalUrl":"https://ui-seed-digibility.example/","httpStatus":200,"decodeStatus":"ok","titleCount":1,"title":"T","effectiveIndex":true,"wordCount":50,"contentHash":"abc","extractionStatus":"extracted","extractorVersion":"1.0.0","canonicalClass":"self"},
      {"requestedUrl":"https://ui-seed-digibility.example/a","httpStatus":200,"decodeStatus":"ok","titleCount":0,"effectiveIndex":true,"extractionStatus":"extracted","extractorVersion":"1.0.0"}]'::jsonb);
  IF n <> 2 THEN RAISE EXCEPTION 'SNAP: expected 2, got %', n; END IF;
  -- workspace/website derived server-side
  IF (SELECT count(*) FROM public.seo_crawl_page_snapshots WHERE job_id=v_job AND workspace_id='44444444-0000-0000-0001-000000000001') <> 2 THEN
    RAISE EXCEPTION 'SNAP: workspace not derived'; END IF;
  -- idempotent upsert
  PERFORM public.seo_crawl_worker_record_snapshots(v_job,'worker-F',v_tok,'[{"requestedUrl":"https://ui-seed-digibility.example/","title":"T2","extractorVersion":"1.0.0"}]'::jsonb);
  SELECT count(*) INTO n FROM public.seo_crawl_page_snapshots WHERE job_id=v_job;
  IF n <> 2 THEN RAISE EXCEPTION 'SNAP: upsert created duplicate (%)', n; END IF;

  SELECT id INTO v_snap FROM public.seo_crawl_page_snapshots WHERE job_id=v_job AND requested_url='https://ui-seed-digibility.example/a';

  -- page issue (valid snapshot)
  n := public.seo_crawl_worker_record_issues(v_job,'worker-F',v_tok,
    '[{"code":"TITLE_MISSING","category":"metadata","severity":"error","scope":"page","ruleVersion":"1.0.0","fingerprint":"https://ui-seed-digibility.example/a","summary":"Missing title","evidence":{}}]'::jsonb, v_snap);
  IF n <> 1 THEN RAISE EXCEPTION 'ISSUE: page issue not recorded'; END IF;
  -- idempotent
  PERFORM public.seo_crawl_worker_record_issues(v_job,'worker-F',v_tok,
    '[{"code":"TITLE_MISSING","category":"metadata","severity":"error","scope":"page","ruleVersion":"1.0.0","fingerprint":"https://ui-seed-digibility.example/a"}]'::jsonb, v_snap);
  SELECT count(*) INTO n FROM public.seo_crawl_issues WHERE job_id=v_job AND issue_code='TITLE_MISSING';
  IF n <> 1 THEN RAISE EXCEPTION 'ISSUE: page issue duplicated on rerun (%)', n; END IF;

  -- site issue (null snapshot)
  PERFORM public.seo_crawl_worker_record_issues(v_job,'worker-F',v_tok,
    '[{"code":"DUPLICATE_TITLE","category":"duplicate","severity":"warning","scope":"site","ruleVersion":"1.0.0","fingerprint":"grp1","evidence":{"pageCount":2}}]'::jsonb, NULL);
  IF (SELECT page_snapshot_id FROM public.seo_crawl_issues WHERE job_id=v_job AND issue_code='DUPLICATE_TITLE') IS NOT NULL THEN
    RAISE EXCEPTION 'ISSUE: site issue must have null snapshot'; END IF;

  -- unknown issue code rejected (CHECK)
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_record_issues(v_job,'worker-F',v_tok,'[{"code":"lowercase_bad","category":"x","severity":"info","scope":"site","ruleVersion":"1","fingerprint":"f"}]'::jsonb, NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ISSUE: invalid issue_code accepted'; END IF;
  -- oversized evidence rejected (CHECK octet_length<=8192)
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_record_issues(v_job,'worker-F',v_tok, ('[{"code":"LOW_CONTENT","category":"content","severity":"info","scope":"site","ruleVersion":"1","fingerprint":"big","evidence":{"blob":"'||repeat('x',9000)||'"}}]')::jsonb, NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ISSUE: oversized evidence accepted'; END IF;
  -- lease-token mismatch denied
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_record_snapshots(v_job,'worker-F',gen_random_uuid(),'[]'::jsonb); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'SNAP: stale token accepted'; END IF;

  -- progress bounded + status unchanged
  PERFORM public.seo_crawl_worker_update_extraction_progress(v_job,'worker-F',v_tok,'{"pagesExtracted":2,"issuesDetected":1}'::jsonb);
  IF (SELECT status FROM public.seo_crawl_jobs WHERE id=v_job) <> 'running' THEN RAISE EXCEPTION 'PROGRESS: status changed'; END IF;

  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'HAPPY ok';
END $t$;

-- 3. CUSTOMER read + direct-write denial + non-member isolation
DO $t$
DECLARE v_job uuid; v_tok uuid; v_snap uuid;
BEGIN
  PERFORM public._seo16f_login(current_setting('seo16f.owner')::uuid);
  v_job := public.seo_crawl_request(current_setting('seo16f.website')::uuid, 'PHASE16F-VERIFY-rls', NULL);
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-F2', 60);
  PERFORM public.seo_crawl_worker_record_snapshots(v_job,'worker-F2',v_tok,'[{"requestedUrl":"https://ui-seed-digibility.example/rls","extractorVersion":"1.0.0"}]'::jsonb);
  SELECT id INTO v_snap FROM public.seo_crawl_page_snapshots WHERE job_id=v_job LIMIT 1;
  PERFORM public.seo_crawl_worker_record_issues(v_job,'worker-F2',v_tok,'[{"code":"CANONICAL_MISSING","category":"canonical","severity":"info","scope":"page","ruleVersion":"1.0.0","fingerprint":"u"}]'::jsonb, v_snap);
  PERFORM set_config('seo16f.rlsjob', v_job::text, false);
END $t$;

SET LOCAL ROLE authenticated;
SELECT public._seo16f_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid); -- owner member
DO $t$
DECLARE v_job uuid := current_setting('seo16f.rlsjob')::uuid; ok boolean; rc int; n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_page_snapshots WHERE job_id=v_job;
  IF n < 1 THEN RAISE EXCEPTION 'ISO: member cannot read snapshots'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_issues WHERE job_id=v_job;
  IF n < 1 THEN RAISE EXCEPTION 'ISO: member cannot read issues'; END IF;
  ok:=false; BEGIN INSERT INTO public.seo_crawl_issues(job_id,workspace_id,website_id,issue_code,category,severity,scope,rule_version,fingerprint)
    VALUES(v_job,'44444444-0000-0000-0001-000000000001','44444444-0000-0000-0002-000000000001','TITLE_MISSING','metadata','error','site','1','f'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated inserted an issue'; END IF;
  UPDATE public.seo_crawl_page_snapshots SET title='hax' WHERE job_id=v_job; GET DIAGNOSTICS rc=ROW_COUNT;
  IF rc <> 0 THEN RAISE EXCEPTION 'RLS: authenticated updated a snapshot'; END IF;
END $t$;
SELECT public._seo16f_login('8ae3b67e-6f00-4e10-905c-3a76281ffde9'::uuid); -- non-member
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_page_snapshots WHERE job_id=current_setting('seo16f.rlsjob')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: non-member read snapshots (%)', n; END IF;
END $t$;
RESET ROLE;
DELETE FROM public.seo_crawl_jobs WHERE id=current_setting('seo16f.rlsjob')::uuid;

-- 4. TEARDOWN
DELETE FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16F-VERIFY-%';
DROP FUNCTION IF EXISTS public._seo16f_login(uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16F-VERIFY-%';
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual jobs %', n; END IF;
END $t$;
-- P1b fixture cleanup (token-marked; postgres context).
RESET ROLE;
DELETE FROM public.seo_ownership_verifications WHERE challenge_token = 'P1B-FIXTURE-TOKEN';
SELECT 'ALL PASS — seo_phase16f crawl extraction verification complete' AS result;
