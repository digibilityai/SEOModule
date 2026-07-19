-- =============================================================================
-- SEO Backend — Stage 5 (Phase 14B.1) — Migration 14 of 16: Decline Diagnoses
-- =============================================================================
-- Additive only. First table of the Decline Diagnosis Engine. Builds on Stage 1
-- (seo_workspaces/seo_websites + helpers), Stage 2 (seo_recommendations), and
-- Stage 4 (seo_page_inventory / seo_page_keywords / seo_page_performance_snapshots).
--
-- One diagnosis record explains WHY a tracked page (optionally a specific
-- page+keyword, optionally anchored to one performance snapshot) may be losing
-- ranking/traffic — business-friendly explanation first, technical detail
-- second, plus a recommended next action and a suggested owner. It reads
-- Stage 4 performance data as its evidence source (see migration 15 for the
-- structured evidence rows and migration 16 for the current-view + safe
-- insert RPC).
--
-- This migration does NOT run a crawler, does NOT call GSC/GA4 or any external
-- API, does NOT call an LLM, and does NOT create a cron job. It ships NO
-- diagnosis heuristics — "which cause applies" is decided by the writer
-- (service layer / manual seed / a future engine), not by SQL here. Rows are
-- written by the service role / system or by owner/admin/team_member via the
-- app, matching the same "no client-side generation" pattern already used for
-- seo_audit_issues / seo_recommendations / seo_page_performance_snapshots.
-- Does not touch Stage 1-4 or Core.
-- =============================================================================

-- ===========================================================================
-- seo_decline_diagnoses — one diagnosis per page / page+keyword / snapshot.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_decline_diagnoses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  page_id uuid NOT NULL REFERENCES public.seo_page_inventory(id) ON DELETE CASCADE,
  page_url text NOT NULL,                                 -- snapshot of the page's URL
  -- Optional keyword focus. NULL = a page-level diagnosis (not tied to one
  -- keyword). ON DELETE SET NULL: losing the keyword row must not delete the
  -- diagnosis (keyword text is snapshotted below), just detach the link.
  page_keyword_id uuid REFERENCES public.seo_page_keywords(id) ON DELETE SET NULL,
  keyword text,                                           -- snapshot of the keyword text; NULL = page-level
  -- Optional anchor to the exact Stage 4 snapshot the evidence came from.
  -- ON DELETE SET NULL for the same reason (metrics are snapshotted into
  -- seo_decline_diagnosis_evidence, migration 15).
  performance_snapshot_id uuid REFERENCES public.seo_page_performance_snapshots(id) ON DELETE SET NULL,
  diagnosis_type text NOT NULL CHECK (diagnosis_type IN (
    'ctr_drop', 'ranking_decline', 'clicks_decline', 'impressions_decline',
    'content_freshness', 'indexing_issue', 'cannibalization_risk',
    'intent_mismatch', 'competitor_improvement', 'technical_performance',
    'no_data', 'mixed_signals')),
  severity text NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  -- Nullable per the Stage 5 field spec: a diagnosis may be recorded before a
  -- confidence is scored (e.g. an early manual/system note). Range-checked
  -- only when present.
  confidence_percentage integer
    CHECK (confidence_percentage IS NULL OR confidence_percentage BETWEEN 0 AND 100),
  -- Optional snapshot of the Stage 4 movement_status that triggered this
  -- diagnosis. Same allowed set as seo_page_performance_snapshots.movement_status.
  movement_status text
    CHECK (movement_status IS NULL OR movement_status IN (
      'improving', 'stable', 'declining', 'new', 'no_data')),
  business_summary text NOT NULL,                         -- plain-language "what changed / why it matters"
  likely_cause text NOT NULL,                             -- plain-language "our best explanation"
  technical_explanation text,                             -- optional deeper detail for developers/experts
  recommended_next_action text NOT NULL,                  -- the single next step to take
  suggested_owner text NOT NULL CHECK (suggested_owner IN (
    'client_action', 'developer_needed', 'digibility_expert', 'system_suggestion')),
  priority text NOT NULL DEFAULT 'medium'
    CHECK (priority IN ('low', 'medium', 'high')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN (
    'open', 'in_review', 'action_planned', 'resolved', 'dismissed')),
  -- Optional forward-link to a recommendation this diagnosis was converted
  -- into. The conversion flow itself is NOT built in Stage 5 — this is only a
  -- nullable seam. ON DELETE SET NULL so retiring a recommendation never
  -- deletes diagnosis history.
  linked_recommendation_id uuid REFERENCES public.seo_recommendations(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_workspace ON public.seo_decline_diagnoses (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_website ON public.seo_decline_diagnoses (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_page ON public.seo_decline_diagnoses (page_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_keyword ON public.seo_decline_diagnoses (page_keyword_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_snapshot ON public.seo_decline_diagnoses (performance_snapshot_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_recommendation ON public.seo_decline_diagnoses (linked_recommendation_id);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_type ON public.seo_decline_diagnoses (diagnosis_type);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_severity ON public.seo_decline_diagnoses (severity);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_status ON public.seo_decline_diagnoses (status);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_priority ON public.seo_decline_diagnoses (priority);
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_created ON public.seo_decline_diagnoses (created_at DESC);
-- Fast "open diagnoses for this website" listing (the common UI read).
CREATE INDEX IF NOT EXISTS idx_seo_decline_diag_website_status
  ON public.seo_decline_diagnoses (website_id, status);

-- Prevents duplicate ACTIVE diagnoses of the same type for the same page (or
-- page+keyword) anchored to the same snapshot. "Active" = still-live lifecycle
-- states; a resolved/dismissed diagnosis never blocks recording a fresh one.
-- page_keyword_id and performance_snapshot_id are nullable, so COALESCE each
-- to a fixed nil sentinel — otherwise a plain unique index would treat every
-- NULL as distinct and silently allow duplicate page-level diagnoses.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_decline_diag_active_combo
  ON public.seo_decline_diagnoses (
    page_id,
    COALESCE(page_keyword_id, '00000000-0000-0000-0000-000000000000'::uuid),
    diagnosis_type,
    COALESCE(performance_snapshot_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  WHERE status IN ('open', 'in_review', 'action_planned');

-- ---------------------------------------------------------------------------
-- updated_at trigger — reuses Stage 1 public.set_updated_at().
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_decline_diagnoses_updated_at ON public.seo_decline_diagnoses;
CREATE TRIGGER trg_seo_decline_diagnoses_updated_at BEFORE UPDATE ON public.seo_decline_diagnoses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: any active workspace member (incl. client) + global admin.
-- Write: owner/admin/team_member + global admin only. Clients never insert/
-- update/delete diagnoses (they consume them read-only, exactly like
-- seo_recommendations / seo_page_performance_snapshots). Service role bypasses
-- RLS for system generation.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_decline_diagnoses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_decline_diagnoses_select ON public.seo_decline_diagnoses;
CREATE POLICY seo_decline_diagnoses_select ON public.seo_decline_diagnoses
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_decline_diagnoses_write ON public.seo_decline_diagnoses;
CREATE POLICY seo_decline_diagnoses_write ON public.seo_decline_diagnoses
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
