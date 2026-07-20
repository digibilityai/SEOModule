-- =============================================================================
-- SEO Reports Stage 1 — Real-data READ path — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER migration
-- 20260720120035_seo_reports_foundation.sql is applied.
--
-- EXECUTION MODEL (same as the P1a / Phase 16C scripts): the
-- `supabase db query --linked -f` runner wraps the whole file in ONE
-- transaction; NO explicit BEGIN/COMMIT. Runs as the `postgres` connection
-- role; the acting SEO user is switched via jwt claims (set_config), and the
-- RLS SELECT tests additionally `SET LOCAL ROLE authenticated` so the
-- member-only policy actually evaluates (postgres bypasses RLS). All fixtures
-- are disposable and removed in teardown → a successful run commits
-- net-nothing. No password / service-role key is used.
--
-- PREREQUISITE: the shared TEST auth users exist (owner/admin/team/client are
-- members of the UI-seed workspace 44444444-0000-0000-0001-000000000001;
-- nonmember is NOT a member) — the same fixtures the P1a Step 2A script relies
-- on.
--
-- WHAT THIS PROVES (Reports Stage 1 read path):
--   structure/RLS wiring; authorized list + detail; member-role reads
--   (incl. client read-only); cross-tenant isolation (nonmember + anon see
--   nothing); website scoping in the read path; missing report → none; empty
--   website → none; deterministic newest-first ordering.
-- =============================================================================

