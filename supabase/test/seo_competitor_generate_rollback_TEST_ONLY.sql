-- =============================================================================
-- SEO Competitor Benchmarking Stage 2A — ROLLBACK (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Reverses 20260724120040_seo_competitor_generate.sql ONLY (the generation RPC
-- + its internal heuristic helper). It does NOT touch the Stage 1 table
-- public.seo_competitors, its RLS, or any other object. Authored for symmetry
-- with the Stage 1 / Reports rollbacks; NOT used in the normal flow.
-- =============================================================================

DROP FUNCTION IF EXISTS public.seo_competitor_generate(uuid);
DROP FUNCTION IF EXISTS public.seo_competitor_heuristic_score(text);
