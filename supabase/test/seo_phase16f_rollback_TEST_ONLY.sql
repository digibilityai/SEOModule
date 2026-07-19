-- =============================================================================
-- SEO Phase 16F — Crawl Extraction + Issues — ROLLBACK (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
-- Reverses migration 20260714120028 on Digi_SEO_Test only. Drops the extraction
-- worker RPCs, the issues table (child) then the snapshots table, and the
-- additive extraction_stats column. Preserves ALL Phase 16C/16D/16E objects. No
-- data outside the crawler-extraction domain is affected.
-- =============================================================================

DROP FUNCTION IF EXISTS public.seo_crawl_worker_update_extraction_progress(uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_record_issues(uuid, text, uuid, jsonb, uuid);
DROP FUNCTION IF EXISTS public.seo_crawl_worker_record_snapshots(uuid, text, uuid, jsonb);

DROP TABLE IF EXISTS public.seo_crawl_issues;            -- child (references snapshots)
DROP TABLE IF EXISTS public.seo_crawl_page_snapshots;

ALTER TABLE public.seo_crawl_jobs DROP COLUMN IF EXISTS extraction_stats;

-- Registry constants (supabaseTypes.ts) + docs + worker extraction modules are
-- reverted separately; no existing DB table is altered by this rollback.
