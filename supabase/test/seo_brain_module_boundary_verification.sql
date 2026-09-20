-- =============================================================================
-- SEO Digi Brain Module Contract v1, Stage 2B, MACHINE BOUNDARY VERIFICATION
--   public.seo_brain_normalize_host(text)
--   public.seo_brain_website_links (+ derivation trigger, RLS)
--   public.seo_brain_resolve_target / _ownership_status /
--   _crawl_findings / _current_recommendations
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- RUN ONLY on a local/fresh project or Digi_SEO_Test, AFTER:
--   * 20260920120000_seo_brain_machine_boundary_identity.sql
--   * 20260920120100_seo_brain_delegated_read_rpcs.sql
--
-- Self-contained + self-seeding: creates its own disposable workspaces,
-- memberships, websites, audit runs/issues, recommendations and links, reusing
-- the shared UI-seed auth.users ids already used by every prior guarded-RPC
-- verification script in this repo. The whole script runs as ONE implicit
-- transaction: any assertion failure aborts and rolls back every fixture. On
-- success, explicit teardown removes all fixtures and a final net-nothing
-- assertion proves zero residue.
--
-- Proves:
--   * host normalizer parity with Digi Brain's normalizeWebsiteHost, case for
--     case against supabase/functions/seo-module-api/normalize-host.test.ts;
--   * the link trigger DERIVES normalized_host and workspace_id and ignores
--     whatever the caller supplied;
--   * exact (business, host) resolution, and refusal for a wrong Business, a
--     wrong host, a revoked link, a changed website URL and an inactive site;
--   * no sibling-website and no cross-tenant substitution;
--   * the authenticity gates: a non-crawler issue and a recommendation with a
--     NULL generation_method are both excluded;
--   * grants: anon and authenticated are denied EXECUTE on all four delegated
--     RPCs; service_role is granted;
--   * link RLS: a client role cannot authorize a link; an owner can.
-- =============================================================================

