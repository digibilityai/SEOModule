-- =============================================================================
-- ROLLBACK: Digi Brain Module Contract v1, Stage 2B machine boundary
--   migrations 20260920120000 + 20260920120100 + 20260920120200 + 20260920120300
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- All four migrations are purely ADDITIVE: they create three new tables, two
-- new trigger functions, one new normalizer, four read functions and six
-- delegated write/status/helper functions, and they alter nothing that already
-- existed. In particular no grant on seo_crawl_request_audit or
-- seo_recommendation_generate was changed: the delegated wrappers run as their
-- own owner precisely so those locked grants stay untouched. Removing them therefore cannot affect any
-- customer table, RLS policy, RPC or row. In particular this script does NOT
-- touch seo_websites, seo_workspaces, seo_workspace_members, seo_audit_runs,
-- seo_audit_issues, seo_recommendations, seo_ownership_verifications, the
-- crawler control plane, or the SSO migration 20260720121000.
--
-- The only data lost is the human-authorized Digi Brain link rows (website and
-- actor) plus the Brain-action correlation index. Those are authorization and
-- correlation records, so re-running the forward migrations leaves empty tables
-- and every machine call resolves to target_not_linked, or unauthorized, until
-- a human re-authorizes each link.
--
-- Crawl jobs, audit runs, findings and recommendations that a delegated call
-- created are NOT removed: they are genuine customer data created through the
-- ordinary, unchanged SEO path, and they remain valid without this boundary.
-- Only the Brain-side correlation for them is dropped. That is the intended fail-closed
-- outcome, not a defect, but it is the reason to check the table is empty (or
-- to export it) before running this on anything but a disposable project.
--
-- Idempotent: every statement uses IF EXISTS and can be re-run safely.
-- =============================================================================

-- Inspect before destroying: how many authorizations are about to be lost.
DO $$
DECLARE
  t text;
  n integer;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'public.seo_brain_website_links',
    'public.seo_brain_actor_links',
    'public.seo_brain_operations'
  ] LOOP
    IF to_regclass(t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM %s', t) INTO n;
      RAISE NOTICE '% rows about to be dropped: %', t, n;
    END IF;
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS public.seo_brain_recommendation_status(text, text, text, text);
DROP FUNCTION IF EXISTS public.seo_brain_generate_recommendations(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.seo_brain_technical_audit_status(text, text, text, text);
DROP FUNCTION IF EXISTS public.seo_brain_request_technical_audit(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.seo_brain_authorize_delegated(text, text, text);
DROP FUNCTION IF EXISTS public.seo_brain_resolve_actor(text);
DROP FUNCTION IF EXISTS public.seo_brain_bootstrap_actor_link(text, uuid, uuid);
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

DROP TRIGGER IF EXISTS trg_seo_brain_operations_updated_at ON public.seo_brain_operations;
DROP POLICY IF EXISTS seo_brain_operations_select ON public.seo_brain_operations;
DROP TABLE IF EXISTS public.seo_brain_operations;

DROP TRIGGER IF EXISTS trg_seo_brain_actor_links_updated_at ON public.seo_brain_actor_links;
DROP TRIGGER IF EXISTS trg_seo_brain_actor_links_guard ON public.seo_brain_actor_links;
DROP POLICY IF EXISTS seo_brain_actor_links_update ON public.seo_brain_actor_links;
DROP POLICY IF EXISTS seo_brain_actor_links_insert ON public.seo_brain_actor_links;
DROP POLICY IF EXISTS seo_brain_actor_links_select ON public.seo_brain_actor_links;
DROP TABLE IF EXISTS public.seo_brain_actor_links;

DROP TABLE IF EXISTS public.seo_brain_website_links;

DROP FUNCTION IF EXISTS public.seo_brain_actor_links_guard();
DROP FUNCTION IF EXISTS public.seo_brain_website_links_derive();
DROP FUNCTION IF EXISTS public.seo_brain_normalize_host(text);

-- public.set_updated_at, public.seo_role_in, public.is_seo_workspace_member and
-- public.seo_is_global_admin are all pre-existing shared helpers. They are used
-- by the dropped objects but owned by earlier, locked migrations, so they are
-- deliberately left in place.

SELECT 'seo_brain_module_boundary_rollback: COMPLETE' AS result;
