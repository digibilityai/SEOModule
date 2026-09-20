-- =============================================================================
-- SEO Backend, Digi Brain Module Contract v1, Stage 2B, Migration 1 of 2:
--   machine-boundary identity (canonical host normalizer + human-authorized
--   Business/website link)
-- =============================================================================
-- Additive only. Introduces the deterministic mapping a machine caller (Digi
-- Brain) needs in order to address exactly one SEO website, and nothing else.
-- Does NOT edit any locked migration, table, RPC or RLS policy. Does NOT touch
-- seo_websites, seo_workspaces, seo_workspace_members, the crawler control
-- plane, ownership verification, or any customer read/write path.
--
-- WHY A NEW NORMALIZER RATHER THAN REUSING AN EXISTING ONE.
-- Two host normalizers already exist in this repository and they disagree:
--   * public.seo_ownership_extract_host (migration 20260716120032) strips the
--     scheme, userinfo, path/query/fragment and the port, but KEEPS a leading
--     "www.". It is inside the locked P1a Domain Ownership Verification module.
--   * The inline normalizer in public.seo_competitor_generate (migration
--     20260724120040) STRIPS a leading "www." and also strips the port. It is
--     inside the locked Competitor Benchmarking module.
-- Digi Brain's frozen Contract v1 identity is produced by normalizeWebsiteHost
-- (lib/identity/website-identity.ts), which lowercases the hostname, strips a
-- leading "www.", and PRESERVES a non-default port as "<host>:<port>". Neither
-- existing function matches that, and changing either one would alter a locked
-- module's behaviour for existing customer data. This migration therefore adds
-- a THIRD, separate function used ONLY at the machine boundary. The two
-- existing normalizers are read-only references here and are not modified.
--
-- DETERMINISM GUARANTEES ESTABLISHED HERE:
--   * normalized_host is DERIVED server-side from the linked website's own
--     website_url by a trigger. It is never accepted from a caller, so a link
--     can never claim host A while pointing at a website whose URL is host B.
--   * workspace_id is DERIVED from the linked website. A link can never span
--     two workspaces.
--   * At most one ACTIVE link per (business_id, normalized_host), and at most
--     one ACTIVE link per website_id. Resolution is therefore exact or absent,
--     never ambiguous and never "pick one".
--   * Creating a link is a HUMAN action, gated by the existing owner/admin
--     role check (public.seo_role_in). No machine path may create one.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Canonical machine-boundary host normalizer.
--
-- Mirrors Digi Brain's normalizeWebsiteHost exactly for the inputs Brain can
-- produce, and returns NULL rather than guessing for anything it cannot parse
-- the same way the WHATWG URL parser would:
--   * a scheme-less input is treated as https (Brain prefixes "https://");
--   * userinfo, path, query and fragment are removed;
--   * the hostname is lowercased;
--   * a single leading "www." is removed from the hostname only, never from
--     the port;
--   * a port equal to its scheme's default is dropped (WHATWG reports an empty
--     port in that case); any other port is significant and is preserved;
--   * leading zeros in a port are removed and an out-of-range port is a parse
--     failure (NULL), matching the URL parser;
--   * subdomains stay distinct and no public-suffix/registrable-domain
--     reduction is performed, matching Brain's documented behaviour.
-- IMMUTABLE and free of table access, so it is safe in an index or a CHECK.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_normalize_host(p_website_url text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_raw       text;
  v_scheme    text;
  v_authority text;
  v_host      text;
  v_port_text text;
  v_port      integer;
BEGIN
  v_raw := btrim(coalesce(p_website_url, ''));
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

REVOKE ALL ON FUNCTION public.seo_brain_normalize_host(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_normalize_host(text) FROM anon;
-- Authenticated needs EXECUTE so the human-facing link INSERT trigger can run
-- under the acting user; service_role needs it for the delegated read RPCs.
GRANT EXECUTE ON FUNCTION public.seo_brain_normalize_host(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seo_brain_normalize_host(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. seo_brain_website_links: the human-authorized Brain Business to SEO
--    website mapping. One row is an explicit authorization by a workspace
--    owner/admin that a named Digi Brain Business may address one specific SEO
--    website. There is deliberately no inference, no name matching and no
--    machine-side creation path.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_brain_website_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Digi Brain businesses.id. Held as text, not uuid: Contract v1 types it as
  -- a plain string and it belongs to a different Supabase project, so SEO must
  -- not assume or enforce its internal format.
  business_id text NOT NULL CHECK (length(btrim(business_id)) BETWEEN 1 AND 200),
  -- DERIVED from the linked website by trg_seo_brain_website_links_derive.
  -- Never accepted from a caller.
  normalized_host text NOT NULL,
  -- DERIVED from the linked website. Present so resolution and every RLS check
  -- can be workspace-scoped without a join.
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  link_status text NOT NULL DEFAULT 'active'
    CHECK (link_status IN ('active', 'revoked')),
  -- The human who authorized this link. Set server-side from auth.uid().
  linked_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  revoked_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Exactly one ACTIVE link per (Business, host): resolution is exact or absent.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_brain_website_links_business_host
  ON public.seo_brain_website_links (business_id, normalized_host)
  WHERE link_status = 'active';

-- Exactly one ACTIVE link per SEO website: a website is never claimed by two
-- Businesses at the same time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_brain_website_links_website
  ON public.seo_brain_website_links (website_id)
  WHERE link_status = 'active';

CREATE INDEX IF NOT EXISTS idx_seo_brain_website_links_workspace
  ON public.seo_brain_website_links (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_brain_website_links_lookup
  ON public.seo_brain_website_links (business_id, normalized_host, link_status);

-- ---------------------------------------------------------------------------
-- 3. Derivation trigger. workspace_id and normalized_host are computed from
--    the linked website, so a caller cannot assert either one. This is the
--    structural guarantee against a link that points at a different website
--    than the host it claims.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_website_links_derive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ws   uuid;
  v_url  text;
  v_host text;
BEGIN
  SELECT w.workspace_id, w.website_url
    INTO v_ws, v_url
  FROM public.seo_websites w
  WHERE w.id = NEW.website_id;

  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Website not found';
  END IF;

  v_host := public.seo_brain_normalize_host(v_url);
  IF v_host IS NULL THEN
    RAISE EXCEPTION 'Website URL cannot be normalized to a canonical host';
  END IF;

  NEW.workspace_id    := v_ws;
  NEW.normalized_host := v_host;
  NEW.business_id     := btrim(NEW.business_id);

  IF TG_OP = 'INSERT' THEN
    NEW.linked_by := auth.uid();
    NEW.linked_at := now();
  END IF;

  -- Revocation bookkeeping is server-set so an audit reader can trust it.
  IF TG_OP = 'UPDATE' AND NEW.link_status = 'revoked' AND OLD.link_status <> 'revoked' THEN
    NEW.revoked_by := auth.uid();
    NEW.revoked_at := now();
  END IF;

  -- A revoked link is terminal. Reactivating would silently resurrect an
  -- authorization a human deliberately withdrew; a new link row is required.
  IF TG_OP = 'UPDATE' AND OLD.link_status = 'revoked' AND NEW.link_status <> 'revoked' THEN
    RAISE EXCEPTION 'A revoked Digi Brain website link cannot be reactivated; create a new link instead';
  END IF;

  -- The Business a link points at is fixed for the life of the row.
  IF TG_OP = 'UPDATE' AND NEW.business_id IS DISTINCT FROM OLD.business_id THEN
    RAISE EXCEPTION 'business_id cannot be changed on an existing link; revoke it and create a new one';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.website_id IS DISTINCT FROM OLD.website_id THEN
    RAISE EXCEPTION 'website_id cannot be changed on an existing link; revoke it and create a new one';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_brain_website_links_derive ON public.seo_brain_website_links;
CREATE TRIGGER trg_seo_brain_website_links_derive
  BEFORE INSERT OR UPDATE ON public.seo_brain_website_links
  FOR EACH ROW EXECUTE FUNCTION public.seo_brain_website_links_derive();

DROP TRIGGER IF EXISTS trg_seo_brain_website_links_updated_at ON public.seo_brain_website_links;
CREATE TRIGGER trg_seo_brain_website_links_updated_at
  BEFORE UPDATE ON public.seo_brain_website_links
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. RLS. Reuses the existing role helpers verbatim; introduces no new
--    authorization model. service_role bypasses RLS and is the only identity
--    the machine read path ever uses.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_brain_website_links ENABLE ROW LEVEL SECURITY;

-- Any active member of the website's workspace may SEE which Business a
-- website is linked to. Matches the existing "members may read their own
-- workspace's records" convention.
DROP POLICY IF EXISTS seo_brain_website_links_select ON public.seo_brain_website_links;
CREATE POLICY seo_brain_website_links_select
  ON public.seo_brain_website_links
  FOR SELECT
  TO authenticated
  USING (
    public.is_seo_workspace_member(workspace_id)
    OR public.seo_is_global_admin()
  );

-- Only an owner/admin of the website's workspace may AUTHORIZE a link. This is
-- the human authorization event the machine path depends on.
DROP POLICY IF EXISTS seo_brain_website_links_insert ON public.seo_brain_website_links;
CREATE POLICY seo_brain_website_links_insert
  ON public.seo_brain_website_links
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.seo_websites w
      WHERE w.id = website_id
        AND (
          public.seo_role_in(w.workspace_id, ARRAY['owner', 'admin'])
          OR public.seo_is_global_admin()
        )
    )
  );

-- Only an owner/admin may REVOKE. The derivation trigger restricts an UPDATE
-- to a status change; identity columns are immutable.
DROP POLICY IF EXISTS seo_brain_website_links_update ON public.seo_brain_website_links;
CREATE POLICY seo_brain_website_links_update
  ON public.seo_brain_website_links
  FOR UPDATE
  TO authenticated
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin'])
    OR public.seo_is_global_admin()
  )
  WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin'])
    OR public.seo_is_global_admin()
  );

-- No DELETE policy: a link is revoked, never erased, so the authorization
-- history stays readable.

REVOKE ALL ON FUNCTION public.seo_brain_website_links_derive() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_brain_website_links_derive() FROM anon;
