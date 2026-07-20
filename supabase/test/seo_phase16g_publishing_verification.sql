-- =============================================================================
-- SEO Phase 16G / Crawler 1E — Publishing Integration — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****  DO NOT RUN ON PRODUCTION ****
-- RUN ONLY on Digi_SEO_Test, AFTER migration 20260714120029. Single-transaction,
-- fail-fast, self-cleaning. Publishes into DISPOSABLE websites (created in the
-- seed workspace) so the 7 seed Page-Inventory / Audit rows are never touched
-- (website isolation). Worker publish RPC is service_role-only (postgres
-- simulates the worker; authenticated/anon denial proven via has_function_privilege).
-- =============================================================================
SELECT set_config('g.ws',    '44444444-0000-0000-0001-000000000001', false);  -- seed workspace
SELECT set_config('g.seedsite','44444444-0000-0000-0002-000000000001', false); -- seed website (7 pages)
SELECT set_config('g.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('g.nonmember','8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo16g_login(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role','authenticated')::text, true);
END $fn$;

-- ---------------------------------------------------------------------------
-- SETUP: disposable websites + baselines. W = publishing target (seed WS, owner
-- is already a member). WOTHER = a website in a foreign workspace (owner is NOT
-- a member) for cross-workspace denial.
-- ---------------------------------------------------------------------------
DO $t$
DECLARE v_w uuid; v_ws2 uuid; v_wother uuid;
BEGIN
  v_w := gen_random_uuid();
  INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, is_active)
    VALUES (v_w, current_setting('g.ws')::uuid, 'https://phase16g-verify.example', 'P16G', 'P16G', true);
  PERFORM set_config('g.web', v_w::text, false);

  -- P1b fixture: seed VERIFIED domain-ownership for the PRIMARY site (g.web) ONLY,
  -- so it passes the P1b verified-only gate (migration 20260719120034). The
  -- cross-workspace foreign site (g.wother, created below) is deliberately LEFT
  -- UNVERIFIED so its negative test still fails first on AUTHORIZATION, not
  -- ownership. Token-marked for teardown; cascade-removed with the website too.
  INSERT INTO public.seo_ownership_verifications
    (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at)
  VALUES (current_setting('g.ws')::uuid, v_w, 'https://phase16g-verify.example',
          'p1b-fixture.example', 'dns_txt', 'verified', 'P1B-FIXTURE-TOKEN', now())
  ON CONFLICT (website_id, method) DO UPDATE
    SET status='verified', challenge_token='P1B-FIXTURE-TOKEN', verified_at=now(), updated_at=now();

  v_ws2 := gen_random_uuid();
  -- The owner is auto-added as a workspace member by a Stage 1 trigger.
  INSERT INTO public.seo_workspaces (id, name, owner_user_id) VALUES (v_ws2, 'P16G-Foreign', current_setting('g.nonmember')::uuid);
  v_wother := gen_random_uuid();
  INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, is_active)
    VALUES (v_wother, v_ws2, 'https://phase16g-foreign.example', 'P16Gf', 'P16Gf', true);
  PERFORM set_config('g.ws2', v_ws2::text, false);
  PERFORM set_config('g.wother', v_wother::text, false);

  -- Baselines that must be invariant.
  PERFORM set_config('g.base_seedpages', (SELECT count(*)::text FROM public.seo_page_inventory WHERE website_id=current_setting('g.seedsite')::uuid AND is_active), false);
  PERFORM set_config('g.base_seedissues',(SELECT count(*)::text FROM public.seo_audit_issues   WHERE website_id=current_setting('g.seedsite')::uuid), false);
  PERFORM set_config('g.base_recs',      (SELECT count(*)::text FROM public.seo_recommendations), false);
  PERFORM set_config('g.base_perf',      (SELECT count(*)::text FROM public.seo_page_performance_snapshots), false);
  RAISE NOTICE 'SETUP ok (web=%, seedpages=%)', v_w, current_setting('g.base_seedpages');
END $t$;

