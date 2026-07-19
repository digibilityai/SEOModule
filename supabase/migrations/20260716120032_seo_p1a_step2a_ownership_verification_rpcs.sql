-- =============================================================================
-- SEO Backend — P1a Step 2A — Migration 32: Guarded CUSTOMER ownership-
--                              verification RPCs (additive)
-- =============================================================================
-- Additive only. Adds ONLY the guarded, customer-facing database API for DNS-TXT
-- domain ownership verification, on top of the Step 1 tables (`…120031`). Every
-- RPC is SECURITY DEFINER + `SET search_path = public`, EXECUTE granted to
-- `authenticated` only (PUBLIC/anon revoked), authorizes SERVER-SIDE
-- (owner/admin only), resolves workspace/website/current-host/role server-side
-- (never trusts client-supplied values), writes append-only audit, and surfaces
-- real authorization/validation errors verbatim (non-masking).
--
-- RPCs (customer):
--   * seo_ownership_verification_initiate(uuid) — create/restart a challenge.
--   * seo_ownership_verification_recheck(uuid)  — re-check (reuse token, no DNS).
--   * seo_ownership_verification_reverify(uuid) — rotate token, invalidate prior.
--   * seo_ownership_verification_revoke(uuid)   — revoke (idempotent).
-- Internal helpers (NOT granted to authenticated/anon):
--   * seo_ownership_extract_host(text)          — parse host from website_url.
--   * seo_ownership_new_challenge_token()        — strong per-record TXT token.
--   * _seo_ownership_authorize(uuid)             — auth+module+website+owner/admin.
--
-- STATUS READ: NONE added — every Step 1 column is customer-safe and both tables
-- already carry a workspace-member SELECT policy, so customer-safe status is read
-- DIRECTLY through existing RLS. No status RPC is created (per Step 2A rule).
--
-- EXPLICITLY NOT IN THIS STEP (Step 2B / Step 3 / later / P1b):
--   * NO service-role claim RPC, pending-work retrieval RPC, or result-
--     persistence RPC; NO global-admin OVERRIDE RPC (all Step 2B).
--   * NO worker code / NO DNS resolution / token comparison (Step 3).
--   * NO frontend service/type/hook/mock/UI; NO supabaseTypes.ts constant.
--   * NO crawl RPC / crawl authorization / crawl UI change; NO P1b enforcement.
--   * seo_crawl_request / seo_crawl_request_audit / seo_crawl_cancel UNCHANGED.
--
-- Role decision (documented): initiate/recheck/reverify/revoke = owner or admin
-- only. team_member + client are DENIED all Step 2A writes (they may READ
-- customer-safe state via the Step 1 RLS SELECT policy). global_admin gets NO
-- special override here — any override is Step 2B. Writes bypass RLS solely
-- because these functions are SECURITY DEFINER (same pattern as the Stage 6 /
-- Phase 16C guarded RPCs); customers still cannot write the tables directly.
-- No existing object is altered; production untouched.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: extract the host from an authoritative website_url (parse only — this
-- is NOT DNS resolution). Lowercased; scheme/userinfo/path/query/fragment/port
-- stripped. Returns '' if nothing usable remains. IMMUTABLE + internal.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_ownership_extract_host(p_url text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(lower(btrim(coalesce(p_url, ''))),
                 '^[a-z][a-z0-9+.-]*://', ''),   -- scheme
               '^[^/@]*@', ''),                   -- userinfo
             '[/?#].*$', ''),                     -- path/query/fragment
           ':[0-9]+$', '');                       -- port
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_extract_host(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_extract_host(text) FROM anon;
REVOKE ALL ON FUNCTION public.seo_ownership_extract_host(text) FROM authenticated;

-- ---------------------------------------------------------------------------
-- Helper: cryptographically-strong, single-purpose DNS-TXT challenge token.
-- Two gen_random_uuid() values (CSPRNG, 256 bits total) → a recognizable,
-- per-record TXT value. VOLATILE + internal (never granted to customers).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_ownership_new_challenge_token()
RETURNS text
LANGUAGE sql
VOLATILE
SET search_path = public
AS $$
  SELECT 'digibility-site-verification='
         || replace(gen_random_uuid()::text, '-', '')
         || replace(gen_random_uuid()::text, '-', '');
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_new_challenge_token() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_new_challenge_token() FROM anon;
REVOKE ALL ON FUNCTION public.seo_ownership_new_challenge_token() FROM authenticated;

-- ---------------------------------------------------------------------------
-- Helper: shared non-masking authorization for every Step 2A customer RPC.
-- Resolves the caller, SEO module access, the website (SERVER-SIDE), the
-- owner/admin role, and the current host — raising verbatim on any failure.
-- Internal only. SECURITY DEFINER so it can read seo_websites reliably;
-- auth.uid() still resolves to the JWT caller inside a definer function.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._seo_ownership_authorize(
  p_website_id uuid,
  OUT v_uid uuid,
  OUT v_ws uuid,
  OUT v_url text,
  OUT v_host text,
  OUT v_role text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active boolean;
  v_archived timestamptz;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.has_seo_module_access(v_uid) THEN
    RAISE EXCEPTION 'SEO module access required';
  END IF;

  -- Resolve workspace + url SERVER-SIDE from the website id (client-supplied
  -- workspace/host/ownership are never trusted).
  SELECT workspace_id, website_url, is_active, archived_at
    INTO v_ws, v_url, v_active, v_archived
  FROM public.seo_websites WHERE id = p_website_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Website % does not exist', p_website_id;
  END IF;

  -- Owner/admin only. team_member, client, and non-members are all denied.
  -- No global-admin override in Step 2A (that is Step 2B).
  IF public.seo_role_in(v_ws, ARRAY['owner'], v_uid) THEN
    v_role := 'owner';
  ELSIF public.seo_role_in(v_ws, ARRAY['admin'], v_uid) THEN
    v_role := 'admin';
  ELSE
    RAISE EXCEPTION 'Requires the owner or admin role.';
  END IF;

  -- Current host from the authoritative website row (parse only).
  IF v_url !~* '^https?://[^[:space:]]+$' THEN
    RAISE EXCEPTION 'Website URL is not a valid http(s) URL';
  END IF;
  v_host := public.seo_ownership_extract_host(v_url);
  IF coalesce(v_host, '') = '' THEN
    RAISE EXCEPTION 'Website URL has no resolvable host';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._seo_ownership_authorize(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._seo_ownership_authorize(uuid) FROM anon;
REVOKE ALL ON FUNCTION public._seo_ownership_authorize(uuid) FROM authenticated;

-- ===========================================================================
-- seo_ownership_verification_initiate — create the first challenge, or restart
-- from a failed/revoked record. Idempotent no-op (no rotation, no event) when a
-- pending record already exists for the SAME host, or when already verified
-- (use re-verify to force a fresh challenge on a verified website). Returns the
-- full customer-safe row.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_initiate(p_website_id uuid)
RETURNS public.seo_ownership_verifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a record;
  r public.seo_ownership_verifications%ROWTYPE;
  v_from text;
BEGIN
  SELECT * INTO a FROM public._seo_ownership_authorize(p_website_id);

  SELECT * INTO r FROM public.seo_ownership_verifications
   WHERE website_id = p_website_id AND method = 'dns_txt';

  IF NOT FOUND THEN
    INSERT INTO public.seo_ownership_verifications
      (workspace_id, website_id, website_url, verification_host, method, status,
       challenge_token, created_by)
    VALUES
      (a.v_ws, p_website_id, a.v_url, a.v_host, 'dns_txt', 'pending',
       public.seo_ownership_new_challenge_token(), a.v_uid)
    RETURNING * INTO r;

    INSERT INTO public.seo_ownership_verification_events
      (verification_id, workspace_id, website_id, event_type, from_status, to_status,
       actor, actor_user_id, actor_role_snapshot, note)
    VALUES
      (r.id, a.v_ws, p_website_id, 'initiated', NULL, 'pending',
       'customer', a.v_uid, a.v_role, 'Ownership verification initiated');
    RETURN r;
  END IF;

  -- Existing record.
  IF r.status = 'verified' THEN
    RETURN r;  -- idempotent: never silently drop a verified state (use re-verify)
  END IF;

  IF r.status = 'pending' AND r.verification_host = a.v_host THEN
    RETURN r;  -- idempotent: challenge already outstanding for the same host
  END IF;

  -- failed / revoked / pending-with-changed-host → restart with a fresh token.
  v_from := r.status;
  UPDATE public.seo_ownership_verifications
     SET status = 'pending',
         challenge_token = public.seo_ownership_new_challenge_token(),
         challenge_rotated_at = now(),
         verification_host = a.v_host,
         website_url = a.v_url,
         verified_at = NULL,
         failure_reason = NULL
   WHERE id = r.id
   RETURNING * INTO r;

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (r.id, a.v_ws, p_website_id, 'initiated', v_from, 'pending',
     'customer', a.v_uid, a.v_role, 'Ownership verification re-initiated');
  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_initiate(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_initiate(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_ownership_verification_initiate(uuid) TO authenticated;

-- ===========================================================================
-- seo_ownership_verification_recheck — customer asserts the TXT record is in
-- place; re-arm a check WITHOUT rotating the token and WITHOUT DNS resolution
-- (resolution is Step 3). Applies only to a pending/failed record. Deterministic
-- + repeatable; appends exactly one 'check_started' event per call.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_recheck(p_website_id uuid)
RETURNS public.seo_ownership_verifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a record;
  r public.seo_ownership_verifications%ROWTYPE;
  v_from text;
BEGIN
  SELECT * INTO a FROM public._seo_ownership_authorize(p_website_id);

  SELECT * INTO r FROM public.seo_ownership_verifications
   WHERE website_id = p_website_id AND method = 'dns_txt';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No verification to re-check for this website; initiate first';
  END IF;
  IF r.status NOT IN ('pending', 'failed') THEN
    RAISE EXCEPTION 'Re-check applies only to a pending or failed verification (current: %)', r.status;
  END IF;

  v_from := r.status;
  UPDATE public.seo_ownership_verifications
     SET status = 'pending',          -- set (from failed) or retain pending
         last_checked_at = now(),
         failure_reason = NULL
   WHERE id = r.id
   RETURNING * INTO r;                 -- challenge_token intentionally UNCHANGED

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (r.id, a.v_ws, p_website_id, 'check_started', v_from, 'pending',
     'customer', a.v_uid, a.v_role, 'Re-check requested (token reused)');
  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_recheck(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_recheck(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_ownership_verification_recheck(uuid) TO authenticated;

-- ===========================================================================
-- seo_ownership_verification_reverify — rotate the challenge token, set pending,
-- and invalidate any prior verified state. Appends exactly one
-- 're_verification_requested' event (from_status records the invalidation).
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_reverify(p_website_id uuid)
RETURNS public.seo_ownership_verifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a record;
  r public.seo_ownership_verifications%ROWTYPE;
  v_from text;
BEGIN
  SELECT * INTO a FROM public._seo_ownership_authorize(p_website_id);

  SELECT * INTO r FROM public.seo_ownership_verifications
   WHERE website_id = p_website_id AND method = 'dns_txt';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No verification to re-verify for this website; initiate first';
  END IF;

  v_from := r.status;
  UPDATE public.seo_ownership_verifications
     SET status = 'pending',
         challenge_token = public.seo_ownership_new_challenge_token(),
         challenge_rotated_at = now(),
         verification_host = a.v_host,
         website_url = a.v_url,
         verified_at = NULL,           -- invalidate any prior verified state
         failure_reason = NULL
   WHERE id = r.id
   RETURNING * INTO r;

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (r.id, a.v_ws, p_website_id, 're_verification_requested', v_from, 'pending',
     'customer', a.v_uid, a.v_role, 'Re-verification requested (challenge rotated)');
  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_reverify(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_reverify(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_ownership_verification_reverify(uuid) TO authenticated;

-- ===========================================================================
-- seo_ownership_verification_revoke — mark the verification revoked. Idempotent:
-- a repeat revoke returns the row and appends NO new event (state unchanged).
-- History is preserved (no delete).
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_ownership_verification_revoke(p_website_id uuid)
RETURNS public.seo_ownership_verifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a record;
  r public.seo_ownership_verifications%ROWTYPE;
  v_from text;
BEGIN
  SELECT * INTO a FROM public._seo_ownership_authorize(p_website_id);

  SELECT * INTO r FROM public.seo_ownership_verifications
   WHERE website_id = p_website_id AND method = 'dns_txt';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No verification to revoke for this website';
  END IF;

  IF r.status = 'revoked' THEN
    RETURN r;  -- idempotent: no state change → no new audit event
  END IF;

  v_from := r.status;
  UPDATE public.seo_ownership_verifications
     SET status = 'revoked',
         verified_at = NULL,
         failure_reason = NULL
   WHERE id = r.id
   RETURNING * INTO r;                 -- token + history preserved

  INSERT INTO public.seo_ownership_verification_events
    (verification_id, workspace_id, website_id, event_type, from_status, to_status,
     actor, actor_user_id, actor_role_snapshot, note)
  VALUES
    (r.id, a.v_ws, p_website_id, 'revoked', v_from, 'revoked',
     'customer', a.v_uid, a.v_role, 'Ownership verification revoked');
  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_revoke(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_ownership_verification_revoke(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_ownership_verification_revoke(uuid) TO authenticated;

-- =============================================================================
-- End P1a Step 2A. Deferred to Step 2B: the service-role claim/result RPCs and
-- the global-admin override RPC. Deferred to Step 3: the DNS-TXT worker. No
-- status RPC was added (direct RLS read is sufficient). No crawl RPC / crawl
-- authorization / crawl UI change; no Step 1 table/policy change; no existing
-- object altered; production untouched.
-- =============================================================================
