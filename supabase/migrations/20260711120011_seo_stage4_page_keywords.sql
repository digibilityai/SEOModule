-- =============================================================================
-- SEO Backend — Stage 4 (Phase 14A.1) — Migration 11 of 13: Page Keywords
-- =============================================================================
-- Additive only. Builds on Stage 1 + mig 10 (seo_page_inventory). Keywords
-- mapped/tracked against a specific page — the join point that performance
-- snapshots (mig 12) attach to when a snapshot is keyword-specific rather
-- than a page-level aggregate.
--
-- No crawler, no rank-tracking API calls, no cron job. Rows are written by
-- the service role / system or by owner/admin/team_member via the app.
-- Does not touch Stage 1-3 or Core.
-- =============================================================================

-- ===========================================================================
-- seo_page_keywords — keywords mapped/tracked against a page.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_page_keywords (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  page_id uuid NOT NULL REFERENCES public.seo_page_inventory(id) ON DELETE CASCADE,
  page_url text NOT NULL,                                 -- snapshot of the page's URL at mapping time
  keyword text NOT NULL,
  keyword_type text NOT NULL DEFAULT 'secondary'
    CHECK (keyword_type IN ('primary', 'secondary', 'semantic', 'question', 'branded', 'local')),
  search_intent text
    CHECK (search_intent IN ('informational', 'navigational', 'transactional', 'commercial')),
  target_location text,
  device text NOT NULL DEFAULT 'all'
    CHECK (device IN ('desktop', 'mobile', 'all')),
  search_engine text NOT NULL DEFAULT 'google'
    CHECK (search_engine IN ('google', 'bing', 'ai_overview', 'other')),
  priority text CHECK (priority IN ('low', 'medium', 'high')),
  is_primary boolean NOT NULL DEFAULT false,
  is_tracked boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_page_keywords_workspace ON public.seo_page_keywords (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_keywords_website ON public.seo_page_keywords (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_keywords_page ON public.seo_page_keywords (page_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_keywords_keyword ON public.seo_page_keywords (keyword);
CREATE INDEX IF NOT EXISTS idx_seo_page_keywords_primary ON public.seo_page_keywords (page_id, is_primary);
CREATE INDEX IF NOT EXISTS idx_seo_page_keywords_tracked ON public.seo_page_keywords (page_id, is_tracked);

-- Prevents duplicate TRACKED keyword mappings for the same page + keyword +
-- location + device + search engine. target_location is nullable (no
-- location targeting yet); COALESCE to '' so two rows both lacking a target
-- location are still treated as the same combination for uniqueness (a plain
-- unique index would otherwise treat every NULL as distinct and allow silent
-- duplicates).
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_page_keywords_tracked_combo
  ON public.seo_page_keywords (page_id, keyword, COALESCE(target_location, ''), device, search_engine)
  WHERE is_tracked;

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_page_keywords_updated_at ON public.seo_page_keywords;
CREATE TRIGGER trg_seo_page_keywords_updated_at BEFORE UPDATE ON public.seo_page_keywords
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — same pattern as seo_page_inventory: read = any member, write =
-- owner/admin/team_member + global admin only. Clients never insert/update/
-- delete keyword mappings.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_page_keywords ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_page_keywords_select ON public.seo_page_keywords;
CREATE POLICY seo_page_keywords_select ON public.seo_page_keywords
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_page_keywords_write ON public.seo_page_keywords;
CREATE POLICY seo_page_keywords_write ON public.seo_page_keywords
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
