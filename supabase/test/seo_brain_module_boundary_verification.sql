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
--   * 20260920120200_seo_brain_actor_links.sql
--   * 20260920120300_seo_brain_delegated_write_rpcs.sql
--   * 20260920120400_seo_brain_stage2b_runtime_corrections.sql
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
--   * table privileges (20260920120400): service_role holds SELECT but NOT
--     INSERT/UPDATE/DELETE on the two human-authorization tables, so the
--     machine identity cannot create an authorization even though it bypasses
--     RLS; anon holds nothing; authenticated keeps exactly the privileges its
--     global-admin / owner-admin RLS policies need;
--   * link RLS: a client role cannot authorize a link; an owner can;
--   * actor mapping: exact active resolution, unknown actor, revoked actor,
--     no email/owner/linked_by fallback, and the fact that a mapping grants
--     NOTHING on its own (a mapped user with no membership is refused);
--   * delegated writes: the role matrix, the preserved verified-ownership
--     requirement, a real crawl job id as the operation handle, same-key STATUS
--     correlation, and a cross-site operation id failing closed;
--   * actor-link RLS: a non-admin cannot authorize an actor mapping.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PREREQUISITE, ASSERTED BEFORE ANY MUTATION.
--
-- This script does NOT create Supabase Auth users, in line with every other
-- verification script in this repository: auth.users rows are created through
-- the Auth API, never from SQL. It reuses the shared TEST fixture users, and
-- refuses to run at all if they are absent, so a missing fixture fails here
-- with a clear message instead of somewhere deep inside an assertion.
--
-- If a user below is missing, create it in Supabase Studio under Authentication
-- -> Users with the matching address, take its UUID and either use that UUID or
-- update the id here. Do not insert into auth.users directly.
--
--   b1.owner   48c479db-aedf-452e-af43-05ed1180baaa  seo-owner-test@example.com
--   b1.client  6c7a04e0-9985-47c3-aad4-f2f0cc5e092c  seo-client-test@example.com
--   b1.nomem   0723d21f-c02c-4725-851f-575f93f2f58c  seo-team-test@example.com
--
-- b1.client was previously a literal that existed nowhere; it is now the shared
-- client fixture used by the other guarded-RPC verification scripts.
-- ---------------------------------------------------------------------------
SELECT set_config('b1.owner',  '48c479db-aedf-452e-af43-05ed1180baaa', false);
SELECT set_config('b1.client', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);
SELECT set_config('b1.nomem',  '0723d21f-c02c-4725-851f-575f93f2f58c', false);

DO $prereq$
DECLARE
  v_pat  text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_keys text[] := ARRAY['owner', 'client', 'nomem'];
  v_k    text;
  v_v    text;
BEGIN
  FOREACH v_k IN ARRAY v_keys LOOP
    v_v := current_setting('b1.' || v_k, true);
    IF v_v IS NULL OR v_v !~ v_pat THEN
      RAISE EXCEPTION
        'PREREQUISITE FAILED: b1.% ("%") is not a valid auth.users UUID. Paste the user id from Authentication -> Users, not an email address.',
        v_k, coalesce(v_v, '<unset>');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = v_v::uuid) THEN
      RAISE EXCEPTION
        'PREREQUISITE FAILED: the fixture auth user for b1.% (%) does not exist on this project. Create the shared TEST users in Supabase Studio (Authentication -> Users) before running this script; it never inserts into auth.users itself.',
        v_k, v_v;
    END IF;
  END LOOP;

  -- Every fixture identity must be distinct, or the isolation assertions below
  -- would pass for the wrong reason.
  IF (SELECT count(DISTINCT x) FROM unnest(ARRAY[
        current_setting('b1.owner'), current_setting('b1.client'), current_setting('b1.nomem')
      ]) AS x) <> 3 THEN
    RAISE EXCEPTION 'PREREQUISITE FAILED: the three fixture user ids must be distinct';
  END IF;

  -- The four Stage 2B migrations must be applied before anything is asserted.
  IF to_regclass('public.seo_brain_actor_links') IS NULL
     OR to_regclass('public.seo_brain_operations') IS NULL
     OR to_regclass('public.seo_brain_website_links') IS NULL THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: the Stage 2B migrations are not applied on this project. Apply 20260920120000, 20260920120100, 20260920120200 and 20260920120300 first.';
  END IF;
  IF to_regprocedure('public.seo_brain_bootstrap_actor_link(text, uuid, uuid)') IS NULL THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: public.seo_brain_bootstrap_actor_link is absent. Re-apply 20260920120200_seo_brain_actor_links.sql.';
  END IF;

  -- The corrective migration must be applied too, or Section 0 and Section 1b
  -- below would fail deep inside an assertion rather than here with a clear
  -- instruction. Detected by BEHAVIOUR, not by a version string: the pre-
  -- correction normalizer returned 'not a url' verbatim for this input.
  IF public.seo_brain_normalize_host('not a url') IS NOT NULL THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: public.seo_brain_normalize_host still admits whitespace in a host. Apply 20260920120400_seo_brain_stage2b_runtime_corrections.sql first.';
  END IF;

  -- Second probe, for the OPPOSITE mistake. A version that trimmed both ends
  -- with '[[:space:][:cntrl:]]' would pass the probe above and still be wrong:
  -- it would strip a leading control character and hand back a clean canonical
  -- host for a value TypeScript refuses to parse. Both probes together pin the
  -- asymmetric trim the corrected migration actually ships.
  IF public.seo_brain_normalize_host(E'\x7fexample.com') IS NOT NULL
     OR public.seo_brain_normalize_host(E'\x01example.com') IS NOT NULL THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: public.seo_brain_normalize_host trims a leading control character and returns a clean host, which TypeScript rejects. The applied 20260920120400 is not the corrected version.';
  END IF;
  -- ...and the trailing end must still normalize, or the trim is too narrow.
  IF public.seo_brain_normalize_host(E'example.com\x01') IS DISTINCT FROM 'example.com' THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: public.seo_brain_normalize_host does not strip a trailing C0 control, which the URL parser does. The applied 20260920120400 is not the corrected version.';
  END IF;

  -- Third probe, for the LOCALE mistake that 20260920120500 corrects. A leading
  -- FS/GS/RS/US is whitespace to glibc and not to JavaScript, so a normalizer
  -- whose leading trim is the POSIX class '[[:space:]]' strips it and returns a
  -- clean canonical host. Both previous probes pass in that state.
  IF public.seo_brain_normalize_host(E'\x1fexample.com') IS NOT NULL
     OR public.seo_brain_normalize_host(E'\x1cexample.com') IS NOT NULL THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: public.seo_brain_normalize_host trims a leading ASCII 28..31, which only glibc treats as whitespace. Apply 20260920120500_seo_brain_normalizer_locale_correction.sql first.';
  END IF;
  IF public.seo_brain_normalize_host(E'example.com\x1f') IS DISTINCT FROM 'example.com' THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: public.seo_brain_normalize_host does not strip a TRAILING ASCII 28..31, which the URL parser does. The applied 20260920120500 narrowed the trailing trim by mistake.';
  END IF;

  -- This script mutates. It must never touch a project holding real customers.
  IF EXISTS (SELECT 1 FROM public.seo_brain_website_links WHERE business_id LIKE 'brain-biz-%')
     OR EXISTS (SELECT 1 FROM public.seo_brain_actor_links WHERE brain_actor_id LIKE 'BRAINVERIFY-actor-%')
     OR EXISTS (SELECT 1 FROM public.seo_workspaces WHERE name LIKE 'BRAIN-VERIFY%') THEN
    RAISE EXCEPTION
      'PREREQUISITE FAILED: fixtures from a previous run are still present. Investigate before re-running; this script refuses to overwrite residue.';
  END IF;
