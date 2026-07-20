-- =============================================================================
-- SEO Reports Stage 2 — seo_report_generate — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test, AFTER 20260720120036_seo_report_generate.sql.
-- Single transaction (runner-wrapped); acting user switched via jwt claims;
-- RLS/definer reads evaluated correctly; disposable fixtures removed in
-- teardown → net-nothing. Prereq: the shared UI-seed workspace + owner/admin/
-- team/client/nonmember users (same fixtures as the P1a/Stage-1 scripts).
--
-- Proves: structure/grants; authz matrix (owner/admin/team allow; client/
-- nonmember/anon/cross-tenant deny with no leak); unsupported-period reject;
-- period derivation; latest-vs-previous audit selection; page-performance
-- normalization across every branch incl. the deterministic Branch 3;
-- content/authority/ai aggregation; truthful provenance for the 3 unavailable
-- areas; first-insert then repeat-update idempotency (one canonical row).
--
-- Approvals are asserted at the empty (0) case here (seeding them requires the
-- seo_recommendations FK chain); the pending/fixed FILTER-count logic is
-- structurally identical to the content/authority counts, which ARE seeded
-- non-zero below. Two-session advisory-lock concurrency is proven separately
-- (see the companion command in the Stage 2 report), not in this single-session
-- script.
-- =============================================================================

SELECT set_config('s2.ws',     '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('s2.site',   'b2000000-0000-0000-0008-000000000001', false);
SELECT set_config('s2.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('s2.admin',  '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('s2.team',   '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('s2.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('s2.non',    '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._s2_login(p uuid) RETURNS void LANGUAGE plpgsql AS $fn$
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
     WHERE n.nspname='public' AND p.proname='seo_report_generate' AND p.prosecdef
       AND (SELECT bool_or(c='search_path=public') FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) c)) THEN
    RAISE EXCEPTION 'STRUCT: seo_report_generate missing / not SECURITY DEFINER+search_path';
  END IF;
  IF NOT has_function_privilege('authenticated','public.seo_report_generate(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: authenticated must EXECUTE';
  END IF;
  IF has_function_privilege('anon','public.seo_report_generate(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'GRANT: anon must NOT EXECUTE';
  END IF;
  RAISE NOTICE 'STRUCT+GRANT ok';
END $t$;

-- ---------- 2. SEED source data (as postgres) -------------------------------
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('s2.site')::uuid, current_setting('s2.ws')::uuid, 'https://rpt-stage2.example', 'RPT S2', 'RPT S2', 'other', 'pending', true)
ON CONFLICT (id) DO NOTHING;

-- audits: previous (56) + latest (62) completed, plus a running one (ignored)
INSERT INTO public.seo_audit_runs (workspace_id, website_id, website_url, status, overall_visibility_score, issue_count, completed_at, started_at)
VALUES
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'completed', 56, 5, now()-interval '10 days', now()-interval '10 days'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'completed', 62, 3, now()-interval '1 day',  now()-interval '1 day'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'running',   99, 9, NULL,                    now());

-- content: 3 total, 1 archived(=completed)
INSERT INTO public.seo_content_opportunities (workspace_id, website_id, website_url, title, target_keyword, status)
VALUES
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'C1', 'kw1', 'idea'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'C2', 'kw2', 'draft_in_progress'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'C3', 'kw3', 'archived');

-- authority: 4 total, 1 avoided
INSERT INTO public.seo_authority_opportunities (workspace_id, website_id, website_url, opportunity_type, title, source_platform, suggested_action, why_it_matters, status)
VALUES
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'backlink', 'A1', 'x', 'do', 'why', 'suggested'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'backlink', 'A2', 'x', 'do', 'why', 'shortlisted'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'backlink', 'A3', 'x', 'do', 'why', 'completed'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'backlink', 'A4', 'x', 'do', 'why', 'avoided');

-- ai gaps: 2
INSERT INTO public.seo_ai_content_gaps (workspace_id, website_id, website_url, topic, missing_answer_angle, suggested_content_type, related_keyword_or_question, recommended_next_action)
VALUES
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'T1','angle','faq','q1','act'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid, 'https://rpt-stage2.example', 'T2','angle','faq','q2','act');

