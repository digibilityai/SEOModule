-- =============================================================================
-- SEO P1b — Verified-only Crawl Enqueue Enforcement — VERIFICATION
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on Digi_SEO_Test (ref snyzotgwwfomgafrsvfm), AFTER the P1b migration
-- 20260719120034_seo_p1b_verified_only_crawl_enqueue.sql is applied (and after
-- P1a migrations 20260716120031/120032/120033).
--
-- EXECUTION MODEL (same as Phase 16C): the `supabase db query --linked -f` runner
-- wraps the whole file in ONE transaction; NO explicit BEGIN/COMMIT. Runs as the
-- `postgres` connection role; the acting SEO user is switched via jwt claims
-- (set_config). seo_crawl_request / seo_crawl_request_audit are SECURITY DEFINER
-- and read auth.uid() from the jwt claims, so jwt-login alone exercises them.
--
-- PREREQUISITE: the five shared TEST auth users exist (owner/admin/team/client/
-- nonmember) and are members of the seed workspace 44444444-…-0001-…01 with their
-- respective roles.
--
-- FIXTURES: disposable websites (prefix b1b00000-) in the seed workspace, plus a
-- disposable foreign workspace/website for the cross-workspace case. Ownership
-- fixtures are token-marked ('P1B-VERIFY-TOKEN'). All fixtures are removed in
-- teardown → a successful run commits net-nothing. No password/secret/challenge
-- value of any real domain is used.
--
-- CONCURRENCY NOTE (case 9): the single-transaction runner cannot execute a true
-- two-session race, so this script STATICALLY proves the FOR SHARE lock + guard
-- are present in the deployed function (not a faked sequential race). The runnable
-- two-session (Session A / Session B) race procedure is in the companion guide
-- P1B_CONCURRENCY_VERIFICATION_GUIDE.md.
-- =============================================================================

