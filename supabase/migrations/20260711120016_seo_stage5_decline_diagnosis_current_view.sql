-- =============================================================================
-- SEO Backend — Stage 5 (Phase 14B.1) — Migration 16 of 16: Current View + RPC
-- =============================================================================
-- Additive only. Builds on migrations 14 (seo_decline_diagnoses) + 15
-- (seo_decline_diagnosis_evidence) and Stage 4's seo_page_inventory +
-- seo_page_performance_latest. Two safe read/write helpers:
--
--   1. seo_decline_diagnoses_current — read-only VIEW of still-live diagnoses
--      joined to page context and the latest Stage 4 performance row, for the
--      common "show me open diagnoses for this website" UI read.
--
--   2. seo_create_decline_diagnosis_from_snapshot(...) — a deterministic,
--      no-heuristic RPC that snapshots page/keyword/url/movement from one
--      Stage 4 performance snapshot, inserts a diagnosis the CALLER has
--      already classified, and auto-derives evidence rows by COPYING that
--      snapshot's already-stored metrics. It invents nothing: no LLM, no
--      crawler, no external API, no "which cause is it" guessing in SQL.
--
-- Does not touch Stage 1-4 or Core.
-- =============================================================================

-- ===========================================================================
-- seo_decline_diagnoses_current — live diagnoses + page + latest-performance
-- context. Not SECURITY DEFINER. Uses security_invoker = true (Postgres 15+,
-- same pattern as Stage 4's seo_page_performance_latest) so it is evaluated
-- with the QUERYING user's own privileges and inherits the underlying tables'
-- RLS exactly — a member sees only their workspace(s), a non-member sees
-- nothing, no bypass, no duplicated policy logic.
--
-- "Current" = the still-live lifecycle states (open / in_review /
-- action_planned); resolved and dismissed diagnoses are intentionally
-- excluded. The latest-performance join is a LEFT JOIN keyed on
-- page_id + page_keyword_id (IS NOT DISTINCT FROM handles the page-level
-- NULL-keyword case and matches exactly one latest row per diagnosis, so the
-- view never fans a diagnosis out into duplicate rows).
-- ===========================================================================
CREATE OR REPLACE VIEW public.seo_decline_diagnoses_current
WITH (security_invoker = true)
AS
SELECT
  d.id,
  d.workspace_id,
  d.website_id,
  d.website_url,
  d.page_id,
  d.page_url,
  d.page_keyword_id,
  d.keyword,
  d.performance_snapshot_id,
  d.diagnosis_type,
  d.severity,
  d.confidence_percentage,
  d.movement_status,
  d.business_summary,
  d.likely_cause,
  d.technical_explanation,
  d.recommended_next_action,
  d.suggested_owner,
  d.priority,
  d.status,
  d.linked_recommendation_id,
  d.created_by,
  d.created_at,
  d.updated_at,
  -- Page context (from Stage 4 page inventory).
  p.page_title,
  p.page_type,
  p.content_status,
  p.indexability_status,
  -- Latest Stage 4 performance context for this page (+ keyword when set).
  l.snapshot_date          AS latest_snapshot_date,
  l.clicks                 AS latest_clicks,
  l.impressions            AS latest_impressions,
  l.ctr                    AS latest_ctr,
  l.average_position       AS latest_average_position,
  l.movement_status        AS latest_movement_status
FROM public.seo_decline_diagnoses d
LEFT JOIN public.seo_page_inventory p
  ON p.id = d.page_id
LEFT JOIN public.seo_page_performance_latest l
  ON l.page_id = d.page_id
 AND l.page_keyword_id IS NOT DISTINCT FROM d.page_keyword_id
WHERE d.status IN ('open', 'in_review', 'action_planned');

-- Views need their own grant even when the underlying tables already grant to
-- `authenticated` — RLS (via security_invoker) still applies per-row on top of
-- this statement-level grant, so this does not widen access.
GRANT SELECT ON public.seo_decline_diagnoses_current TO authenticated;

-- ===========================================================================
-- seo_create_decline_diagnosis_from_snapshot — safe, deterministic creation.
--
-- Given ONE Stage 4 performance snapshot and a caller-decided classification,
-- this:
--   * resolves workspace/website/page/keyword/url/movement FROM the snapshot
--     (non-forgeable — the caller cannot point a diagnosis at a snapshot in a
--     workspace they don't manage),
--   * enforces owner/admin/team_member (or global admin) on THAT snapshot's
--     workspace, raising otherwise — so although EXECUTE is granted to
--     `authenticated`, a client role can never actually create a diagnosis,
--   * inserts the diagnosis (created_by = auth.uid()),
--   * auto-derives evidence rows by copying the snapshot's already-stored
--     current/previous/delta metrics (clicks, impressions, ctr, average
--     position) — only where a previous value exists, so every evidence row
--     shows a real movement.
--
-- SECURITY DEFINER (same pattern as Stage 2's seo_supersede_recommendation) so
-- the snapshot read + inserts run regardless of the caller's own RLS
-- visibility, AFTER the explicit role check. It calls NO external API, NO LLM,
-- and applies NO diagnosis heuristics — classification is entirely the
-- caller's input. Returns the new diagnosis id.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_create_decline_diagnosis_from_snapshot(
  p_snapshot_id uuid,
  p_diagnosis_type text,
  p_severity text,
  p_priority text,
  p_suggested_owner text,
  p_business_summary text,
  p_likely_cause text,
  p_recommended_next_action text,
  p_confidence_percentage integer DEFAULT NULL,
  p_technical_explanation text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s public.seo_page_performance_snapshots%ROWTYPE;
  v_diag_id uuid;
BEGIN
  SELECT * INTO s FROM public.seo_page_performance_snapshots WHERE id = p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Performance snapshot % does not exist', p_snapshot_id;
  END IF;

  -- Permission: manage-level role in the snapshot's own workspace, or global
  -- admin. Clients (and non-members) are rejected here even though EXECUTE is
  -- granted broadly to authenticated.
  IF NOT (
    public.seo_role_in(s.workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) THEN
    RAISE EXCEPTION 'Not permitted to create a decline diagnosis in this workspace';
  END IF;

  INSERT INTO public.seo_decline_diagnoses (
    workspace_id, website_id, website_url, page_id, page_url,
    page_keyword_id, keyword, performance_snapshot_id,
    diagnosis_type, severity, confidence_percentage, movement_status,
    business_summary, likely_cause, technical_explanation,
    recommended_next_action, suggested_owner, priority, created_by
  ) VALUES (
    s.workspace_id, s.website_id, s.website_url, s.page_id, s.page_url,
    s.page_keyword_id, s.keyword, s.id,
    p_diagnosis_type, p_severity, p_confidence_percentage, s.movement_status,
    p_business_summary, p_likely_cause, p_technical_explanation,
    p_recommended_next_action, p_suggested_owner, p_priority, auth.uid()
  )
  RETURNING id INTO v_diag_id;

  -- Deterministic evidence from stored Stage 4 metrics. One row per metric
  -- that has a previous value to compare against. delta = stored *_delta when
  -- present, else current - previous. ON CONFLICT guards re-runs.
  IF s.previous_clicks IS NOT NULL THEN
    INSERT INTO public.seo_decline_diagnosis_evidence (
      workspace_id, website_id, website_url, diagnosis_id, evidence_type,
      metric_name, current_value, previous_value, delta_value, evidence_summary,
      source, created_by)
    VALUES (
      s.workspace_id, s.website_id, s.website_url, v_diag_id, 'traffic',
      'clicks', s.clicks::text, s.previous_clicks::text,
      COALESCE(s.clicks_delta, s.clicks - s.previous_clicks)::text,
      format('Clicks moved from %s to %s.', s.previous_clicks, s.clicks),
      'performance_snapshot', auth.uid())
    ON CONFLICT (diagnosis_id, evidence_type, metric_name) DO NOTHING;
  END IF;

  IF s.previous_impressions IS NOT NULL THEN
    INSERT INTO public.seo_decline_diagnosis_evidence (
      workspace_id, website_id, website_url, diagnosis_id, evidence_type,
      metric_name, current_value, previous_value, delta_value, evidence_summary,
      source, created_by)
    VALUES (
      s.workspace_id, s.website_id, s.website_url, v_diag_id, 'impressions',
      'impressions', s.impressions::text, s.previous_impressions::text,
      COALESCE(s.impressions_delta, s.impressions - s.previous_impressions)::text,
      format('Impressions moved from %s to %s.', s.previous_impressions, s.impressions),
      'performance_snapshot', auth.uid())
    ON CONFLICT (diagnosis_id, evidence_type, metric_name) DO NOTHING;
  END IF;

  IF s.previous_ctr IS NOT NULL AND s.ctr IS NOT NULL THEN
    INSERT INTO public.seo_decline_diagnosis_evidence (
      workspace_id, website_id, website_url, diagnosis_id, evidence_type,
      metric_name, current_value, previous_value, delta_value, evidence_summary,
      source, created_by)
    VALUES (
      s.workspace_id, s.website_id, s.website_url, v_diag_id, 'ctr',
      'ctr', s.ctr::text, s.previous_ctr::text,
      COALESCE(s.ctr_delta, s.ctr - s.previous_ctr)::text,
      format('Click-through rate moved from %s to %s.', s.previous_ctr, s.ctr),
      'performance_snapshot', auth.uid())
    ON CONFLICT (diagnosis_id, evidence_type, metric_name) DO NOTHING;
  END IF;

  IF s.previous_average_position IS NOT NULL AND s.average_position IS NOT NULL THEN
    INSERT INTO public.seo_decline_diagnosis_evidence (
      workspace_id, website_id, website_url, diagnosis_id, evidence_type,
      metric_name, current_value, previous_value, delta_value, evidence_summary,
      source, created_by)
    VALUES (
      s.workspace_id, s.website_id, s.website_url, v_diag_id, 'ranking',
      'average_position', s.average_position::text, s.previous_average_position::text,
      COALESCE(s.position_delta, s.average_position - s.previous_average_position)::text,
      format('Average position moved from %s to %s.', s.previous_average_position, s.average_position),
      'performance_snapshot', auth.uid())
    ON CONFLICT (diagnosis_id, evidence_type, metric_name) DO NOTHING;
  END IF;

  RETURN v_diag_id;
END;
$$;

-- Manager-only is enforced INSIDE the function; the grant just lets the app's
-- authenticated role attempt the call (clients are rejected at the role check).
GRANT EXECUTE ON FUNCTION public.seo_create_decline_diagnosis_from_snapshot(
  uuid, text, text, text, text, text, text, text, integer, text
) TO authenticated;
