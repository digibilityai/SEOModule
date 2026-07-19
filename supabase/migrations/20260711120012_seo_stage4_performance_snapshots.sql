-- =============================================================================
-- SEO Backend — Stage 4 (Phase 14A.1) — Migration 12 of 13: Performance Snapshots
-- =============================================================================
-- Additive only. Builds on Stage 1 + mig 10 (seo_page_inventory) + mig 11
-- (seo_page_keywords). Periodic performance data (clicks/impressions/CTR/
-- average position + period-over-period deltas) for a page, or for a specific
-- page+keyword combination. `movement_status` and `diagnosis_hint` are
-- simple, diagnosis-ready fields for a future Decline Diagnosis module — no
-- diagnosis logic ships in Stage 4.
--
-- `source` records where a row's numbers came from (manual_seed for now;
-- gsc/ga4/import are placeholders for a future real integration). This
-- migration does NOT call any external API, does NOT create a cron job, and
-- does NOT implement real GSC/GA4 import — those are explicitly out of scope
-- for Phase 14A.1. Rows are written by the service role / system or by
-- owner/admin/team_member via the app. Does not touch Stage 1-3 or Core.
-- =============================================================================

-- ===========================================================================
-- seo_page_performance_snapshots — one row per page (or page+keyword) per
-- reporting period per data source. Immutable point-in-time record — no
-- updated_at column/trigger (matches the "periodic snapshot" nature; a
-- correction is a new snapshot row, not an edit of history).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_page_performance_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  page_id uuid NOT NULL REFERENCES public.seo_page_inventory(id) ON DELETE CASCADE,
  page_keyword_id uuid REFERENCES public.seo_page_keywords(id) ON DELETE CASCADE,
  page_url text NOT NULL,                                 -- snapshot of the page's URL
  keyword text,                                           -- snapshot of the keyword text; NULL = page-level aggregate row
  snapshot_date date NOT NULL DEFAULT current_date,
  period_start date NOT NULL,
  period_end date NOT NULL,
  source text NOT NULL DEFAULT 'manual_seed'
    CHECK (source IN ('manual_seed', 'gsc', 'ga4', 'system', 'import')),
  clicks integer NOT NULL DEFAULT 0 CHECK (clicks >= 0),
  impressions integer NOT NULL DEFAULT 0 CHECK (impressions >= 0),
  ctr numeric CHECK (ctr IS NULL OR (ctr >= 0 AND ctr <= 1)),
  average_position numeric CHECK (average_position IS NULL OR average_position > 0),
  previous_clicks integer CHECK (previous_clicks IS NULL OR previous_clicks >= 0),
  previous_impressions integer CHECK (previous_impressions IS NULL OR previous_impressions >= 0),
  previous_ctr numeric CHECK (previous_ctr IS NULL OR (previous_ctr >= 0 AND previous_ctr <= 1)),
  previous_average_position numeric CHECK (previous_average_position IS NULL OR previous_average_position > 0),
  clicks_delta integer,
  impressions_delta integer,
  ctr_delta numeric,
  position_delta numeric,
  movement_status text NOT NULL DEFAULT 'no_data'
    CHECK (movement_status IN ('improving', 'stable', 'declining', 'new', 'no_data')),
  diagnosis_hint text,                                    -- free-text seam for future Decline Diagnosis; no logic here
  imported_at timestamptz,                                -- when a future real GSC/GA4 import wrote this row
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start)
);

CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_workspace ON public.seo_page_performance_snapshots (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_website ON public.seo_page_performance_snapshots (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_page ON public.seo_page_performance_snapshots (page_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_keyword ON public.seo_page_performance_snapshots (page_keyword_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_date ON public.seo_page_performance_snapshots (snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_movement ON public.seo_page_performance_snapshots (movement_status);
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_source ON public.seo_page_performance_snapshots (source);
-- Fast "latest snapshot per page" lookups (used by mig 13's summary view).
CREATE INDEX IF NOT EXISTS idx_seo_page_perf_snap_page_latest
  ON public.seo_page_performance_snapshots (page_id, snapshot_date DESC);

-- Prevents duplicate snapshots for the same page (or page+keyword) on the
-- same date from the same source. page_keyword_id is nullable (NULL = a
-- page-level aggregate row); COALESCE to a fixed nil sentinel so two NULL
-- rows for the same page/date/source are still treated as the same
-- combination for uniqueness (a plain unique index would otherwise treat
-- every NULL as distinct and allow silent duplicate page-level rows).
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_page_perf_snap_combo
  ON public.seo_page_performance_snapshots (
    page_id,
    COALESCE(page_keyword_id, '00000000-0000-0000-0000-000000000000'::uuid),
    snapshot_date,
    source
  );

-- ---------------------------------------------------------------------------
-- RLS — same pattern as mig 10/11: read = any member (incl. client), write =
-- owner/admin/team_member + global admin only. Clients never insert/update/
-- delete performance snapshots. No updated_at trigger (see table comment
-- above — snapshots are immutable; only INSERT is expected in practice, but
-- UPDATE is still policy-gated to the manager set as defense-in-depth).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_page_performance_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_page_performance_snapshots_select ON public.seo_page_performance_snapshots;
CREATE POLICY seo_page_performance_snapshots_select ON public.seo_page_performance_snapshots
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_page_performance_snapshots_write ON public.seo_page_performance_snapshots;
CREATE POLICY seo_page_performance_snapshots_write ON public.seo_page_performance_snapshots
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