-- ===========================================================================
-- 1. STRUCTURE + GRANTS + MAPPING COMPLETENESS
-- ===========================================================================
DO $t$
DECLARE n int;
BEGIN
  IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='public'
      AND table_name IN ('seo_crawl_publications','seo_crawl_issue_audit_map')) <> 2
    THEN RAISE EXCEPTION 'STRUCT: publishing tables missing'; END IF;
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='public' AND c.relname IN ('seo_crawl_publications','seo_crawl_issue_audit_map') AND c.relrowsecurity) <> 2
    THEN RAISE EXCEPTION 'STRUCT: RLS not enabled on publishing tables'; END IF;
  -- additive columns
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name='seo_crawl_jobs' AND column_name='audit_run_id') <> 1
    THEN RAISE EXCEPTION 'STRUCT: seo_crawl_jobs.audit_run_id missing'; END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name='seo_page_inventory'
      AND column_name IN ('http_status','word_count','content_type','first_h1','source','source_crawl_job_id','crawler_extracted_at','crawler_extractor_version')) <> 8
    THEN RAISE EXCEPTION 'STRUCT: page_inventory provenance columns missing'; END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name='seo_audit_issues'
      AND column_name IN ('source','crawl_job_id','source_issue_fingerprint','source_rule_version','issue_scope','source_category','source_severity')) <> 7
    THEN RAISE EXCEPTION 'STRUCT: audit_issues provenance columns missing'; END IF;
  -- functions
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='public' AND p.proname IN ('seo_crawl_request_audit','seo_crawl_worker_publish_results')) <> 2
    THEN RAISE EXCEPTION 'STRUCT: publishing fns missing'; END IF;
  -- grants: publish worker RPC service-role-only; orchestration authenticated-only.
  IF has_function_privilege('authenticated','public.seo_crawl_worker_publish_results(uuid,text,uuid,integer)','EXECUTE')
     OR has_function_privilege('anon','public.seo_crawl_worker_publish_results(uuid,text,uuid,integer)','EXECUTE')
    THEN RAISE EXCEPTION 'GRANT: worker publish executable by authenticated/anon'; END IF;
  IF NOT has_function_privilege('authenticated','public.seo_crawl_request_audit(uuid,text,jsonb)','EXECUTE')
    THEN RAISE EXCEPTION 'GRANT: orchestration not executable by authenticated'; END IF;
  IF has_function_privilege('anon','public.seo_crawl_request_audit(uuid,text,jsonb)','EXECUTE')
    THEN RAISE EXCEPTION 'GRANT: orchestration executable by anon'; END IF;
  -- mapping: all 29 stable codes present; the 3 site codes included.
  SELECT count(*) INTO n FROM public.seo_crawl_issue_audit_map;
  IF n <> 29 THEN RAISE EXCEPTION 'MAP: expected 29 codes, got %', n; END IF;
  IF (SELECT count(*) FROM public.seo_crawl_issue_audit_map WHERE issue_code IN ('DUPLICATE_TITLE','DUPLICATE_DESCRIPTION','DUPLICATE_CONTENT')) <> 3
    THEN RAISE EXCEPTION 'MAP: site codes missing'; END IF;
  RAISE NOTICE 'STRUCT+GRANTS+MAP ok';
END $t$;

