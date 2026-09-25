-- =============================================================================
-- SEO Digi Brain, D-026A Case D continuation security fix, VERIFICATION
--   public.seo_brain_link_intent_continue_by_code (corrected)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on a local/fresh project or Digi_SEO_Test, AFTER
-- 20260921120000_seo_brain_link_intents.sql and the (corrected)
-- 20260925120000_seo_brain_link_completion.sql. NOT RUN as part of this PR;
-- see supabase/test/seo_brain_link_intents_verification.sql for the same
-- convention and the broader D-026A RPC surface (create_intent, redeem,
-- pending_by_code, finalize_case_a, authorize), which this file does not
-- repeat.
--
-- SAFE EXECUTION (required). Not transactional by itself: wrap it so nothing
-- can persist, whether it passes or fails:
--
--   ( echo 'BEGIN;'; cat supabase/test/seo_brain_link_intent_continue_verification.sql; echo 'ROLLBACK;' ) \
--     | psql "$TEST_DB_URL" -v ON_ERROR_STOP=1
--
-- Against a project where 20260925120000 is still UNAPPLIED (the state of
-- this PR), put the (corrected) migration inside the same transaction:
--
--   ( echo 'BEGIN;'
--     cat supabase/migrations/20260925120000_seo_brain_link_completion.sql
--     cat supabase/test/seo_brain_link_intent_continue_verification.sql
--     echo 'ROLLBACK;' ) | psql "$TEST_DB_URL" -v ON_ERROR_STOP=1
--
-- Self-contained and self-seeding: uses the same shared TEST fixture auth
-- user (b1.nomem) the sibling verification script depends on, confirmed
-- unmapped by its own prerequisite check, and creates its own disposable
-- actor mapping and link intents. Everything this script creates is removed
-- by its own teardown at the end; the wrapper above is the guarantee.
--
-- Proves (the corrected continue_by_code, post-review):
--   * a freshly redeemed case D intent can continue exactly once, and the
--     response carries the mapped user's own intentId/seoUserId/email;
--   * a second continuation attempt with the SAME launch code fails (NULL),
--     even though the underlying intent is still 'redeemed' and its
--     ~30 minute consent_expires_at has not elapsed;
--   * continuation after the short redemption_expires_at window has elapsed
--     fails (NULL), even though the intent is still 'redeemed', still
--     un-consumed, and its ~30 minute consent_expires_at has not elapsed;
--   * consent_expires_at itself (used later by resolve_link_website and
--     authorize) is untouched by any of the above: it is set at redemption
--     exactly as before, and remains valid on a row whose SHORT continuation
--     window has already closed, proving the two windows are independent;
--   * the atomic UPDATE...WHERE continuation_consumed_at IS NULL...RETURNING
--     claim is what a concurrent second attempt would also lose to: this is
--     exercised directly (a second call cannot observe or reuse the row the
--     first call already claimed);
--   * case A (pending_provisioning / pending_by_code) is untouched and still
--     works, since neither it nor its underlying columns were modified;
--   * case D's own completion (redeem -> continue) still produces a
--     'redeemed', 'case_d_existing_mapping' row with the mapped user, exactly
--     as before, so authorize's own downstream preconditions are unaffected.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PREREQUISITE, ASSERTED BEFORE ANY MUTATION.
-- ---------------------------------------------------------------------------
SELECT set_config('b1.nomem', '0723d21f-c02c-4725-851f-575f93f2f58c', false);

DO $prereq$
DECLARE
  v_v text := current_setting('b1.nomem', true);
BEGIN
  IF v_v IS NULL OR v_v !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: b1.nomem ("%") is not a valid auth.users UUID.', coalesce(v_v, '<unset>');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_v::uuid) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: the fixture auth user for b1.nomem (%) does not exist on this project.', v_v;
  END IF;
  IF (SELECT lower(btrim(email)) FROM auth.users WHERE id = v_v::uuid) IS NULL THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: b1.nomem has no email.';
  END IF;

  IF to_regprocedure('public.seo_brain_link_intent_continue_by_code(text)') IS NULL THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: 20260925120000_seo_brain_link_completion.sql is not applied.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'seo_brain_link_intents'
      AND column_name = 'continuation_consumed_at'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: continuation_consumed_at is absent; the corrected migration is not applied.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'LINKCONT-VERIFY-%'
  ) OR EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'LINKCONT-VERIFY-%'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: fixtures from a previous run are still present.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.seo_brain_actor_links WHERE seo_user_id = v_v::uuid AND link_status = 'active'
  ) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: b1.nomem already has an active actor mapping; this script needs one genuinely free fixture user.';
  END IF;
