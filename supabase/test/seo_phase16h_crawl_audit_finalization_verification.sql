-- =============================================================================
-- SEO Phase 16H — Crawler-linked Audit Finalization — VERIFICATION
-- =============================================================================
--                         **** TEST ONLY ****
--                   **** DO NOT RUN ON PRODUCTION ****
--
-- Run only on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), after additive
-- migration 20260715120030.
--
-- Coverage:
--   1. Structure and grants
--   2. Queued cancellation finalizes only its linked running audit
--   3. Idempotent cancellation repairs a historical orphan
--   4. Active cancellation waits for worker acknowledgment
--   5. Direct worker failure finalizes the linked audit
--   6. Retry-wait remains running; exhausted retry becomes failed
--   7. Stale recovery remains running when retryable; fails when exhausted
--   8. Completed audits are never overwritten
--
-- Uses one disposable website and direct, deterministic lease fixtures.
-- It never calls seo_crawl_claim_job(), so unrelated queued UAT jobs cannot
-- be claimed. Complete teardown leaves no verification rows.
-- =============================================================================

SELECT set_config(
  'seo1630.ws',
  '44444444-0000-0000-0001-000000000001',
  false
);

SELECT set_config(
  'seo1630.owner',
  '48c479db-aedf-452e-af43-05ed1180baaa',
  false
);

CREATE OR REPLACE FUNCTION public._seo1630_login(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_uid,
      'role', 'authenticated'
    )::text,
    true
  );
END;
$fn$;

DO $t$
DECLARE
  v_website uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.seo_websites
    (
      id,
      workspace_id,
      website_url,
      website_name,
      business_name,
      is_active
    )
  VALUES
    (
      v_website,
      current_setting('seo1630.ws')::uuid,
      'https://phase16h-audit-finalization.example',
      'Phase 16H audit finalization verification',
      'Phase 16H verification',
      true
    );

  PERFORM set_config('seo1630.website', v_website::text, false);

  -- P1b fixture: seed VERIFIED domain-ownership for this disposable site so
  -- seo_crawl_request_audit passes the P1b verified-only gate (migration
  -- 20260719120034). Token-marked; cascade-removed with the website at teardown.
  INSERT INTO public.seo_ownership_verifications
    (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at)
  VALUES (current_setting('seo1630.ws')::uuid, v_website, 'https://phase16h-audit-finalization.example',
          'p1b-fixture.example', 'dns_txt', 'verified', 'P1B-FIXTURE-TOKEN', now())
  ON CONFLICT (website_id, method) DO UPDATE
    SET status='verified', challenge_token='P1B-FIXTURE-TOKEN', verified_at=now(), updated_at=now();
END;
$t$;