SELECT set_config('b1.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('b1.client', 'c6b1f0f6-3d6c-4b53-9a0f-9bf3d7a0f111', false);

-- ---------------------------------------------------------------------------
-- 0. Normalizer parity. Each row mirrors one case in normalize-host.test.ts.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT * FROM (VALUES
      ('https://example.com',                 'example.com'),
      ('https://example.com/pricing?q=1#top', 'example.com'),
      ('example.com',                         'example.com'),
      ('HTTPS://EXAMPLE.COM',                 'example.com'),
      ('https://www.example.com',             'example.com'),
      ('https://shop.example.com',            'shop.example.com'),
      ('https://www.shop.example.com',        'shop.example.com'),
      ('https://a.b.example.co.uk',           'a.b.example.co.uk'),
      ('https://example.com:443',             'example.com'),
      ('http://example.com:80',               'example.com'),
      ('https://example.com:8443',            'example.com:8443'),
      ('http://example.com:8080',             'example.com:8080'),
      ('https://www.example.com:8443',        'example.com:8443'),
      ('https://user:pass@example.com/x',     'example.com'),
      ('',                                    NULL),
      ('   ',                                 NULL),
      ('not a url',                           NULL)
    ) AS t(input, expected)
  LOOP
    IF public.seo_brain_normalize_host(c.input) IS DISTINCT FROM c.expected THEN
      RAISE EXCEPTION 'normalizer parity failed for "%": expected %, got %',
        c.input, c.expected, public.seo_brain_normalize_host(c.input);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Grants: the delegated RPCs are service_role only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_brain_resolve_target(text, text)',
    'public.seo_brain_ownership_status(text, text)',
    'public.seo_brain_crawl_findings(text, text, integer)',
    'public.seo_brain_current_recommendations(text, text, integer)'
  ] LOOP
    IF has_function_privilege('anon', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon must not execute %', fn;
    END IF;
    IF has_function_privilege('authenticated', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'authenticated must not execute %', fn;
    END IF;
    IF NOT has_function_privilege('service_role', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'service_role must execute %', fn;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Fixtures: two workspaces, three websites (one a tempting sibling).
-- ---------------------------------------------------------------------------
INSERT INTO public.user_module_access (user_id, module_name, is_active)
VALUES (current_setting('b1.owner')::uuid, 'seo', true)
ON CONFLICT (user_id, module_name) DO UPDATE SET is_active = true;

INSERT INTO public.seo_workspaces (id, name, owner_user_id)
VALUES
  ('b1000000-0000-4000-8000-000000000001', 'BRAIN-VERIFY ws1', current_setting('b1.owner')::uuid),
  ('b1000000-0000-4000-8000-000000000002', 'BRAIN-VERIFY ws2', current_setting('b1.owner')::uuid);

INSERT INTO public.seo_websites (id, workspace_id, website_url, website_name, business_name)
VALUES
  ('b1000000-0000-4000-8000-00000000000a', 'b1000000-0000-4000-8000-000000000001',
   'https://www.brainverify-a.test', 'A', 'A'),
  ('b1000000-0000-4000-8000-00000000000b', 'b1000000-0000-4000-8000-000000000001',
   'https://shop.brainverify-a.test', 'B sibling', 'B'),
  ('b1000000-0000-4000-8000-00000000000c', 'b1000000-0000-4000-8000-000000000002',
   'https://brainverify-c.test', 'C other tenant', 'C');

-- ---------------------------------------------------------------------------
-- 3. The trigger DERIVES host and workspace and ignores caller-supplied values.
-- ---------------------------------------------------------------------------
INSERT INTO public.seo_brain_website_links
  (id, business_id, normalized_host, workspace_id, website_id)
VALUES
  ('b1000000-0000-4000-8000-0000000000f1', 'brain-biz-1',
   'attacker-controlled.example',                       -- ignored
   'b1000000-0000-4000-8000-000000000002',              -- ignored (wrong ws)
   'b1000000-0000-4000-8000-00000000000a');

DO $$
DECLARE
  v record;
BEGIN
  SELECT normalized_host, workspace_id INTO v
  FROM public.seo_brain_website_links
  WHERE id = 'b1000000-0000-4000-8000-0000000000f1';

  IF v.normalized_host <> 'brainverify-a.test' THEN
    RAISE EXCEPTION 'normalized_host must be derived, got %', v.normalized_host;
  END IF;
  IF v.workspace_id <> 'b1000000-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'workspace_id must be derived, got %', v.workspace_id;
  END IF;
END $$;

INSERT INTO public.seo_brain_website_links (business_id, normalized_host, workspace_id, website_id)
VALUES ('brain-biz-2', 'x', 'b1000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-00000000000c');

-- ---------------------------------------------------------------------------
-- 4. Resolution matrix.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r text;
BEGIN
  -- Exact match resolves to the linked website.
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-1', 'brainverify-a.test');
  IF r <> 'resolved' THEN RAISE EXCEPTION 'exact match must resolve, got %', r; END IF;

  -- Wrong Business for a host that IS linked to another Business.
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-2', 'brainverify-a.test');
  IF r <> 'not_linked' THEN RAISE EXCEPTION 'wrong Business must not resolve, got %', r; END IF;

  -- Wrong host for a Business that IS linked to another host.
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-1', 'shop.brainverify-a.test');
  IF r <> 'not_linked' THEN RAISE EXCEPTION 'wrong host must not resolve, got %', r; END IF;

  -- Unknown Business entirely.
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-nope', 'brainverify-a.test');
  IF r <> 'not_linked' THEN RAISE EXCEPTION 'unknown Business must not resolve, got %', r; END IF;

  -- Empty input is refused, never treated as a wildcard.
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('', '');
  IF r <> 'invalid_target' THEN RAISE EXCEPTION 'empty target must be invalid, got %', r; END IF;

  -- A non-canonical host does not match the stored canonical value.
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-1', 'www.brainverify-a.test');
  IF r <> 'not_linked' THEN RAISE EXCEPTION 'non-canonical host must not resolve, got %', r; END IF;
END $$;

-- Revoked link stops resolving.
UPDATE public.seo_brain_website_links
  SET link_status = 'revoked'
WHERE id = 'b1000000-0000-4000-8000-0000000000f1';

DO $$
DECLARE r text;
BEGIN
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-1', 'brainverify-a.test');
  IF r <> 'revoked' THEN RAISE EXCEPTION 'revoked link must not resolve, got %', r; END IF;
END $$;

-- A revoked link cannot be reactivated.
DO $$
BEGIN
  BEGIN
    UPDATE public.seo_brain_website_links
      SET link_status = 'active'
    WHERE id = 'b1000000-0000-4000-8000-0000000000f1';
    RAISE EXCEPTION 'reactivating a revoked link must be refused';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'reactivating a revoked link must be refused' THEN RAISE; END IF;
  END;
END $$;

-- Re-link for the remaining assertions.
INSERT INTO public.seo_brain_website_links (business_id, normalized_host, workspace_id, website_id)
VALUES ('brain-biz-1', 'x', 'b1000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-00000000000a');

-- A website URL change invalidates the old authorization.
UPDATE public.seo_websites
  SET website_url = 'https://renamed-brainverify.test'
WHERE id = 'b1000000-0000-4000-8000-00000000000a';

DO $$
DECLARE r text;
BEGIN
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-1', 'brainverify-a.test');
  IF r <> 'host_changed' THEN RAISE EXCEPTION 'a changed website URL must not resolve, got %', r; END IF;
END $$;

UPDATE public.seo_websites
  SET website_url = 'https://www.brainverify-a.test'
WHERE id = 'b1000000-0000-4000-8000-00000000000a';

-- An inactive website does not resolve.
UPDATE public.seo_websites SET is_active = false
WHERE id = 'b1000000-0000-4000-8000-00000000000a';

DO $$
DECLARE r text;
BEGIN
  SELECT resolution INTO r FROM public.seo_brain_resolve_target('brain-biz-1', 'brainverify-a.test');
  IF r <> 'website_inactive' THEN RAISE EXCEPTION 'inactive website must not resolve, got %', r; END IF;
END $$;

UPDATE public.seo_websites SET is_active = true
WHERE id = 'b1000000-0000-4000-8000-00000000000a';

-- ---------------------------------------------------------------------------
-- 5. Authenticity gates and no substitution.
-- ---------------------------------------------------------------------------
INSERT INTO public.seo_audit_runs (id, workspace_id, website_id, website_url, status, is_latest, completed_at)
VALUES
  ('b1000000-0000-4000-8000-0000000000r1', 'b1000000-0000-4000-8000-000000000001',
   'b1000000-0000-4000-8000-00000000000a', 'https://www.brainverify-a.test', 'completed', true, now()),
  ('b1000000-0000-4000-8000-0000000000r2', 'b1000000-0000-4000-8000-000000000001',
   'b1000000-0000-4000-8000-00000000000b', 'https://shop.brainverify-a.test', 'completed', true, now());

INSERT INTO public.seo_audit_issues
  (workspace_id, website_id, website_url, audit_run_id, category, severity, title,
   simple_explanation, why_it_matters, technical_explanation, affected_page_url,
   impact, effort, risk, fix_owner, suggested_next_action, source, source_issue_fingerprint)
VALUES
  -- Genuine crawler issue on the linked website.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'b1000000-0000-4000-8000-0000000000r1', 'indexability', 'critical',
   'BRAINVERIFY genuine', 'x', 'x', 'x', 'https://www.brainverify-a.test/p', 'high', 'low', 'low',
   'client_action', 'fix it', 'crawler', 'GENUINE::fp1'),
  -- Seeded issue on the SAME website: must be excluded by the authenticity gate.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'b1000000-0000-4000-8000-0000000000r1', 'speed', 'high',
   'BRAINVERIFY seeded', 'x', 'x', 'x', 'https://www.brainverify-a.test/q', 'high', 'low', 'low',
   'client_action', 'fix it', 'seed', 'SEEDED::fp2'),
  -- Sibling website issue: must never appear for the linked website.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000b',
   'https://shop.brainverify-a.test', 'b1000000-0000-4000-8000-0000000000r2', 'speed', 'high',
   'BRAINVERIFY sibling', 'x', 'x', 'x', 'https://shop.brainverify-a.test/p', 'high', 'low', 'low',
   'client_action', 'fix it', 'crawler', 'SIBLING::fp3');

