-- =============================================================================
-- SEO Phase 16D — Crawler Worker Lifecycle + Lease — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER migration
-- 20260714120026. Single-transaction runner (no BEGIN/COMMIT/ROLLBACK); runs as
-- postgres. Customer RPCs use jwt-claims login; worker lifecycle functions are
-- service_role-only and are called directly (postgres/superuser bypasses the
-- grant; the authenticated/anon denial is proven via has_function_privilege).
-- All jobs tagged 'PHASE16D-VERIFY-'; teardown removes them → commits net-nothing.
-- =============================================================================

SELECT set_config('seo16d.website', '44444444-0000-0000-0002-000000000001', false);
SELECT set_config('seo16d.owner',   '48c479db-aedf-452e-af43-05ed1180baaa', false);

CREATE OR REPLACE FUNCTION public._seo16d_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $fn$;

-- ---------- 1. STRUCTURE + GRANTS -------------------------------------------
DO $t$
DECLARE n int;
BEGIN
  IF (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='seo_crawl_jobs' AND column_name='lease_token') <> 1
     OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='seo_crawl_attempts' AND column_name='lease_token') <> 1 THEN
    RAISE EXCEPTION 'STRUCT: lease_token columns missing'; END IF;
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
    ('seo_crawl_worker_heartbeat','seo_crawl_worker_complete','seo_crawl_worker_partial',
     'seo_crawl_worker_fail','seo_crawl_worker_schedule_retry','seo_crawl_worker_acknowledge_cancellation','seo_crawl_recover_stale_jobs');
  IF n <> 7 THEN RAISE EXCEPTION 'STRUCT: expected 7 lifecycle fns, got %', n; END IF;
  IF has_function_privilege('authenticated','public.seo_crawl_worker_heartbeat(uuid,text,uuid,integer,integer,integer)','EXECUTE')
     OR has_function_privilege('anon','public.seo_crawl_worker_complete(uuid,text,uuid,integer)','EXECUTE')
     OR has_function_privilege('authenticated','public.seo_crawl_recover_stale_jobs(timestamptz,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: worker fns must NOT be executable by authenticated/anon'; END IF;
  IF NOT has_function_privilege('service_role','public.seo_crawl_worker_complete(uuid,text,uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: service_role must execute worker fns'; END IF;
  RAISE NOTICE 'STRUCT+GRANTS ok';
END $t$;

-- helper: create a queued job as owner and return its id
CREATE OR REPLACE FUNCTION public._seo16d_new_job(p_key text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid;
BEGIN
  PERFORM public._seo16d_login(current_setting('seo16d.owner')::uuid);
  v := public.seo_crawl_request(current_setting('seo16d.website')::uuid, p_key, NULL);
  RETURN v;
END $fn$;

-- ---------- 2. HAPPY PATH: claim → heartbeat → complete ---------------------
DO $t$
DECLARE v_job uuid; v_tok uuid; v_lease timestamptz; v_new_lease timestamptz; st text; n int; att_outcome text;
BEGIN
  v_job := public._seo16d_new_job('PHASE16D-VERIFY-happy');
  SELECT lease_token, lease_expires_at INTO v_tok, v_lease FROM public.seo_crawl_claim_job('worker-A', 60);
  IF v_tok IS NULL THEN RAISE EXCEPTION 'HAPPY: claim did not return a lease_token'; END IF;
  IF (SELECT lease_token FROM public.seo_crawl_jobs WHERE id=v_job) <> v_tok THEN RAISE EXCEPTION 'HAPPY: job lease_token not persisted'; END IF;
  -- heartbeat extends lease, adds NO event
  v_new_lease := public.seo_crawl_worker_heartbeat(v_job, 'worker-A', v_tok, 120, 5, 10);
  IF v_new_lease <= v_lease THEN RAISE EXCEPTION 'HAPPY: heartbeat did not extend lease'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=v_job;  -- queued + claimed only
  IF n <> 2 THEN RAISE EXCEPTION 'HAPPY: heartbeat should add no event (events=%)', n; END IF;
  -- complete
  st := public.seo_crawl_worker_complete(v_job, 'worker-A', v_tok, 5);
  IF st <> 'completed' THEN RAISE EXCEPTION 'HAPPY: complete → %', st; END IF;
  IF (SELECT status FROM public.seo_crawl_jobs WHERE id=v_job) <> 'completed'
     OR (SELECT lease_token FROM public.seo_crawl_jobs WHERE id=v_job) IS NOT NULL THEN
    RAISE EXCEPTION 'HAPPY: job not completed / lease not cleared'; END IF;
  SELECT outcome INTO att_outcome FROM public.seo_crawl_attempts WHERE job_id=v_job AND attempt_number=1;
  IF att_outcome <> 'succeeded' THEN RAISE EXCEPTION 'HAPPY: attempt outcome % (expected succeeded)', att_outcome; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='completed';
  IF n <> 1 THEN RAISE EXCEPTION 'HAPPY: expected exactly 1 completed event, got %', n; END IF;
  -- idempotent complete: no duplicate event, still completed
  st := public.seo_crawl_worker_complete(v_job, 'worker-A', v_tok, 5);
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='completed';
  IF n <> 1 THEN RAISE EXCEPTION 'HAPPY: idempotent complete added a duplicate event'; END IF;
  -- heartbeat after terminal is rejected
  BEGIN v_new_lease := public.seo_crawl_worker_heartbeat(v_job,'worker-A',v_tok,120); RAISE EXCEPTION 'HAPPY: heartbeat allowed after completion';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'HAPPY:%' THEN RAISE; END IF; END;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'HAPPY path ok';
END $t$;

-- ---------- 3. LEASE-TOKEN MISMATCH (stale worker) --------------------------
DO $t$
DECLARE v_job uuid; v_tok uuid; ok boolean;
BEGIN
  v_job := public._seo16d_new_job('PHASE16D-VERIFY-mismatch');
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-A', 60);
  -- wrong token → heartbeat + complete denied
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_heartbeat(v_job,'worker-A', gen_random_uuid(), 60); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'MISMATCH: heartbeat with wrong token accepted'; END IF;
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_complete(v_job,'worker-A', gen_random_uuid(), 1); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'MISMATCH: complete with wrong token accepted'; END IF;
  -- correct token still works
  PERFORM public.seo_crawl_worker_complete(v_job,'worker-A', v_tok, 1);
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'LEASE mismatch ok';
END $t$;

-- ---------- 4. STALE RECOVERY invalidates the old worker --------------------
DO $t$
DECLARE v_job uuid; v_tok1 uuid; v_tok2 uuid; n int; ok boolean; st text;
BEGIN
  v_job := public._seo16d_new_job('PHASE16D-VERIFY-stale');
  SELECT lease_token INTO v_tok1 FROM public.seo_crawl_claim_job('worker-1', 60);
  -- simulate lease expiry
  UPDATE public.seo_crawl_jobs SET lease_expires_at = now() - interval '2 minutes' WHERE id=v_job;
  n := public.seo_crawl_recover_stale_jobs(now(), 100);
  IF n < 1 THEN RAISE EXCEPTION 'STALE: recovery did not recover the job'; END IF;
  IF (SELECT status FROM public.seo_crawl_jobs WHERE id=v_job) <> 'retry_wait'
     OR (SELECT lease_token FROM public.seo_crawl_jobs WHERE id=v_job) IS NOT NULL THEN
    RAISE EXCEPTION 'STALE: job not moved to retry_wait / token not cleared'; END IF;
  IF (SELECT outcome FROM public.seo_crawl_attempts WHERE job_id=v_job AND lease_token=v_tok1) <> 'lease_expired' THEN
    RAISE EXCEPTION 'STALE: abandoned attempt not marked lease_expired'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='lease_expired') THEN
    RAISE EXCEPTION 'STALE: no lease_expired event'; END IF;
  -- idempotent: second recovery does nothing (job now retry_wait, no lease)
  n := public.seo_crawl_recover_stale_jobs(now(), 100);
  IF (SELECT status FROM public.seo_crawl_jobs WHERE id=v_job) <> 'retry_wait' THEN RAISE EXCEPTION 'STALE: idempotency broken'; END IF;
  -- re-claim → new token; the OLD worker(token1) can no longer write
  SELECT lease_token INTO v_tok2 FROM public.seo_crawl_claim_job('worker-2', 60);
  IF v_tok2 = v_tok1 THEN RAISE EXCEPTION 'STALE: re-claim reused the old token'; END IF;
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_complete(v_job,'worker-1', v_tok1, 1); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'STALE: old worker (stale token) was allowed to complete after reassignment'; END IF;
  -- new worker completes fine
  PERFORM public.seo_crawl_worker_complete(v_job,'worker-2', v_tok2, 1);
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'STALE recovery ok';
END $t$;

-- ---------- 5. RETRY + MAX-ATTEMPTS terminal --------------------------------
DO $t$
DECLARE v_job uuid; v_tok uuid; st text; n int;
BEGIN
  -- retry scheduling (attempts remain)
  v_job := public._seo16d_new_job('PHASE16D-VERIFY-retry');
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-R', 60);   -- attempt 1, max 3
  st := public.seo_crawl_worker_schedule_retry(v_job,'worker-R', v_tok, now()+interval '5 minutes', 'transient', 'temporary');
  IF st <> 'retry_wait' THEN RAISE EXCEPTION 'RETRY: schedule_retry → % (expected retry_wait)', st; END IF;
  IF (SELECT retry_after FROM public.seo_crawl_jobs WHERE id=v_job) IS NULL
     OR (SELECT lease_token FROM public.seo_crawl_jobs WHERE id=v_job) IS NOT NULL THEN
    RAISE EXCEPTION 'RETRY: retry_after/lease not set correctly'; END IF;
  IF (SELECT outcome FROM public.seo_crawl_attempts WHERE job_id=v_job AND attempt_number=1) <> 'failed'
     OR (SELECT retry_class FROM public.seo_crawl_attempts WHERE job_id=v_job AND attempt_number=1) <> 'retryable' THEN
    RAISE EXCEPTION 'RETRY: attempt not marked failed/retryable'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='retry_scheduled') THEN
    RAISE EXCEPTION 'RETRY: no retry_scheduled event'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;

  -- max attempts exhausted → terminal failure
  v_job := public._seo16d_new_job('PHASE16D-VERIFY-maxatt');
  UPDATE public.seo_crawl_jobs SET max_attempts=1 WHERE id=v_job;
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-M', 60);   -- attempt_count → 1 == max
  st := public.seo_crawl_worker_schedule_retry(v_job,'worker-M', v_tok, now()+interval '5 minutes', 'boom', 'gave up');
  IF st <> 'failed' THEN RAISE EXCEPTION 'MAXATT: expected terminal failed, got %', st; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='failed') THEN
    RAISE EXCEPTION 'MAXATT: no failed event'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'RETRY + max-attempts ok';
