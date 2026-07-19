-- =============================================================================
-- SEO Backend — Phase 16C — Migration 25: Crawler Job Control Plane (additive)
-- =============================================================================
-- Additive only. Establishes the DATABASE CONTRACT for crawler jobs: job
-- storage, an append-only event history, per-attempt execution rows, guarded
-- customer RPCs (request + cancel), and a service-role-only worker claim
-- function. It does NOT crawl anything — no worker, Edge Function, sitemap,
-- HTML download, robots.txt, URL extraction, issue detection, audit/page
-- population, scheduling, or GSC/GA4/LLM integration is built here (Phase 1B+).
--
-- Architecture (approved — ADR_CRAWLER_RUNTIME_ARCHITECTURE.md, Option C hybrid):
--   * Frontend → guarded SECURITY DEFINER RPC to request/cancel a crawl.
--   * Supabase = job/status/ownership/result store; RLS-scoped customer reads.
--   * A future service-role WORKER claims + executes jobs (not in this phase).
--   * No BFF; the service-role key lives only in the future worker runtime.
--
-- Security model mirrors the existing Stage 6 RPCs: SECURITY DEFINER +
-- `SET search_path = public`; workspace resolved SERVER-SIDE from website_id
-- (client workspace_id/url never trusted); role check IN-function via
-- seo_role_in()/seo_is_global_admin(); EXECUTE granted narrowly with PUBLIC/anon
-- revoked. RLS is default-deny: customers never write job/attempt/event rows
-- directly. No secrets/credentials/authorization headers are stored here.
--
-- Role decision (documented): crawl request + cancel = owner/admin/team_member
-- or global admin. `client` = DENIED (mirrors campaign-create; no product rule
-- says clients may trigger crawls). Reads follow the existing workspace-member
-- rule (clients, as members, may read customer-safe job/event fields).
--
-- Usage/plan limits: DEFERRED (documented). seo_plan_limits has no crawl columns
-- and seo_usage_events (append-only counter) cannot cleanly model
-- reserve→start→complete→release, so forcing it now would be fragile. This
-- migration enforces only the DB-level duplicate-active-job guard; per-period /
-- concurrency plan enforcement is a documented Phase 1B/1C follow-up.
--
-- Website eligibility: workspace membership + is_active + not archived. TRUE
-- external domain-ownership verification does NOT exist in the schema and is a
-- documented PREREQUISITE for live crawling — this contract does not claim it.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. seo_crawl_jobs — one requested crawl (customer-facing, RLS-scoped).
--    Initial status is 'queued': the request RPC validates eligibility
--    synchronously, so 'requested' collapses into 'queued' atomically.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                                  -- snapshot at request time
  requested_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  requested_role_snapshot text NOT NULL
    CHECK (requested_role_snapshot IN ('owner', 'admin', 'team_member', 'global_admin')),
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'claimed', 'running', 'retry_wait',
                      'cancellation_requested', 'completed', 'partially_completed',
                      'failed', 'cancelled')),
  trigger_source text NOT NULL DEFAULT 'manual'
    CHECK (trigger_source IN ('manual', 'scheduled', 'system')),
  idempotency_key text NOT NULL,
  config jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(config) = 'object'),                 -- immutable budget/config snapshot
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  max_attempts integer NOT NULL DEFAULT 3 CHECK (max_attempts > 0),
  pages_discovered integer NOT NULL DEFAULT 0 CHECK (pages_discovered >= 0),
  pages_crawled integer NOT NULL DEFAULT 0 CHECK (pages_crawled >= 0),
  requested_at timestamptz NOT NULL DEFAULT now(),
  queued_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  started_at timestamptz,
  heartbeat_at timestamptz,
  lease_expires_at timestamptz,
  retry_after timestamptz,                                   -- when a retry_wait job becomes eligible
  completed_at timestamptz,
  cancellation_requested_at timestamptz,
  cancelled_at timestamptz,
  error_code text,                                           -- customer-safe
  error_message text,                                        -- customer-safe
  correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),    -- trace id
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seo_crawl_jobs_idempotency_uniq UNIQUE (workspace_id, idempotency_key)
);