-- ---------- 0. Fixture ids + jwt login helper -------------------------------
SELECT set_config('rpt.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('rpt.siteA',     'a1000000-0000-0000-0003-0000000000a1', false);
SELECT set_config('rpt.siteB',     'a1000000-0000-0000-0003-0000000000b1', false);
SELECT set_config('rpt.siteEmpty', 'a1000000-0000-0000-0003-0000000000e1', false);
SELECT set_config('rpt.owner',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('rpt.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('rpt.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('rpt.client',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('rpt.nonmember', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo_rpt_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF p_uid IS NULL THEN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  ELSE
    PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  END IF;
END $fn$;

-- ---------- 1. STRUCTURE ----------------------------------------------------
DO $t$
DECLARE n int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='seo_reports') THEN
    RAISE EXCEPTION 'STRUCT: public.seo_reports missing';
  END IF;

  -- RLS enabled
  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='public' AND c.relname='seo_reports' AND c.relrowsecurity;
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: RLS not enabled on seo_reports'; END IF;

  -- canonical scalar columns + summary jsonb present
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='seo_reports' AND column_name IN
     ('id','workspace_id','website_id','website_url','report_type','period_key',
      'period_label','period_start','period_end','title','status','summary',
      'generated_at','generation_status','generation_error','created_by',
      'created_at','updated_at');
  IF n <> 18 THEN RAISE EXCEPTION 'STRUCT: expected 18 known columns, got %', n; END IF;

  -- summary is jsonb
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='seo_reports'
                   AND column_name='summary' AND data_type='jsonb') THEN
    RAISE EXCEPTION 'STRUCT: summary must be jsonb';
  END IF;

  -- unique (website_id, report_type, period_key)
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='seo_reports'
      AND indexdef ILIKE '%UNIQUE%(website_id, report_type, period_key)%'
  ) THEN RAISE EXCEPTION 'STRUCT: unique(website_id, report_type, period_key) missing'; END IF;

  -- both policies present
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname='public' AND tablename='seo_reports'
     AND policyname IN ('seo_reports_select','seo_reports_write');
  IF n <> 2 THEN RAISE EXCEPTION 'STRUCT: expected 2 policies, got %', n; END IF;

  RAISE NOTICE 'STRUCT ok';
END $t$;

-- ---------- 2. SEED disposable websites + reports (as postgres) -------------
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES
  (current_setting('rpt.siteA')::uuid,     current_setting('rpt.workspace')::uuid, 'https://rpt-a.example',     'Reports Disposable A', 'Reports A', 'other', 'pending', true),
  (current_setting('rpt.siteB')::uuid,     current_setting('rpt.workspace')::uuid, 'https://rpt-b.example',     'Reports Disposable B', 'Reports B', 'other', 'pending', true),
  (current_setting('rpt.siteEmpty')::uuid, current_setting('rpt.workspace')::uuid, 'https://rpt-empty.example', 'Reports Disposable E', 'Reports E', 'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- Website A: two reports (distinct periods) with different generated_at to
-- prove newest-first ordering. Website B: one report. Website Empty: none.
INSERT INTO public.seo_reports
  (workspace_id, website_id, website_url, report_type, period_key, period_label, period_start, period_end, title, status, summary, generated_at, created_by)
VALUES
  (current_setting('rpt.workspace')::uuid, current_setting('rpt.siteA')::uuid, 'https://rpt-a.example', 'progress', 'last_month',
     'June 2026', '2026-06-01', '2026-06-30', 'Progress report — June 2026', 'generated',
     '{"overall_score_current":62,"overall_score_previous":56,"overall_score_movement":6,"next_actions":["Review approvals"]}'::jsonb,
     '2026-06-05T09:00:00Z', current_setting('rpt.owner')::uuid),
  (current_setting('rpt.workspace')::uuid, current_setting('rpt.siteA')::uuid, 'https://rpt-a.example', 'progress', 'current_month',
     'July 2026', '2026-07-01', '2026-07-20', 'Progress report — July 2026', 'generated',
     '{"overall_score_current":66,"overall_score_previous":62,"overall_score_movement":4,"next_actions":["Keep monitoring"]}'::jsonb,
     '2026-07-05T09:00:00Z', current_setting('rpt.owner')::uuid),
  (current_setting('rpt.workspace')::uuid, current_setting('rpt.siteB')::uuid, 'https://rpt-b.example', 'progress', 'last_month',
     'June 2026', '2026-06-01', '2026-06-30', 'Progress report — June 2026 (B)', 'generated',
     '{"overall_score_current":40,"overall_score_previous":40,"overall_score_movement":0,"next_actions":[]}'::jsonb,
     '2026-06-10T09:00:00Z', current_setting('rpt.owner')::uuid);

-- ---------- 3. RLS READS under the authenticated role -----------------------
SET LOCAL ROLE authenticated;

-- 3a. owner: authorized list + website scoping + ordering + detail
SELECT public._seo_rpt_login(current_setting('rpt.owner')::uuid);
DO $t$
DECLARE n int; first_period text; detail_title text;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteA')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'READ: owner should see 2 reports for site A, got %', n; END IF;

  -- website scoping: A=2, B=1, no bleed
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteB')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'READ: owner should see 1 report for site B, got %', n; END IF;

  -- deterministic newest-first ordering (generated_at DESC): July before June
  SELECT period_key INTO first_period FROM public.seo_reports
    WHERE website_id=current_setting('rpt.siteA')::uuid
    ORDER BY generated_at DESC, id LIMIT 1;
  IF first_period <> 'current_month' THEN
    RAISE EXCEPTION 'READ: newest-first ordering wrong; got % first', first_period;
  END IF;

  -- detail by period (maybeSingle equivalent)
  SELECT title INTO detail_title FROM public.seo_reports
    WHERE website_id=current_setting('rpt.siteA')::uuid AND report_type='progress' AND period_key='last_month';
  IF detail_title <> 'Progress report — June 2026' THEN
    RAISE EXCEPTION 'READ: detail lookup returned wrong row (%)', detail_title;
  END IF;

  -- missing report → none
  SELECT count(*) INTO n FROM public.seo_reports
    WHERE website_id=current_setting('rpt.siteA')::uuid AND period_key='last_90_days';
  IF n <> 0 THEN RAISE EXCEPTION 'READ: missing period should return 0, got %', n; END IF;

  -- empty website → none
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteEmpty')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'READ: empty website should return 0, got %', n; END IF;

  RAISE NOTICE 'READ owner/list/detail/scoping/ordering/empty ok';
END $t$;

-- 3b. member roles: admin / team / client can all read (client read-only)
SELECT public._seo_rpt_login(current_setting('rpt.admin')::uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteA')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'READ: admin should see 2 for site A, got %', n; END IF;
END $t$;

SELECT public._seo_rpt_login(current_setting('rpt.team')::uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteA')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'READ: team_member should see 2 for site A, got %', n; END IF;
END $t$;

SELECT public._seo_rpt_login(current_setting('rpt.client')::uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteA')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'READ: client should see 2 for site A (read-only), got %', n; END IF;
END $t$;

-- 3c. cross-tenant isolation: nonmember + anon see nothing
SELECT public._seo_rpt_login(current_setting('rpt.nonmember')::uuid);
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteA')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: nonmember must see 0 reports, got %', n; END IF;
END $t$;

SELECT public._seo_rpt_login(NULL);  -- anon
DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('rpt.siteA')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: anon must see 0 reports, got %', n; END IF;
  RAISE NOTICE 'READ member-roles + cross-tenant isolation ok';
END $t$;

-- 3d. client write denial (defense-in-depth; no customer write path in Stage 1)
SELECT public._seo_rpt_login(current_setting('rpt.client')::uuid);
DO $t$
DECLARE ok boolean := false; rc int;
BEGIN
  BEGIN
    INSERT INTO public.seo_reports
      (workspace_id, website_id, website_url, report_type, period_key, period_label, period_start, period_end, title, status, summary)
    VALUES (current_setting('rpt.workspace')::uuid, current_setting('rpt.siteA')::uuid, 'https://rpt-a.example',
            'progress', 'last_90_days', 'x', '2026-01-01', '2026-03-31', 'x', 'generated', '{}'::jsonb);
  EXCEPTION WHEN insufficient_privilege OR others THEN ok := true;
  END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: client directly INSERTed a report'; END IF;
  RAISE NOTICE 'READ client write-denial ok';
END $t$;

RESET ROLE;

-- ---------- 4. TEARDOWN (as postgres) + net-nothing -------------------------
DELETE FROM public.seo_reports
 WHERE website_id IN (current_setting('rpt.siteA')::uuid,
                      current_setting('rpt.siteB')::uuid,
                      current_setting('rpt.siteEmpty')::uuid);
DELETE FROM public.seo_websites
 WHERE id IN (current_setting('rpt.siteA')::uuid,
              current_setting('rpt.siteB')::uuid,
              current_setting('rpt.siteEmpty')::uuid);
DROP FUNCTION IF EXISTS public._seo_rpt_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports
   WHERE website_id IN (current_setting('rpt.siteA')::uuid,
                        current_setting('rpt.siteB')::uuid,
                        current_setting('rpt.siteEmpty')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: % report fixtures remain', n; END IF;
  RAISE NOTICE 'TEARDOWN ok — net-nothing';
  RAISE NOTICE 'ALL REPORTS READ-PATH CHECKS PASSED';
END $t$;
