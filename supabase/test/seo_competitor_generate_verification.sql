-- =============================================================================
-- SEO Competitor Benchmarking Stage 2A — GENERATION RPC — VERIFICATION
--   public.seo_competitor_generate(p_website_id uuid)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test, AFTER:
--   * 20260720123000_seo_competitors.sql            (Stage 1 table)
--   * 20260724120040_seo_competitor_generate.sql    (Stage 2A RPC)
--
-- Self-contained + self-seeding: creates its own disposable workspaces,
-- memberships, websites, onboarding, and audit fixtures (reusing the shared
-- UI-seed auth.users ids that already exist on TEST). The whole script runs as
-- ONE implicit transaction — ANY assertion failure aborts and rolls back every
-- fixture (net-nothing). On success, explicit teardown removes all fixtures and
-- a final net-nothing assertion proves zero residue.
--
-- Acting user is switched via request.jwt.claims; RLS-sensitive steps additionally
-- SET LOCAL ROLE authenticated / anon so grants + policies evaluate for real.
--
-- Proves: contract (SECURITY DEFINER, search_path, grants: authenticated EXECUTE,
-- anon/ PUBLIC denied, advisory lock present); authz matrix (owner/admin/
-- team_member allowed; client/anon/non-member/cross-tenant denied) with a single
-- non-leaking error (missing website == unauthorized); server-derived workspace/
-- actor/url/provenance/timestamps/generation_method; deterministic + idempotent
-- repeated generation; normalized-URL de-duplication + uniqueness; only
-- 'estimated' provenance; score bounds + required fields; audit-derived status;
-- replace-to-match stale-row removal; no effect on another website; no write
-- outside the resolved workspace; non-destructive empty-onboarding generation;
-- self-cleaning.
-- =============================================================================

