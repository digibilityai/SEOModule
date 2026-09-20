-- =============================================================================
-- SEO Backend, Digi Brain Module Contract v1, Stage 2B amendment, Migration 4:
--   delegated, service-role-only WRITE + STATUS RPCs for the machine boundary
-- =============================================================================
-- Additive only. Adds the Brain-action correlation record and four functions
-- backing the two delegated write capabilities and their STATUS follow-ups.
-- Edits no existing table, policy, RPC or migration.
--
-- THE EXISTING AUTHORIZATION PATH IS REUSED, NOT REIMPLEMENTED.
-- public.seo_crawl_request_audit and public.seo_recommendation_generate both
-- authorize on auth.uid(). Rather than copy their rules (which would drift) or
-- weaken them (which would defeat the point), each wrapper below resolves the
-- acting human deterministically, checks membership and role itself as a first
-- gate, and then sets request.jwt.claims for the acting SEO user so the
-- EXISTING RPC runs its own unmodified checks against that identity. The
-- verified-ownership requirement, the single-active-job rule, idempotency,
-- config normalization, the role matrix and every append-only event therefore
-- behave exactly as they do for a human in the browser, and
-- seo_crawl_jobs.requested_by records the real person rather than a system
-- account. public.seo_run_audit is never called: it is a stub that creates a
-- run row and no findings.
--
-- WHY SECURITY DEFINER HERE, WHEN THE READ RPCs ARE SECURITY INVOKER.
-- The read functions in migration 20260920120100 are INVOKER because
-- service_role already bypasses RLS and needed no extra privilege. These four
-- are different: they must INVOKE seo_crawl_request_audit and
-- seo_recommendation_generate, which are granted to `authenticated` only. The
-- alternative is granting service_role EXECUTE on those two locked customer
-- RPCs, which would widen a locked module's grant surface. Running as the
-- function owner keeps that surface untouched. search_path is pinned on all
-- four, and all four are revoked from PUBLIC, anon and authenticated.
--
-- SETTING request.jwt.claims IS SCOPED AND RESTORED.
-- set_config(..., true) is transaction local, so the impersonation cannot
-- outlive the statement's transaction. Each wrapper also restores the previous
-- value explicitly on both the success and the failure path, so nothing later
-- in the same transaction observes a borrowed identity.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Brain-action correlation record.
--
--    Contract v1's STATUS exchange correlates by brainActionId, optionally
--    assisted by moduleOperationId. SEO needs somewhere to record that
--    correlation, scoped to the exact Business and website, so that a STATUS
--    call can resolve the same operation and an operation belonging to another
--    website fails closed rather than answering.
--
--    This is a correlation index, not a second source of truth. For a technical
--    audit the live status is always re-read from seo_crawl_jobs; this table
--    only says which job belongs to which Brain action.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_brain_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id text NOT NULL,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  capability text NOT NULL
    CHECK (capability IN ('execute.technical_audit', 'execute.recommendations')),
  -- Brain owned. Opaque here, stored only as a correlation reference.
  brain_action_id text NOT NULL,
  idempotency_key text NOT NULL,
  -- The handle returned to Brain. For a technical audit this is the REAL
  -- seo_crawl_jobs.id; for recommendation generation, which completes
  -- synchronously and has no job of its own, it is this row's own id.
  module_operation_id text NOT NULL,
  module_status text NOT NULL,
  -- Truthful attribution of who the operation actually ran as.
  brain_actor_id text,
  acted_as_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- One operation per Business + website + capability + Brain action. A retry
  -- of the same logical call resolves to the same row rather than starting a
  -- second operation, which is what Contract v1's idempotencyKey is for.
  --
  -- website_id is part of the key because every lookup in this file is scoped
  -- by website. Without it, one Business with two linked websites reusing a
  -- Brain action id would collide across them: the recommendation insert below
  -- would fail outright, and the audit insert's ON CONFLICT would update the
  -- OTHER website's row while returning this website's job id, leaving that
  -- row's stored handle pointing at a job the subsequent website-scoped STATUS
  -- lookup can never match. Scoping the key exactly as the lookups scope keeps
  -- idempotency per website intact and makes the collision impossible.
  CONSTRAINT seo_brain_operations_action_uniq
    UNIQUE (business_id, website_id, capability, brain_action_id)
);

CREATE INDEX IF NOT EXISTS idx_seo_brain_operations_website
  ON public.seo_brain_operations (website_id);
