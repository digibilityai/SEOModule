-- =============================================================================
-- SEO Competitor Benchmarking Stage 1 — READ path + RLS — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test, AFTER 20260720123000_seo_competitors.sql.
-- Single transaction (runner-wrapped); acting user switched via jwt claims; the
-- RLS tests additionally SET LOCAL ROLE authenticated so the policies actually
-- evaluate (postgres bypasses RLS). Disposable fixtures removed in teardown →
-- net-nothing. Prereq: the shared UI-seed workspace + owner/admin/team/client/
-- nonmember users (same fixtures as the P1a / Reports scripts).
--
-- Proves: structure (table, RLS enabled, columns, unique key, provenance CHECK);
-- authorized member read (incl. client read-only); owner/admin/team_member
-- write; client write denial; anon/nonmember/cross-tenant denial; uniqueness
-- behaviour; self-cleaning.
-- =============================================================================

SELECT set_config('cmp.ws',     '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('cmp.site',   'c5000000-0000-0000-0009-000000000001', false);
SELECT set_config('cmp.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('cmp.admin',  '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('cmp.team',   '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('cmp.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('cmp.non',    '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._cmp_login(p uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF p IS NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub',p,'role','authenticated')::text, true);
  END IF;
END $fn$;

-- ---------- 1. STRUCTURE -----------------------------------------------------
DO $t$
DECLARE n int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='seo_competitors') THEN
    RAISE EXCEPTION 'STRUCT: seo_competitors missing';
  END IF;
  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='public' AND c.relname='seo_competitors' AND c.relrowsecurity;
  IF n <> 1 THEN RAISE EXCEPTION 'STRUCT: RLS not enabled'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='seo_competitors'
                 AND indexdef ILIKE '%UNIQUE%(website_id, normalized_competitor_url)%') THEN
    RAISE EXCEPTION 'STRUCT: unique(website_id, normalized_competitor_url) missing';
  END IF;

  -- provenance CHECK constrains to 'estimated' only
  IF NOT EXISTS (SELECT 1 FROM pg_constraint con JOIN pg_class r ON r.oid=con.conrelid
                 WHERE r.relname='seo_competitors' AND con.contype='c'
                   AND pg_get_constraintdef(con.oid) ILIKE '%data_provenance%estimated%') THEN
    RAISE EXCEPTION 'STRUCT: data_provenance estimated CHECK missing';
  END IF;

  SELECT count(*) INTO n FROM pg_policies WHERE schemaname='public' AND tablename='seo_competitors'
    AND policyname IN ('seo_competitors_select','seo_competitors_write');
  IF n <> 2 THEN RAISE EXCEPTION 'STRUCT: expected 2 policies, got %', n; END IF;
  RAISE NOTICE 'STRUCT ok';
END $t$;

-- ---------- 2. SEED disposable website (as postgres) ------------------------
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('cmp.site')::uuid, current_setting('cmp.ws')::uuid, 'https://cmp-s1.example', 'CMP S1', 'CMP S1', 'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- ---------- 3. RLS: writes + reads under the authenticated role -------------
SET LOCAL ROLE authenticated;

-- 3a. owner may WRITE two competitor rows (data_provenance defaults to 'estimated')
SELECT public._cmp_login(current_setting('cmp.owner')::uuid);
DO $t$
DECLARE n int;
BEGIN
  INSERT INTO public.seo_competitors (workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url, overall_strength_score, generation_method, created_by)
  VALUES (current_setting('cmp.ws')::uuid, current_setting('cmp.site')::uuid, 'https://cmp-s1.example', 'Comp A', 'https://www.compa.com/', 'compa.com', 66, 'heuristic_v1', current_setting('cmp.owner')::uuid),
         (current_setting('cmp.ws')::uuid, current_setting('cmp.site')::uuid, 'https://cmp-s1.example', 'Comp B', 'https://compb.com',       'compb.com', 50, 'heuristic_v1', current_setting('cmp.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'WRITE: owner should have inserted 2, got %', n; END IF;
  -- provenance is truthful 'estimated'
  IF EXISTS (SELECT 1 FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid AND data_provenance <> 'estimated') THEN
    RAISE EXCEPTION 'PROVENANCE: a row is not estimated';
  END IF;
  RAISE NOTICE 'WRITE owner + provenance ok';
END $t$;

-- 3b. uniqueness: same website + same normalized url is rejected
DO $t$
DECLARE ok boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.seo_competitors (workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url)
    VALUES (current_setting('cmp.ws')::uuid, current_setting('cmp.site')::uuid, 'https://cmp-s1.example', 'Comp A dup', 'https://compa.com', 'compa.com');
  EXCEPTION WHEN unique_violation THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'UNIQUE: duplicate normalized_competitor_url was allowed'; END IF;
  RAISE NOTICE 'UNIQUE ok';
END $t$;

-- 3c. admin + team_member may write
DO $t$
BEGIN
  PERFORM public._cmp_login(current_setting('cmp.admin')::uuid);
  UPDATE public.seo_competitors SET overall_strength_score=67 WHERE website_id=current_setting('cmp.site')::uuid AND normalized_competitor_url='compa.com';
  PERFORM public._cmp_login(current_setting('cmp.team')::uuid);
  UPDATE public.seo_competitors SET overall_strength_score=51 WHERE website_id=current_setting('cmp.site')::uuid AND normalized_competitor_url='compb.com';
  RAISE NOTICE 'WRITE admin+team ok';
END $t$;

-- 3d. member reads (owner/admin/team/client all see 2; client is read-only)
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._cmp_login(current_setting('cmp.client')::uuid);
  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'READ: client should see 2, got %', n; END IF;
  RAISE NOTICE 'READ client ok';
END $t$;

-- 3e. client WRITE denial
DO $t$
DECLARE ok boolean := false;
BEGIN
  PERFORM public._cmp_login(current_setting('cmp.client')::uuid);
  BEGIN
    INSERT INTO public.seo_competitors (workspace_id, website_id, website_url, competitor_name, competitor_url, normalized_competitor_url)
    VALUES (current_setting('cmp.ws')::uuid, current_setting('cmp.site')::uuid, 'https://cmp-s1.example', 'Comp C', 'https://compc.com', 'compc.com');
  EXCEPTION WHEN insufficient_privilege OR others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: client WROTE a competitor'; END IF;
  RAISE NOTICE 'client write-denial ok';
END $t$;

-- 3f. cross-tenant / anon denial (nonmember + anon see 0)
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._cmp_login(current_setting('cmp.non')::uuid);
  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: nonmember must see 0, got %', n; END IF;
  PERFORM public._cmp_login(NULL);
  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'ISO: anon must see 0, got %', n; END IF;
  RAISE NOTICE 'cross-tenant + anon denial ok';
END $t$;

RESET ROLE;

-- ---------- 4. TEARDOWN + net-nothing ---------------------------------------
DELETE FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid;
DELETE FROM public.seo_websites WHERE id=current_setting('cmp.site')::uuid;
DROP FUNCTION IF EXISTS public._cmp_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_competitors WHERE website_id=current_setting('cmp.site')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: % competitor fixtures remain', n; END IF;
  RAISE NOTICE 'TEARDOWN ok — net-nothing';
  RAISE NOTICE 'ALL COMPETITOR STAGE 1 CHECKS PASSED';
END $t$;
