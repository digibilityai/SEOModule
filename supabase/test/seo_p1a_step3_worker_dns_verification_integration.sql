-- =============================================================================
-- SEO P1a Step 3 — DNS-TXT verification worker ↔ Step 2B RPC — TEST INTEGRATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER migrations
-- 20260716120031/120032/120033 are applied.
--
-- WHAT THIS PROVES: the exact claim → result → audit flow the DNS-TXT worker
-- performs, exercised through the REAL Step 2B RPCs
-- (`seo_ownership_verification_claim` / `record_result`) with a DETERMINISTIC,
-- script-simulated resolver decision (match → verified; not-found → failed) —
-- so no dependency on live public DNS. The worker↔RPC wiring (runner + gateway)
-- is separately proven by the Node test `test/ownershipVerification.test.ts`.
--
-- EXECUTION MODEL: single-transaction runner (no BEGIN/COMMIT). Runs as
-- `postgres`, which may call the service_role-only RPCs (superuser) to simulate
-- the worker; the acting customer (owner) is switched via jwt claims. All
-- fixtures (disposable websites af…b1/b2) are removed in teardown → net-nothing.
-- No service-role key is used or printed.
-- =============================================================================

SELECT set_config('i3.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('i3.site1', 'af000000-0000-0000-0002-0000000000b1', false);  -- match → verified
SELECT set_config('i3.site2', 'af000000-0000-0000-0002-0000000000b2', false);  -- not-found → failed
SELECT set_config('i3.owner', '48c479db-aedf-452e-af43-05ed1180baaa', false);

CREATE OR REPLACE FUNCTION public._seo_i3_login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END $fn$;

-- baseline: NO crawl / audit / page / recommendation / Stage 6 row may change
SELECT set_config('i3.b_jobs',   (SELECT count(*)::text FROM public.seo_crawl_jobs), false);
SELECT set_config('i3.b_att',    (SELECT count(*)::text FROM public.seo_crawl_attempts), false);
SELECT set_config('i3.b_evt',    (SELECT count(*)::text FROM public.seo_crawl_events), false);
SELECT set_config('i3.b_issues', (SELECT count(*)::text FROM public.seo_audit_issues), false);
SELECT set_config('i3.b_inv',    (SELECT count(*)::text FROM public.seo_page_inventory), false);
SELECT set_config('i3.b_perf',   (SELECT count(*)::text FROM public.seo_page_performance_snapshots), false);
SELECT set_config('i3.b_rec',    (SELECT count(*)::text FROM public.seo_recommendations), false);
SELECT set_config('i3.b_opp',    (SELECT count(*)::text FROM public.seo_authority_opportunities), false);

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES
 (current_setting('i3.site1')::uuid, current_setting('i3.workspace')::uuid, 'https://p1a-step3-ok.example',   'P1A S3 OK',   'P1A S3', 'other','pending',true),
 (current_setting('i3.site2')::uuid, current_setting('i3.workspace')::uuid, 'https://p1a-step3-fail.example', 'P1A S3 Fail', 'P1A S3', 'other','pending',true)
ON CONFLICT (id) DO NOTHING;

-- ---------- MATCH path → verified -------------------------------------------
DO $t$
DECLARE v_site uuid := current_setting('i3.site1')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; cl record; vid uuid; t0 text; ev int;
BEGIN
  PERFORM public._seo_i3_login(current_setting('i3.owner')::uuid);
  -- customer initiates (real Step 2A RPC) → pending challenge
  r := public.seo_ownership_verification_initiate(v_site);
  vid := r.id; t0 := r.challenge_token;

  -- WORKER: claim (real Step 2B service-role RPC)
  SELECT * INTO cl FROM public.seo_ownership_verification_claim('p1a-step3-int', 120);
  IF cl.verification_id <> vid THEN RAISE EXCEPTION 'INT: claim did not return the pending item'; END IF;
  IF cl.expected_challenge_value <> t0 THEN RAISE EXCEPTION 'INT: expected value != challenge token'; END IF;
  IF cl.dns_txt_name <> '_digibility-site-verification.p1a-step3-ok.example' THEN RAISE EXCEPTION 'INT: dns_txt_name wrong (%)', cl.dns_txt_name; END IF;

  -- WORKER decision: DNS TXT contains an exact match (deterministic, simulated) → verified
  r := public.seo_ownership_verification_record_result(vid, 'p1a-step3-int', cl.lease_token, 'verified', NULL, NULL, NULL);
  IF r.status <> 'verified' THEN RAISE EXCEPTION 'INT: status % (expected verified)', r.status; END IF;
  IF r.verified_at IS NULL THEN RAISE EXCEPTION 'INT: verified_at not set'; END IF;
  IF r.challenge_token <> t0 THEN RAISE EXCEPTION 'INT: challenge token changed on verify'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid AND event_type='verified';
  IF ev <> 1 THEN RAISE EXCEPTION 'INT: expected 1 verified audit event, got %', ev; END IF;
  RAISE NOTICE 'INT verified path ok';
END $t$;

-- ---------- NOT-FOUND path → failed (customer-safe reason + internal diag) ---
DO $t$
DECLARE v_site uuid := current_setting('i3.site2')::uuid;
        r public.seo_ownership_verifications%ROWTYPE; cl record; vid uuid; t0 text; ev int;
        v_intcode text; v_intdetail text;
BEGIN
  PERFORM public._seo_i3_login(current_setting('i3.owner')::uuid);
  r := public.seo_ownership_verification_initiate(v_site);
  vid := r.id; t0 := r.challenge_token;

  SELECT * INTO cl FROM public.seo_ownership_verification_claim('p1a-step3-int', 120);
  IF cl.verification_id <> vid THEN RAISE EXCEPTION 'INT: claim(fail) did not return the pending item'; END IF;

  -- WORKER decision: record not found → failed with customer-safe reason +
  -- internal diagnostics (as the runner would map dns_not_found).
  r := public.seo_ownership_verification_record_result(
         vid, 'p1a-step3-int', cl.lease_token, 'failed',
         'The DNS TXT record was not found. Add the record and re-check.',
         'dns_not_found', 'dns not_found');
  IF r.status <> 'failed' THEN RAISE EXCEPTION 'INT: status % (expected failed)', r.status; END IF;
  IF r.failure_reason <> 'The DNS TXT record was not found. Add the record and re-check.' THEN
    RAISE EXCEPTION 'INT: customer-safe failure_reason not persisted'; END IF;
  IF r.challenge_token <> t0 THEN RAISE EXCEPTION 'INT: challenge token changed on fail'; END IF;
  SELECT count(*) INTO ev FROM public.seo_ownership_verification_events WHERE verification_id=vid AND event_type='failed';
  IF ev <> 1 THEN RAISE EXCEPTION 'INT: expected 1 failed audit event, got %', ev; END IF;

  -- internal diagnostics stored on the (global-admin-only) claim row, NOT on the
  -- customer-safe verification row.
  SELECT internal_error_code, internal_error_detail INTO v_intcode, v_intdetail
  FROM public.seo_ownership_verification_claims
  WHERE verification_id=vid AND worker_id='p1a-step3-int' AND outcome='failed';
  IF v_intcode <> 'dns_not_found' THEN RAISE EXCEPTION 'INT: internal_error_code not stored on claim row'; END IF;
  RAISE NOTICE 'INT failed path ok';
END $t$;

-- ---------- internal diagnostics NOT customer-readable -----------------------
SET LOCAL ROLE authenticated;
SELECT public._seo_i3_login('48c479db-aedf-452e-af43-05ed1180baaa'::uuid);  -- owner (member)
DO $t$
DECLARE n int;
BEGIN
  PERFORM public._seo_i3_login(current_setting('i3.owner')::uuid);
  SELECT count(*) INTO n FROM public.seo_ownership_verification_claims
   WHERE website_id IN (current_setting('i3.site1')::uuid, current_setting('i3.site2')::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'INT: internal claim/lease rows are customer-readable (%)', n; END IF;
END $t$;
RESET ROLE;

-- ---------- TEARDOWN + no-other-module-change assertions ---------------------
DELETE FROM public.seo_ownership_verifications
 WHERE website_id IN (current_setting('i3.site1')::uuid, current_setting('i3.site2')::uuid);  -- cascade claims + events
DELETE FROM public.seo_websites
 WHERE id IN (current_setting('i3.site1')::uuid, current_setting('i3.site2')::uuid);
DROP FUNCTION IF EXISTS public._seo_i3_login(uuid);

DO $t$
DECLARE nv int; nw int;
BEGIN
  SELECT count(*) INTO nv FROM public.seo_ownership_verifications
   WHERE website_id IN ('af000000-0000-0000-0002-0000000000b1','af000000-0000-0000-0002-0000000000b2');
  SELECT count(*) INTO nw FROM public.seo_websites
   WHERE id IN ('af000000-0000-0000-0002-0000000000b1','af000000-0000-0000-0002-0000000000b2');
  IF nv+nw <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual verifications=% websites=%', nv, nw; END IF;

  IF (SELECT count(*) FROM public.seo_crawl_jobs)                 <> current_setting('i3.b_jobs')::int   THEN RAISE EXCEPTION 'ISO: seo_crawl_jobs changed'; END IF;
  IF (SELECT count(*) FROM public.seo_crawl_attempts)             <> current_setting('i3.b_att')::int    THEN RAISE EXCEPTION 'ISO: seo_crawl_attempts changed'; END IF;
  IF (SELECT count(*) FROM public.seo_crawl_events)               <> current_setting('i3.b_evt')::int    THEN RAISE EXCEPTION 'ISO: seo_crawl_events changed'; END IF;
  IF (SELECT count(*) FROM public.seo_audit_issues)               <> current_setting('i3.b_issues')::int THEN RAISE EXCEPTION 'ISO: seo_audit_issues changed'; END IF;
  IF (SELECT count(*) FROM public.seo_page_inventory)             <> current_setting('i3.b_inv')::int    THEN RAISE EXCEPTION 'ISO: seo_page_inventory changed'; END IF;
  IF (SELECT count(*) FROM public.seo_page_performance_snapshots) <> current_setting('i3.b_perf')::int   THEN RAISE EXCEPTION 'ISO: seo_page_performance_snapshots changed'; END IF;
  IF (SELECT count(*) FROM public.seo_recommendations)            <> current_setting('i3.b_rec')::int    THEN RAISE EXCEPTION 'ISO: seo_recommendations changed'; END IF;
  IF (SELECT count(*) FROM public.seo_authority_opportunities)    <> current_setting('i3.b_opp')::int    THEN RAISE EXCEPTION 'ISO: seo_authority_opportunities changed'; END IF;
  RAISE NOTICE 'TEARDOWN + no-other-module-change ok';
END $t$;

SELECT 'ALL PASS — seo_p1a_step3 worker DNS-verification TEST integration complete' AS result;
