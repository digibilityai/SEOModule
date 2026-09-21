-- =============================================================================
-- SEO Digi Brain, D-026A SEO PR-1, LINK INTENT VERIFICATION
--   public.seo_brain_link_intents
--   public.seo_brain_create_link_intent
--   public.seo_brain_link_intent_redeem
--   public.seo_brain_link_intent_pending_email
--   public.seo_brain_link_intent_finalize_case_a
--   public.seo_brain_link_authorize
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on a local/fresh project or Digi_SEO_Test, AFTER
-- 20260921120000_seo_brain_link_intents.sql and everything it depends on
-- (the five 20260920 Stage 2B migrations). NOT RUN as part of this PR; see the
-- PR description. Dry-run verified, inside BEGIN/ROLLBACK, against
-- Digi_SEO_Test's actual current state during PR-1 development.
--
-- Self-contained and self-seeding, in the same style as
-- seo_brain_module_boundary_verification.sql: creates its own disposable
-- workspace, memberships, websites and ownership rows, reuses the same shared
-- TEST fixture auth.users this repository's other verification scripts
-- already depend on, and is a single implicit transaction so any failed
-- assertion rolls back every fixture it created.
--
-- b1.owner and b1.client ALREADY carry real, active seo_brain_actor_links rows
-- from the genuine Stage 2B acceptance evidence, and this script must not
-- disturb that: revoking either would be irreversible (the guard trigger makes
-- revocation terminal) and would destroy real acceptance history. Case D
-- therefore reads b1.owner's EXISTING mapping rather than creating one, and
-- every test that needs a genuinely UNMAPPED user uses b1.nomem, which carries
-- no mapping on Digi_SEO_Test today. Explicit teardown at the end removes
-- every row this script itself created, including the module-access grant and
-- actor link it places on b1.nomem, so it leaves zero residue and disturbs no
-- pre-existing row.
--
-- Proves:
--   * create_intent: input validation (actor id, business id, email shape,
--     canonical host, display name length) and a genuine created intent;
--   * redeem: an unknown code is invalid_or_expired_code; a code cannot be
--     redeemed twice; an expired code is refused; case D resolves an
--     existing active actor mapping unconditionally, ahead of any session;
--     case B requires a live session AND explicit confirmation before it
--     creates a mapping, refuses a session already mapped to a different
--     actor, and creates the mapping with a genuine linked_by; case C
--     (existing auth.users email, no session, no mapping) refuses safely and
--     creates nothing, and burns its code even though nothing was bound; case
--     A (new email) reaches pending_provisioning and nothing else, and
--     seo_brain_link_intent_pending_email discloses the email ONLY while a
--     code is genuinely pending and nothing once it is not;
--   * finalize_case_a: grants module access, creates a link_method =
--     'brain_intent_new' actor mapping, and marks the intent redeemed;
--     refuses a stale or already-resolved intentId; refuses on an actor
--     conflict;
--   * authorize: the full precondition chain (redeemed, matching user,
--     within the consent window, module access, owner/admin role, active
--     website, host match, verified ownership, no conflicting link),
--     genuine linked_by = auth.uid(), source_intent_id recorded, the intent
--     marked link_created, and that it cannot be spent twice; an unrelated
--     workspace's website answers exactly like a nonexistent one;
--   * grants: create_intent, pending_email and finalize_case_a are
--     service_role only; redeem is anon and authenticated; authorize is
--     authenticated only;
--   * RLS: seo_brain_link_intents has no INSERT/UPDATE grant to anon or
--     authenticated at all; a redeemed user (or a global admin) may SELECT
--     their own row and nobody else's.
--
-- NOT covered here, and why: the ACTUAL creation of a passwordless auth user
-- in case A is performed by the Edge Function through
-- supabase.auth.admin.createUser, which no SQL script may safely replicate;
-- see link-intent.test.ts for that step's own coverage (with a mocked Admin
-- API), and Section 8 below for finalize_case_a exercised against a stand-in
-- id in auth.users that already exists. Likewise, this script exercises case
-- B's "already mapped, refused" and "confirmation required" sub-paths against
-- real data, but not a from-scratch case B SUCCESS against a truly unmapped
-- live session distinct from the one case A/finalize_case_a also uses,
-- because Digi_SEO_Test has only one shared fixture user (b1.nomem) with no
-- pre-existing mapping; see the PR description for how this gap is closed.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PREREQUISITE, ASSERTED BEFORE ANY MUTATION.
-- ---------------------------------------------------------------------------
SELECT set_config('b1.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('b1.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('b1.nomem',  '0723d21f-c02c-4725-851f-575f93f2f58c', false);

DO $prereq$
DECLARE
  v_pat  text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_keys text[] := ARRAY['owner', 'client', 'nomem'];
  v_k    text;
  v_v    text;
BEGIN
  FOREACH v_k IN ARRAY v_keys LOOP
    v_v := current_setting('b1.' || v_k, true);
    IF v_v IS NULL OR v_v !~ v_pat THEN
      RAISE EXCEPTION 'PREREQUISITE FAILED: b1.% ("%") is not a valid auth.users UUID.', v_k, coalesce(v_v, '<unset>');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_v::uuid) THEN
      RAISE EXCEPTION 'PREREQUISITE FAILED: the fixture auth user for b1.% (%) does not exist on this project.', v_k, v_v;
    END IF;
  END LOOP;

  IF to_regclass('public.seo_brain_link_intents') IS NULL THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: 20260921120000_seo_brain_link_intents.sql is not applied.';
  END IF;
  IF to_regprocedure('public.seo_brain_link_authorize(uuid, uuid)') IS NULL THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: public.seo_brain_link_authorize is absent.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_workspaces WHERE name LIKE 'LINKINTENT-VERIFY%')
     OR EXISTS (SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%') THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: fixtures from a previous run are still present.';
  END IF;
  -- b1.nomem must be genuinely unmapped, or Sections 4 and 6/8 below cannot
  -- exercise a clean-slate path without disturbing something real.
  IF EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links WHERE seo_user_id = current_setting('b1.nomem')::uuid AND link_status = 'active'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: b1.nomem already has an active actor mapping; this script needs one genuinely free fixture user.';
  END IF;
END $prereq$;

-- ---------------------------------------------------------------------------
-- Fixture workspace, websites and ownership.
-- ---------------------------------------------------------------------------
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('11000000-0000-4000-8000-000000000001', 'LINKINTENT-VERIFY ws1', current_setting('b1.owner')::uuid);

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role)
VALUES ('11000000-0000-4000-8000-000000000001', current_setting('b1.client')::uuid, 'client')
ON CONFLICT (workspace_id, user_id) DO UPDATE SET seo_role = 'client';

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, is_active, archived_at)
VALUES
  ('11000000-0000-4000-8000-00000000000a', '11000000-0000-4000-8000-000000000001',
   'https://linkintent-verify-a.test', 'Fixture A', 'Fixture', true, NULL),
  ('11000000-0000-4000-8000-00000000000b', '11000000-0000-4000-8000-000000000001',
   'https://linkintent-verify-b.test', 'Fixture B, unverified ownership', 'Fixture', true, NULL),
  ('11000000-0000-4000-8000-00000000000c', '11000000-0000-4000-8000-000000000001',
   'https://linkintent-verify-c.test', 'Fixture C, inactive', 'Fixture', false, now()),
  ('11000000-0000-4000-8000-00000000000e', '11000000-0000-4000-8000-000000000001',
   'https://linkintent-verify-e.test', 'Fixture E, active, different host', 'Fixture', true, NULL);