END $prereq$;

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
      ('not a url',                           NULL),
      -- --------------------------------------------------------------------
      -- Whitespace and control characters (added by 20260920120400). The pre-
      -- correction function returned 'not a url' for the row above and a bare
      -- control character for the two lone-whitespace rows below.
      --
      -- ASCII tab, LF and CR are REMOVED from the input by the URL parser, so
      -- these three normalize rather than fail. This is the parser's own rule,
      -- pinned here so the SQL cannot quietly start rejecting them.
      (E'exa\tmple.com',                      'example.com'),
      (E'exa\nmple.com',                      'example.com'),
      (E'exa\rmple.com',                      'example.com'),
      -- Every OTHER ASCII whitespace or control character inside the host is a
      -- parse failure: space, form feed and vertical tab all fail closed.
      ('exa mple.com',                        NULL),
      ('example .com',                        NULL),
      (E'exa\fmple.com',                      NULL),
      (E'exa\x0bmple.com',                    NULL),
      -- ...and in the port, which is part of the authority.
      ('https://example.com:84 43',           NULL),
      (E'https://example.com\f/x',            NULL),
      -- Leading/trailing whitespace is trimmed, including whitespace that is
      -- not the space character. btrim/1 stripped only spaces before.
      (' example.com ',                       'example.com'),
      (E'\texample.com',                      'example.com'),
      (E'\t',                                 NULL),
      (E'\f',                                 NULL),
      (E'\x0b',                               NULL),
      -- Whitespace OUTSIDE the host and port is not the host's business: the
      -- URL parser accepts it in a path, a query, a fragment and in userinfo,
      -- and so must this function, or it would start refusing URLs Digi Brain
      -- normalizes successfully.
      ('https://example.com/a b',             'example.com'),
      ('https://example.com/?q=a b',          'example.com'),
      ('https://example.com/x#a b',           'example.com'),
      ('https://us er:pa ss@example.com/x',   'example.com'),
      (E'https://exa\tmple.com:8443/p a th',  'example.com:8443'),
      -- --------------------------------------------------------------------
      -- The two ends of the input are NOT symmetric, and a symmetric trim was
      -- the fail-OPEN defect independent review caught before this migration
      -- was ever applied. TypeScript runs String.trim() on the RAW value and
      -- only then prefixes 'https://', so the URL parser's leading strip never
      -- reaches the start of the caller's string.
      --
      -- LEADING: a C0 control or DEL is NOT trimmed. It survives into the
      -- authority and fails the parse, exactly as TypeScript fails it. A
      -- symmetric '[[:space:][:cntrl:]]' trim would have returned a clean
      -- 'example.com' for every one of these.
      (E'\x01example.com',                    NULL),
      (E'\x1fexample.com',                    NULL),
      (E'\x7fexample.com',                    NULL),
      (E'\x01https://example.com',            NULL),
      (E'\x7fhttps://example.com',            NULL),
      (E'\x01',                               NULL),
      (E'\x1f',                               NULL),
      (E'\x7f',                               NULL),
      -- TRAILING: after the scheme is prefixed the caller's tail IS the
      -- parser's tail, so the parser's C0-control-or-space strip applies.
      (E'example.com\x01',                    'example.com'),
      (E'example.com\x1f',                    'example.com'),
      -- ...but DEL is not a C0 control, so it is not stripped and the host
      -- fails. This is why the trailing class stops at chr(32).
      (E'example.com\x7f',                    NULL),
      -- Non-space ASCII whitespace at either end is trimmed at both ends.
      (E'\fexample.com',                      'example.com'),
      (E'\x0bexample.com',                    'example.com'),
      (E'example.com\f',                      'example.com'),
      (E'example.com\x0b',                    'example.com'),
      (E'\r\nexample.com',                    'example.com'),
      (E'example.com\r\n',                    'example.com'),
      -- --------------------------------------------------------------------
      -- ASCII 28 to 31 (FS, GS, RS, US). THE 20260920120500 DEFECT.
      -- glibc classifies these four as space characters and JavaScript does
      -- not, so the POSIX class '[[:space:]]' used by 20260920120400 for the
      -- leading trim stripped them and returned a clean canonical host for a
      -- value the TypeScript twin rejects. Measured on this database:
      --   SELECT string_agg(i::text, ',' ORDER BY i)
      --     FROM generate_series(1,32) i WHERE chr(i) ~ '[[:space:]]';
      --   --> 9,10,11,12,13,28,29,30,31,32
      -- LEADING must fail, because String.trim() leaves them in place.
      (E'\x1cexample.com',                    NULL),
      (E'\x1dexample.com',                    NULL),
      (E'\x1eexample.com',                    NULL),
      (E'\x1fexample.com',                    NULL),
      -- TRAILING must still normalize, because after the scheme is prefixed
      -- the parser's own C0-or-space strip applies. A trim merely narrowed at
      -- both ends would have broken these.
      (E'example.com\x1c',                    'example.com'),
      (E'example.com\x1d',                    'example.com'),
      (E'example.com\x1e',                    'example.com'),
      (E'example.com\x1f',                    'example.com'),
      (E'\x1c',                               NULL),
      (E'\x1f',                               NULL),
      (E'exa\x1cmple.com',                    NULL),
      (E'exa\x1fmple.com',                    NULL),
      -- --------------------------------------------------------------------
      -- IPv4 and IPv6 literals, with and without a port, and an uppercase
      -- IPv6 literal. These prove the correction moved no network-literal
      -- behaviour.
      ('192.168.1.1',                         '192.168.1.1'),
      ('https://192.168.1.1:8443',            '192.168.1.1:8443'),
      ('http://192.168.1.1:80',               '192.168.1.1'),
      ('[::1]',                               '[::1]'),
      ('https://[::1]:8443',                  '[::1]:8443'),
      ('http://[2001:db8::1]:80',             '[2001:db8::1]'),
      ('https://[2001:DB8::1]',               '[2001:db8::1]')
      -- NUL is deliberately absent: PostgreSQL text cannot contain chr(0), so
      -- the function can never be handed it and there is nothing to assert.
      -- An IPv4-mapped IPv6 literal is also absent: the URL parser recompresses
      -- '[::ffff:192.168.1.1]' to '[::ffff:c0a8:101]' and SQL does not. That
      -- divergence is pre-existing, fails closed, and is recorded in
      -- SEO_BRAIN_MODULE_INTERFACE.md rather than fixed with an IPv6
      -- canonicalizer in PL/pgSQL.
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
    'public.seo_brain_current_recommendations(text, text, integer)',
    'public.seo_brain_resolve_actor(text)',
    'public.seo_brain_authorize_delegated(text, text, text)',
    'public.seo_brain_request_technical_audit(text, text, text, text, text)',
    'public.seo_brain_technical_audit_status(text, text, text, text)',
    'public.seo_brain_generate_recommendations(text, text, text, text, text)',
    'public.seo_brain_recommendation_status(text, text, text, text)'
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
-- 1b. TABLE privileges (20260920120400), asserted BEFORE any mutation.
--
-- WHY THIS SECTION EXISTS. Supabase grants ALL on every new public table to
-- anon, authenticated and service_role by default, and service_role bypasses
-- RLS. Section 1 above proves the machine cannot EXECUTE the bootstrap RPC, but
-- that proves nothing on its own while the default table grant lets it INSERT
-- the same row directly. The first controlled TEST run found exactly that. RLS
-- policy assertions and function-grant assertions are both blind to it, so the
-- privilege itself is asserted here.
--
-- THE INVARIANT. An actor mapping and a website link are HUMAN authorizations.
-- The machine identity may read them and may never create, alter or erase one.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'public.seo_brain_actor_links',
    'public.seo_brain_website_links'
  ] LOOP
    -- service_role: read yes, write never. SELECT is required, because
    -- seo_brain_resolve_actor and the four delegated read RPCs are SECURITY
    -- INVOKER and read these tables as service_role.
    IF NOT has_table_privilege('service_role', t, 'SELECT') THEN
      RAISE EXCEPTION 'service_role must retain SELECT on % (the SECURITY INVOKER read RPCs depend on it)', t;
    END IF;
    IF has_table_privilege('service_role', t, 'INSERT') THEN
      RAISE EXCEPTION 'service_role must NOT hold INSERT on %: the machine identity bypasses RLS and would be able to mint its own human authorization', t;
    END IF;
    IF has_table_privilege('service_role', t, 'UPDATE') THEN
      RAISE EXCEPTION 'service_role must NOT hold UPDATE on %: it bypasses RLS and could revoke or alter a human authorization', t;
    END IF;
    IF has_table_privilege('service_role', t, 'DELETE') THEN
      RAISE EXCEPTION 'service_role must NOT hold DELETE on %: authorization history is append-only', t;
    END IF;

    -- anon: nothing at all. No policy names anon, so RLS already denied it;
    -- this closes the privilege too, so a later policy cannot widen anon by
    -- accident.
    IF has_table_privilege('anon', t, 'SELECT')
       OR has_table_privilege('anon', t, 'INSERT')
       OR has_table_privilege('anon', t, 'UPDATE')
       OR has_table_privilege('anon', t, 'DELETE') THEN
      RAISE EXCEPTION 'anon must hold no privilege on %', t;
    END IF;

    -- authenticated: the INTENDED human path, deliberately preserved. Both
    -- tables authorize through RLS policies declared TO authenticated with no
    -- SECURITY DEFINER RPC behind them, so revoking these would break the
    -- product, not harden it. Asserted positively so a future over-zealous
    -- REVOKE is caught here rather than by a customer.
    IF NOT has_table_privilege('authenticated', t, 'SELECT') THEN
      RAISE EXCEPTION 'authenticated must retain SELECT on %: the member/admin read policy depends on it', t;
    END IF;
    IF NOT has_table_privilege('authenticated', t, 'INSERT') THEN
      RAISE EXCEPTION 'authenticated must retain INSERT on %: the human global-admin / owner-admin authorization policy depends on it', t;
    END IF;
    IF NOT has_table_privilege('authenticated', t, 'UPDATE') THEN
      RAISE EXCEPTION 'authenticated must retain UPDATE on %: revocation is an UPDATE under RLS', t;
    END IF;
    -- No DELETE policy exists on either table: an authorization is revoked,
    -- never erased.
    IF has_table_privilege('authenticated', t, 'DELETE') THEN
      RAISE EXCEPTION 'authenticated must NOT hold DELETE on %: authorization history is append-only', t;
    END IF;
  END LOOP;

  -- seo_brain_operations is a correlation index written ONLY by the four
  -- SECURITY DEFINER delegated wrappers, which run as the table owner. It has a
  -- SELECT policy for workspace members and no write policy at all, so no
  -- client role needs direct mutation on it.
  IF has_table_privilege('service_role', 'public.seo_brain_operations', 'INSERT')
     OR has_table_privilege('service_role', 'public.seo_brain_operations', 'UPDATE')
     OR has_table_privilege('service_role', 'public.seo_brain_operations', 'DELETE') THEN
    RAISE EXCEPTION 'service_role must NOT mutate public.seo_brain_operations directly; the delegated SECURITY DEFINER wrappers are the only write path';
  END IF;
  IF has_table_privilege('authenticated', 'public.seo_brain_operations', 'INSERT')
     OR has_table_privilege('authenticated', 'public.seo_brain_operations', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.seo_brain_operations', 'DELETE') THEN
    RAISE EXCEPTION 'authenticated must NOT mutate public.seo_brain_operations directly; there is deliberately no human write path';
  END IF;
  IF has_table_privilege('anon', 'public.seo_brain_operations', 'SELECT')
     OR has_table_privilege('anon', 'public.seo_brain_operations', 'INSERT')
     OR has_table_privilege('anon', 'public.seo_brain_operations', 'UPDATE')
     OR has_table_privilege('anon', 'public.seo_brain_operations', 'DELETE') THEN
    RAISE EXCEPTION 'anon must hold no privilege on public.seo_brain_operations';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.seo_brain_operations', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated must retain SELECT on public.seo_brain_operations: the workspace-member read policy depends on it';
  END IF;
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
  ('b1000000-0000-4000-8000-0000000000e1', 'b1000000-0000-4000-8000-000000000001',
   'b1000000-0000-4000-8000-00000000000a', 'https://www.brainverify-a.test', 'completed', true, now()),
  ('b1000000-0000-4000-8000-0000000000e2', 'b1000000-0000-4000-8000-000000000001',
   'b1000000-0000-4000-8000-00000000000b', 'https://shop.brainverify-a.test', 'completed', true, now());

INSERT INTO public.seo_audit_issues
  (workspace_id, website_id, website_url, audit_run_id, category, severity, title,
   simple_explanation, why_it_matters, technical_explanation, affected_page_url,
   impact, effort, risk, fix_owner, suggested_next_action, source, source_issue_fingerprint)
VALUES
  -- Genuine crawler issue on the linked website.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'b1000000-0000-4000-8000-0000000000e1', 'indexability', 'critical',
   'BRAINVERIFY genuine', 'x', 'x', 'x', 'https://www.brainverify-a.test/p', 'high', 'low', 'low',
   'client_action', 'fix it', 'crawler', 'GENUINE::fp1'),
  -- Seeded issue on the SAME website: must be excluded by the authenticity gate.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'b1000000-0000-4000-8000-0000000000e1', 'speed', 'high',
   'BRAINVERIFY seeded', 'x', 'x', 'x', 'https://www.brainverify-a.test/q', 'high', 'low', 'low',
   'client_action', 'fix it', 'seed', 'SEEDED::fp2'),
  -- Sibling website issue: must never appear for the linked website.
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000b',
   'https://shop.brainverify-a.test', 'b1000000-0000-4000-8000-0000000000e2', 'speed', 'high',
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
-- 6b. Actor mapping: identity only, never permission.
-- ---------------------------------------------------------------------------
SELECT set_config('b1.actor_ok',    current_setting('b1.owner'), false);  -- owner of ws1
SELECT set_config('b1.actor_nomem', current_setting('b1.nomem'), false);  -- no membership

