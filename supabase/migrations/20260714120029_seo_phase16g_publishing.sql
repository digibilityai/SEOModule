-- =============================================================================
-- SEO Backend — Phase 16G / Crawler Phase 1E — Controlled Page Inventory & Audit
-- Publishing Integration. ADDITIVE ONLY. Publication contract VERSION 1.
-- =============================================================================
-- Connects the verified crawler domain (Phase 16C–16F) to the existing customer
-- Page Inventory (Stage 4) and Audit (Stage 2) contracts via:
--   1. An explicit, guarded crawl-job -> audit-run association (additive column
--      + orchestration RPC). NEVER a "latest run" guess.
--   2. A single service-role-only transactional publishing RPC that reads the
--      persisted crawler-domain snapshots/issues SERVER-SIDE (never worker JSON),
--      upserts Page Inventory + Audit Issues, records publication evidence, and
--      updates the associated audit run honestly.
-- Preserves seo_crawl_request and seo_run_audit UNCHANGED. Additive nullable
-- provenance only; no existing column/constraint/status removed or renamed.
-- No seo_recommendations write. No Page Performance / Stage 6 write. No scoring.
-- Target: Digi_SEO_Test only. Production untouched.
-- =============================================================================

-- ===========================================================================
-- 1. Association — additive nullable audit_run_id on crawl jobs.
--    Populated ONLY by the guarded orchestration RPC; NULL for generic crawls
--    (backward compatible: a job with no association publishes nothing).
-- ===========================================================================
ALTER TABLE public.seo_crawl_jobs
  ADD COLUMN IF NOT EXISTS audit_run_id uuid
    REFERENCES public.seo_audit_runs(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_seo_crawl_jobs_audit_run
  ON public.seo_crawl_jobs (audit_run_id) WHERE audit_run_id IS NOT NULL;

-- ===========================================================================
-- 2. Page Inventory — additive nullable crawler-owned facts + provenance.
--    Existing rows get NULL (backward compatible). User-owned fields
--    (page_type, priority, is_tracked, content_status, is_active, first_seen_at)
--    are NEVER written by the publisher.
-- ===========================================================================
ALTER TABLE public.seo_page_inventory
  ADD COLUMN IF NOT EXISTS http_status integer,
  ADD COLUMN IF NOT EXISTS word_count integer CHECK (word_count IS NULL OR word_count >= 0),
  ADD COLUMN IF NOT EXISTS content_type text,
  ADD COLUMN IF NOT EXISTS first_h1 text,
  ADD COLUMN IF NOT EXISTS source text,                       -- NULL/legacy, 'crawler', 'manual', 'seed'
  ADD COLUMN IF NOT EXISTS source_crawl_job_id uuid
    REFERENCES public.seo_crawl_jobs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS crawler_extracted_at timestamptz,  -- stale-job ordering key
  ADD COLUMN IF NOT EXISTS crawler_extractor_version text;
CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_source_job
  ON public.seo_page_inventory (source_crawl_job_id) WHERE source_crawl_job_id IS NOT NULL;

-- ===========================================================================
-- 3. Audit Issues — additive nullable crawler provenance + site-scope support.
--    affected_page_url stays NOT NULL (unchanged); site issues use the run's
--    real website_url + issue_scope='site' (no fabricated page). source_* keep
--    the original crawler severity/category/rule version + fingerprint.
-- ===========================================================================
ALTER TABLE public.seo_audit_issues
  ADD COLUMN IF NOT EXISTS source text,                       -- NULL/legacy manual, or 'crawler'
  ADD COLUMN IF NOT EXISTS crawl_job_id uuid
    REFERENCES public.seo_crawl_jobs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_issue_fingerprint text,     -- '<CODE>::<crawler fingerprint>'
  ADD COLUMN IF NOT EXISTS source_rule_version text,
  ADD COLUMN IF NOT EXISTS issue_scope text CHECK (issue_scope IS NULL OR issue_scope IN ('page','site')),
  ADD COLUMN IF NOT EXISTS source_category text,
  ADD COLUMN IF NOT EXISTS source_severity text;
-- Idempotency: one crawler issue per (run, code+fingerprint). Manual issues have
-- NULL fingerprint and are excluded from this uniqueness (never touched).
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_audit_issues_crawler_fp
  ON public.seo_audit_issues (audit_run_id, source_issue_fingerprint)
  WHERE source_issue_fingerprint IS NOT NULL;

-- ===========================================================================
-- 4. Deterministic issue-code -> Audit mapping (VERSION 1). Complete for all 26
--    Phase 1D codes. Static, non-AI, customer-safe text satisfying the Audit
--    NOT NULL contract. audit_category is chosen so that only genuinely
--    high-risk crawler findings (canonical/indexability/redirects) map to a
--    high-risk Audit category; metadata/heading/content/image findings map to
--    non-high-risk buckets. Original crawler category is preserved in provenance.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_crawl_issue_audit_map (
  issue_code text PRIMARY KEY CHECK (issue_code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  audit_category text NOT NULL CHECK (audit_category IN (
    'crawl','indexability','speed','mobile','schema','duplicate_content',
    'broken_links','sitemap','robots_txt','canonical','redirects')),
  audit_title text NOT NULL,
  simple_explanation text NOT NULL,
  why_it_matters text NOT NULL,
  technical_explanation text NOT NULL,
  suggested_next_action text NOT NULL,
  publishable boolean NOT NULL DEFAULT true,
  map_version integer NOT NULL DEFAULT 1
);
ALTER TABLE public.seo_crawl_issue_audit_map ENABLE ROW LEVEL SECURITY;
-- Reference data: no customer policy (locked to definer/service role). The
-- publishing RPC (SECURITY DEFINER) reads it regardless of RLS.

INSERT INTO public.seo_crawl_issue_audit_map
  (issue_code, audit_category, audit_title, simple_explanation, why_it_matters, technical_explanation, suggested_next_action)
VALUES
 ('TITLE_MISSING','crawl','Missing page title','This page has no title tag.','Search engines and users rely on the title to understand the page.','No <title> element was found in the document head.','Add a descriptive <title> element to this page.'),
 ('TITLE_EMPTY','crawl','Empty page title','The page title tag is present but empty.','An empty title gives search engines nothing to display.','A <title> element exists but contains no text.','Provide meaningful text inside the <title> element.'),
 ('TITLE_MULTIPLE','crawl','Multiple page titles','The page defines more than one title tag.','Multiple titles are ambiguous for search engines.','More than one <title> element was detected.','Keep a single <title> element per page.'),
 ('TITLE_TOO_SHORT','crawl','Short page title','The page title is shorter than the guidance length.','Very short titles may underuse the available space.','Title length is below the configured guidance minimum.','Consider expanding the title toward the guidance range.'),
 ('TITLE_TOO_LONG','crawl','Long page title','The page title is longer than the guidance length.','Long titles may be truncated in search results.','Title length exceeds the configured guidance maximum.','Consider shortening the title toward the guidance range.'),
 ('DESCRIPTION_MISSING','crawl','Missing meta description','This page has no meta description.','A meta description influences the search snippet.','No meta description tag was found.','Add a concise meta description to this page.'),
 ('DESCRIPTION_EMPTY','crawl','Empty meta description','The meta description is present but empty.','An empty description leaves the snippet to be auto-generated.','A meta description tag exists but has no content.','Provide meaningful meta description text.'),
 ('DESCRIPTION_MULTIPLE','crawl','Multiple meta descriptions','The page defines more than one meta description.','Multiple descriptions are ambiguous.','More than one meta description tag was detected.','Keep a single meta description per page.'),
 ('DESCRIPTION_TOO_SHORT','crawl','Short meta description','The meta description is shorter than guidance.','Very short descriptions may underuse the snippet.','Description length is below the guidance minimum.','Consider expanding the description toward the guidance range.'),
 ('DESCRIPTION_TOO_LONG','crawl','Long meta description','The meta description is longer than guidance.','Long descriptions may be truncated in results.','Description length exceeds the guidance maximum.','Consider shortening the description toward the guidance range.'),
 ('H1_MISSING','crawl','Missing H1 heading','This page has no H1 heading.','The H1 signals the primary topic of the page.','No <h1> element was found.','Add a single descriptive <h1> heading.'),
 ('H1_MULTIPLE','crawl','Multiple H1 headings','The page has more than one H1 heading.','Multiple H1s can dilute the primary topic signal.','More than one <h1> element was detected.','Consider using a single primary <h1>.'),
 ('H1_EMPTY','crawl','Empty H1 heading','The first H1 heading is empty.','An empty H1 provides no topical signal.','An <h1> element exists but contains no text.','Provide meaningful text in the primary <h1>.'),
 ('CANONICAL_MISSING','canonical','Missing canonical tag','This page declares no canonical URL.','Canonical tags help consolidate duplicate URLs.','No rel=canonical link was found.','Consider adding a self-referencing canonical URL.'),
 ('CANONICAL_MULTIPLE','canonical','Multiple canonical tags','The page declares more than one canonical URL.','Conflicting canonicals confuse consolidation.','More than one rel=canonical link was detected.','Keep a single canonical URL per page.'),
 ('CANONICAL_INVALID','canonical','Invalid canonical URL','The canonical value is not a valid URL.','An invalid canonical cannot be honored.','The rel=canonical value did not parse as a URL.','Correct the canonical to a valid absolute URL.'),
 ('CANONICAL_UNSAFE','canonical','Unsafe canonical URL','The canonical uses an unsupported scheme.','Unsafe canonicals are ignored by crawlers.','The canonical URL used a non-http(s) or unsafe scheme.','Use a valid http(s) canonical URL.'),
 ('CANONICAL_CROSS_ORIGIN','canonical','Cross-origin canonical','The canonical points to a different host.','Cross-origin canonicals transfer indexing signals off-site.','The canonical host differs from the page host.','Confirm the cross-origin canonical is intended.'),
 ('CANONICAL_NON_SELF','canonical','Non-self canonical','The canonical points to a different URL on this site.','Non-self canonicals can de-index this URL.','The canonical resolves to another same-site URL.','Confirm the canonical target is intended.'),
 ('EFFECTIVE_NOINDEX','indexability','Page set to noindex','This page is effectively set to noindex.','A noindex page will be excluded from search.','Robots directives resolve to noindex for this page.','Confirm this page should be excluded from search.'),
 ('CONFLICTING_ROBOTS','indexability','Conflicting robots directives','The page has conflicting index directives.','Conflicting directives resolve conservatively to noindex.','Both index and noindex directives were present.','Resolve the conflicting robots directives.'),
 ('REDIRECT_CHAIN_LONG','redirects','Long redirect chain','This URL resolves through several redirects.','Long redirect chains waste crawl budget and slow users.','The redirect count exceeded the guidance threshold.','Reduce the number of redirect hops.'),
 ('DECODE_UNSUPPORTED','crawl','Unsupported text encoding','The page used an unsupported character encoding.','Unsupported encodings can corrupt extracted text.','The declared charset could not be decoded reliably.','Serve the page using a supported encoding such as UTF-8.'),
 ('HTML_LANG_MISSING','crawl','Missing HTML lang attribute','The page does not declare a language.','The lang attribute aids accessibility and localization.','No lang attribute was found on the <html> element.','Add a lang attribute to the <html> element.'),
 ('LOW_CONTENT','crawl','Low content volume','This page has little textual content.','Thin pages may provide limited value in search.','Visible word count was below the guidance threshold.','Consider adding more substantive content.'),
 ('IMAGES_MISSING_ALT','crawl','Images missing alt text','One or more images have no alt text.','Alt text aids accessibility and image search.','At least one <img> had an empty or missing alt attribute.','Add descriptive alt text to the affected images.'),
 ('DUPLICATE_TITLE','duplicate_content','Duplicate page titles','Several pages share the same title.','Duplicate titles make pages harder to distinguish.','Two or more indexable pages share a normalized title.','Give each page a distinct title.'),
 ('DUPLICATE_DESCRIPTION','duplicate_content','Duplicate meta descriptions','Several pages share the same meta description.','Duplicate descriptions weaken snippet relevance.','Two or more indexable pages share a normalized description.','Give each page a distinct meta description.'),
 ('DUPLICATE_CONTENT','duplicate_content','Duplicate page content','Several pages share the same content.','Duplicate content competes with itself in search.','Two or more indexable pages share a content hash.','Differentiate or consolidate the duplicate pages.')
ON CONFLICT (issue_code) DO NOTHING;

-- ===========================================================================
-- 5. Publication evidence — one authoritative record per (job, run, version).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_crawl_publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES public.seo_crawl_jobs(id) ON DELETE CASCADE,
  audit_run_id uuid NOT NULL REFERENCES public.seo_audit_runs(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  publication_version integer NOT NULL DEFAULT 1 CHECK (publication_version >= 1),
  source_ruleset_version text,
  status text NOT NULL DEFAULT 'running'
    CHECK (status IN ('running','published','failed')),
  pages_eligible integer NOT NULL DEFAULT 0 CHECK (pages_eligible >= 0),
  pages_published integer NOT NULL DEFAULT 0 CHECK (pages_published >= 0),
  issues_eligible integer NOT NULL DEFAULT 0 CHECK (issues_eligible >= 0),
  issues_published integer NOT NULL DEFAULT 0 CHECK (issues_published >= 0),
  crawl_partial boolean NOT NULL DEFAULT false,
  started_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  error_code text,                                            -- customer-safe
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT seo_crawl_publications_uniq UNIQUE (job_id, audit_run_id, publication_version)
);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_publications_run ON public.seo_crawl_publications (audit_run_id);
CREATE INDEX IF NOT EXISTS idx_seo_crawl_publications_website ON public.seo_crawl_publications (website_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_seo_crawl_publications_updated_at ON public.seo_crawl_publications;
CREATE TRIGGER trg_seo_crawl_publications_updated_at BEFORE UPDATE ON public.seo_crawl_publications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.seo_crawl_publications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_crawl_publications_select ON public.seo_crawl_publications;
CREATE POLICY seo_crawl_publications_select ON public.seo_crawl_publications
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );
-- No customer INSERT/UPDATE/DELETE policy: writes occur only via the
-- service-role publishing RPC (service role bypasses RLS).

-- ===========================================================================
-- 6. Orchestration RPC (customer-callable) — atomically create/validate an
--    audit run + a crawl job and bind them. Preserves seo_crawl_request and
--    seo_run_audit UNCHANGED (seo_crawl_request is reused verbatim). Returns
--    both identifiers directly — callers never query for "the latest".
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_crawl_request_audit(
  p_website_id uuid,
  p_idempotency_key text DEFAULT NULL,
  p_config jsonb DEFAULT NULL
)
RETURNS TABLE (audit_run_id uuid, crawl_job_id uuid, job_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_url text;
  v_freq text;
  v_job_id uuid;
  v_job_status text;
  v_existing_run uuid;
  v_run_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.has_seo_module_access(v_uid) THEN RAISE EXCEPTION 'SEO module access required'; END IF;

  SELECT w.workspace_id, w.website_url, ws.plan_tier INTO v_ws, v_url, v_freq
  FROM public.seo_websites w JOIN public.seo_workspaces ws ON ws.id = w.workspace_id
  WHERE w.id = p_website_id;
  IF v_ws IS NULL THEN RAISE EXCEPTION 'Website % does not exist', p_website_id; END IF;

  -- Requester role matrix (owner/admin/team_member/global_admin) — matches the
  -- crawl-request contract; clients are denied (same as seo_crawl_request).
  IF NOT (public.seo_is_global_admin(v_uid)
       OR public.seo_role_in(v_ws, ARRAY['owner','admin','team_member'], v_uid)) THEN
    RAISE EXCEPTION 'Not permitted to request a crawl for this website';
  END IF;

  -- 1) Create the crawl job via the UNCHANGED generic request RPC (handles
  --    eligibility, idempotency, single-active-job enforcement, event).
  v_job_id := public.seo_crawl_request(p_website_id, p_idempotency_key, p_config);
  SELECT j.status, j.audit_run_id INTO v_job_status, v_existing_run
  FROM public.seo_crawl_jobs j WHERE j.id = v_job_id;

  -- 2) Idempotent replay: the job already has an association -> return it as-is.
  IF v_existing_run IS NOT NULL THEN
    audit_run_id := v_existing_run; crawl_job_id := v_job_id; job_status := v_job_status;
    RETURN NEXT; RETURN;
  END IF;

  -- 3) Never associate a job that already reached a terminal state.
  IF v_job_status IN ('completed','partially_completed','failed','cancelled') THEN
    RAISE EXCEPTION 'Crawl job already finished; cannot associate an audit run';
  END IF;

  -- 4) Create a fresh audit run (mirrors seo_run_audit: one latest per website).
  v_freq := CASE v_freq WHEN 'pro' THEN 'weekly_plus_change_monitoring'
                        WHEN 'standard' THEN 'weekly' ELSE 'monthly' END;
  UPDATE public.seo_audit_runs SET is_latest = false, updated_at = now()
    WHERE website_id = p_website_id AND is_latest;
  INSERT INTO public.seo_audit_runs
    (workspace_id, website_id, website_url, frequency, status, is_latest, started_at, created_by)
  VALUES (v_ws, p_website_id, v_url, v_freq, 'running', true, now(), v_uid)
  RETURNING id INTO v_run_id;

  -- 5) Bind (only while unassociated + pre-terminal).
  UPDATE public.seo_crawl_jobs SET audit_run_id = v_run_id, updated_at = now()
    WHERE id = v_job_id AND public.seo_crawl_jobs.audit_run_id IS NULL;

  audit_run_id := v_run_id; crawl_job_id := v_job_id; job_status := v_job_status;
  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION public.seo_crawl_request_audit(uuid, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_crawl_request_audit(uuid, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_crawl_request_audit(uuid, text, jsonb) TO authenticated;

-- ===========================================================================
-- 7. Worker publishing RPC (service-role ONLY) — one transactional publish.
--    Reads crawler-domain records SERVER-SIDE. Worker supplies NO page/issue
--    payload, NO status, NO counts, NO target row ids. Idempotent + stale-safe.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_crawl_worker_publish_results(
  p_job_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_publication_version integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.seo_crawl_jobs%ROWTYPE;
  v_run public.seo_audit_runs%ROWTYPE;
  v_pub_id uuid;
  v_ruleset text;
  v_crawl_ts timestamptz;
  v_pages_eligible integer := 0;
  v_pages_written integer := 0;
  v_issues_eligible integer := 0;
  v_issues_written integer := 0;
  v_crawl_partial boolean := false;
BEGIN
  IF p_publication_version < 1 THEN RAISE EXCEPTION 'invalid publication version'; END IF;

  SELECT * INTO v_job FROM public.seo_crawl_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'job % not found', p_job_id; END IF;

  -- Actively owned + pre-terminal (publishing happens before final completion).
  IF v_job.status NOT IN ('claimed','running') THEN
    RAISE EXCEPTION 'publish not allowed in status % (cancelled/terminal)', v_job.status;
  END IF;
  PERFORM public._seo_crawl_assert_owner(v_job, p_worker_id, p_lease_token);

  -- No explicit association -> nothing to publish (generic crawl path).
  IF v_job.audit_run_id IS NULL THEN
    RETURN jsonb_build_object('status','skipped_no_association',
      'pagesEligible',0,'pagesPublished',0,'issuesEligible',0,'issuesPublished',0,
      'publicationVersion',p_publication_version);
  END IF;

  SELECT * INTO v_run FROM public.seo_audit_runs WHERE id = v_job.audit_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'associated audit run missing'; END IF;
  IF v_run.workspace_id <> v_job.workspace_id OR v_run.website_id <> v_job.website_id THEN
    RAISE EXCEPTION 'audit run / crawl job workspace or website mismatch';
  END IF;
  -- Publishable while running; 'completed' allowed only for an idempotent replay
  -- of this same job+version (converge). Any other state is refused.
  IF v_run.status NOT IN ('running','completed') THEN
    RAISE EXCEPTION 'associated audit run is not in a publishable state (%)', v_run.status;
  END IF;
  IF v_run.status = 'completed' AND NOT EXISTS (
    SELECT 1 FROM public.seo_crawl_publications
    WHERE job_id = p_job_id AND audit_run_id = v_run.id AND publication_version = p_publication_version
  ) THEN
    RAISE EXCEPTION 'audit run already completed by a different source; refusing to publish';
  END IF;

  -- Refuse silent drops: every crawler issue code must be mapped.
  IF EXISTS (
    SELECT 1 FROM public.seo_crawl_issues ci
    WHERE ci.job_id = p_job_id
      AND NOT EXISTS (SELECT 1 FROM public.seo_crawl_issue_audit_map m WHERE m.issue_code = ci.issue_code)
  ) THEN
    RAISE EXCEPTION 'unmapped crawler issue code present; refusing partial publish';
  END IF;

  SELECT extractor_version INTO v_ruleset FROM public.seo_crawl_page_snapshots
    WHERE job_id = p_job_id LIMIT 1;
  v_crawl_ts := coalesce(v_job.started_at, v_job.claimed_at, v_job.requested_at, now());
  v_crawl_partial := (v_job.status = 'running' AND v_job.pages_crawled < v_job.pages_discovered);

  SELECT count(*) INTO v_pages_eligible FROM public.seo_crawl_page_snapshots
    WHERE job_id = p_job_id AND extraction_status = 'extracted';

  -- Publication evidence (upsert -> running).
  INSERT INTO public.seo_crawl_publications
    (job_id, audit_run_id, workspace_id, website_id, publication_version,
     source_ruleset_version, status, pages_eligible, issues_eligible, crawl_partial, started_at)
  VALUES
    (p_job_id, v_run.id, v_job.workspace_id, v_job.website_id, p_publication_version,
     v_ruleset, 'running', v_pages_eligible, 0, v_crawl_partial, now())
  ON CONFLICT (job_id, audit_run_id, publication_version) DO UPDATE
    SET status = 'running', pages_eligible = EXCLUDED.pages_eligible,
        crawl_partial = EXCLUDED.crawl_partial, started_at = now(),
        error_code = NULL, updated_at = now()
  RETURNING id INTO v_pub_id;

  -- No usable results: publish nothing, mark run failed honestly.
  IF v_pages_eligible = 0 THEN
    UPDATE public.seo_crawl_publications
      SET status = 'failed', error_code = 'no_results', published_at = now(), updated_at = now()
      WHERE id = v_pub_id;
    UPDATE public.seo_audit_runs
      SET status = 'failed', completed_at = now(),
          error_message = 'No crawlable pages produced usable results', updated_at = now()
      WHERE id = v_run.id;
    RETURN jsonb_build_object('status','no_results','publicationId',v_pub_id,'auditRunId',v_run.id,
      'pagesEligible',0,'pagesPublished',0,'issuesEligible',0,'issuesPublished',0,
      'publicationVersion',p_publication_version);
  END IF;

  -- ---- Page Inventory upsert (crawler-owned technical facts + provenance) ----
  -- Identity = (website_id, page_url) among active rows. User-owned fields are
  -- never in the SET list. Stale-job + non-crawler-source protection in WHERE.
  WITH src AS (
    SELECT DISTINCT ON (s.requested_url)
      s.requested_url, s.title, s.description, s.canonical_resolved, s.effective_index,
      s.http_status, s.word_count, s.content_type, s.first_h1, s.extracted_at, s.extractor_version
    FROM public.seo_crawl_page_snapshots s
    WHERE s.job_id = p_job_id AND s.extraction_status = 'extracted'
    ORDER BY s.requested_url, s.extracted_at DESC
  )
  INSERT INTO public.seo_page_inventory
    (workspace_id, website_id, website_url, page_url, page_title, meta_description,
     indexability_status, canonical_url, last_seen_at, http_status, word_count,
     content_type, first_h1, source, source_crawl_job_id, crawler_extracted_at, crawler_extractor_version)
  SELECT
    v_job.workspace_id, v_job.website_id, v_job.website_url, src.requested_url,
    src.title, src.description,
    CASE WHEN src.effective_index THEN 'indexable' ELSE 'noindex' END,
    src.canonical_resolved, src.extracted_at, src.http_status, src.word_count,
    src.content_type, src.first_h1, 'crawler', p_job_id,
    coalesce(src.extracted_at, v_crawl_ts), src.extractor_version
  FROM src
  ON CONFLICT (website_id, page_url) WHERE is_active DO UPDATE SET
    page_title = EXCLUDED.page_title,
    meta_description = EXCLUDED.meta_description,
    indexability_status = EXCLUDED.indexability_status,
    canonical_url = EXCLUDED.canonical_url,
    last_seen_at = EXCLUDED.last_seen_at,
    http_status = EXCLUDED.http_status,
    word_count = EXCLUDED.word_count,
    content_type = EXCLUDED.content_type,
    first_h1 = EXCLUDED.first_h1,
    source = 'crawler',
    source_crawl_job_id = EXCLUDED.source_crawl_job_id,
    crawler_extracted_at = EXCLUDED.crawler_extracted_at,
    crawler_extractor_version = EXCLUDED.crawler_extractor_version,
    updated_at = now()
  WHERE (public.seo_page_inventory.source IS NULL OR public.seo_page_inventory.source = 'crawler')
    AND (public.seo_page_inventory.crawler_extracted_at IS NULL
         OR EXCLUDED.crawler_extracted_at >= public.seo_page_inventory.crawler_extracted_at);
  GET DIAGNOSTICS v_pages_written = ROW_COUNT;

  -- ---- Audit Issue upsert (mapped; page + site scoped; provenance) ----
  SELECT count(*) INTO v_issues_eligible FROM public.seo_crawl_issues WHERE job_id = p_job_id;

  INSERT INTO public.seo_audit_issues
    (workspace_id, website_id, website_url, audit_run_id, category, severity, title,
     simple_explanation, why_it_matters, technical_explanation, affected_page_url,
     impact, effort, risk, confidence_percentage, fix_owner, suggested_next_action, status,
     source, crawl_job_id, source_issue_fingerprint, source_rule_version, issue_scope,
     source_category, source_severity)
  SELECT
    v_job.workspace_id, v_job.website_id, v_job.website_url, v_run.id,
    m.audit_category,
    CASE ci.severity WHEN 'critical' THEN 'critical' WHEN 'error' THEN 'high'
                     WHEN 'warning' THEN 'medium' ELSE 'low' END,
    m.audit_title, m.simple_explanation, m.why_it_matters, m.technical_explanation,
    CASE WHEN ci.scope = 'site' THEN v_job.website_url
         ELSE coalesce(ps.requested_url, v_job.website_url) END,
    CASE ci.severity WHEN 'critical' THEN 'high' WHEN 'error' THEN 'high'
                     WHEN 'warning' THEN 'medium' ELSE 'low' END,       -- impact (deterministic)
    'medium',                                                            -- effort (deterministic)
    CASE WHEN public.seo_is_high_risk_category(m.audit_category) THEN 'high' ELSE 'low' END, -- risk
    90, 'system_suggestion', m.suggested_next_action, 'open',
    'crawler', p_job_id, ci.issue_code || '::' || ci.fingerprint, ci.rule_version, ci.scope,
    ci.category, ci.severity
  FROM public.seo_crawl_issues ci
  JOIN public.seo_crawl_issue_audit_map m ON m.issue_code = ci.issue_code AND m.publishable
  LEFT JOIN public.seo_crawl_page_snapshots ps ON ps.id = ci.page_snapshot_id
  WHERE ci.job_id = p_job_id
  ON CONFLICT (audit_run_id, source_issue_fingerprint) WHERE source_issue_fingerprint IS NOT NULL
  DO UPDATE SET
    category = EXCLUDED.category, severity = EXCLUDED.severity, title = EXCLUDED.title,
    simple_explanation = EXCLUDED.simple_explanation, why_it_matters = EXCLUDED.why_it_matters,
    technical_explanation = EXCLUDED.technical_explanation, affected_page_url = EXCLUDED.affected_page_url,
    impact = EXCLUDED.impact, risk = EXCLUDED.risk, suggested_next_action = EXCLUDED.suggested_next_action,
    source_category = EXCLUDED.source_category, source_severity = EXCLUDED.source_severity,
    source_rule_version = EXCLUDED.source_rule_version, crawl_job_id = EXCLUDED.crawl_job_id,
    issue_scope = EXCLUDED.issue_scope, updated_at = now()
  WHERE public.seo_audit_issues.source = 'crawler';   -- never touch manual issues
  GET DIAGNOSTICS v_issues_written = ROW_COUNT;

  -- ---- Update the associated audit run honestly (no scoring) ----
  UPDATE public.seo_audit_runs SET
    status = 'completed', completed_at = now(), error_message = NULL,
    issue_count = (SELECT count(*) FROM public.seo_audit_issues WHERE audit_run_id = v_run.id),
    updated_at = now()
  WHERE id = v_run.id;

  UPDATE public.seo_crawl_publications SET
    status = 'published', pages_published = v_pages_written,
    issues_eligible = v_issues_eligible, issues_published = v_issues_written,
    published_at = now(), error_code = NULL, updated_at = now()
  WHERE id = v_pub_id;

  RETURN jsonb_build_object('status','published','publicationId',v_pub_id,'auditRunId',v_run.id,
    'pagesEligible',v_pages_eligible,'pagesPublished',v_pages_written,
    'issuesEligible',v_issues_eligible,'issuesPublished',v_issues_written,
    'crawlPartial',v_crawl_partial,'publicationVersion',p_publication_version);
END;
$$;

-- Service-role-only execution for the worker publishing RPC.
DO $$
DECLARE fn text;
BEGIN
  fn := 'public.seo_crawl_worker_publish_results(uuid, text, uuid, integer)';
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
END $$;
