-- =============================================================================
-- SEO Backend, Digi Brain Module Contract v1, Stage 2B amendment, Migration 3:
--   human-authorized Brain actor to SEO user identity mapping
-- =============================================================================
-- Additive only. Resolves the single blocking issue recorded in Stage 2B: Digi
-- Brain's `actorId` identifies a human in the Digi Brain Supabase project, and
-- SEO users are rows in the SEO project's own auth.users, with nothing mapping
-- one to the other. This migration adds that mapping, and nothing else.
--
-- WHAT THIS TABLE IS NOT.
-- It establishes IDENTITY ONLY. It grants no SEO permission of any kind. After
-- an actor resolves to an SEO user, every delegated capability still runs the
-- existing authorization chain unchanged:
--     resolved SEO user
--       -> public.has_seo_module_access
--       -> public.seo_role_in(workspace, allowed roles) / seo_is_global_admin
--       -> the target website's own workspace
-- A row here that maps a Brain actor to an SEO user with no workspace
-- membership resolves successfully and is then refused by the role check, which
-- is the intended behaviour and is covered by test and by SQL verification.
--
-- WHAT IS DELIBERATELY NOT USED TO INFER IDENTITY.
-- No email matching, no display name matching, no workspace ownership, no most
-- recent membership, no reuse of seo_brain_website_links.linked_by, no SSO
-- session assumption, and no machine credential. The machine credential
-- authenticates the transport and never stands in for a human. A mapping exists
-- only because a human created it.
--
-- WHY NOT THE EXISTING SEAMS.
-- public.seo_identity_profiles is keyed on the SEO user id, holds no Brain
-- identifier, mirrors profile attributes this mapping must not duplicate, and is
-- referenced by zero lines of application code. public.seo_workspaces.
-- core_profile_id is an unused nullable seam at workspace granularity, which
-- cannot express a per-person mapping. Neither is modified here.
--
-- WHO MAY CREATE A MAPPING.
-- A global admin only (public.seo_is_global_admin). This is deliberately
-- narrower than the owner/admin rule used for seo_brain_website_links, because
-- an actor link is a PLATFORM level identity assertion rather than a
-- workspace scoped one: allowing any workspace admin to declare "this Brain
-- actor is that SEO user" would let one tenant's admin bind an arbitrary Brain
-- actor to an arbitrary SEO user, including a user in another workspace. A
-- self service claim flow could be added later, but it needs a possession proof
-- of the Brain identity to be safe, and that proof does not exist yet.
--
-- HOW THE FIRST MAPPING IS CREATED. public.seo_is_global_admin() reads
-- public.profiles, which this repository never creates, so on a standalone SEO
-- project no authenticated session can satisfy the INSERT policy and there is
-- no reachable global admin to create the first row. A controlled operator
-- procedure, public.seo_brain_bootstrap_actor_link, is provided for exactly
-- that bootstrap. It is granted to nobody, including service_role, requires the
-- SEO user being linked AND the authorizing SEO user to be stated explicitly,
-- and refuses to run inside an authenticated session. See its own note below.
--
-- REVOCATION FAILS CLOSED. A revoked mapping stops resolving immediately and
-- cannot be reactivated; a new row is required.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_brain_actor_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Digi Brain's own identifier for a human. Opaque here: SEO never parses it,
  -- never assumes a format, and never stores any other attribute of that
  -- person. Held as text because Contract v1 types actorId as a plain string
  -- and it belongs to a different Supabase project.
  brain_actor_id text NOT NULL CHECK (length(btrim(brain_actor_id)) BETWEEN 1 AND 200),
  -- The SEO account this actor acts as. The ONLY SEO-side attribute stored.
  -- No email, no name, no role: those already live in auth.users, in
  -- seo_workspace_members and in seo_identity_profiles, and duplicating them
  -- here would create a second, drifting copy of a person's identity.
  seo_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  link_status text NOT NULL DEFAULT 'active'
    CHECK (link_status IN ('active', 'revoked')),
  -- The human who authorized this mapping. Server-set from auth.uid().
  linked_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  revoked_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Exactly one ACTIVE mapping per Brain actor: resolution is exact or absent.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_brain_actor_links_actor
  ON public.seo_brain_actor_links (brain_actor_id)
  WHERE link_status = 'active';

-- Exactly one ACTIVE mapping per SEO user, so two Brain actors can never both
-- act as the same SEO account and make its audit trail ambiguous.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_brain_actor_links_user
  ON public.seo_brain_actor_links (seo_user_id)
  WHERE link_status = 'active';

CREATE INDEX IF NOT EXISTS idx_seo_brain_actor_links_lookup
  ON public.seo_brain_actor_links (brain_actor_id, link_status);