CREATE OR REPLACE FUNCTION public._seo1630_request(p_key text)
RETURNS TABLE (
  audit_run_id uuid,
  crawl_job_id uuid
)
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM public._seo1630_login(
    current_setting('seo1630.owner')::uuid
  );

  RETURN QUERY
  SELECT
    requested.audit_run_id,
    requested.crawl_job_id
  FROM public.seo_crawl_request_audit(
    current_setting('seo1630.website')::uuid,
    p_key,
    '{}'::jsonb
  ) AS requested;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._seo1630_make_running(
  p_job_id uuid,
  p_worker_id text,
  p_attempt_count integer,
  p_max_attempts integer,
  p_lease_expired boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_token uuid := gen_random_uuid();
  v_lease timestamptz;
  v_workspace uuid;
BEGIN
  v_lease :=
    CASE
      WHEN p_lease_expired
        THEN now() - interval '2 minutes'
      ELSE now() + interval '5 minutes'
    END;

  SELECT workspace_id
    INTO v_workspace
  FROM public.seo_crawl_jobs
  WHERE id = p_job_id;

  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'fixture job % not found', p_job_id;
  END IF;

  UPDATE public.seo_crawl_jobs
  SET
    status = 'running',
    attempt_count = p_attempt_count,
    max_attempts = p_max_attempts,
    claimed_at = coalesce(claimed_at, now()),
    started_at = coalesce(started_at, now()),
    heartbeat_at = now(),
    lease_expires_at = v_lease,
    lease_token = v_token,
    retry_after = NULL
  WHERE id = p_job_id;

  INSERT INTO public.seo_crawl_attempts
    (
      job_id,
      workspace_id,
      attempt_number,
      worker_id,
      lease_token,
      lease_expires_at,
      started_at
    )
  VALUES
    (
      p_job_id,
      v_workspace,
      p_attempt_count,
      p_worker_id,
      v_token,
      v_lease,
      now()
    );

  RETURN v_token;
END;
$fn$;

CREATE OR REPLACE FUNCTION public._seo1630_cleanup_runs()
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  DELETE FROM public.seo_crawl_jobs
  WHERE website_id = current_setting('seo1630.website')::uuid;

  DELETE FROM public.seo_audit_runs
  WHERE website_id = current_setting('seo1630.website')::uuid;
END;
$fn$;

-- ===========================================================================
-- 1. STRUCTURE + GRANTS
-- ===========================================================================
DO $t$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*)
    INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n
    ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      '_seo_crawl_finalize_linked_audit_failed',
      'seo_crawl_cancel',
      'seo_crawl_worker_fail',
      'seo_crawl_worker_schedule_retry',
      'seo_crawl_worker_acknowledge_cancellation',
      'seo_crawl_recover_stale_jobs'
    );

  IF v_count <> 6 THEN
    RAISE EXCEPTION
      'STRUCT: expected six finalization/lifecycle functions, found %',
      v_count;
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public._seo_crawl_finalize_linked_audit_failed(uuid,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'GRANT: authenticated can execute internal audit-finalization helper';
  END IF;

  IF has_function_privilege(
    'service_role',
    'public._seo_crawl_finalize_linked_audit_failed(uuid,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'GRANT: service_role can directly execute internal helper';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.seo_crawl_cancel(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'GRANT: authenticated cannot execute customer cancel RPC';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.seo_crawl_worker_fail(uuid,text,uuid,text,text,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'GRANT: authenticated can execute worker failure RPC';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.seo_crawl_worker_fail(uuid,text,uuid,text,text,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'GRANT: service_role cannot execute worker failure RPC';
  END IF;

  RAISE NOTICE 'STRUCTURE + GRANTS ok';
END;
$t$;

-- ===========================================================================
-- 2. QUEUED CANCELLATION + COMPLETED-HISTORY PROTECTION
-- ===========================================================================
DO $t$
DECLARE
  v_baseline_run uuid;
  v_baseline_job uuid;
  v_new_run uuid;
  v_new_job uuid;
  v_baseline_updated timestamptz;
  v_status text;
  v_events integer;
BEGIN
  SELECT audit_run_id, crawl_job_id
    INTO v_baseline_run, v_baseline_job
  FROM public._seo1630_request('PHASE16H-1630-baseline');

  DELETE FROM public.seo_crawl_jobs
  WHERE id = v_baseline_job;

  UPDATE public.seo_audit_runs
  SET
    status = 'completed',
    completed_at = now() - interval '1 day',
    issue_count = 3,
    error_message = NULL
  WHERE id = v_baseline_run;

  SELECT audit_run_id, crawl_job_id
    INTO v_new_run, v_new_job
  FROM public._seo1630_request('PHASE16H-1630-queued-cancel');

  SELECT updated_at
    INTO v_baseline_updated
  FROM public.seo_audit_runs
  WHERE id = v_baseline_run;

  PERFORM public._seo1630_login(
    current_setting('seo1630.owner')::uuid
  );

  v_status := public.seo_crawl_cancel(v_new_job);

  IF v_status <> 'cancelled' THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: expected cancelled, got %',
      v_status;
  END IF;

  IF (SELECT status FROM public.seo_audit_runs WHERE id = v_new_run)
      <> 'failed' THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: linked audit was not finalized as failed';
  END IF;

  IF (SELECT completed_at FROM public.seo_audit_runs WHERE id = v_new_run)
      IS NULL THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: linked audit has no completed_at';
  END IF;

  IF (SELECT error_message FROM public.seo_audit_runs WHERE id = v_new_run)
      NOT ILIKE '%cancel%' THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: linked audit has no customer-safe cancellation message';
  END IF;

  IF (SELECT status FROM public.seo_audit_runs WHERE id = v_baseline_run)
      <> 'completed'
     OR (SELECT issue_count FROM public.seo_audit_runs
         WHERE id = v_baseline_run) <> 3 THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: previous completed audit was modified';
  END IF;

  IF (SELECT updated_at FROM public.seo_audit_runs WHERE id = v_baseline_run)
      <> v_baseline_updated THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: previous completed audit timestamp changed';
  END IF;

  IF (SELECT is_latest FROM public.seo_audit_runs WHERE id = v_baseline_run)
     OR NOT (SELECT is_latest FROM public.seo_audit_runs WHERE id = v_new_run) THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: existing is_latest contract changed unexpectedly';
  END IF;

  SELECT count(*)
    INTO v_events
  FROM public.seo_crawl_events
  WHERE job_id = v_new_job
    AND event_type = 'cancelled';

  IF v_events <> 1 THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: expected one cancelled event, found %',
      v_events;
  END IF;

  -- Idempotent repeat must not duplicate the event or rewrite the audit.
  v_status := public.seo_crawl_cancel(v_new_job);

  SELECT count(*)
    INTO v_events
  FROM public.seo_crawl_events
  WHERE job_id = v_new_job
    AND event_type = 'cancelled';

  IF v_status <> 'cancelled' OR v_events <> 1 THEN
    RAISE EXCEPTION
      'QUEUED CANCEL: idempotent repeat changed status/event count';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'QUEUED CANCELLATION + HISTORY PROTECTION ok';
END;
$t$;

-- ===========================================================================
-- 3. HISTORICAL ORPHAN SELF-HEAL
-- ===========================================================================
DO $t$
DECLARE
  v_run uuid;
  v_job uuid;
  v_status text;
BEGIN
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-orphan-heal');

  -- Reproduce the pre-fix state: terminal crawl, linked audit still running.
  UPDATE public.seo_crawl_jobs
  SET
    status = 'cancelled',
    cancellation_requested_at = now(),
    cancelled_at = now()
  WHERE id = v_job;

  IF (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
      <> 'running' THEN
    RAISE EXCEPTION
      'ORPHAN HEAL: fixture did not reproduce running audit';
  END IF;

  PERFORM public._seo1630_login(
    current_setting('seo1630.owner')::uuid
  );

  v_status := public.seo_crawl_cancel(v_job);

  IF v_status <> 'cancelled'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'failed' THEN
    RAISE EXCEPTION
      'ORPHAN HEAL: idempotent cancel did not repair linked audit';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'HISTORICAL ORPHAN SELF-HEAL ok';
END;
$t$;

-- ===========================================================================
-- 4. ACTIVE CANCELLATION — FINALIZE ONLY AFTER WORKER ACK
-- ===========================================================================
DO $t$
DECLARE
  v_run uuid;
  v_job uuid;
  v_token uuid;
  v_status text;
  v_events integer;
BEGIN
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-active-cancel');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-cancel',
    1,
    3,
    false
  );

  PERFORM public._seo1630_login(
    current_setting('seo1630.owner')::uuid
  );

  v_status := public.seo_crawl_cancel(v_job);

  IF v_status <> 'cancellation_requested' THEN
    RAISE EXCEPTION
      'ACTIVE CANCEL: expected cancellation_requested, got %',
      v_status;
  END IF;

  IF (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
      <> 'running' THEN
    RAISE EXCEPTION
      'ACTIVE CANCEL: audit finalized before worker acknowledgment';
  END IF;

  v_status := public.seo_crawl_worker_acknowledge_cancellation(
    v_job,
    'worker-cancel',
    v_token
  );

  IF v_status <> 'cancelled'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'failed' THEN
    RAISE EXCEPTION
      'ACTIVE CANCEL: worker acknowledgment did not finalize audit';
  END IF;

  IF (SELECT outcome
      FROM public.seo_crawl_attempts
      WHERE job_id = v_job
        AND attempt_number = 1) <> 'cancelled' THEN
    RAISE EXCEPTION
      'ACTIVE CANCEL: attempt was not marked cancelled';
  END IF;

  SELECT count(*)
    INTO v_events
  FROM public.seo_crawl_events
  WHERE job_id = v_job
    AND event_type = 'cancelled';

  IF v_events <> 1 THEN
    RAISE EXCEPTION
      'ACTIVE CANCEL: expected one cancelled event, found %',
      v_events;
  END IF;

  v_status := public.seo_crawl_worker_acknowledge_cancellation(
    v_job,
    'worker-cancel',
    v_token
  );

  IF v_status <> 'cancelled' THEN
    RAISE EXCEPTION
      'ACTIVE CANCEL: idempotent acknowledgment failed';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'ACTIVE CANCELLATION ok';
END;
$t$;

-- ===========================================================================
-- 5. DIRECT WORKER FAILURE
-- ===========================================================================
DO $t$
DECLARE
  v_run uuid;
  v_job uuid;
  v_token uuid;
  v_status text;
BEGIN
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-worker-fail');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-fail',
    1,
    3,
    false
  );

  v_status := public.seo_crawl_worker_fail(
    v_job,
    'worker-fail',
    v_token,
    'fixture_failure',
    'Fixture crawl failed safely.',
    'non_retryable',
    'internal fixture detail'
  );

  IF v_status <> 'failed'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'failed' THEN
    RAISE EXCEPTION
      'WORKER FAIL: crawl/audit terminal state mismatch';
  END IF;

  IF (SELECT error_message FROM public.seo_audit_runs WHERE id = v_run)
      <> 'Fixture crawl failed safely.' THEN
    RAISE EXCEPTION
      'WORKER FAIL: customer-safe message not propagated';
  END IF;

  IF (SELECT outcome
      FROM public.seo_crawl_attempts
      WHERE job_id = v_job
        AND attempt_number = 1) <> 'failed' THEN
    RAISE EXCEPTION
      'WORKER FAIL: attempt was not marked failed';
  END IF;

  -- Idempotent terminal replay.
  v_status := public.seo_crawl_worker_fail(
    v_job,
    'worker-fail',
    v_token,
    'fixture_failure',
    'Fixture crawl failed safely.',
    'non_retryable',
    NULL
  );

  IF v_status <> 'failed' THEN
    RAISE EXCEPTION
      'WORKER FAIL: idempotent terminal replay failed';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'DIRECT WORKER FAILURE ok';
END;
$t$;

-- ===========================================================================
-- 6. RETRY WAIT VS. MAX-ATTEMPT FAILURE
-- ===========================================================================
DO $t$
DECLARE
  v_run uuid;
  v_job uuid;
  v_token uuid;
  v_status text;
BEGIN
  -- Retryable path: linked audit remains running.
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-retry-wait');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-retry',
    1,
    3,
    false
  );

  v_status := public.seo_crawl_worker_schedule_retry(
    v_job,
    'worker-retry',
    v_token,
    now() + interval '5 minutes',
    'temporary',
    'Temporary crawl interruption.',
    'fixture retry detail'
  );

  IF v_status <> 'retry_wait'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'running' THEN
    RAISE EXCEPTION
      'RETRY WAIT: active retry incorrectly finalized the audit';
  END IF;

  PERFORM public._seo1630_cleanup_runs();

  -- Exhausted path: linked audit becomes failed.
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-retry-exhausted');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-retry-max',
    1,
    1,
    false
  );

  v_status := public.seo_crawl_worker_schedule_retry(
    v_job,
    'worker-retry-max',
    v_token,
    now() + interval '5 minutes',
    'max_attempts',
    'Maximum crawl attempts exhausted.',
    'fixture exhausted detail'
  );

  IF v_status <> 'failed'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'failed' THEN
    RAISE EXCEPTION
      'RETRY EXHAUSTED: linked audit was not finalized';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'RETRY WAIT + MAX-ATTEMPT FAILURE ok';
