-- =============================================================================
-- SEO Backend — Phase 16F (Crawler 1D) — Migration 28: Extraction + Issues
-- =============================================================================
-- Additive only. Builds on migrations 25–27. Adds crawler-domain page-extraction
-- snapshots + detected-issue storage and THREE service-role-only worker RPCs.
-- Does NOT publish into seo_page_inventory / seo_audit_issues / seo_recommendations
-- (Phase 1E), does NOT write Stage 6 / Page Performance, does NOT crawl. Applied
-- to Digi_SEO_Test only; production untouched. No existing status/RPC changed.
--
-- Data minimization: snapshots store only technical metadata + counts + a content
-- HASH — never full HTML, full text, scripts, JSON-LD, forms, cookies, headers
-- (beyond the allowlisted x-robots fact captured as effective_* directives), PII
-- or stack traces. Issue evidence is bounded + customer-safe. Customers may READ
-- their own workspace's snapshots/issues (RLS); NO customer writes. Worker RPCs
-- validate the Phase 16D lease_token, derive workspace/website server-side, are
-- SECURITY DEFINER + search_path=public, and are service_role-only.
-- =============================================================================

ALTER TABLE public.seo_crawl_jobs ADD COLUMN IF NOT EXISTS extraction_stats jsonb;

-- ---------------------------------------------------------------------------
-- 1. seo_crawl_page_snapshots — one technical snapshot per job + page URL.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_page_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  discovered_page_id uuid REFERENCES public.seo_crawl_discovered_pages(id) ON DELETE SET NULL,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  requested_url text NOT NULL,
  final_url text,
  http_status integer,
  redirect_count integer CHECK (redirect_count IS NULL OR redirect_count >= 0),
  content_type text,
  declared_charset text,
  decode_status text CHECK (decode_status IN ('ok','unsupported')),
  response_bytes integer CHECK (response_bytes IS NULL OR response_bytes >= 0),
  discovery_source text,
  depth integer NOT NULL DEFAULT 0 CHECK (depth >= 0),
  robots_decision text,
  title text, title_len integer, title_count integer NOT NULL DEFAULT 0 CHECK (title_count >= 0),
  description text, description_len integer, description_count integer NOT NULL DEFAULT 0 CHECK (description_count >= 0),
  h1_count integer NOT NULL DEFAULT 0 CHECK (h1_count >= 0), first_h1 text,
  h2_count integer NOT NULL DEFAULT 0, h3_count integer NOT NULL DEFAULT 0,
  h4_count integer NOT NULL DEFAULT 0, h5_count integer NOT NULL DEFAULT 0, h6_count integer NOT NULL DEFAULT 0,
  html_lang text,
  canonical_count integer NOT NULL DEFAULT 0, canonical_raw text, canonical_resolved text,
  canonical_class text CHECK (canonical_class IS NULL OR canonical_class IN
    ('missing','self','same_origin_other','cross_origin','invalid','unsafe','multiple')),
  meta_robots text, effective_index boolean, effective_follow boolean,
  word_count integer NOT NULL DEFAULT 0 CHECK (word_count >= 0),
  content_hash text, html_bytes_metric integer,
  internal_link_count integer NOT NULL DEFAULT 0, external_link_count integer NOT NULL DEFAULT 0,
  image_count integer NOT NULL DEFAULT 0, images_missing_alt integer NOT NULL DEFAULT 0,
  structured_data_blocks integer NOT NULL DEFAULT 0,
  extraction_status text NOT NULL DEFAULT 'extracted' CHECK (extraction_status IN ('extracted','decode_failed','parse_failed')),
  extractor_version text NOT NULL,
  extraction_error_code text,
  extracted_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seo_crawl_page_snapshots_uniq UNIQUE (job_id, requested_url)
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_snap_website ON public.seo_crawl_page_snapshots (website_id, extracted_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_snap_job ON public.seo_crawl_page_snapshots (job_id);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_snap_hash ON public.seo_crawl_page_snapshots (job_id, content_hash);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_snap_title ON public.seo_crawl_page_snapshots (job_id, title);

DROP TRIGGER IF EXISTS trg_seo_crawl_snap_updated_at ON public.seo_crawl_page_snapshots;
CREATE TRIGGER trg_seo_crawl_snap_updated_at BEFORE UPDATE ON public.seo_crawl_page_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. seo_crawl_issues — deterministic findings (page or site scope).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_crawl_issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  page_snapshot_id uuid REFERENCES public.seo_crawl_page_snapshots(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  issue_code text NOT NULL CHECK (issue_code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  category text NOT NULL,
  severity text NOT NULL CHECK (severity IN ('critical','error','warning','info')),
  scope text NOT NULL CHECK (scope IN ('page','site')),
  rule_version text NOT NULL,
  fingerprint text NOT NULL,
  summary text,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(evidence) = 'object' AND octet_length(evidence::text) <= 8192),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- a page-scoped issue must reference a snapshot; a site-scoped issue must not.
  CONSTRAINT seo_crawl_issues_scope_chk CHECK (
    (scope = 'page' AND page_snapshot_id IS NOT NULL) OR
    (scope = 'site' AND page_snapshot_id IS NULL)),
  CONSTRAINT seo_crawl_issues_uniq UNIQUE (job_id, issue_code, fingerprint)
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_issues_job_sev ON public.seo_crawl_issues (job_id, severity);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_issues_page ON public.seo_crawl_issues (page_snapshot_id);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_issues_code ON public.seo_crawl_issues (job_id, issue_code);

-- ---------------------------------------------------------------------------
-- 3. RLS — customer read (own workspace), no customer writes.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_crawl_page_snapshots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_crawl_page_snapshots_select ON public.seo_crawl_page_snapshots;
CREATE POLICY seo_crawl_page_snapshots_select ON public.seo_crawl_page_snapshots
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());

ALTER TABLE public.seo_crawl_issues ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_crawl_issues_select ON public.seo_crawl_issues;
CREATE POLICY seo_crawl_issues_select ON public.seo_crawl_issues
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());

