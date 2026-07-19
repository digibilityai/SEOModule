-- =============================================================================
-- SEO P1a Step 2B — Service-role RPCs + global-admin override — ROLLBACK
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
--
-- Reverse-order teardown of migration 20260716120033 on Digi_SEO_Test only.
-- Additive-only migration → this drops ONLY the objects it created (3 RPCs + the
-- internal claims table). It does NOT drop or alter:
--   * the Step 1 tables seo_ownership_verifications / _events or their history,
--   * the Step 2A customer RPCs / helpers,
--   * any crawler object/data, Page Performance, Stage 6,
--   * any earlier SEO migration or the shared set_updated_at().
-- =============================================================================

-- 1. RPCs first.
DROP FUNCTION IF EXISTS public.seo_ownership_verification_admin_override(uuid, text, text);
DROP FUNCTION IF EXISTS public.seo_ownership_verification_record_result(uuid, text, uuid, text, text, text, text);
DROP FUNCTION IF EXISTS public.seo_ownership_verification_claim(text, integer);

-- 2. Internal claim/lease ledger (its policy + indexes drop with the table).
DROP TABLE IF EXISTS public.seo_ownership_verification_claims;

-- Step 1 tables + audit history, Step 2A RPCs, and every other object are left
-- untouched. No frontend/supabaseTypes.ts constant was added by Step 2B.
