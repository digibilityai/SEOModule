-- =============================================================================
-- SEO Backend — Phase 16D (Crawler 1B) — Migration 26: Worker Lifecycle + Lease
-- =============================================================================
-- Additive only. Builds on migration 25 (crawler control plane). Adds the
-- SERVICE-ROLE-ONLY worker lifecycle contract the future crawler worker uses to
-- safely advance a claimed job, plus a LEASE TOKEN so a stale worker can never
-- write to a job whose lease has been reassigned. Does NOT crawl anything and
-- does NOT edit migration 25. Applied to Digi_SEO_Test only; production untouched.
--
-- Security: every function here is SECURITY DEFINER + `SET search_path=public`,
-- with EXECUTE REVOKED from PUBLIC/anon/authenticated and available ONLY to
-- service_role (the future worker runtime). Customer RLS from migration 25 is
-- unchanged; no customer-facing policy is added; internal diagnostics stay in
-- seo_crawl_attempts (admin-read-only). No existing status string is changed.
--
-- Lease-token model: seo_crawl_claim_job now generates a random `lease_token`,
-- stores it on the job + the attempt, and returns it. Every lifecycle function
-- requires (job_id, worker_id, lease_token) and rejects a mismatched/cleared
-- token — so a re-claim after lease expiry invalidates the previous worker.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Additive lease-token columns.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_crawl_jobs      ADD COLUMN IF NOT EXISTS lease_token uuid;
ALTER TABLE public.seo_crawl_attempts  ADD COLUMN IF NOT EXISTS lease_token uuid;