-- ---------------------------------------------------------------------------
-- Server-set bookkeeping + immutability of the identity columns.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_actor_links_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  NEW.brain_actor_id := btrim(NEW.brain_actor_id);

  IF TG_OP = 'INSERT' THEN
    -- Authorization is recorded, never inferred. With a session identity the
    -- server always uses it and ignores whatever the client supplied, so an
    -- authenticated global admin cannot attribute a mapping to somebody else.
    -- With no session identity (the controlled operator bootstrap below, which
    -- runs in a direct SQL session where auth.uid() is NULL) the caller must
    -- state the authorizing SEO user explicitly. There is nothing else that
    -- could truthfully stand in for it, so the row is refused rather than
    -- written with an unattributed NULL.
    IF auth.uid() IS NOT NULL THEN
      NEW.linked_by := auth.uid();
    ELSIF NEW.linked_by IS NULL THEN
      RAISE EXCEPTION 'linked_by is required: this session has no auth.uid(), so the authorizing SEO user must be supplied explicitly (use public.seo_brain_bootstrap_actor_link)';
    END IF;
    NEW.linked_at := now();
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Which human is which is fixed for the life of the row. Repointing a
    -- mapping in place would silently transfer every future attribution.
    IF NEW.brain_actor_id IS DISTINCT FROM OLD.brain_actor_id THEN
      RAISE EXCEPTION 'brain_actor_id cannot be changed; revoke this mapping and create a new one';
    END IF;
    IF NEW.seo_user_id IS DISTINCT FROM OLD.seo_user_id THEN
      RAISE EXCEPTION 'seo_user_id cannot be changed; revoke this mapping and create a new one';
    END IF;
    -- Revocation is terminal and fails closed.
    IF OLD.link_status = 'revoked' AND NEW.link_status <> 'revoked' THEN
      RAISE EXCEPTION 'A revoked Digi Brain actor mapping cannot be reactivated; create a new mapping instead';
    END IF;
    IF NEW.link_status = 'revoked' AND OLD.link_status <> 'revoked' THEN
      -- Same rule as linked_by: revocation is an authorization act and is
      -- attributed to a real human or refused.
      IF auth.uid() IS NOT NULL THEN
        NEW.revoked_by := auth.uid();
      ELSIF NEW.revoked_by IS NULL THEN
        RAISE EXCEPTION 'revoked_by is required: this session has no auth.uid(), so the revoking SEO user must be supplied explicitly in the same UPDATE';
      END IF;
      NEW.revoked_at := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_brain_actor_links_guard ON public.seo_brain_actor_links;
CREATE TRIGGER trg_seo_brain_actor_links_guard
  BEFORE INSERT OR UPDATE ON public.seo_brain_actor_links
  FOR EACH ROW EXECUTE FUNCTION public.seo_brain_actor_links_guard();

DROP TRIGGER IF EXISTS trg_seo_brain_actor_links_updated_at ON public.seo_brain_actor_links;
CREATE TRIGGER trg_seo_brain_actor_links_updated_at
  BEFORE UPDATE ON public.seo_brain_actor_links
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS. service_role bypasses RLS and is the only identity the machine path
-- uses; these policies govern the HUMAN authorization path only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_brain_actor_links ENABLE ROW LEVEL SECURITY;

-- A person may see their own mapping. A global admin may see all of them.
-- Nobody else can enumerate who is mapped to whom.
DROP POLICY IF EXISTS seo_brain_actor_links_select ON public.seo_brain_actor_links;
CREATE POLICY seo_brain_actor_links_select
  ON public.seo_brain_actor_links
  FOR SELECT
  TO authenticated
  USING (seo_user_id = auth.uid() OR public.seo_is_global_admin());

-- Only a global admin may authorize a mapping. This is the human action the
-- whole delegated write path depends on; there is no machine path to it.
DROP POLICY IF EXISTS seo_brain_actor_links_insert ON public.seo_brain_actor_links;
CREATE POLICY seo_brain_actor_links_insert
  ON public.seo_brain_actor_links
  FOR INSERT
  TO authenticated
  WITH CHECK (public.seo_is_global_admin());

-- A global admin may revoke, and a person may revoke their own mapping. The
-- guard trigger restricts an UPDATE to a status change.
DROP POLICY IF EXISTS seo_brain_actor_links_update ON public.seo_brain_actor_links;
CREATE POLICY seo_brain_actor_links_update
  ON public.seo_brain_actor_links
  FOR UPDATE
  TO authenticated
  USING (seo_user_id = auth.uid() OR public.seo_is_global_admin())
  WITH CHECK (seo_user_id = auth.uid() OR public.seo_is_global_admin());

