-- =============================================================================
-- SEO Recommendation Generation Stage 1 — GENERATION RPC — VERIFICATION
--   public.seo_recommendation_generate(p_website_id uuid)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test, AFTER:
--   * 20260711120004_seo_stage2_audit.sql              (seo_audit_issues)
--   * 20260711120005_seo_stage2_recommendations.sql    (seo_recommendations)
--   * 20260714120029_seo_phase16g_publishing.sql       (source_issue_fingerprint)
--   * 20260724130000_seo_recommendation_generate.sql   (this stage's migration)
--
-- Self-contained + self-seeding: creates its own disposable workspaces,
-- memberships, websites, audit runs/issues, and pre-touched recommendation
-- fixtures (reusing the shared UI-seed auth.users ids already used by every
-- prior guarded-RPC verification script in this repo). The whole script runs
-- as ONE implicit transaction — ANY assertion failure aborts and rolls back
-- every fixture (net-nothing). On success, explicit teardown removes all
-- fixtures and a final net-nothing assertion proves zero residue.
--
-- Acting user is switched via request.jwt.claims; RLS-sensitive steps
-- additionally SET LOCAL ROLE authenticated / anon so grants + policies
-- evaluate for real.
--
-- Proves: contract (SECURITY DEFINER, search_path, SETOF return type, grants:
-- authenticated EXECUTE / anon+PUBLIC denied, advisory lock present); authz
-- matrix (owner/admin/team_member allowed; client/anon/non-member/
-- cross-tenant denied) with a single non-leaking error (missing website ==
-- unauthorized); category->area / fix_owner->action_type mapping for a
-- representative issue of each combination; only open/in_review issues
-- become candidates; issues without a source_issue_fingerprint are skipped;
-- on-page templates always generated with business-context interpolation;
-- idempotency (no-op regeneration leaves updated_at untouched); the
-- three-way replace-to-match (insert-new / supersede-changed-untouched /
-- leave-alone-changed-acted-on / retire-resolved-untouched /
-- leave-alone-resolved-acted-on) for BOTH issue-derived and on-page rows;
-- the two dedup unique indexes actually rejecting a manual duplicate; RPC
-- return value equals the canonical current set; isolation across
-- website/workspace; self-cleaning.
-- =============================================================================

SELECT set_config('r1.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('r1.admin',  '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('r1.team',   '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('r1.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('r1.cross',  '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);
SELECT set_config('r1.nonmem', 'a1900000-0000-0000-00ff-0000000000ff', false);

SELECT set_config('r1.ws_a',     'a1900000-0000-0000-0001-000000000001', false);
SELECT set_config('r1.ws_b',     'a1900000-0000-0000-0002-000000000002', false);
SELECT set_config('r1.site_a',   'a1900000-0000-0000-0003-000000000001', false);
SELECT set_config('r1.site_iso', 'a1900000-0000-0000-0004-000000000002', false);
SELECT set_config('r1.site_b',   'a1900000-0000-0000-0005-000000000003', false);
SELECT set_config('r1.ghost',    'a1900000-0000-0000-0006-0000000000aa', false);

CREATE OR REPLACE FUNCTION public._r1_login(p uuid) RETURNS void LANGUAGE plpgsql AS $fn$
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
  v_retset boolean;
  v_rettyp text;
BEGIN
  SELECT p.prosecdef, p.proconfig, p.proretset, format_type(p.prorettype, NULL)
    INTO v_secdef, v_cfg, v_retset, v_rettyp
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='seo_recommendation_generate'
    AND pg_get_function_identity_arguments(p.oid)='p_website_id uuid';
  IF v_secdef IS NULL THEN RAISE EXCEPTION 'CONTRACT: seo_recommendation_generate(uuid) missing'; END IF;
  IF NOT v_secdef THEN RAISE EXCEPTION 'CONTRACT: not SECURITY DEFINER'; END IF;
  IF v_cfg IS NULL OR NOT ('search_path=public' = ANY(v_cfg)) THEN
    RAISE EXCEPTION 'CONTRACT: search_path=public not set (got %)', v_cfg;
  END IF;
  IF NOT v_retset THEN RAISE EXCEPTION 'CONTRACT: not a SETOF-returning function'; END IF;
  IF v_rettyp <> 'seo_recommendations' THEN
    RAISE EXCEPTION 'CONTRACT: return type is % not seo_recommendations', v_rettyp;
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.seo_recommendation_generate(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT: authenticated lacks EXECUTE';
  END IF;
  IF has_function_privilege('anon', 'public.seo_recommendation_generate(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT: anon must NOT have EXECUTE';
  END IF;

  v_def := pg_get_functiondef('public.seo_recommendation_generate(uuid)'::regprocedure);
  IF position('pg_advisory_xact_lock' IN v_def) = 0 THEN
    RAISE EXCEPTION 'CONTRACT: pg_advisory_xact_lock missing (no serialization)';
  END IF;

  -- New additive columns + partial unique indexes present.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='seo_recommendations'
                   AND column_name='source_issue_fingerprint') THEN
    RAISE EXCEPTION 'CONTRACT: source_issue_fingerprint column missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='seo_recommendations'
                   AND column_name='generation_method') THEN
    RAISE EXCEPTION 'CONTRACT: generation_method column missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND indexname='uq_seo_recommendations_issue_fingerprint') THEN
    RAISE EXCEPTION 'CONTRACT: uq_seo_recommendations_issue_fingerprint index missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND indexname='uq_seo_recommendations_onpage_area') THEN
    RAISE EXCEPTION 'CONTRACT: uq_seo_recommendations_onpage_area index missing';
  END IF;
  RAISE NOTICE 'CONTRACT ok';
END $t$;

-- ---------- 1. SEED disposable tenancy (as postgres) -------------------------
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES (current_setting('r1.ws_a')::uuid, 'R1 WS A', current_setting('r1.owner')::uuid),
       (current_setting('r1.ws_b')::uuid, 'R1 WS B', current_setting('r1.cross')::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES (current_setting('r1.ws_a')::uuid, current_setting('r1.admin')::uuid,  'admin',       'active'),
       (current_setting('r1.ws_a')::uuid, current_setting('r1.team')::uuid,   'team_member', 'active'),
       (current_setting('r1.ws_a')::uuid, current_setting('r1.client')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, industry, target_location, website_type, setup_status, is_active)
VALUES (current_setting('r1.site_a')::uuid,   current_setting('r1.ws_a')::uuid, 'https://r1-site-a.example',   'R1 A',   'Acme Plumbing', 'Plumbing', 'Austin, TX', 'other', 'pending', true),
       (current_setting('r1.site_iso')::uuid, current_setting('r1.ws_a')::uuid, 'https://r1-site-iso.example', 'R1 ISO', 'R1 ISO Co',     NULL,       NULL,         'other', 'pending', true),
       (current_setting('r1.site_b')::uuid,   current_setting('r1.ws_b')::uuid, 'https://r1-site-b.example',   'R1 B',   'R1 B Co',       NULL,       NULL,         'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- Run 1 (completed) for site_a with a representative issue mix.
INSERT INTO public.seo_audit_runs (id, workspace_id, website_id, website_url, status,
  technical_health_score, onpage_score, authority_score, ai_discovery_score,
  is_latest, started_at, completed_at, created_by)
VALUES ('a1900000-0000-0000-0007-000000000001'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', 'completed',
        70, 65, 60, 55, true, now() - interval '2 days', now() - interval '2 days', current_setting('r1.owner')::uuid);
SELECT set_config('r1.run1', 'a1900000-0000-0000-0007-000000000001', false);

-- iss_schema: category=schema, fix_owner=system_suggestion, status=open -> candidate.
-- iss_dup:    category=duplicate_content, fix_owner=client_action, status=in_review -> candidate.
-- iss_can:    category=canonical, fix_owner=developer_needed, status=open -> candidate (resolved in run2).
-- iss_sit:    category=sitemap, fix_owner=system_suggestion, status=open -> candidate (acted on before run2).
-- iss_rob:    category=robots_txt, fix_owner=digibility_expert, status=fixed -> EXCLUDED (status).
-- iss_speed:  category=speed, fix_owner=system_suggestion, status=open, fingerprint NULL -> EXCLUDED (no fingerprint).
INSERT INTO public.seo_audit_issues (
  id, workspace_id, website_id, website_url, audit_run_id, category, severity, title,
  simple_explanation, why_it_matters, technical_explanation, affected_page_url,
  impact, effort, risk, confidence_percentage, fix_owner, suggested_next_action, status,
  source, source_issue_fingerprint
) VALUES
  ('a1900000-0000-0000-0008-000000000001'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run1')::uuid,
   'schema', 'medium', 'Missing LocalBusiness schema', 'x', 'Helps rich results', 'x', 'https://r1-site-a.example/',
   'medium', 'low', 'low', 80, 'system_suggestion', 'Add LocalBusiness schema markup.', 'open',
   'crawler', 'SCH001::fp-v1'),
  ('a1900000-0000-0000-0008-000000000002'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run1')::uuid,
   'duplicate_content', 'high', 'Duplicate service page content', 'x', 'Confuses search engines', 'x', 'https://r1-site-a.example/services',
   'high', 'medium', 'low', 75, 'client_action', 'Rewrite duplicate service page copy.', 'in_review',
   'crawler', 'DUP001::fp-v1'),
  ('a1900000-0000-0000-0008-000000000003'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run1')::uuid,
   'canonical', 'medium', 'Missing canonical tag', 'x', 'Prevents duplicate indexing', 'x', 'https://r1-site-a.example/blog',
   'medium', 'low', 'medium', 78, 'developer_needed', 'Add a canonical tag to the blog page.', 'open',
   'crawler', 'CAN001::fp-v1'),
  ('a1900000-0000-0000-0008-000000000004'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run1')::uuid,
   'sitemap', 'low', 'Sitemap missing new pages', 'x', 'Slower discovery of new pages', 'x', 'https://r1-site-a.example/sitemap.xml',
   'low', 'low', 'low', 82, 'system_suggestion', 'Regenerate and resubmit the sitemap.', 'open',
   'crawler', 'SIT001::fp-v1'),
  ('a1900000-0000-0000-0008-000000000005'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run1')::uuid,
   'robots_txt', 'high', 'robots.txt blocks services', 'x', 'Blocks indexing', 'x', 'https://r1-site-a.example/robots.txt',
   'high', 'low', 'high', 90, 'digibility_expert', 'Remove the disallow rule.', 'fixed',
   'crawler', 'ROB001::fp-v1'),
  ('a1900000-0000-0000-0008-000000000006'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run1')::uuid,
   'speed', 'medium', 'Slow largest contentful paint', 'x', 'Hurts rankings and UX', 'x', 'https://r1-site-a.example/',
   'medium', 'medium', 'low', 65, 'system_suggestion', 'Optimize hero image and defer scripts.', 'open',
   NULL, NULL);

-- ---------- 2. AUTHZ MATRIX (under the authenticated / anon roles) -----------
SET LOCAL ROLE authenticated;

DO $t$
DECLARE n int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  -- 4 issue-derived (schema, dup, can, sit) + 7 on-page = 11.
  IF n <> 11 THEN RAISE EXCEPTION 'OWNER: expected 11 generated, got %', n; END IF;
  RAISE NOTICE 'owner allowed ok (n=11)';
END $t$;

DO $t$
DECLARE n int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.admin')::uuid);
  SELECT count(*) INTO n FROM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  IF n <> 11 THEN RAISE EXCEPTION 'ADMIN: expected 11 (idempotent), got %', n; END IF;
  RAISE NOTICE 'admin allowed ok';
END $t$;

DO $t$
DECLARE n int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.team')::uuid);
  SELECT count(*) INTO n FROM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  IF n <> 11 THEN RAISE EXCEPTION 'TEAM: expected 11, got %', n; END IF;
  RAISE NOTICE 'team_member allowed ok';
END $t$;

DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._r1_login(current_setting('r1.client')::uuid);
  BEGIN
    PERFORM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'CLIENT: client was allowed to generate'; END IF;
  IF msg <> 'Not authorized to generate recommendations for this website.' THEN
    RAISE EXCEPTION 'CLIENT: unexpected message: %', msg;
  END IF;
  PERFORM set_config('r1.msg_denied', msg, false);
  RAISE NOTICE 'client denied ok';
END $t$;

DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._r1_login(current_setting('r1.nonmem')::uuid);
  BEGIN
    PERFORM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'NONMEMBER: non-member was allowed'; END IF;
  IF msg <> current_setting('r1.msg_denied') THEN
    RAISE EXCEPTION 'NONMEMBER: message differs from client (leak): %', msg;
  END IF;
  RAISE NOTICE 'non-member denied ok';
END $t$;

DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._r1_login(current_setting('r1.cross')::uuid);
  BEGIN
    PERFORM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'CROSS: cross-tenant owner was allowed'; END IF;
  IF msg <> current_setting('r1.msg_denied') THEN
    RAISE EXCEPTION 'CROSS: message differs (leak): %', msg;
  END IF;
  RAISE NOTICE 'cross-tenant denied ok';
END $t$;

DO $t$
DECLARE msg text; ok boolean := false;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);
  BEGIN
    PERFORM public.seo_recommendation_generate(current_setting('r1.ghost')::uuid);
  EXCEPTION WHEN others THEN ok := true; msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'NOLEAK: missing website did not error'; END IF;
  IF msg <> current_setting('r1.msg_denied') THEN
    RAISE EXCEPTION 'NOLEAK: missing-website message differs (existence leak): %', msg;
  END IF;
  RAISE NOTICE 'no-leak (missing website == unauthorized) ok';
END $t$;

RESET ROLE;
SET LOCAL ROLE anon;
DO $t$
DECLARE ok boolean := false;
BEGIN
  PERFORM public._r1_login(NULL);
  BEGIN
    PERFORM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  EXCEPTION WHEN insufficient_privilege OR others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ANON: anon was able to execute the RPC'; END IF;
  RAISE NOTICE 'anon EXECUTE denial ok';
END $t$;
RESET ROLE;
SET LOCAL ROLE authenticated;

-- ---------- 3. MAPPING + FIELDS + ELIGIBILITY --------------------------------
DO $t$
DECLARE r record; n int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);

  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current
    AND source_issue_fingerprint='SCH001::fp-v1';
  IF NOT FOUND OR r.area <> 'schema' OR r.action_type <> 'auto_suggest' THEN
    RAISE EXCEPTION 'MAP: schema/system_suggestion mismatch (area=%, action_type=%)', r.area, r.action_type;
  END IF;

  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current
    AND source_issue_fingerprint='DUP001::fp-v1';
  IF NOT FOUND OR r.area <> 'content' OR r.action_type <> 'manual_support' THEN
    RAISE EXCEPTION 'MAP: duplicate_content/client_action mismatch (area=%, action_type=%)', r.area, r.action_type;
  END IF;

  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current
    AND source_issue_fingerprint='CAN001::fp-v1';
  IF NOT FOUND OR r.area <> 'technical' OR r.action_type <> 'approval_required' THEN
    RAISE EXCEPTION 'MAP: canonical/developer_needed mismatch (area=%, action_type=%)', r.area, r.action_type;
  END IF;

  -- fixed-status issue never produced a recommendation.
  SELECT count(*) INTO n FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND source_issue_fingerprint='ROB001::fp-v1';
  IF n <> 0 THEN RAISE EXCEPTION 'ELIGIBILITY: fixed-status issue produced a recommendation'; END IF;

  -- no-fingerprint issue never produced a recommendation.
  SELECT count(*) INTO n FROM public.seo_recommendations r2
  WHERE r2.website_id=current_setting('r1.site_a')::uuid AND r2.issue_id='a1900000-0000-0000-0008-000000000006'::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ELIGIBILITY: no-fingerprint issue produced a recommendation'; END IF;

  -- server-derived fields + provenance on an issue-derived row.
  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='SCH001::fp-v1';
  IF r.workspace_id <> current_setting('r1.ws_a')::uuid THEN RAISE EXCEPTION 'DERIVE: workspace_id not server-derived'; END IF;
  IF r.website_url <> 'https://r1-site-a.example' THEN RAISE EXCEPTION 'DERIVE: website_url not server snapshot'; END IF;
  IF r.created_by <> current_setting('r1.owner')::uuid THEN RAISE EXCEPTION 'DERIVE: created_by not the actor'; END IF;
  IF r.generation_method <> 'rule_based_v1' THEN RAISE EXCEPTION 'METHOD: generation_method not rule_based_v1 (%)', r.generation_method; END IF;
  IF r.status <> 'suggested' THEN RAISE EXCEPTION 'STATUS: new recommendation not suggested (%)', r.status; END IF;

  -- on-page templates: all 7 areas present with issue_id NULL, business-context interpolated.
  SELECT count(*) INTO n FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND issue_id IS NULL;
  IF n <> 7 THEN RAISE EXCEPTION 'ONPAGE: expected 7 on-page rows, got %', n; END IF;

  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND issue_id IS NULL AND area='title';
  IF r.suggested_change <> 'Acme Plumbing - Plumbing in Austin, TX' THEN
    RAISE EXCEPTION 'ONPAGE: title interpolation mismatch (%)', r.suggested_change;
  END IF;
  RAISE NOTICE 'mapping + fields + eligibility + on-page interpolation ok';
END $t$;

-- ---------- 4. RPC RETURN VALUE == canonical current set ---------------------
DO $t$
DECLARE n_returned int; n_table int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);
  CREATE TEMP TABLE tmp_r1_returned AS
    SELECT * FROM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);
  SELECT count(*) INTO n_returned FROM tmp_r1_returned;
  SELECT count(*) INTO n_table FROM public.seo_recommendations
    WHERE website_id=current_setting('r1.site_a')::uuid AND is_current;
  IF n_returned <> n_table THEN
    RAISE EXCEPTION 'RETURN: returned % rows but table has % current rows', n_returned, n_table;
  END IF;
  IF EXISTS (SELECT id FROM tmp_r1_returned EXCEPT SELECT id FROM public.seo_recommendations WHERE is_current) THEN
    RAISE EXCEPTION 'RETURN: a returned row is not a current row in the table';
  END IF;
  DROP TABLE tmp_r1_returned;
  RAISE NOTICE 'RPC return value equals canonical current set ok';
END $t$;

-- ---------- 5. IDEMPOTENCY: no-op regeneration leaves updated_at untouched ---
DO $t$
DECLARE v_before timestamptz; v_after timestamptz; n int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);
  SELECT updated_at INTO v_before FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='DUP001::fp-v1';

  PERFORM pg_sleep(1);
  PERFORM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);

  SELECT updated_at INTO v_after FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='DUP001::fp-v1';
  IF v_after <> v_before THEN
    RAISE EXCEPTION 'IDEMPOTENT: unchanged content was written (updated_at moved)';
  END IF;

  SELECT count(*) INTO n FROM public.seo_recommendations WHERE website_id=current_setting('r1.site_a')::uuid AND is_current;
  IF n <> 11 THEN RAISE EXCEPTION 'IDEMPOTENT: current row count changed to %', n; END IF;
  RAISE NOTICE 'idempotency (no write on unchanged regeneration) ok';
