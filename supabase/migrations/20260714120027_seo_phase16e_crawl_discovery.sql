-- =============================================================================
-- SEO Backend — Phase 16E (Crawler 1C) — Migration 27: Crawl Discovery Storage
-- =============================================================================
-- Additive only. Builds on migrations 25 (control plane) + 26 (worker lifecycle).
-- Adds crawler-domain discovery storage (discovered pages + sitemaps) and TWO
-- service-role-only worker RPCs to persist them + progress. Does NOT edit any
-- prior migration, does NOT write Page Inventory / Audit / Stage 6 / Page
-- Performance tables, and does NOT crawl anything. Applied to Digi_SEO_Test only;
-- production untouched. No existing status value or RPC signature changed.
--
-- Security: discovery tables are worker-owned. Customers may READ customer-safe
-- fields for their own workspace (RLS: is_seo_workspace_member OR global admin),
-- but have NO insert/update/delete. Writes happen only via the two SECURITY
-- DEFINER RPCs below, which validate lease ownership (Phase 16D lease_token) and
-- derive workspace/website SERVER-SIDE from the job — never from the caller.
-- EXECUTE is REVOKED from PUBLIC/anon/authenticated and GRANTed to service_role.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Additive progress column on jobs.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_crawl_jobs ADD COLUMN IF NOT EXISTS discovery_stats jsonb;

-- ---------------------------------------------------------------------------
-- 2. seo_crawl_discovered_pages — one discovered URL per job (customer-safe).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_discovered_pages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  normalized_url text NOT NULL,
  discovered_url text NOT NULL,
  final_url text,
  discovery_source text NOT NULL CHECK (discovery_source IN ('start','sitemap','html_link')),
  parent_url text,
  sitemap_url text,
  depth integer NOT NULL DEFAULT 0 CHECK (depth >= 0),
  queue_order integer NOT NULL DEFAULT 0 CHECK (queue_order >= 0),
  robots_decision text NOT NULL DEFAULT 'not_evaluated'
    CHECK (robots_decision IN ('allowed','disallowed','not_evaluated')),
  fetch_status text NOT NULL DEFAULT 'queued'
    CHECK (fetch_status IN ('queued','fetched','blocked_robots','skipped','failed')),
  http_status integer,
  content_type text,
  response_bytes integer CHECK (response_bytes IS NULL OR response_bytes >= 0),
  redirect_count integer CHECK (redirect_count IS NULL OR redirect_count >= 0),
  sitemap_lastmod text,
  error_code text,                                       -- customer-safe code only
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seo_crawl_discovered_pages_uniq UNIQUE (job_id, normalized_url)
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_pages_job_order ON public.seo_crawl_discovered_pages (job_id, queue_order);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_pages_job_status ON public.seo_crawl_discovered_pages (job_id, fetch_status);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_pages_website ON public.seo_crawl_discovered_pages (website_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_seo_crawl_pages_updated_at ON public.seo_crawl_discovered_pages;
CREATE TRIGGER trg_seo_crawl_pages_updated_at BEFORE UPDATE ON public.seo_crawl_discovered_pages
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. seo_crawl_sitemaps — one fetched sitemap per job.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_sitemaps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  sitemap_url text NOT NULL,
  parent_sitemap_url text,
  sitemap_type text NOT NULL DEFAULT 'unknown' CHECK (sitemap_type IN ('urlset','sitemapindex','unknown')),
  fetch_status text NOT NULL DEFAULT 'failed' CHECK (fetch_status IN ('parsed','failed')),
  urls_discovered integer NOT NULL DEFAULT 0 CHECK (urls_discovered >= 0),
  error_code text,
  depth integer NOT NULL DEFAULT 0 CHECK (depth >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seo_crawl_sitemaps_uniq UNIQUE (job_id, sitemap_url)
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_sitemaps_job ON public.seo_crawl_sitemaps (job_id);

-- ---------------------------------------------------------------------------
-- 4. RLS — customer read (own workspace), no customer writes.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_crawl_discovered_pages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_crawl_discovered_pages_select ON public.seo_crawl_discovered_pages;
CREATE POLICY seo_crawl_discovered_pages_select ON public.seo_crawl_discovered_pages
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());

ALTER TABLE public.seo_crawl_sitemaps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_crawl_sitemaps_select ON public.seo_crawl_sitemaps;
CREATE POLICY seo_crawl_sitemaps_select ON public.seo_crawl_sitemaps
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());
-- No INSERT/UPDATE/DELETE policy on either → all customer writes denied.

