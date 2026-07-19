-- =============================================================================
-- SEO P1a Step 1 — Domain Ownership Verification DB Contract — ROLLBACK (TEST ONLY)
-- =============================================================================
--                          ****  TEST ONLY  ****
--                 ****  DO NOT RUN unless explicitly instructed  ****
--
-- Reverse-order teardown of migration 20260716120031 on Digi_SEO_Test only.
-- Additive-only migration → this drops ONLY the objects it created. It does NOT
-- alter or drop any pre-existing table/column/policy/function (including the
-- shared public.set_updated_at() trigger fn, which this migration only REUSED).
-- Tables are dropped in dependency order (audit child first); their policies,
-- indexes and triggers drop with them.
-- =============================================================================

-- 1. Triggers + the integrity trigger function (triggers also drop with the
--    tables, but drop them explicitly first for clarity/idempotency).
DROP TRIGGER IF EXISTS trg_seo_ownership_verification_events_integrity ON public.seo_ownership_verification_events;
DROP TRIGGER IF EXISTS trg_seo_ownership_verifications_integrity ON public.seo_ownership_verifications;
DROP TRIGGER IF EXISTS trg_seo_ownership_verifications_updated_at ON public.seo_ownership_verifications;
DROP FUNCTION IF EXISTS public.seo_ownership_verification_integrity();

-- 2. Tables in dependency order (events reference verifications). Policies +
--    indexes drop automatically with the tables.
DROP TABLE IF EXISTS public.seo_ownership_verification_events;
DROP TABLE IF EXISTS public.seo_ownership_verifications;

-- NOTE: public.set_updated_at() is a pre-existing shared function — NOT dropped.
-- No frontend/supabaseTypes.ts constant was added by Step 1; documentation is
-- reverted separately. No existing DB object is altered by this rollback.
