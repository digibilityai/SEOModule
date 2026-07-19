-- =============================================================================
-- SEO Phase 16D — Worker Lifecycle — ROLLBACK (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
--
-- Reverses migration 20260714120026 on Digi_SEO_Test only. Drops the worker
-- lifecycle functions + the lease-token columns, and restores the pre-16D claim
-- function (without lease_token) so Phase 16C is left intact. Preserves all
-- Phase 16C objects. No customer data is affected (additive columns only).
-- =============================================================================

-- 1. Worker lifecycle functions + internal guard.
DROP FUNCTION IF EXISTS public.seo_crawl_recover_stale_jobs(timestamptz, integer);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_acknowledge_cancellation(uuid, text, uuid);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_schedule_retry(uuid, text, uuid, timestamptz, text, text, text);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_fail(uuid, text, uuid, text, text, text, text);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_partial(uuid, text, uuid, integer, text, text);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_complete(uuid, text, uuid, integer);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_heartbeat(uuid, text, uuid, integer, integer, integer);
DROP FUNCTION IF EXISTS public._seo_crawl_assert_owner(public.seo_crawl_jobs, text, uuid);

-- 2. Restore the Phase 16C claim signature (no lease_token) so migration 25's
--    contract is intact after rollback.
DROP FUNCTION IF EXISTS public.seo_crawl_claim_job(text, integer);
CREATE OR REPLACE FUNCTION public.seo_crawl_claim_job(p_worker_id text, p_lease_seconds integer DEFAULT 300)
RETURNS TABLE (job_id uuid, website_id uuid, website_url text, workspace_id uuid,
               attempt_number integer, config jsonb, lease_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE; v_attempt integer; v_lease timestamptz;
BEGIN
  IF coalesce(btrim(p_worker_id),'')='' THEN RAISE EXCEPTION 'worker id required'; END IF;
  IF p_lease_seconds < 30 OR p_lease_seconds > 3600 THEN RAISE EXCEPTION 'lease seconds must be 30..3600'; END IF;
  SELECT * INTO v_job FROM public.seo_crawl_jobs
    WHERE status IN ('queued','retry_wait') AND (retry_after IS NULL OR retry_after <= now())
    ORDER BY queued_at ASC FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  v_attempt := v_job.attempt_count + 1; v_lease := now() + make_interval(secs => p_lease_seconds);
  INSERT INTO public.seo_crawl_attempts (job_id, workspace_id, attempt_number, worker_id, lease_expires_at, started_at)
    VALUES (v_job.id, v_job.workspace_id, v_attempt, p_worker_id, v_lease, now());
  UPDATE public.seo_crawl_jobs SET status='running', attempt_count=v_attempt,
    claimed_at=coalesce(claimed_at,now()), started_at=coalesce(started_at,now()),
    heartbeat_at=now(), lease_expires_at=v_lease, retry_after=NULL WHERE id=v_job.id;
  INSERT INTO public.seo_crawl_events (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
    VALUES (v_job.id, v_job.workspace_id, v_job.website_id, 'claimed', v_job.status, 'running', 'worker', 'Claimed by worker '||p_worker_id);
  RETURN QUERY SELECT v_job.id, v_job.website_id, v_job.website_url, v_job.workspace_id, v_attempt, v_job.config, v_lease;
END; $$;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM authenticated;

-- 3. Additive lease-token columns (drop last; safe — only Phase 16D used them).
ALTER TABLE public.seo_crawl_attempts DROP COLUMN IF EXISTS lease_token;
ALTER TABLE public.seo_crawl_jobs     DROP COLUMN IF EXISTS lease_token;