INSERT INTO public.user_module_access (user_id, module_name, is_active)
VALUES (current_setting('b1.actor_nomem')::uuid, 'seo', true)
ON CONFLICT (user_id, module_name) DO UPDATE SET is_active = true;

-- The bootstrap procedure is reachable by the operator only. Proving this
-- BEFORE using it is the point: if the machine identity could reach it, the
-- machine endpoint could mint its own human.
DO $$
DECLARE
  v_fn text := 'public.seo_brain_bootstrap_actor_link(text, uuid, uuid)';
  v_r  text;
BEGIN
  FOREACH v_r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_function_privilege(v_r, v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '% must not be able to execute the actor-link bootstrap procedure', v_r;
    END IF;
  END LOOP;
END $$;

-- The POSITIVE creation path, exercised for real rather than bypassed.
--
-- Why not the authenticated global-admin INSERT policy: this project has no
-- currently reachable global-admin identity, so no signed-in session satisfies
-- public.seo_is_global_admin() and none can create the FIRST mapping. (The
-- earlier claim here, that the function "reads public.profiles" and nothing
-- else, was wrong: 20260720121000_seo_cross_project_identity_bridge extends it
-- through public.seo_identity_profiles. The absence of a reachable admin is the
-- real reason, and it is corrected in 20260920120400 and in
-- SEO_BRAIN_MODULE_INTERFACE.md.) The reachable positive path today is the
-- controlled operator bootstrap, and it is what runs here.
--
-- Note the explicit third argument: the authorizing SEO user is stated, never
-- inferred from the linked user, an email, a name or workspace ownership.
DO $$
DECLARE
  v_id       uuid;
  v_linkedby uuid;
BEGIN
  v_id := public.seo_brain_bootstrap_actor_link(
    'BRAINVERIFY-actor-ok',
    current_setting('b1.actor_ok')::uuid,
    current_setting('b1.owner')::uuid);

  SELECT linked_by INTO v_linkedby FROM public.seo_brain_actor_links WHERE id = v_id;
  IF v_linkedby IS DISTINCT FROM current_setting('b1.owner')::uuid THEN
    RAISE EXCEPTION 'the bootstrap must record the stated authorizer, got %', v_linkedby;
  END IF;

  PERFORM public.seo_brain_bootstrap_actor_link(
    'BRAINVERIFY-actor-nomem',
    current_setting('b1.actor_nomem')::uuid,
    current_setting('b1.owner')::uuid);
END $$;

-- The bootstrap refuses to invent an authorizer, and refuses a user it cannot
-- find. Both refusals matter more than the happy path.
DO $$
BEGIN
  BEGIN
    PERFORM public.seo_brain_bootstrap_actor_link(
      'BRAINVERIFY-actor-unauthorized', current_setting('b1.client')::uuid, NULL);
    RAISE EXCEPTION 'the bootstrap must refuse a mapping with no stated authorizer';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'the bootstrap must refuse a mapping with no stated authorizer' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.seo_brain_bootstrap_actor_link(
      'BRAINVERIFY-actor-ghost',
      '00000000-0000-4000-8000-0000000000ff'::uuid,
      current_setting('b1.owner')::uuid);
    RAISE EXCEPTION 'the bootstrap must refuse an SEO user that does not exist';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'the bootstrap must refuse an SEO user that does not exist' THEN RAISE; END IF;
  END;
END $$;

-- A direct operator insert that names no authorizer is refused by the guard
-- trigger, so no mapping can ever exist without a recorded human behind it.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id)
    VALUES ('BRAINVERIFY-actor-unattributed', current_setting('b1.client')::uuid);
    RAISE EXCEPTION 'an unattributed operator insert must be refused';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'an unattributed operator insert must be refused' THEN RAISE; END IF;
  END;