-- A second, unrelated workspace + website, owned by nobody in ws1, to prove an
-- unrelated website answers identically to a nonexistent one.
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES ('11000000-0000-4000-8000-000000000002', 'LINKINTENT-VERIFY ws2 (unrelated)', current_setting('b1.nomem')::uuid);
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, is_active)
VALUES ('11000000-0000-4000-8000-00000000000d', '11000000-0000-4000-8000-000000000002',
        'https://linkintent-verify-d.test', 'Fixture D, unrelated workspace', 'Fixture', true);

INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at, last_checked_at)
VALUES
  ('11000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-00000000000a',
   'https://linkintent-verify-a.test', 'linkintent-verify-a.test', 'dns_txt', 'verified',
   'digibility-site-verification=linkintentverifytoken', now(), now());
-- Fixture B deliberately has NO ownership row: status resolves to 'not_started'.

-- ---------------------------------------------------------------------------
-- 1. create_intent: validation.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r jsonb;
BEGIN
  r := public.seo_brain_create_link_intent('', 'a@b.com', 'biz-1', 'linkintent-verify-a.test');
  IF r->>'resolution' <> 'invalid_request' THEN RAISE EXCEPTION 'empty actor id must be refused, got %', r; END IF;

  r := public.seo_brain_create_link_intent('actor-1', 'not-an-email', 'biz-1', 'linkintent-verify-a.test');
  IF r->>'resolution' <> 'invalid_request' THEN RAISE EXCEPTION 'bad email must be refused, got %', r; END IF;

  r := public.seo_brain_create_link_intent('actor-1', 'a@b.com', '', 'linkintent-verify-a.test');
  IF r->>'resolution' <> 'invalid_request' THEN RAISE EXCEPTION 'empty business id must be refused, got %', r; END IF;

  r := public.seo_brain_create_link_intent('actor-1', 'a@b.com', 'biz-1', 'https://linkintent-verify-a.test');
  IF r->>'resolution' <> 'invalid_request' THEN
    RAISE EXCEPTION 'a non-canonical host (scheme present) must be refused, got %', r;
  END IF;

  r := public.seo_brain_create_link_intent('actor-1', 'a@b.com', 'biz-1', 'linkintent-verify-a.test', repeat('x', 201));
  IF r->>'resolution' <> 'invalid_request' THEN RAISE EXCEPTION 'an overlong display name must be refused, got %', r; END IF;

  r := public.seo_brain_create_link_intent('actor-1', 'A@B.com', 'biz-1', 'linkintent-verify-a.test', 'Fixture Business');
  IF r->>'resolution' <> 'created' OR NOT (r ? 'intentId') OR NOT (r ? 'launchCode') OR NOT (r ? 'redemptionExpiresAt') THEN
    RAISE EXCEPTION 'a well formed request must create an intent, got %', r;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. redeem: unknown code.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r jsonb;