END $prereq$;

-- ---------------------------------------------------------------------------
-- FIXTURE. b1.nomem stands in for a customer already durably mapped through
-- the Brain-intent consent flow (link_method set), exactly the precondition
-- continue_by_code requires. Directly inserted rather than driven through
-- redeem/finalize_case_a: that creation path is already covered by
-- seo_brain_link_intents_verification.sql and is not what this fix changes.
-- ---------------------------------------------------------------------------
INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id, linked_by, link_method)
VALUES ('LINKCONT-VERIFY-actor-1', current_setting('b1.nomem')::uuid, current_setting('b1.nomem')::uuid, 'brain_intent_confirmed');

-- ---------------------------------------------------------------------------
-- 1 & 4 (partial). A freshly redeemed case D intent continues exactly once;
-- a second attempt with the same code fails; consent_expires_at is untouched.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb;
  code    text;
  r       jsonb;
  r2      jsonb;
  v_intent record;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKCONT-VERIFY-actor-1', 'continue-case@example.test', 'LINKCONT-VERIFY-biz-1', 'linkcont-verify.test');
  code := created->>'launchCode';

  r := public.seo_brain_link_intent_redeem(code, false);
  IF r->>'outcome' <> 'case_d_resolved' THEN RAISE EXCEPTION 'setup: case D must resolve, got %', r; END IF;
  IF (r->>'seoUserId')::uuid <> current_setting('b1.nomem')::uuid THEN
    RAISE EXCEPTION 'setup: case D must resolve to the mapped user, got %', r;
  END IF;

  SELECT * INTO v_intent FROM public.seo_brain_link_intents WHERE id = (r->>'intentId')::uuid;
  IF v_intent.consent_expires_at IS NULL THEN
    RAISE EXCEPTION 'setup: redemption must still set consent_expires_at, got NULL';
  END IF;

  -- 1. Fresh continuation succeeds, carrying the mapped user's identity.
  r2 := public.seo_brain_link_intent_continue_by_code(code);
  IF r2 IS NULL THEN RAISE EXCEPTION 'a freshly redeemed case D intent must continue once, got NULL'; END IF;
  IF (r2->>'seoUserId')::uuid <> current_setting('b1.nomem')::uuid
     OR (r2->>'intentId')::uuid <> v_intent.id
     OR r2->>'email' IS NULL THEN
    RAISE EXCEPTION 'continuation must return the mapped user''s own intentId/seoUserId/email, got %', r2;
  END IF;

  -- continuation_consumed_at is now stamped; status/outcome/consent window untouched.
  SELECT * INTO v_intent FROM public.seo_brain_link_intents WHERE id = v_intent.id;
  IF v_intent.continuation_consumed_at IS NULL THEN
    RAISE EXCEPTION 'a successful continuation must stamp continuation_consumed_at';
  END IF;
  IF v_intent.status <> 'redeemed' OR v_intent.redemption_outcome <> 'case_d_existing_mapping' THEN
    RAISE EXCEPTION 'continuation must not change status/redemption_outcome, got status=% outcome=%',
      v_intent.status, v_intent.redemption_outcome;
  END IF;
  IF v_intent.consent_expires_at IS NULL OR now() > v_intent.consent_expires_at THEN
    RAISE EXCEPTION 'consent_expires_at must remain valid and untouched by continuation, got %', v_intent.consent_expires_at;
  END IF;

  -- 2. Second attempt, same code, still well inside both windows: refused.
  -- This is the exact claim a concurrent second caller would also lose: the
  -- atomic UPDATE...WHERE continuation_consumed_at IS NULL has nothing left
  -- to claim, the same guarantee that protects two truly simultaneous calls.
  r2 := public.seo_brain_link_intent_continue_by_code(code);
  IF r2 IS NOT NULL THEN
    RAISE EXCEPTION 'a second continuation attempt with the same code must fail, got %', r2;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Continuation after the short redemption_expires_at window has elapsed
