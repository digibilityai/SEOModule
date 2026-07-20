-- =============================================================================
-- SEO Backend — Reports Stage 1 — Migration: Progress Report persistence
-- =============================================================================
-- Additive only. Builds on Stage 1 (seo_workspaces, seo_websites, the
-- is_seo_workspace_member / seo_role_in / seo_is_global_admin helpers and the
-- shared public.set_updated_at() trigger function). Introduces ONE new table,
-- public.seo_reports, the canonical persisted "Progress Report" record that the
-- Reports UI reads.
--
-- SCOPE (Reports Stage 1 — real-data READ foundation only):
--   * Persist a per-website, per-period progress report as canonical scalar
--     columns + a `summary` jsonb payload holding the cross-module rollup.
--   * RLS: read = any workspace member (incl. client); write = owner/admin/
--     team_member (+ global admin) as defense-in-depth.
--   * NO write RPC, NO generation, NO PDF/CSV/export/schedule/email/share, NO
--     storage bucket, NO worker, NO scheduler ship in this migration. Report
--     rows are written by the service role / a future generation stage (or, in
--     TEST, by the read-path verification fixtures). Generation is a later
--     Reports stage.
--
-- Does NOT touch any Stage 1-6, crawler, ownership, or enqueue object. Does not
-- edit any applied migration. Additive new table only.
-- =============================================================================

-- ===========================================================================
-- seo_reports — one canonical progress report per (website, report_type,
-- period). The wide cross-module rollup (score movement, per-area summaries and
-- counts, next_actions) lives in `summary` jsonb so the schema stays stable as
-- upstream modules evolve; the indexed scalar columns carry tenancy, period,
-- status and generation metadata.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  report_type text NOT NULL DEFAULT 'progress'
    CHECK (report_type IN ('progress')),
  period_key text NOT NULL
    CHECK (period_key IN ('current_month', 'last_month', 'last_90_days')),
  period_label text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  title text NOT NULL,
  status text NOT NULL DEFAULT 'generated'
    CHECK (status IN ('not_generated', 'generated', 'stale')),
  -- Cross-module rollup payload (overall_score_*, *_summary, *_count,
  -- next_actions[]). Shape mirrors the frontend ProgressReport read type minus
  -- the scalar columns above. jsonb (not per-field columns) keeps this table
  -- stable as rollup fields change in later stages.
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  generated_at timestamptz,                               -- when the report content was produced; NULL only for a not_generated placeholder
  -- Reserved for a future async-generation stage (queued/running/…); unused in
  -- Stage 1. No behavior keys off these yet.
  generation_status text,
  generation_error text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start),
  -- One canonical report per website + type + period (matches the existing
  -- "replace the snapshot for this website+period" semantics).
  UNIQUE (website_id, report_type, period_key)
);

CREATE INDEX IF NOT EXISTS idx_seo_reports_workspace ON public.seo_reports (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_reports_website ON public.seo_reports (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_reports_website_period ON public.seo_reports (website_id, period_key);
CREATE INDEX IF NOT EXISTS idx_seo_reports_generated_at ON public.seo_reports (generated_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at trigger (shared public.set_updated_at(), same as Stage 1 tables).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_reports_updated_at ON public.seo_reports;
CREATE TRIGGER trg_seo_reports_updated_at BEFORE UPDATE ON public.seo_reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — same pattern as seo_websites / seo_page_performance_snapshots:
--   read  = any workspace member (incl. client) or global admin
--   write = owner/admin/team_member or global admin (defense-in-depth; there is
--           no customer write path in Stage 1, but the policy is gated to the
--           manager set now so a future generation stage cannot accidentally
--           allow a client to write).
-- Table DML is granted to anon/authenticated by Supabase's default privileges;
-- RLS is the authoritative gate. anon has no workspace membership, so the
-- member-only SELECT policy blocks it (verified in the read-path script).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_reports_select ON public.seo_reports;
CREATE POLICY seo_reports_select ON public.seo_reports
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_reports_write ON public.seo_reports;
CREATE POLICY seo_reports_write ON public.seo_reports
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