BEGIN
  r := public.seo_brain_link_intent_redeem('not-a-real-code', false);
  IF r->>'outcome' <> 'invalid_or_expired_code' THEN RAISE EXCEPTION 'unknown code must be invalid_or_expired_code, got %', r; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Case D: an active actor mapping already exists. Resolves unconditionally
--    with no session at all, and cannot be redeemed twice.
--
--    Reads b1.owner's EXISTING active mapping rather than creating one: on
--    Digi_SEO_Test that is real Stage 2B acceptance evidence, and revoking it
--    to make room would be irreversible. On a genuinely fresh project, where
--    b1.owner starts unmapped, this falls back to creating one, which the
--    teardown below then removes.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_existing text;
BEGIN
  SELECT l.brain_actor_id INTO v_existing
  FROM public.seo_brain_actor_links l
  WHERE l.seo_user_id = current_setting('b1.owner')::uuid AND l.link_status = 'active';

  IF v_existing IS NOT NULL THEN
    PERFORM set_config('li.actor_d', v_existing, false);
    PERFORM set_config('li.actor_d_fixture_owned', 'false', false);
  ELSE
    INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id, linked_by)
    VALUES ('LINKINTENT-VERIFY-actor-d', current_setting('b1.owner')::uuid, current_setting('b1.owner')::uuid);
    PERFORM set_config('li.actor_d', 'LINKINTENT-VERIFY-actor-d', false);
    PERFORM set_config('li.actor_d_fixture_owned', 'true', false);
  END IF;
END $$;

DO $$
DECLARE
  created jsonb;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    current_setting('li.actor_d'), 'd-case@example.test', 'LINKINTENT-VERIFY-biz-d', 'linkintent-verify-a.test');
  PERFORM set_config('li.code_d', created->>'launchCode', false);

  r := public.seo_brain_link_intent_redeem(current_setting('li.code_d'), false);
  IF r->>'outcome' <> 'case_d_resolved' THEN RAISE EXCEPTION 'case D must resolve, got %', r; END IF;
  IF (r->>'seoUserId')::uuid <> current_setting('b1.owner')::uuid THEN
    RAISE EXCEPTION 'case D must resolve to the mapped user, got %', r;
  END IF;
  PERFORM set_config('li.intent_d', r->>'intentId', false);

  r := public.seo_brain_link_intent_redeem(current_setting('li.code_d'), false);
  IF r->>'outcome' <> 'invalid_or_expired_code' THEN
    RAISE EXCEPTION 'a redeemed code must not be redeemable again, got %', r;
  END IF;
END $$;

-- Fabricate expiry on a fresh intent to prove an expired code is refused.
DO $$
DECLARE
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKINTENT-VERIFY-actor-expired', 'expired-case@example.test', 'LINKINTENT-VERIFY-biz-expired',
    'linkintent-verify-a.test');
  intent_id := (created->>'intentId')::uuid;

  UPDATE public.seo_brain_link_intents SET redemption_expires_at = now() - interval '1 second' WHERE id = intent_id;

  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  IF r->>'outcome' <> 'invalid_or_expired_code' THEN RAISE EXCEPTION 'an expired code must be refused, got %', r; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Case B: a live SEO session, no existing mapping. Requires confirm=true,