-- ---------- 0. Fixture ids + jwt-claims login helper -------------------------
SELECT set_config('p1b.workspace', '44444444-0000-0000-0001-000000000001', false);
SELECT set_config('p1b.verified',  'b1b00000-0000-0000-0002-000000000001', false);  -- verified (direct)
SELECT set_config('p1b.verified2', 'b1b00000-0000-0000-0002-000000000002', false);  -- verified (audit path)
SELECT set_config('p1b.pending',   'b1b00000-0000-0000-0002-000000000003', false);  -- pending  → blocked
SELECT set_config('p1b.failed',    'b1b00000-0000-0000-0002-000000000004', false);  -- failed   → blocked
SELECT set_config('p1b.revoked',   'b1b00000-0000-0000-0002-000000000005', false);  -- revoked  → blocked
SELECT set_config('p1b.missing',   'b1b00000-0000-0000-0002-000000000006', false);  -- no row   → blocked
SELECT set_config('p1b.fws',       'b1b00000-0000-0000-0001-0000000000f1', false);  -- foreign workspace
SELECT set_config('p1b.fsite',     'b1b00000-0000-0000-0002-0000000000f2', false);  -- foreign verified site
SELECT set_config('p1b.owner',     '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('p1b.admin',     '9830c4d7-167b-4d78-9179-37b60511bd73', false);
SELECT set_config('p1b.team',      '0723d21f-c02c-4725-851f-575f93f2f58c', false);
SELECT set_config('p1b.client',    '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('p1b.nonmember', '8ae3b67e-6f00-4e10-905c-3a76281ffde9', false);

CREATE OR REPLACE FUNCTION public._seo_p1b_login(p_uid uuid)
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

-- ---------- 1. CONTRACT: signature / return / grants UNCHANGED ---------------
DO $t$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='seo_crawl_request'
       AND pg_get_function_identity_arguments(p.oid)='p_website_id uuid, p_idempotency_key text, p_config jsonb'
       AND pg_get_function_result(p.oid)='uuid'
       AND p.prosecdef  -- SECURITY DEFINER preserved
  ) THEN RAISE EXCEPTION 'CONTRACT: seo_crawl_request signature/return/security mode changed'; END IF;

  IF NOT has_function_privilege('authenticated','public.seo_crawl_request(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.seo_crawl_request(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT: seo_crawl_request grants changed (authenticated must; anon must NOT)'; END IF;

  IF NOT has_function_privilege('authenticated','public.seo_crawl_request_audit(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.seo_crawl_request_audit(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT: seo_crawl_request_audit grants changed'; END IF;
  RAISE NOTICE 'CONTRACT ok';
END $t$;

-- ---------- 2. GUARD + FOR SHARE present in the deployed function ------------
DO $t$
DECLARE v_def text := pg_get_functiondef('public.seo_crawl_request(uuid,text,jsonb)'::regprocedure);
BEGIN
  IF position('Domain ownership must be verified' IN v_def) = 0 THEN
    RAISE EXCEPTION 'GUARD: verified-ownership rejection message missing from seo_crawl_request'; END IF;
  IF position('FOR SHARE' IN v_def) = 0 THEN
    RAISE EXCEPTION 'CONCURRENCY: FOR SHARE ownership lock missing from seo_crawl_request'; END IF;
  IF position('seo_ownership_verifications' IN v_def) = 0 THEN
    RAISE EXCEPTION 'GUARD: seo_crawl_request does not reference seo_ownership_verifications'; END IF;
  RAISE NOTICE 'GUARD + FOR SHARE present ok';
END $t$;

-- ---------- 3. Fixtures (disposable websites + ownership states) -------------
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES
 (current_setting('p1b.verified')::uuid,  current_setting('p1b.workspace')::uuid, 'https://p1b-verified.example',  'P1B Verified',  'P1B', 'other','pending',true),
 (current_setting('p1b.verified2')::uuid, current_setting('p1b.workspace')::uuid, 'https://p1b-verified2.example', 'P1B Verified2', 'P1B', 'other','pending',true),
 (current_setting('p1b.pending')::uuid,   current_setting('p1b.workspace')::uuid, 'https://p1b-pending.example',   'P1B Pending',   'P1B', 'other','pending',true),
 (current_setting('p1b.failed')::uuid,    current_setting('p1b.workspace')::uuid, 'https://p1b-failed.example',    'P1B Failed',    'P1B', 'other','pending',true),
 (current_setting('p1b.revoked')::uuid,   current_setting('p1b.workspace')::uuid, 'https://p1b-revoked.example',   'P1B Revoked',   'P1B', 'other','pending',true),
 (current_setting('p1b.missing')::uuid,   current_setting('p1b.workspace')::uuid, 'https://p1b-missing.example',   'P1B Missing',   'P1B', 'other','pending',true)
ON CONFLICT (id) DO NOTHING;

-- foreign workspace (owned by nonmember → seed owner is NOT a member) + verified site
INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES (current_setting('p1b.fws')::uuid, 'P1B-Foreign', current_setting('p1b.nonmember')::uuid)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name, website_type, setup_status, is_active)
VALUES (current_setting('p1b.fsite')::uuid, current_setting('p1b.fws')::uuid, 'https://p1b-foreign.example', 'P1B Foreign', 'P1B', 'other','pending',true)
ON CONFLICT (id) DO NOTHING;

-- ownership rows: verified for verified/verified2/foreign; pending/failed/revoked; NONE for missing
INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status, challenge_token, verified_at)
SELECT w.workspace_id, w.id, w.website_url, 'p1b-verify.example', 'dns_txt',
       CASE
         WHEN w.id = current_setting('p1b.pending')::uuid THEN 'pending'
         WHEN w.id = current_setting('p1b.failed')::uuid  THEN 'failed'
         WHEN w.id = current_setting('p1b.revoked')::uuid THEN 'revoked'
         ELSE 'verified'
       END,
       'P1B-VERIFY-TOKEN',
       CASE WHEN w.id IN (current_setting('p1b.pending')::uuid, current_setting('p1b.failed')::uuid, current_setting('p1b.revoked')::uuid)
            THEN NULL ELSE now() END
  FROM public.seo_websites w
 WHERE w.id IN (current_setting('p1b.verified')::uuid, current_setting('p1b.verified2')::uuid,
                current_setting('p1b.pending')::uuid, current_setting('p1b.failed')::uuid,
                current_setting('p1b.revoked')::uuid, current_setting('p1b.fsite')::uuid)
ON CONFLICT (website_id, method) DO UPDATE
  SET status=EXCLUDED.status, challenge_token='P1B-VERIFY-TOKEN', verified_at=EXCLUDED.verified_at, updated_at=now();

-- ---------- 4. VERIFIED → enqueue succeeds (direct + idempotency + event) ----
DO $t$
DECLARE v_site uuid := current_setting('p1b.verified')::uuid; j1 uuid; j2 uuid; n int;
BEGIN
  PERFORM public._seo_p1b_login(current_setting('p1b.owner')::uuid);
  -- direct success
  j1 := public.seo_crawl_request(v_site, 'P1B-idem', NULL);
  IF j1 IS NULL THEN RAISE EXCEPTION 'VERIFIED: direct seo_crawl_request returned NULL'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE id=j1 AND website_id=v_site AND status='queued';
  IF n <> 1 THEN RAISE EXCEPTION 'VERIFIED: crawl job not created queued'; END IF;
  -- exactly one 'queued' event (unchanged behaviour)
  SELECT count(*) INTO n FROM public.seo_crawl_events WHERE job_id=j1 AND event_type='queued';
  IF n <> 1 THEN RAISE EXCEPTION 'VERIFIED: expected exactly 1 queued event, got %', n; END IF;
  -- idempotency: same key returns the same job, no second job
  j2 := public.seo_crawl_request(v_site, 'P1B-idem', NULL);
  IF j2 <> j1 THEN RAISE EXCEPTION 'COMPAT: idempotent repeat returned a different job'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE website_id=v_site;
  IF n <> 1 THEN RAISE EXCEPTION 'COMPAT: idempotency created a duplicate job (% jobs)', n; END IF;
  RAISE NOTICE 'VERIFIED direct + idempotency + event ok';
END $t$;

-- 4b. single-active-job unchanged: a DIFFERENT key while active is rejected
DO $t$
DECLARE v_site uuid := current_setting('p1b.verified')::uuid; ok boolean := false; v_msg text;
BEGIN
  PERFORM public._seo_p1b_login(current_setting('p1b.owner')::uuid);
  BEGIN
    PERFORM public.seo_crawl_request(v_site, 'P1B-idem-2', NULL);
  EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
  IF NOT ok THEN RAISE EXCEPTION 'COMPAT: single-active-job not enforced'; END IF;
  IF position('active crawl already exists' IN v_msg) = 0 THEN
    RAISE EXCEPTION 'COMPAT: wrong error for second active job: %', v_msg; END IF;
  RAISE NOTICE 'COMPAT single-active-job ok';
END $t$;

-- 4c. VERIFIED → seo_crawl_request_audit succeeds (separate site; job + run linked)
DO $t$
DECLARE v_site uuid := current_setting('p1b.verified2')::uuid; r record; n int;
BEGIN
  PERFORM public._seo_p1b_login(current_setting('p1b.owner')::uuid);
  SELECT audit_run_id, crawl_job_id, job_status INTO r
    FROM public.seo_crawl_request_audit(v_site, 'P1B-audit', NULL);
  IF r.audit_run_id IS NULL OR r.crawl_job_id IS NULL THEN
    RAISE EXCEPTION 'VERIFIED: request_audit did not return both ids'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE id=r.crawl_job_id AND audit_run_id=r.audit_run_id;
  IF n <> 1 THEN RAISE EXCEPTION 'VERIFIED: audit run not linked to crawl job'; END IF;
  RAISE NOTICE 'VERIFIED audit-path ok';
END $t$;

-- ---------- 5. NON-VERIFIED states → blocked (no job, no audit run) ----------
-- Helper: assert both entry points reject a site with the OWNERSHIP message and
-- create neither a crawl job nor an audit run.
DO $t$
DECLARE
  v_owner uuid := current_setting('p1b.owner')::uuid;
  arr text[] := ARRAY['p1b.pending','p1b.failed','p1b.revoked','p1b.missing'];
  k text; v_site uuid; ok boolean; v_msg text; n int; runs_before int; runs_after int;
BEGIN
  FOREACH k IN ARRAY arr LOOP
    v_site := current_setting(k)::uuid;
    PERFORM public._seo_p1b_login(v_owner);

    -- direct request rejects with the ownership message
    ok := false;
    BEGIN PERFORM public.seo_crawl_request(v_site, 'P1B-blk-'||k, NULL);
    EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
    IF NOT ok THEN RAISE EXCEPTION 'BLOCK %: direct request unexpectedly succeeded', k; END IF;
    IF position('Domain ownership must be verified' IN v_msg) = 0 THEN
      RAISE EXCEPTION 'BLOCK %: wrong rejection message: %', k, v_msg; END IF;

    -- audit orchestration rejects AND creates neither a job nor an audit run
    runs_before := (SELECT count(*) FROM public.seo_audit_runs WHERE website_id=v_site);
    ok := false;
    BEGIN PERFORM public.seo_crawl_request_audit(v_site, 'P1B-blk-audit-'||k, NULL);
    EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
    IF NOT ok THEN RAISE EXCEPTION 'BLOCK %: request_audit unexpectedly succeeded', k; END IF;
    IF position('Domain ownership must be verified' IN v_msg) = 0 THEN
      RAISE EXCEPTION 'BLOCK %: request_audit wrong message: %', k, v_msg; END IF;

    -- no crawl job created for this site
    SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE website_id=v_site;
    IF n <> 0 THEN RAISE EXCEPTION 'BLOCK %: a crawl job was created (%)', k, n; END IF;
    -- no orphan audit run created by the rejected orchestration (transaction rollback)
    runs_after := (SELECT count(*) FROM public.seo_audit_runs WHERE website_id=v_site);
    IF runs_after <> runs_before THEN
      RAISE EXCEPTION 'BLOCK %: orphan audit run created (% -> %)', k, runs_before, runs_after; END IF;
  END LOOP;
  RAISE NOTICE 'BLOCKED (pending/failed/revoked/missing) + no-orphan ok';
END $t$;

-- ---------- 6. AUTHORIZATION PRECEDENCE (verified site; authz/authn first) ----
-- On a VERIFIED site, unauthorized callers must fail on the EXISTING
-- authentication/authorization error, NOT on ownership (no ownership-state leak).
DO $t$
DECLARE v_site uuid := current_setting('p1b.verified')::uuid; ok boolean; v_msg text;
BEGIN
  -- anon → 'Not authenticated'
  PERFORM public._seo_p1b_login(NULL);
  ok := false;
  BEGIN PERFORM public.seo_crawl_request(v_site, 'P1B-anon', NULL);
  EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
  IF NOT ok OR position('Not authenticated' IN v_msg) = 0 THEN
    RAISE EXCEPTION 'AUTHZ anon: expected Not authenticated, got: %', v_msg; END IF;
  IF position('Domain ownership' IN v_msg) > 0 THEN
    RAISE EXCEPTION 'AUTHZ anon: ownership state leaked before authentication'; END IF;

  -- client → 'Not permitted...'
  PERFORM public._seo_p1b_login(current_setting('p1b.client')::uuid);
  ok := false;
  BEGIN PERFORM public.seo_crawl_request(v_site, 'P1B-client', NULL);
  EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
  IF NOT ok OR position('Not permitted' IN v_msg) = 0 THEN
    RAISE EXCEPTION 'AUTHZ client: expected Not permitted, got: %', v_msg; END IF;
  IF position('Domain ownership' IN v_msg) > 0 THEN
    RAISE EXCEPTION 'AUTHZ client: ownership state leaked before role check'; END IF;

  -- non-member → 'Not permitted...'
  PERFORM public._seo_p1b_login(current_setting('p1b.nonmember')::uuid);
  ok := false;
  BEGIN PERFORM public.seo_crawl_request(v_site, 'P1B-nonmember', NULL);
  EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
  IF NOT ok OR position('Not permitted' IN v_msg) = 0 THEN
    RAISE EXCEPTION 'AUTHZ nonmember: expected Not permitted, got: %', v_msg; END IF;
  RAISE NOTICE 'AUTHZ precedence (anon/client/nonmember) ok';
END $t$;

-- 6b. CROSS-WORKSPACE: seed owner (not a member of the foreign ws) enqueuing a
-- VERIFIED foreign site must fail on AUTHORIZATION, not ownership.
DO $t$
DECLARE v_fsite uuid := current_setting('p1b.fsite')::uuid; ok boolean; v_msg text; n int;
BEGIN
  PERFORM public._seo_p1b_login(current_setting('p1b.owner')::uuid);
  ok := false;
  BEGIN PERFORM public.seo_crawl_request(v_fsite, 'P1B-xws', NULL);
  EXCEPTION WHEN OTHERS THEN ok := true; v_msg := SQLERRM; END;
  IF NOT ok OR position('Not permitted' IN v_msg) = 0 THEN
    RAISE EXCEPTION 'AUTHZ cross-workspace: expected Not permitted, got: %', v_msg; END IF;
  IF position('Domain ownership' IN v_msg) > 0 THEN
    RAISE EXCEPTION 'AUTHZ cross-workspace: ownership state leaked before role check'; END IF;
  SELECT count(*) INTO n FROM public.seo_crawl_jobs WHERE website_id=v_fsite;
  IF n <> 0 THEN RAISE EXCEPTION 'AUTHZ cross-workspace: a job was created (%)', n; END IF;
  RAISE NOTICE 'AUTHZ cross-workspace ok';
END $t$;

-- ---------- 7. TEARDOWN + isolation -----------------------------------------
RESET ROLE;
DELETE FROM public.seo_crawl_events
  WHERE job_id IN (SELECT id FROM public.seo_crawl_jobs
                    WHERE website_id IN (current_setting('p1b.verified')::uuid, current_setting('p1b.verified2')::uuid));
DELETE FROM public.seo_crawl_jobs
  WHERE website_id IN (current_setting('p1b.verified')::uuid, current_setting('p1b.verified2')::uuid,
                       current_setting('p1b.pending')::uuid, current_setting('p1b.failed')::uuid,
                       current_setting('p1b.revoked')::uuid, current_setting('p1b.missing')::uuid,
                       current_setting('p1b.fsite')::uuid);
DELETE FROM public.seo_audit_runs
  WHERE website_id IN (current_setting('p1b.verified')::uuid, current_setting('p1b.verified2')::uuid);
DELETE FROM public.seo_ownership_verifications WHERE challenge_token = 'P1B-VERIFY-TOKEN';
DELETE FROM public.seo_websites
  WHERE id IN (current_setting('p1b.verified')::uuid, current_setting('p1b.verified2')::uuid,
               current_setting('p1b.pending')::uuid, current_setting('p1b.failed')::uuid,
               current_setting('p1b.revoked')::uuid, current_setting('p1b.missing')::uuid,
               current_setting('p1b.fsite')::uuid);
DELETE FROM public.seo_workspaces WHERE id = current_setting('p1b.fws')::uuid;  -- cascades foreign site/ownership
DROP FUNCTION IF EXISTS public._seo_p1b_login(uuid);

DO $t$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.seo_websites
   WHERE id IN ('b1b00000-0000-0000-0002-000000000001','b1b00000-0000-0000-0002-000000000002',
                'b1b00000-0000-0000-0002-000000000003','b1b00000-0000-0000-0002-000000000004',
                'b1b00000-0000-0000-0002-000000000005','b1b00000-0000-0000-0002-000000000006',
                'b1b00000-0000-0000-0002-0000000000f2');
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual websites %', n; END IF;
  SELECT count(*) INTO n FROM public.seo_ownership_verifications WHERE challenge_token='P1B-VERIFY-TOKEN';
  IF n <> 0 THEN RAISE EXCEPTION 'TEARDOWN: residual ownership rows %', n; END IF;
  RAISE NOTICE 'TEARDOWN ok (0 residual)';
END $t$;

SELECT 'ALL PASS — seo_p1b verified-only crawl enqueue enforcement verification complete' AS result;