-- At most ONE active (non-terminal) job per website — DB-level dedup, not a
-- race-prone check-then-insert.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_crawl_jobs_active_per_website
  ON public.seo_crawl_jobs (website_id)
  WHERE status IN ('queued', 'claimed', 'running', 'retry_wait', 'cancellation_requested');

-- Query-purpose indexes.
CREATE INDEX IF NOT EXISTS idx_seo_crawl_jobs_workspace_recent
  ON public.seo_crawl_jobs (workspace_id, requested_at DESC);       -- workspace recent jobs
CREATE INDEX IF NOT EXISTS idx_seo_crawl_jobs_website_history
  ON public.seo_crawl_jobs (website_id, requested_at DESC);         -- website job history
CREATE INDEX IF NOT EXISTS idx_seo_crawl_jobs_claimable
  ON public.seo_crawl_jobs (status, queued_at)
  WHERE status IN ('queued', 'retry_wait');                         -- worker eligible-job claim
CREATE INDEX IF NOT EXISTS idx_seo_crawl_jobs_lease
  ON public.seo_crawl_jobs (lease_expires_at)
  WHERE status IN ('claimed', 'running');                           -- lease-expired recovery
CREATE INDEX IF NOT EXISTS idx_seo_crawl_jobs_correlation
  ON public.seo_crawl_jobs (correlation_id);                        -- trace lookup

-- ---------------------------------------------------------------------------
-- 2. seo_crawl_attempts — per-execution rows (INTERNAL diagnostics; worker-only).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  worker_id text,
  lease_expires_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  outcome text CHECK (outcome IN ('succeeded', 'partial', 'failed', 'cancelled', 'lease_expired')),
  retry_class text CHECK (retry_class IN ('retryable', 'non_retryable')),
  internal_error_code text,                                  -- INTERNAL — not customer-safe
  internal_error_detail text,                                -- INTERNAL — not customer-safe
  pages_crawled integer NOT NULL DEFAULT 0 CHECK (pages_crawled >= 0),
  http_requests integer NOT NULL DEFAULT 0 CHECK (http_requests >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seo_crawl_attempts_job_number_uniq UNIQUE (job_id, attempt_number)
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_attempts_job
  ON public.seo_crawl_attempts (job_id, attempt_number);

-- ---------------------------------------------------------------------------
-- 3. seo_crawl_events — append-only lifecycle history (customer-safe).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  event_type text NOT NULL
    CHECK (event_type IN ('queued', 'claimed', 'started', 'progress', 'retry_scheduled',
                          'cancellation_requested', 'completed', 'partially_completed',
                          'failed', 'cancelled', 'lease_expired')),
  from_status text,
  to_status text,
  actor text NOT NULL CHECK (actor IN ('customer', 'worker', 'system')),
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role_snapshot text,
  note text,                                                 -- customer-safe only
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_events_job
  ON public.seo_crawl_events (job_id, created_at);

-- ---------------------------------------------------------------------------
-- 4. Triggers: updated_at + workspace/website cross-integrity (defense-in-depth;
--    the request RPC already resolves workspace from website_id).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_crawl_jobs_updated_at ON public.seo_crawl_jobs;
CREATE TRIGGER trg_seo_crawl_jobs_updated_at BEFORE UPDATE ON public.seo_crawl_jobs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.seo_crawl_job_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ws uuid;
BEGIN
  SELECT workspace_id INTO v_ws FROM public.seo_websites WHERE id = NEW.website_id;
  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'seo_crawl_jobs: website % does not exist', NEW.website_id;
  END IF;
  IF v_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'seo_crawl_jobs: website % does not belong to workspace %',
      NEW.website_id, NEW.workspace_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_seo_crawl_jobs_integrity ON public.seo_crawl_jobs;
CREATE TRIGGER trg_seo_crawl_jobs_integrity
  BEFORE INSERT OR UPDATE OF workspace_id, website_id ON public.seo_crawl_jobs
  FOR EACH ROW EXECUTE FUNCTION public.seo_crawl_job_integrity();

-- ---------------------------------------------------------------------------
-- 5. RLS — default deny; customer reads only; writes via RPC/worker only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_crawl_jobs ENABLE ROW LEVEL SECURITY;
-- Workspace members (incl. clients) read customer-safe job fields; global admin all.
DROP POLICY IF EXISTS seo_crawl_jobs_select ON public.seo_crawl_jobs;
CREATE POLICY seo_crawl_jobs_select ON public.seo_crawl_jobs
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );
-- No INSERT/UPDATE/DELETE policy for authenticated → all customer writes denied.
-- Creation + cancellation happen through SECURITY DEFINER RPCs; execution writes
-- happen via the service-role worker (which bypasses RLS).

