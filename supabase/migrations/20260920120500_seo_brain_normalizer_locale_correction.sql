-- =============================================================================
-- SEO Backend, Digi Brain Module Contract v1, Stage 2B, Migration 6:
--   Locale-independent character classes in the host normalizer
-- =============================================================================
-- Additive. Creates no table, no policy, no capability and no new object. It
-- replaces ONE function body in place.
--
-- WHY THIS IS A NEW FILE RATHER THAN AN EDIT TO 20260920120400.
-- 20260920120400 is already APPLIED and RECORDED on Digi_SEO_Test (47/47).
-- Migration history there is the authoritative truth, so an edit to an applied
-- file would never run and would leave the database and the repository
-- disagreeing. The correction is therefore expressed forward.
--
-- WHAT IS CORRECTED, AND HOW IT WAS FOUND.
-- 20260920120400 made the trim asymmetric, which was right, but expressed the
-- LEADING class as the POSIX class '[[:space:]]' on the assumption that it
-- equals JavaScript String.trim()'s ASCII set. The controlled TEST run of
-- supabase/test/seo_brain_module_boundary_verification.sql disproved that in
-- Section 0, before any mutation:
--
--   normalizer parity failed for "<US>example.com": expected <NULL>, got example.com
--
-- Measured on Digi_SEO_Test rather than assumed:
--
--   SELECT string_agg(i::text, ',' ORDER BY i)
--     FROM generate_series(1,32) i WHERE chr(i) ~ '[[:space:]]';
--   --> 9,10,11,12,13,28,29,30,31,32
--
-- glibc classifies FS (28), GS (29), RS (30) and US (31) as space characters.
-- JavaScript String.trim() does NOT: its ASCII set is TAB, LF, VT, FF, CR and
-- space, that is 9 through 13 plus 32. So '[[:space:]]' trimmed a leading
-- U+001C through U+001F and returned a clean canonical host for a value the
-- TypeScript twin refuses to parse. That is the same fail-open shape the
-- earlier review caught, moved to four different characters.
--
-- THE RULE THIS FILE ESTABLISHES. A POSIX character class must never be used
-- where the result has to MATCH JavaScript or WHATWG behaviour, because the
-- class membership is decided by the database's ctype and not by the standard
-- being mirrored. Where parity is the goal, the characters are written out.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Host normalizer, final form. Only the two trim classes and the forbidden
-- class are touched. Every other line is byte-for-byte what 20260920120400
-- applied, and every documented behaviour of that migration is preserved:
-- the asymmetric trim, TAB/LF/CR removal, authority-level rejection, IPv6
-- bracket handling, "www." stripping, default-port elision and the 0..65535
-- port range.
--
-- THE THREE CLASSES, and why each is written the way it is.
--
--   c_lead      EXPLICIT. This is a PARITY decision: it must equal JS
--               String.trim()'s ASCII set exactly, so it is written out as
--               chr(9) through chr(13) plus chr(32). Verified on TEST to
--               contain exactly 9,10,11,12,13,32 and to exclude 1, 28, 29,
--               30, 31 and 127.
--
--   c_trail     EXPLICIT, and unchanged from 20260920120400, which already
--               wrote it out. This is the URL parser's trailing
--               C0-control-or-space strip, chr(1) through chr(32). DEL
--               (chr(127)) is deliberately outside it: DEL is not a C0
--               control, the parser does not strip it, and it must fall
--               through to c_forbidden. chr(0) is absent because PostgreSQL
--               text cannot contain it.
--
--   c_forbidden EXPLICIT FLOOR PLUS POSIX CEILING, and this asymmetry is
--               deliberate rather than an oversight. This class is a REJECTION
--               gate, not a parity target, so the two kinds of error are not
--               equally bad: rejecting too much fails CLOSED and refuses a
--               host, while rejecting too little fails OPEN and admits one.
--               Writing chr(1)-chr(32) and chr(127) explicitly guarantees the
--               ASCII floor no matter what the database ctype says, which is
--               the lesson of this migration. Keeping [:space:] and [:cntrl:]
--               alongside preserves an existing fail-closed behaviour that a
--               purely explicit class would have SILENTLY REMOVED: on
--               Digi_SEO_Test those classes also match U+0085, U+00A0, U+1680,
--               U+2000, U+2007, U+2028, U+2029, U+202F, U+205F and U+3000, so
--               a host carrying non-ASCII whitespace is refused today. Dropping
--               them would have started admitting such hosts, which is exactly
--               the direction this whole sequence of corrections exists to
--               prevent.
--
-- Signature, volatility, security mode, search_path and grants are unchanged:
-- public.seo_brain_normalize_host(text) -> text, IMMUTABLE, SECURITY INVOKER,
-- SET search_path = public, EXECUTE to authenticated and service_role only.
-- Nothing depends on the body, so CREATE OR REPLACE is sufficient and the
-- derivation trigger and the four read RPCs keep working untouched.
--
-- STILL NOT A WHATWG PARSER. No public-suffix reduction, no IDN/punycode
-- conversion, no IPv4 canonicalization, no backslash-as-separator and no
-- percent-decoding of a host. Those divergences are pre-existing, are recorded
-- in SEO_BRAIN_MODULE_INTERFACE.md, and every one of them fails closed.
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
  -- LEADING trim: JS String.trim()'s ASCII set, written out. NOT '[[:space:]]',
  -- which on glibc also contains FS/GS/RS/US (28..31) and would trim a leading
  -- control character that TypeScript rejects.
  c_lead      constant text := '[' || chr(9) || '-' || chr(13) || chr(32) || ']';
  -- TRAILING trim: the URL parser's C0-control-or-space strip, chr(1)..chr(32).
  -- DEL (chr(127)) is excluded on purpose; it is not a C0 control.
  c_trail     constant text := '[' || chr(1) || '-' || chr(32) || ']';
  -- FORBIDDEN in a host or a port. Explicit ASCII floor (chr(1)..chr(32) and
  -- chr(127)) so it cannot shrink with the locale, plus the POSIX classes so it
  -- keeps refusing the non-ASCII whitespace it refuses today.
  c_forbidden constant text := '[' || chr(1) || '-' || chr(32) || chr(127) || '[:space:][:cntrl:]]';
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

  -- Whitespace and control characters are forbidden in the host and the port.
  -- Asserted here, after userinfo and path have gone, so a space in a path or
  -- in userinfo still parses exactly as it does in TypeScript.
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

COMMENT ON FUNCTION public.seo_brain_normalize_host(text) IS
  'Canonical machine-boundary host. Mirrors Digi Brain normalizeWebsiteHost for whitespace and control characters: the leading trim is JS String.trim()''s ASCII set written out explicitly (chr(9)..chr(13), chr(32)), the trailing trim is the parser''s chr(1)..chr(32), and anything else in the host or port fails the parse. POSIX classes are deliberately not used for the trims: on glibc [:space:] also contains chr(28)..chr(31) (20260920120500). NOT a full WHATWG parser: no IDN/punycode, no public-suffix reduction, no IPv4 canonicalization, no backslash-as-separator. Those divergences fail closed.';