END $$;

DO $$
DECLARE
  u uuid;
  r text;
BEGIN
  -- Exact active resolution.
  u := public.seo_brain_resolve_actor('BRAINVERIFY-actor-ok');
  IF u IS DISTINCT FROM current_setting('b1.actor_ok')::uuid THEN
    RAISE EXCEPTION 'exact actor must resolve, got %', u;
  END IF;

  -- Unknown actor resolves to nothing. No email, name or owner fallback.
  IF public.seo_brain_resolve_actor('BRAINVERIFY-actor-unknown') IS NOT NULL THEN
    RAISE EXCEPTION 'an unknown actor must not resolve to anybody';
  END IF;
  IF public.seo_brain_resolve_actor('') IS NOT NULL THEN
    RAISE EXCEPTION 'an empty actor id must not resolve';
  END IF;

  -- A mapping grants NOTHING: the mapped user with no membership resolves as an
  -- identity and is then refused by the role check.
  SELECT resolution INTO r
  FROM public.seo_brain_authorize_delegated('brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-nomem');
  IF r <> 'actor_unauthorized' THEN
    RAISE EXCEPTION 'a mapped user with no membership must be actor_unauthorized, got %', r;
  END IF;

  -- No actor at all cannot perform a delegated write.
  SELECT resolution INTO r
  FROM public.seo_brain_authorize_delegated('brain-biz-1', 'brainverify-a.test', '');
  IF r <> 'actor_required' THEN
    RAISE EXCEPTION 'a delegated write with no actor must be actor_required, got %', r;
  END IF;

  -- An unmapped actor is distinct from an unauthorized one.
  SELECT resolution INTO r
  FROM public.seo_brain_authorize_delegated('brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-unknown');
  IF r <> 'actor_not_linked' THEN
    RAISE EXCEPTION 'an unmapped actor must be actor_not_linked, got %', r;
  END IF;

  -- The owner of ws1 is permitted.
  SELECT resolution INTO r
  FROM public.seo_brain_authorize_delegated('brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-ok');
  IF r <> 'resolved' THEN
    RAISE EXCEPTION 'a mapped owner must be permitted, got %', r;
  END IF;
