-- =============================================================================
-- SEO Competitor Benchmarking Stage 1 — ROLLBACK for 20260720123000_seo_competitors.sql
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Reverses the Competitor Benchmarking Stage 1 table on Digi_SEO_Test only.
-- seo_competitors is a NEW table with no dependents; a single DROP restores the
-- prior state (trigger + both policies drop with the table). Remove the
-- 20260720123000 migration-history row afterward if it had been recorded.
-- =============================================================================

DROP TABLE IF EXISTS public.seo_competitors CASCADE;
