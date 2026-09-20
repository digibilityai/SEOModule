-- =============================================================================
-- SEO Backend, Digi Brain Module Contract v1, Stage 2B, Migration 2 of 2:
--   delegated, service-role-only READ RPCs for the machine boundary
-- =============================================================================
-- Additive only. Four narrow read functions that a server-side machine caller
-- (the seo-module-api Edge Function, running with the SEO service role) may
-- execute. Nothing here is reachable by anon or authenticated, and nothing here
-- writes. Does NOT edit, replace or weaken any existing table, RLS policy,
-- customer RPC or locked migration.
--
-- SECURITY INVOKER, NOT SECURITY DEFINER, ON PURPOSE.
-- These functions are granted to service_role alone, and service_role already
-- bypasses RLS. SECURITY DEFINER would therefore add no capability the caller
-- lacks while permanently widening the blast radius if a future grant were ever
-- added by mistake. The repository's SECURITY DEFINER functions exist to let a
-- LESS privileged role (authenticated) perform a guarded action; that rationale
-- does not apply here, so the weaker option is the correct one. search_path is
-- still pinned on every function.
--
-- NO CALLER-SUPPLIED TARGET.
-- Not one of these functions accepts a workspace_id or a website_id. Each takes
-- only the Digi Brain Business identifier plus the canonical normalized host,
-- and resolves the target itself through the human-authorized link table. A
-- machine caller therefore cannot name a website it was not linked to, and no
-- sibling-website or "most recent workspace" substitution is expressible.
--
-- AUTHENTICITY GATES (Contract v1 principle 6).
-- Findings are restricted to source = 'crawler' rows from the latest COMPLETED
-- audit run. Recommendations are restricted to is_current rows carrying a
-- non-null generation_method. Manual, seeded, imported and legacy rows are
-- excluded in SQL, so a machine response can never carry them as genuine.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Shared resolution. Returns exactly one row, always, so the caller can
--    distinguish "resolved" from each specific reason it did not resolve.
--    `resolution` is diagnostic detail for the SEO side; the Contract v1
--    boundary collapses every non-'resolved' value to target_not_linked.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_brain_resolve_target(
  p_business_id text,
  p_normalized_host text
)
RETURNS TABLE (
  resolution      text,
  workspace_id    uuid,
  website_id      uuid,
  normalized_host text,
  website_url     text,
  linked_at       timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_business text := btrim(coalesce(p_business_id, ''));
  v_host     text := lower(btrim(coalesce(p_normalized_host, '')));
  v_link     record;
  v_site     record;
BEGIN
  resolution      := 'not_linked';
  workspace_id    := NULL;
  website_id      := NULL;
  normalized_host := NULLIF(v_host, '');
  website_url     := NULL;
  linked_at       := NULL;

  IF v_business = '' OR v_host = '' THEN
    resolution := 'invalid_target';
    RETURN NEXT;
    RETURN;
  END IF;

  -- The host is compared verbatim against the stored canonical value. It is
  -- never re-derived from the caller's string and never matched loosely, so a
  -- caller that sends a non-canonical host simply does not resolve.
  SELECT l.*
    INTO v_link
  FROM public.seo_brain_website_links l
  WHERE l.business_id = v_business
    AND l.normalized_host = v_host
  ORDER BY (l.link_status = 'active') DESC, l.linked_at DESC
  LIMIT 1;

  IF v_link IS NULL THEN
    resolution := 'not_linked';
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_link.link_status <> 'active' THEN
    resolution := 'revoked';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT w.id, w.workspace_id, w.website_url, w.is_active, w.archived_at
    INTO v_site
  FROM public.seo_websites w
  WHERE w.id = v_link.website_id;

  IF v_site IS NULL THEN
    resolution := 'website_missing';
    RETURN NEXT;
    RETURN;
  END IF;

  -- A link is only valid while the website still identifies the host it was
  -- authorized for. If the website's URL was edited to a different host, the
  -- old authorization must stop resolving rather than silently follow the
  -- website to its new identity.
  IF public.seo_brain_normalize_host(v_site.website_url) IS DISTINCT FROM v_link.normalized_host THEN
    resolution := 'host_changed';
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT v_site.is_active OR v_site.archived_at IS NOT NULL THEN
    resolution := 'website_inactive';
    RETURN NEXT;
    RETURN;
  END IF;

  resolution      := 'resolved';
  workspace_id    := v_site.workspace_id;
  website_id      := v_site.id;
  normalized_host := v_link.normalized_host;
  website_url     := v_site.website_url;
  linked_at       := v_link.linked_at;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. The three capability reads return ONE jsonb payload each, not a set.
--
--    A set-returning shape cannot distinguish "resolved, and there are
--    legitimately zero findings" from "did not resolve": both come back as zero
--    rows. Collapsing that ambiguity in the caller would mean guessing, and
--    guessing here is exactly the substitution risk this boundary exists to
--    prevent. One payload carrying an explicit `resolution` removes it.
--
--    Keys are camelCase because the payload is consumed verbatim by the
--    seo-module-api Edge Function, so there is no second translation layer to
--    get wrong. `resolution` is SEO-side diagnostic detail: the Contract v1
--    boundary collapses every non-'resolved' value onto target_not_linked and
--    never leaks the specific reason to the caller.
--
--    Each function re-resolves the target itself rather than accepting one.
--    Resolution is cheap (two indexed lookups) and making it non-optional is
--    what guarantees no call can ever read a website it was not linked to.
-- ---------------------------------------------------------------------------

-- 2a. Ownership verification state. Genuine: the row is written only by the
--     P1a DNS-TXT verification path.
CREATE OR REPLACE FUNCTION public.seo_brain_ownership_status(
  p_business_id text,
  p_normalized_host text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_target record;
  v_row    record;
BEGIN
  SELECT * INTO v_target
  FROM public.seo_brain_resolve_target(p_business_id, p_normalized_host);

  IF v_target.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_target.resolution);
  END IF;

  SELECT v.verification_host, v.method, v.ownership_source, v.status,
         v.verified_at, v.last_checked_at, v.failure_reason
    INTO v_row
  FROM public.seo_ownership_verifications v
  WHERE v.website_id = v_target.website_id
    AND v.method = 'dns_txt';

  RETURN jsonb_build_object(
    'resolution',       'resolved',
    'websiteId',        v_target.website_id,
    'normalizedHost',   v_target.normalized_host,
    'verificationHost', v_row.verification_host,
    'method',           v_row.method,
    'ownershipSource',  v_row.ownership_source,
    -- No verification record at all is a real, reportable state, not an error.
    'status',           coalesce(v_row.status, 'not_started'),
    'verifiedAt',       v_row.verified_at,
    'lastCheckedAt',    v_row.last_checked_at,
    'failureReason',    v_row.failure_reason
  );
END;
$$;

-- 2b. Genuine crawler findings: latest COMPLETED audit run, source='crawler'
--     only. Manual, seeded and legacy rows are excluded here in SQL, so they
--     cannot reach a machine caller even if a later caller forgets to check.
CREATE OR REPLACE FUNCTION public.seo_brain_crawl_findings(
  p_business_id text,
  p_normalized_host text,
  p_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_target   record;
  v_run      record;
  v_limit    integer := LEAST(GREATEST(coalesce(p_limit, 200), 1), 500);
  v_findings jsonb;
BEGIN
  SELECT * INTO v_target
  FROM public.seo_brain_resolve_target(p_business_id, p_normalized_host);

  IF v_target.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_target.resolution);
  END IF;

  SELECT r.id, r.completed_at
    INTO v_run
  FROM public.seo_audit_runs r
  WHERE r.website_id = v_target.website_id
    AND r.status = 'completed'
  ORDER BY r.completed_at DESC NULLS LAST, r.created_at DESC
  LIMIT 1;

  -- A linked website that has not completed an audit yet is a real state, not
  -- a failure, and never a reason to fall back to another run or website.
  IF v_run IS NULL THEN
    RETURN jsonb_build_object(
      'resolution', 'no_completed_audit',
      'websiteId',  v_target.website_id
    );
  END IF;

  -- jsonb_build_object keeps the ordering keys out of the payload, and the
  -- explicit ORDER BY inside jsonb_agg makes the array order guaranteed rather
  -- than incidental to how the subquery happens to be scanned.
  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               -- The crawler fingerprint is the stable cross-run identity and
               -- the evidence anchor back to the job that produced the finding.
               -- The issue id is only a fallback for a legacy row, which the
               -- source filter below already excludes in practice.
               'findingKey',             coalesce(f.source_issue_fingerprint, f.id::text),
               'title',                  f.title,
               'observation',            f.simple_explanation,
               'recommendedAction',      f.suggested_next_action,
               'severity',               f.severity,
               'category',               f.category,
               'affectedPageUrl',        f.affected_page_url,
               'issueScope',             f.issue_scope,
               'source',                 f.source,
               'crawlJobId',             f.crawl_job_id,
               'sourceIssueFingerprint', f.source_issue_fingerprint,
               'sourceRuleVersion',      f.source_rule_version
             )
             ORDER BY f.severity_rank, f.created_at
           ),
           '[]'::jsonb
         )
    INTO v_findings
  FROM (
    SELECT
      i.id, i.title, i.simple_explanation, i.suggested_next_action, i.severity,
      i.category, i.affected_page_url, i.issue_scope, i.source, i.crawl_job_id,
      i.source_issue_fingerprint, i.source_rule_version, i.created_at,
      CASE i.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1
                      WHEN 'medium' THEN 2 ELSE 3 END AS severity_rank
    FROM public.seo_audit_issues i
    WHERE i.website_id = v_target.website_id
      AND i.audit_run_id = v_run.id
      AND i.source = 'crawler'                        -- authenticity gate
      AND i.status IN ('open', 'in_review')
    ORDER BY severity_rank, i.created_at
    LIMIT v_limit
  ) f;

  RETURN jsonb_build_object(
    'resolution',       'resolved',
    'websiteId',        v_target.website_id,
    'normalizedHost',   v_target.normalized_host,
    'auditRunId',       v_run.id,
    'auditCompletedAt', v_run.completed_at,
    'findings',         v_findings
  );