END $$;

-- Revocation fails closed and is terminal. An operator revoke must name the
-- revoking human for the same reason creation must: the guard trigger refuses
-- an unattributed status change when there is no session identity to record.
DO $$
BEGIN
  BEGIN
    UPDATE public.seo_brain_actor_links
      SET link_status = 'revoked'
    WHERE brain_actor_id = 'BRAINVERIFY-actor-ok';
    RAISE EXCEPTION 'an unattributed operator revoke must be refused';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'an unattributed operator revoke must be refused' THEN RAISE; END IF;
  END;
END $$;

UPDATE public.seo_brain_actor_links
  SET link_status = 'revoked',
      revoked_by  = current_setting('b1.owner')::uuid,
      revoke_reason = 'BRAINVERIFY teardown assertion'
WHERE brain_actor_id = 'BRAINVERIFY-actor-ok';

DO $$
BEGIN
  IF public.seo_brain_resolve_actor('BRAINVERIFY-actor-ok') IS NOT NULL THEN
    RAISE EXCEPTION 'a revoked actor mapping must not resolve';
  END IF;
  BEGIN
    UPDATE public.seo_brain_actor_links
      SET link_status = 'active'
    WHERE brain_actor_id = 'BRAINVERIFY-actor-ok';
    RAISE EXCEPTION 'reactivating a revoked actor mapping must be refused';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'reactivating a revoked actor mapping must be refused' THEN RAISE; END IF;
  END;