-- ===========================================================================
-- 2. ASSOCIATION — explicit, no latest-run guessing.
-- ===========================================================================
DO $t$
DECLARE r1 uuid; j1 uuid; st text; r2 uuid; j2 uuid; ok boolean; jplain uuid;
BEGIN
  PERFORM public._seo16g_login(current_setting('g.owner')::uuid);

  SELECT audit_run_id, crawl_job_id, job_status INTO r1, j1, st
    FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-assoc', NULL);
  IF r1 IS NULL OR j1 IS NULL THEN RAISE EXCEPTION 'ASSOC: ids not returned directly'; END IF;
  IF (SELECT audit_run_id FROM public.seo_crawl_jobs WHERE id=j1) <> r1
    THEN RAISE EXCEPTION 'ASSOC: job not bound to run'; END IF;
  IF (SELECT status FROM public.seo_audit_runs WHERE id=r1) <> 'running'
     OR (SELECT website_id FROM public.seo_audit_runs WHERE id=r1) <> current_setting('g.web')::uuid
    THEN RAISE EXCEPTION 'ASSOC: run not running/wrong website'; END IF;

  -- idempotent replay (same key) returns the SAME run + job (no new run).
  SELECT audit_run_id, crawl_job_id INTO r2, j2
    FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-assoc', NULL);
  IF r2 <> r1 OR j2 <> j1 THEN RAISE EXCEPTION 'ASSOC: replay created a new run/job'; END IF;
  IF (SELECT count(*) FROM public.seo_audit_runs WHERE website_id=current_setting('g.web')::uuid) <> 1
    THEN RAISE EXCEPTION 'ASSOC: duplicate audit run created on replay'; END IF;

  -- cross-workspace association denied (owner is not a member of the foreign ws).
  ok:=false;
  BEGIN PERFORM public.seo_crawl_request_audit(current_setting('g.wother')::uuid, 'PHASE16G-x', NULL);
  EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ASSOC: cross-workspace association allowed'; END IF;

  -- free the single-active-job slot before the terminal-job test.
  DELETE FROM public.seo_crawl_jobs WHERE id=j1;
  DELETE FROM public.seo_audit_runs WHERE id=r1;

  -- associating an already-FINISHED unassociated job is denied.
  jplain := public.seo_crawl_request(current_setting('g.web')::uuid, 'PHASE16G-plain', NULL);
  UPDATE public.seo_crawl_jobs SET status='completed', audit_run_id=NULL WHERE id=jplain;
  ok:=false;
  BEGIN PERFORM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-plain', NULL);
  EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'ASSOC: terminal job was (re)associated'; END IF;
  DELETE FROM public.seo_crawl_jobs WHERE id=jplain;
  RAISE NOTICE 'ASSOC ok';
END $t$;

