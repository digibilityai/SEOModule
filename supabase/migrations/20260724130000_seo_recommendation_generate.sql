-- =============================================================================
-- SEO Backend — Recommendation Generation Stage 1 — Migration:
--   additive schema + guarded generation RPC
--   public.seo_recommendation_generate(p_website_id uuid)
-- =============================================================================
-- Additive only. Builds on Stage 2 (`seo_audit_issues`, migration
-- 20260711120004; `seo_recommendations`, migration 20260711120005) and the
-- locked Phase 16G provenance columns on seo_audit_issues (migration
-- 20260714120029 — read only, not modified). Introduces ONE guarded
-- SECURITY DEFINER RPC that (re)generates canonical, persisted
-- seo_recommendations rows from real crawler-detected audit issues plus a
-- fixed on-page template set, following the exact pattern proven twice by
-- seo_report_generate and seo_competitor_generate.
--
-- Full design rationale: SEO_RECOMMENDATION_GENERATION_ARCHITECTURE.md
-- (design-only doc, not committed to this migration's scope).
--
-- SCOPE:
--   * Server-derived authorization (authenticated; workspace resolved from
--     the website; owner/admin/team_member or global admin; client/anon/
--     nonmember/cross-tenant denied with a single non-leaking error) —
--     mirrors the existing seo_recommendations_write / seo_audit_issues_write
--     RLS policies exactly; no new authorization model introduced.
--   * NO client-supplied content: the RPC accepts ONLY p_website_id.
--   * Deterministic, rule-based reproduction of the existing mock heuristic
--     (src/mocks/recommendationMockData.ts CATEGORY_TO_AREA,
--     ACTION_TYPE_BY_FIX_OWNER, ON_PAGE_TEMPLATES) — NO AI/LLM inference, NO
--     new categories, NO external integrations.
--   * Candidate issues limited to status IN ('open','in_review') from the
--     latest COMPLETED audit run — an issue a human already resolved does
--     not spawn a fresh recommendation.
--   * Issue-derived identity = source_issue_fingerprint (already present on
--     seo_audit_issues via the locked Phase 16G migration; read-only here).
--     Issues without a fingerprint (no current writer produces this, but the
--     column is nullable) are skipped non-destructively — there is no stable
--     cross-run identity to dedupe them against.
--   * On-page identity = area (one current on-page recommendation per area).
--   * Three-way replace-to-match using the existing is_current/superseded_by
--     versioning (first real consumer of that scheme): insert if new;
--     no write if unchanged; supersede if changed AND status is still
--     suggested/needs_review; leave untouched if changed AND a human has
--     already acted (status is any other value) — a decision in progress is
--     never silently overwritten. Issue-derived recommendations no longer in
--     the desired set are retired (is_current=false, superseded_by=NULL)
--     under the same untouched-status protection; on-page recommendations
--     are never auto-retired (no external issue that can "resolve").
--   * Transaction-scoped advisory lock keyed by (website, generation op) so
--     concurrent/duplicate Generate calls serialize; the two partial unique
--     indexes below are the final guarantee.
--   * Returns the canonical current recommendation set for the website after
--     persistence (SETOF, not a transient/summary payload).
--   * anon + PUBLIC EXECUTE revoked up-front (folded in — no corrective
--     follow-up migration needed).
--
-- Does NOT touch any locked module, table, RPC, or contract; does NOT modify
-- seo_audit_issues, seo_approval_items, seo_approval_transition, or any
-- crawler table; does NOT weaken RLS, mock mode, or read paths.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Additive columns on seo_recommendations.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_recommendations
  ADD COLUMN IF NOT EXISTS source_issue_fingerprint text,   -- copied from the linked issue at generation time; NULL for on-page recs
  ADD COLUMN IF NOT EXISTS generation_method text;           -- e.g. 'rule_based_v1'; mirrors Competitor Stage 2A's provenance discipline

-- ---------------------------------------------------------------------------
-- 2. Dedup identity — partial unique indexes scoped to the live (is_current)
--    rows only, so a superseded/retired row never conflicts with its own
--    replacement (same pattern as Competitor Stage 2A's
--    UNIQUE(website_id, normalized_competitor_url), extended with the
--    is_current versioning dimension this table already has).
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_recommendations_issue_fingerprint
  ON public.seo_recommendations (website_id, source_issue_fingerprint)
  WHERE is_current AND source_issue_fingerprint IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_recommendations_onpage_area
  ON public.seo_recommendations (website_id, area)
  WHERE is_current AND issue_id IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Guarded generation RPC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_recommendation_generate(
  p_website_id uuid
) RETURNS SETOF public.seo_recommendations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid              uuid := auth.uid();
  v_ws               uuid;
  v_url              text;
  v_business_name    text;
  v_industry         text;
  v_target_location  text;
  v_run_id           uuid;
  d                  record;
  v_existing         record;
  v_new_id           uuid;
  v_changed          boolean;
BEGIN
  -- 1. Authentication.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authorized to generate recommendations for this website.';
  END IF;

  -- 2. Resolve website -> workspace/url/business-context fields server-side
  --    (never trust a caller workspace). A missing website yields the SAME
  --    generic error as a role failure so existence never leaks.
  SELECT w.workspace_id, w.website_url, w.business_name, w.industry, w.target_location
    INTO v_ws, v_url, v_business_name, v_industry, v_target_location
  FROM public.seo_websites w
  WHERE w.id = p_website_id;

  IF v_ws IS NULL
     OR NOT (public.seo_role_in(v_ws, ARRAY['owner','admin','team_member'])
             OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not authorized to generate recommendations for this website.';
  END IF;

  -- 3. Concurrency: transaction-scoped advisory lock keyed deterministically
  --    to (website, generation op) so concurrent Generates serialize.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_website_id::text || ':recommendation_generate', 0));

  -- 4. Source selection: latest COMPLETED audit run (same rule as
  --    seo_report_generate). No completed run -> no issue-derived
  --    candidates this call (on-page templates are business-context-only
  --    and are still generated — they do not depend on an audit existing).
  SELECT a.id INTO v_run_id
  FROM public.seo_audit_runs a
  WHERE a.website_id = p_website_id AND a.status = 'completed'
  ORDER BY COALESCE(a.completed_at, a.started_at) DESC
  LIMIT 1;

  -- 5. Build the desired set (issue-derived + on-page) in a reentrant-safe
  --    temp table (DROP first so repeated calls within one transaction,
  --    as used by the self-cleaning SQL verification scripts, do not fail
  --    on "relation already exists").
  DROP TABLE IF EXISTS pg_temp.tmp_seo_rec_desired;
  CREATE TEMP TABLE tmp_seo_rec_desired (
    issue_id                  uuid,
    source_issue_fingerprint  text,
    area                      text NOT NULL,
    title                     text NOT NULL,
    current_value             text,
    suggested_change          text NOT NULL,
    why_it_helps              text NOT NULL,
    action_type               text NOT NULL,
    impact                    text NOT NULL,
    effort                    text NOT NULL,
    risk                      text NOT NULL,
    confidence_percentage     int NOT NULL
  ) ON COMMIT DROP;

  -- 5a. Issue-derived candidates: open/in_review issues from the selected
  --     run, mapped via the existing mock's CATEGORY_TO_AREA /
  --     ACTION_TYPE_BY_FIX_OWNER (src/mocks/recommendationMockData.ts).
  IF v_run_id IS NOT NULL THEN
    INSERT INTO tmp_seo_rec_desired (
      issue_id, source_issue_fingerprint, area, title, current_value,
      suggested_change, why_it_helps, action_type, impact, effort, risk,
      confidence_percentage
    )
    SELECT
      i.id,
      i.source_issue_fingerprint,
      CASE i.category
        WHEN 'schema' THEN 'schema'
        WHEN 'duplicate_content' THEN 'content'
        ELSE 'technical'
      END,
      i.title,
      NULL,
      i.suggested_next_action,
      i.why_it_matters,
      CASE i.fix_owner
        WHEN 'client_action' THEN 'manual_support'
        WHEN 'developer_needed' THEN 'approval_required'
        WHEN 'digibility_expert' THEN 'expert_review'
        WHEN 'system_suggestion' THEN 'auto_suggest'
      END,
      i.impact, i.effort, i.risk, i.confidence_percentage
    FROM public.seo_audit_issues i
    WHERE i.audit_run_id = v_run_id
      AND i.website_id = p_website_id
      AND i.status IN ('open', 'in_review')
      AND i.source_issue_fingerprint IS NOT NULL;
  END IF;

  -- 5b. On-page candidates: the 7 fixed templates, personalized only by
  --     business-context fields (src/mocks/recommendationMockData.ts
  --     ON_PAGE_TEMPLATES) — reproduced verbatim.
  INSERT INTO tmp_seo_rec_desired (
    issue_id, source_issue_fingerprint, area, title, current_value,
    suggested_change, why_it_helps, action_type, impact, effort, risk,
    confidence_percentage
  ) VALUES
    (NULL, NULL, 'title',
     'Homepage title tag doesn''t mention your service or location',
     'Home',
     v_business_name || ' - ' || COALESCE(v_industry, 'Professional Services')
       || COALESCE(' in ' || v_target_location, ''),
     'A descriptive title helps customers recognize your business in search results and can improve click-through rate.',
     'approval_required', 'high', 'low', 'low', 84),
    (NULL, NULL, 'meta_description',
     'Meta description is missing or generic',
     NULL,
     'Looking for ' || COALESCE(lower(v_industry), 'trusted local services') || '? '
       || v_business_name || ' offers reliable service'
       || COALESCE(' in ' || v_target_location, '') || '. Contact us today.',
     'A clear meta description encourages more people to click through from search results.',
     'approval_required', 'medium', 'low', 'low', 80),
    (NULL, NULL, 'h1',
     'Homepage H1 is too generic',
     'Welcome',
     v_business_name || COALESCE(' — Serving ' || v_target_location, ''),
     'Your H1 should tell visitors and search engines what the page is about at a glance.',
     'auto_suggest', 'medium', 'low', 'low', 82),
    (NULL, NULL, 'faq',
     'No FAQ section on key pages',
     NULL,
     'Add an FAQ section answering the 4-5 questions customers ask most before booking.',
     'FAQs can earn extra visibility in search results and address objections before customers call.',
     'manual_support', 'medium', 'medium', 'low', 70),
    (NULL, NULL, 'schema',
     'Business structured data is missing',
     'Not present',
     'Add LocalBusiness structured data with your name, address, phone and hours.',
     'Structured data helps search engines display rich results like hours and reviews directly in search.',
     'auto_suggest', 'medium', 'low', 'low', 85),
    (NULL, NULL, 'internal_links',
     'Key pages aren''t linked from the homepage or blog',
     NULL,
     'Link from your homepage and blog posts to your most important service pages.',
     'Internal links help search engines find and prioritize your key pages.',
     'manual_support', 'low', 'low', 'low', 75),
    (NULL, NULL, 'content',
     'Service pages are thin on detail',
     NULL,
     'Expand thin service pages with more detail on process, pricing range and what to expect.',
     'More helpful, specific content tends to rank better and builds more trust with visitors.',
     'manual_support', 'medium', 'medium', 'low', 72);

  -- 6. Three-way replace-to-match, one desired item at a time.
  FOR d IN SELECT * FROM tmp_seo_rec_desired LOOP
    IF d.issue_id IS NOT NULL THEN
      SELECT * INTO v_existing FROM public.seo_recommendations
      WHERE website_id = p_website_id AND is_current
        AND source_issue_fingerprint = d.source_issue_fingerprint
      LIMIT 1;
    ELSE
      SELECT * INTO v_existing FROM public.seo_recommendations
      WHERE website_id = p_website_id AND is_current
        AND issue_id IS NULL AND area = d.area
      LIMIT 1;
    END IF;

    IF NOT FOUND THEN
      -- Case 1: no current recommendation with this identity -> insert.
      INSERT INTO public.seo_recommendations (
        workspace_id, website_id, website_url, audit_run_id, issue_id,
        area, title, current_value, suggested_change, why_it_helps,
        action_type, impact, effort, risk, confidence_percentage,
        status, is_current, source_issue_fingerprint, generation_method, created_by
      ) VALUES (
        v_ws, p_website_id, v_url, v_run_id, d.issue_id,
        d.area, d.title, d.current_value, d.suggested_change, d.why_it_helps,
        d.action_type, d.impact, d.effort, d.risk, d.confidence_percentage,
        'suggested', true, d.source_issue_fingerprint, 'rule_based_v1', v_uid
      );
    ELSE
      v_changed := (v_existing.title IS DISTINCT FROM d.title)
        OR (v_existing.suggested_change IS DISTINCT FROM d.suggested_change)
        OR (v_existing.impact IS DISTINCT FROM d.impact)
        OR (v_existing.risk IS DISTINCT FROM d.risk)
        OR (v_existing.action_type IS DISTINCT FROM d.action_type);

      IF v_changed THEN
        IF v_existing.status IN ('suggested', 'needs_review') THEN
          -- Case 3: changed + untouched -> supersede. Retire the old row
          -- FIRST (frees the partial-unique identity slot) so the new
          -- INSERT below never momentarily collides with it.
          UPDATE public.seo_recommendations
            SET is_current = false, updated_at = now()
          WHERE id = v_existing.id;

          INSERT INTO public.seo_recommendations (
            workspace_id, website_id, website_url, audit_run_id, issue_id,
            area, title, current_value, suggested_change, why_it_helps,
            action_type, impact, effort, risk, confidence_percentage,
            status, is_current, source_issue_fingerprint, generation_method, created_by
          ) VALUES (
            v_ws, p_website_id, v_url, v_run_id, d.issue_id,
            d.area, d.title, d.current_value, d.suggested_change, d.why_it_helps,
            d.action_type, d.impact, d.effort, d.risk, d.confidence_percentage,
            'suggested', true, d.source_issue_fingerprint, 'rule_based_v1', v_uid
          )
          RETURNING id INTO v_new_id;

          UPDATE public.seo_recommendations
            SET superseded_by = v_new_id
          WHERE id = v_existing.id;
        END IF;
        -- Case 4 (changed but a human already acted): do nothing. The old
        -- row is left completely untouched; no new row is inserted.
      END IF;
      -- Case 2 (unchanged): no write at all.
    END IF;
  END LOOP;

  -- 7. Retire issue-derived recommendations whose source issue is no longer
  --    in the desired set (resolved, or no longer open/in_review), but only
  --    if nobody has acted on them yet. On-page recommendations are never
  --    auto-retired (no external issue that can "resolve").
  UPDATE public.seo_recommendations r
    SET is_current = false, superseded_by = NULL, updated_at = now()
  WHERE r.website_id = p_website_id
    AND r.is_current
    AND r.issue_id IS NOT NULL
    AND r.source_issue_fingerprint IS NOT NULL
    AND r.status IN ('suggested', 'needs_review')
    AND NOT EXISTS (
      SELECT 1 FROM tmp_seo_rec_desired t
      WHERE t.source_issue_fingerprint = r.source_issue_fingerprint
    );

  -- 8. Return the canonical current recommendation set for this website
  --    (not a transient/summary payload), stable ordering.
  RETURN QUERY
    SELECT * FROM public.seo_recommendations
    WHERE website_id = p_website_id AND is_current
    ORDER BY area, created_at, id;
END;
$$;

-- Grants: authenticated-only EXECUTE (the in-function role gate is
-- authoritative); anon + PUBLIC revoked up-front (defense in depth, folded
-- into this same migration — no corrective follow-up required).
REVOKE ALL ON FUNCTION public.seo_recommendation_generate(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_recommendation_generate(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_recommendation_generate(uuid) TO authenticated;