END $$;

-- Re-map for the delegated write assertions, through the same controlled path.
SELECT public.seo_brain_bootstrap_actor_link(
  'BRAINVERIFY-actor-ok2',
  current_setting('b1.actor_ok')::uuid,
  current_setting('b1.owner')::uuid);

-- A non-admin cannot authorize an actor mapping.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', current_setting('b1.client'), 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id)
    VALUES ('BRAINVERIFY-actor-smuggled', current_setting('b1.client')::uuid);
    RESET ROLE;
    RAISE EXCEPTION 'a non-admin must not be able to authorize an actor mapping';
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    RESET ROLE;
  END;
END $$;
RESET ROLE;

-- The same invariant for the MACHINE identity, exercised for real rather than
-- read from the catalogue. service_role bypasses RLS, so no policy can stop it
-- and only the revoked table privilege can. Section 1b asserts the privilege;
-- this proves the privilege actually bites.
DO $$
BEGIN
  SET LOCAL ROLE service_role;
  BEGIN
    INSERT INTO public.seo_brain_actor_links (brain_actor_id, seo_user_id)
    VALUES ('BRAINVERIFY-actor-machine-minted', current_setting('b1.nomem')::uuid);
    RESET ROLE;
    RAISE EXCEPTION 'service_role must not be able to create an actor mapping directly; it bypasses RLS, so the table privilege is the only thing standing in its way';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
  END;
END $$;
RESET ROLE;

DO $$
BEGIN
  SET LOCAL ROLE service_role;
  BEGIN
    INSERT INTO public.seo_brain_website_links (business_id, normalized_host, workspace_id, website_id)
    VALUES ('brain-biz-machine-minted', 'x', 'b1000000-0000-4000-8000-000000000001',
            'b1000000-0000-4000-8000-00000000000b');
    RESET ROLE;
    RAISE EXCEPTION 'service_role must not be able to create a Digi Brain website link directly';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
  END;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 6c. Delegated writes: ownership preserved, real job id, STATUS correlation.
-- ---------------------------------------------------------------------------
DO $$
DECLARE payload jsonb;
BEGIN
  -- No verified ownership yet: the requirement is preserved, not bypassed.
  payload := public.seo_brain_request_technical_audit(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-ok2', 'BRAINVERIFY-action-1',
    'BRAINVERIFY-action-1:execute.technical_audit');
  IF payload->>'resolution' <> 'ownership_not_verified' THEN
    RAISE EXCEPTION 'unverified ownership must block a delegated crawl, got %', payload->>'resolution';
  END IF;
END $$;

