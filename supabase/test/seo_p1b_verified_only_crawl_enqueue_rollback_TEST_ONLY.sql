-- =============================================================================
-- SEO P1b — Verified-only Crawl Enqueue Enforcement — ROLLBACK
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Reverts the P1b guard by restoring public.seo_crawl_request to its EXACT
-- pre-P1b (Phase 16C) body via CREATE OR REPLACE. Removes ONLY the new
-- verified-ownership precondition; every other check/behaviour/grant is the
-- original. No table/RPC/data is dropped; P1a objects are untouched; the applied
-- Phase 16C migration is not edited. Run on Digi_SEO_Test only, and only if
-- instructed to roll P1b back.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.seo_crawl_request(
  p_website_id uuid,
  p_idempotency_key text DEFAULT NULL,
  p_config jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_url text;
  v_active boolean;
  v_archived timestamptz;
  v_role text;
  v_key text;
  v_config jsonb;
  v_existing uuid;
  v_job_id uuid;
BEGIN
  -- 1. Authenticated.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. SEO module access (authoritative Stage 1 helper).
  IF NOT public.has_seo_module_access(v_uid) THEN
    RAISE EXCEPTION 'SEO module access required';
  END IF;

  -- 3. Resolve workspace + eligibility fields SERVER-SIDE from the website id.
  --    Client-supplied workspace/url are never trusted.
  SELECT workspace_id, website_url, is_active, archived_at
    INTO v_ws, v_url, v_active, v_archived
  FROM public.seo_websites WHERE id = p_website_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Website % does not exist', p_website_id;
  END IF;

  -- 4. Role check: owner/admin/team_member or global admin (client denied).
  IF public.seo_is_global_admin(v_uid) THEN
    v_role := 'global_admin';
  ELSIF public.seo_role_in(v_ws, ARRAY['owner'], v_uid) THEN
    v_role := 'owner';
  ELSIF public.seo_role_in(v_ws, ARRAY['admin'], v_uid) THEN
    v_role := 'admin';
  ELSIF public.seo_role_in(v_ws, ARRAY['team_member'], v_uid) THEN
    v_role := 'team_member';
  ELSE
    RAISE EXCEPTION 'Not permitted to request a crawl for this website';
  END IF;

  -- 5. Website crawl eligibility (NOT domain-ownership — see migration notes).
  IF v_active IS NOT TRUE OR v_archived IS NOT NULL THEN
    RAISE EXCEPTION 'Website is not eligible for crawling (inactive or archived)';
  END IF;

  -- 6. URL sanity (http/https only). Deep SSRF/redirect checks are the worker's
  --    execution-safety responsibility (documented), not this gate.
  IF v_url !~* '^https?://[^[:space:]]+$' THEN
    RAISE EXCEPTION 'Website URL is not a crawlable http(s) URL';
  END IF;

  -- 7. Idempotency key (accept a safe caller key or generate one).
  v_key := btrim(coalesce(p_idempotency_key, ''));
  IF v_key = '' THEN
    v_key := 'auto-' || gen_random_uuid()::text;
  ELSIF length(v_key) > 200 THEN
    RAISE EXCEPTION 'idempotency key too long';
  END IF;

  -- Same idempotency key in this workspace → return the existing job (idempotent).
  SELECT id INTO v_existing
  FROM public.seo_crawl_jobs
  WHERE workspace_id = v_ws AND idempotency_key = v_key;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- 8. Config snapshot (validated + normalized).
  v_config := public.seo_crawl_normalize_config(p_config);

  -- 9. Atomic create. The partial unique index rejects a SECOND active job for
  --    the same website with a clear conflict error.
  BEGIN
    INSERT INTO public.seo_crawl_jobs
      (workspace_id, website_id, website_url, requested_by, requested_role_snapshot,
       status, trigger_source, idempotency_key, config)
    VALUES
      (v_ws, p_website_id, v_url, v_uid, v_role,
       'queued', 'manual', v_key, v_config)
    RETURNING id INTO v_job_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'An active crawl already exists for this website';
  END;

  -- 10. Initial lifecycle event (append-only).
  INSERT INTO public.seo_crawl_events
    (job_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (v_job_id, v_ws, p_website_id, 'queued', NULL, 'queued',
     'customer', v_uid, v_role, 'Crawl requested');

  RETURN v_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.seo_crawl_request(uuid, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_request(uuid, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_crawl_request(uuid, text, jsonb) TO authenticated;

SELECT 'P1b ROLLBACK COMPLETE — seo_crawl_request restored to pre-P1b (Phase 16C) body' AS result;