END $t$;

-- ---------- 6. REGENERATION-SAFETY setup: touch two recommendations ---------
-- sit rec (issue-derived) and title rec (on-page) are marked as human-acted
-- (approved / ready_to_publish) BEFORE run2 exists, simulating operator action
-- between crawls. Direct UPDATE as postgres (bypasses RLS; equivalent to what
-- seo_approval_transition would do in the real approval workflow).
RESET ROLE;
UPDATE public.seo_recommendations
  SET status='approved', updated_at=now()
WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='SIT001::fp-v1';

UPDATE public.seo_recommendations
  SET status='ready_to_publish', updated_at=now()
WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND issue_id IS NULL AND area='title';

SELECT set_config('r1.sit_rec_id', (SELECT id::text FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='SIT001::fp-v1'), false);
SELECT set_config('r1.title_rec_id', (SELECT id::text FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND issue_id IS NULL AND area='title'), false);

-- Run 2 (completed, later than run1): schema issue's content changes (still
-- suggested -> supersede); duplicate_content issue unchanged (no write);
-- canonical issue is resolved (omitted entirely -> retire, was suggested);
-- sitemap issue is also resolved (omitted -> already approved -> must NOT
-- be retired). Business context changes too (affects on-page templates).
UPDATE public.seo_audit_runs SET is_latest = false
WHERE id = current_setting('r1.run1')::uuid;

