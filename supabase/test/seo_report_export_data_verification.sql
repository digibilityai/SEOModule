-- =============================================================================
-- SEO Reports Stage 3 — seo_report_export_data — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test, AFTER 20260720120038_seo_report_export_data.sql.
-- Single transaction; acting user via jwt claims; self-cleaning → net-nothing.
-- Prereq: shared UI-seed workspace + owner/admin/team/client/nonmember users.
--
-- Proves: structure/grants (authenticated allowed; anon denied); read-only
-- export authz (owner/admin/team return the canonical row; client/nonmember/
-- anon denied with a non-leaking error; unsupported period rejected); the
-- returned row EQUALS the stored row; the RPC performs no writes.
-- =============================================================================

SELECT set_config('e3.ws',     '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('e3.site',   'b3000000-0000-0000-0008-000000000001', false);
SELECT set_config('e3.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('e3.admin',  '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('e3.team',   '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('e3.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('e3.non',    '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);
SELECT set_config('e3.rid',    'd3000000-0000-0000-0008-000000000001', false);

CREATE OR REPLACE FUNCTION public._e3_login(p uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF p IS NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub',p,'role','authenticated')::text, true);
  END IF;
END $fn$;

-- ---------- 1. STRUCTURE + GRANTS -------------------------------------------
DO $t$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='seo_report_export_data' AND p.prosecdef
       AND p.provolatile='s'  -- STABLE (read-only)
       AND (SELECT bool_or(c='search_path=public') FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) c)) THEN
    RAISE EXCEPTION 'STRUCT: seo_report_export_data missing / not STABLE SECURITY DEFINER+search_path';
  END IF;
  IF NOT has_function_privilege('authenticated','public.seo_report_export_data(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated must EXECUTE';
  END IF;
  IF has_function_privilege('anon','public.seo_report_export_data(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: anon must NOT EXECUTE';
  END IF;
  RAISE NOTICE 'STRUCT+GRANT ok';
END $t$;

-- ---------- 2. SEED website + a stored report (as postgres) -----------------
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('e3.site')::uuid, current_setting('e3.ws')::uuid, 'https://rpt-s3.example', 'RPT S3', 'RPT S3', 'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.seo_reports (id, workspace_id, website_id, website_url, report_type, period_key, period_label, period_start, period_end, title, status, summary, generated_at, created_by)
VALUES (current_setting('e3.rid')::uuid, current_setting('e3.ws')::uuid, current_setting('e3.site')::uuid, 'https://rpt-s3.example',
        'progress', 'last_month', 'June 2026', '2026-06-01', '2026-06-30', 'Progress report — June 2026', 'generated',
        jsonb_build_object('overall_score_current',62,'overall_score_movement',6,'data_provenance',
          jsonb_build_object('competitor','unavailable','roadmap','unavailable','expert_support','unavailable')),
        '2026-06-05T09:00:00Z', current_setting('e3.owner')::uuid);

-- baseline stored snapshot for the read-only + equals checks
SELECT set_config('e3.stored_summary', (SELECT summary::text FROM public.seo_reports WHERE id=current_setting('e3.rid')::uuid), false);
SELECT set_config('e3.base_updated', (SELECT updated_at::text FROM public.seo_reports WHERE id=current_setting('e3.rid')::uuid), false);

-- ---------- 3. AUTHORIZED export + equals-stored ----------------------------
SET LOCAL ROLE authenticated;

SELECT public._e3_login(current_setting('e3.owner')::uuid);
DO $t$
DECLARE r public.seo_reports%ROWTYPE; n int;
BEGIN
  SELECT * INTO r FROM public.seo_report_export_data(current_setting('e3.site')::uuid, 'last_month');
  IF r.id <> current_setting('e3.rid')::uuid THEN RAISE EXCEPTION 'EXPORT: owner got wrong row'; END IF;
  IF r.summary::text <> current_setting('e3.stored_summary') THEN RAISE EXCEPTION 'EXPORT: returned summary != stored'; END IF;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'EXPORT owner ok';
END $t$;

-- admin + team allowed
DO $t$
DECLARE r public.seo_reports%ROWTYPE;
BEGIN
  PERFORM public._e3_login(current_setting('e3.admin')::uuid);
  SELECT * INTO r FROM public.seo_report_export_data(current_setting('e3.site')::uuid, 'last_month');
  IF r.id IS NULL THEN RAISE EXCEPTION 'EXPORT: admin denied unexpectedly'; END IF;
  PERFORM public._e3_login(current_setting('e3.team')::uuid);
  SELECT * INTO r FROM public.seo_report_export_data(current_setting('e3.site')::uuid, 'last_month');
  IF r.id IS NULL THEN RAISE EXCEPTION 'EXPORT: team denied unexpectedly'; END IF;
  RAISE NOTICE 'EXPORT admin+team ok';
END $t$;

-- ---------- 4. DENIALS (client / nonmember / anon / unsupported period) -----
DO $t$
DECLARE ok boolean;
BEGIN
  ok := false; PERFORM public._e3_login(current_setting('e3.client')::uuid);
  BEGIN PERFORM public.seo_report_export_data(current_setting('e3.site')::uuid, 'last_month'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: client export was allowed'; END IF;

  ok := false; PERFORM public._e3_login(current_setting('e3.non')::uuid);
  BEGIN PERFORM public.seo_report_export_data(current_setting('e3.site')::uuid, 'last_month'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: nonmember export was allowed'; END IF;

  ok := false; PERFORM public._e3_login(NULL);
  BEGIN PERFORM public.seo_report_export_data(current_setting('e3.site')::uuid, 'last_month'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: anon export was allowed'; END IF;

  ok := false; PERFORM public._e3_login(current_setting('e3.owner')::uuid);
  BEGIN PERFORM public.seo_report_export_data(current_setting('e3.site')::uuid, 'weekly'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: unsupported period accepted'; END IF;

  RAISE NOTICE 'DENIALS ok';
END $t$;

RESET ROLE;

-- ---------- 5. READ-ONLY (row unchanged) ------------------------------------
DO $t$
BEGIN
  IF (SELECT updated_at::text FROM public.seo_reports WHERE id=current_setting('e3.rid')::uuid) <> current_setting('e3.base_updated') THEN
    RAISE EXCEPTION 'READ-ONLY: export mutated the report row';
  END IF;
  RAISE NOTICE 'READ-ONLY ok';
END $t$;

-- ---------- 6. TEARDOWN + net-nothing ---------------------------------------
DELETE FROM public.seo_reports WHERE website_id=current_setting('e3.site')::uuid;
DELETE FROM public.seo_websites WHERE id=current_setting('e3.site')::uuid;
DROP FUNCTION IF EXISTS public._e3_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('e3.site')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residue'; END IF;
  RAISE NOTICE 'TEARDOWN ok — net-nothing';
  RAISE NOTICE 'ALL STAGE 3 EXPORT-DATA CHECKS PASSED';
END $t$;