-- ---------------------------------------------------------------------------
-- 4. seo_crawl_worker_record_snapshots — worker-only bulk upsert.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_record_snapshots(
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_snapshots jsonb DEFAULT '[]'::jsonb
)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE; v_ws uuid; v_site uuid; v_count int := 0;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id=p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('claimed','running') THEN RAISE EXCEPTION 'record not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  v_ws := v_job.workspace_id; v_site := v_job.website_id;

  INSERT INTO public.seo_crawl_page_snapshots
    (job_id, workspace_id, website_id, requested_url, final_url, http_status, redirect_count, content_type,
     declared_charset, decode_status, response_bytes, discovery_source, depth, robots_decision,
     title, title_len, title_count, description, description_len, description_count, h1_count, first_h1,
     h2_count, h3_count, h4_count, h5_count, h6_count, html_lang, canonical_count, canonical_raw, canonical_resolved,
     canonical_class, meta_robots, effective_index, effective_follow, word_count, content_hash, html_bytes_metric,
     internal_link_count, external_link_count, image_count, images_missing_alt, structured_data_blocks,
     extraction_status, extractor_version, extraction_error_code)
  SELECT p_job_id, v_ws, v_site, x."requestedUrl", x."finalUrl", x."httpStatus", x."redirectCount", left(x."contentType",120),
     left(x."declaredCharset",40), x."decodeStatus", x."responseBytes", left(x."discoverySource",20), coalesce(x."depth",0), left(x."robotsDecision",20),
     left(x."title",2048), x."titleLen", coalesce(x."titleCount",0), left(x."description",2048), x."descriptionLen", coalesce(x."descriptionCount",0),
     coalesce(x."h1Count",0), left(x."firstH1",2048), coalesce(x."h2Count",0), coalesce(x."h3Count",0), coalesce(x."h4Count",0),
     coalesce(x."h5Count",0), coalesce(x."h6Count",0), left(x."htmlLang",32), coalesce(x."canonicalCount",0), left(x."canonicalRaw",2048), left(x."canonicalResolved",2048),
     x."canonicalClass", left(x."metaRobots",256), x."effectiveIndex", x."effectiveFollow", coalesce(x."wordCount",0), left(x."contentHash",64), x."htmlBytesMetric",
     coalesce(x."internalLinkCount",0), coalesce(x."externalLinkCount",0), coalesce(x."imageCount",0), coalesce(x."imagesMissingAlt",0), coalesce(x."structuredDataBlocks",0),
     coalesce(x."extractionStatus",'extracted'), coalesce(x."extractorVersion",'unknown'), left(x."extractionErrorCode",80)
  FROM jsonb_to_recordset(coalesce(p_snapshots,'[]'::jsonb)) AS x(
    "requestedUrl" text,"finalUrl" text,"httpStatus" int,"redirectCount" int,"contentType" text,"declaredCharset" text,"decodeStatus" text,
    "responseBytes" int,"discoverySource" text,"depth" int,"robotsDecision" text,"title" text,"titleLen" int,"titleCount" int,
    "description" text,"descriptionLen" int,"descriptionCount" int,"h1Count" int,"firstH1" text,"h2Count" int,"h3Count" int,"h4Count" int,"h5Count" int,"h6Count" int,
    "htmlLang" text,"canonicalCount" int,"canonicalRaw" text,"canonicalResolved" text,"canonicalClass" text,"metaRobots" text,"effectiveIndex" boolean,"effectiveFollow" boolean,
    "wordCount" int,"contentHash" text,"htmlBytesMetric" int,"internalLinkCount" int,"externalLinkCount" int,"imageCount" int,"imagesMissingAlt" int,"structuredDataBlocks" int,
    "extractionStatus" text,"extractorVersion" text,"extractionErrorCode" text)
  WHERE x."requestedUrl" IS NOT NULL
  ON CONFLICT (job_id, requested_url) DO UPDATE SET
    final_url=EXCLUDED.final_url, http_status=EXCLUDED.http_status, redirect_count=EXCLUDED.redirect_count,
    decode_status=EXCLUDED.decode_status, title=EXCLUDED.title, title_len=EXCLUDED.title_len, title_count=EXCLUDED.title_count,
    description=EXCLUDED.description, description_len=EXCLUDED.description_len, description_count=EXCLUDED.description_count,
    h1_count=EXCLUDED.h1_count, first_h1=EXCLUDED.first_h1, html_lang=EXCLUDED.html_lang,
    canonical_count=EXCLUDED.canonical_count, canonical_class=EXCLUDED.canonical_class, canonical_resolved=EXCLUDED.canonical_resolved,
    meta_robots=EXCLUDED.meta_robots, effective_index=EXCLUDED.effective_index, effective_follow=EXCLUDED.effective_follow,
    word_count=EXCLUDED.word_count, content_hash=EXCLUDED.content_hash, internal_link_count=EXCLUDED.internal_link_count,
    external_link_count=EXCLUDED.external_link_count, image_count=EXCLUDED.image_count, images_missing_alt=EXCLUDED.images_missing_alt,
    structured_data_blocks=EXCLUDED.structured_data_blocks, extraction_status=EXCLUDED.extraction_status,
    extractor_version=EXCLUDED.extractor_version, extraction_error_code=EXCLUDED.extraction_error_code, updated_at=now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;