INSERT INTO public.seo_audit_runs (id, workspace_id, website_id, website_url, status,
  technical_health_score, onpage_score, authority_score, ai_discovery_score,
  is_latest, started_at, completed_at, created_by)
VALUES ('a1900000-0000-0000-0007-000000000002'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', 'completed',
        75, 68, 62, 58, true, now() - interval '1 hour', now() - interval '1 hour', current_setting('r1.owner')::uuid);
SELECT set_config('r1.run2', 'a1900000-0000-0000-0007-000000000002', false);

INSERT INTO public.seo_audit_issues (
  id, workspace_id, website_id, website_url, audit_run_id, category, severity, title,
  simple_explanation, why_it_matters, technical_explanation, affected_page_url,
  impact, effort, risk, confidence_percentage, fix_owner, suggested_next_action, status,
  source, source_issue_fingerprint
) VALUES
  ('a1900000-0000-0000-0008-000000000011'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run2')::uuid,
   'schema', 'medium', 'Missing LocalBusiness AND Review schema', 'x', 'Helps rich results', 'x', 'https://r1-site-a.example/',
   'medium', 'low', 'low', 80, 'system_suggestion', 'Add LocalBusiness + Review schema markup.', 'open',
   'crawler', 'SCH001::fp-v1'),
  ('a1900000-0000-0000-0008-000000000012'::uuid, current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example', current_setting('r1.run2')::uuid,
   'duplicate_content', 'high', 'Duplicate service page content', 'x', 'Confuses search engines', 'x', 'https://r1-site-a.example/services',
   'high', 'medium', 'low', 75, 'client_action', 'Rewrite duplicate service page copy.', 'in_review',
   'crawler', 'DUP001::fp-v1');
