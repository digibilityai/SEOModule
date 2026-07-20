-- =============================================================================
-- SEO Reports Stage 1 — Browser-acceptance fixture CLEANUP
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Removes ONLY the deterministic browser-acceptance fixture row seeded by
-- seo_reports_stage1_browser_fixture_TEST_ONLY.sql. Targets the fixed fixture
-- id exclusively, so no real report data is affected.
-- =============================================================================

DELETE FROM public.seo_reports WHERE id='d1000000-0000-0000-0007-000000000001';

SELECT json_build_object(
  'fixture_remaining', (SELECT count(*) FROM public.seo_reports WHERE id='d1000000-0000-0000-0007-000000000001')
) AS cleanup_status;
