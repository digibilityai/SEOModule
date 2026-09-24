-- =============================================================================
-- SEO Backend, D-026A: customer-facing SEO linking completion.
--   Closes the gap left after `20260921120000_seo_brain_link_intents.sql`:
--   Brain creates an intent, SEO receives a launchCode, identity may be
--   established (case A/B/D), but nothing yet resolved a website or spent the
--   redeemed intent on `seo_brain_link_authorize`. This migration adds exactly
--   two additive RPCs that complete that path. It edits no existing table, RPC,
--   column or policy.
-- =============================================================================
-- WHAT THIS ADDS.
--   1. seo_brain_link_intent_continue_by_code, service_role only, mirrors the
--      existing seo_brain_link_intent_pending_by_code pattern. Case D (an
--      existing durable actor mapping) redeems the intent server-side already,
--      but the browser making that call may have no live SEO session at all
--      (a returning customer, second visit from Brain). This is the trusted
--      lookup the link-intent/continue Edge Function route uses to mint a
--      magic-link sign-in for the SAME mapped user, the same way case A mints
--      one for a freshly created user. It deliberately does not create
--      anything: the actor mapping and module access already exist.
--   2. seo_brain_resolve_link_website, authenticated only. Once a genuine SEO
--      session exists for the redeemed intent's user, this resolves (or, only
--      when nothing matches, creates) the single website matching the intent's
--      normalized host, reusing the existing DNS ownership-verification
--      capability unchanged. It never lets a customer pick a website; it fails
--      clearly on anything ambiguous rather than guessing.
--
-- NEITHER FUNCTION TOUCHES seo_brain_link_authorize. Authorization remains the
-- single, unchanged, transactional path from a redeemed intent to a durable
-- website link; these two functions only get a genuine session and a genuine,
-- verified-or-verification-pending website in front of it.
--
-- WHY NO session_continued_at COLUMN. Case D continuation needs no new mutable
-- state: seo_brain_link_intent_continue_by_code re-derives eligibility from
-- columns that already exist (status, redemption_outcome, consent_expires_at,
-- the actor mapping's own link_status/link_method) on every call, so repeating
-- it within the existing ~30 minute consent window is safe and idempotent:
-- it only ever mints another magic link for the same already-mapped user. A
-- provenance timestamp was considered and is not required by anything in this
-- design; omitted per the smallest-implementation rule.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. seo_brain_link_intent_continue_by_code. service_role only, called by the
--    link-intent/continue Edge Function route with the ORIGINAL LAUNCH CODE
--    (never an intent id), exactly like seo_brain_link_intent_pending_by_code.
--
--    Security boundary: only resolves when the durable actor mapping backing
--    this case D redemption is 'active' AND carries a non-NULL link_method,
--    i.e. it was itself created through the Brain-intent consent flow
--    (brain_intent_new or brain_intent_confirmed), never a pre-existing
--    operator-bootstrap mapping with no recorded consent trail. Returns NULL
--    for anything else, so the Edge Function has exactly one place to fail
--    closed. Live-session mismatch is NOT checked here: this call carries no
--    browser session at all (service_role, launch code only); it is the
--    caller's (SeoBrainConnectPage's) job to compare its own current session,
--    if any, against `seoUserId` before ever invoking this, and refuse rather
--    than call it on a mismatch; seo_brain_link_authorize itself re-checks the
--    signed-in caller against `redeemed_seo_user_id` regardless.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_link_intent_continue_by_code(p_launch_code text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT jsonb_build_object('intentId', i.id, 'seoUserId', i.redeemed_seo_user_id, 'email', u.email)
  FROM public.seo_brain_link_intents i
  JOIN auth.users u ON u.id = i.redeemed_seo_user_id
  JOIN public.seo_brain_actor_links l
    ON l.brain_actor_id = i.brain_actor_id
   AND l.seo_user_id = i.redeemed_seo_user_id
   AND l.link_status = 'active'
   AND l.link_method IS NOT NULL
  WHERE btrim(coalesce(p_launch_code, '')) <> ''
    AND i.launch_code_hash = encode(digest(p_launch_code, 'sha256'), 'hex')
    AND i.status = 'redeemed'
    AND i.redemption_outcome = 'case_d_existing_mapping'
    AND i.consent_expires_at IS NOT NULL
    AND now() <= i.consent_expires_at;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_link_intent_continue_by_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_link_intent_continue_by_code(text) FROM anon;
REVOKE ALL ON FUNCTION public.seo_brain_link_intent_continue_by_code(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_link_intent_continue_by_code(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. seo_brain_resolve_link_website. authenticated only, called by the now
--    signed-in customer's browser, the same trust level as seo_brain_link_
--    authorize itself. Guards mirror authorize's own intent-level checks
--    (redeemed, exact caller, consent window, active actor mapping, SEO module
--    access) because resolving/creating a website is itself a meaningful,
--    consent-gated action, not a read.
--
--    Resolution, in order:
--      a. Every ACTIVE website whose normalized host matches the intent's, in
--         a workspace where the caller holds seo_role 'owner' or 'admin' (the
--         same two roles authorize itself accepts to link). More than one ->
--         fail clearly (website_ambiguous) rather than choose.
--      b. None found: resolve exactly one workspace to create it in (a
--         workspace the caller owns or administers, if exactly one; more than
--         one -> workspace_ambiguous; none -> create one, with the caller as
--         owner, mirroring the existing owner-bootstrap convention in
--         seo_workspaces_insert/trg_seo_workspaces_add_owner_member). Then
--         create exactly one seo_websites row for the intent's host in it. No
--         customer selector anywhere in this path.
--      c. Either way, ensure DNS ownership verification is at least underway
--         via the EXISTING, unchanged seo_ownership_verification_initiate
--         (idempotent: a no-op when already pending/verified for this host).
--         Returns whether the current host is already genuinely verified,
--         using the same stricter check authorize itself applies (both the
--         verification's stored host and website_url snapshot must still
--         normalize to the intent's host); never authorization itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_resolve_link_website(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller         uuid := auth.uid();
  v_intent         record;
  v_workspace_id   uuid;
  v_workspace_count integer;
  v_website_id     uuid;
  v_website_count  integer;
  v_name           text;
  v_url            text;
  v_verified       boolean;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('resolution', 'unauthorized', 'detail', 'no authenticated session');
  END IF;
  IF p_intent_id IS NULL THEN
    RETURN jsonb_build_object('resolution', 'invalid_request');
  END IF;

  SELECT * INTO v_intent
  FROM public.seo_brain_link_intents
  WHERE id = p_intent_id
  FOR UPDATE;

  IF NOT FOUND OR v_intent.status <> 'redeemed' THEN
    RETURN jsonb_build_object('resolution', 'intent_not_redeemed');
  END IF;
  IF v_intent.redeemed_seo_user_id <> v_caller THEN
    RETURN jsonb_build_object('resolution', 'identity_mismatch');
  END IF;
  IF v_intent.consent_expires_at IS NULL OR now() > v_intent.consent_expires_at THEN
    RETURN jsonb_build_object('resolution', 'intent_expired');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links l
    WHERE l.brain_actor_id = v_intent.brain_actor_id
      AND l.seo_user_id = v_caller
      AND l.link_status = 'active'
  ) THEN
    RETURN jsonb_build_object('resolution', 'actor_mapping_inactive');
  END IF;

  IF NOT public.has_seo_module_access(v_caller) THEN
    RETURN jsonb_build_object('resolution', 'unauthorized', 'detail', 'no SEO module access');
  END IF;

  v_url := 'https://' || v_intent.normalized_host;

  -- (a) Reuse an existing, active website for this host, in a workspace the
  -- caller owns or administers.
  SELECT count(*), min(w.id), min(w.workspace_id)
    INTO v_website_count, v_website_id, v_workspace_id
  FROM public.seo_websites w
  JOIN public.seo_workspace_members m
    ON m.workspace_id = w.workspace_id
   AND m.user_id = v_caller
   AND m.status = 'active'
   AND m.seo_role IN ('owner', 'admin')
  WHERE public.seo_brain_normalize_host(w.website_url) = v_intent.normalized_host
    AND w.is_active
    AND w.archived_at IS NULL;

  IF v_website_count > 1 THEN
    RETURN jsonb_build_object('resolution', 'website_ambiguous');
  END IF;

  IF v_website_count = 0 THEN
    -- (b) Resolve exactly one workspace to create the website in.
    v_website_id := NULL;
    v_workspace_id := NULL;

    SELECT count(*), min(m.workspace_id) INTO v_workspace_count, v_workspace_id
    FROM public.seo_workspace_members m
    WHERE m.user_id = v_caller AND m.status = 'active' AND m.seo_role IN ('owner', 'admin');

    IF v_workspace_count > 1 THEN
      RETURN jsonb_build_object('resolution', 'workspace_ambiguous');
    END IF;

    v_name := coalesce(v_intent.business_display_name, v_intent.normalized_host);

    IF v_workspace_count = 0 THEN
      INSERT INTO public.seo_workspaces (name, owner_user_id, created_by)
      VALUES (v_name, v_caller, v_caller)
      RETURNING id INTO v_workspace_id;
    END IF;

    BEGIN
      INSERT INTO public.seo_websites (workspace_id, website_url, website_name, business_name, created_by)
      VALUES (v_workspace_id, v_url, v_name, v_name, v_caller)
      RETURNING id INTO v_website_id;
    EXCEPTION WHEN unique_violation THEN
      -- Defence in depth behind the pre-check above, for the race between it
      -- and this insert; reuse whatever now exists at that exact URL rather
      -- than fail the whole request.
      SELECT id INTO v_website_id
      FROM public.seo_websites
      WHERE workspace_id = v_workspace_id AND website_url = v_url;
      IF v_website_id IS NULL THEN
        RETURN jsonb_build_object('resolution', 'conflicting_website');
      END IF;
    END;
  END IF;

  -- (c) Ensure DNS ownership verification is at least underway, through the
  -- existing, unchanged capability. The caller is 'owner' or 'admin' in
  -- v_workspace_id either way above, which is exactly what it requires.
  PERFORM public.seo_ownership_verification_initiate(v_website_id);

  SELECT (v.status = 'verified'
          AND public.seo_brain_normalize_host(v.verification_host) = v_intent.normalized_host
          AND public.seo_brain_normalize_host(v.website_url) = v_intent.normalized_host)
    INTO v_verified
  FROM public.seo_ownership_verifications v
  WHERE v.website_id = v_website_id AND v.method = 'dns_txt';

  RETURN jsonb_build_object(
    'resolution',     'resolved',
    'websiteId',      v_website_id,
    'workspaceId',    v_workspace_id,
    'normalizedHost', v_intent.normalized_host,
    'verified',       coalesce(v_verified, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_resolve_link_website(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_resolve_link_website(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_brain_resolve_link_website(uuid) TO authenticated;
