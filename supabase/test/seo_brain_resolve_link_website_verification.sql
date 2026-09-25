-- =============================================================================
-- SEO Digi Brain, D-026A resolve_link_website min(uuid) fix, VERIFICATION
--   public.seo_brain_resolve_link_website (corrected)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER
-- 20260925120000_seo_brain_link_completion.sql and the corrective
-- 20260925130000_seo_brain_resolve_link_website_min_uuid_fix.sql.
--
-- SAFE EXECUTION (required), same convention as the sibling
-- seo_brain_link_intent_continue_verification.sql. Not transactional by
-- itself: wrap it so nothing can persist, whether it passes or fails:
--
--   ( echo 'BEGIN;'; cat supabase/test/seo_brain_resolve_link_website_verification.sql; echo 'ROLLBACK;' ) \
--     | psql "$TEST_DB_URL" -v ON_ERROR_STOP=1
--
-- Against a project where 20260925130000 is still UNAPPLIED, put the
-- corrective migration inside the same transaction:
--
--   ( echo 'BEGIN;'
--     cat supabase/migrations/20260925130000_seo_brain_resolve_link_website_min_uuid_fix.sql
--     cat supabase/test/seo_brain_resolve_link_website_verification.sql
--     echo 'ROLLBACK;' ) | psql "$TEST_DB_URL" -v ON_ERROR_STOP=1
--
-- Uses the shared TEST fixture users 'admin' (9830c4d7-...) and 'team_member'
-- (0723d21f-..., a.k.a. b1.nomem) already relied on by the sibling P1A
-- ownership-verification script and the Case D continuation script
-- respectively -- NOT 'owner' or 'client', both of which already carry
-- pre-existing active Brain actor mappings on this project (a Stage 2B
-- operator-bootstrap mapping for each, dated 2026-09-20/21) that this script
-- must not disturb. Confirmed free of any active mapping by this script's own
-- prerequisite check. Creates its own disposable actor mappings, link
-- intents, websites and (for the ambiguity/role-gating cases) workspaces, all
-- tagged 'RESOLVEVERIFY-%'; everything created is removed by its own
-- teardown at the end.
--
-- Proves (the corrected seo_brain_resolve_link_website, post min(uuid) fix):
--   1. the RPC executes without error on PostgreSQL, where a bare
--      min(uuid_column) does not exist as an aggregate;
--   2. exactly one existing, active website matching the intent's host, in a
--      workspace the caller owns/administers, is reused (not recreated);
--   3. a second workspace the caller also owns/administers, holding another
--      active website for the SAME host, makes resolution refuse as
--      'website_ambiguous' rather than guessing between them;
--   4. a caller with no owner/admin workspace at all still resolves, by
--      creating exactly one new workspace + website for the intent's host
--      (the zero-match path; min() over zero rows must yield NULL, not
--      error), unchanged;
--   5. the SAME caller in (4) is also a 'team_member' of the workspace that
--      holds the (4)/(admin's) matching website, never owner/admin there, so
--      it is not handed that existing website -- role gating is unchanged by
--      the fix.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Fixture ids (shared TEST users) + jwt login helper.
-- ---------------------------------------------------------------------------
SELECT set_config('rv.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('rv.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('rv.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('rv.web1',      'ab000000-0000-0000-0003-0000000000a1', false);
SELECT set_config('rv.ws2',       'ab000000-0000-0000-0003-0000000000b2', false);
SELECT set_config('rv.web2',      'ab000000-0000-0000-0003-0000000000b3', false);

CREATE OR REPLACE FUNCTION public._seo_rv_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $fn$;

-- ---------------------------------------------------------------------------
-- PREREQUISITES, ASSERTED BEFORE ANY MUTATION.
-- ---------------------------------------------------------------------------
DO $prereq$
BEGIN
  IF to_regprocedure('public.seo_brain_resolve_link_website(uuid)') IS NULL THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: seo_brain_resolve_link_website is not present.';
  END IF;

  IF NOT public.has_seo_module_access(current_setting('rv.admin')::uuid)
     OR NOT public.has_seo_module_access(current_setting('rv.team')::uuid) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: admin/team fixtures must already have active SEO module access.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.seo_brain_actor_links
             WHERE seo_user_id IN (current_setting('rv.admin')::uuid, current_setting('rv.team')::uuid)
               AND link_status = 'active') THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: admin/team must have no active Brain actor mapping; free fixtures required.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'RESOLVEVERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'RESOLVEVERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_workspaces WHERE name LIKE 'RESOLVEVERIFY-%')
     OR EXISTS (SELECT 1 FROM public.seo_websites WHERE id IN (current_setting('rv.web1')::uuid, current_setting('rv.web2')::uuid))
     OR EXISTS (SELECT 1 FROM public.seo_workspaces WHERE id = current_setting('rv.ws2')::uuid) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: fixtures from a previous run are still present.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.seo_workspace_members
                 WHERE workspace_id = current_setting('rv.workspace')::uuid
                   AND user_id = current_setting('rv.admin')::uuid
                   AND status = 'active' AND seo_role IN ('owner', 'admin')) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: admin fixture must be owner/admin of the seed workspace.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_workspace_members
                 WHERE workspace_id = current_setting('rv.workspace')::uuid
                   AND user_id = current_setting('rv.team')::uuid
                   AND status = 'active' AND seo_role = 'team_member') THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: team fixture must be a team_member (not owner/admin) of the seed workspace.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.seo_workspace_members
             WHERE user_id = current_setting('rv.team')::uuid
               AND status = 'active' AND seo_role IN ('owner', 'admin')) THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: team fixture must hold no owner/admin membership anywhere, for the zero-match case to be valid.';
  END IF;
