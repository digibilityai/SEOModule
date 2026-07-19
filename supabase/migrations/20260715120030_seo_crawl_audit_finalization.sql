-- =============================================================================
-- Phase 16H defect fix — crawler-linked audit finalization
--
-- Proven defect:
--   A terminal cancelled/failed crawl could leave its linked seo_audit_runs
--   row permanently status='running'. Because that row remained is_latest=true,
--   it masked previously completed, published audit results.
--
-- Scope:
--   * additive migration only
--   * preserve every existing RPC name, parameter and return contract
--   * preserve crawl role permissions and lifecycle status vocabulary
--   * do not delete or rewrite completed audit history
--   * terminalize only linked audit rows that are still status='running'
--
-- Approved locked-module bug fix: 2026-07-15.
-- Production untouched unless separately promoted.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Internal helper.
--
-- Finalizes an audit-backed crawl attempt as a failed audit only when:
--   * the crawl has an audit_run_id;
--   * the audit belongs to the same workspace and website; and
--   * the audit is still running.
--
-- Completed/failed audit rows are never overwritten.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._seo_crawl_finalize_linked_audit_failed(
  p_job_id uuid,
  p_error_message text,
  p_completed_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT *
    INTO v_job
  FROM public.seo_crawl_jobs
  WHERE id = p_job_id;

  IF NOT FOUND OR v_job.audit_run_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.seo_audit_runs
  SET
    status = 'failed',
    completed_at = coalesce(completed_at, p_completed_at, now()),
    error_message = left(
      coalesce(
        nullif(btrim(p_error_message), ''),
        'The crawl did not produce a completed audit.'
      ),
      500
    ),
    updated_at = now()
  WHERE id = v_job.audit_run_id
    AND workspace_id = v_job.workspace_id
    AND website_id = v_job.website_id
    AND status = 'running';
END;
$$;

REVOKE ALL ON FUNCTION public._seo_crawl_finalize_linked_audit_failed(uuid, text, timestamptz)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public._seo_crawl_finalize_linked_audit_failed(uuid, text, timestamptz)
  FROM anon;
REVOKE ALL ON FUNCTION public._seo_crawl_finalize_linked_audit_failed(uuid, text, timestamptz)
  FROM authenticated;
REVOKE ALL ON FUNCTION public._seo_crawl_finalize_linked_audit_failed(uuid, text, timestamptz)
  FROM service_role;

-- ---------------------------------------------------------------------------
-- 2. Customer cancellation.
--
-- Queued/retry-wait cancellation is immediately terminal, so its linked
-- running audit is finalized immediately.
--
-- Claimed/running cancellation remains cancellation_requested until the
-- worker acknowledges it; the audit is finalized by the worker-ack RPC below.
--
-- Idempotent calls against an already-cancelled/failed job also self-heal any
-- pre-existing orphaned running audit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_cancel(p_job_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_job public.seo_crawl_jobs%ROWTYPE;
  v_role text;
  v_new_status text;
  v_event text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT *
    INTO v_job
  FROM public.seo_crawl_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Crawl job % does not exist', p_job_id;
  END IF;

  -- Same role rule as request: owner/admin/team_member or global admin.
  IF public.seo_is_global_admin(v_uid) THEN
    v_role := 'global_admin';
  ELSIF public.seo_role_in(
    v_job.workspace_id,
    ARRAY['owner', 'admin', 'team_member'],
    v_uid
  ) THEN
    v_role := (
      SELECT seo_role
      FROM public.seo_workspace_members
      WHERE workspace_id = v_job.workspace_id
        AND user_id = v_uid
        AND status = 'active'
    );
  ELSE
    RAISE EXCEPTION 'Not permitted to cancel crawls for this workspace';
  END IF;

  -- Terminal / already-requested: idempotent no-op for the crawl job.
  -- Cancelled/failed states also repair an orphaned linked audit if necessary.
  IF v_job.status IN (
    'completed',
    'partially_completed',
    'failed',
    'cancelled',
    'cancellation_requested'
  ) THEN
    IF v_job.status = 'cancelled' THEN
      PERFORM public._seo_crawl_finalize_linked_audit_failed(
        p_job_id,
        'Crawl cancelled before audit results were published.',
        coalesce(v_job.cancelled_at, v_job.completed_at, now())
      );
    ELSIF v_job.status = 'failed' THEN
      PERFORM public._seo_crawl_finalize_linked_audit_failed(
        p_job_id,
        coalesce(
          v_job.error_message,
          'The crawl failed before audit results were published.'
        ),
        coalesce(v_job.completed_at, now())
      );
    END IF;

    RETURN v_job.status;
  END IF;

  IF v_job.status IN ('queued', 'retry_wait') THEN
    -- Unclaimed: cancel immediately.
    v_new_status := 'cancelled';
    v_event := 'cancelled';

    UPDATE public.seo_crawl_jobs
    SET
      status = 'cancelled',
      cancellation_requested_at = now(),
      cancelled_at = now()
    WHERE id = p_job_id;

    PERFORM public._seo_crawl_finalize_linked_audit_failed(
      p_job_id,
      'Crawl cancelled before audit results were published.',
      now()
    );
  ELSE
    -- Claimed/running: request cancellation; worker finalizes.
    v_new_status := 'cancellation_requested';
    v_event := 'cancellation_requested';

    UPDATE public.seo_crawl_jobs
    SET
      status = 'cancellation_requested',
      cancellation_requested_at = now()
    WHERE id = p_job_id;
  END IF;

  INSERT INTO public.seo_crawl_events
    (
      job_id,
      workspace_id,
      website_id,
      event_type,
      from_status,
      to_status,
      actor,
      actor_user_id,
      actor_role_snapshot,
      note
    )
  VALUES
    (
      p_job_id,
      v_job.workspace_id,
      v_job.website_id,
      v_event,
      v_job.status,
      v_new_status,
      'customer',
      v_uid,
      v_role,
      'Cancellation requested by customer'
    );

  RETURN v_new_status;
END;
$$;

REVOKE ALL ON FUNCTION public.seo_crawl_cancel(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_cancel(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_crawl_cancel(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Worker terminal failure.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_fail(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_error_code text,
  p_error_message text,
  p_retry_class text DEFAULT 'non_retryable',
  p_internal_detail text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT *
    INTO v_job
  FROM public.seo_crawl_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'job % not found', p_job_id;
  END IF;

  IF v_job.status = 'failed' THEN
    PERFORM public._seo_crawl_finalize_linked_audit_failed(
      p_job_id,
      coalesce(
        v_job.error_message,
        p_error_message,
        'The crawl failed before audit results were published.'
      ),
      coalesce(v_job.completed_at, now())
    );
    RETURN 'failed';
  END IF;

  IF v_job.status NOT IN ('running', 'claimed') THEN
    RAISE EXCEPTION 'fail not allowed from %', v_job.status;
  END IF;

  PERFORM public._seo_crawl_assert_owner(
    v_job,
    p_worker_id,
    p_lease_token
  );

  UPDATE public.seo_crawl_jobs
  SET
    status = 'failed',
    completed_at = now(),
    error_code = coalesce(p_error_code, 'crawl_failed'),
    error_message = left(
      coalesce(p_error_message, 'The crawl failed.'),
      500
    ),
    lease_token = NULL,
    lease_expires_at = NULL
  WHERE id = p_job_id;

  UPDATE public.seo_crawl_attempts
  SET
    outcome = 'failed',
    retry_class = coalesce(p_retry_class, 'non_retryable'),
    internal_error_code = p_error_code,
    internal_error_detail = p_internal_detail,
    finished_at = now()
  WHERE job_id = p_job_id
    AND lease_token = p_lease_token;

  INSERT INTO public.seo_crawl_events
    (
      job_id,
      workspace_id,
      website_id,
      event_type,
      from_status,
      to_status,
      actor,
      note
    )
  VALUES
    (
      p_job_id,
      v_job.workspace_id,
      v_job.website_id,
      'failed',
      v_job.status,
      'failed',
      'worker',
      'Crawl failed'
    );

  PERFORM public._seo_crawl_finalize_linked_audit_failed(
    p_job_id,
    coalesce(p_error_message, 'The crawl failed.'),
    now()
  );

  RETURN 'failed';
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Retry scheduling.
--
-- A retry_wait job remains an active attempt and its linked audit remains
-- running. Only max-attempt exhaustion finalizes the audit as failed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_schedule_retry(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_retry_after timestamptz,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL,
  p_internal_detail text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
  v_status text;
BEGIN
  SELECT *
    INTO v_job
  FROM public.seo_crawl_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'job % not found', p_job_id;
  END IF;

  IF v_job.status NOT IN ('running', 'claimed') THEN
    RAISE EXCEPTION 'retry not allowed from %', v_job.status;
  END IF;

  PERFORM public._seo_crawl_assert_owner(
    v_job,
    p_worker_id,
    p_lease_token
  );

  UPDATE public.seo_crawl_attempts
  SET
    outcome = 'failed',
    retry_class = 'retryable',
    internal_error_code = p_error_code,
    internal_error_detail = p_internal_detail,
    finished_at = now()
  WHERE job_id = p_job_id
    AND lease_token = p_lease_token;

  IF v_job.attempt_count >= v_job.max_attempts THEN
    v_status := 'failed';

    UPDATE public.seo_crawl_jobs
    SET
      status = 'failed',
      completed_at = now(),
      error_code = coalesce(p_error_code, 'max_attempts_exhausted'),
      error_message = left(
        coalesce(
          p_error_message,
          'The crawl failed after the maximum retries.'
        ),
        500
      ),
      lease_token = NULL,
      lease_expires_at = NULL
    WHERE id = p_job_id;

    INSERT INTO public.seo_crawl_events
      (
        job_id,
        workspace_id,
        website_id,
        event_type,
        from_status,
        to_status,
        actor,
        note
      )
    VALUES
      (
        p_job_id,
        v_job.workspace_id,
        v_job.website_id,
        'failed',
        v_job.status,
        'failed',
        'worker',
        'Crawl failed (max attempts)'
      );

    PERFORM public._seo_crawl_finalize_linked_audit_failed(
      p_job_id,
      coalesce(
        p_error_message,
        'The crawl failed after the maximum retries.'
      ),
      now()
    );
  ELSE
    v_status := 'retry_wait';

    UPDATE public.seo_crawl_jobs
    SET
      status = 'retry_wait',
      retry_after = p_retry_after,
      error_code = p_error_code,
      error_message = left(p_error_message, 500),
      lease_token = NULL,
      lease_expires_at = NULL
    WHERE id = p_job_id;

    INSERT INTO public.seo_crawl_events
      (
        job_id,
        workspace_id,
        website_id,
        event_type,
        from_status,
        to_status,
        actor,
        note
      )
    VALUES
      (
        p_job_id,
        v_job.workspace_id,
        v_job.website_id,
        'retry_scheduled',
        v_job.status,
        'retry_wait',
        'worker',
        'Retry scheduled'
      );
  END IF;

  RETURN v_status;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Worker cancellation acknowledgment.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_acknowledge_cancellation(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT *
    INTO v_job
  FROM public.seo_crawl_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'job % not found', p_job_id;
  END IF;

  IF v_job.status = 'cancelled' THEN
    PERFORM public._seo_crawl_finalize_linked_audit_failed(
      p_job_id,
      'Crawl cancelled before audit results were published.',
      coalesce(v_job.cancelled_at, v_job.completed_at, now())
    );
    RETURN 'cancelled';
  END IF;

  IF v_job.status <> 'cancellation_requested' THEN
    RAISE EXCEPTION 'ack-cancellation not allowed from %', v_job.status;
  END IF;

  PERFORM public._seo_crawl_assert_owner(
    v_job,
    p_worker_id,
    p_lease_token
  );

  UPDATE public.seo_crawl_jobs
  SET
    status = 'cancelled',
    cancelled_at = now(),
    lease_token = NULL,
    lease_expires_at = NULL
  WHERE id = p_job_id;

  UPDATE public.seo_crawl_attempts
  SET
    outcome = 'cancelled',
    finished_at = now()
  WHERE job_id = p_job_id
    AND lease_token = p_lease_token;

  INSERT INTO public.seo_crawl_events
    (
      job_id,
      workspace_id,
      website_id,
      event_type,
      from_status,
      to_status,
      actor,
      note
    )
  VALUES
    (
      p_job_id,
      v_job.workspace_id,
      v_job.website_id,
      'cancelled',
      v_job.status,
      'cancelled',
      'worker',
      'Cancellation acknowledged by worker'
    );

  PERFORM public._seo_crawl_finalize_linked_audit_failed(
    p_job_id,
    'Crawl cancelled before audit results were published.',
    now()
  );

  RETURN 'cancelled';
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Stale-lease recovery.
--
-- Retryable stale jobs keep their audit running. Jobs that exhaust retries are
-- terminal failures and therefore finalize their linked running audit.
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
DECLARE
  r public.seo_crawl_jobs%ROWTYPE;
  v_count integer := 0;
  v_new text;
BEGIN
  FOR r IN
    SELECT *
    FROM public.seo_crawl_jobs
    WHERE status IN ('claimed', 'running', 'cancellation_requested')
      AND lease_expires_at IS NOT NULL
      AND lease_expires_at < p_now
    ORDER BY lease_expires_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT p_limit
  LOOP
    UPDATE public.seo_crawl_attempts
    SET
      outcome = 'lease_expired',
      finished_at = now()
    WHERE job_id = r.id
      AND lease_token = r.lease_token
      AND outcome IS NULL;

    IF r.attempt_count < r.max_attempts THEN
      v_new := 'retry_wait';

      UPDATE public.seo_crawl_jobs
      SET
        status = 'retry_wait',
        retry_after = p_now,
        lease_token = NULL,
        lease_expires_at = NULL
      WHERE id = r.id;
    ELSE
      v_new := 'failed';

      UPDATE public.seo_crawl_jobs
      SET
        status = 'failed',
        completed_at = now(),
        error_code = 'lease_expired',
        error_message =
          'The crawl was interrupted and could not be completed.',
        lease_token = NULL,
        lease_expires_at = NULL
      WHERE id = r.id;

      PERFORM public._seo_crawl_finalize_linked_audit_failed(
        r.id,
        'The crawl was interrupted and could not be completed.',
        now()
      );
    END IF;

    INSERT INTO public.seo_crawl_events
      (
        job_id,
        workspace_id,
        website_id,
        event_type,
        from_status,
        to_status,
        actor,
        note
      )
    VALUES
      (
        r.id,
        r.workspace_id,
        r.website_id,
        'lease_expired',
        r.status,
        v_new,
        'system',
        'Stale lease recovered'
      );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Worker lifecycle RPC permissions remain service-role only.
DO $grants$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_crawl_worker_fail(uuid,text,uuid,text,text,text,text)',
    'public.seo_crawl_worker_schedule_retry(uuid,text,uuid,timestamptz,text,text,text)',
    'public.seo_crawl_worker_acknowledge_cancellation(uuid,text,uuid)',
    'public.seo_crawl_recover_stale_jobs(timestamptz,integer)'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END;
$grants$;

-- ---------------------------------------------------------------------------
-- 7. TEST-safe historical repair.
--
-- Repair only already-terminal cancelled/failed crawl jobs whose linked audit
-- is still running. Completed audit rows and their published issues are not
-- changed. The failed attempt remains is_latest=true; the frontend will
-- separately select the newest completed audit for durable result display.
-- ---------------------------------------------------------------------------
UPDATE public.seo_audit_runs AS ar
SET
  status = 'failed',
  completed_at = coalesce(
    ar.completed_at,
    cj.cancelled_at,
    cj.completed_at,
    cj.updated_at,
    now()
  ),
  error_message = left(
    coalesce(
      ar.error_message,
      CASE
        WHEN cj.status = 'cancelled'
          THEN 'Crawl cancelled before audit results were published.'
        ELSE cj.error_message
      END,
      'The crawl failed before audit results were published.'
    ),
    500
  ),
  updated_at = now()
FROM public.seo_crawl_jobs AS cj
WHERE cj.audit_run_id = ar.id
  AND ar.workspace_id = cj.workspace_id
  AND ar.website_id = cj.website_id
  AND ar.status = 'running'
  AND cj.status IN ('cancelled', 'failed');

-- =============================================================================
-- End Phase 16H crawler-linked audit finalization defect fix.
-- =============================================================================
