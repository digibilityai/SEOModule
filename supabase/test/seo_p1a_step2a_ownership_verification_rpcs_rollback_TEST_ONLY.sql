-- =============================================================================
-- SEO P1a Step 2A — Guarded CUSTOMER ownership-verification RPCs — ROLLBACK
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
--
-- Reverse-order teardown of migration 20260716120032 on Digi_SEO_Test only.
-- Additive-only migration → this drops ONLY the functions it created (the 4
-- customer RPCs + 3 internal helpers). It does NOT drop or alter:
--   * the Step 1 tables seo_ownership_verifications / _events or their history,
--   * any crawler object, Page Performance object, Stage 6 object,
--   * any other existing SEO object or the shared set_updated_at().
-- =============================================================================

-- 1. Customer RPCs.
DROP FUNCTION IF EXISTS public.seo_ownership_verification_initiate(uuid);
DROP FUNCTION IF EXISTS public.seo_ownership_verification_recheck(uuid);
DROP FUNCTION IF EXISTS public.seo_ownership_verification_reverify(uuid);
DROP FUNCTION IF EXISTS public.seo_ownership_verification_revoke(uuid);

-- 2. Internal helpers.
DROP FUNCTION IF EXISTS public._seo_ownership_authorize(uuid);
DROP FUNCTION IF EXISTS public.seo_ownership_new_challenge_token();
DROP FUNCTION IF EXISTS public.seo_ownership_extract_host(text);

-- Step 1 tables + audit history and every other object are intentionally left
-- untouched. No frontend/supabaseTypes.ts constant was added by Step 2A.