END;
$t$;

-- ===========================================================================
-- 7. STALE-LEASE RECOVERY
-- ===========================================================================
DO $t$
DECLARE
  v_run uuid;
  v_job uuid;
  v_token uuid;
  v_recovered integer;
BEGIN
  -- Retryable stale lease: linked audit remains running.
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-stale-retry');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-stale-retry',
    1,
    3,
    true
  );

  v_recovered := public.seo_crawl_recover_stale_jobs(now(), 100);

  IF v_recovered < 1
     OR (SELECT status FROM public.seo_crawl_jobs WHERE id = v_job)
        <> 'retry_wait'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'running' THEN
    RAISE EXCEPTION
      'STALE RETRY: recovery state or linked audit state is incorrect';
  END IF;

  PERFORM public._seo1630_cleanup_runs();

  -- Exhausted stale lease: linked audit becomes failed.
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-stale-fail');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-stale-fail',
    1,
    1,
    true
  );

  v_recovered := public.seo_crawl_recover_stale_jobs(now(), 100);

  IF v_recovered < 1
     OR (SELECT status FROM public.seo_crawl_jobs WHERE id = v_job)
        <> 'failed'
     OR (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
        <> 'failed' THEN
    RAISE EXCEPTION
      'STALE FAILURE: terminal recovery did not finalize linked audit';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'STALE-LEASE RECOVERY ok';
END;
$t$;

-- ===========================================================================
-- 8. COMPLETED AUDIT MUST NEVER BE OVERWRITTEN
-- ===========================================================================
DO $t$
DECLARE
  v_run uuid;
  v_job uuid;
  v_token uuid;
  v_completed_at timestamptz;
  v_status text;
BEGIN
  SELECT audit_run_id, crawl_job_id
    INTO v_run, v_job
  FROM public._seo1630_request('PHASE16H-1630-completed-protection');

  v_token := public._seo1630_make_running(
    v_job,
    'worker-completed-protection',
    1,
    3,
    false
  );

  v_completed_at := now() - interval '2 hours';

  UPDATE public.seo_audit_runs
  SET
    status = 'completed',
    completed_at = v_completed_at,
    issue_count = 7,
    error_message = NULL
  WHERE id = v_run;

  v_status := public.seo_crawl_worker_fail(
    v_job,
    'worker-completed-protection',
    v_token,
    'late_failure',
    'Late worker failure must not overwrite published audit.',
    'non_retryable',
    NULL
  );

  IF v_status <> 'failed' THEN
    RAISE EXCEPTION
      'COMPLETED PROTECTION: crawl did not reach expected failed state';
  END IF;

  IF (SELECT status FROM public.seo_audit_runs WHERE id = v_run)
      <> 'completed'
     OR (SELECT completed_at FROM public.seo_audit_runs WHERE id = v_run)
        <> v_completed_at
     OR (SELECT issue_count FROM public.seo_audit_runs WHERE id = v_run)
        <> 7
     OR (SELECT error_message FROM public.seo_audit_runs WHERE id = v_run)
        IS NOT NULL THEN
    RAISE EXCEPTION
      'COMPLETED PROTECTION: completed audit was overwritten';
  END IF;

  PERFORM public._seo1630_cleanup_runs();
  RAISE NOTICE 'COMPLETED AUDIT PROTECTION ok';
END;
$t$;

-- ===========================================================================
-- 9. TEARDOWN
-- ===========================================================================
DO $t$
DECLARE
  v_website uuid := current_setting('seo1630.website')::uuid;
BEGIN
  PERFORM public._seo1630_cleanup_runs();

  -- P1b fixture cleanup (token-marked; also cascade-removed with the website below).
  DELETE FROM public.seo_ownership_verifications WHERE challenge_token = 'P1B-FIXTURE-TOKEN';

  DELETE FROM public.seo_websites
  WHERE id = v_website;

  IF EXISTS (
    SELECT 1
    FROM public.seo_crawl_jobs
    WHERE idempotency_key LIKE 'PHASE16H-1630-%'
  ) THEN
    RAISE EXCEPTION
      'TEARDOWN: residual crawl jobs remain';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.seo_websites
    WHERE id = v_website
  ) THEN
    RAISE EXCEPTION
      'TEARDOWN: disposable website remains';
  END IF;

  RAISE NOTICE 'TEARDOWN ok';
END;
$t$;

DROP FUNCTION IF EXISTS public._seo1630_cleanup_runs();
DROP FUNCTION IF EXISTS public._seo1630_make_running(
  uuid,
  text,
  integer,
  integer,
  boolean
);
DROP FUNCTION IF EXISTS public._seo1630_request(text);
DROP FUNCTION IF EXISTS public._seo1630_login(uuid);

SELECT
  'PHASE 16H AUDIT FINALIZATION VERIFICATION: ALL PASS' AS result;
