-- =============================================================================
-- SEO Backend, D-026A: corrective fix for seo_brain_link_authorize.
--   20260921120000_seo_brain_link_intents.sql, 20260925120000_seo_brain_link_
--   completion.sql and 20260925130000_seo_brain_resolve_link_website_min_uuid_
--   fix.sql are already applied to Digi_SEO_Test and are not edited or
--   reordered by this migration (forward-only). This corrects a genuine
--   customer-facing defect found during the live TEST founder acceptance
--   retry: a returning customer whose Brain Business already holds a genuine,
--   verified, active link to the EXACT website that a fresh Connect SEO
--   Intelligence attempt resolves to (the same host, in the same workspace)
--   was refused with 'business_host_already_linked' -> presented to the
--   customer as "This business is already connected to this website." That
--   check only ever compared (business_id, normalized_host); it never
--   compared the pre-existing active link's own website_id against the
--   website_id actually being authorized, so it could not tell "this exact
--   relationship already exists" (idempotent repeat) apart from "this
--   business already holds an active link to a DIFFERENT website at the same
--   host" (a genuine, still-refused conflict).
--
--   Fix: when an active link already exists for (business_id,
--   normalized_host), additionally inspect its website_id.
--     - website_id = the requested p_website_id: the exact intended
--       relationship already exists. Return a new resolution,
--       'already_linked', carrying the EXISTING link's id -- no new row is
--       inserted -- and still mark the redeemed intent consumed against that
--       existing link, exactly as the normal success path does, so the
--       launch code cannot be replayed indefinitely. This is a customer-
--       facing success, not an error.
--     - website_id <> the requested p_website_id: unchanged, still refused as
--       'business_host_already_linked'.
--   'website_already_linked' (a DIFFERENT business already holding an active
--   link to THIS website) is untouched. Every prior guard in this function --
--   redeemed intent, exact caller identity, consent window, active actor
--   mapping, module access, workspace membership, owner/admin role, active
--   website, host match, verified ownership -- runs unchanged and BEFORE this
--   check, so the idempotent short-circuit only ever fires for a request that
--   has already passed every existing authorization/security guard for the
--   exact website_id being requested. No guard is weakened or bypassed.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.seo_brain_link_authorize(
  p_intent_id uuid,
  p_website_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller       uuid := auth.uid();
  v_intent       record;
  v_website      record;
  v_ownership    record;
  v_website_host text;
  v_new_id       uuid;
  v_existing_link record;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('resolution', 'unauthorized', 'detail', 'no authenticated session');
  END IF;
  IF p_intent_id IS NULL OR p_website_id IS NULL THEN
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

  -- Re-check the Brain actor to SEO user mapping at spend time (review N3). A
  -- mapping revoked after redemption, or one that no longer maps this actor to
  -- this authenticated user, must stop authorization.
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

  SELECT w.* INTO v_website
  FROM public.seo_websites w
  WHERE w.id = p_website_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('resolution', 'website_not_found');
  END IF;

  -- A caller with no membership at all in this website's workspace gets the
  -- SAME refusal as a nonexistent website: this endpoint must not become a way
  -- to probe which website ids exist in a workspace the caller has no
  -- relationship to whatsoever. A caller who IS a member, just not owner or
  -- admin (team_member, client), already has legitimate visibility into this
  -- website through the ordinary SELECT policy, so refusing them with
  -- website_not_found would be actively misleading rather than protective;
  -- they get the honest unauthorized instead.
  IF NOT (public.is_seo_workspace_member(v_website.workspace_id, v_caller)
          OR public.seo_is_global_admin(v_caller)) THEN
    RETURN jsonb_build_object('resolution', 'website_not_found');
  END IF;

  IF NOT (public.seo_role_in(v_website.workspace_id, ARRAY['owner', 'admin'], v_caller)
          OR public.seo_is_global_admin(v_caller)) THEN
    RETURN jsonb_build_object('resolution', 'unauthorized', 'detail', 'workspace role does not permit authorizing a link');
  END IF;

  IF NOT v_website.is_active OR v_website.archived_at IS NOT NULL THEN
    RETURN jsonb_build_object('resolution', 'website_inactive');
  END IF;

  v_website_host := public.seo_brain_normalize_host(v_website.website_url);
  IF v_website_host IS DISTINCT FROM v_intent.normalized_host THEN
    RETURN jsonb_build_object('resolution', 'host_mismatch');
  END IF;

  -- Ownership must be verified for THIS host (review B1). status = 'verified'
  -- alone is not enough: a website whose URL was changed after verification
  -- still carries the old row, and it proves ownership of the OLD host. The
  -- stored evidence (verification_host and the website_url snapshot taken when
  -- the challenge was issued) must each still normalize to BOTH the website's
  -- current host and the intent's host. Historical evidence is only read.
  SELECT v.status, v.verification_host, v.website_url INTO v_ownership
  FROM public.seo_ownership_verifications v
  WHERE v.website_id = p_website_id AND v.method = 'dns_txt';

  IF NOT FOUND
     OR v_ownership.status <> 'verified'
     OR public.seo_brain_normalize_host(v_ownership.verification_host) IS DISTINCT FROM v_website_host
     OR public.seo_brain_normalize_host(v_ownership.verification_host) IS DISTINCT FROM v_intent.normalized_host
     OR public.seo_brain_normalize_host(v_ownership.website_url) IS DISTINCT FROM v_website_host
     OR public.seo_brain_normalize_host(v_ownership.website_url) IS DISTINCT FROM v_intent.normalized_host
  THEN
    RETURN jsonb_build_object('resolution', 'ownership_not_verified');
  END IF;

  -- D-026A idempotent-repeat fix: an active link already exists for this
  -- business+host. If it is the EXACT website being authorized, the intended
  -- relationship already exists -- converge to success (already_linked)
  -- rather than refusing a repeat of an identical, already-satisfied request.
  -- Any other website at this host for the same business remains a genuine
  -- conflict, refused exactly as before.
  SELECT l.id, l.website_id INTO v_existing_link
  FROM public.seo_brain_website_links l
  WHERE l.business_id = v_intent.brain_business_id
    AND l.normalized_host = v_intent.normalized_host
    AND l.link_status = 'active';

  IF FOUND THEN
    IF v_existing_link.website_id = p_website_id THEN
      UPDATE public.seo_brain_link_intents
      SET status = 'link_created',
          consumed_at = now(),
          consumed_website_id = p_website_id
      WHERE id = v_intent.id;

      RETURN jsonb_build_object(
        'resolution',     'already_linked',
        'linkId',         v_existing_link.id,
        'websiteId',      p_website_id,
        'businessId',     v_intent.brain_business_id,
        'normalizedHost', v_intent.normalized_host,
        'linkedBy',       v_caller
      );
    END IF;
    RETURN jsonb_build_object('resolution', 'business_host_already_linked');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.seo_brain_website_links l
    WHERE l.website_id = p_website_id AND l.link_status = 'active'
  ) THEN
    RETURN jsonb_build_object('resolution', 'website_already_linked');
  END IF;

  BEGIN
    INSERT INTO public.seo_brain_website_links (business_id, website_id, source_intent_id)
    VALUES (v_intent.brain_business_id, p_website_id, v_intent.id)
    RETURNING id INTO v_new_id;
  EXCEPTION WHEN unique_violation THEN
    -- Defence in depth behind the two pre-checks above, for the race between
    -- them and this insert.
    RETURN jsonb_build_object('resolution', 'conflicting_link');
  END;

  UPDATE public.seo_brain_link_intents
  SET status = 'link_created',
      consumed_at = now(),
      consumed_website_id = p_website_id
  WHERE id = v_intent.id;

  RETURN jsonb_build_object(
    'resolution',     'resolved',
    'linkId',         v_new_id,
    'websiteId',      p_website_id,
    'businessId',     v_intent.brain_business_id,
    'normalizedHost', v_intent.normalized_host,
    'linkedBy',       v_caller
  );
END;
$$;
-- CREATE OR REPLACE preserves the function's OID, so the REVOKE/GRANT already
-- applied by 20260921120000 are untouched; no ACL statements are repeated here.