-- ---------------------------------------------------------------------------
-- 5. seo_crawl_worker_record_issues — worker-only idempotent upsert.
--    Page-scoped issues must reference a snapshot belonging to THIS job. The
--    issue_code CHECK + evidence-size CHECK on the table are enforced too.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_record_issues(
  p_job_id uuid, p_worker_id text, p_lease_token uuid,
  p_issues jsonb DEFAULT '[]'::jsonb, p_page_snapshot_id uuid DEFAULT NULL
)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE; v_ws uuid; v_site uuid; v_count int := 0;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id=p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('claimed','running') THEN RAISE EXCEPTION 'record not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  v_ws := v_job.workspace_id; v_site := v_job.website_id;
  -- if a page snapshot is supplied it must belong to this job.
  IF p_page_snapshot_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.seo_crawl_page_snapshots WHERE id=p_page_snapshot_id AND job_id=p_job_id) THEN
    RAISE EXCEPTION 'page snapshot % does not belong to job %', p_page_snapshot_id, p_job_id;
  END IF;

  INSERT INTO public.seo_crawl_issues
    (job_id, page_snapshot_id, workspace_id, website_id, issue_code, category, severity, scope, rule_version, fingerprint, summary, evidence)
  SELECT p_job_id,
     CASE WHEN coalesce(i."scope",'page')='page' THEN p_page_snapshot_id ELSE NULL END,
     v_ws, v_site, i."code", left(i."category",40), i."severity", coalesce(i."scope",'page'),
     left(i."ruleVersion",20), left(i."fingerprint",128), left(i."summary",300), coalesce(i."evidence",'{}'::jsonb)
  FROM jsonb_to_recordset(coalesce(p_issues,'[]'::jsonb)) AS i(
    "code" text,"category" text,"severity" text,"scope" text,"ruleVersion" text,"fingerprint" text,"summary" text,"evidence" jsonb)
  WHERE i."code" IS NOT NULL
  ON CONFLICT (job_id, issue_code, fingerprint) DO UPDATE SET
    severity=EXCLUDED.severity, category=EXCLUDED.category, rule_version=EXCLUDED.rule_version,
    summary=EXCLUDED.summary, evidence=EXCLUDED.evidence;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;

-- ---------------------------------------------------------------------------
-- 6. seo_crawl_worker_update_extraction_progress — bounded stats snapshot.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_update_extraction_progress(
  p_job_id uuid, p_worker_id text, p_lease_token uuid, p_stats jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_job public.seo_crawl_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id=p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;
  IF v_job.status NOT IN ('claimed','running') THEN RAISE EXCEPTION 'progress not allowed from %', v_job.status; END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);
  IF octet_length(coalesce(p_stats,'{}'::jsonb)::text) > 4096 THEN RAISE EXCEPTION 'extraction stats too large'; END IF;
  UPDATE public.seo_crawl_jobs SET extraction_stats = p_stats WHERE id=p_job_id;  -- never touches status/ownership
END; $$;

-- ---------------------------------------------------------------------------
-- 7. Grants — service_role ONLY.
-- ---------------------------------------------------------------------------
DO $g$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.seo_crawl_worker_record_snapshots(uuid,text,uuid,jsonb)',
    'public.seo_crawl_worker_record_issues(uuid,text,uuid,jsonb,uuid)',
    'public.seo_crawl_worker_update_extraction_progress(uuid,text,uuid,jsonb)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $g$;

-- =============================================================================
-- End Phase 16F extraction + issues. Deferred to Phase 1E: mapping these
-- crawler-domain facts/findings into seo_page_inventory / seo_audit_issues /
-- seo_recommendations (locked-scope regression required). No crawling runs from
-- this migration; customer RLS + locked modules unchanged; production untouched.
-- =============================================================================
