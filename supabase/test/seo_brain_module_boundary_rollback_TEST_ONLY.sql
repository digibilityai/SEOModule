-- =============================================================================
-- ROLLBACK: Digi Brain Module Contract v1, Stage 2B machine boundary
--   migrations 20260920120000 + 20260920120100
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Both migrations are purely ADDITIVE: they create one new table, one new
-- trigger function, one new normalizer and four new read functions, and they
-- alter nothing that already existed. Removing them therefore cannot affect any
-- customer table, RLS policy, RPC or row. In particular this script does NOT
-- touch seo_websites, seo_workspaces, seo_workspace_members, seo_audit_runs,
-- seo_audit_issues, seo_recommendations, seo_ownership_verifications, the
-- crawler control plane, or the SSO migration 20260720121000.
--
-- The only data lost is the human-authorized Digi Brain link rows themselves.
-- Those are authorization records, so re-running the forward migration leaves
-- an empty link table and every machine call resolves to target_not_linked
-- until a human re-authorizes each link. That is the intended fail-closed
-- outcome, not a defect, but it is the reason to check the table is empty (or
-- to export it) before running this on anything but a disposable project.
--
-- Idempotent: every statement uses IF EXISTS and can be re-run safely.
-- =============================================================================

-- Inspect before destroying: how many authorizations are about to be lost.
DO $$
DECLARE n integer;
BEGIN
  IF to_regclass('public.seo_brain_website_links') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM public.seo_brain_website_links' INTO n;
    RAISE NOTICE 'seo_brain_website_links rows about to be dropped: %', n;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.seo_brain_current_recommendations(text, text, integer);
DROP FUNCTION IF EXISTS public.seo_brain_crawl_findings(text, text, integer);
DROP FUNCTION IF EXISTS public.seo_brain_ownership_status(text, text);
DROP FUNCTION IF EXISTS public.seo_brain_resolve_target(text, text);

DROP TRIGGER IF EXISTS trg_seo_brain_website_links_updated_at ON public.seo_brain_website_links;
DROP TRIGGER IF EXISTS trg_seo_brain_website_links_derive ON public.seo_brain_website_links;

-- Policies go with the table, but dropping them explicitly keeps this readable
-- and safe to run against a partially applied state.
DROP POLICY IF EXISTS seo_brain_website_links_update ON public.seo_brain_website_links;
DROP POLICY IF EXISTS seo_brain_website_links_insert ON public.seo_brain_website_links;
DROP POLICY IF EXISTS seo_brain_website_links_select ON public.seo_brain_website_links;

DROP TABLE IF EXISTS public.seo_brain_website_links;

DROP FUNCTION IF EXISTS public.seo_brain_website_links_derive();
DROP FUNCTION IF EXISTS public.seo_brain_normalize_host(text);

-- public.set_updated_at, public.seo_role_in, public.is_seo_workspace_member and
-- public.seo_is_global_admin are all pre-existing shared helpers. They are used
-- by the dropped objects but owned by earlier, locked migrations, so they are
-- deliberately left in place.

SELECT 'seo_brain_module_boundary_rollback: COMPLETE' AS result;