-- ---------------------------------------------------------------------------
-- 5. seo_crawl_worker_record_discovery — worker-only bulk upsert.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_record_discovery(
  p_job_id uuid, p_worker_id text, p_lease_token uuid,
  p_pages jsonb DEFAULT '[]'::jsonb, p_sitemaps jsonb DEFAULT '[]'::jsonb
)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE; v_ws uuid; v_site uuid; v_count int := 0;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('claimed','running') THEN RAISE EXCEPTION 'record not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  v_ws := v_job.workspace_id; v_site := v_job.website_id;  -- server-side, never from caller

  INSERT INTO public.seo_crawl_discovered_pages
    (job_id, workspace_id, website_id, normalized_url, discovered_url, final_url, discovery_source,
     parent_url, sitemap_url, depth, queue_order, robots_decision, fetch_status, http_status,
     content_type, response_bytes, redirect_count, sitemap_lastmod, error_code)
  SELECT p_job_id, v_ws, v_site, x."normalizedUrl", x."discoveredUrl", x."finalUrl",
         coalesce(x."discoverySource",'html_link'), x."parentUrl", x."sitemapUrl",
         coalesce(x."depth",0), coalesce(x."queueOrder",0),
         coalesce(x."robotsDecision",'not_evaluated'), coalesce(x."fetchStatus",'queued'),
         x."httpStatus", left(x."contentType",120), x."responseBytes", x."redirectCount",
         left(x."sitemapLastmod",64), left(x."errorCode",80)
  FROM jsonb_to_recordset(coalesce(p_pages,'[]'::jsonb)) AS x(
    "normalizedUrl" text, "discoveredUrl" text, "finalUrl" text, "discoverySource" text,
    "parentUrl" text, "sitemapUrl" text, "depth" int, "queueOrder" int, "robotsDecision" text,
    "fetchStatus" text, "httpStatus" int, "contentType" text, "responseBytes" int,
    "redirectCount" int, "sitemapLastmod" text, "errorCode" text)
  WHERE x."normalizedUrl" IS NOT NULL
  ON CONFLICT (job_id, normalized_url) DO UPDATE SET
    final_url = EXCLUDED.final_url, fetch_status = EXCLUDED.fetch_status,
    http_status = EXCLUDED.http_status, content_type = EXCLUDED.content_type,
    response_bytes = EXCLUDED.response_bytes, redirect_count = EXCLUDED.redirect_count,
    robots_decision = EXCLUDED.robots_decision, error_code = EXCLUDED.error_code,
    updated_at = now();
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO public.seo_crawl_sitemaps
    (job_id, workspace_id, website_id, sitemap_url, parent_sitemap_url, sitemap_type, fetch_status, urls_discovered, error_code, depth)
  SELECT p_job_id, v_ws, v_site, s."sitemapUrl", s."parentSitemapUrl",
         coalesce(s."sitemapType",'unknown'), coalesce(s."fetchStatus",'failed'),
         coalesce(s."urlsDiscovered",0), left(s."errorCode",80), coalesce(s."depth",0)
  FROM jsonb_to_recordset(coalesce(p_sitemaps,'[]'::jsonb)) AS s(
    "sitemapUrl" text, "parentSitemapUrl" text, "sitemapType" text, "fetchStatus" text,
    "urlsDiscovered" int, "errorCode" text, "depth" int)
  WHERE s."sitemapUrl" IS NOT NULL
  ON CONFLICT (job_id, sitemap_url) DO UPDATE SET
    sitemap_type = EXCLUDED.sitemap_type, fetch_status = EXCLUDED.fetch_status,
    urls_discovered = EXCLUDED.urls_discovered, error_code = EXCLUDED.error_code;

  RETURN v_count;
END; $$;

-- ---------------------------------------------------------------------------
-- 6. seo_crawl_worker_update_discovery_progress — bounded progress snapshot.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_update_discovery_progress(
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_stats jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('claimed','running') THEN RAISE EXCEPTION 'progress not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  -- Only progress fields are updated — never status/ownership/authorization.
  UPDATE public.seo_crawl_jobs
    SET discovery_stats = p_stats,
        pages_discovered = GREATEST(pages_discovered, coalesce((p_stats->>'urlsDiscovered')::int, 0)),
        pages_crawled   = GREATEST(pages_crawled,   coalesce((p_stats->>'pagesFetched')::int, 0))
    WHERE id = p_job_id;
END; $$;

-- ---------------------------------------------------------------------------
-- 7. Grants — worker functions: service_role ONLY.
-- ---------------------------------------------------------------------------
DO $g$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_crawl_worker_record_discovery(uuid,text,uuid,jsonb,jsonb)',
    'public.seo_crawl_worker_update_discovery_progress(uuid,text,uuid,jsonb)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $g$;

-- =============================================================================
-- End Phase 16E discovery storage. Deferred to Phase 1D: page extraction +
-- technical SEO issue detection + Page Inventory/Audit integration. No crawling
-- runs from this migration; customer RLS + locked modules unchanged; production
-- untouched.
-- =============================================================================
