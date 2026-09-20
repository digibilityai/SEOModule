-- =============================================================================
-- SEO Backend, Digi Brain Module Contract v1, Stage 2B, Migration 5:
--   ADDITIVE runtime corrections found during controlled TEST verification
-- =============================================================================
-- Additive only. Creates no table, no policy and no new capability. It replaces
-- ONE function body in place and tightens table-level privileges that Supabase's
-- default grants had left open.
--
-- WHY THIS IS A NEW FILE RATHER THAN AN EDIT TO 20260920120000.
-- 20260920120000, 20260920120100, 20260920120200 and 20260920120300 are already
-- APPLIED and RECORDED on Digi_SEO_Test. Migration history there is the
-- authoritative truth, so an edit to an applied file would never run and would
-- leave the database and the repository disagreeing. Every correction below is
-- therefore expressed forward, as its own migration.
--
-- WHAT IS CORRECTED.
--   1. public.seo_brain_normalize_host admitted ASCII whitespace inside a host.
--      normalizeHost('not a url') returns NULL in TypeScript and returned
--      'not a url' in SQL. That is a genuine parity defect at the machine
--      boundary and is fixed here.
--   2. service_role held Supabase's default direct INSERT/UPDATE/DELETE on
--      public.seo_brain_actor_links and public.seo_brain_website_links, and
--      bypasses RLS. That contradicts the Stage 2B invariant that the machine
--      identity has NO path of any kind to creating a human authorization.
--      Those privileges are revoked here.
--   3. public.seo_brain_operations is written ONLY by the SECURITY DEFINER
--      delegated wrappers, so no client role needs direct mutation on it.
--      Direct mutation is revoked from all three client roles.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Host normalizer: reject ASCII whitespace and C0/DEL control characters in
--    the host/port, mirror the URL parser's tab/newline handling, and trim each
--    end of the input with the set that end actually uses.
--
-- THE DEFECT. The authority pattern was '^[^:\[\]/?#]+(:[0-9]*)?$'. A space is
-- none of the excluded characters, so 'not a url' matched and was returned
-- verbatim as if it were a canonical host. TypeScript's normalizeWebsiteHost
-- returns NULL for it, because the WHATWG URL parser treats a space in a host
-- as a forbidden host code point and fails the parse.
--
-- THE CORRECTION, and why it is exactly this size. Three things were measured
-- against the TypeScript twin rather than assumed:
--
--   * ASCII tab (U+0009), LF (U+000A) and CR (U+000D) are REMOVED from the
--     whole input by the URL parser before anything else is read, so
--     'exa<TAB>mple.com' normalizes to 'example.com' in TypeScript. Removing
--     them here is a single documented spec step, not a parser.
--   * The trim is ASYMMETRIC, because the TypeScript twin is. It calls JS
--     String.trim() on the RAW value and only THEN prefixes 'https://' for a
--     scheme-less input, so the URL parser's own leading trim never sees the
--     start of the caller's string. The two ends therefore differ:
--       - LEADING: JS String.trim() removes ASCII whitespace only, that is
--         TAB, LF, VT, FF, CR and space. A leading NUL, SOH or US survives
--         into the authority and fails the parse. So the leading trim is
--         '[[:space:]]', which is exactly that set. btrim/1 stripped only the
--         space character, so a lone form feed survived and was returned as a
--         host; that is the bug being fixed, and this fixes it without
--         admitting a leading control character.
--       - TRAILING: after prefixing, the caller's tail IS the parser's tail,
--         and the parser strips trailing C0-control-or-space. That is chr(1)
--         through chr(32). DEL (U+007F) is deliberately NOT in this range: it
--         is not a C0 control, the parser does not strip it, and it must fall
--         through to the forbidden-character check below.
--     A trailing NUL is the one input where the two sides cannot be compared:
--     PostgreSQL text cannot contain chr(0) at all, so SQL can never receive
--     that value.
--   * Every other ASCII whitespace or control character (space, VT, FF and the
--     rest of C0, plus DEL) inside the host or port is a PARSE FAILURE. This is
--     asserted on the authority AFTER userinfo and path/query/fragment have
--     been removed, because the parser forbids these characters in the host
--     only: 'https://example.com/a b' and 'https://us er:pa ss@example.com/x'
--     both normalize to 'example.com' in TypeScript and must keep doing so.
--
-- WHAT DELIBERATELY DID NOT CHANGE. No canonical valid-host output moves: every
-- currently valid host is ASCII letters, digits, dots, hyphens and an optional
-- port, none of which is in the rejected set. Nothing is broadened; the only
-- inputs whose result changes are ones that were previously accepted wrongly.
--
-- WHAT THIS IS NOT. This is NOT a WHATWG URL parser and does not claim full
-- fidelity to one. It corrects whitespace and control handling at the machine
-- boundary and nothing else. No public-suffix reduction, no IDN/punycode
-- conversion, no IPv4 canonicalization of 0x7f.1 or 2130706433, no backslash
-- as a path separator and no percent-decoding of a host are attempted. Those
-- remaining divergences are PRE-EXISTING and every one of them fails CLOSED:
-- SQL returns a value that can never equal a canonical host Brain would send,
-- so the comparison refuses rather than mismatching. They are recorded in
-- SEO_BRAIN_MODULE_INTERFACE.md rather than papered over, and deliberately not
-- fixed by rewriting a URL parser in PL/pgSQL.
--
-- Signature, volatility, security mode, search_path and grants are unchanged:
-- public.seo_brain_normalize_host(text) -> text, IMMUTABLE, SECURITY INVOKER,
-- SET search_path = public, EXECUTE to authenticated and service_role only.
-- Nothing depends on the body, so CREATE OR REPLACE is sufficient and the
-- derivation trigger and the four read RPCs keep working untouched.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_normalize_host(p_website_url text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  -- ASCII tab, LF and CR: removed from the input by the URL parser.
  c_strip     constant text := chr(9) || chr(10) || chr(13);
  -- LEADING trim: exactly JS String.trim()'s ASCII set, which is what the
  -- TypeScript twin applies to the raw value before it prefixes a scheme.
  -- '[[:space:]]' is TAB, LF, VT, FF, CR and space. A leading DEL or other
  -- C0 control is deliberately NOT trimmed: it must reach c_forbidden below.
  c_lead      constant text := '[[:space:]]';
  -- TRAILING trim: the URL parser's own trailing strip, C0-control-or-space,
  -- which is chr(1) through chr(32). Written as an explicit range because
  -- '[:cntrl:]' would also pull in DEL (chr(127)), which the parser does NOT
  -- strip. chr(0) is omitted because PostgreSQL text cannot contain it.
  c_trail     constant text := '[' || chr(1) || '-' || chr(32) || ']';
  -- Anything in this class is forbidden in a host or a port. [:cntrl:] covers
  -- C0 and DEL; [:space:] covers space, tab, LF, VT, FF and CR. The two
  -- overlap on purpose: neither alone covers both space and DEL.
  c_forbidden constant text := '[[:space:][:cntrl:]]';
  v_raw       text;
  v_scheme    text;
  v_authority text;
  v_host      text;
  v_port_text text;
  v_port      integer;
BEGIN
  v_raw := coalesce(p_website_url, '');

  -- Trim each end with the set that end actually uses (see the header), then
  -- remove every ASCII tab/LF/CR anywhere in the input, as the parser does.
  v_raw := regexp_replace(v_raw, '^' || c_lead || '+', '');
  v_raw := regexp_replace(v_raw, c_trail || '+$', '');
  v_raw := translate(v_raw, c_strip, '');

  IF v_raw = '' THEN
    RETURN NULL;
  END IF;

  -- Scheme. Brain parses a scheme-less value as https, so the scheme only ever
  -- decides which port counts as the default one.
  v_scheme := lower(substring(v_raw from '^([a-zA-Z][a-zA-Z0-9+.-]*)://'));
  IF v_scheme IS NULL THEN
    v_scheme    := 'https';
    v_authority := v_raw;
  ELSE
    v_authority := regexp_replace(v_raw, '^[a-zA-Z][a-zA-Z0-9+.-]*://', '');
  END IF;

  -- Authority only: userinfo first, then path/query/fragment.
  v_authority := regexp_replace(v_authority, '^[^/?#@]*@', '');
  v_authority := regexp_replace(v_authority, '[/?#].*$', '');
  IF v_authority = '' THEN
    RETURN NULL;
  END IF;

  -- THE FIX. Whitespace and control characters are forbidden in the host and
  -- the port. Asserted here, after userinfo and path have gone, so a space in
  -- a path or in userinfo still parses exactly as it does in TypeScript.
  IF v_authority ~ c_forbidden THEN
    RETURN NULL;                            -- forbidden host code point
  END IF;

  -- Split host from an optional port. An IPv6 literal keeps its brackets, as
  -- the URL parser does. Anything that matches neither shape is a parse
  -- failure, not a value to guess at.
  IF v_authority ~ '^\[[0-9A-Fa-f:.]+\](:[0-9]*)?$' THEN
    v_host      := lower(substring(v_authority from '^(\[[0-9A-Fa-f:.]+\])'));
    v_port_text := substring(v_authority from ':([0-9]*)$');
  ELSIF v_authority ~ '^[^:\[\]/?#]+(:[0-9]*)?$' THEN
    v_host      := lower(split_part(v_authority, ':', 1));
    v_port_text := substring(v_authority from ':([0-9]*)$');
    -- "www." is stripped from the hostname alone, before any port is
    -- reattached, so it can never touch the port.
    IF v_host LIKE 'www.%' THEN
      v_host := substring(v_host from 5);
    END IF;
  ELSE
    RETURN NULL;
  END IF;

  IF v_host IS NULL OR v_host = '' THEN
    RETURN NULL;
  END IF;

  -- An empty port ("example.com:") is no port at all, as in the URL parser.
  IF v_port_text IS NULL OR v_port_text = '' THEN
    RETURN v_host;
  END IF;

  v_port := v_port_text::integer;          -- also drops leading zeros
  IF v_port < 0 OR v_port > 65535 THEN
    RETURN NULL;                            -- URL parse failure
  END IF;

  -- Default port for the scheme is reported as absent by the URL parser.
  IF (v_scheme = 'https' AND v_port = 443)
     OR (v_scheme = 'http' AND v_port = 80)
     OR (v_scheme = 'wss'  AND v_port = 443)
     OR (v_scheme = 'ws'   AND v_port = 80)
     OR (v_scheme = 'ftp'  AND v_port = 21) THEN
    RETURN v_host;
  END IF;

  RETURN v_host || ':' || v_port::text;
END;
$$;

-- Grants restated verbatim so this migration is self-describing and so a
-- rebuilt-from-scratch project ends in exactly the same state.
REVOKE ALL ON FUNCTION public.seo_brain_normalize_host(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_normalize_host(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_brain_normalize_host(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_normalize_host(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. seo_brain_actor_links: the machine identity must not be able to create a
--    human authorization.
--
-- WHAT THE TEST RUN FOUND. Supabase grants ALL on every new public table to
-- anon, authenticated and service_role by default. service_role additionally
-- bypasses RLS. The Stage 2B design states plainly that an actor mapping is a
-- human global-admin act with no machine path, and that
-- seo_brain_bootstrap_actor_link is revoked from service_role precisely so the
-- machine cannot mint its own human. The default table grant made that RPC
-- revocation moot: service_role could simply INSERT the row.
--
-- WHAT IS REVOKED, AND WHAT IS NOT.
--   * service_role loses INSERT, UPDATE, DELETE, TRUNCATE. It KEEPS SELECT,
--     which is genuinely required: public.seo_brain_resolve_actor is
--     SECURITY INVOKER and is granted to service_role, so it reads this table
--     as service_role. Revoking SELECT would break actor resolution and with it
--     both delegated write capabilities.
--   * anon loses everything. No policy on this table names anon, so RLS already
--     denied it; this closes the privilege as well, so a future policy cannot
--     widen anon by accident.
--   * authenticated KEEPS SELECT, INSERT and UPDATE. This was checked against
--     the RLS path rather than assumed: seo_brain_actor_links_insert and
--     seo_brain_actor_links_update are declared TO authenticated and are the
--     ONLY product path by which a global admin authorizes or revokes a
--     mapping. There is no SECURITY DEFINER RPC behind them, so revoking the
--     table privilege would break the intended human global-admin path
--     outright. DELETE and TRUNCATE are revoked: there is deliberately no
--     DELETE policy, because a mapping is revoked and never erased.
-- ---------------------------------------------------------------------------
REVOKE ALL ON TABLE public.seo_brain_actor_links FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.seo_brain_actor_links FROM service_role;
REVOKE DELETE, TRUNCATE ON TABLE public.seo_brain_actor_links FROM authenticated;

-- ---------------------------------------------------------------------------
-- 3. seo_brain_website_links: same invariant, same reasoning.
--
-- The link between a Digi Brain Business and an SEO website is an explicit
-- human authorization by a workspace owner/admin. 20260920120000 says there is
-- "deliberately no inference, no name matching and no machine-side creation
-- path", and the derivation trigger exists so a caller cannot assert
-- normalized_host or workspace_id. A service_role INSERT would still have
-- produced a trigger-derived, perfectly well-formed link that no human ever
-- authorized, which is the exact outcome the design forbids.
--
-- service_role KEEPS SELECT: all four delegated read RPCs
-- (seo_brain_resolve_target and friends) are SECURITY INVOKER and resolve links
-- as service_role. authenticated KEEPS SELECT/INSERT/UPDATE for the owner/admin
-- RLS path. No DELETE policy exists here either, for the same reason.
-- ---------------------------------------------------------------------------
REVOKE ALL ON TABLE public.seo_brain_website_links FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.seo_brain_website_links FROM service_role;
REVOKE DELETE, TRUNCATE ON TABLE public.seo_brain_website_links FROM authenticated;

-- ---------------------------------------------------------------------------
-- 4. seo_brain_operations: hardened, after establishing its intended mutation
--    path rather than by reflex.
--
-- THE INTENDED PATH, as read from 20260920120300. Every row is written by
-- seo_brain_request_technical_audit or seo_brain_generate_recommendations and
-- updated by their STATUS counterparts. All four are SECURITY DEFINER and run
-- as the function owner, which is also the table owner, so none of them relies
-- on a client role's table privilege. The table carries a SELECT policy for
-- workspace members and NO write policy at all, and its comment states the rows
-- "are written by the delegated wrappers only".
--
-- THE DECISION. No client role needs direct mutation, so direct mutation is
-- revoked from all three. This is strictly narrower than the RLS posture the
-- table already declares, so it removes no product capability. SELECT is left
-- in place for authenticated (the member-read policy governs it) and for
-- service_role (harmless read-only, and consistent with the other two tables).
-- ---------------------------------------------------------------------------
REVOKE ALL ON TABLE public.seo_brain_operations FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.seo_brain_operations FROM service_role;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.seo_brain_operations FROM authenticated;

-- ---------------------------------------------------------------------------
-- 5. Corrected rationale for public.seo_brain_bootstrap_actor_link.
--
-- The rationale written into 20260920120200 is STALE and is corrected here
-- rather than edited there, because that migration is applied. It claimed that
-- public.seo_is_global_admin() "reads public.profiles", that this repository
-- never creates public.profiles, and that the function therefore returns false
-- for every user on a standalone SEO project. The live Digi_SEO_Test state
-- disproves the premise: 20260720121000_seo_cross_project_identity_bridge
-- extends seo_is_global_admin() through public.seo_identity_profiles, so
-- public.profiles is not the only source it can resolve an admin from.
--
-- THE ACTUAL REASON THE BOOTSTRAP EXISTS, which the stale text obscured:
--
--   * A target environment may simply contain no reachable global-admin
--     identity. Whether seo_is_global_admin() reads public.profiles,
--     seo_identity_profiles or both is beside the point; what matters is that
--     on Digi_SEO_Test no signed-in session satisfies it today, so the FIRST
--     actor mapping cannot be created through the ordinary RLS INSERT policy
--     and the delegated write path could never be exercised at all.
--   * The bootstrap is the operator's way in, and nothing more. It creates no
--     role, changes no policy, and is revoked from PUBLIC, anon, authenticated
--     and service_role, so only the database owner in a direct operator session
--     can reach it. The machine endpoint authenticates as service_role and, as
--     of section 2 above, now has neither the RPC nor the table privilege.
--   * It infers NO identity. Both the SEO user being mapped and the human
--     authorizing the mapping are required arguments and must already exist in
--     auth.users. There is no email match, no display-name match, no workspace
--     ownership fallback, no "the only admin" heuristic, and no fallback to the
--     session or to the linked user. A direct SQL session has no auth.uid() to
--     borrow, which is exactly why the authorizer is stated rather than
--     defaulted.
--
-- This corrects the recorded reason only. The global-admin architecture is
-- unchanged and is deliberately not redesigned here.
-- ---------------------------------------------------------------------------
COMMENT ON FUNCTION public.seo_brain_bootstrap_actor_link(text, uuid, uuid) IS
  'Operator-only bootstrap for the FIRST Digi Brain actor mapping. Needed because a target environment may contain no reachable global-admin identity, so the authenticated RLS INSERT path cannot create the first mapping. Requires an explicit human authorizer and infers no identity. Revoked from PUBLIC, anon, authenticated and service_role. See migration 20260920120400.';

COMMENT ON TABLE public.seo_brain_actor_links IS
  'Human-authorized mapping from a Digi Brain actorId to one SEO auth.users identity. Created only by a global admin through RLS, or by the operator bootstrap. service_role holds SELECT only (20260920120400): the machine identity has no path to creating a mapping.';

COMMENT ON TABLE public.seo_brain_website_links IS
  'Human-authorized mapping from a Digi Brain businessId plus canonical host to one SEO website. normalized_host and workspace_id are trigger-derived. service_role holds SELECT only (20260920120400): the machine identity has no path to creating a link.';

COMMENT ON FUNCTION public.seo_brain_normalize_host(text) IS
  'Canonical machine-boundary host. Mirrors Digi Brain normalizeWebsiteHost for whitespace and control characters: leading trim is ASCII whitespace only, trailing trim is C0-or-space, and any whitespace or C0/DEL control left in the host or port fails the parse (20260920120400). NOT a full WHATWG parser: no IDN/punycode, no public-suffix reduction, no IPv4 canonicalization, no backslash-as-separator. Those divergences fail closed.';
