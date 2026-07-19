-- =============================================================================
-- SEO Backend — Stage 5 (Phase 14B.1) — Migration 15 of 16: Diagnosis Evidence
-- =============================================================================
-- Additive only. Builds on migration 14 (seo_decline_diagnoses). Structured
-- "why we think this happened" rows behind a diagnosis, so the UI can show the
-- supporting metric movements (traffic/ranking/CTR/impressions/etc.) as plain
-- evidence lines instead of burying them in prose.
--
-- Values are stored as text (current_value / previous_value / delta_value) on
-- purpose: evidence spans mixed metric kinds (integer clicks, fractional CTR,
-- decimal average position, and future qualitative notes), and this table is
-- display-oriented, not an analytics store — the numeric source of truth stays
-- in Stage 4's seo_page_performance_snapshots. No crawler, no external API, no
-- LLM, no cron. Rows are written by the service role / system or by owner/
-- admin/team_member via the app. Does not touch Stage 1-4 or Core.
-- =============================================================================

-- ===========================================================================
-- seo_decline_diagnosis_evidence — one supporting evidence line per diagnosis.
-- Deleting a diagnosis cascades its evidence away (evidence has no meaning on
-- its own).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_decline_diagnosis_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  diagnosis_id uuid NOT NULL REFERENCES public.seo_decline_diagnoses(id) ON DELETE CASCADE,
  evidence_type text NOT NULL CHECK (evidence_type IN (
    'traffic', 'ranking', 'ctr', 'impressions', 'content', 'technical',
    'indexability', 'competitor', 'query_intent', 'system_note')),
  metric_name text NOT NULL,                              -- e.g. 'clicks', 'average_position', 'ctr'
  current_value text,                                     -- text: mixed metric kinds (see file header)
  previous_value text,
  delta_value text,
  evidence_summary text NOT NULL,                         -- plain-language one-liner for this evidence row
  source text NOT NULL DEFAULT 'performance_snapshot' CHECK (source IN (
    'performance_snapshot', 'page_inventory', 'audit_issue',
    'recommendation', 'manual_seed', 'system')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_seo_decline_evidence_workspace ON public.seo_decline_diagnosis_evidence (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_evidence_website ON public.seo_decline_diagnosis_evidence (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_evidence_diagnosis ON public.seo_decline_diagnosis_evidence (diagnosis_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_evidence_type ON public.seo_decline_diagnosis_evidence (evidence_type);
CREATE INDEX IF NOT EXISTS idx_seo_decline_evidence_source ON public.seo_decline_diagnosis_evidence (source);

-- Prevents duplicate evidence lines for the same metric within one diagnosis
-- (e.g. two 'clicks' rows). metric_name is never NULL, so a plain unique index
-- is sufficient here.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_decline_evidence_metric
  ON public.seo_decline_diagnosis_evidence (diagnosis_id, evidence_type, metric_name);

-- No updated_at column/trigger: evidence rows are immutable point-in-time
-- captures (a correction is a new row / a re-generated evidence set, not an
-- edit), same rationale as seo_page_performance_snapshots in Stage 4.

-- ---------------------------------------------------------------------------
-- RLS — mirrors seo_decline_diagnoses exactly. Read: any active workspace
-- member (incl. client) + global admin. Write: owner/admin/team_member +
-- global admin only. Clients never insert/update/delete evidence.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_decline_diagnosis_evidence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_decline_diagnosis_evidence_select ON public.seo_decline_diagnosis_evidence;
CREATE POLICY seo_decline_diagnosis_evidence_select ON public.seo_decline_diagnosis_evidence
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_decline_diagnosis_evidence_write ON public.seo_decline_diagnosis_evidence;
CREATE POLICY seo_decline_diagnosis_evidence_write ON public.seo_decline_diagnosis_evidence
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