-- CAN001 and SIT001 intentionally NOT re-published in run2 (resolved / no longer detected).

UPDATE public.seo_websites SET business_name = 'Acme Plumbing & Drain'
WHERE id = current_setting('r1.site_a')::uuid;

-- ---------- 7. REGENERATE against run2 and verify the full matrix -----------
SET LOCAL ROLE authenticated;
DO $t$
DECLARE r record; n int; v_old_id uuid;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);
  PERFORM public.seo_recommendation_generate(current_setting('r1.site_a')::uuid);

  -- 7a. schema: changed + untouched(suggested) -> superseded; a NEW current
  --     row exists with the updated content, old row retired with superseded_by set.
  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='SCH001::fp-v1';
  IF NOT FOUND THEN RAISE EXCEPTION 'SUPERSEDE: no current schema recommendation after change'; END IF;
  IF r.title <> 'Missing LocalBusiness AND Review schema' THEN
    RAISE EXCEPTION 'SUPERSEDE: schema recommendation content not updated (%)', r.title;
  END IF;
  IF r.status <> 'suggested' THEN RAISE EXCEPTION 'SUPERSEDE: new schema row not suggested (%)', r.status; END IF;
  SELECT id INTO v_old_id FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND source_issue_fingerprint='SCH001::fp-v1' AND NOT is_current;
  IF v_old_id IS NULL THEN RAISE EXCEPTION 'SUPERSEDE: old schema row not found / still current'; END IF;
  IF (SELECT superseded_by FROM public.seo_recommendations WHERE id=v_old_id) <> r.id THEN
    RAISE EXCEPTION 'SUPERSEDE: old schema row superseded_by does not point at the new row';
  END IF;

  -- 7b. duplicate_content: unchanged -> same row id, still current, still in_review-mapped suggested.
  SELECT count(*) INTO n FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND source_issue_fingerprint='DUP001::fp-v1';
  IF n <> 1 THEN RAISE EXCEPTION 'NOWRITE: expected exactly 1 current duplicate_content row, got %', n; END IF;
  SELECT count(*) INTO n FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND source_issue_fingerprint='DUP001::fp-v1';
  IF n <> 1 THEN RAISE EXCEPTION 'NOWRITE: a second (superseded) duplicate_content row was created (%)', n; END IF;

  -- 7c. canonical: resolved + untouched(suggested) -> retired, superseded_by NULL.
  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND source_issue_fingerprint='CAN001::fp-v1';
  IF r.is_current THEN RAISE EXCEPTION 'RETIRE: resolved canonical recommendation still current'; END IF;
  IF r.superseded_by IS NOT NULL THEN RAISE EXCEPTION 'RETIRE: retired row unexpectedly has superseded_by set'; END IF;

  -- 7d. sitemap: resolved but ALREADY APPROVED -> must remain untouched (still current, still approved).
  SELECT * INTO r FROM public.seo_recommendations WHERE id = current_setting('r1.sit_rec_id')::uuid;
  IF NOT r.is_current THEN RAISE EXCEPTION 'PRESERVE: approved sitemap recommendation was retired despite human action'; END IF;
  IF r.status <> 'approved' THEN RAISE EXCEPTION 'PRESERVE: approved sitemap recommendation status changed to %', r.status; END IF;
  IF r.superseded_by IS NOT NULL THEN RAISE EXCEPTION 'PRESERVE: approved sitemap recommendation was superseded'; END IF;

  -- 7e. title (on-page): content changed (business_name changed) but ALREADY
  --     ready_to_publish -> left completely untouched, no new title row inserted.
  SELECT * INTO r FROM public.seo_recommendations WHERE id = current_setting('r1.title_rec_id')::uuid;
  IF NOT r.is_current THEN RAISE EXCEPTION 'PRESERVE: ready_to_publish title recommendation was superseded'; END IF;
  IF r.status <> 'ready_to_publish' THEN RAISE EXCEPTION 'PRESERVE: title recommendation status changed to %', r.status; END IF;
  IF r.suggested_change = 'Acme Plumbing & Drain - Plumbing in Austin, TX' THEN
    RAISE EXCEPTION 'PRESERVE: title recommendation content was silently overwritten';
  END IF;
  SELECT count(*) INTO n FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND issue_id IS NULL AND area='title';
  IF n <> 1 THEN RAISE EXCEPTION 'PRESERVE: a second current title row was inserted alongside the untouched one (%)', n; END IF;

  -- 7f. meta_description / h1 (on-page, still suggested): content changed
  --     (business_name changed) -> superseded with new interpolated content.
  SELECT * INTO r FROM public.seo_recommendations
  WHERE website_id=current_setting('r1.site_a')::uuid AND is_current AND issue_id IS NULL AND area='h1';
  IF r.suggested_change <> 'Acme Plumbing & Drain — Serving Austin, TX' THEN
    RAISE EXCEPTION 'ONPAGE-SUPERSEDE: h1 content not updated (%)', r.suggested_change;
  END IF;
  IF r.status <> 'suggested' THEN RAISE EXCEPTION 'ONPAGE-SUPERSEDE: new h1 row not suggested (%)', r.status; END IF;

  RAISE NOTICE 'regeneration-safety full matrix (supersede/no-write/retire/preserve x2) ok';