-- Verify ownership the way P1a records it, then retry.
INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status,
   challenge_token, verified_at, last_checked_at)
VALUES
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000a',
   'https://www.brainverify-a.test', 'brainverify-a.test', 'dns_txt', 'verified',
   'digibility-site-verification=brainverifytoken', now(), now())
ON CONFLICT (website_id, method) DO UPDATE
  SET status = 'verified', verified_at = now(), last_checked_at = now();

DO $$
DECLARE
  payload    jsonb;
  v_job      text;
  v_req_by   uuid;
  v_status   jsonb;
BEGIN
  payload := public.seo_brain_request_technical_audit(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-ok2', 'BRAINVERIFY-action-1',
    'BRAINVERIFY-action-1:execute.technical_audit');

  IF payload->>'resolution' <> 'resolved' THEN
    RAISE EXCEPTION 'a verified, authorized delegated crawl must be accepted, got % (%)',
      payload->>'resolution', payload->>'detail';
  END IF;

  v_job := payload->>'moduleOperationId';

  -- The handle is a REAL crawl job on the REAL control plane.
  SELECT j.requested_by INTO v_req_by
  FROM public.seo_crawl_jobs j
  WHERE j.id = v_job::uuid
    AND j.website_id = 'b1000000-0000-4000-8000-00000000000a';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'moduleOperationId must be a real crawl job for this website';
  END IF;

  -- Attribution is the real human, not a system account.
  IF v_req_by IS DISTINCT FROM current_setting('b1.actor_ok')::uuid THEN
    RAISE EXCEPTION 'requested_by must be the resolved human, got %', v_req_by;
  END IF;

  -- Idempotent replay returns the same operation, not a second crawl.
  payload := public.seo_brain_request_technical_audit(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-ok2', 'BRAINVERIFY-action-1',
    'BRAINVERIFY-action-1:execute.technical_audit');
  IF payload->>'moduleOperationId' <> v_job OR (payload->>'replayed')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'a repeated Brain action must replay the same operation';
  END IF;

  -- STATUS correlates on the same Brain action.
  v_status := public.seo_brain_technical_audit_status(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-action-1', v_job);
  IF v_status->>'resolution' <> 'resolved' THEN
    RAISE EXCEPTION 'status must resolve, got %', v_status->>'resolution';
  END IF;

  -- A handle that is not this operation's fails closed.
  v_status := public.seo_brain_technical_audit_status(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-action-1', gen_random_uuid()::text);
  IF v_status->>'resolution' <> 'operation_mismatch' THEN
    RAISE EXCEPTION 'a foreign operation id must fail closed, got %', v_status->>'resolution';
  END IF;

  -- An unknown Brain action is not answered.
  v_status := public.seo_brain_technical_audit_status(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-action-never', NULL);
  IF v_status->>'resolution' <> 'operation_not_found' THEN
    RAISE EXCEPTION 'an unknown action must not be answered, got %', v_status->>'resolution';
  END IF;

  -- The other tenant cannot see this operation at all.
  v_status := public.seo_brain_technical_audit_status(
    'brain-biz-2', 'brainverify-c.test', 'BRAINVERIFY-action-1', v_job);
  IF v_status->>'resolution' = 'resolved' THEN
    RAISE EXCEPTION 'a cross-tenant status poll must never resolve';
  END IF;
END $$;

-- Delegated recommendation generation over the genuine crawler audit.
DO $$
DECLARE payload jsonb;
BEGIN
  payload := public.seo_brain_generate_recommendations(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-ok2', 'BRAINVERIFY-action-2',
    'BRAINVERIFY-action-2:execute.recommendations');

  IF payload->>'resolution' <> 'resolved' THEN
    RAISE EXCEPTION 'delegated generation must succeed over genuine crawler evidence, got % (%)',
      payload->>'resolution', payload->>'detail';
  END IF;
  IF coalesce(payload->>'generationMethod', '') = '' THEN
    RAISE EXCEPTION 'the stored generation method must be reported back';
  END IF;

  -- An unauthorized actor is refused even with a valid machine caller.
  payload := public.seo_brain_generate_recommendations(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-actor-nomem', 'BRAINVERIFY-action-3',
    'BRAINVERIFY-action-3:execute.recommendations');
  IF payload->>'resolution' <> 'actor_unauthorized' THEN
    RAISE EXCEPTION 'an unauthorized actor must be refused, got %', payload->>'resolution';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6d. Operation correlation is keyed per WEBSITE, not per Business.
--
--     One Business can have more than one website linked. Reusing a Brain
--     action id across them must produce two independent operations. If the
--     uniqueness key omitted website_id, this second request would collide with
--     the first website's row instead.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_cols text[];
BEGIN
  SELECT array_agg(a.attname::text ORDER BY a.attname::text) INTO v_cols
  FROM pg_constraint c
  JOIN unnest(c.conkey) AS k(attnum) ON true
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
  WHERE c.conname = 'seo_brain_operations_action_uniq'
    AND c.conrelid = 'public.seo_brain_operations'::regclass;

  IF v_cols IS DISTINCT FROM ARRAY['brain_action_id', 'business_id', 'capability', 'website_id'] THEN
    RAISE EXCEPTION
      'seo_brain_operations_action_uniq must be (business_id, website_id, capability, brain_action_id), got %',
      v_cols;
  END IF;
END $$;

-- Link the sibling website to the SAME Business and verify its ownership.
INSERT INTO public.seo_brain_website_links (business_id, normalized_host, workspace_id, website_id)
VALUES ('brain-biz-1', 'x', 'b1000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-00000000000b');

INSERT INTO public.seo_ownership_verifications
  (workspace_id, website_id, website_url, verification_host, method, status,
   challenge_token, verified_at, last_checked_at)
VALUES
  ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-00000000000b',
   'https://shop.brainverify-a.test', 'shop.brainverify-a.test', 'dns_txt', 'verified',
   'digibility-site-verification=brainverifytoken2', now(), now())
ON CONFLICT (website_id, method) DO UPDATE
  SET status = 'verified', verified_at = now(), last_checked_at = now();

DO $$
DECLARE
  v_first   text;
  v_second  text;
  v_payload jsonb;
  v_n       integer;
  v_status  jsonb;
BEGIN
  SELECT o.module_operation_id INTO v_first
  FROM public.seo_brain_operations o
  WHERE o.business_id = 'brain-biz-1'
    AND o.capability = 'execute.technical_audit'
    AND o.brain_action_id = 'BRAINVERIFY-action-1'
    AND o.website_id = 'b1000000-0000-4000-8000-00000000000a';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'the first website operation should already exist';
  END IF;

  -- Same Business, same Brain action, DIFFERENT website.
  v_payload := public.seo_brain_request_technical_audit(
    'brain-biz-1', 'shop.brainverify-a.test', 'BRAINVERIFY-actor-ok2', 'BRAINVERIFY-action-1',
    'BRAINVERIFY-action-1:execute.technical_audit');

  IF v_payload->>'resolution' <> 'resolved' THEN
    RAISE EXCEPTION 'the sibling website must get its own operation, got % (%)',
      v_payload->>'resolution', v_payload->>'detail';
  END IF;
  IF (v_payload->>'replayed')::boolean IS TRUE THEN
    RAISE EXCEPTION 'a different website must not replay another website''s operation';
  END IF;

  v_second := v_payload->>'moduleOperationId';
  IF v_second = v_first THEN
    RAISE EXCEPTION 'two websites must not share one operation handle';
  END IF;

  SELECT count(*) INTO v_n
  FROM public.seo_brain_operations o
  WHERE o.business_id = 'brain-biz-1'
    AND o.capability = 'execute.technical_audit'
    AND o.brain_action_id = 'BRAINVERIFY-action-1';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'expected two independent operations, got %', v_n;
  END IF;

  -- The first website's stored handle is untouched, which is exactly what the
  -- old Business-wide key would have clobbered.
  v_status := public.seo_brain_technical_audit_status(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-action-1', v_first);
  IF v_status->>'resolution' <> 'resolved' THEN
    RAISE EXCEPTION 'the first website status must still resolve, got %', v_status->>'resolution';
  END IF;

  -- And each website refuses the other's handle.
  v_status := public.seo_brain_technical_audit_status(
    'brain-biz-1', 'brainverify-a.test', 'BRAINVERIFY-action-1', v_second);
  IF v_status->>'resolution' <> 'operation_mismatch' THEN
    RAISE EXCEPTION 'a sibling website handle must fail closed, got %', v_status->>'resolution';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 7. Teardown + net-nothing proof.
-- ---------------------------------------------------------------------------
DELETE FROM public.seo_recommendations
  WHERE website_id IN ('b1000000-0000-4000-8000-00000000000a',
                       'b1000000-0000-4000-8000-00000000000b',
                       'b1000000-0000-4000-8000-00000000000c');
DELETE FROM public.seo_audit_issues
  WHERE audit_run_id IN ('b1000000-0000-4000-8000-0000000000e1',
                         'b1000000-0000-4000-8000-0000000000e2');
DELETE FROM public.seo_audit_runs
  WHERE id IN ('b1000000-0000-4000-8000-0000000000e1', 'b1000000-0000-4000-8000-0000000000e2');
DELETE FROM public.seo_brain_operations
  WHERE business_id IN ('brain-biz-1', 'brain-biz-2');
DELETE FROM public.seo_crawl_jobs
  WHERE website_id IN ('b1000000-0000-4000-8000-00000000000a',
                       'b1000000-0000-4000-8000-00000000000b',
                       'b1000000-0000-4000-8000-00000000000c');
DELETE FROM public.seo_ownership_verifications
  WHERE website_id IN ('b1000000-0000-4000-8000-00000000000a',
                       'b1000000-0000-4000-8000-00000000000b',
                       'b1000000-0000-4000-8000-00000000000c');
DELETE FROM public.seo_brain_actor_links
  WHERE brain_actor_id LIKE 'BRAINVERIFY-actor-%';
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

  SELECT count(*) INTO n FROM public.seo_brain_actor_links
  WHERE brain_actor_id LIKE 'BRAINVERIFY-actor-%';
  IF n <> 0 THEN RAISE EXCEPTION 'residue: % actor mappings remain', n; END IF;

  SELECT count(*) INTO n FROM public.seo_brain_operations
  WHERE business_id LIKE 'brain-biz-%';
  IF n <> 0 THEN RAISE EXCEPTION 'residue: % operation rows remain', n; END IF;
END $$;

SELECT 'seo_brain_module_boundary_verification: ALL ASSERTIONS PASSED' AS result;
