-- =============================================================================
-- SEO Reports Stage 1 — ROLLBACK for 20260720120035_seo_reports_foundation.sql
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Reverses the Reports Stage 1 foundation migration on Digi_SEO_Test only, if
-- the migration must be backed out during TEST bring-up. seo_reports is a NEW
-- table with no dependents, so a single DROP restores the prior state exactly
-- (the trigger and both policies drop with the table).
--
-- After running this, also remove the migration-history row for
-- 20260720120035 if the migration had been recorded, so the history stays
-- consistent (only if it was applied via the migration runner).
-- =============================================================================

DROP TABLE IF EXISTS public.seo_reports CASCADE;