END $t$;

-- ---------- 8. DEDUP INDEX ENFORCEMENT (manual duplicate attempt) -----------
RESET ROLE;
DO $t$
DECLARE ok boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.seo_recommendations (
      workspace_id, website_id, website_url, area, title, suggested_change, why_it_helps,
      action_type, impact, effort, risk, is_current, source_issue_fingerprint
    ) VALUES (
      current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example',
      'technical', 'dup attempt', 'x', 'x', 'auto_suggest', 'low', 'low', 'low', true, 'DUP001::fp-v1'
    );
  EXCEPTION WHEN unique_violation THEN ok := true;
  END;
  IF NOT ok THEN RAISE EXCEPTION 'INDEX: duplicate current source_issue_fingerprint was NOT rejected'; END IF;

  ok := false;
  BEGIN
    INSERT INTO public.seo_recommendations (
      workspace_id, website_id, website_url, area, title, suggested_change, why_it_helps,
      action_type, impact, effort, risk, is_current
    ) VALUES (
      current_setting('r1.ws_a')::uuid, current_setting('r1.site_a')::uuid, 'https://r1-site-a.example',
      'h1', 'dup onpage attempt', 'x', 'x', 'auto_suggest', 'low', 'low', 'low', true
    );
  EXCEPTION WHEN unique_violation THEN ok := true;
  END;
  IF NOT ok THEN RAISE EXCEPTION 'INDEX: duplicate current on-page area was NOT rejected'; END IF;
  RAISE NOTICE 'dedup index enforcement ok';