-- pages + keywords + snapshots covering every normalization branch.
-- P1 aging(+improving primary)→needs_refresh; P2 stale(+declining page-level)→needs_refresh;
-- P3 improving; P4 stable; P5 declining(page-level); P6 new→neid; P7 no_data→neid;
-- P8 no snapshot→neid; P9 Branch3 newest-date→declining; P10 Branch3 equal-date tie(lower kw id)→improving;
-- P11 improving but INACTIVE→excluded. Expected active total=10, improving=2, declining=2.
INSERT INTO public.seo_page_inventory (id, workspace_id, website_id, website_url, page_url, content_status, is_active)
VALUES
 ('f2000000-0000-0000-0008-000000000001', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p1','aging', true),
 ('f2000000-0000-0000-0008-000000000002', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p2','stale', true),
 ('f2000000-0000-0000-0008-000000000003', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p3','fresh', true),
 ('f2000000-0000-0000-0008-000000000004', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p4','fresh', true),
 ('f2000000-0000-0000-0008-000000000005', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p5','fresh', true),
 ('f2000000-0000-0000-0008-000000000006', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p6','fresh', true),
 ('f2000000-0000-0000-0008-000000000007', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p7','fresh', true),
 ('f2000000-0000-0000-0008-000000000008', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p8','fresh', true),
 ('f2000000-0000-0000-0008-000000000009', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p9','fresh', true),
 ('f2000000-0000-0000-0008-00000000000a', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p10','fresh', true),
 ('f2000000-0000-0000-0008-00000000000b', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','/p11','fresh', false);

-- primary keywords for P1,P3,P4,P6,P7,P11; Branch-3 non-primary keywords for P9,P10
INSERT INTO public.seo_page_keywords (id, workspace_id, website_id, website_url, page_id, page_url, keyword, is_primary)
VALUES
 ('c1000000-0000-0000-0008-000000000001', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000001','/p1','k1', true),
 ('c1000000-0000-0000-0008-000000000003', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000003','/p3','k3', true),
 ('c1000000-0000-0000-0008-000000000004', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000004','/p4','k4', true),
 ('c1000000-0000-0000-0008-000000000006', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000006','/p6','k6', true),
 ('c1000000-0000-0000-0008-000000000007', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000007','/p7','k7', true),
 ('c1000000-0000-0000-0008-00000000000b', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-00000000000b','/p11','k11', true),
 -- P9 Branch-3: two non-primary keywords (older improving, newer declining)
 ('c1000000-0000-0000-0008-000000000091', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000009','/p9','k9a', false),
 ('c1000000-0000-0000-0008-000000000092', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000009','/p9','k9b', false),
 -- P10 Branch-3 tie: same date; lower keyword id improving, higher declining
 ('c1000000-0000-0000-0008-0000000000a1', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-00000000000a','/p10','k10a', false),
 ('c1000000-0000-0000-0008-0000000000a2', current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-00000000000a','/p10','k10b', false);

-- snapshots (movement + snapshot_date; page_keyword_id NULL = page-level)
INSERT INTO public.seo_page_performance_snapshots (workspace_id, website_id, website_url, page_id, page_keyword_id, page_url, snapshot_date, period_start, period_end, movement_status)
VALUES
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000001','c1000000-0000-0000-0008-000000000001','/p1', current_date, current_date-7, current_date, 'improving'),  -- P1 primary improving (overridden by aging)
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000002', NULL,                                   '/p2', current_date, current_date-7, current_date, 'declining'),  -- P2 page-level declining (overridden by stale)
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000003','c1000000-0000-0000-0008-000000000003','/p3', current_date, current_date-7, current_date, 'improving'),  -- P3 improving
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000004','c1000000-0000-0000-0008-000000000004','/p4', current_date, current_date-7, current_date, 'stable'),     -- P4 stable
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000005', NULL,                                   '/p5', current_date, current_date-7, current_date, 'declining'),  -- P5 page-level declining
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000006','c1000000-0000-0000-0008-000000000006','/p6', current_date, current_date-7, current_date, 'new'),        -- P6 new
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000007','c1000000-0000-0000-0008-000000000007','/p7', current_date, current_date-7, current_date, 'no_data'),    -- P7 no_data
 -- P9 Branch3: older improving, newer declining -> newest wins (declining)
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000009','c1000000-0000-0000-0008-000000000091','/p9', current_date-5, current_date-7, current_date, 'improving'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-000000000009','c1000000-0000-0000-0008-000000000092','/p9', current_date-1, current_date-7, current_date, 'declining'),
 -- P10 Branch3 tie: same date; lower kw id improving wins
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-00000000000a','c1000000-0000-0000-0008-0000000000a1','/p10', current_date, current_date-7, current_date, 'improving'),
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-00000000000a','c1000000-0000-0000-0008-0000000000a2','/p10', current_date, current_date-7, current_date, 'declining'),
 -- P11 inactive primary improving (excluded)
 (current_setting('s2.ws')::uuid, current_setting('s2.site')::uuid,'https://rpt-stage2.example','f2000000-0000-0000-0008-00000000000b','c1000000-0000-0000-0008-00000000000b','/p11', current_date, current_date-7, current_date, 'improving');
-- P8 intentionally has NO snapshot.

-- ---------- 3. GENERATE (owner) + assert summary ----------------------------
SET LOCAL ROLE authenticated;
SELECT public._s2_login(current_setting('s2.owner')::uuid);

DO $t$
DECLARE v_id uuid; s jsonb; r public.seo_reports%ROWTYPE;
BEGIN
  v_id := public.seo_report_generate(current_setting('s2.site')::uuid, 'last_month');
  SELECT * INTO r FROM public.seo_reports WHERE id=v_id;
  s := r.summary;

  IF r.period_key <> 'last_month' THEN RAISE EXCEPTION 'period_key wrong'; END IF;
  IF r.period_start <> (date_trunc('month', current_date) - interval '1 month')::date THEN RAISE EXCEPTION 'period_start wrong: %', r.period_start; END IF;
  IF r.period_end <> (date_trunc('month', current_date) - interval '1 day')::date THEN RAISE EXCEPTION 'period_end wrong: %', r.period_end; END IF;
  IF r.status <> 'generated' THEN RAISE EXCEPTION 'status wrong'; END IF;
  IF r.created_by <> current_setting('s2.owner')::uuid THEN RAISE EXCEPTION 'created_by wrong'; END IF;

  IF (s->>'overall_score_current')::int <> 62 THEN RAISE EXCEPTION 'audit current % (want 62)', s->>'overall_score_current'; END IF;
  IF (s->>'overall_score_previous')::int <> 56 THEN RAISE EXCEPTION 'audit previous % (want 56)', s->>'overall_score_previous'; END IF;
  IF (s->>'overall_score_movement')::int <> 6 THEN RAISE EXCEPTION 'audit movement % (want 6)', s->>'overall_score_movement'; END IF;
  IF (s->>'issues_found_count')::int <> 3 THEN RAISE EXCEPTION 'issues_found % (want 3)', s->>'issues_found_count'; END IF;

  IF (s->>'content_pieces_planned')::int <> 3 THEN RAISE EXCEPTION 'content planned % (want 3)', s->>'content_pieces_planned'; END IF;
  IF (s->>'content_pieces_completed')::int <> 1 THEN RAISE EXCEPTION 'content completed % (want 1)', s->>'content_pieces_completed'; END IF;

  IF (s->>'authority_opportunities_count')::int <> 4 THEN RAISE EXCEPTION 'authority % (want 4)', s->>'authority_opportunities_count'; END IF;
  IF (s->>'ai_content_gaps_count')::int <> 2 THEN RAISE EXCEPTION 'ai gaps % (want 2)', s->>'ai_content_gaps_count'; END IF;

  IF (s->>'improving_pages_count')::int <> 2 THEN RAISE EXCEPTION 'improving % (want 2 = P3+P10)', s->>'improving_pages_count'; END IF;
  IF (s->>'declining_pages_count')::int <> 2 THEN RAISE EXCEPTION 'declining % (want 2 = P5+P9)', s->>'declining_pages_count'; END IF;

  -- approvals empty (truthful 0)
  IF (s->>'pending_approvals_count')::int <> 0 THEN RAISE EXCEPTION 'pending approvals % (want 0)', s->>'pending_approvals_count'; END IF;
  IF (s->>'issues_fixed_count')::int <> 0 THEN RAISE EXCEPTION 'fixed % (want 0)', s->>'issues_fixed_count'; END IF;

  -- provenance: 6 live, 3 unavailable
  IF s->'data_provenance'->>'audit' <> 'live' OR s->'data_provenance'->>'page_performance' <> 'live'
     OR s->'data_provenance'->>'competitor' <> 'unavailable'
     OR s->'data_provenance'->>'roadmap' <> 'unavailable'
     OR s->'data_provenance'->>'expert_support' <> 'unavailable' THEN
    RAISE EXCEPTION 'provenance wrong: %', s->'data_provenance';
  END IF;
  IF (s->>'competitor_gaps_count')::int <> 0 OR (s->>'open_support_requests_count')::int <> 0 THEN
    RAISE EXCEPTION 'unavailable-area counts must be 0';
  END IF;

  PERFORM set_config('s2.rid', v_id::text, false);
  RAISE NOTICE 'GENERATE owner + aggregation + provenance ok (report %)', v_id;
END $t$;

-- ---------- 4. IDEMPOTENCY: repeat generate = same row ----------------------
DO $t$
DECLARE v_id2 uuid; n int;
BEGIN
  PERFORM public._s2_login(current_setting('s2.owner')::uuid);
  v_id2 := public.seo_report_generate(current_setting('s2.site')::uuid, 'last_month');
  IF v_id2 <> current_setting('s2.rid')::uuid THEN RAISE EXCEPTION 'IDEMPOTENCY: id changed (% vs %)', v_id2, current_setting('s2.rid'); END IF;
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('s2.site')::uuid AND report_type='progress' AND period_key='last_month';
  IF n <> 1 THEN RAISE EXCEPTION 'IDEMPOTENCY: % rows (want 1)', n; END IF;
  RAISE NOTICE 'IDEMPOTENCY ok';
END $t$;

-- ---------- 5. AUTHZ negatives ----------------------------------------------
DO $t$
DECLARE ok boolean;
BEGIN
  -- admin + team allowed
  PERFORM public._s2_login(current_setting('s2.admin')::uuid);
  PERFORM public.seo_report_generate(current_setting('s2.site')::uuid, 'current_month');
  PERFORM public._s2_login(current_setting('s2.team')::uuid);
  PERFORM public.seo_report_generate(current_setting('s2.site')::uuid, 'last_90_days');

  -- client denied
  ok := false;
  PERFORM public._s2_login(current_setting('s2.client')::uuid);
  BEGIN PERFORM public.seo_report_generate(current_setting('s2.site')::uuid, 'last_month'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: client was allowed'; END IF;

  -- nonmember denied (no existence leak — same generic message)
  ok := false;
  PERFORM public._s2_login(current_setting('s2.non')::uuid);
  BEGIN PERFORM public.seo_report_generate(current_setting('s2.site')::uuid, 'last_month'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: nonmember was allowed'; END IF;

  -- anon denied
  ok := false;
  PERFORM public._s2_login(NULL);
  BEGIN PERFORM public.seo_report_generate(current_setting('s2.site')::uuid, 'last_month'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: anon was allowed'; END IF;

  -- unsupported period denied (owner)
  ok := false;
  PERFORM public._s2_login(current_setting('s2.owner')::uuid);
  BEGIN PERFORM public.seo_report_generate(current_setting('s2.site')::uuid, 'weekly'); EXCEPTION WHEN others THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: unsupported period accepted'; END IF;

  RAISE NOTICE 'AUTHZ matrix ok';
END $t$;

RESET ROLE;

-- ---------- 6. TEARDOWN + net-nothing ---------------------------------------
DELETE FROM public.seo_reports WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_page_performance_snapshots WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_page_keywords WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_page_inventory WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_ai_content_gaps WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_authority_opportunities WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_content_opportunities WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_audit_runs WHERE website_id=current_setting('s2.site')::uuid;
DELETE FROM public.seo_websites WHERE id=current_setting('s2.site')::uuid;
DROP FUNCTION IF EXISTS public._s2_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_reports WHERE website_id=current_setting('s2.site')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residue'; END IF;
  RAISE NOTICE 'TEARDOWN ok — net-nothing';
  RAISE NOTICE 'ALL STAGE 2 GENERATE CHECKS PASSED';
END $t$;
