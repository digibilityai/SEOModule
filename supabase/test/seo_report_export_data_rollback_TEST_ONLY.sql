-- =============================================================================
-- SEO Reports Stage 3 — ROLLBACK for 20260720120038_seo_report_export_data.sql
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Drops the Stage 3 export-data RPC on Digi_SEO_Test only. Stage 1/2 objects
-- are unaffected. Remove the 20260720120038 migration-history row afterward if
-- it had been recorded.
-- =============================================================================

DROP FUNCTION IF EXISTS public.seo_report_export_data(uuid, text);