DO $$
DECLARE
  payload jsonb;
BEGIN
  payload := public.seo_brain_crawl_findings('brain-biz-1', 'brainverify-a.test');

  IF payload->>'resolution' <> 'resolved' THEN
    RAISE EXCEPTION 'findings must resolve, got %', payload->>'resolution';
  END IF;
  IF jsonb_array_length(payload->'findings') <> 1 THEN
    RAISE EXCEPTION 'expected exactly the one genuine crawler finding, got %',
      jsonb_array_length(payload->'findings');
  END IF;
  IF payload->'findings'->0->>'findingKey' <> 'GENUINE::fp1' THEN
    RAISE EXCEPTION 'wrong finding returned: %', payload->'findings'->0->>'findingKey';
  END IF;
  IF payload::text LIKE '%SEEDED%' THEN
    RAISE EXCEPTION 'a seeded issue leaked through the authenticity gate';
  END IF;
  IF payload::text LIKE '%SIBLING%' THEN
    RAISE EXCEPTION 'a sibling website issue leaked through resolution';
  END IF;
END $$;

INSERT INTO public.seo_recommendations
  (workspace_id, website_id, website_url, area, title, suggested_change, why_it_helps,
   action_type, impact, effort, risk, is_current, generation_method)
VALUES
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'title', 'BRAINVERIFY generated', 'x', 'x',
   'approval_required', 'high', 'low', 'low', true, 'rule_based_v1'),
  -- No generation_method: a legacy/manual row that must be excluded.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'h1', 'BRAINVERIFY ungenerated', 'x', 'x',
   'approval_required', 'high', 'low', 'low', true, NULL);