END $t$;

-- ---------- 9. ISOLATION: other website + other workspace untouched ---------
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_recommendations WHERE website_id=current_setting('r1.site_iso')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: isolation website unexpectedly has recommendations'; END IF;
  SELECT count(*) INTO n FROM public.seo_recommendations WHERE workspace_id=current_setting('r1.ws_b')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: cross-tenant workspace unexpectedly has recommendations'; END IF;
  IF EXISTS (SELECT 1 FROM public.seo_recommendations
             WHERE website_id=current_setting('r1.site_a')::uuid AND workspace_id <> current_setting('r1.ws_a')::uuid) THEN
    RAISE EXCEPTION 'ISO: a generated row is outside the resolved workspace';
  END IF;
  RAISE NOTICE 'isolation (other website + other workspace) ok';
END $t$;

-- ---------- 10. NON-DESTRUCTIVE: no completed audit run ----------------------
-- site_iso has no audit runs at all -> on-page templates still generate (7),
-- zero issue-derived rows, no error.
SET LOCAL ROLE authenticated;
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._r1_login(current_setting('r1.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_recommendation_generate(current_setting('r1.site_iso')::uuid);
  IF n <> 7 THEN RAISE EXCEPTION 'NOAUDIT: expected 7 on-page-only rows for an audit-less website, got %', n; END IF;
  RAISE NOTICE 'no-completed-audit generation (on-page only, non-destructive) ok';
END $t$;

RESET ROLE;

-- ---------- 11. TEARDOWN + net-nothing ---------------------------------------
DELETE FROM public.seo_recommendations WHERE website_id IN (
  current_setting('r1.site_a')::uuid, current_setting('r1.site_iso')::uuid, current_setting('r1.site_b')::uuid);
DELETE FROM public.seo_audit_issues WHERE website_id = current_setting('r1.site_a')::uuid;
DELETE FROM public.seo_audit_runs WHERE website_id = current_setting('r1.site_a')::uuid;
DELETE FROM public.seo_websites WHERE id IN (
  current_setting('r1.site_a')::uuid, current_setting('r1.site_iso')::uuid, current_setting('r1.site_b')::uuid);
DELETE FROM public.seo_workspace_members WHERE workspace_id IN (
  current_setting('r1.ws_a')::uuid, current_setting('r1.ws_b')::uuid);
DELETE FROM public.seo_workspaces WHERE id IN (
  current_setting('r1.ws_a')::uuid, current_setting('r1.ws_b')::uuid);
DROP FUNCTION IF EXISTS public._r1_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_recommendations
    WHERE website_id IN (current_setting('r1.site_a')::uuid, current_setting('r1.site_iso')::uuid, current_setting('r1.site_b')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: % recommendation fixtures remain', n; END IF;
  SELECT count(*) INTO n FROM public.seo_workspaces WHERE id IN (current_setting('r1.ws_a')::uuid, current_setting('r1.ws_b')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: % workspace fixtures remain', n; END IF;
  RAISE NOTICE 'TEARDOWN ok — net-nothing';
  RAISE NOTICE 'ALL RECOMMENDATION GENERATION STAGE 1 CHECKS PASSED';
END $t$;

-- =============================================================================
-- CONCURRENCY — two-session verification guide (cannot be proven inside one SQL
-- transaction; the advisory lock is transaction-scoped, so two independent
-- sessions are required). Presence of pg_advisory_xact_lock is asserted in §0.
--
-- Session A (psql #1):
--   BEGIN;
--   -- seed a disposable ws/website/completed-audit-run/issue as above, or
--   -- reuse an existing owned website with a completed audit, then:
--   SELECT * FROM public.seo_recommendation_generate('<website_id>');  -- acquires the lock
--   -- leave the transaction OPEN (do not COMMIT yet).
--
-- Session B (psql #2), concurrently:
--   BEGIN;
--   SELECT * FROM public.seo_recommendation_generate('<same website_id>');  -- BLOCKS
--
-- Observe from a third session:
--   SELECT wait_event_type, wait_event, query FROM pg_stat_activity
--    WHERE query ILIKE '%seo_recommendation_generate%';
--   -- Session B shows a Lock / advisory wait_event while A holds the lock.
--
-- Then COMMIT Session A -> Session B unblocks, completes, and both converge to
-- the SAME canonical set (the two partial UNIQUE indexes guarantee exactly one
-- current row per identity; no duplicates). COMMIT B, then delete the
-- disposable fixtures. Expected: no duplicate-key error, one canonical row per
-- identity, net-nothing after cleanup.
-- =============================================================================