-- No separate lookup index: seo_brain_operations_action_uniq already indexes
-- (business_id, website_id, capability, brain_action_id), which is exactly the
-- shape every correlation lookup below uses.
CREATE INDEX IF NOT EXISTS idx_seo_brain_operations_module_op
  ON public.seo_brain_operations (module_operation_id);

DROP TRIGGER IF EXISTS trg_seo_brain_operations_updated_at ON public.seo_brain_operations;
CREATE TRIGGER trg_seo_brain_operations_updated_at
  BEFORE UPDATE ON public.seo_brain_operations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.seo_brain_operations ENABLE ROW LEVEL SECURITY;

-- Members of the website's workspace may read what Brain has asked for on
-- their behalf. No human write path: these rows are written by the delegated
-- wrappers only.
DROP POLICY IF EXISTS seo_brain_operations_select ON public.seo_brain_operations;
CREATE POLICY seo_brain_operations_select
  ON public.seo_brain_operations
  FOR SELECT
  TO authenticated
  USING (
    public.is_seo_workspace_member(workspace_id)
    OR public.seo_is_global_admin()
  );

-- ---------------------------------------------------------------------------
-- 2. Shared authorization for a delegated write.
--
--    Resolves the target and the actor independently, then applies the SAME
--    role matrix the underlying RPCs use (owner/admin/team_member, or global
--    admin) as a first gate. The underlying RPC applies it again for real.
--
--    Returns one row always, so the caller can tell each refusal apart. Note
--    that `actor_not_linked` and `actor_unauthorized` are different facts: the
--    first means no mapping exists, the second means the mapped human simply
--    does not have permission on this workspace. A mapping never grants
--    anything on its own.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_authorize_delegated(
  p_business_id text,
  p_normalized_host text,
  p_brain_actor_id text
)
RETURNS TABLE (
  resolution   text,
  workspace_id uuid,
  website_id   uuid,
  seo_user_id  uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target record;
  v_user   uuid;
BEGIN
  resolution   := 'not_linked';
  workspace_id := NULL;
  website_id   := NULL;
  seo_user_id  := NULL;

  SELECT * INTO v_target
  FROM public.seo_brain_resolve_target(p_business_id, p_normalized_host);

  IF v_target.resolution <> 'resolved' THEN
    resolution := v_target.resolution;
    RETURN NEXT;
    RETURN;
  END IF;

  workspace_id := v_target.workspace_id;
  website_id   := v_target.website_id;

  -- A delegated write always needs a human. An automated Brain request with no
  -- actorId cannot perform one, and is refused rather than run as a system
  -- account that no audit reader could hold responsible.
  IF btrim(coalesce(p_brain_actor_id, '')) = '' THEN
    resolution := 'actor_required';
    RETURN NEXT;
    RETURN;
  END IF;

  v_user := public.seo_brain_resolve_actor(p_brain_actor_id);
  IF v_user IS NULL THEN
    resolution := 'actor_not_linked';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Identity established. Authorization starts here, and the mapping itself
  -- contributes nothing to it.
  IF NOT public.has_seo_module_access(v_user) THEN
    resolution := 'actor_unauthorized';
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT (public.seo_is_global_admin(v_user)
          OR public.seo_role_in(v_target.workspace_id,
                                ARRAY['owner', 'admin', 'team_member'], v_user)) THEN
    resolution := 'actor_unauthorized';
    RETURN NEXT;
    RETURN;
  END IF;

  resolution  := 'resolved';
  seo_user_id := v_user;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. execute.technical_audit
--
--    Reuses public.seo_crawl_request_audit verbatim. That RPC creates the audit
--    run and the crawl job through the unchanged generic enqueue path, which
--    enforces verified domain ownership (P1b), website eligibility, the single
--    active job rule and idempotency. No second queue is introduced, and the
--    crawler worker remains the only thing that executes a crawl.
--    public.seo_run_audit is never called: it is a stub that creates a run row
--    and no findings.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_request_technical_audit(
  p_business_id text,
  p_normalized_host text,
  p_brain_actor_id text,
  p_brain_action_id text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth         record;
  v_prev_claims  text;
  v_business     text := btrim(coalesce(p_business_id, ''));
  v_key          text := btrim(coalesce(p_idempotency_key, ''));
  v_action       text := btrim(coalesce(p_brain_action_id, ''));
  v_existing_op  text;
  v_live_status  text;
  v_ownership    text;
  v_audit_run    uuid;
  v_job_id       uuid;
  v_job_status   text;
  v_detail       text;
  v_crawl_key    text;
BEGIN
  IF v_action = '' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'brain_action_id is required');
  END IF;
  IF v_key = '' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'idempotency_key is required');
  END IF;

  SELECT * INTO v_auth
  FROM public.seo_brain_authorize_delegated(p_business_id, p_normalized_host, p_brain_actor_id);

  IF v_auth.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_auth.resolution);
  END IF;

  -- Idempotent replay: the same Brain action resolves to the same operation
  -- without enqueuing a second crawl.
  SELECT o.module_operation_id INTO v_existing_op
  FROM public.seo_brain_operations o
  WHERE o.business_id = v_business
    AND o.capability = 'execute.technical_audit'
    AND o.brain_action_id = v_action
    AND o.website_id = v_auth.website_id;

  IF FOUND THEN
    -- Live status is re-read from the job itself, re-scoped to this website.
    SELECT j.status INTO v_live_status
    FROM public.seo_crawl_jobs j
    WHERE j.id = v_existing_op::uuid
      AND j.website_id = v_auth.website_id;

    RETURN jsonb_build_object(
      'resolution',        'resolved',
      'websiteId',         v_auth.website_id,
      'moduleOperationId', v_existing_op,
      'moduleStatus',      coalesce(v_live_status, 'unknown'),
      'actedAsUserId',     v_auth.seo_user_id,
      'replayed',          true
    );
  END IF;

  -- Pre-check ownership so the refusal carries a truthful, specific reason.
  -- seo_crawl_request enforces this again authoritatively, under a row lock.
  SELECT v.status INTO v_ownership
  FROM public.seo_ownership_verifications v
  WHERE v.website_id = v_auth.website_id AND v.method = 'dns_txt';

  IF coalesce(v_ownership, 'not_started') <> 'verified' THEN
    RETURN jsonb_build_object(
      'resolution',      'ownership_not_verified',
      'websiteId',       v_auth.website_id,
      'ownershipStatus', coalesce(v_ownership, 'not_started')
    );
  END IF;

  -- The crawl control plane's idempotency space is WORKSPACE scoped
  -- (seo_crawl_jobs is looked up by workspace_id + idempotency_key), while
  -- Brain derives one key per Brain action and capability, with no website in
  -- it. One Business with two linked websites in the same workspace would
  -- therefore hand the second website the FIRST website's crawl job. Binding
  -- the website into the key given to the control plane keeps replay of the
  -- same Brain action for the SAME website returning the same job, which is
  -- what idempotency is for, while giving a different website its own. Brain's
  -- own key is still what is stored on the operation row.
  v_crawl_key := v_key || '@' || v_auth.website_id::text;
  IF length(v_crawl_key) > 200 THEN
    RETURN jsonb_build_object(
      'resolution', 'invalid_request',
      'detail',     'idempotency_key is too long for the crawl control plane'
    );
  END IF;

  -- Act as the resolved human so the existing RPC's own checks run for real
  -- and seo_crawl_jobs.requested_by records the real person.
  v_prev_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_auth.seo_user_id::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    SELECT a.audit_run_id, a.crawl_job_id, a.job_status
      INTO v_audit_run, v_job_id, v_job_status
    FROM public.seo_crawl_request_audit(v_auth.website_id, v_crawl_key, NULL) a;
  EXCEPTION WHEN OTHERS THEN
    v_detail := SQLERRM;
    PERFORM set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);
    RETURN jsonb_build_object(
      'resolution', 'execution_failed',
      'websiteId',  v_auth.website_id,
      'detail',     v_detail
    );
  END;

  PERFORM set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);

  INSERT INTO public.seo_brain_operations
    (business_id, workspace_id, website_id, capability, brain_action_id,
     idempotency_key, module_operation_id, module_status, brain_actor_id, acted_as_user_id)
  VALUES
    (v_business, v_auth.workspace_id, v_auth.website_id, 'execute.technical_audit',
     v_action, v_key, v_job_id::text, v_job_status,
     btrim(coalesce(p_brain_actor_id, '')), v_auth.seo_user_id)
  ON CONFLICT ON CONSTRAINT seo_brain_operations_action_uniq DO UPDATE
    SET module_status = EXCLUDED.module_status, updated_at = now();

  RETURN jsonb_build_object(
    'resolution',        'resolved',
    'websiteId',         v_auth.website_id,
    'auditRunId',        v_audit_run,
    -- The REAL crawl job identifier, not a synthetic handle.
    'moduleOperationId', v_job_id::text,
    'moduleStatus',      v_job_status,
    'actedAsUserId',     v_auth.seo_user_id,
    'replayed',          false
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. STATUS for execute.technical_audit.
--
--    Scoped to the exact linked Business and website. A moduleOperationId that
--    exists but belongs to another website is refused rather than answered:
--    that is the cross-site correlation leak this function exists to prevent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_technical_audit_status(
  p_business_id text,
  p_normalized_host text,
  p_brain_action_id text,
  p_module_operation_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target    record;
  v_op_id     text;
  v_acted_as  uuid;
  v_status    text;
  v_supplied  text := btrim(coalesce(p_module_operation_id, ''));
BEGIN
  SELECT * INTO v_target
  FROM public.seo_brain_resolve_target(p_business_id, p_normalized_host);

  IF v_target.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_target.resolution);
  END IF;

  SELECT o.module_operation_id, o.acted_as_user_id
    INTO v_op_id, v_acted_as
  FROM public.seo_brain_operations o
  WHERE o.business_id = btrim(coalesce(p_business_id, ''))
    AND o.capability = 'execute.technical_audit'
    AND o.brain_action_id = btrim(coalesce(p_brain_action_id, ''))
    AND o.website_id = v_target.website_id;     -- scoping, not decoration

  IF NOT FOUND THEN
    RETURN jsonb_build_object('resolution', 'operation_not_found');
  END IF;

  -- When the caller supplies a handle it must be THIS operation's handle. A
  -- real handle from another website or another action fails closed.
  IF v_supplied <> '' AND v_supplied <> v_op_id THEN
    RETURN jsonb_build_object('resolution', 'operation_mismatch');
  END IF;

  -- Live truth comes from the crawl job itself, re-checked against the website.
  SELECT j.status INTO v_status
  FROM public.seo_crawl_jobs j
  WHERE j.id = v_op_id::uuid
    AND j.website_id = v_target.website_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('resolution', 'operation_not_found');
  END IF;

  RETURN jsonb_build_object(
    'resolution',        'resolved',
    'websiteId',         v_target.website_id,
    'moduleOperationId', v_op_id,
    'moduleStatus',      v_status,
    'actedAsUserId',     v_acted_as
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. execute.recommendations
--
--    Reuses public.seo_recommendation_generate verbatim. That RPC derives
--    recommendations from real crawler issues on the latest COMPLETED audit run
--    and stamps generation_method. This wrapper additionally refuses to run at
--    all unless that latest completed run actually contains crawler-sourced
--    issues, so generation can never be delegated over a seeded or manual
--    audit.
--
--    Generation is synchronous, so the acknowledgement is already terminal. It
--    is still recorded as an operation so STATUS can resolve it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_generate_recommendations(
  p_business_id text,
  p_normalized_host text,
  p_brain_actor_id text,
  p_brain_action_id text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth          record;
  v_prev_claims   text;
  v_business      text := btrim(coalesce(p_business_id, ''));
  v_action        text := btrim(coalesce(p_brain_action_id, ''));
  v_key           text := btrim(coalesce(p_idempotency_key, ''));
  v_existing_op   text;
  v_existing_stat text;
  v_run_id        uuid;
  v_crawler_n     integer;
  v_generated     integer;
  v_method        text;
  v_module_op     text;
  v_detail        text;
BEGIN
  IF v_action = '' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'brain_action_id is required');
  END IF;
  IF v_key = '' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'idempotency_key is required');
  END IF;

  SELECT * INTO v_auth
  FROM public.seo_brain_authorize_delegated(p_business_id, p_normalized_host, p_brain_actor_id);

  IF v_auth.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_auth.resolution);
  END IF;

  SELECT o.module_operation_id, o.module_status
    INTO v_existing_op, v_existing_stat
  FROM public.seo_brain_operations o
  WHERE o.business_id = v_business
    AND o.capability = 'execute.recommendations'
    AND o.brain_action_id = v_action
    AND o.website_id = v_auth.website_id;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'resolution',        'resolved',
      'websiteId',         v_auth.website_id,
      'moduleOperationId', v_existing_op,
      'moduleStatus',      v_existing_stat,
      'actedAsUserId',     v_auth.seo_user_id,
      'replayed',          true
    );
  END IF;

  -- The audit this generation derives from must be genuine crawler evidence.
  -- Without this gate a website whose only completed run was seeded would
  -- produce recommendations that Contract v1 would then carry as genuine.
  SELECT r.id INTO v_run_id
  FROM public.seo_audit_runs r
  WHERE r.website_id = v_auth.website_id
    AND r.status = 'completed'
  ORDER BY r.completed_at DESC NULLS LAST, r.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('resolution', 'no_completed_audit', 'websiteId', v_auth.website_id);
  END IF;

  SELECT count(*) INTO v_crawler_n
  FROM public.seo_audit_issues i
  WHERE i.audit_run_id = v_run_id
    AND i.website_id = v_auth.website_id
    AND i.source = 'crawler';

  IF coalesce(v_crawler_n, 0) = 0 THEN
    RETURN jsonb_build_object('resolution', 'no_genuine_audit_evidence', 'websiteId', v_auth.website_id);
  END IF;

  v_prev_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_auth.seo_user_id::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    SELECT count(*) INTO v_generated
    FROM public.seo_recommendation_generate(v_auth.website_id);
  EXCEPTION WHEN OTHERS THEN
    v_detail := SQLERRM;
    PERFORM set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);
    RETURN jsonb_build_object(
      'resolution', 'execution_failed',
      'websiteId',  v_auth.website_id,
      'detail',     v_detail
    );
  END;

  PERFORM set_config('request.jwt.claims', coalesce(v_prev_claims, ''), true);

  -- Report the method actually stored on the rows, never a constant written
  -- here, so the response can never overstate how they were produced.
  SELECT rec.generation_method INTO v_method
  FROM public.seo_recommendations rec
  WHERE rec.website_id = v_auth.website_id
    AND rec.is_current
    AND rec.generation_method IS NOT NULL
  ORDER BY rec.updated_at DESC
  LIMIT 1;

  v_module_op := gen_random_uuid()::text;

  INSERT INTO public.seo_brain_operations
    (business_id, workspace_id, website_id, capability, brain_action_id,
     idempotency_key, module_operation_id, module_status, brain_actor_id, acted_as_user_id)
  VALUES
    (v_business, v_auth.workspace_id, v_auth.website_id, 'execute.recommendations',
     v_action, v_key, v_module_op, 'completed',
     btrim(coalesce(p_brain_actor_id, '')), v_auth.seo_user_id);

  RETURN jsonb_build_object(
    'resolution',       'resolved',
    'websiteId',        v_auth.website_id,
    'moduleOperationId', v_module_op,
    'moduleStatus',     'completed',
    'auditRunId',       v_run_id,
    'generatedCount',   coalesce(v_generated, 0),
    'generationMethod', v_method,
    'actedAsUserId',    v_auth.seo_user_id,
    'replayed',         false
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. STATUS for execute.recommendations. Same scoping rules as the audit
--    status: exact Business, exact website, exact operation or nothing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_recommendation_status(
  p_business_id text,
  p_normalized_host text,
  p_brain_action_id text,
  p_module_operation_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target   record;
  v_op_id    text;
  v_status   text;
  v_acted_as uuid;
  v_supplied text := btrim(coalesce(p_module_operation_id, ''));
BEGIN
  SELECT * INTO v_target
  FROM public.seo_brain_resolve_target(p_business_id, p_normalized_host);

  IF v_target.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_target.resolution);
  END IF;

  SELECT o.module_operation_id, o.module_status, o.acted_as_user_id
    INTO v_op_id, v_status, v_acted_as
  FROM public.seo_brain_operations o
  WHERE o.business_id = btrim(coalesce(p_business_id, ''))
    AND o.capability = 'execute.recommendations'
    AND o.brain_action_id = btrim(coalesce(p_brain_action_id, ''))
    AND o.website_id = v_target.website_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('resolution', 'operation_not_found');
  END IF;

  IF v_supplied <> '' AND v_supplied <> v_op_id THEN
    RETURN jsonb_build_object('resolution', 'operation_mismatch');
  END IF;

  RETURN jsonb_build_object(
    'resolution',        'resolved',
    'websiteId',         v_target.website_id,
    'moduleOperationId', v_op_id,
    'moduleStatus',      v_status,
    'actedAsUserId',     v_acted_as
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants. service_role only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_brain_authorize_delegated(text, text, text)',
    'public.seo_brain_request_technical_audit(text, text, text, text, text)',
    'public.seo_brain_technical_audit_status(text, text, text, text)',
    'public.seo_brain_generate_recommendations(text, text, text, text, text)',
    'public.seo_brain_recommendation_status(text, text, text, text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