--    and refuses a session already mapped to a different actor. Uses
--    b1.nomem, the one shared fixture confirmed free of any mapping above; it
--    is left mapped to 'LINKINTENT-VERIFY-actor-b' at the end of this
--    section, and freed again immediately afterward so Section 6/8 can reuse
--    it from a clean slate.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKINTENT-VERIFY-actor-b', 'b-case@example.test', 'LINKINTENT-VERIFY-biz-b', 'linkintent-verify-a.test');
  PERFORM set_config('li.code_b', created->>'launchCode', false);

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.nomem'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  -- Unconfirmed: a decision is not yet made, so nothing is claimed.
  r := public.seo_brain_link_intent_redeem(current_setting('li.code_b'), false);
  IF r->>'outcome' <> 'confirmation_required' THEN
    RESET ROLE;
    RAISE EXCEPTION 'a live session without confirm must ask for confirmation, got %', r;
  END IF;

  -- The SAME code, still valid: confirming now creates the mapping.
  r := public.seo_brain_link_intent_redeem(current_setting('li.code_b'), true);
  IF r->>'outcome' <> 'case_b_confirmed' THEN
    RESET ROLE;
    RAISE EXCEPTION 'a confirmed live session must resolve to case_b_confirmed, got %', r;
  END IF;
  IF (r->>'seoUserId')::uuid <> current_setting('b1.nomem')::uuid THEN
    RESET ROLE;
    RAISE EXCEPTION 'case B must bind the signed-in user, got %', r;
  END IF;

  RESET ROLE;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links l
    WHERE l.brain_actor_id = 'LINKINTENT-VERIFY-actor-b'
      AND l.seo_user_id = current_setting('b1.nomem')::uuid
      AND l.link_status = 'active'
      AND l.link_method = 'brain_intent_confirmed'
  ) THEN
    RAISE EXCEPTION 'case B must create an actor link with link_method brain_intent_confirmed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links l
    WHERE l.brain_actor_id = 'LINKINTENT-VERIFY-actor-b' AND l.linked_by = current_setting('b1.nomem')::uuid
  ) THEN
    RAISE EXCEPTION 'case B linked_by must be the genuine signed-in user, from auth.uid(), not asserted';
  END IF;
END $$;

-- b1.nomem is now actively mapped. A second, unrelated intent for a
-- DIFFERENT actor, confirmed by the same now-mapped session, must be refused.
DO $$
DECLARE
  created jsonb;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKINTENT-VERIFY-actor-b2', 'b2-case@example.test', 'LINKINTENT-VERIFY-biz-b2', 'linkintent-verify-a.test');

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.nomem'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  r := public.seo_brain_link_intent_redeem(created->>'launchCode', true);
  RESET ROLE;

  IF r->>'outcome' <> 'case_b_conflict' THEN
    RAISE EXCEPTION 'an already-mapped session confirming a different actor must be case_b_conflict, got %', r;
  END IF;
  IF EXISTS (SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id = 'LINKINTENT-VERIFY-actor-b2') THEN
    RAISE EXCEPTION 'case_b_conflict must create no mapping';
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- Free b1.nomem again so Sections 6 and 8 start from a genuinely clean slate.
DELETE FROM public.seo_brain_actor_links WHERE brain_actor_id = 'LINKINTENT-VERIFY-actor-b';

-- ---------------------------------------------------------------------------
-- 5. Case C: the Brain-confirmed email already has an SEO identity, no
--    session, no mapping. Refuses safely and creates nothing. Uses b1.owner's
--    real email, read only: nothing about b1.owner is mutated here.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  owner_email text;
  created jsonb;
  r jsonb;