-- Shared UI-seed auth.users (exist on TEST; same fixtures as the Stage 1 / P1a /
-- Reports scripts).
SELECT set_config('c2.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('c2.admin',  '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('c2.team',   '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('c2.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
-- A user that is a member of a DIFFERENT workspace (cross-tenant owner).
SELECT set_config('c2.cross',  '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);
-- A pure non-member: a synthetic id that belongs to no workspace (never inserts,
-- so no auth.users row is required).
SELECT set_config('c2.nonmem', 'c2000000-0000-0000-00ff-0000000000ff', false);

-- Disposable tenancy fixtures.
SELECT set_config('c2.ws_a',    'c2000000-0000-0000-0001-000000000001', false);  -- primary workspace
SELECT set_config('c2.ws_b',    'c2000000-0000-0000-0002-000000000002', false);  -- cross-tenant workspace
SELECT set_config('c2.site_a',  'c2000000-0000-0000-0003-000000000001', false);  -- generation target (ws_a)
SELECT set_config('c2.site_iso','c2000000-0000-0000-0004-000000000002', false);  -- isolation target (ws_a)
SELECT set_config('c2.site_b',  'c2000000-0000-0000-0005-000000000003', false);  -- cross-tenant website (ws_b)
SELECT set_config('c2.ghost',   'c2000000-0000-0000-0006-0000000000aa', false);  -- non-existent website (no-leak)

CREATE OR REPLACE FUNCTION public._c2_login(p uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF p IS NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub',p,'role','authenticated')::text, true);
  END IF;
END $fn$;

-- ---------- 0. CONTRACT (function shape + grants + advisory lock) ------------
DO $t$
DECLARE
  v_secdef boolean;
  v_cfg    text[];
  v_def    text;
BEGIN
  SELECT p.prosecdef, p.proconfig INTO v_secdef, v_cfg
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='seo_competitor_generate'
    AND pg_get_function_identity_arguments(p.oid)='p_website_id uuid';
  IF v_secdef IS NULL THEN RAISE EXCEPTION 'CONTRACT: seo_competitor_generate(uuid) missing'; END IF;
  IF NOT v_secdef THEN RAISE EXCEPTION 'CONTRACT: not SECURITY DEFINER'; END IF;
  IF v_cfg IS NULL OR NOT ('search_path=public' = ANY(v_cfg)) THEN
    RAISE EXCEPTION 'CONTRACT: search_path=public not set (got %)', v_cfg;
  END IF;

  -- Grants: authenticated may EXECUTE; anon may NOT.
  IF NOT has_function_privilege('authenticated', 'public.seo_competitor_generate(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT: authenticated lacks EXECUTE';
  END IF;
  IF has_function_privilege('anon', 'public.seo_competitor_generate(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT: anon must NOT have EXECUTE';
  END IF;

  -- Transaction-scoped advisory lock present (concurrency serialization).
  v_def := pg_get_functiondef('public.seo_competitor_generate(uuid)'::regprocedure);
  IF position('pg_advisory_xact_lock' IN v_def) = 0 THEN
    RAISE EXCEPTION 'CONTRACT: pg_advisory_xact_lock missing (no serialization)';
  END IF;
  IF position('estimated' IN v_def) = 0 THEN
    RAISE EXCEPTION 'CONTRACT: estimated provenance not written';
  END IF;
  RAISE NOTICE 'CONTRACT ok';
END $t$;

-- ---------- 1. SEED disposable tenancy (as postgres) ------------------------
-- Workspaces (owner membership auto-created by trigger).
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES (current_setting('c2.ws_a')::uuid, 'C2 WS A', current_setting('c2.owner')::uuid),
       (current_setting('c2.ws_b')::uuid, 'C2 WS B', current_setting('c2.cross')::uuid)
ON CONFLICT (id) DO NOTHING;

-- ws_a memberships: admin, team_member, client (owner already added by trigger).
INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES (current_setting('c2.ws_a')::uuid, current_setting('c2.admin')::uuid,  'admin',       'active'),
       (current_setting('c2.ws_a')::uuid, current_setting('c2.team')::uuid,   'team_member', 'active'),
       (current_setting('c2.ws_a')::uuid, current_setting('c2.client')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

-- Websites.
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('c2.site_a')::uuid,   current_setting('c2.ws_a')::uuid, 'https://c2-site-a.example',   'C2 A',   'C2 A',   'other', 'pending', true),
       (current_setting('c2.site_iso')::uuid, current_setting('c2.ws_a')::uuid, 'https://c2-site-iso.example', 'C2 ISO', 'C2 ISO', 'other', 'pending', true),
       (current_setting('c2.site_b')::uuid,   current_setting('c2.ws_b')::uuid, 'https://c2-site-b.example',   'C2 B',   'C2 B',   'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- Onboarding for site_a: competitor list with a duplicate normalized host to
-- prove de-duplication (alpha.com appears twice).
INSERT INTO public.seo_business_onboarding (website_id, website_url, workspace_id, competitors)
VALUES (current_setting('c2.site_a')::uuid, 'https://c2-site-a.example', current_setting('c2.ws_a')::uuid,
        ARRAY['https://www.alpha.com/', 'https://beta.io', 'https://www.alpha.com/pricing'])
ON CONFLICT (website_id) DO NOTHING;

-- Latest COMPLETED audit for site_a: known scores → our_overall = round(mean of
-- 8 dims) = round((80+70+65+60+50+50+73+72)/8) = round(520/8) = 65.
INSERT INTO public.seo_audit_runs (workspace_id, website_id, website_url, status,
  technical_health_score, onpage_score, authority_score, ai_discovery_score,
  is_latest, started_at, completed_at, created_by)
VALUES (current_setting('c2.ws_a')::uuid, current_setting('c2.site_a')::uuid, 'https://c2-site-a.example', 'completed',
        80, 70, 60, 50, true, now(), now(), current_setting('c2.owner')::uuid);

-- Pre-seed a STALE competitor row for site_a (gamma.net) that is NOT in the
-- onboarding list → replace-to-match must remove it.
INSERT INTO public.seo_competitors (workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url, overall_strength_score, generation_method, created_by)
VALUES (current_setting('c2.ws_a')::uuid, current_setting('c2.site_a')::uuid, 'https://c2-site-a.example', 'Gamma', 'https://gamma.net', 'gamma.net', 40, 'heuristic_v1', current_setting('c2.owner')::uuid);

-- Pre-seed an untouched competitor row for the isolation website (same ws_a).
INSERT INTO public.seo_competitors (workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url, overall_strength_score, generation_method, created_by)
VALUES (current_setting('c2.ws_a')::uuid, current_setting('c2.site_iso')::uuid, 'https://c2-site-iso.example', 'Isolated', 'https://isolated.com', 'isolated.com', 55, 'heuristic_v1', current_setting('c2.owner')::uuid);

-- Pre-seed an untouched competitor row for the cross-tenant website (ws_b).
INSERT INTO public.seo_competitors (workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url, overall_strength_score, generation_method, created_by)
VALUES (current_setting('c2.ws_b')::uuid, current_setting('c2.site_b')::uuid, 'https://c2-site-b.example', 'Foreign', 'https://foreign.com', 'foreign.com', 55, 'heuristic_v1', current_setting('c2.cross')::uuid);

-- ---------- 2. AUTHZ MATRIX (under the authenticated / anon roles) -----------
SET LOCAL ROLE authenticated;

-- 2a. owner ALLOWED → generates the canonical set (alpha.com, beta.io) = 2.
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._c2_login(current_setting('c2.owner')::uuid);
  n := public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  IF n <> 2 THEN RAISE EXCEPTION 'OWNER: expected 2 generated, got %', n; END IF;
  RAISE NOTICE 'owner allowed ok (n=2)';
END $t$;

-- 2b. admin ALLOWED (idempotent → still 2).
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._c2_login(current_setting('c2.admin')::uuid);
  n := public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  IF n <> 2 THEN RAISE EXCEPTION 'ADMIN: expected 2, got %', n; END IF;
  RAISE NOTICE 'admin allowed ok';
END $t$;

-- 2c. team_member ALLOWED.
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._c2_login(current_setting('c2.team')::uuid);
  n := public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  IF n <> 2 THEN RAISE EXCEPTION 'TEAM: expected 2, got %', n; END IF;
  RAISE NOTICE 'team_member allowed ok';
END $t$;

-- 2d. client DENIED with the generic non-leaking message.
DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._c2_login(current_setting('c2.client')::uuid);
  BEGIN
    PERFORM public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'CLIENT: client was allowed to generate'; END IF;
  IF msg <> 'Not authorized to generate competitor benchmarks for this website.' THEN
    RAISE EXCEPTION 'CLIENT: unexpected message: %', msg;
  END IF;
  PERFORM set_config('c2.msg_client', msg, false);
  RAISE NOTICE 'client denied ok';
END $t$;

-- 2e. pure non-member DENIED (same generic message).
DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._c2_login(current_setting('c2.nonmem')::uuid);
  BEGIN
    PERFORM public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'NONMEMBER: non-member was allowed'; END IF;
  IF msg <> current_setting('c2.msg_client') THEN
    RAISE EXCEPTION 'NONMEMBER: message differs from client (leak): %', msg;
  END IF;
  RAISE NOTICE 'non-member denied ok';
END $t$;

-- 2f. cross-tenant DENIED: c2.cross is OWNER of ws_b but not a member of ws_a.
DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._c2_login(current_setting('c2.cross')::uuid);
  BEGIN
    PERFORM public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'CROSS: cross-tenant owner was allowed'; END IF;
  IF msg <> current_setting('c2.msg_client') THEN
    RAISE EXCEPTION 'CROSS: message differs (leak): %', msg;
  END IF;
  RAISE NOTICE 'cross-tenant denied ok';
END $t$;

-- 2g. NO-LEAK: a missing website (as an authorized owner) yields the SAME
--     generic message as an authorization failure (existence never leaks).
DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._c2_login(current_setting('c2.owner')::uuid);
  BEGIN
    PERFORM public.seo_competitor_generate(current_setting('c2.ghost')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'NOLEAK: missing website did not error'; END IF;
  IF msg <> current_setting('c2.msg_client') THEN
    RAISE EXCEPTION 'NOLEAK: missing-website message differs (existence leak): %', msg;
  END IF;
  RAISE NOTICE 'no-leak (missing website == unauthorized) ok';
END $t$;

-- 2h. anon DENIED at the grant level (EXECUTE revoked).
RESET ROLE;
SET LOCAL ROLE anon;
DO $t$
DECLARE ok boolean := false;
BEGIN
  PERFORM public._c2_login(NULL);
  BEGIN
    PERFORM public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  EXCEPTION WHEN insufficient_privilege OR others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON: anon was able to execute the RPC'; END IF;
  RAISE NOTICE 'anon EXECUTE denial ok';
END $t$;
RESET ROLE;
SET LOCAL ROLE authenticated;

-- ---------- 3. SERVER-DERIVED FIELDS + BOUNDS + PROVENANCE ------------------
DO $t$
DECLARE r record; n int; v_expected text;
BEGIN
  PERFORM public._c2_login(current_setting('c2.owner')::uuid);

  -- exactly 2 rows (alpha.com + beta.io); the duplicate alpha normalized once.
  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'SET: expected 2 rows, got %', n; END IF;

  -- exactly the expected normalized set (uniqueness + de-dup).
  IF EXISTS (SELECT 1 FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid
             AND normalized_competitor_url NOT IN ('alpha.com','beta.io')) THEN
    RAISE EXCEPTION 'SET: unexpected normalized url present';
  END IF;
  IF (SELECT count(DISTINCT normalized_competitor_url) FROM public.seo_competitors
      WHERE website_id=current_setting('c2.site_a')::uuid) <> 2 THEN
    RAISE EXCEPTION 'SET: normalized urls not distinct/complete';
  END IF;

  -- per-row server-derived + bounds + provenance + required fields.
  FOR r IN SELECT * FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid LOOP
    IF r.workspace_id <> current_setting('c2.ws_a')::uuid THEN
      RAISE EXCEPTION 'DERIVE: workspace_id not server-derived (%).', r.workspace_id; END IF;
    IF r.website_url <> 'https://c2-site-a.example' THEN
      RAISE EXCEPTION 'DERIVE: website_url not the server snapshot (%).', r.website_url; END IF;
    IF r.created_by <> current_setting('c2.owner')::uuid THEN
      RAISE EXCEPTION 'DERIVE: created_by not the actor (%).', r.created_by; END IF;
    IF r.data_provenance <> 'estimated' THEN
      RAISE EXCEPTION 'PROVENANCE: row not estimated (%).', r.data_provenance; END IF;
    IF r.generation_method <> 'heuristic_v1' THEN
      RAISE EXCEPTION 'METHOD: generation_method not heuristic_v1 (%).', r.generation_method; END IF;
    IF r.created_at IS NULL OR r.updated_at IS NULL THEN
      RAISE EXCEPTION 'TS: server timestamps missing'; END IF;
    -- heuristic score bounds [35,90); all persisted scores within [0,100].
    IF r.content_strength_score  NOT BETWEEN 35 AND 89
    OR r.technical_health_score  NOT BETWEEN 35 AND 89
    OR r.authority_score         NOT BETWEEN 35 AND 89
    OR r.ai_visibility_score     NOT BETWEEN 35 AND 89
    OR r.review_strength_score   NOT BETWEEN 35 AND 89
    OR r.overall_strength_score  NOT BETWEEN 35 AND 89 THEN
      RAISE EXCEPTION 'BOUNDS: a heuristic score out of [35,89] for %', r.normalized_competitor_url; END IF;
    IF length(coalesce(r.competitor_name,'')) = 0 OR length(coalesce(r.suggested_next_action,'')) = 0 THEN
      RAISE EXCEPTION 'FIELDS: required text field empty for %', r.normalized_competitor_url; END IF;
    -- audit-derived status rule (our_overall = 65). CASE assigned to a variable
    -- first (a CASE inside an IF condition confuses the plpgsql IF/THEN parser).
    v_expected := CASE WHEN r.overall_strength_score - 65 > 5 THEN 'stronger'
                       WHEN r.overall_strength_score - 65 < -5 THEN 'weaker'
                       ELSE 'similar' END;
    IF r.status <> v_expected THEN
      RAISE EXCEPTION 'STATUS: audit-derived status mismatch for % (overall=%, status=%)',
        r.normalized_competitor_url, r.overall_strength_score, r.status; END IF;
  END LOOP;

  -- overall = round(mean of the 5 dimension scores).
  IF EXISTS (SELECT 1 FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid
             AND overall_strength_score <> round((content_strength_score+technical_health_score+authority_score
                 +ai_visibility_score+review_strength_score)::numeric/5)::int) THEN
    RAISE EXCEPTION 'OVERALL: overall_strength_score is not the mean of the 5 dimensions';
  END IF;

  -- ONLY 'estimated' provenance persisted anywhere in the generated set.
  IF EXISTS (SELECT 1 FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid
             AND data_provenance <> 'estimated') THEN
    RAISE EXCEPTION 'PROVENANCE: a non-estimated row persisted';
  END IF;
  RAISE NOTICE 'server-derived + bounds + provenance + status ok';
END $t$;

-- ---------- 4. REPLACE-TO-MATCH: stale row removed --------------------------
DO $t$
BEGIN
  IF EXISTS (SELECT 1 FROM public.seo_competitors
             WHERE website_id=current_setting('c2.site_a')::uuid AND normalized_competitor_url='gamma.net') THEN
    RAISE EXCEPTION 'STALE: gamma.net (not in onboarding) was not removed';
  END IF;
  RAISE NOTICE 'replace-to-match stale removal ok';
END $t$;

-- ---------- 5. DETERMINISM / IDEMPOTENCY under repeated calls ----------------
DO $t$
DECLARE sig1 text; sig2 text; n int;
BEGIN
  PERFORM public._c2_login(current_setting('c2.owner')::uuid);
  SELECT md5(string_agg(
      normalized_competitor_url||':'||content_strength_score||':'||technical_health_score||':'||
      authority_score||':'||ai_visibility_score||':'||review_strength_score||':'||
      overall_strength_score||':'||status, ',' ORDER BY normalized_competitor_url))
    INTO sig1
  FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid;

  -- regenerate twice more (owner + team) against unchanged inputs.
  PERFORM public.seo_competitor_generate(current_setting('c2.site_a')::uuid);
  PERFORM public._c2_login(current_setting('c2.team')::uuid);
  PERFORM public.seo_competitor_generate(current_setting('c2.site_a')::uuid);

  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'IDEMPOTENT: row count changed to %', n; END IF;

  SELECT md5(string_agg(
      normalized_competitor_url||':'||content_strength_score||':'||technical_health_score||':'||
      authority_score||':'||ai_visibility_score||':'||review_strength_score||':'||
      overall_strength_score||':'||status, ',' ORDER BY normalized_competitor_url))
    INTO sig2
  FROM public.seo_competitors WHERE website_id=current_setting('c2.site_a')::uuid;

  IF sig1 <> sig2 THEN RAISE EXCEPTION 'DETERMINISM: canonical scores/status changed across repeated generation'; END IF;
  RAISE NOTICE 'deterministic + idempotent repeated generation ok';
END $t$;

-- ---------- 6. ISOLATION: other website + other workspace untouched ---------
-- Checked as postgres (RLS-bypassing) so the TRUE cross-tenant state is observed
-- — under the authenticated owner role RLS would legitimately hide ws_b rows.
RESET ROLE;
DO $t$
DECLARE n int;
BEGIN
  -- site_iso (same ws_a) still has exactly its untouched row.
  SELECT count(*) INTO n FROM public.seo_competitors
    WHERE website_id=current_setting('c2.site_iso')::uuid AND normalized_competitor_url='isolated.com'
      AND overall_strength_score=55;
  IF n <> 1 THEN RAISE EXCEPTION 'ISO: other website in same workspace was modified'; END IF;

  -- ws_b website untouched; no row written outside ws_a.
  SELECT count(*) INTO n FROM public.seo_competitors WHERE workspace_id=current_setting('c2.ws_b')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'ISO: cross-tenant workspace rows changed (got %)', n; END IF;
  IF EXISTS (SELECT 1 FROM public.seo_competitors
             WHERE website_id=current_setting('c2.site_a')::uuid
               AND workspace_id <> current_setting('c2.ws_a')::uuid) THEN
    RAISE EXCEPTION 'ISO: a generated row is outside the resolved workspace';
  END IF;
  RAISE NOTICE 'isolation (other website + other workspace) ok';
END $t$;

-- ---------- 7. NON-DESTRUCTIVE empty onboarding -----------------------------
-- site_iso has NO onboarding competitor list → generate must return 0 and must
-- NOT wipe the pre-existing row (mirrors the mock's non-destructive early return).
SET LOCAL ROLE authenticated;
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._c2_login(current_setting('c2.owner')::uuid);
  n := public.seo_competitor_generate(current_setting('c2.site_iso')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'EMPTY: expected 0 for empty onboarding, got %', n; END IF;
  SELECT count(*) INTO n FROM public.seo_competitors
    WHERE website_id=current_setting('c2.site_iso')::uuid AND normalized_competitor_url='isolated.com';
  IF n <> 1 THEN RAISE EXCEPTION 'EMPTY: empty-onboarding generation wiped existing rows'; END IF;
  RAISE NOTICE 'non-destructive empty-onboarding generation ok';
END $t$;

RESET ROLE;

-- ---------- 8. TEARDOWN + net-nothing ---------------------------------------
DELETE FROM public.seo_competitors WHERE website_id IN (
  current_setting('c2.site_a')::uuid, current_setting('c2.site_iso')::uuid, current_setting('c2.site_b')::uuid);
DELETE FROM public.seo_audit_runs WHERE website_id = current_setting('c2.site_a')::uuid;
DELETE FROM public.seo_business_onboarding WHERE website_id = current_setting('c2.site_a')::uuid;
DELETE FROM public.seo_websites WHERE id IN (
  current_setting('c2.site_a')::uuid, current_setting('c2.site_iso')::uuid, current_setting('c2.site_b')::uuid);
DELETE FROM public.seo_workspace_members WHERE workspace_id IN (
  current_setting('c2.ws_a')::uuid, current_setting('c2.ws_b')::uuid);
DELETE FROM public.seo_workspaces WHERE id IN (
  current_setting('c2.ws_a')::uuid, current_setting('c2.ws_b')::uuid);
DROP FUNCTION IF EXISTS public._c2_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_competitors
    WHERE website_id IN (current_setting('c2.site_a')::uuid, current_setting('c2.site_iso')::uuid, current_setting('c2.site_b')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: % competitor fixtures remain', n; END IF;
  SELECT count(*) INTO n FROM public.seo_workspaces WHERE id IN (current_setting('c2.ws_a')::uuid, current_setting('c2.ws_b')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: % workspace fixtures remain', n; END IF;
  RAISE NOTICE 'TEARDOWN ok — net-nothing';
  RAISE NOTICE 'ALL COMPETITOR STAGE 2A CHECKS PASSED';
END $t$;

-- =============================================================================
-- CONCURRENCY — two-session verification guide (cannot be proven inside one SQL
-- transaction; the advisory lock is transaction-scoped, so two independent
-- sessions are required). Presence of pg_advisory_xact_lock is asserted in §0.
--
-- Session A (psql #1):
--   BEGIN;
--   -- seed a disposable ws/website/onboarding(with 1+ competitors) as above, or
--   -- reuse an existing owned website with onboarding competitors, then:
--   SELECT public.seo_competitor_generate('<website_id>');  -- acquires the lock
--   -- leave the transaction OPEN (do not COMMIT yet).
--
-- Session B (psql #2), concurrently:
--   BEGIN;
--   SELECT public.seo_competitor_generate('<same website_id>');  -- BLOCKS
--
-- Observe from a third session:
--   SELECT wait_event_type, wait_event, query FROM pg_stat_activity
--    WHERE query ILIKE '%seo_competitor_generate%';
--   -- Session B shows a Lock / advisory wait_event while A holds the lock.
--
-- Then COMMIT Session A → Session B unblocks, completes, and both converge to
-- the SAME canonical set (the UNIQUE(website_id, normalized_competitor_url) key
-- guarantees exactly one row per normalized competitor; no duplicates). COMMIT
-- B, then delete the disposable fixtures. Expected: no duplicate-key error, one
-- canonical row per competitor, net-nothing after cleanup.
-- =============================================================================