END $t$;

-- ---------- 6. CANCELLATION ACK ---------------------------------------------
DO $t$
DECLARE v_job uuid; v_tok uuid; st text; n int; ok boolean;
BEGIN
  v_job := public._seo16d_new_job('PHASE16D-VERIFY-cancel');
  SELECT lease_token INTO v_tok FROM public.seo_crawl_claim_job('worker-X', 60);   -- running
  -- customer requests cancellation of the running job
  PERFORM public._seo16d_login(current_setting('seo16d.owner')::uuid);
  IF public.seo_crawl_cancel(v_job) <> 'cancellation_requested' THEN RAISE EXCEPTION 'CANCEL: expected cancellation_requested'; END IF;
  -- heartbeat now rejected (cancellation)
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_heartbeat(v_job,'worker-X',v_tok,60); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'CANCEL: heartbeat allowed after cancellation_requested'; END IF;
  -- worker acknowledges → cancelled
  st := public.seo_crawl_worker_acknowledge_cancellation(v_job,'worker-X',v_tok);
  IF st <> 'cancelled' THEN RAISE EXCEPTION 'CANCEL: ack → %', st; END IF;
  IF (SELECT outcome FROM public.seo_crawl_attempts WHERE job_id=v_job AND attempt_number=1) <> 'cancelled' THEN
    RAISE EXCEPTION 'CANCEL: attempt not marked cancelled'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=v_job AND event_type='cancelled';
  IF n <> 1 THEN RAISE EXCEPTION 'CANCEL: expected 1 cancelled event, got %', n; END IF;
  -- idempotent ack
  st := public.seo_crawl_worker_acknowledge_cancellation(v_job,'worker-X',v_tok);
  IF st <> 'cancelled' THEN RAISE EXCEPTION 'CANCEL: idempotent ack → %', st; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=v_job;
  RAISE NOTICE 'CANCEL ack ok';
END $t$;

-- ---------- 7. EXISTING RLS UNCHANGED (member cannot read internal attempts)-
SET LOCAL ROLE authenticated;
SELECT public._seo16d_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_attempts;  -- non-admin member → 0 (admin-only policy)
  IF n <> 0 THEN RAISE EXCEPTION 'RLS: authenticated non-admin read internal attempts (%)', n; END IF;
END $t$;
RESET ROLE;

-- ---------- 8. TEARDOWN -----------------------------------------------------
DELETE FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16D-VERIFY-%';
DROP FUNCTION IF EXISTS public._seo16d_new_job(text);
DROP FUNCTION IF EXISTS public._seo16d_login(uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16D-VERIFY-%';
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual jobs %', n; END IF;
END $t$;

SELECT 'ALL PASS — seo_phase16d worker lifecycle verification complete' AS result;
