-- =============================================================================
-- SEO Backend, D-026A SEO PR-1: cross-repo linking foundation
--   seo_brain_link_intents, provenance columns, and the redemption/authorize
--   RPC surface a Brain-authenticated customer will later use to authorize a
--   verified SEO website for a real Brain Business.
-- =============================================================================
-- Additive only. Edits no existing table, policy, RPC or migration, and does
-- not change public.seo_brain_website_links or public.seo_brain_actor_links
-- beyond adding one nullable provenance column to each.
--
-- WHAT THIS EXISTS TO UNBLOCK.
-- Digi Brain's businessId is a UUID belonging to a real customer Business.
-- Today the only way an SEO website ever gets linked to a Business is a human
-- with direct database access, because public.seo_brain_website_links has no
-- product surface and its INSERT policy requires an authenticated owner/admin
-- session, which this repository currently gives no customer a way to reach
-- for a Brain-originated Business. This migration adds the minimum backend
-- primitive for that: a single-use, Brain-originated intent that a genuine SEO
-- session (new or existing) can redeem and then use, within a short consent
-- window, to authorize exactly one website link. It creates no UI, and it does
-- not touch Digi Brain, Contract v1, or the six existing capabilities.
--
-- THREE TRUST BOUNDARIES, KEPT SEPARATE RATHER THAN BLURRED.
--   1. create_intent: Brain server to SEO, over the EXISTING machine secret
--      (SEO_MODULE_API_SECRET), exactly like every Contract v1 exchange.
--      public.seo_brain_create_link_intent, service_role only.
--   2. redeem: the customer's OWN browser, over the ordinary anon/authenticated
--      Supabase client, exactly like every other customer-facing SEO RPC. This
--      is deliberately NOT gated by the machine secret, which a browser cannot
--      hold, and it is the only place auth.uid() can be trusted to mean "this
--      browser's current SEO session," which is what distinguishes case B
--      (a live session) from case A/C (none). public.seo_brain_link_intent_redeem,
--      granted to anon and authenticated.
--   3. finalize_case_a and authorize: server-only completions of a redemption
--      that already happened. public.seo_brain_link_intent_finalize_case_a
--      (service_role only, called by the edge function immediately after it
--      creates a passwordless auth user through the official Supabase Admin
--      API, which is the one step no SQL function can safely perform) and
--      public.seo_brain_link_authorize (authenticated only, called by the now
--      signed-in customer to spend the redeemed intent on exactly one website).
--
-- WHAT IS DELIBERATELY NOT BUILT HERE. No SEO UI page. No Core involvement, no
-- Core SSO, no billing, no generic identity or provisioning infrastructure, no
-- second secret. Workspace creation, website creation and DNS ownership
-- verification are all reused unchanged; this migration creates none of them.
-- Rate limiting the redemption/provisioning endpoints is a real, deliberately
-- deferred hardening item, called out in the PR rather than built here.
--
-- WHY THIS DOES NOT WEAKEN THE EXISTING DIRECT-INSERT RLS POLICY.
-- public.seo_brain_website_links keeps its existing owner/admin INSERT policy
-- unchanged: that remains the administrative/manual linking path (the one the
-- Stage 2B synthetic acceptance link used) and nothing here removes it. This
-- migration adds a SEPARATE, additionally-verified path, seo_brain_link_authorize,
-- for customer-created links: it requires a redeemed, unexpired, unconsumed
-- intent, verified ownership and a host match on top of the same owner/admin
-- role gate. Tightening or removing the plain INSERT path is a bigger,
-- separate decision and is intentionally left for a follow-up.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. seo_brain_link_intents.
--
--    Lifecycle: issued -> (pending_provisioning ->) redeemed -> link_created,
--    or issued -> refused. Every transition is a single atomic
--    UPDATE ... WHERE status = '<expected>' ... RETURNING, so two concurrent
--    callers presenting the same code can never both succeed, and a code is
--    reusable only while it is still 'issued'.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_brain_link_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Digi Brain identifiers. Opaque here, exactly as seo_brain_actor_links and
  -- seo_brain_website_links already hold them: SEO never parses either one.
  brain_actor_id text NOT NULL CHECK (length(btrim(brain_actor_id)) BETWEEN 1 AND 200),
  brain_business_id text NOT NULL CHECK (length(btrim(brain_business_id)) BETWEEN 1 AND 200),

  -- Brain's own confirmed email for this actor. Used only to decide, at
  -- redemption time, whether an SEO identity already exists at that address
  -- (case A vs case C). It is never used to merge an intent into an existing
  -- account automatically; case C exists precisely so that never happens.
  brain_confirmed_email text NOT NULL
    CHECK (brain_confirmed_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),

  -- Independently normalized and validated by SEO at creation time; never
  -- trusted verbatim from the caller. Must already be canonical, the same rule
  -- the machine boundary applies to every websiteIdentity.normalizedHost.
  normalized_host text NOT NULL,

  -- Presentation only. Never read by any authorization decision below.
  business_display_name text CHECK (business_display_name IS NULL OR length(business_display_name) <= 200),

  -- The launch code itself is returned to Brain exactly once, at creation, and
  -- is never stored. Only its SHA-256 is kept, so a database read can never
  -- recover a usable code.
  launch_code_hash text NOT NULL UNIQUE CHECK (length(launch_code_hash) = 64),

  status text NOT NULL DEFAULT 'issued'
    CHECK (status IN ('issued', 'pending_provisioning', 'redeemed', 'link_created', 'refused')),

  issued_at timestamptz NOT NULL DEFAULT now(),
  -- Approximately 120 seconds from issued_at, computed once at insert time.
  redemption_expires_at timestamptz NOT NULL,

  redeemed_at timestamptz,
  redeemed_seo_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  redemption_outcome text
    CHECK (redemption_outcome IS NULL
           OR redemption_outcome IN ('case_a_new_identity', 'case_b_confirmed', 'case_d_existing_mapping')),
  -- Approximately 30 minutes from redeemed_at. seo_brain_link_authorize is the
  -- only thing that may still act on this intent before this passes.
  consent_expires_at timestamptz,

  consumed_at timestamptz,
  consumed_website_id uuid REFERENCES public.seo_websites(id) ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_brain_link_intents_lookup
  ON public.seo_brain_link_intents (brain_actor_id, normalized_host, status);