ALTER TABLE public.seo_crawl_attempts ENABLE ROW LEVEL SECURITY;
-- Attempts hold INTERNAL diagnostics → NO customer read. Global admin only.
DROP POLICY IF EXISTS seo_crawl_attempts_select ON public.seo_crawl_attempts;
CREATE POLICY seo_crawl_attempts_select ON public.seo_crawl_attempts
  FOR SELECT USING (public.seo_is_global_admin());
-- No customer insert/update/delete policy.

ALTER TABLE public.seo_crawl_events ENABLE ROW LEVEL SECURITY;
-- Workspace members read customer-safe events; global admin all. Append-only:
-- no INSERT/UPDATE/DELETE policy for authenticated (inserts via RPC/worker only).
DROP POLICY IF EXISTS seo_crawl_events_select ON public.seo_crawl_events;
CREATE POLICY seo_crawl_events_select ON public.seo_crawl_events
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

-- ---------------------------------------------------------------------------
-- 6. Config validation helper — validates + normalizes the request-time budget
--    snapshot. Only known keys with safe types/bounds are accepted; unknown
--    keys or bad types raise. Returns the merged (defaults <- provided) object.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_normalize_config(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_defaults jsonb := jsonb_build_object(
    'max_pages', 100,
    'max_depth', 3,
    'crawl_timeout_seconds', 900,
    'per_host_delay_ms', 1000,
    'use_sitemap', true,
    'respect_robots', true,
    'user_agent_profile', 'digibility-seo-crawler',
    'max_response_bytes', 5242880,
    'mime_allowlist_id', 'html_text_v1'
  );
  v_allowed text[] := ARRAY['max_pages','max_depth','crawl_timeout_seconds','per_host_delay_ms',
                            'use_sitemap','respect_robots','user_agent_profile',
                            'max_response_bytes','mime_allowlist_id'];
  v_in jsonb := coalesce(p_config, '{}'::jsonb);
  v_out jsonb := v_defaults;
  v_key text;
BEGIN
  IF jsonb_typeof(v_in) <> 'object' THEN
    RAISE EXCEPTION 'crawl config must be a JSON object';
  END IF;
  FOR v_key IN SELECT jsonb_object_keys(v_in) LOOP
    IF NOT (v_key = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'crawl config: unsupported key "%"', v_key;
    END IF;
  END LOOP;
  -- Bounded numeric knobs.
  IF v_in ? 'max_pages' THEN
    IF jsonb_typeof(v_in->'max_pages') <> 'number' OR (v_in->>'max_pages')::int < 1 OR (v_in->>'max_pages')::int > 5000 THEN
      RAISE EXCEPTION 'crawl config: max_pages must be 1..5000';
    END IF;
    v_out := jsonb_set(v_out, '{max_pages}', to_jsonb((v_in->>'max_pages')::int));
  END IF;
  IF v_in ? 'max_depth' THEN
    IF jsonb_typeof(v_in->'max_depth') <> 'number' OR (v_in->>'max_depth')::int < 1 OR (v_in->>'max_depth')::int > 10 THEN
      RAISE EXCEPTION 'crawl config: max_depth must be 1..10';
    END IF;
    v_out := jsonb_set(v_out, '{max_depth}', to_jsonb((v_in->>'max_depth')::int));
  END IF;
  IF v_in ? 'crawl_timeout_seconds' THEN
    IF jsonb_typeof(v_in->'crawl_timeout_seconds') <> 'number' OR (v_in->>'crawl_timeout_seconds')::int < 30 OR (v_in->>'crawl_timeout_seconds')::int > 3600 THEN
      RAISE EXCEPTION 'crawl config: crawl_timeout_seconds must be 30..3600';
    END IF;
    v_out := jsonb_set(v_out, '{crawl_timeout_seconds}', to_jsonb((v_in->>'crawl_timeout_seconds')::int));
  END IF;
  IF v_in ? 'per_host_delay_ms' THEN
    IF jsonb_typeof(v_in->'per_host_delay_ms') <> 'number' OR (v_in->>'per_host_delay_ms')::int < 0 OR (v_in->>'per_host_delay_ms')::int > 60000 THEN
      RAISE EXCEPTION 'crawl config: per_host_delay_ms must be 0..60000';
    END IF;
    v_out := jsonb_set(v_out, '{per_host_delay_ms}', to_jsonb((v_in->>'per_host_delay_ms')::int));
  END IF;
  IF v_in ? 'max_response_bytes' THEN
    IF jsonb_typeof(v_in->'max_response_bytes') <> 'number' OR (v_in->>'max_response_bytes')::bigint < 1024 OR (v_in->>'max_response_bytes')::bigint > 52428800 THEN
      RAISE EXCEPTION 'crawl config: max_response_bytes must be 1024..52428800';
    END IF;
    v_out := jsonb_set(v_out, '{max_response_bytes}', to_jsonb((v_in->>'max_response_bytes')::bigint));
  END IF;
  -- Booleans.
  IF v_in ? 'use_sitemap' THEN
    IF jsonb_typeof(v_in->'use_sitemap') <> 'boolean' THEN RAISE EXCEPTION 'crawl config: use_sitemap must be boolean'; END IF;
    v_out := jsonb_set(v_out, '{use_sitemap}', v_in->'use_sitemap');
  END IF;
  IF v_in ? 'respect_robots' THEN
    IF jsonb_typeof(v_in->'respect_robots') <> 'boolean' THEN RAISE EXCEPTION 'crawl config: respect_robots must be boolean'; END IF;
    -- respect_robots may not be disabled through this contract (safety).
    IF (v_in->>'respect_robots')::boolean = false THEN
      RAISE EXCEPTION 'crawl config: respect_robots cannot be disabled';
    END IF;
    v_out := jsonb_set(v_out, '{respect_robots}', v_in->'respect_robots');
  END IF;
  -- Constrained identifiers.
  IF v_in ? 'user_agent_profile' THEN
    IF (v_in->>'user_agent_profile') <> 'digibility-seo-crawler' THEN
      RAISE EXCEPTION 'crawl config: unsupported user_agent_profile';
    END IF;
  END IF;
  IF v_in ? 'mime_allowlist_id' THEN
    IF (v_in->>'mime_allowlist_id') <> 'html_text_v1' THEN
      RAISE EXCEPTION 'crawl config: unsupported mime_allowlist_id';
    END IF;
  END IF;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_crawl_normalize_config(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_normalize_config(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_crawl_normalize_config(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. seo_crawl_request — guarded customer enqueue RPC.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 8. seo_crawl_cancel — guarded customer cancellation RPC (idempotent).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_cancel(p_job_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_website uuid;
  v_status text;
  v_role text;
  v_new_status text;
  v_event text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT workspace_id, website_id, status INTO v_ws, v_website, v_status
  FROM public.seo_crawl_jobs WHERE id = p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Crawl job % does not exist', p_job_id;
  END IF;

  -- Same role rule as request: owner/admin/team_member or global admin.
  IF public.seo_is_global_admin(v_uid) THEN
    v_role := 'global_admin';
  ELSIF public.seo_role_in(v_ws, ARRAY['owner','admin','team_member'], v_uid) THEN
    v_role := (SELECT seo_role FROM public.seo_workspace_members
               WHERE workspace_id = v_ws AND user_id = v_uid AND status = 'active');
  ELSE
    RAISE EXCEPTION 'Not permitted to cancel crawls for this workspace';
  END IF;

  -- Terminal / already-requested → idempotent no-op (return current status).
  IF v_status IN ('completed', 'partially_completed', 'failed', 'cancelled', 'cancellation_requested') THEN
    RETURN v_status;
  END IF;

  IF v_status IN ('queued', 'retry_wait') THEN
    -- Unclaimed → cancel immediately (safe).
    v_new_status := 'cancelled';
    v_event := 'cancelled';
    UPDATE public.seo_crawl_jobs
      SET status = 'cancelled',
          cancellation_requested_at = now(),
          cancelled_at = now()
      WHERE id = p_job_id;
  ELSE
    -- claimed/running → request cancellation; the worker finalizes.
    v_new_status := 'cancellation_requested';
    v_event := 'cancellation_requested';
    UPDATE public.seo_crawl_jobs
      SET status = 'cancellation_requested',
          cancellation_requested_at = now()
      WHERE id = p_job_id;
  END IF;

  INSERT INTO public.seo_crawl_events
    (job_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (p_job_id, v_ws, v_website, v_event, v_status, v_new_status,
     'customer', v_uid, v_role, 'Cancellation requested by customer');

  RETURN v_new_status;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_crawl_cancel(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_cancel(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_crawl_cancel(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. seo_crawl_claim_job — SERVICE-ROLE-ONLY atomic worker claim. Defines the
--    contract for the future worker (not built here). NOT callable by
--    authenticated/anon. Uses FOR UPDATE SKIP LOCKED so two workers never claim
--    the same job; skips cancellation_requested/terminal jobs.
-- ---------------------------------------------------------------------------
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
  lease_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
  v_attempt integer;
  v_lease timestamptz;
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
    RETURN;  -- nothing to claim
  END IF;

  v_attempt := v_job.attempt_count + 1;
  v_lease := now() + make_interval(secs => p_lease_seconds);

  INSERT INTO public.seo_crawl_attempts
    (job_id, workspace_id, attempt_number, worker_id, lease_expires_at, started_at)
  VALUES
    (v_job.id, v_job.workspace_id, v_attempt, p_worker_id, v_lease, now());

  UPDATE public.seo_crawl_jobs
    SET status = 'running',
        attempt_count = v_attempt,
        claimed_at = coalesce(claimed_at, now()),
        started_at = coalesce(started_at, now()),
        heartbeat_at = now(),
        lease_expires_at = v_lease,
        retry_after = NULL
    WHERE id = v_job.id;

  INSERT INTO public.seo_crawl_events
    (job_id, workspace_id, website_id, event_type, from_status, to_status, actor, note)
  VALUES
    (v_job.id, v_job.workspace_id, v_job.website_id, 'claimed', v_job.status, 'running',
     'worker', 'Claimed by worker ' || p_worker_id);

  RETURN QUERY SELECT v_job.id, v_job.website_id, v_job.website_url, v_job.workspace_id,
                      v_attempt, v_job.config, v_lease;
END;
$$;
-- Worker-only: NOT authenticated/anon. service_role keeps its default grant
-- (Supabase trusted backend role, only in the future worker runtime).
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.seo_crawl_claim_job(text, integer) FROM authenticated;

-- =============================================================================
-- End Phase 16C crawler control-plane contract. Deferred to Phase 1B+: the
-- worker itself, heartbeat/terminal-completion functions, stale-lease reaper,
-- customer-triggered retry RPC, plan/usage enforcement, and external
-- domain-ownership verification. No existing object was altered; no crawling
-- runs; production untouched.
-- =============================================================================