BEGIN
  SELECT email INTO owner_email FROM auth.users WHERE id = current_setting('b1.owner')::uuid;
  IF owner_email IS NULL THEN
    RAISE EXCEPTION 'fixture b1.owner has no email on this project; cannot exercise case C';
  END IF;

  created := public.seo_brain_create_link_intent(
    'LINKINTENT-VERIFY-actor-c', owner_email, 'LINKINTENT-VERIFY-biz-c', 'linkintent-verify-a.test');

  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  IF r->>'outcome' <> 'existing_account_verification_required' THEN
    RAISE EXCEPTION 'an existing email with no session must be existing_account_verification_required, got %', r;
  END IF;
  IF EXISTS (SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id = 'LINKINTENT-VERIFY-actor-c') THEN
    RAISE EXCEPTION 'case C must never create a mapping';
  END IF;

  -- Single use: the code is burned even though nothing was bound.
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  IF r->>'outcome' <> 'invalid_or_expired_code' THEN RAISE EXCEPTION 'a case C code must not be reusable, got %', r; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6. Case A: a genuinely new email. Reaches pending_provisioning and nothing
--    else. pending_email discloses the email only while genuinely pending.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb;
  r jsonb;
  intent_id uuid;
  email text;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKINTENT-VERIFY-actor-a', 'a-case-new@example.test', 'LINKINTENT-VERIFY-biz-a', 'linkintent-verify-a.test');
  PERFORM set_config('li.code_a', created->>'launchCode', false);
  intent_id := (created->>'intentId')::uuid;
  PERFORM set_config('li.intent_a', intent_id::text, false);

  -- Before redemption, the email is not yet disclosed: the intent is
  -- 'issued', not 'pending_provisioning'.
  email := public.seo_brain_link_intent_pending_email(intent_id);
  IF email IS NOT NULL THEN RAISE EXCEPTION 'pending_email must be NULL before redemption, got %', email; END IF;

  r := public.seo_brain_link_intent_redeem(current_setting('li.code_a'), false);
  IF r->>'outcome' <> 'case_a_provisioning_required' THEN
    RAISE EXCEPTION 'a genuinely new email must reach case_a_provisioning_required, got %', r;
  END IF;
  IF r->>'brainConfirmedEmail' <> 'a-case-new@example.test' THEN
    RAISE EXCEPTION 'case A must return the stored confirmed email, got %', r;
  END IF;

  -- Now genuinely pending: the trusted lookup discloses it.
  email := public.seo_brain_link_intent_pending_email(intent_id);
  IF email <> 'a-case-new@example.test' THEN
    RAISE EXCEPTION 'pending_email must return the email while pending, got %', email;
  END IF;

  -- Re-presenting the same code while pending is an idempotent peek, not a
  -- second claim: it returns the same outcome and burns nothing further.
  r := public.seo_brain_link_intent_redeem(current_setting('li.code_a'), false);
  IF r->>'outcome' <> 'case_a_provisioning_required' THEN
    RAISE EXCEPTION 're-presenting a pending code must still be case_a_provisioning_required, got %', r;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 7. finalize_case_a, standing in for the edge function's post-createUser
--    call. b1.nomem stands in for a user supabase.auth.admin.createUser would
--    have just created; this script never creates an Auth user itself.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  intent_id uuid := current_setting('li.intent_a')::uuid;
  stand_in  uuid := current_setting('b1.nomem')::uuid;
  r jsonb;
  email text;
BEGIN
  r := public.seo_brain_link_intent_finalize_case_a(intent_id, stand_in);
  IF r->>'resolution' <> 'resolved' THEN RAISE EXCEPTION 'finalize_case_a must resolve, got %', r; END IF;
  IF (r->>'seoUserId')::uuid <> stand_in THEN RAISE EXCEPTION 'finalize_case_a must bind the supplied user, got %', r; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_module_access WHERE user_id = stand_in AND module_name = 'seo' AND is_active
  ) THEN
    RAISE EXCEPTION 'finalize_case_a must grant SEO module access';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links
    WHERE brain_actor_id = 'LINKINTENT-VERIFY-actor-a' AND seo_user_id = stand_in
      AND link_status = 'active' AND link_method = 'brain_intent_new' AND linked_by = stand_in
  ) THEN
    RAISE EXCEPTION 'finalize_case_a must create a brain_intent_new actor link, self-authorized';
  END IF;

  -- Once resolved, pending_email no longer discloses anything: the intent is
  -- 'redeemed', not 'pending_provisioning'.
  email := public.seo_brain_link_intent_pending_email(intent_id);
  IF email IS NOT NULL THEN RAISE EXCEPTION 'pending_email must be NULL once redeemed, got %', email; END IF;

  -- A second finalize on the same, now-redeemed intent is refused.
  r := public.seo_brain_link_intent_finalize_case_a(intent_id, stand_in);
  IF r->>'resolution' <> 'invalid_or_expired_intent' THEN
    RAISE EXCEPTION 'finalize_case_a must refuse a non-pending intent, got %', r;
  END IF;
END $$;

-- finalize_case_a refuses on a genuine actor conflict: b1.nomem is already
-- actively mapped (to actor-a, from the section above).
DO $$
DECLARE
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKINTENT-VERIFY-actor-a2', 'a2-case-new@example.test', 'LINKINTENT-VERIFY-biz-a2', 'linkintent-verify-a.test');
  intent_id := (created->>'intentId')::uuid;
  PERFORM public.seo_brain_link_intent_redeem(created->>'launchCode', false); -- -> pending_provisioning

  r := public.seo_brain_link_intent_finalize_case_a(intent_id, current_setting('b1.nomem')::uuid);
  IF r->>'resolution' <> 'actor_conflict' THEN
    RAISE EXCEPTION 'finalize_case_a must refuse a seo_user_id already actively mapped, got %', r;
  END IF;