END $prereq$;

-- ---------------------------------------------------------------------------
-- FIXTURES: actor mappings (case D preconditions) + the first disposable
-- website, reused across tests A/B/D.
-- ---------------------------------------------------------------------------
INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id, linked_by, link_method) VALUES
  ('RESOLVEVERIFY-actor-admin', current_setting('rv.admin')::uuid, current_setting('rv.admin')::uuid, 'brain_intent_confirmed'),
  ('RESOLVEVERIFY-actor-team',  current_setting('rv.team')::uuid,  current_setting('rv.team')::uuid,  'brain_intent_confirmed');

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('rv.web1')::uuid, current_setting('rv.workspace')::uuid,
        'https://resolveverify-1.example', 'ResolveVerify Disposable 1', 'ResolveVerify', 'other', 'pending', true);

-- ---------------------------------------------------------------------------
-- TEST A. Exactly one matching website, owner/admin membership -> reused.
-- Exercises the exact broken query (count(*), min(w.id), min(w.workspace_id))
-- against real UUID rows.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb; r jsonb; intent_id uuid;
BEGIN
  created := public.seo_brain_create_link_intent(
    'RESOLVEVERIFY-actor-admin', 'resolve-admin@example.test', 'RESOLVEVERIFY-biz-admin', 'resolveverify-1.example');
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  IF r->>'outcome' <> 'case_d_resolved' THEN RAISE EXCEPTION 'A setup: case D must resolve, got %', r; END IF;
  intent_id := (r->>'intentId')::uuid;
  PERFORM set_config('rv.intent_admin', intent_id::text, false);

  PERFORM public._seo_rv_login(current_setting('rv.admin')::uuid);
  r := public.seo_brain_resolve_link_website(intent_id);
  IF r->>'resolution' <> 'resolved' THEN RAISE EXCEPTION 'A: expected resolved, got %', r; END IF;
  IF (r->>'websiteId')::uuid <> current_setting('rv.web1')::uuid THEN
    RAISE EXCEPTION 'A: expected the existing website to be reused, got %', r;
  END IF;
  IF (r->>'workspaceId')::uuid <> current_setting('rv.workspace')::uuid THEN
    RAISE EXCEPTION 'A: expected the seed workspace, got %', r;
  END IF;
  IF NOT (r ? 'verified') THEN RAISE EXCEPTION 'A: response missing verified key, got %', r; END IF;
  RAISE NOTICE 'TEST A (single match reused) ok';
END $$;

-- ---------------------------------------------------------------------------
-- TEST B. A second workspace the SAME admin also administers, holding
-- another active website for the SAME host -> ambiguous, refuses.
-- Re-resolves the SAME still-redeemed intent (resolve_link_website does not
-- spend it; only authorize does), exercising min() with a 2-row group this
-- time, which must still be correctly treated as ambiguous by count(*), not
-- by whichever value min() happens to pick.
-- ---------------------------------------------------------------------------
-- trg_seo_workspaces_add_owner_member already inserts the owner's own
-- seo_workspace_members row on INSERT; no separate membership insert needed.
INSERT INTO public.seo_workspaces (id, name, owner_user_id, created_by)
VALUES (current_setting('rv.ws2')::uuid, 'RESOLVEVERIFY-ws2', current_setting('rv.admin')::uuid, current_setting('rv.admin')::uuid);
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('rv.web2')::uuid, current_setting('rv.ws2')::uuid,
        'https://resolveverify-1.example', 'ResolveVerify Disposable 2', 'ResolveVerify', 'other', 'pending', true);