CREATE INDEX IF NOT EXISTS idx_seo_brain_link_intents_redeemed_user
  ON public.seo_brain_link_intents (redeemed_seo_user_id);

DROP TRIGGER IF EXISTS trg_seo_brain_link_intents_updated_at ON public.seo_brain_link_intents;
CREATE TRIGGER trg_seo_brain_link_intents_updated_at
  BEFORE UPDATE ON public.seo_brain_link_intents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- RLS. No human INSERT/UPDATE path at all: every mutation below happens inside
-- a SECURITY DEFINER function, which bypasses RLS as the table owner. Only a
-- narrow SELECT is granted, so a customer can see their own redeemed intent
-- and nothing about anyone else's.
ALTER TABLE public.seo_brain_link_intents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_brain_link_intents_select ON public.seo_brain_link_intents;
CREATE POLICY seo_brain_link_intents_select
  ON public.seo_brain_link_intents
  FOR SELECT
  TO authenticated
  USING (redeemed_seo_user_id = auth.uid() OR public.seo_is_global_admin());

-- ---------------------------------------------------------------------------
-- 2. Provenance columns. Both nullable and additive; every existing row keeps
--    its current, unattributed provenance unchanged.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_brain_actor_links
  ADD COLUMN IF NOT EXISTS link_method text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'seo_brain_actor_links_link_method_check'
  ) THEN
    ALTER TABLE public.seo_brain_actor_links
      ADD CONSTRAINT seo_brain_actor_links_link_method_check
      CHECK (link_method IS NULL OR link_method IN ('brain_intent_new', 'brain_intent_confirmed'));
  END IF;
END $$;

COMMENT ON COLUMN public.seo_brain_actor_links.link_method IS
  'How this mapping was created. NULL for every mapping created before this migration '
  '(operator bootstrap or a future admin surface). brain_intent_new: case A, a new '
  'passwordless SEO identity created from a Brain-confirmed email. brain_intent_confirmed: '
  'case B, an existing live SEO session explicitly confirmed by its own signed-in user. '
  'Never set from an automatic email match.';