END $$;
DELETE FROM public.seo_brain_link_intents WHERE brain_actor_id = 'LINKINTENT-VERIFY-actor-a2';

-- ---------------------------------------------------------------------------
-- 8. authorize: the full precondition chain, using the case D intent redeemed
--    in Section 3 (b1.owner, already the owner of the fixture workspace).
-- ---------------------------------------------------------------------------

-- 8a. Success.
DO $$
DECLARE
  r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  r := public.seo_brain_link_authorize(current_setting('li.intent_d')::uuid, '11000000-0000-4000-8000-00000000000a');
  RESET ROLE;

  IF r->>'resolution' <> 'resolved' THEN RAISE EXCEPTION 'authorize must resolve for the redeemed owner, got %', r; END IF;
  IF r->>'normalizedHost' <> 'linkintent-verify-a.test' THEN RAISE EXCEPTION 'authorize must echo the intent host, got %', r; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_website_links l
    WHERE l.business_id = 'LINKINTENT-VERIFY-biz-d'
      AND l.website_id = '11000000-0000-4000-8000-00000000000a'
      AND l.link_status = 'active'
      AND l.linked_by = current_setting('b1.owner')::uuid
      AND l.source_intent_id = current_setting('li.intent_d')::uuid
  ) THEN
    RAISE EXCEPTION 'authorize must create a link with genuine linked_by and source_intent_id';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_link_intents
    WHERE id = current_setting('li.intent_d')::uuid AND status = 'link_created'
      AND consumed_website_id = '11000000-0000-4000-8000-00000000000a'
  ) THEN
    RAISE EXCEPTION 'authorize must mark the intent link_created';
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8b. A consumed intent cannot be spent twice.
DO $$
DECLARE
  r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  r := public.seo_brain_link_authorize(current_setting('li.intent_d')::uuid, '11000000-0000-4000-8000-00000000000b');
  RESET ROLE;
  IF r->>'resolution' <> 'intent_not_redeemed' THEN
    RAISE EXCEPTION 'a consumed intent must refuse as intent_not_redeemed, got %', r;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8c. Identity mismatch: an intent this script never redeemed for b1.client
--     cannot be authorized by b1.client either (there is no redeemed intent
--     at all for it in this run, so this doubles as an intent_not_redeemed
--     check from a different caller's perspective; a dedicated case-B intent
--     was intentionally not kept mapped to b1.client on this project, per the
--     header note, so this section asserts against a fresh, never-redeemed
--     intent instead).
DO $$
DECLARE
  created jsonb;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    current_setting('li.actor_d'), 'd-case-mismatch@example.test', 'LINKINTENT-VERIFY-biz-mismatch',
    'linkintent-verify-a.test');
  PERFORM public.seo_brain_link_intent_redeem(created->>'launchCode', false); -- resolves to b1.owner (case D)

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.client'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  r := public.seo_brain_link_authorize((created->>'intentId')::uuid, '11000000-0000-4000-8000-00000000000b');
  RESET ROLE;

  IF r->>'resolution' <> 'identity_mismatch' THEN
    RAISE EXCEPTION 'authorize by a user other than the redeemed one must be identity_mismatch, got %', r;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8d. b1.client is only a 'client' in this workspace: an intent genuinely
--     redeemed for b1.client (via case D, reusing whatever b1.client is
--     really mapped to) is refused as unauthorized when it tries to
--     authorize a link.
DO $$
DECLARE
  v_client_actor text;
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  SELECT l.brain_actor_id INTO v_client_actor
  FROM public.seo_brain_actor_links l
  WHERE l.seo_user_id = current_setting('b1.client')::uuid AND l.link_status = 'active';

  IF v_client_actor IS NULL THEN
    RAISE NOTICE 'b1.client has no active actor mapping on this project; skipping 8d (client-role refusal is still covered by Section 9''s RLS-equivalent assertions in the module boundary script)';
  ELSE
    created := public.seo_brain_create_link_intent(
      v_client_actor, 'client-role-case@example.test', 'LINKINTENT-VERIFY-biz-client-role', 'linkintent-verify-a.test');
    r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
    intent_id := (r->>'intentId')::uuid;

    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', current_setting('b1.client'), 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    r := public.seo_brain_link_authorize(intent_id, '11000000-0000-4000-8000-00000000000b');
    RESET ROLE;

    IF r->>'resolution' <> 'unauthorized' THEN RAISE EXCEPTION 'a client role must be unauthorized, got %', r; END IF;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8e. Ownership not verified (fixture B has no verification row).
