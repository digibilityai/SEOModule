-- =============================================================================
-- SEO Reports Stage 1 — Browser-acceptance POPULATED-STATE fixture (SEED)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Seeds EXACTLY ONE public.seo_reports row on Digi_SEO_Test so an operator can
-- visually verify the Reports Stage 1 populated state in the browser (generation
-- is deferred to Stage 2, so no report exists otherwise). No schema change, no
-- migration. Uses the existing seo_reports shape only.
--
-- Targets the TEST website `https://digibility.ai`
-- (fb98d59c-0f7d-4724-9f60-9db385bf2592, workspace
-- 77777777-0000-0000-0000-000000000001) — the active website used for the
-- authenticated browser matrix.
--
-- SAFETY:
--   * Fail-fast guard: aborts unless that TEST website exists (a production
--     project would not have this id).
--   * Idempotent + non-destructive: ON CONFLICT (website_id, report_type,
--     period_key) DO NOTHING — never overwrites a real report row.
--   * Deterministic fixture id d1000000-0000-0000-0007-000000000001 → cleanup
--     targets only this row (see seo_reports_stage1_browser_fixture_cleanup_TEST_ONLY.sql).
--   * period_key='last_month' matches ReportsPage's default period, so the row
--     renders on first load without changing the selector.
-- =============================================================================

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.seo_websites
                 WHERE id='fb98d59c-0f7d-4724-9f60-9db385bf2592'
                   AND workspace_id='77777777-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'Refusing to seed: target TEST website fb98d59c-… not found — this does not look like Digi_SEO_Test.';
  END IF;
END $guard$;

INSERT INTO public.seo_reports
  (id, workspace_id, website_id, website_url, report_type, period_key, period_label,
   period_start, period_end, title, status, summary, generated_at, created_by)
VALUES (
  'd1000000-0000-0000-0007-000000000001',
  '77777777-0000-0000-0000-000000000001',
  'fb98d59c-0f7d-4724-9f60-9db385bf2592',
  'https://digibility.ai',
  'progress',
  'last_month',
  'June 2026',
  '2026-06-01',
  '2026-06-30',
  'Progress report — June 2026',
  'generated',
  jsonb_build_object(
    'overall_score_current', 62,
    'overall_score_previous', 56,
    'overall_score_movement', 6,
    'technical_summary', '1 technical issue found and 1 fixed during this period.',
    'issues_found_count', 1,
    'issues_fixed_count', 1,
    'pending_approvals_count', 1,
    'content_summary', '1 content opportunity identified, nothing published yet.',
    'content_pieces_planned', 4,
    'content_pieces_completed', 0,
    'performance_summary', 'Homepage improving; 2 service pages declining.',
    'declining_pages_count', 2,
    'improving_pages_count', 1,
    'offpage_summary', '9 authority opportunities identified, 2 flagged as risky and avoided.',
    'authority_opportunities_count', 9,
    'ai_visibility_summary', 'Cited in 2 of 4 tracked AI answers so far.',
    'ai_content_gaps_count', 3,
    'competitor_summary', '2 competitors tracked; trailing on reviews and AI visibility.',
    'competitor_gaps_count', 3,
    'roadmap_summary', '90-day roadmap generated; early actions in progress.',
    'roadmap_completed_count', 0,
    'roadmap_total_count', 1,
    'expert_support_summary', 'No open support requests yet.',
    'open_support_requests_count', 0,
    'next_actions', jsonb_build_array(
      'Review the pending approval in the Approval Queue.',
      'Add pricing detail to the drain cleaning service page.',
      'Ask recent customers for Google reviews.'
    )
  ),
  '2026-06-05T09:00:00Z',
  NULL
)
ON CONFLICT (website_id, report_type, period_key) DO NOTHING;

-- Confirmation (no secrets): exactly one fixture row present.
SELECT json_build_object(
  'fixture_present', (SELECT count(*) FROM public.seo_reports WHERE id='d1000000-0000-0000-0007-000000000001'),
  'website_id',      'fb98d59c-0f7d-4724-9f60-9db385bf2592',
  'period_key',      'last_month'
) AS fixture_status;