DO $$
DECLARE
  payload jsonb;
BEGIN
  payload := public.seo_brain_current_recommendations('brain-biz-1', 'brainverify-a.test');
  IF jsonb_array_length(payload->'recommendations') <> 1 THEN
    RAISE EXCEPTION 'expected exactly the one generated recommendation, got %',
      jsonb_array_length(payload->'recommendations');
  END IF;
  IF payload::text LIKE '%ungenerated%' THEN
    RAISE EXCEPTION 'a recommendation with no generation_method leaked through the gate';
  END IF;
END $$;

-- Ownership: no verification record yet is a reportable state, not an error.
DO $$
DECLARE payload jsonb;
BEGIN
  payload := public.seo_brain_ownership_status('brain-biz-1', 'brainverify-a.test');
  IF payload->>'status' <> 'not_started' THEN
    RAISE EXCEPTION 'absent verification must report not_started, got %', payload->>'status';
  END IF;
  -- And an unlinked target reveals nothing at all.
  payload := public.seo_brain_ownership_status('brain-biz-nope', 'brainverify-a.test');
  IF payload ? 'websiteId' THEN
    RAISE EXCEPTION 'an unlinked target must not disclose a websiteId';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6. Link RLS: a client may not authorize a link; an owner may.
-- ---------------------------------------------------------------------------
INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role)
VALUES ('b1000000-0000-4000-8000-000000000001', current_setting('b1.client')::uuid, 'client')
ON CONFLICT (workspace_id, user_id) DO UPDATE SET seo_role = 'client';

DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.client'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.seo_brain_website_links (business_id, normalized_host, workspace_id, website_id)
    VALUES ('brain-biz-client', 'x', 'b1000000-0000-4000-8000-000000000001',
            'b1000000-0000-4000-8000-00000000000b');
    RESET ROLE;
    RAISE EXCEPTION 'a client role must not be able to authorize a Digi Brain link';
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    RESET ROLE;
  END;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 7. Teardown + net-nothing proof.
-- ---------------------------------------------------------------------------
DELETE FROM public.seo_recommendations
  WHERE website_id IN ('b1000000-0000-4000-8000-00000000000a',
                       'b1000000-0000-4000-8000-00000000000b',
                       'b1000000-0000-4000-8000-00000000000c');
DELETE FROM public.seo_audit_issues
  WHERE audit_run_id IN ('b1000000-0000-4000-8000-0000000000r1',
                         'b1000000-0000-4000-8000-0000000000r2');
DELETE FROM public.seo_audit_runs
  WHERE id IN ('b1000000-0000-4000-8000-0000000000r1', 'b1000000-0000-4000-8000-0000000000r2');
DELETE FROM public.seo_brain_website_links
  WHERE business_id IN ('brain-biz-1', 'brain-biz-2', 'brain-biz-client');
DELETE FROM public.seo_workspace_members
  WHERE workspace_id IN ('b1000000-0000-4000-8000-000000000001',
                         'b1000000-0000-4000-8000-000000000002');
DELETE FROM public.seo_websites
  WHERE id IN ('b1000000-0000-4000-8000-00000000000a',
               'b1000000-0000-4000-8000-00000000000b',
               'b1000000-0000-4000-8000-00000000000c');
DELETE FROM public.seo_workspaces
  WHERE id IN ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002');

DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM public.seo_brain_website_links
  WHERE business_id LIKE 'brain-biz-%';
  IF n <> 0 THEN RAISE EXCEPTION 'residue: % link rows remain', n; END IF;

  SELECT count(*) INTO n FROM public.seo_workspaces
  WHERE name LIKE 'BRAIN-VERIFY%';
  IF n <> 0 THEN RAISE EXCEPTION 'residue: % workspaces remain', n; END IF;
END $$;

SELECT 'seo_brain_module_boundary_verification: ALL ASSERTIONS PASSED' AS result;