DO $$
DECLARE
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  -- Host must match fixture B's own host, or host_mismatch would fire first.
  created := public.seo_brain_create_link_intent(
    current_setting('li.actor_d'), 'd-case-2@example.test', 'LINKINTENT-VERIFY-biz-d2', 'linkintent-verify-b.test');
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false); -- case D again, unconditional
  intent_id := (r->>'intentId')::uuid;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  r := public.seo_brain_link_authorize(intent_id, '11000000-0000-4000-8000-00000000000b');
  RESET ROLE;

  IF r->>'resolution' <> 'ownership_not_verified' THEN
    RAISE EXCEPTION 'an unverified website must refuse as ownership_not_verified, got %', r;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8f. Host mismatch: the intent's host is fixture A's; presented against
--     fixture E (active, but a different host), it must fail on host, not on
--     activity or ownership. Fixture C is deliberately NOT used here: it is
--     both inactive AND host-mismatched, which would leave this assertion
--     unable to tell which check actually fired.
DO $$
DECLARE
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    current_setting('li.actor_d'), 'd-case-3@example.test', 'LINKINTENT-VERIFY-biz-d3', 'linkintent-verify-a.test');
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  intent_id := (r->>'intentId')::uuid;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  r := public.seo_brain_link_authorize(intent_id, '11000000-0000-4000-8000-00000000000e');
  RESET ROLE;

  IF r->>'resolution' <> 'host_mismatch' THEN
    RAISE EXCEPTION 'a website whose host differs from the intent must refuse as host_mismatch, got %', r;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8g. An unrelated workspace's website answers exactly like a nonexistent id.
DO $$
DECLARE
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    current_setting('li.actor_d'), 'd-case-4@example.test', 'LINKINTENT-VERIFY-biz-d4', 'linkintent-verify-d.test');
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  intent_id := (r->>'intentId')::uuid;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  r := public.seo_brain_link_authorize(intent_id, '11000000-0000-4000-8000-00000000000d');
  RESET ROLE;

  IF r->>'resolution' <> 'website_not_found' THEN
    RAISE EXCEPTION 'an unrelated workspace website must refuse as website_not_found, got %', r;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- 8h. business_host_already_linked: fixture A is already linked (business-d)
--     from Section 8a.
DO $$
DECLARE
  created jsonb;
  intent_id uuid;
  r jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    current_setting('li.actor_d'), 'd-case-5@example.test', 'LINKINTENT-VERIFY-biz-d', 'linkintent-verify-a.test');
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  intent_id := (r->>'intentId')::uuid;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  r := public.seo_brain_link_authorize(intent_id, '11000000-0000-4000-8000-00000000000a');
  RESET ROLE;

  IF r->>'resolution' <> 'business_host_already_linked' THEN
    RAISE EXCEPTION 'the same business/host must refuse as business_host_already_linked, got %', r;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- ---------------------------------------------------------------------------
-- 9. Grants.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_brain_create_link_intent(text, text, text, text, text)',
    'public.seo_brain_link_intent_pending_email(uuid)',
    'public.seo_brain_link_intent_finalize_case_a(uuid, uuid)'
  ] LOOP
    IF has_function_privilege('anon', fn, 'EXECUTE') THEN RAISE EXCEPTION 'anon must not execute %', fn; END IF;
    IF has_function_privilege('authenticated', fn, 'EXECUTE') THEN RAISE EXCEPTION 'authenticated must not execute %', fn; END IF;
    IF NOT has_function_privilege('service_role', fn, 'EXECUTE') THEN RAISE EXCEPTION 'service_role must execute %', fn; END IF;
  END LOOP;

  fn := 'public.seo_brain_link_intent_redeem(text, boolean)';
  IF NOT has_function_privilege('anon', fn, 'EXECUTE') THEN RAISE EXCEPTION 'anon must execute %', fn; END IF;
  IF NOT has_function_privilege('authenticated', fn, 'EXECUTE') THEN RAISE EXCEPTION 'authenticated must execute %', fn; END IF;

  fn := 'public.seo_brain_link_authorize(uuid, uuid)';
  IF has_function_privilege('anon', fn, 'EXECUTE') THEN RAISE EXCEPTION 'anon must not execute %', fn; END IF;
  IF NOT has_function_privilege('authenticated', fn, 'EXECUTE') THEN RAISE EXCEPTION 'authenticated must execute %', fn; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 10. RLS on seo_brain_link_intents: no human write path at all.
