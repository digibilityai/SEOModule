-- =============================================================================
-- SEO Backend — Reports Stage 3 (PDF export) — Migration: export-data RPC
-- =============================================================================
-- Additive only. Builds on Reports Stage 1 (`public.seo_reports`) and Stage 2
-- (`seo_report_generate`). Introduces ONE read-only guarded RPC that returns the
-- already-persisted canonical report row for a website+period to authorized
-- exporters. The PDF itself is rendered client-side from this row — there is no
-- BFF/edge-function in this architecture (SEO_DECISIONS A1); this RPC is the
-- server-side authorization boundary for the export ACTION.
--
-- SCOPE (Reports Stage 3 — export authorization only):
--   * `STABLE` `SECURITY DEFINER` read-only function; NEVER regenerates or
--     recomputes a report (no INSERT/UPDATE/DELETE anywhere).
--   * Same authorization model as Stage 2 generation: authenticated; workspace
--     derived from the website server-side; owner/admin/team_member (or global
--     admin) only; **client / anon / nonmember / cross-tenant denied** with one
--     non-leaking error (missing website === role-denied).
--   * Returns 0 or 1 `seo_reports` row (the canonical stored report). No
--     client-supplied content is trusted; the row comes straight from the table.
--   * NO CSV/email/schedule/share, NO new metrics, NO worker, NO production.
--
-- Note: Stage 1 RLS already lets any workspace member (incl. client) READ a
-- report; this RPC intentionally restricts the EXPORT action to the manager set
-- (owner/admin/team_member), mirroring who may generate — a workflow control,
-- server-enforced, so a client-role EXPORT is denied even though a client may
-- still view on-screen.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.seo_report_export_data(
  p_website_id uuid,
  p_period_key text
) RETURNS SETOF public.seo_reports
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required to export a report.';
  END IF;

  SELECT w.workspace_id INTO v_ws FROM public.seo_websites w WHERE w.id = p_website_id;

  IF v_ws IS NULL
     OR NOT (public.seo_role_in(v_ws, ARRAY['owner','admin','team_member'])
             OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not authorized to export a report for this website.';
  END IF;

  IF p_period_key NOT IN ('current_month','last_month','last_90_days') THEN
    RAISE EXCEPTION 'Unsupported report period: %', p_period_key;
  END IF;

  RETURN QUERY
    SELECT r.*
    FROM public.seo_reports r
    WHERE r.website_id = p_website_id
      AND r.report_type = 'progress'
      AND r.period_key = p_period_key;
END;
$$;

-- Grants: authenticated-only (in-function role gate is authoritative);
-- anon/PUBLIC denied explicitly (Supabase default-privileges grant anon).
REVOKE ALL ON FUNCTION public.seo_report_export_data(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_report_export_data(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_report_export_data(uuid, text) TO authenticated;
