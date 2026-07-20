-- =============================================================================
-- SEO Backend — Reports Stage 2 — Migration: guarded report-generation RPC
-- =============================================================================
-- Additive only. Builds on Reports Stage 1 (`public.seo_reports`, migration
-- 20260720120035 — NOT edited here) and the existing live source tables
-- (seo_audit_runs, seo_approval_items, seo_content_opportunities,
-- seo_page_inventory/seo_page_performance_latest, seo_authority_opportunities,
-- seo_ai_content_gaps). Introduces ONE guarded SECURITY DEFINER RPC that
-- composes a real progress report server-side and upserts the single canonical
-- seo_reports row for a website + period.
--
-- SCOPE (Reports Stage 2 — guarded generation write path):
--   * Server-derived authorization (authenticated; workspace resolved from the
--     website; owner/admin/team_member or global admin; client/anon/nonmember/
--     cross-tenant denied with a single non-leaking error).
--   * Server-derived period (start/end/label), report_type, website_url, actor,
--     generated_at — NO client-supplied metrics/identity/dates/title/summary.
--   * Synchronous, transactional aggregation of the SIX live areas; the THREE
--     unavailable areas (competitor / roadmap / expert-support — no Supabase
--     source exists) are represented truthfully as "not connected", with a
--     `data_provenance` map in `summary` so a 0 is never read as a measured 0.
--   * Transaction-scoped advisory lock keyed by (website, report_type, period)
--     + INSERT ... ON CONFLICT DO UPDATE on the Stage 1 unique key, so
--     concurrent/duplicate Generate actions converge to ONE canonical row.
--   * NO async worker, NO PDF/CSV/schedule/email/share, NO production work.
--
-- Aggregation rules (documented; DB-native semantics, truthful — not a
-- byte-for-byte reproduction of the mock's app-level status strings):
--   audit:      latest vs previous COMPLETED audit (ORDER BY
--               COALESCE(completed_at,started_at) DESC); current snapshot, not
--               period-filtered (mirrors the mock's snapshot semantics).
--   approvals:  pending = status IN ('suggested','needs_review');
--               fixed    = status = 'completed'.
--   content:    planned = all opportunities; completed = status='archived'
--               (the app maps DB 'archived' → app 'completed').
--   pages:      per-active-page performance status; see the page-performance
--               decision table below (exact parity for all deterministic
--               branches; a DETERMINISTIC resolution for the one branch that is
--               non-deterministic in the current TypeScript — Branch 3).
--   authority:  total + avoided (status='avoided').
--   ai:         total content gaps.
--
-- Page-performance normalization (parity with
-- seoPagePerformanceSupabaseService.ts):
--   status(movement, content):
--     content IN ('aging','stale')                  -> needs_refresh
--     else movement='improving'                     -> improving
--     else movement='stable'                        -> stable
--     else movement='declining'                     -> declining
--     else movement IN ('new','no_data') / null     -> not_enough_data
--   snapshot pick per page (from seo_page_performance_latest):
--     1) primary-keyword row (page_keyword_id = primary keyword id)
--     2) else page-level aggregate row (page_keyword_id IS NULL)
--     3) else ANY row — DETERMINISTIC resolution (Branch 3, intentional):
--        ORDER BY snapshot_date DESC, page_keyword_id ASC LIMIT 1
--        (the current TS uses an unordered `forPage[0]`, so this branch has no
--        stable parity target; we resolve it deterministically — this is a
--        documented normalization decision, NOT byte-identical TS parity)
--     4) else no snapshot -> movement 'no_data'
--   Only active pages (is_active=true) are counted; aging/stale pages are
--   never counted as improving/declining.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.seo_report_generate(
  p_website_id uuid,
  p_period_key text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_ws             uuid;
  v_url            text;
  v_report_id      uuid;
  v_today          date := current_date;
  v_period_start   date;
  v_period_end     date;
  v_period_label   text;
  -- audit
  v_overall_curr   int := 0;
  v_overall_prev   int := 0;
  v_issues_found   int := 0;
  v_has_audit      boolean := false;
  -- approvals
  v_pending        int := 0;
  v_fixed          int := 0;
  -- content
  v_content_total  int := 0;
  v_content_done   int := 0;
  -- pages
  v_pages_total    int := 0;
  v_improving      int := 0;
  v_declining      int := 0;
  -- authority
  v_authority      int := 0;
  v_avoided        int := 0;
  -- ai
  v_ai_gaps        int := 0;
  -- text
  v_summary        jsonb;
  v_next           jsonb := '[]'::jsonb;
BEGIN
  -- 1. Authentication.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required to generate a report.';
  END IF;

  -- 2. Resolve website -> workspace + url server-side (never trust a caller
  --    workspace). A missing website yields the SAME generic error as a role
  --    failure so existence never leaks to an unauthorized caller.
  SELECT w.workspace_id, w.website_url INTO v_ws, v_url
  FROM public.seo_websites w
  WHERE w.id = p_website_id;

  IF v_ws IS NULL
     OR NOT (public.seo_role_in(v_ws, ARRAY['owner','admin','team_member'])
             OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not authorized to generate a report for this website.';
  END IF;

  -- 3. Period derivation + validation (Stage 1 canonical keys only).
  IF p_period_key = 'current_month' THEN
    v_period_start := date_trunc('month', v_today)::date;
    v_period_end   := v_today;
    v_period_label := trim(to_char(v_today, 'FMMonth YYYY'));
  ELSIF p_period_key = 'last_month' THEN
    v_period_start := (date_trunc('month', v_today) - interval '1 month')::date;
    v_period_end   := (date_trunc('month', v_today) - interval '1 day')::date;
    v_period_label := trim(to_char(v_period_start, 'FMMonth YYYY'));
  ELSIF p_period_key = 'last_90_days' THEN
    v_period_start := (v_today - interval '90 days')::date;
    v_period_end   := v_today;
    v_period_label := trim(to_char(v_period_start, 'FMMon DD')) || ' – '
                      || trim(to_char(v_today, 'FMMon DD, YYYY'));
  ELSE
    RAISE EXCEPTION 'Unsupported report period: %', p_period_key;
  END IF;

  -- 4. Concurrency: transaction-scoped advisory lock keyed by
  --    (website, report_type, period) so concurrent Generates serialize and
  --    converge to one row (the unique key is the final guarantee).
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_website_id::text || ':progress:' || p_period_key, 0));

  -- 5a. Audit — latest vs previous COMPLETED (current snapshot).
  SELECT overall_visibility_score, issue_count, true
    INTO v_overall_curr, v_issues_found, v_has_audit
  FROM public.seo_audit_runs
  WHERE website_id = p_website_id AND status = 'completed'
  ORDER BY COALESCE(completed_at, started_at) DESC
  LIMIT 1;

  IF v_has_audit THEN
    SELECT COALESCE(overall_visibility_score, v_overall_curr)
      INTO v_overall_prev
    FROM public.seo_audit_runs
    WHERE website_id = p_website_id AND status = 'completed'
    ORDER BY COALESCE(completed_at, started_at) DESC
    OFFSET 1 LIMIT 1;
    IF NOT FOUND THEN v_overall_prev := v_overall_curr; END IF;
  ELSE
    v_overall_curr := 0; v_overall_prev := 0; v_issues_found := 0;
  END IF;

  -- 5b. Approvals.
  SELECT count(*) FILTER (WHERE status IN ('suggested','needs_review')),
         count(*) FILTER (WHERE status = 'completed')
    INTO v_pending, v_fixed
  FROM public.seo_approval_items
  WHERE website_id = p_website_id;

  -- 5c. Content (app 'completed' = DB 'archived').
  SELECT count(*), count(*) FILTER (WHERE status = 'archived')
    INTO v_content_total, v_content_done
  FROM public.seo_content_opportunities
  WHERE website_id = p_website_id;

  -- 5d. Page performance — resolve each ACTIVE page's status, then count.
  WITH pages AS (
    SELECT pi.id, pi.content_status,
           (SELECT k.id FROM public.seo_page_keywords k
             WHERE k.page_id = pi.id AND k.is_primary = true LIMIT 1) AS primary_kw
    FROM public.seo_page_inventory pi
    WHERE pi.website_id = p_website_id AND pi.is_active = true
  ),
  picked AS (
    SELECT p.id, p.content_status,
      (
        SELECT l.movement_status
        FROM public.seo_page_performance_latest l
        WHERE l.page_id = p.id
        ORDER BY
          -- Branch 1: primary keyword; Branch 2: page-level (NULL);
          -- Branch 3 (deterministic): snapshot_date DESC, page_keyword_id ASC
          (p.primary_kw IS NOT NULL AND l.page_keyword_id = p.primary_kw) DESC,
          (l.page_keyword_id IS NULL) DESC,
          l.snapshot_date DESC,
          l.page_keyword_id ASC NULLS LAST
        LIMIT 1
      ) AS movement_status
    FROM pages p
  ),
  resolved AS (
    SELECT
      CASE
        WHEN content_status IN ('aging','stale') THEN 'needs_refresh'
        WHEN movement_status = 'improving' THEN 'improving'
        WHEN movement_status = 'stable' THEN 'stable'
        WHEN movement_status = 'declining' THEN 'declining'
        ELSE 'not_enough_data'  -- new / no_data / null
      END AS perf_status
    FROM picked
  )
  SELECT count(*),
         count(*) FILTER (WHERE perf_status = 'improving'),
         count(*) FILTER (WHERE perf_status = 'declining')
    INTO v_pages_total, v_improving, v_declining
  FROM resolved;

  -- 5e. Authority.
  SELECT count(*), count(*) FILTER (WHERE status = 'avoided')
    INTO v_authority, v_avoided
  FROM public.seo_authority_opportunities
  WHERE website_id = p_website_id;

  -- 5f. AI content gaps.
  SELECT count(*) INTO v_ai_gaps
  FROM public.seo_ai_content_gaps
  WHERE website_id = p_website_id;

  -- 6. Next actions (live signals only; unavailable areas contribute none).
  IF v_pending > 0 THEN
    v_next := v_next || to_jsonb(format('Review the %s pending approval%s in the Approval Queue.',
                                        v_pending, CASE WHEN v_pending = 1 THEN '' ELSE 's' END));
  END IF;
  IF v_declining > 0 THEN
    v_next := v_next || to_jsonb(format('Check the %s declining page%s in Page Performance.',
                                        v_declining, CASE WHEN v_declining = 1 THEN '' ELSE 's' END));
  END IF;
  IF jsonb_array_length(v_next) = 0 THEN
    v_next := v_next || to_jsonb('No urgent actions right now — keep monitoring your visibility score.'::text);
  END IF;

  -- 7. Compose truthful summary (+ provenance).
  v_summary := jsonb_build_object(
    'overall_score_current', v_overall_curr,
    'overall_score_previous', v_overall_prev,
    'overall_score_movement', v_overall_curr - v_overall_prev,
    'technical_summary', CASE WHEN v_has_audit
        THEN format('%s technical issue%s found in the latest audit.', v_issues_found,
                    CASE WHEN v_issues_found = 1 THEN '' ELSE 's' END)
        ELSE 'No completed audit yet for this period.' END,
    'issues_found_count', v_issues_found,
    'issues_fixed_count', v_fixed,
    'pending_approvals_count', v_pending,
    'content_summary', CASE WHEN v_content_total > 0
        THEN format('%s content opportunit%s identified, %s completed.', v_content_total,
                    CASE WHEN v_content_total = 1 THEN 'y' ELSE 'ies' END, v_content_done)
        ELSE 'No content opportunities identified yet.' END,
    'content_pieces_planned', v_content_total,
    'content_pieces_completed', v_content_done,
    'performance_summary', CASE WHEN v_pages_total > 0
        THEN format('%s page%s improving, %s declining.', v_improving,
                    CASE WHEN v_improving = 1 THEN '' ELSE 's' END, v_declining)
        ELSE 'No page performance data tracked yet.' END,
    'declining_pages_count', v_declining,
    'improving_pages_count', v_improving,
    'offpage_summary', CASE WHEN v_authority > 0
        THEN format('%s authority opportunit%s identified, %s flagged as risky and avoided.', v_authority,
                    CASE WHEN v_authority = 1 THEN 'y' ELSE 'ies' END, v_avoided)
        ELSE 'No authority opportunities identified yet.' END,
    'authority_opportunities_count', v_authority,
    'ai_visibility_summary', CASE WHEN v_ai_gaps > 0
        THEN format('%s AI content gap%s identified.', v_ai_gaps,
                    CASE WHEN v_ai_gaps = 1 THEN '' ELSE 's' END)
        ELSE 'No AI visibility gaps identified yet.' END,
    'ai_content_gaps_count', v_ai_gaps,
    -- Unavailable areas: truthful "not connected" (never fabricated / never a measured 0).
    'competitor_summary', 'Competitor tracking is not connected yet.',
    'competitor_gaps_count', 0,
    'roadmap_summary', 'The 90-day roadmap is not connected yet.',
    'roadmap_completed_count', 0,
    'roadmap_total_count', 0,
    'expert_support_summary', 'Expert support tracking is not connected yet.',
    'open_support_requests_count', 0,
    'next_actions', v_next,
    'data_provenance', jsonb_build_object(
      'audit', 'live', 'approvals', 'live', 'content', 'live',
      'page_performance', 'live', 'authority', 'live', 'ai_visibility', 'live',
      'competitor', 'unavailable', 'roadmap', 'unavailable', 'expert_support', 'unavailable'
    )
  );

  -- 8. Canonical upsert (transactional; one row per website+type+period).
  INSERT INTO public.seo_reports AS r
    (workspace_id, website_id, website_url, report_type, period_key, period_label,
     period_start, period_end, title, status, summary, generated_at, created_by)
  VALUES
    (v_ws, p_website_id, v_url, 'progress', p_period_key, v_period_label,
     v_period_start, v_period_end, 'Progress report — ' || v_period_label,
     'generated', v_summary, now(), v_uid)
  ON CONFLICT (website_id, report_type, period_key) DO UPDATE
    SET website_url  = EXCLUDED.website_url,
        period_label = EXCLUDED.period_label,
        period_start = EXCLUDED.period_start,
        period_end   = EXCLUDED.period_end,
        title        = EXCLUDED.title,
        status       = 'generated',
        summary      = EXCLUDED.summary,
        generated_at = now(),
        updated_at   = now()
        -- created_by intentionally preserved (original author retained)
  RETURNING r.id INTO v_report_id;

  RETURN v_report_id;
END;
$$;

-- Grants: authenticated-only EXECUTE (in-function role gate is authoritative);
-- anon/PUBLIC denied. Mirrors the seo_crawl_request convention.
REVOKE ALL ON FUNCTION public.seo_report_generate(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seo_report_generate(uuid, text) TO authenticated;