--    fails, even though status/consumed/consent_expires_at all still say
--    "eligible" by every OTHER measure. Fabricates elapsed time exactly like
--    seo_brain_link_intents_verification.sql's own expiry test.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb;
  code    text;
  r       jsonb;
  intent_id uuid;
  v_consent timestamptz;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKCONT-VERIFY-actor-1', 'continue-case-2@example.test', 'LINKCONT-VERIFY-biz-2', 'linkcont-verify.test');
  code := created->>'launchCode';

  r := public.seo_brain_link_intent_redeem(code, false);
  IF r->>'outcome' <> 'case_d_resolved' THEN RAISE EXCEPTION 'setup: case D must resolve, got %', r; END IF;
  intent_id := (r->>'intentId')::uuid;

  SELECT consent_expires_at INTO v_consent FROM public.seo_brain_link_intents WHERE id = intent_id;

  -- Simulate the short window having elapsed AFTER a successful redemption,
  -- without touching status, continuation_consumed_at or consent_expires_at.
  UPDATE public.seo_brain_link_intents
  SET redemption_expires_at = now() - interval '1 second'
  WHERE id = intent_id;

  r := public.seo_brain_link_intent_continue_by_code(code);
  IF r IS NOT NULL THEN
    RAISE EXCEPTION 'continuation after the short redemption window has elapsed must fail, got %', r;
  END IF;

  -- The intent remains otherwise eligible by every OTHER field: proves the
  -- refusal came from the short window specifically, not from something else,
  -- and that the 30 minute consent window is untouched and still valid.
  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_link_intents
    WHERE id = intent_id AND status = 'redeemed' AND continuation_consumed_at IS NULL
      AND consent_expires_at = v_consent AND now() <= consent_expires_at
  ) THEN
    RAISE EXCEPTION 'the intent must remain otherwise eligible and its consent window untouched after the short-window refusal';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Case A untouched: pending_provisioning / pending_by_code still work
--    exactly as before (neither function nor its columns were modified).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb;
  r jsonb;
  p jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKCONT-VERIFY-actor-a', 'continue-case-a@example.test', 'LINKCONT-VERIFY-biz-a', 'linkcont-verify.test');

  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  IF r->>'outcome' <> 'case_a_provisioning_required' THEN
    RAISE EXCEPTION 'case A must still reach case_a_provisioning_required, got %', r;
  END IF;

  p := public.seo_brain_link_intent_pending_by_code(created->>'launchCode');
  IF p->>'brainConfirmedEmail' <> 'continue-case-a@example.test' THEN
    RAISE EXCEPTION 'pending_by_code must still resolve a genuinely pending case A code, got %', p;
  END IF;

  -- A case A code is never eligible for case D continuation.
  IF public.seo_brain_link_intent_continue_by_code(created->>'launchCode') IS NOT NULL THEN
    RAISE EXCEPTION 'a pending_provisioning (case A) code must never continue as case D';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6. Case D completion still works: a fresh redeem -> continue pair produces
--    exactly the row shape seo_brain_link_authorize's own preconditions
--    depend on (unaffected by this fix, exercised for regression only).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb;
  code    text;
  r       jsonb;
  r2      jsonb;
BEGIN
  created := public.seo_brain_create_link_intent(
    'LINKCONT-VERIFY-actor-1', 'continue-case-3@example.test', 'LINKCONT-VERIFY-biz-3', 'linkcont-verify.test');
  code := created->>'launchCode';

  r := public.seo_brain_link_intent_redeem(code, false);
  IF r->>'outcome' <> 'case_d_resolved' THEN RAISE EXCEPTION 'case D redeem must still resolve, got %', r; END IF;

  r2 := public.seo_brain_link_intent_continue_by_code(code);
  IF r2 IS NULL THEN RAISE EXCEPTION 'case D continuation must still succeed once, got NULL'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.seo_brain_link_intents
    WHERE id = (r->>'intentId')::uuid
      AND status = 'redeemed'
      AND redeemed_seo_user_id = current_setting('b1.nomem')::uuid
      AND redemption_outcome = 'case_d_existing_mapping'
      AND consent_expires_at IS NOT NULL AND now() <= consent_expires_at
  ) THEN
    RAISE EXCEPTION 'a completed case D continuation must leave the row eligible for authorize, exactly as before';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 7. A launch code that was never case D (unknown / wrong outcome) and an
--    empty code are both refused, same as before.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF public.seo_brain_link_intent_continue_by_code('not-a-real-code') IS NOT NULL THEN
    RAISE EXCEPTION 'an unknown code must never continue';
  END IF;
  IF public.seo_brain_link_intent_continue_by_code('') IS NOT NULL THEN
    RAISE EXCEPTION 'an empty code must never continue';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- TEARDOWN. Removes every row this script created; disturbs nothing else.
-- ---------------------------------------------------------------------------
DELETE FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'LINKCONT-VERIFY-%';
DELETE FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'LINKCONT-VERIFY-%';
