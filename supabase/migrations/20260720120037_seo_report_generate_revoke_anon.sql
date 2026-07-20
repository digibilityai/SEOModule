-- =============================================================================
-- SEO Backend — Reports Stage 2 — Corrective migration: deny anon EXECUTE
-- =============================================================================
-- Additive corrective follow-up to 20260720120036_seo_report_generate.sql
-- (which is applied and immutable). That migration revoked EXECUTE from PUBLIC
-- and granted it to `authenticated`, but did NOT explicitly revoke the grant
-- that Supabase's default privileges give to the `anon` role for new functions
-- in schema public. This migration removes anon's EXECUTE so the RPC follows
-- the same authenticated-only convention as seo_crawl_request /
-- seo_ownership_verification_* (REVOKE FROM PUBLIC + REVOKE FROM anon + GRANT
-- TO authenticated).
--
-- Functional note: the RPC already rejects anon at runtime (auth.uid() IS NULL
-- -> "Authentication required"); this migration corrects the GRANT posture
-- (defense in depth) so anon cannot even invoke it.
-- =============================================================================

REVOKE ALL ON FUNCTION public.seo_report_generate(uuid, text) FROM anon;
-- Re-assert the intended grants (idempotent; harmless if already present).
REVOKE ALL ON FUNCTION public.seo_report_generate(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seo_report_generate(uuid, text) TO authenticated;