END;
$$;

-- 2c. Current rule-generated recommendations. is_current only, and
--     generation_method must be present: that column is what distinguishes a
--     generator-produced row from a legacy, manual or seeded one.
CREATE OR REPLACE FUNCTION public.seo_brain_current_recommendations(
  p_business_id text,
  p_normalized_host text,
  p_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_target record;
  v_limit  integer := LEAST(GREATEST(coalesce(p_limit, 200), 1), 500);
  v_recs   jsonb;
BEGIN
  SELECT * INTO v_target
  FROM public.seo_brain_resolve_target(p_business_id, p_normalized_host);

  IF v_target.resolution <> 'resolved' THEN
    RETURN jsonb_build_object('resolution', v_target.resolution);
  END IF;

  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               'recommendationId',       r.id,
               'findingKey',             coalesce(r.source_issue_fingerprint,
                                                  'onpage::' || r.area),
               'area',                   r.area,
               'title',                  r.title,
               'currentValue',           r.current_value,
               'suggestedChange',        r.suggested_change,
               'whyItHelps',             r.why_it_helps,
               'actionType',             r.action_type,
               'impact',                 r.impact,
               'effort',                 r.effort,
               'risk',                   r.risk,
               'status',                 r.status,
               'generationMethod',       r.generation_method,
               'sourceIssueFingerprint', r.source_issue_fingerprint,
               'auditRunId',             r.audit_run_id,
               'updatedAt',              r.updated_at
             )
             ORDER BY r.impact_rank, r.effort_rank, r.created_at
           ),
           '[]'::jsonb
         )
    INTO v_recs
  FROM (
    SELECT
      rec.*,
      CASE rec.impact WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END AS impact_rank,
      CASE rec.effort WHEN 'low'  THEN 0 WHEN 'medium' THEN 1 ELSE 2 END AS effort_rank
    FROM public.seo_recommendations rec
    WHERE rec.website_id = v_target.website_id
      AND rec.is_current
      AND rec.generation_method IS NOT NULL            -- authenticity gate
    ORDER BY impact_rank, effort_rank, rec.created_at
    LIMIT v_limit
  ) r;

  RETURN jsonb_build_object(
    'resolution',      'resolved',
    'websiteId',       v_target.website_id,
    'normalizedHost',  v_target.normalized_host,
    'recommendations', v_recs
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Grants. service_role only, on all four. anon, authenticated and PUBLIC are
--    revoked explicitly and up front, so no corrective follow-up migration is
--    ever needed.
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
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END $$;
