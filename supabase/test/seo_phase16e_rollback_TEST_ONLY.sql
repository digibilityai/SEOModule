-- =============================================================================
-- SEO Phase 16E — Crawl Discovery Storage — ROLLBACK (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
-- Reverses migration 20260714120027 on Digi_SEO_Test only. Drops the discovery
-- worker RPCs, the discovery tables (policies/indexes drop with them), and the
-- additive discovery_stats column. Preserves ALL Phase 16C/16D objects. No
-- customer data outside the crawler-discovery domain is affected.
-- =============================================================================

DROP FUNCTION IF EXISTS public.seo_crawl_worker_update_discovery_progress(uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_record_discovery(uuid, text, uuid, jsonb, jsonb);

DROP TABLE IF EXISTS public.seo_crawl_sitemaps;
DROP TABLE IF EXISTS public.seo_crawl_discovered_pages;

ALTER TABLE public.seo_crawl_jobs DROP COLUMN IF EXISTS discovery_stats;

-- Registry constants (supabaseTypes.ts) + docs + worker discovery modules are
-- reverted separately; no existing DB table is altered by this rollback.