-- ===========================================================================
-- 3/4. PAGE INVENTORY PUBLISHING (+ authz denials, manual preserve, stale).
-- ===========================================================================
DO $t$
DECLARE r uuid; j uuid; tok uuid; res jsonb; n int; ok boolean; v_manual text;
BEGIN
  PERFORM public._seo16g_login(current_setting('g.owner')::uuid);
  v_manual := 'https://phase16g-verify.example/manual-owned';

  -- pre-existing MANUAL page (user-owned) that also appears in the crawl set.
  INSERT INTO public.seo_page_inventory (workspace_id, website_id, website_url, page_url,
    page_title, page_type, indexability_status, priority, is_tracked, source)
  VALUES (current_setting('g.ws')::uuid, current_setting('g.web')::uuid, 'https://phase16g-verify.example',
    v_manual, 'MANUAL TITLE', 'service_page', 'indexable', 'high', false, 'manual');

  SELECT audit_run_id, crawl_job_id INTO r, j
    FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-pi', NULL);
  SELECT lease_token INTO tok FROM public.seo_crawl_claim_job('worker-G', 120);

  -- authz denials BEFORE publishing.
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_publish_results(j,'worker-G',gen_random_uuid(),1);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: stale lease token accepted'; END IF;

  -- record 4 snapshots: 3 crawler-owned + the manual url (skipped on publish).
  PERFORM public.seo_crawl_worker_record_snapshots(j,'worker-G',tok, format('[
    {"requestedUrl":"https://phase16g-verify.example/","finalUrl":"https://phase16g-verify.example/","httpStatus":200,"contentType":"text/html","decodeStatus":"ok","titleCount":1,"title":"Home","description":"Home desc","descriptionLen":9,"h1Count":1,"firstH1":"Welcome","canonicalResolved":"https://phase16g-verify.example/","canonicalClass":"self","effectiveIndex":true,"wordCount":320,"contentHash":"h1","extractionStatus":"extracted","extractorVersion":"1.0.0"},
    {"requestedUrl":"https://phase16g-verify.example/a","httpStatus":200,"contentType":"text/html","decodeStatus":"ok","titleCount":1,"title":"A","effectiveIndex":true,"wordCount":40,"contentHash":"h2","extractionStatus":"extracted","extractorVersion":"1.0.0"},
    {"requestedUrl":"https://phase16g-verify.example/secret","httpStatus":200,"decodeStatus":"ok","titleCount":1,"title":"S","effectiveIndex":false,"wordCount":10,"contentHash":"h3","extractionStatus":"extracted","extractorVersion":"1.0.0"},
    {"requestedUrl":"%s","httpStatus":200,"decodeStatus":"ok","titleCount":1,"title":"CRAWLER TITLE","effectiveIndex":true,"wordCount":100,"contentHash":"h4","extractionStatus":"extracted","extractorVersion":"1.0.0"}
  ]', v_manual)::jsonb);

  res := public.seo_crawl_worker_publish_results(j,'worker-G',tok,1);
  IF res->>'status' <> 'published' THEN RAISE EXCEPTION 'PI: publish status %', res->>'status'; END IF;
  IF (res->>'pagesEligible')::int <> 4 THEN RAISE EXCEPTION 'PI: eligible %', res->>'pagesEligible'; END IF;
  -- 3 crawler rows written; manual url skipped (source=manual).
  IF (res->>'pagesPublished')::int <> 3 THEN RAISE EXCEPTION 'PI: published %', res->>'pagesPublished'; END IF;

  -- mapped fields on the home page.
  IF NOT EXISTS (SELECT 1 FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid
      AND page_url='https://phase16g-verify.example/' AND page_title='Home' AND meta_description='Home desc'
      AND indexability_status='indexable' AND canonical_url='https://phase16g-verify.example/'
      AND http_status=200 AND word_count=320 AND content_type='text/html' AND first_h1='Welcome'
      AND source='crawler' AND source_crawl_job_id=j AND crawler_extracted_at IS NOT NULL)
    THEN RAISE EXCEPTION 'PI: home mapped fields incorrect'; END IF;
  -- noindex mapping.
  IF (SELECT indexability_status FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid AND page_url='https://phase16g-verify.example/secret') <> 'noindex'
    THEN RAISE EXCEPTION 'PI: noindex not mapped'; END IF;
  -- manual/user-owned row untouched.
  IF NOT EXISTS (SELECT 1 FROM public.seo_page_inventory WHERE page_url=v_manual
      AND page_title='MANUAL TITLE' AND source='manual' AND priority='high' AND is_tracked=false)
    THEN RAISE EXCEPTION 'PI: manual row overwritten'; END IF;

  -- idempotent replay: no duplicate active rows.
  PERFORM public.seo_crawl_worker_publish_results(j,'worker-G',tok,1);
  SELECT count(*) INTO n FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid AND is_active;
  IF n <> 4 THEN RAISE EXCEPTION 'PI: replay changed active row count (%)', n; END IF;

  -- cancelled/terminal job cannot publish.
  UPDATE public.seo_crawl_jobs SET status='cancellation_requested' WHERE id=j;
  ok:=false; BEGIN PERFORM public.seo_crawl_worker_publish_results(j,'worker-G',tok,1);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'AUTHZ: cancelled job published'; END IF;

  -- STALE-JOB PROTECTION: newer crawl wins; older cannot overwrite.
  UPDATE public.seo_crawl_jobs SET status='completed' WHERE id=j;  -- free the active slot
  UPDATE public.seo_page_inventory SET crawler_extracted_at = now() - interval '2 days'
    WHERE website_id=current_setting('g.web')::uuid AND page_url='https://phase16g-verify.example/a';

  -- newer job updates crawler-owned title.
  DECLARE r3 uuid; j3 uuid; tok3 uuid;
  BEGIN
    SELECT audit_run_id, crawl_job_id INTO r3, j3 FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-new', NULL);
    SELECT lease_token INTO tok3 FROM public.seo_crawl_claim_job('worker-G3', 120);
    PERFORM public.seo_crawl_worker_record_snapshots(j3,'worker-G3',tok3,
      '[{"requestedUrl":"https://phase16g-verify.example/a","httpStatus":200,"decodeStatus":"ok","titleCount":1,"title":"A-NEW","effectiveIndex":true,"wordCount":80,"contentHash":"h2b","extractionStatus":"extracted","extractorVersion":"1.0.0"}]'::jsonb);
    PERFORM public.seo_crawl_worker_publish_results(j3,'worker-G3',tok3,1);
    IF (SELECT page_title FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid AND page_url='https://phase16g-verify.example/a') <> 'A-NEW'
      THEN RAISE EXCEPTION 'STALE: newer crawl did not update'; END IF;
    UPDATE public.seo_crawl_jobs SET status='completed' WHERE id=j3;

    -- older crawl (extracted_at in the past) must NOT overwrite the newer title.
    DECLARE r4 uuid; j4 uuid; tok4 uuid;
    BEGIN
      SELECT audit_run_id, crawl_job_id INTO r4, j4 FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-old', NULL);
      SELECT lease_token INTO tok4 FROM public.seo_crawl_claim_job('worker-G4', 120);
      PERFORM public.seo_crawl_worker_record_snapshots(j4,'worker-G4',tok4,
        '[{"requestedUrl":"https://phase16g-verify.example/a","httpStatus":200,"decodeStatus":"ok","titleCount":1,"title":"A-STALE","effectiveIndex":true,"wordCount":5,"contentHash":"h2c","extractionStatus":"extracted","extractorVersion":"1.0.0"}]'::jsonb);
      UPDATE public.seo_crawl_page_snapshots SET extracted_at = now() - interval '5 days' WHERE job_id=j4;
      PERFORM public.seo_crawl_worker_publish_results(j4,'worker-G4',tok4,1);
      IF (SELECT page_title FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid AND page_url='https://phase16g-verify.example/a') <> 'A-NEW'
        THEN RAISE EXCEPTION 'STALE: older crawl overwrote newer data'; END IF;
      UPDATE public.seo_crawl_jobs SET status='completed' WHERE id=j4;
    END;
  END;

  -- no Page Performance write occurred.
  IF (SELECT count(*)::text FROM public.seo_page_performance_snapshots) <> current_setting('g.base_perf')
    THEN RAISE EXCEPTION 'PI: page performance snapshots changed'; END IF;
  -- seed website inventory unchanged (isolation).
  IF (SELECT count(*)::text FROM public.seo_page_inventory WHERE website_id=current_setting('g.seedsite')::uuid AND is_active) <> current_setting('g.base_seedpages')
    THEN RAISE EXCEPTION 'PI: seed inventory changed'; END IF;
  RAISE NOTICE 'PAGE-INVENTORY ok';
END $t$;

-- ===========================================================================
-- 5. AUDIT ISSUE PUBLISHING (mapping, scope, provenance, idempotency, manual).
-- ===========================================================================
DO $t$
DECLARE r uuid; j uuid; tok uuid; res jsonb; s_a uuid; s_home uuid; n int; sib uuid;
BEGIN
  PERFORM public._seo16g_login(current_setting('g.owner')::uuid);
  SELECT audit_run_id, crawl_job_id INTO r, j FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-ai', NULL);
  SELECT lease_token INTO tok FROM public.seo_crawl_claim_job('worker-GA', 120);

  PERFORM public.seo_crawl_worker_record_snapshots(j,'worker-GA',tok,
    '[{"requestedUrl":"https://phase16g-verify.example/","httpStatus":200,"decodeStatus":"ok","titleCount":1,"title":"Home","effectiveIndex":true,"wordCount":300,"contentHash":"z1","extractionStatus":"extracted","extractorVersion":"1.0.0"},
      {"requestedUrl":"https://phase16g-verify.example/a","httpStatus":200,"decodeStatus":"ok","titleCount":0,"effectiveIndex":true,"wordCount":10,"contentHash":"z2","extractionStatus":"extracted","extractorVersion":"1.0.0"}]'::jsonb);
  SELECT id INTO s_a    FROM public.seo_crawl_page_snapshots WHERE job_id=j AND requested_url='https://phase16g-verify.example/a';
  SELECT id INTO s_home FROM public.seo_crawl_page_snapshots WHERE job_id=j AND requested_url='https://phase16g-verify.example/';

  -- page issues: TITLE_MISSING(error), CANONICAL_MISSING(info) on /a ; LOW_CONTENT(info) on /a
  PERFORM public.seo_crawl_worker_record_issues(j,'worker-GA',tok,
    '[{"code":"TITLE_MISSING","category":"metadata","severity":"error","scope":"page","ruleVersion":"1.0.0","fingerprint":"https://phase16g-verify.example/a"},
      {"code":"CANONICAL_MISSING","category":"canonical","severity":"info","scope":"page","ruleVersion":"1.0.0","fingerprint":"https://phase16g-verify.example/a"},
      {"code":"LOW_CONTENT","category":"content","severity":"info","scope":"page","ruleVersion":"1.0.0","fingerprint":"https://phase16g-verify.example/a"}]'::jsonb, s_a);
  -- site issue: DUPLICATE_TITLE(warning)
  PERFORM public.seo_crawl_worker_record_issues(j,'worker-GA',tok,
    '[{"code":"DUPLICATE_TITLE","category":"duplicate","severity":"warning","scope":"site","ruleVersion":"1.0.0","fingerprint":"grpX","evidence":{"pageCount":2}}]'::jsonb, NULL);

  -- pre-existing MANUAL audit issue in the same run (must be preserved + never counted as crawler).
  INSERT INTO public.seo_audit_issues (workspace_id, website_id, website_url, audit_run_id, category, severity,
    title, simple_explanation, why_it_matters, technical_explanation, affected_page_url, impact, effort, risk,
    confidence_percentage, fix_owner, suggested_next_action, status)
  VALUES (current_setting('g.ws')::uuid, current_setting('g.web')::uuid, 'https://phase16g-verify.example', r,
    'speed','high','MANUAL ISSUE','x','y','z','https://phase16g-verify.example/', 'high','low','low',
    50,'developer_needed','do it','open');

  res := public.seo_crawl_worker_publish_results(j,'worker-GA',tok,1);
  IF res->>'status' <> 'published' THEN RAISE EXCEPTION 'AI: publish status %', res->>'status'; END IF;
  IF (res->>'issuesEligible')::int <> 4 THEN RAISE EXCEPTION 'AI: eligible %', res->>'issuesEligible'; END IF;
  IF (res->>'issuesPublished')::int <> 4 THEN RAISE EXCEPTION 'AI: published %', res->>'issuesPublished'; END IF;

  -- severity + category mapping (error->high crawl; warning->medium duplicate_content; info->low canonical high-risk).
  IF NOT EXISTS (SELECT 1 FROM public.seo_audit_issues WHERE audit_run_id=r AND source='crawler'
      AND source_issue_fingerprint='TITLE_MISSING::https://phase16g-verify.example/a'
      AND category='crawl' AND severity='high' AND affected_page_url='https://phase16g-verify.example/a'
      AND issue_scope='page' AND source_severity='error' AND source_category='metadata'
      AND source_rule_version='1.0.0' AND is_high_risk_category=false)
    THEN RAISE EXCEPTION 'AI: TITLE_MISSING mapping wrong'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.seo_audit_issues WHERE audit_run_id=r AND source='crawler'
      AND source_issue_fingerprint='CANONICAL_MISSING::https://phase16g-verify.example/a'
      AND category='canonical' AND severity='low' AND is_high_risk_category=true)
    THEN RAISE EXCEPTION 'AI: CANONICAL_MISSING mapping/high-risk wrong'; END IF;
  -- site issue: no fabricated page — affected_page_url is the real website_url, scope=site.
  IF NOT EXISTS (SELECT 1 FROM public.seo_audit_issues WHERE audit_run_id=r AND source='crawler'
      AND source_issue_fingerprint='DUPLICATE_TITLE::grpX' AND category='duplicate_content'
      AND severity='medium' AND issue_scope='site' AND affected_page_url='https://phase16g-verify.example')
    THEN RAISE EXCEPTION 'AI: site DUPLICATE_TITLE representation wrong'; END IF;

  -- idempotent replay: no duplicate crawler issues.
  PERFORM public.seo_crawl_worker_publish_results(j,'worker-GA',tok,1);
  SELECT count(*) INTO n FROM public.seo_audit_issues WHERE audit_run_id=r AND source='crawler';
  IF n <> 4 THEN RAISE EXCEPTION 'AI: replay duplicated crawler issues (%)', n; END IF;
  -- manual issue preserved + not relabelled.
  IF NOT EXISTS (SELECT 1 FROM public.seo_audit_issues WHERE audit_run_id=r AND title='MANUAL ISSUE' AND source IS NULL)
    THEN RAISE EXCEPTION 'AI: manual issue altered/removed'; END IF;
  -- audit run completed honestly; issue_count = all issues (4 crawler + 1 manual); scores untouched (still 0).
  IF (SELECT status FROM public.seo_audit_runs WHERE id=r) <> 'completed'
     OR (SELECT issue_count FROM public.seo_audit_runs WHERE id=r) <> 5
     OR (SELECT overall_visibility_score FROM public.seo_audit_runs WHERE id=r) <> 0
    THEN RAISE EXCEPTION 'AI: audit run status/count/score wrong'; END IF;

  -- a sibling run for the same website is NOT touched.
  INSERT INTO public.seo_audit_runs (workspace_id, website_id, website_url, status, is_latest)
    VALUES (current_setting('g.ws')::uuid, current_setting('g.web')::uuid, 'https://phase16g-verify.example', 'running', false)
    RETURNING id INTO sib;
  PERFORM public.seo_crawl_worker_publish_results(j,'worker-GA',tok,1);  -- replay again
  IF (SELECT status FROM public.seo_audit_runs WHERE id=sib) <> 'running'
    THEN RAISE EXCEPTION 'AI: sibling run mutated'; END IF;

  -- NO recommendation rows created anywhere.
  IF (SELECT count(*)::text FROM public.seo_recommendations) <> current_setting('g.base_recs')
    THEN RAISE EXCEPTION 'AI: recommendations changed'; END IF;
  -- seed website audit issues unchanged.
  IF (SELECT count(*)::text FROM public.seo_audit_issues WHERE website_id=current_setting('g.seedsite')::uuid) <> current_setting('g.base_seedissues')
    THEN RAISE EXCEPTION 'AI: seed audit issues changed'; END IF;

  UPDATE public.seo_crawl_jobs SET status='completed' WHERE id=j;
  RAISE NOTICE 'AUDIT-ISSUE ok';