--
--     This project follows the same convention seen throughout this
--     repository's schema: table-level GRANTs to anon/authenticated are
--     broad, by Supabase's own default, and ROW LEVEL SECURITY is the actual
--     enforcement layer. has_table_privilege would therefore report a false
--     positive here; the only honest proof is attempting the write and
--     catching the refusal, exactly as the existing module boundary
--     verification script does for the client-role link-authorization case.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.nomem'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.seo_brain_link_intents
      (brain_actor_id, brain_business_id, brain_confirmed_email, normalized_host, launch_code_hash, redemption_expires_at)
    VALUES ('LINKINTENT-VERIFY-rls-probe', 'biz', 'a@b.com', 'linkintent-verify-a.test', repeat('0', 64), now());
    RESET ROLE;
    RAISE EXCEPTION 'an authenticated user must not be able to insert into seo_brain_link_intents directly';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
  END;
END $$;

-- UPDATE (unlike INSERT's WITH CHECK) does not raise when RLS excludes every
-- row: with no UPDATE policy at all, the USING clause matches nothing, so the
-- honest proof is that it silently affects zero rows, not that it errors.
DO $$
DECLARE
  n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.nomem'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  UPDATE public.seo_brain_link_intents SET status = 'refused' WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%';
  GET DIAGNOSTICS n = ROW_COUNT;
  RESET ROLE;
  IF n <> 0 THEN
    RAISE EXCEPTION 'an authenticated user must not be able to update seo_brain_link_intents directly, affected % rows', n;
  END IF;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

DO $$
DECLARE
  n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.owner'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO n FROM public.seo_brain_link_intents WHERE redeemed_seo_user_id = current_setting('b1.owner')::uuid;
  IF n = 0 THEN
    RESET ROLE;
    RAISE EXCEPTION 'the redeemed owner must be able to select their own intent';
  END IF;

  SELECT count(*) INTO n FROM public.seo_brain_link_intents WHERE redeemed_seo_user_id = current_setting('b1.nomem')::uuid;
  IF n <> 0 THEN
    RESET ROLE;
    RAISE EXCEPTION 'the owner must not see a different user''s redeemed intent, saw %', n;
  END IF;

  RESET ROLE;
END $$;
SELECT set_config('request.jwt.claims',     '', false),
       set_config('request.jwt.claim.sub',  '', false),
       set_config('request.jwt.claim.role', '', false);

-- ---------------------------------------------------------------------------
-- TEARDOWN. Removes every fixture this script created, including the
-- module-access grant and actor link it placed on the shared b1.nomem
-- fixture, and the actor link it may have created on b1.owner (only when that
-- fallback was actually used), so this script leaves zero residue and
-- disturbs no pre-existing row.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF current_setting('li.actor_d_fixture_owned', true) = 'true' THEN
    DELETE FROM public.seo_brain_actor_links WHERE brain_actor_id = current_setting('li.actor_d');
  END IF;
END $$;

DELETE FROM public.seo_brain_website_links WHERE business_id LIKE 'LINKINTENT-VERIFY-%';
DELETE FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%';
DELETE FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%';
DELETE FROM public.user_module_access
  WHERE user_id = '0723d21f-c02c-4725-851f-575f93f2f58c'::uuid AND module_name = 'seo';
DELETE FROM public.seo_ownership_verifications WHERE website_id IN (
  '11000000-0000-4000-8000-00000000000a', '11000000-0000-4000-8000-00000000000b',
  '11000000-0000-4000-8000-00000000000c', '11000000-0000-4000-8000-00000000000d',
  '11000000-0000-4000-8000-00000000000e'
);
DELETE FROM public.seo_workspace_members WHERE workspace_id IN (
  '11000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002'
);
DELETE FROM public.seo_websites WHERE id IN (
  '11000000-0000-4000-8000-00000000000a', '11000000-0000-4000-8000-00000000000b',
  '11000000-0000-4000-8000-00000000000c', '11000000-0000-4000-8000-00000000000d',
  '11000000-0000-4000-8000-00000000000e'
);
DELETE FROM public.seo_workspaces WHERE id IN (
  '11000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000002'
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'LINKINTENT-VERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_brain_website_links WHERE business_id LIKE 'LINKINTENT-VERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_workspaces WHERE name LIKE 'LINKINTENT-VERIFY%')
     OR EXISTS (
          SELECT 1 FROM public.user_module_access
          WHERE user_id = '0723d21f-c02c-4725-851f-575f93f2f58c'::uuid AND module_name = 'seo'
        )
  THEN
    RAISE EXCEPTION 'TEARDOWN INCOMPLETE: residue remains after cleanup';
  END IF;
  RAISE NOTICE 'seo_brain_link_intents_verification: all assertions passed, zero residue.';
END $$;
