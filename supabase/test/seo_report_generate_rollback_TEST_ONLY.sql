-- =============================================================================
-- SEO Reports Stage 2 — ROLLBACK for 20260720120036_seo_report_generate.sql
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Drops the Stage 2 generation RPC on Digi_SEO_Test only. Stage 1's
-- seo_reports table and read path are unaffected. After running, remove the
-- 20260720120036 migration-history row if the migration had been recorded.
-- =============================================================================

DROP FUNCTION IF EXISTS public.seo_report_generate(uuid, text);
