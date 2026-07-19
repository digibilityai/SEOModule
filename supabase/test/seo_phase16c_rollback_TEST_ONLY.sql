-- =============================================================================
-- SEO Phase 16C — Crawler Control Plane — ROLLBACK (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
--
-- Reverse-order teardown of migration 20260713120025 on Digi_SEO_Test only.
-- Additive-only migration → this drops ONLY the objects it created. It does NOT
-- alter or drop any pre-existing table/column/policy/function, so no existing
-- record is affected. Tables are dropped in dependency order (children first);
-- their policies/indexes/triggers drop with them.
-- =============================================================================

-- 1. RPCs + helper functions first.
DROP FUNCTION IF EXISTS public.seo_crawl_claim_job(text, integer);
DROP FUNCTION IF EXISTS public.seo_crawl_cancel(uuid);
DROP FUNCTION IF EXISTS public.seo_crawl_request(uuid, text, jsonb);
DROP FUNCTION IF EXISTS public.seo_crawl_normalize_config(jsonb);

-- 2. Trigger fn (its triggers drop with the table, but drop the fn explicitly).
DROP TRIGGER IF EXISTS trg_seo_crawl_jobs_integrity ON public.seo_crawl_jobs;
DROP TRIGGER IF EXISTS trg_seo_crawl_jobs_updated_at ON public.seo_crawl_jobs;
DROP FUNCTION IF EXISTS public.seo_crawl_job_integrity();

-- 3. Tables in dependency order (events + attempts reference jobs). Policies +
--    indexes drop automatically with the tables.
DROP TABLE IF EXISTS public.seo_crawl_events;
DROP TABLE IF EXISTS public.seo_crawl_attempts;
DROP TABLE IF EXISTS public.seo_crawl_jobs;

-- Registry constants (supabaseTypes.ts) + documentation are reverted separately
-- in the frontend/docs; no existing DB table is altered by this rollback.
