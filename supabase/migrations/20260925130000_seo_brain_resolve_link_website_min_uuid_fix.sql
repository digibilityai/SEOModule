-- =============================================================================
-- SEO Backend, D-026A: corrective fix for seo_brain_resolve_link_website.
--   20260925120000_seo_brain_link_completion.sql is already applied to
--   Digi_SEO_Test and is not edited or reordered by this migration (forward-
--   only). This corrects a genuine runtime defect found during live TEST
--   acceptance via a real Brain-originated intent:
--
--     seoBrainLinkIntentService.resolveLinkWebsite:
--     function min(uuid) does not exist
--
--   PostgreSQL does not define a MIN/MAX aggregate for the uuid type (no
--   default transition function is registered for it), so every call to this
--   RPC failed at its very first query. The three call sites below used
--   min(<uuid column>) only to pull the single value out of a 0-or-1-row
--   group (count(*) in the same SELECT is what actually distinguishes
--   none/one/ambiguous; when more than one row matches, the branch that
--   follows returns *_ambiguous before ever reading the aggregated value).
--   Casting to text for the aggregate and back to uuid keeps that exact
--   behaviour: NULL on zero rows, the one row's id on exactly one row, and an
--   arbitrary-but-discarded value on more than one row, with no change to
--   which row is treated as ambiguous, how a website/workspace is matched,
--   ownership/role checks, or DNS verification.
-- =============================================================================

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
  -- caller owns or administers. min() is cast through text because Postgres
  -- has no min(uuid) aggregate; count(*) still governs 0/1/ambiguous below,
  -- unchanged.
  SELECT count(*), min(w.id::text)::uuid, min(w.workspace_id::text)::uuid
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

    SELECT count(*), min(m.workspace_id::text)::uuid INTO v_workspace_count, v_workspace_id
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
-- CREATE OR REPLACE preserves the function's OID, so the REVOKE/GRANT already
-- applied by 20260925120000 are untouched; no ACL statements are repeated here.