END $t$;

-- ===========================================================================
-- 6. TRANSACTIONALITY — a mid-publish failure rolls back ALL product writes.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public._seo16g_boom() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN RAISE EXCEPTION 'boom (induced audit-issue failure)'; END $fn$;

DO $t$
DECLARE r uuid; j uuid; tok uuid; s uuid; ok boolean; turl text := 'https://phase16g-verify.example/txn';
BEGIN
  PERFORM public._seo16g_login(current_setting('g.owner')::uuid);
  SELECT audit_run_id, crawl_job_id INTO r, j FROM public.seo_crawl_request_audit(current_setting('g.web')::uuid, 'PHASE16G-txn', NULL);
  SELECT lease_token INTO tok FROM public.seo_crawl_claim_job('worker-GT', 120);
  PERFORM public.seo_crawl_worker_record_snapshots(j,'worker-GT',tok, format('[{"requestedUrl":"%s","httpStatus":200,"decodeStatus":"ok","titleCount":0,"effectiveIndex":true,"wordCount":5,"contentHash":"t1","extractionStatus":"extracted","extractorVersion":"1.0.0"}]', turl)::jsonb);
  SELECT id INTO s FROM public.seo_crawl_page_snapshots WHERE job_id=j AND requested_url=turl;
  PERFORM public.seo_crawl_worker_record_issues(j,'worker-GT',tok,
    ('[{"code":"TITLE_MISSING","category":"metadata","severity":"error","scope":"page","ruleVersion":"1.0.0","fingerprint":"'||turl||'"}]')::jsonb, s);

  CREATE TRIGGER trg_seo16g_boom BEFORE INSERT ON public.seo_audit_issues
    FOR EACH ROW EXECUTE FUNCTION public._seo16g_boom();

  ok:=false;
  BEGIN PERFORM public.seo_crawl_worker_publish_results(j,'worker-GT',tok,1);
  EXCEPTION WHEN OTHERS THEN ok:=true; END;  -- savepoint rolls back the whole publish
  IF NOT ok THEN RAISE EXCEPTION 'TXN: induced failure did not raise'; END IF;

  DROP TRIGGER trg_seo16g_boom ON public.seo_audit_issues;

  -- The page-inventory row written before the failing audit insert must be gone.
  IF EXISTS (SELECT 1 FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid AND page_url=turl)
    THEN RAISE EXCEPTION 'TXN: partial page-inventory write survived rollback'; END IF;
  -- No publication marked successful.
  IF EXISTS (SELECT 1 FROM public.seo_crawl_publications WHERE job_id=j AND status='published')
    THEN RAISE EXCEPTION 'TXN: publication marked published after failure'; END IF;
  UPDATE public.seo_crawl_jobs SET status='completed' WHERE id=j;
  RAISE NOTICE 'TRANSACTIONALITY ok';