DO $$
DECLARE r jsonb;
BEGIN
  PERFORM public._seo_rv_login(current_setting('rv.admin')::uuid);
  r := public.seo_brain_resolve_link_website(current_setting('rv.intent_admin')::uuid);
  IF r->>'resolution' <> 'website_ambiguous' THEN
    RAISE EXCEPTION 'B: expected website_ambiguous with two owner/admin-visible matches, got %', r;
  END IF;
  RAISE NOTICE 'TEST B (ambiguity refuses) ok';
END $$;

-- ---------------------------------------------------------------------------
-- TEST C/D (merged). Caller is a 'team_member' of the seed workspace holding
-- website #1 for this same host -- never owner/admin there -- and holds NO
-- owner/admin membership anywhere else either. Proves BOTH:
--   (4) zero-match creates exactly one new workspace + website (min() over a
--       genuinely empty owner/admin-membership group must yield NULL, not
--       error, before the INSERT path runs), and
--   (5) role gating is unchanged: the existing admin-owned website(s) for
--       this exact host are never handed to a non-owner/admin caller.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  created jsonb; r jsonb; intent_id uuid;
  v_ws uuid; v_web uuid;
BEGIN
  created := public.seo_brain_create_link_intent(
    'RESOLVEVERIFY-actor-team', 'resolve-team@example.test', 'RESOLVEVERIFY-biz-team',
    'resolveverify-1.example', 'RESOLVEVERIFY-team-ws');
  r := public.seo_brain_link_intent_redeem(created->>'launchCode', false);
  IF r->>'outcome' <> 'case_d_resolved' THEN RAISE EXCEPTION 'C/D setup: case D must resolve, got %', r; END IF;
  intent_id := (r->>'intentId')::uuid;

  PERFORM public._seo_rv_login(current_setting('rv.team')::uuid);
  r := public.seo_brain_resolve_link_website(intent_id);
  IF r->>'resolution' <> 'resolved' THEN RAISE EXCEPTION 'C/D: expected resolved (own new website), got %', r; END IF;
  v_ws  := (r->>'workspaceId')::uuid;
  v_web := (r->>'websiteId')::uuid;
  IF v_web IN (current_setting('rv.web1')::uuid, current_setting('rv.web2')::uuid) THEN
    RAISE EXCEPTION 'C/D: team_member must not be handed an existing owner/admin-only website, got %', r;
  END IF;
  IF v_ws IN (current_setting('rv.workspace')::uuid, current_setting('rv.ws2')::uuid) THEN
    RAISE EXCEPTION 'C/D: team_member must not be handed an existing owner/admin-only workspace, got %', r;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_workspaces WHERE id = v_ws AND name = 'RESOLVEVERIFY-team-ws'
                   AND owner_user_id = current_setting('rv.team')::uuid) THEN
    RAISE EXCEPTION 'C/D: expected a freshly created, team-owned workspace named RESOLVEVERIFY-team-ws';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_websites WHERE id = v_web AND workspace_id = v_ws
                   AND website_url = 'https://resolveverify-1.example') THEN
    RAISE EXCEPTION 'C/D: expected a freshly created website for the intent host in the new workspace';
  END IF;
  PERFORM set_config('rv.team_ws', v_ws::text, false);
  PERFORM set_config('rv.team_web', v_web::text, false);
  RAISE NOTICE 'TEST C/D (zero-match creates new + role gating unchanged) ok';
END $$;

-- ---------------------------------------------------------------------------
-- TEARDOWN. Removes every row this script created; disturbs nothing else.
-- seo_websites -> seo_ownership_verifications/events cascade; seo_workspaces
-- -> seo_workspace_members cascade.
-- ---------------------------------------------------------------------------
DELETE FROM public.seo_websites WHERE id IN (
  current_setting('rv.web1')::uuid, current_setting('rv.web2')::uuid, current_setting('rv.team_web')::uuid
);
DELETE FROM public.seo_workspaces WHERE id IN (
  current_setting('rv.ws2')::uuid, current_setting('rv.team_ws')::uuid
);
DELETE FROM public.seo_brain_link_intents WHERE brain_actor_id LIKE 'RESOLVEVERIFY-%';
DELETE FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'RESOLVEVERIFY-%';
DROP FUNCTION IF EXISTS public._seo_rv_login(uuid);

SELECT 'ALL PASS — seo_brain_resolve_link_website min(uuid) fix verification complete' AS result;