ALTER TABLE public.seo_brain_website_links
  ADD COLUMN IF NOT EXISTS source_intent_id uuid REFERENCES public.seo_brain_link_intents(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.seo_brain_website_links.source_intent_id IS
  'The seo_brain_link_intents row this link was authorized from, when it was created through '
  'seo_brain_link_authorize. NULL for every link created through the plain administrative '
  'INSERT path, including the existing Stage 2B synthetic acceptance link.';

-- ---------------------------------------------------------------------------
-- 3. create_intent. Brain server to SEO only. service_role, called by the
--    seo-module-api edge function after it has already checked the same
--    machine secret every Contract v1 exchange uses.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_create_link_intent(
  p_brain_actor_id text,
  p_brain_confirmed_email text,
  p_brain_business_id text,
  p_normalized_host text,
  p_business_display_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
-- extensions is searched in addition to public because gen_random_bytes and
-- digest are pgcrypto functions, and pgcrypto lives in the extensions schema
-- on this project, not in public. gen_random_uuid needs no such addition:
-- Postgres 13+ ships it in pg_catalog, which every search_path implicitly
-- includes, which is why every other DEFINER function in this migration set
-- has never needed this.
SET search_path = public, extensions
AS $$
DECLARE
  v_actor    text := btrim(coalesce(p_brain_actor_id, ''));
  v_business text := btrim(coalesce(p_brain_business_id, ''));
  v_email    text := lower(btrim(coalesce(p_brain_confirmed_email, '')));
  v_host     text := btrim(coalesce(p_normalized_host, ''));
  v_display  text := nullif(btrim(coalesce(p_business_display_name, '')), '');
  v_code     text;
  v_hash     text;
  v_id       uuid;
  v_expires  timestamptz := now() + interval '120 seconds';
BEGIN
  IF v_actor = '' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'brain_actor_id is required');
  END IF;
  IF v_business = '' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'brain_business_id is required');
  END IF;
  IF v_email = '' OR v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'brain_confirmed_email is not a valid email');
  END IF;
  IF v_host = '' OR public.seo_brain_normalize_host(v_host) IS DISTINCT FROM v_host THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'normalized_host is not a canonical normalized host');
  END IF;
  IF v_display IS NOT NULL AND length(v_display) > 200 THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'business_display_name is too long');
  END IF;

  -- 32 random bytes, hex encoded: 256 bits of entropy, well beyond what a
  -- 120 second guessing window could threaten.
  v_code := encode(gen_random_bytes(32), 'hex');
  v_hash := encode(digest(v_code, 'sha256'), 'hex');

  INSERT INTO public.seo_brain_link_intents (
    brain_actor_id, brain_business_id, brain_confirmed_email, normalized_host,
    business_display_name, launch_code_hash, redemption_expires_at
  ) VALUES (
    v_actor, v_business, v_email, v_host, v_display, v_hash, v_expires
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'resolution',          'created',
    'intentId',            v_id,
    'launchCode',          v_code,
    'redemptionExpiresAt', v_expires
  );
