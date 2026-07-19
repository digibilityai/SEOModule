-- =============================================================================
-- SEO Phase 16G / Crawler 1E — Publishing — ROLLBACK  ****  TEST ONLY  ****
-- =============================================================================
-- DO NOT RUN ON PRODUCTION. DO NOT RUN unless explicitly instructed.
-- Drops ONLY Phase 16G objects; preserves all Phase 16C–16F objects and all
-- Stage 1–6 product tables. Additive provenance columns are removed last, after
-- confirming no later dependency. Published TEST rows in the existing product
-- tables are disposable-fixture rows; delete them separately by tag/website.
-- =============================================================================

-- 1. Functions first (publish RPC, then orchestration RPC).
DROP FUNCTION IF EXISTS public.seo_crawl_worker_publish_results(uuid, text, uuid, integer);
DROP FUNCTION IF EXISTS public.seo_crawl_request_audit(uuid, text, jsonb);

-- 2. Publication evidence + mapping tables (drop policies via table drop).
DROP TABLE IF EXISTS public.seo_crawl_publications;
DROP TABLE IF EXISTS public.seo_crawl_issue_audit_map;

-- 3. Additive nullable provenance columns (only after the above are gone).
ALTER TABLE public.seo_audit_issues
  DROP COLUMN IF EXISTS source,
  DROP COLUMN IF EXISTS crawl_job_id,
  DROP COLUMN IF EXISTS source_issue_fingerprint,
  DROP COLUMN IF EXISTS source_rule_version,
  DROP COLUMN IF EXISTS issue_scope,
  DROP COLUMN IF EXISTS source_category,
  DROP COLUMN IF EXISTS source_severity;

ALTER TABLE public.seo_page_inventory
  DROP COLUMN IF EXISTS http_status,
  DROP COLUMN IF EXISTS word_count,
  DROP COLUMN IF EXISTS content_type,
  DROP COLUMN IF EXISTS first_h1,
  DROP COLUMN IF EXISTS source,
  DROP COLUMN IF EXISTS source_crawl_job_id,
  DROP COLUMN IF EXISTS crawler_extracted_at,
  DROP COLUMN IF EXISTS crawler_extractor_version;

-- 4. The crawl-job → audit-run association column (last).
ALTER TABLE public.seo_crawl_jobs DROP COLUMN IF EXISTS audit_run_id;

SELECT 'PHASE 16G ROLLBACK (TEST) COMPLETE' AS result;