-- No DELETE policy: a mapping is revoked, never erased, so the authorization
-- history stays readable.

REVOKE ALL ON FUNCTION public.seo_brain_actor_links_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_actor_links_guard() FROM anon;

-- ---------------------------------------------------------------------------
-- Controlled operator bootstrap.
--
-- WHY THIS EXISTS. The INSERT policy above requires public.seo_is_global_admin(),
-- which reads public.profiles. This repository never creates public.profiles,
-- so on a standalone SEO project (including Digi_SEO_Test) that function
-- returns false for every user and no authenticated session can create the
-- FIRST mapping. Without a way in, the delegated write path can never be
-- exercised at all. This procedure is that way in, and nothing more.
--
-- WHAT IT IS NOT. It is not an admin UI, not a product feature, and not a new
-- global-admin system. It creates no role, changes no policy, and is granted to
-- nobody: EXECUTE is revoked from PUBLIC, anon, authenticated and service_role,
-- so it is reachable only by the database owner in a direct operator session.
-- The machine endpoint authenticates as service_role and therefore still has no
-- path of any kind to creating an actor mapping.
--
-- WHAT IT REFUSES TO INVENT. It derives nothing. The operator must name the SEO
-- user being linked AND the SEO user who authorized the mapping, both as
-- auth.users ids, and both must already exist. No email match, no display name
-- match, no workspace ownership, no "the only admin", no fallback to the
-- session, no fallback to the linked user.
--
-- THE HONEST LIMITATION. On this schema the authorizer can only be recorded if
-- the operator supplies it, because a direct SQL session has no auth.uid() and
-- there is no product-level global-admin record to read one from. This
-- procedure therefore makes p_authorized_by a required argument rather than
-- defaulting it, and the guard trigger refuses any unattributed insert. A
-- product-level admin surface would replace this procedure; that is deliberately
-- out of scope here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_bootstrap_actor_link(
  p_brain_actor_id text,
  p_seo_user_id uuid,
  p_authorized_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_actor text := btrim(coalesce(p_brain_actor_id, ''));
  v_id    uuid;
BEGIN
  -- A session carrying a JWT must use the ordinary RLS path, so this procedure
  -- can never become a way around the global-admin INSERT policy.
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'seo_brain_bootstrap_actor_link is an operator procedure and must not be called from an authenticated session; use the normal insert path';
  END IF;

  IF v_actor = '' THEN
    RAISE EXCEPTION 'p_brain_actor_id is required';
  END IF;
  IF p_seo_user_id IS NULL THEN
    RAISE EXCEPTION 'p_seo_user_id is required: state the SEO auth.users id being linked';
  END IF;
  IF p_authorized_by IS NULL THEN
    RAISE EXCEPTION 'p_authorized_by is required: state the SEO auth.users id of the human authorizing this mapping. It is never inferred';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p_seo_user_id) THEN
    RAISE EXCEPTION 'p_seo_user_id % does not exist in auth.users', p_seo_user_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p_authorized_by) THEN
    RAISE EXCEPTION 'p_authorized_by % does not exist in auth.users', p_authorized_by;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links l
    WHERE l.brain_actor_id = v_actor AND l.link_status = 'active'
  ) THEN
    RAISE EXCEPTION 'an active mapping already exists for Brain actor %; revoke it before creating another', v_actor;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links l
    WHERE l.seo_user_id = p_seo_user_id AND l.link_status = 'active'
  ) THEN
    RAISE EXCEPTION 'SEO user % is already mapped to an active Brain actor', p_seo_user_id;
  END IF;

  INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id, linked_by)
  VALUES (v_actor, p_seo_user_id, p_authorized_by)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_bootstrap_actor_link(text, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_bootstrap_actor_link(text, uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.seo_brain_bootstrap_actor_link(text, uuid, uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.seo_brain_bootstrap_actor_link(text, uuid, uuid) FROM service_role;

-- ---------------------------------------------------------------------------
-- Resolution helper. service_role only. Returns the SEO user for an ACTIVE
-- mapping, or NULL. Never falls back to anything.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_resolve_actor(p_brain_actor_id text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT l.seo_user_id
  FROM public.seo_brain_actor_links l
  WHERE l.brain_actor_id = btrim(coalesce(p_brain_actor_id, ''))
    AND l.link_status = 'active'
    AND btrim(coalesce(p_brain_actor_id, '')) <> ''
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_resolve_actor(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_resolve_actor(text) FROM anon;
REVOKE ALL ON FUNCTION public.seo_brain_resolve_actor(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_resolve_actor(text) TO service_role;