-- ---------------------------------------------------------------------------
-- 2. Enhanced claim — additively returns + persists a lease_token. Behaviour is
--    otherwise identical to migration 25 (atomic FOR UPDATE SKIP LOCKED claim of
--    a queued/retry-ready job → running, attempt row, lease, 'claimed' event).
--    RETURNS TABLE changes shape (adds one column), so DROP+CREATE is required;
--    there is no existing consumer (the worker is built in this phase).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.seo_crawl_claim_job(text, integer);
CREATE OR REPLACE FUNCTION public.seo_crawl_claim_job(
  p_worker_id text,
  p_lease_seconds integer DEFAULT 300
)
RETURNS TABLE (
  job_id uuid,
  website_id uuid,
  website_url text,
  workspace_id uuid,
  attempt_number integer,
  config jsonb,
  lease_expires_at timestamptz,
  lease_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
  v_attempt integer;
  v_lease timestamptz;
  v_token uuid := gen_random_uuid();
BEGIN
  IF coalesce(btrim(p_worker_id), '') = '' THEN
    RAISE EXCEPTION 'worker id required';
  END IF;
  IF p_lease_seconds < 30 OR p_lease_seconds > 3600 THEN
    RAISE EXCEPTION 'lease seconds must be 30..3600';
  END IF;

  SELECT * INTO v_job
  FROM public.seo_crawl_jobs
  WHERE status IN ('queued', 'retry_wait')
    AND (retry_after IS NULL OR retry_after <= now())
  ORDER BY queued_at ASC
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_attempt := v_job.attempt_count + 1;
  v_lease := now() + make_interval(secs => p_lease_seconds);

  INSERT INTO public.seo_crawl_attempts
    (job_id, workspace_id, attempt_number, worker_id, lease_token, lease_expires_at, started_at)
  VALUES
    (v_job.id, v_job.workspace_id, v_attempt, p_worker_id, v_token, v_lease, now());

  UPDATE public.seo_crawl_jobs
    SET status = 'running',
        attempt_count = v_attempt,
        claimed_at = coalesce(claimed_at, now()),
        started_at = coalesce(started_at, now()),
        heartbeat_at = now(),
        lease_expires_at = v_lease,
        lease_token = v_token,
        retry_after = NULL
    WHERE id = v_job.id;

  INSERT INTO public.seo_crawl_events
    (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
  VALUES
    (v_job.id, v_job.workspace_id, v_job.website_id, 'claimed', v_job.status, 'running',
     'worker', 'Claimed by worker ' || p_worker_id);

  RETURN QUERY SELECT v_job.id, v_job.website_id, v_job.website_url, v_job.workspace_id,
                      v_attempt, v_job.config, v_lease, v_token;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM authenticated;

-- ---------------------------------------------------------------------------
-- 3. Internal ownership guard (raises on a stale/mismatched lease). Not granted
--    to anyone; called only by the lifecycle functions (same-owner definer).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._seo_crawl_assert_owner(
  p_job public.seo_crawl_jobs,
  p_worker_id text,
  p_lease_token uuid
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_lease_token IS NULL OR p_job.lease_token IS NULL OR p_job.lease_token <> p_lease_token THEN
    RAISE EXCEPTION 'lease lost or reassigned (stale worker); refusing write to job %', p_job.id;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Heartbeat — extends the lease; NO per-heartbeat event (avoids flooding).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_heartbeat(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_lease_seconds integer DEFAULT 300,
  p_pages_crawled integer DEFAULT NULL,
  p_pages_discovered integer DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE; v_lease timestamptz;
BEGIN
  IF p_lease_seconds < 30 OR p_lease_seconds > 3600 THEN RAISE EXCEPTION 'lease seconds must be 30..3600'; END IF;
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('claimed', 'running') THEN
    RAISE EXCEPTION 'heartbeat not allowed in status % (cancelled/terminal)', v_job.status;
  END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);

  v_lease := now() + make_interval(secs => p_lease_seconds);
  UPDATE public.seo_crawl_jobs
    SET heartbeat_at = now(),
        lease_expires_at = v_lease,
        pages_crawled  = GREATEST(pages_crawled, coalesce(p_pages_crawled, pages_crawled)),
        pages_discovered = GREATEST(pages_discovered, coalesce(p_pages_discovered, pages_discovered))
    WHERE id = p_job_id;
  UPDATE public.seo_crawl_attempts
    SET lease_expires_at = v_lease
    WHERE job_id = p_job_id AND lease_token = p_lease_token;
  RETURN v_lease;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Terminal / retry / cancel-ack transitions (one event each; clear lease).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_complete(
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_pages_crawled integer DEFAULT 0
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status = 'completed' THEN RETURN 'completed'; END IF;  -- idempotent
  IF v_job.status <> 'running' THEN RAISE EXCEPTION 'complete not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  UPDATE public.seo_crawl_jobs
    SET status='completed', completed_at=now(), pages_crawled=GREATEST(pages_crawled, coalesce(p_pages_crawled,0)),
        lease_token=NULL, lease_expires_at=NULL
    WHERE id=p_job_id;
  UPDATE public.seo_crawl_attempts SET outcome='succeeded', finished_at=now(),
        pages_crawled=GREATEST(pages_crawled, coalesce(p_pages_crawled,0))
    WHERE job_id=p_job_id AND lease_token=p_lease_token;
  INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
    VALUES (p_job_id, v_job.workspace_id, v_job.website_id, 'completed', v_job.status, 'completed', 'worker', 'Crawl completed');
  RETURN 'completed';
END; $$;

CREATE OR REPLACE FUNCTION public.seo_crawl_worker_partial(
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_pages_crawled integer DEFAULT 0,
  p_error_code text DEFAULT NULL, p_error_message text DEFAULT NULL
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status = 'partially_completed' THEN RETURN 'partially_completed'; END IF;
  IF v_job.status <> 'running' THEN RAISE EXCEPTION 'partial not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  UPDATE public.seo_crawl_jobs
    SET status='partially_completed', completed_at=now(), pages_crawled=GREATEST(pages_crawled, coalesce(p_pages_crawled,0)),
        error_code=p_error_code, error_message=left(p_error_message, 500), lease_token=NULL, lease_expires_at=NULL
    WHERE id=p_job_id;
  UPDATE public.seo_crawl_attempts SET outcome='partial', finished_at=now(),
        pages_crawled=GREATEST(pages_crawled, coalesce(p_pages_crawled,0))
    WHERE job_id=p_job_id AND lease_token=p_lease_token;
  INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
    VALUES (p_job_id, v_job.workspace_id, v_job.website_id, 'partially_completed', v_job.status, 'partially_completed', 'worker', 'Crawl partially completed');
  RETURN 'partially_completed';
END; $$;

CREATE OR REPLACE FUNCTION public.seo_crawl_worker_fail(
  p_job_id uuid, p_worker_id text, p_lease_token uuid,
  p_error_code text, p_error_message text,
  p_retry_class text DEFAULT 'non_retryable',
  p_internal_detail text DEFAULT NULL
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status = 'failed' THEN RETURN 'failed'; END IF;
  IF v_job.status NOT IN ('running','claimed') THEN RAISE EXCEPTION 'fail not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  UPDATE public.seo_crawl_jobs
    SET status='failed', completed_at=now(), error_code=coalesce(p_error_code,'crawl_failed'),
        error_message=left(coalesce(p_error_message,'The crawl failed.'), 500), lease_token=NULL, lease_expires_at=NULL
    WHERE id=p_job_id;
  UPDATE public.seo_crawl_attempts SET outcome='failed', retry_class=coalesce(p_retry_class,'non_retryable'),
        internal_error_code=p_error_code, internal_error_detail=p_internal_detail, finished_at=now()
    WHERE job_id=p_job_id AND lease_token=p_lease_token;
  INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
    VALUES (p_job_id, v_job.workspace_id, v_job.website_id, 'failed', v_job.status, 'failed', 'worker', 'Crawl failed');
  RETURN 'failed';
END; $$;

CREATE OR REPLACE FUNCTION public.seo_crawl_worker_schedule_retry(
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_retry_after timestamptz,
  p_error_code text DEFAULT NULL, p_error_message text DEFAULT NULL, p_internal_detail text DEFAULT NULL
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE; v_status text;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('running','claimed') THEN RAISE EXCEPTION 'retry not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  UPDATE public.seo_crawl_attempts SET outcome='failed', retry_class='retryable',
        internal_error_code=p_error_code, internal_error_detail=p_internal_detail, finished_at=now()
    WHERE job_id=p_job_id AND lease_token=p_lease_token;
  IF v_job.attempt_count >= v_job.max_attempts THEN
    -- no attempts left → terminal failure
    v_status := 'failed';
    UPDATE public.seo_crawl_jobs SET status='failed', completed_at=now(),
        error_code=coalesce(p_error_code,'max_attempts_exhausted'),
        error_message=left(coalesce(p_error_message,'The crawl failed after the maximum retries.'),500),
        lease_token=NULL, lease_expires_at=NULL WHERE id=p_job_id;
    INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
      VALUES (p_job_id, v_job.workspace_id, v_job.website_id, 'failed', v_job.status, 'failed', 'worker', 'Crawl failed (max attempts)');
  ELSE
    v_status := 'retry_wait';
    UPDATE public.seo_crawl_jobs SET status='retry_wait', retry_after=p_retry_after,
        error_code=p_error_code, error_message=left(p_error_message,500), lease_token=NULL, lease_expires_at=NULL
      WHERE id=p_job_id;
    INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
      VALUES (p_job_id, v_job.workspace_id, v_job.website_id, 'retry_scheduled', v_job.status, 'retry_wait', 'worker', 'Retry scheduled');
  END IF;
  RETURN v_status;
END; $$;

CREATE OR REPLACE FUNCTION public.seo_crawl_worker_acknowledge_cancellation(
  p_job_id uuid, p_worker_id text, p_lease_token uuid
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status = 'cancelled' THEN RETURN 'cancelled'; END IF;  -- idempotent
  IF v_job.status <> 'cancellation_requested' THEN RAISE EXCEPTION 'ack-cancellation not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  UPDATE public.seo_crawl_jobs SET status='cancelled', cancelled_at=now(), lease_token=NULL, lease_expires_at=NULL WHERE id=p_job_id;
  UPDATE public.seo_crawl_attempts SET outcome='cancelled', finished_at=now()
    WHERE job_id=p_job_id AND lease_token=p_lease_token;
  INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
    VALUES (p_job_id, v_job.workspace_id, v_job.website_id, 'cancelled', v_job.status, 'cancelled', 'worker', 'Cancellation acknowledged by worker');
  RETURN 'cancelled';
END; $$;

-- ---------------------------------------------------------------------------
-- 6. Stale-lease recovery — idempotent, concurrency-safe (SKIP LOCKED).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_recover_stale_jobs(
  p_now timestamptz DEFAULT now(),
  p_limit integer DEFAULT 100
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r public.seo_crawl_jobs%ROWTYPE; v_count int := 0; v_new text;
BEGIN
  FOR r IN
    SELECT * FROM public.seo_crawl_jobs
    WHERE status IN ('claimed','running','cancellation_requested')
      AND lease_expires_at IS NOT NULL AND lease_expires_at < p_now
    ORDER BY lease_expires_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  LOOP
    -- close the abandoned attempt (the one holding the current lease)
    UPDATE public.seo_crawl_attempts
      SET outcome='lease_expired', finished_at=now()
      WHERE job_id=r.id AND lease_token=r.lease_token AND outcome IS NULL;

    IF r.attempt_count < r.max_attempts THEN
      v_new := 'retry_wait';
      UPDATE public.seo_crawl_jobs
        SET status='retry_wait', retry_after=p_now, lease_token=NULL, lease_expires_at=NULL
        WHERE id=r.id;
    ELSE
      v_new := 'failed';
      UPDATE public.seo_crawl_jobs
        SET status='failed', completed_at=now(),
            error_code='lease_expired', error_message='The crawl was interrupted and could not be completed.',
            lease_token=NULL, lease_expires_at=NULL
        WHERE id=r.id;
    END IF;

    INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
      VALUES (r.id, r.workspace_id, r.website_id, 'lease_expired', r.status, v_new, 'system', 'Stale lease recovered');
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants — every worker function: service_role ONLY.
-- ---------------------------------------------------------------------------
DO $grants$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_crawl_worker_heartbeat(uuid,text,uuid,integer,integer,integer)',
    'public.seo_crawl_worker_complete(uuid,text,uuid,integer)',
    'public.seo_crawl_worker_partial(uuid,text,uuid,integer,text,text)',
    'public.seo_crawl_worker_fail(uuid,text,uuid,text,text,text,text)',
    'public.seo_crawl_worker_schedule_retry(uuid,text,uuid,timestamptz,text,text,text)',
    'public.seo_crawl_worker_acknowledge_cancellation(uuid,text,uuid)',
    'public.seo_crawl_recover_stale_jobs(timestamptz,integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $grants$;
-- _seo_crawl_assert_owner is an internal helper — revoke from everyone (only the
-- definer-owned lifecycle functions call it).
REVOKE ALL ON FUNCTION public._seo_crawl_assert_owner(public.seo_crawl_jobs, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._seo_crawl_assert_owner(public.seo_crawl_jobs, text, uuid) FROM anon;
REVOKE ALL ON FUNCTION public._seo_crawl_assert_owner(public.seo_crawl_jobs, text, uuid) FROM authenticated;

-- =============================================================================
-- End Phase 16D worker lifecycle. Deferred to Phase 1C: the actual crawl
-- (URL safety, robots.txt, sitemap, page discovery). No crawling runs; customer
-- RLS unchanged; no existing status value altered; production untouched.
-- =============================================================================