END $t$;

-- ===========================================================================
-- 7. RLS — member reads published data; customer cannot write / invoke publish;
--    non-member cannot read.
-- ===========================================================================
SET LOCAL ROLE authenticated;
DO $t$
DECLARE n int; ok boolean;
BEGIN
  PERFORM public._seo16g_login(current_setting('g.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_crawl_publications WHERE website_id=current_setting('g.web')::uuid;
  IF n < 1 THEN RAISE EXCEPTION 'RLS: member cannot read publications'; END IF;
  SELECT count(*) INTO n FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid AND is_active;
  IF n < 3 THEN RAISE EXCEPTION 'RLS: member cannot read published inventory'; END IF;
  SELECT count(*) INTO n FROM public.seo_audit_issues WHERE website_id=current_setting('g.web')::uuid AND source='crawler';
  IF n < 4 THEN RAISE EXCEPTION 'RLS: member cannot read published issues'; END IF;
  -- customer cannot insert a publication row.
  ok:=false;
  BEGIN INSERT INTO public.seo_crawl_publications (job_id,audit_run_id,workspace_id,website_id,publication_version)
    VALUES (gen_random_uuid(),gen_random_uuid(),current_setting('g.ws')::uuid,current_setting('g.web')::uuid,1);
  EXCEPTION WHEN OTHERS THEN ok:=true; END;
  IF NOT ok THEN RAISE EXCEPTION 'RLS: authenticated inserted a publication'; END IF;
  -- customer cannot invoke the worker publish RPC (grant denied).
  IF has_function_privilege('public.seo_crawl_worker_publish_results(uuid,text,uuid,integer)','EXECUTE')
    THEN RAISE EXCEPTION 'RLS: authenticated can execute worker publish'; END IF;
END $t$;

DO $t$
DECLARE n int;
BEGIN
  PERFORM public._seo16g_login(current_setting('g.nonmember')::uuid);
  SELECT count(*) INTO n FROM public.seo_crawl_publications WHERE website_id=current_setting('g.web')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'RLS: non-member read publications (%)', n; END IF;
  SELECT count(*) INTO n FROM public.seo_page_inventory WHERE website_id=current_setting('g.web')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'RLS: non-member read inventory (%)', n; END IF;
END $t$;
RESET ROLE;

-- ===========================================================================
-- 8. CLEANUP + INVARIANTS
-- ===========================================================================
DO $t$
BEGIN
  DELETE FROM public.seo_ownership_verifications WHERE challenge_token = 'P1B-FIXTURE-TOKEN';  -- P1b fixture (also cascade-removed with g.web below)
  DELETE FROM public.seo_websites  WHERE id IN (current_setting('g.web')::uuid, current_setting('g.wother')::uuid);
  DELETE FROM public.seo_workspaces WHERE id = current_setting('g.ws2')::uuid;  -- cascades foreign ws/website

  IF (SELECT count(*) FROM public.seo_crawl_jobs WHERE idempotency_key LIKE 'PHASE16G-%') <> 0
    THEN RAISE EXCEPTION 'CLEANUP: residual crawl jobs'; END IF;
  IF (SELECT count(*)::text FROM public.seo_page_inventory WHERE website_id=current_setting('g.seedsite')::uuid AND is_active) <> current_setting('g.base_seedpages')
    THEN RAISE EXCEPTION 'CLEANUP: seed inventory changed'; END IF;
  IF (SELECT count(*)::text FROM public.seo_audit_issues WHERE website_id=current_setting('g.seedsite')::uuid) <> current_setting('g.base_seedissues')
    THEN RAISE EXCEPTION 'CLEANUP: seed audit issues changed'; END IF;
  IF (SELECT count(*)::text FROM public.seo_recommendations) <> current_setting('g.base_recs')
    THEN RAISE EXCEPTION 'CLEANUP: recommendations changed'; END IF;
  IF (SELECT count(*)::text FROM public.seo_page_performance_snapshots) <> current_setting('g.base_perf')
    THEN RAISE EXCEPTION 'CLEANUP: page performance changed'; END IF;
  RAISE NOTICE 'CLEANUP ok';
END $t$;

DROP FUNCTION IF EXISTS public._seo16g_boom();
DROP FUNCTION IF EXISTS public._seo16g_login(uuid);

SELECT 'PHASE 16G VERIFICATION: ALL PASS' AS result;
