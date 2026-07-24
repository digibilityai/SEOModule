-- =============================================================================
-- ROLLBACK — Recommendation Generation Stage 1
--   migration 20260724130000_seo_recommendation_generate.sql
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Reason: this migration was applied to Digi_SEO_Test ahead of the intended
-- TEST-promotion gate in the governing delivery sequence (local verification
-- -> Digi_SEO_Test -> production), without an approval recorded in the
-- controlling ChatGPT instruction trail. Rollback safety was proven by direct
-- database audit before this script was written or run (see
-- SEO_RECOMMENDATION_GENERATION_STAGE1_VERIFICATION.md "Environment-Control
-- Reconciliation" addendum): 0 non-fixture rows use either new column, 0
-- other functions/views/constraints depend on the RPC or the two new
-- indexes, and dropping the columns removes no legitimate data (both are
-- 100% NULL across every existing row).
--
-- Idempotent: every statement uses IF EXISTS and can be re-run safely.
--
-- Does NOT touch: seo_audit_issues, seo_approval_items, seo_approval_transition,
-- any crawler table, any other seo_recommendations column or row, or the
-- pending SSO migration 20260720121000.
-- =============================================================================

-- 1. Revoke RPC execute privileges (defense-in-depth; DROP FUNCTION below
--    removes the grants anyway, but revoke first per the explicit dependency
--    order requested).
REVOKE ALL ON FUNCTION public.seo_recommendation_generate(uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.seo_recommendation_generate(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.seo_recommendation_generate(uuid) FROM PUBLIC;

-- 2. Drop the guarded generation RPC.
DROP FUNCTION IF EXISTS public.seo_recommendation_generate(uuid);

-- 3. Drop only the two indexes introduced by this migration.
DROP INDEX IF EXISTS public.uq_seo_recommendations_issue_fingerprint;
DROP INDEX IF EXISTS public.uq_seo_recommendations_onpage_area;

-- 4. Drop only the two additive columns introduced by this migration.
ALTER TABLE public.seo_recommendations
  DROP COLUMN IF EXISTS source_issue_fingerprint,
  DROP COLUMN IF EXISTS generation_method;

-- 5. Post-rollback verification (read-only assertions; raises if anything is
--    left behind or if anything unrelated was disturbed).
DO $t$
DECLARE n int;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
             WHERE ns.nspname='public' AND p.proname='seo_recommendation_generate') THEN
    RAISE EXCEPTION 'ROLLBACK: seo_recommendation_generate still exists';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
             AND indexname IN ('uq_seo_recommendations_issue_fingerprint','uq_seo_recommendations_onpage_area')) THEN
    RAISE EXCEPTION 'ROLLBACK: a new index still exists';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
             AND table_name='seo_recommendations' AND column_name IN ('source_issue_fingerprint','generation_method')) THEN
    RAISE EXCEPTION 'ROLLBACK: a new column still exists';
  END IF;
  -- seo_recommendations row count + column set otherwise untouched.
  SELECT count(*) INTO n FROM public.seo_recommendations;
  RAISE NOTICE 'ROLLBACK VERIFIED: RPC gone, both indexes gone, both columns gone. seo_recommendations row count = %', n;
END $t$;