END;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_create_link_intent(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_create_link_intent(text, text, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.seo_brain_create_link_intent(text, text, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_create_link_intent(text, text, text, text, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. redeem. Called directly by the customer's own browser over the ordinary
--    anon/authenticated Supabase client, exactly like any other customer
--    facing SEO RPC. This is the one place auth.uid() reflects the browser's
--    real current SEO session, which is what case B depends on.
--
--    Case order, and why: case D (an existing active actor mapping) is
--    checked first and unconditionally, because that mapping is already its
--    own proof and needs no session at all. Only once no mapping exists does a
--    live session decide case B (confirm before linking) versus case A/C,
--    which are decided by whether the Brain confirmed email already has an
--    SEO identity. Email is used only to choose between "create" and "refuse
--    and ask the customer to sign in"; it never merges an intent into an
--    existing account by itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_link_intent_redeem(
  p_launch_code text,
  p_confirm boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
-- extensions for digest(), the same reason as seo_brain_create_link_intent above.
SET search_path = public, extensions
AS $$
DECLARE
  v_hash          text := encode(digest(coalesce(p_launch_code, ''), 'sha256'), 'hex');
  v_intent        record;
  v_mapped_user   uuid;
  v_caller        uuid := auth.uid();
  v_existing_user uuid;
  v_conflict      boolean;
  v_claimed       record;
BEGIN
  IF btrim(coalesce(p_launch_code, '')) = '' THEN
    RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
  END IF;

  SELECT * INTO v_intent
  FROM public.seo_brain_link_intents
  WHERE launch_code_hash = v_hash;

  IF NOT FOUND OR v_intent.status NOT IN ('issued', 'pending_provisioning') OR now() > v_intent.redemption_expires_at THEN
    RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
  END IF;

  -- A case A provisioning call is already in flight for this code. This is an
  -- idempotent peek, not a new claim, so the SEO frontend can safely re-poll
  -- while it waits on account creation without burning anything.
  IF v_intent.status = 'pending_provisioning' THEN
    RETURN jsonb_build_object(
      'outcome',             'case_a_provisioning_required',
      'intentId',            v_intent.id,
      'brainConfirmedEmail', v_intent.brain_confirmed_email
    );
  END IF;

  -- Case D: an active mapping already exists for this Brain actor. It is
  -- already proof-backed, so it resolves unconditionally, ahead of whatever
  -- session state the browser happens to be in.
  v_mapped_user := public.seo_brain_resolve_actor(v_intent.brain_actor_id);
  IF v_mapped_user IS NOT NULL THEN
    UPDATE public.seo_brain_link_intents
    SET status = 'redeemed',
        redeemed_at = now(),
        redeemed_seo_user_id = v_mapped_user,
        redemption_outcome = 'case_d_existing_mapping',
        consent_expires_at = now() + interval '30 minutes'
    WHERE id = v_intent.id AND status = 'issued'
    RETURNING * INTO v_claimed;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
    END IF;

    RETURN jsonb_build_object(
      'outcome',  'case_d_resolved',
      'intentId', v_claimed.id,
      'seoUserId', v_mapped_user
    );
  END IF;

  -- No mapping. A live SEO session decides case B.
  IF v_caller IS NOT NULL THEN
    IF NOT p_confirm THEN
      -- Not yet a decision: nothing is claimed, so the same code can still be
      -- presented again once the customer has explicitly confirmed.
      RETURN jsonb_build_object('outcome', 'confirmation_required', 'intentId', v_intent.id);
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.seo_brain_actor_links l
      WHERE l.seo_user_id = v_caller AND l.link_status = 'active'
    ) INTO v_conflict;

    IF v_conflict THEN
      UPDATE public.seo_brain_link_intents
      SET status = 'refused'
      WHERE id = v_intent.id AND status = 'issued'
      RETURNING * INTO v_claimed;

      IF NOT FOUND THEN
        RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
      END IF;
      RETURN jsonb_build_object('outcome', 'case_b_conflict', 'intentId', v_claimed.id);
    END IF;

    UPDATE public.seo_brain_link_intents
    SET status = 'redeemed',
        redeemed_at = now(),
        redeemed_seo_user_id = v_caller,
        redemption_outcome = 'case_b_confirmed',
        consent_expires_at = now() + interval '30 minutes'
    WHERE id = v_intent.id AND status = 'issued'
    RETURNING * INTO v_claimed;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
    END IF;

    -- The explicit confirmation, taken while genuinely signed in, is the
    -- possession proof the actor-links migration required before a
    -- self-service mapping could exist. auth.uid() is non-null here, so the
    -- guard trigger records linked_by from the real session regardless of
    -- what is passed.
    INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id, link_method)
    VALUES (v_intent.brain_actor_id, v_caller, 'brain_intent_confirmed');

    RETURN jsonb_build_object(
      'outcome',  'case_b_confirmed',
      'intentId', v_claimed.id,
      'seoUserId', v_caller
    );
  END IF;

  -- No session. Case A versus case C turns on whether the Brain-confirmed
  -- email already has an SEO identity. This is the only place email is read,
  -- and it only ever chooses between "create" and "refuse"; it never merges.
  SELECT u.id INTO v_existing_user
  FROM auth.users u
  WHERE lower(u.email) = v_intent.brain_confirmed_email
  LIMIT 1;

  IF v_existing_user IS NOT NULL THEN
    UPDATE public.seo_brain_link_intents
    SET status = 'refused'
    WHERE id = v_intent.id AND status = 'issued'
    RETURNING * INTO v_claimed;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
    END IF;
    RETURN jsonb_build_object('outcome', 'existing_account_verification_required', 'intentId', v_claimed.id);
  END IF;

  UPDATE public.seo_brain_link_intents
  SET status = 'pending_provisioning'
  WHERE id = v_intent.id AND status = 'issued'
  RETURNING * INTO v_claimed;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('outcome', 'invalid_or_expired_code');
  END IF;

  RETURN jsonb_build_object(
    'outcome',             'case_a_provisioning_required',
    'intentId',            v_claimed.id,
    'brainConfirmedEmail', v_claimed.brain_confirmed_email
  );
END;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_link_intent_redeem(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seo_brain_link_intent_redeem(text, boolean) TO anon;
GRANT EXECUTE ON FUNCTION public.seo_brain_link_intent_redeem(text, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5a. Trusted email lookup for provisioning. service_role only. The edge
--     function calls this BEFORE calling the Admin API, so account creation
--     always uses SEO's own stored, Brain-confirmed email rather than
--     whatever a caller echoes back. Without this, a caller who obtained one
--     intentId (a random uuid, so this is already a high bar) could pair it
--     with an email of their own choosing and hijack a stranger's pending
--     provisioning. Returns NULL for anything that is not genuinely, still
--     pending, so the edge function has one place to fail closed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_link_intent_pending_email(p_intent_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT i.brain_confirmed_email
  FROM public.seo_brain_link_intents i
  WHERE i.id = p_intent_id
    AND i.status = 'pending_provisioning'
    AND now() <= i.redemption_expires_at;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_link_intent_pending_email(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_link_intent_pending_email(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.seo_brain_link_intent_pending_email(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_link_intent_pending_email(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. finalize_case_a. service_role only. Called by the edge function
--    immediately after it creates a passwordless auth user through the
--    official Supabase Admin API for a case A outcome, which is a step no SQL
--    function can safely perform itself. p_seo_user_id must be the user the
--    edge function just created for the EXACT email
--    seo_brain_link_intent_pending_email just returned for this same
--    p_intent_id; finalize itself re-checks pending_provisioning and expiry,
--    which is what actually prevents a stale or reused intentId from binding.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_link_intent_finalize_case_a(
  p_intent_id uuid,
  p_seo_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intent   record;
  v_conflict boolean;
BEGIN
  IF p_intent_id IS NULL THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'p_intent_id is required');
  END IF;
  IF p_seo_user_id IS NULL THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'p_seo_user_id is required');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p_seo_user_id) THEN
    RETURN jsonb_build_object('resolution', 'invalid_request', 'detail', 'p_seo_user_id does not exist');
  END IF;

  SELECT * INTO v_intent
  FROM public.seo_brain_link_intents
  WHERE id = p_intent_id
  FOR UPDATE;

  IF NOT FOUND OR v_intent.status <> 'pending_provisioning' OR now() > v_intent.redemption_expires_at THEN
    RETURN jsonb_build_object('resolution', 'invalid_or_expired_intent');
  END IF;

  -- Race safety: refuse rather than double-map if something else has claimed
  -- either side since this intent entered pending_provisioning.
  SELECT EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links l
    WHERE l.link_status = 'active'
      AND (l.brain_actor_id = v_intent.brain_actor_id OR l.seo_user_id = p_seo_user_id)
  ) INTO v_conflict;

  IF v_conflict THEN
    UPDATE public.seo_brain_link_intents SET status = 'refused' WHERE id = v_intent.id;
    RETURN jsonb_build_object('resolution', 'actor_conflict');
  END IF;

  INSERT INTO public.user_module_access (user_id, module_name, is_active, granted_by)
  VALUES (p_seo_user_id, 'seo', true, p_seo_user_id)
  ON CONFLICT (user_id, module_name) DO UPDATE SET is_active = true;

  INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id, linked_by, link_method)
  VALUES (v_intent.brain_actor_id, p_seo_user_id, p_seo_user_id, 'brain_intent_new');

  UPDATE public.seo_brain_link_intents
  SET status = 'redeemed',
      redeemed_at = now(),
      redeemed_seo_user_id = p_seo_user_id,
      redemption_outcome = 'case_a_new_identity',
      consent_expires_at = now() + interval '30 minutes'
  WHERE id = v_intent.id;

  RETURN jsonb_build_object('resolution', 'resolved', 'intentId', v_intent.id, 'seoUserId', p_seo_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.seo_brain_link_intent_finalize_case_a(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_link_intent_finalize_case_a(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.seo_brain_link_intent_finalize_case_a(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_link_intent_finalize_case_a(uuid, uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 6. authorize. The single transactional path that turns a redeemed intent
--    into a durable website link. authenticated only: the caller must be
--    genuinely signed in as the exact SEO user the intent redeemed to.
-- ---------------------------------------------------------------------------
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
  v_caller     uuid := auth.uid();
  v_intent     record;
  v_website    record;
  v_ownership  text;
  v_website_host text;
  v_new_id     uuid;
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

  SELECT v.status INTO v_ownership
  FROM public.seo_ownership_verifications v
  WHERE v.website_id = p_website_id AND v.method = 'dns_txt';

  IF coalesce(v_ownership, 'not_started') <> 'verified' THEN
    RETURN jsonb_build_object('resolution', 'ownership_not_verified');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.seo_brain_website_links l
    WHERE l.business_id = v_intent.brain_business_id
      AND l.normalized_host = v_intent.normalized_host
      AND l.link_status = 'active'
  ) THEN
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

REVOKE ALL ON FUNCTION public.seo_brain_link_authorize(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_link_authorize(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_brain_link_authorize(uuid, uuid) TO authenticated;
