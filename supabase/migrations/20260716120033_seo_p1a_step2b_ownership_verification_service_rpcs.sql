-- =============================================================================
-- SEO Backend — P1a Step 2B — Migration 33: Service-role ownership-verification
--                              RPCs + global-admin override (additive)
-- =============================================================================
-- Additive only. Adds the TRUSTED backend API the FUTURE isolated DNS-TXT
-- verification worker (Step 3) and the global-admin administrative path will
-- call, on top of the Step 1 tables (`…120031`) and Step 2A customer RPCs
-- (`…120032`). NO worker, NO DNS resolution, NO frontend, NO crawl change here.
--
-- OBJECTS (all additive; no existing object altered):
--   * seo_ownership_verification_claims — INTERNAL claim/lease ledger (mirrors
--     the crawler's internal seo_crawl_attempts split). RLS: global-admin SELECT
--     only → lease tokens / worker ids / internal diagnostics are NOT customer-
--     readable. Lease metadata is kept OFF the customer-readable
--     seo_ownership_verifications table for exactly this reason.
--   * seo_ownership_verification_claim(text,int)          — SERVICE-ROLE ONLY.
--   * seo_ownership_verification_record_result(...)         — SERVICE-ROLE ONLY.
--   * seo_ownership_verification_admin_override(uuid,text,text) — authenticated,
--     internally global-admin-gated.
--
-- LEASE MODEL (mirrors Phase 16D, but on a NEW ownership-only table — the
-- crawler's tables/leases/statuses/RPCs are NOT reused or modified): claim
-- atomically selects one eligible pending/failed verification via
-- FOR UPDATE SKIP LOCKED, releases any expired open claim, and opens ONE new
-- claim (random lease_token + bounded lease_expires_at). A partial unique index
-- enforces at most one OPEN claim per verification. Result persistence validates
-- (verification_id, worker_id, lease_token) against the OPEN claim and rejects
-- stale/mismatched/cross-workspace/cross-website claims; duplicate identical
-- results are idempotent.
--
-- EXPLICITLY NOT IN THIS STEP: worker code / DNS resolver (Step 3); frontend /
-- supabaseTypes.ts (Steps 4-5); crawler worker files; crawl request/cancel/
-- claim/lifecycle/publishing/finalization RPCs; crawl statuses; crawl frontend;
-- Page Performance; Stage 6; P1b enqueue enforcement; production/infra.
-- Migrations `…120031`/`…120032` and every earlier migration are NOT edited.
--
-- SECURITY: SECURITY DEFINER + SET search_path=public; explicit grant/revoke;
-- service-role functions revoked from authenticated/anon/PUBLIC; the override
-- RPC revoked from anon and internally requires seo_is_global_admin; no client-
-- supplied workspace/host/role/status/ownership is trusted (all resolved
-- server-side); append-only customer audit preserved; internal diagnostics live
-- only on the admin-only claims table; customer-safe errors only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. seo_ownership_verification_claims — INTERNAL claim/lease ledger.
--    Global-admin SELECT only; no customer read; writes via service-role RPCs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_ownership_verification_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verification_id uuid NOT NULL REFERENCES public.seo_ownership_verifications(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  worker_id text NOT NULL,
  lease_token uuid NOT NULL,
  claimed_at timestamptz NOT NULL DEFAULT now(),
  lease_expires_at timestamptz NOT NULL,
  released_at timestamptz,
  outcome text CHECK (outcome IN ('verified', 'failed', 'released', 'lease_expired')),
  internal_error_code text,                                   -- INTERNAL — not customer-safe
  internal_error_detail text,                                 -- INTERNAL — not customer-safe
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_ownership_claims_verification
  ON public.seo_ownership_verification_claims (verification_id, created_at);
-- At most ONE open claim per verification (duplicate-concurrent-claim guard).
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_ownership_claims_open_per_verification
  ON public.seo_ownership_verification_claims (verification_id)
  WHERE released_at IS NULL;

ALTER TABLE public.seo_ownership_verification_claims ENABLE ROW LEVEL SECURITY;
-- INTERNAL diagnostics → NO customer read. Global admin only. No customer write
-- policy (writes happen via the SERVICE-ROLE RPCs below, which bypass RLS).
DROP POLICY IF EXISTS seo_ownership_verification_claims_select ON public.seo_ownership_verification_claims;
CREATE POLICY seo_ownership_verification_claims_select ON public.seo_ownership_verification_claims
  FOR SELECT USING (public.seo_is_global_admin());

-- ===========================================================================
-- 2. seo_ownership_verification_claim — SERVICE-ROLE-ONLY atomic claim.
--    Selects one eligible (pending|failed) dns_txt verification with no OPEN,
--    unexpired claim; releases expired open claims first (stale recovery); opens
--    one new lease. Returns ONLY the fields the DNS worker needs.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_claim(
  p_worker_id text,
  p_lease_seconds integer DEFAULT 120
)
RETURNS TABLE (
  verification_id uuid,
  workspace_id uuid,
  website_id uuid,
  verification_host text,
  dns_txt_name text,
  expected_challenge_value text,
  lease_token uuid,
  lease_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.seo_ownership_verifications%ROWTYPE;
  v_token uuid;
  v_lease timestamptz;
BEGIN
  IF coalesce(btrim(p_worker_id), '') = '' THEN
    RAISE EXCEPTION 'worker id required';
  END IF;
  IF p_lease_seconds < 30 OR p_lease_seconds > 3600 THEN
    RAISE EXCEPTION 'lease seconds must be 30..3600';
  END IF;

  -- Pick one eligible verification with NO open, unexpired claim.
  SELECT ov.* INTO v
  FROM public.seo_ownership_verifications ov
  WHERE ov.method = 'dns_txt'
    AND ov.status IN ('pending', 'failed')
    AND NOT EXISTS (
      SELECT 1 FROM public.seo_ownership_verification_claims c
      WHERE c.verification_id = ov.id
        AND c.released_at IS NULL
        AND c.lease_expires_at > now()
    )
  ORDER BY ov.updated_at ASC
  FOR UPDATE OF ov SKIP LOCKED
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;  -- nothing claimable
  END IF;

  -- Stale recovery: close any expired-but-open claim so the partial unique index
  -- is satisfied and the previous worker's lease_token is invalidated. The table
  -- is aliased because this function's RETURNS TABLE output columns share names
  -- with the claim columns (avoids an ambiguous-column reference).
  UPDATE public.seo_ownership_verification_claims AS oc
     SET released_at = now(), outcome = 'lease_expired'
   WHERE oc.verification_id = v.id AND oc.released_at IS NULL;

  v_token := gen_random_uuid();
  v_lease := now() + make_interval(secs => p_lease_seconds);

  INSERT INTO public.seo_ownership_verification_claims
    (verification_id, workspace_id, website_id, worker_id, lease_token, lease_expires_at)
  VALUES
    (v.id, v.workspace_id, v.website_id, p_worker_id, v_token, v_lease);

  RETURN QUERY SELECT
    v.id, v.workspace_id, v.website_id, v.verification_host,
    '_digibility-site-verification.' || v.verification_host,   -- DNS TXT record name
    v.challenge_token,                                         -- expected TXT value
    v_token, v_lease;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_claim(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_claim(text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_claim(text, integer) FROM authenticated;

-- ===========================================================================
-- 3. seo_ownership_verification_record_result — SERVICE-ROLE-ONLY result write.
--    Validates the OPEN claim (verification_id, worker_id, lease_token) +
--    workspace/website consistency; persists verified/failed (customer-safe) and
--    closes the claim (internal diagnostics stay on the claim row); appends one
--    customer event; duplicate identical results are idempotent; challenge token
--    is NOT rotated.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_record_result(
  p_verification_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_outcome text,
  p_failure_reason text DEFAULT NULL,
  p_internal_error_code text DEFAULT NULL,
  p_internal_error_detail text DEFAULT NULL
)
RETURNS public.seo_ownership_verifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.seo_ownership_verifications%ROWTYPE;
  c public.seo_ownership_verification_claims%ROWTYPE;
  v_target text;
  v_from text;
BEGIN
  IF p_outcome NOT IN ('verified', 'failed') THEN
    RAISE EXCEPTION 'Unsupported result outcome: %', p_outcome;
  END IF;

  SELECT * INTO v FROM public.seo_ownership_verifications WHERE id = p_verification_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verification % does not exist', p_verification_id;
  END IF;

  v_target := CASE p_outcome WHEN 'verified' THEN 'verified' ELSE 'failed' END;

  -- Find the OPEN claim matching the worker + lease.
  SELECT * INTO c FROM public.seo_ownership_verification_claims
   WHERE verification_id = p_verification_id
     AND worker_id = p_worker_id
     AND lease_token = p_lease_token
     AND released_at IS NULL
     AND lease_expires_at > now();

  IF NOT FOUND THEN
    -- Idempotent duplicate? A claim already CLOSED with this exact
    -- (worker, lease, outcome) and the verification already in the target state.
    IF EXISTS (
      SELECT 1 FROM public.seo_ownership_verification_claims c2
      WHERE c2.verification_id = p_verification_id
        AND c2.worker_id = p_worker_id
        AND c2.lease_token = p_lease_token
        AND c2.outcome = p_outcome
    ) AND v.status = v_target THEN
      RETURN v;  -- idempotent: no second update, no second event
    END IF;
    RAISE EXCEPTION 'Stale or mismatched claim for verification %', p_verification_id;
  END IF;

  -- Consistency: the claim must belong to the verification's workspace/website.
  IF c.workspace_id <> v.workspace_id OR c.website_id <> v.website_id THEN
    RAISE EXCEPTION 'Claim workspace/website mismatch for verification %', p_verification_id;
  END IF;

  v_from := v.status;

  IF p_outcome = 'verified' THEN
    UPDATE public.seo_ownership_verifications
       SET status = 'verified', verified_at = now(), last_checked_at = now(),
           failure_reason = NULL
     WHERE id = p_verification_id
     RETURNING * INTO v;                 -- challenge_token intentionally preserved
  ELSE
    UPDATE public.seo_ownership_verifications
       SET status = 'failed', last_checked_at = now(),
           failure_reason = left(coalesce(p_failure_reason, 'Verification failed'), 500)
     WHERE id = p_verification_id
     RETURNING * INTO v;                 -- challenge_token preserved
  END IF;

  -- Close the claim; internal diagnostics stay on the (admin-only) claim row.
  UPDATE public.seo_ownership_verification_claims
     SET released_at = now(), outcome = p_outcome,
         internal_error_code = p_internal_error_code,
         internal_error_detail = p_internal_error_detail
   WHERE id = c.id;

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_role_snapshot, note)
  VALUES
    (v.id, v.workspace_id, v.website_id, p_outcome, v_from, v_target,
     'worker', 'worker',
     CASE WHEN p_outcome = 'verified' THEN 'Ownership verified'
          ELSE 'Ownership verification failed' END);

  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_record_result(uuid, text, uuid, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_record_result(uuid, text, uuid, text, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_record_result(uuid, text, uuid, text, text, text, text) FROM authenticated;

-- ===========================================================================
-- 4. seo_ownership_verification_admin_override — authenticated, GLOBAL-ADMIN
--    ONLY. Narrow administrative actions: mark_verified | invalidate. Requires a
--    non-empty reason; resolves website/workspace/host server-side; appends one
--    'admin_override' event recording the action + actor. Idempotent on a repeat
--    of the same terminal action. Does NOT grant override to ordinary users and
--    does NOT weaken owner/admin customer permissions.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_admin_override(
  p_website_id uuid,
  p_action text,
  p_reason text
)
RETURNS public.seo_ownership_verifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_url text;
  v_host text;
  r public.seo_ownership_verifications%ROWTYPE;
  v_from text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.seo_is_global_admin(v_uid) THEN
    RAISE EXCEPTION 'Requires the global admin role.';
  END IF;
  IF p_action NOT IN ('mark_verified', 'invalidate') THEN
    RAISE EXCEPTION 'Unsupported admin override action: %', p_action;
  END IF;
  IF coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'An administrative reason is required';
  END IF;

  SELECT workspace_id, website_url INTO v_ws, v_url
  FROM public.seo_websites WHERE id = p_website_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Website % does not exist', p_website_id;
  END IF;
  IF v_url !~* '^https?://[^[:space:]]+$' THEN
    RAISE EXCEPTION 'Website URL is not a valid http(s) URL';
  END IF;
  v_host := public.seo_ownership_extract_host(v_url);

  SELECT * INTO r FROM public.seo_ownership_verifications
   WHERE website_id = p_website_id AND method = 'dns_txt';

  IF p_action = 'mark_verified' THEN
    IF FOUND AND r.status = 'verified' THEN
      RETURN r;  -- idempotent
    END IF;
    IF FOUND THEN
      v_from := r.status;
      UPDATE public.seo_ownership_verifications
         SET status = 'verified', verified_at = now(), failure_reason = NULL,
             verification_host = v_host, website_url = v_url
       WHERE id = r.id RETURNING * INTO r;
    ELSE
      v_from := NULL;
      INSERT INTO public.seo_ownership_verifications
        (workspace_id, website_id, website_url, verification_host, method, status,
         challenge_token, verified_at, created_by)
      VALUES
        (v_ws, p_website_id, v_url, v_host, 'dns_txt', 'verified',
         public.seo_ownership_new_challenge_token(), now(), v_uid)
      RETURNING * INTO r;
    END IF;
  ELSE  -- invalidate
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No verification record to invalidate for this website';
    END IF;
    IF r.status = 'revoked' THEN
      RETURN r;  -- idempotent
    END IF;
    v_from := r.status;
    UPDATE public.seo_ownership_verifications
       SET status = 'revoked', verified_at = NULL
     WHERE id = r.id RETURNING * INTO r;
  END IF;

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (r.id, r.workspace_id, r.website_id, 'admin_override', v_from, r.status,
     'global_admin', v_uid, 'global_admin',
     'Global-admin ' || p_action || ': ' || p_reason);

  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_admin_override(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_admin_override(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_ownership_verification_admin_override(uuid, text, text) TO authenticated;

-- =============================================================================
-- End P1a Step 2B. The DNS-TXT worker (Step 3), frontend (Steps 4-5), and P1b
-- enqueue enforcement remain excluded/unstarted. No worker code, no DNS
-- resolution, no crawl object, no Step 1/2A object, and no existing policy was
-- altered; production untouched.
-- =============================================================================
