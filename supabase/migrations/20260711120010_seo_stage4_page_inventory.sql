-- =============================================================================
-- SEO Backend — Stage 4 (Phase 14A.1) — Migration 10 of 13: Page Inventory
-- =============================================================================
-- Additive only. First table of the Page Performance Tracker module. Builds on
-- Stage 1 (seo_workspaces/seo_websites + helpers). One row per discovered/
-- tracked page on a website — the anchor that Stage 4 keywords (mig 11) and
-- performance snapshots (mig 12) attach to.
--
-- No crawler, no GSC/GA4/CMS calls, no cron job. Rows are written by the
-- service role / system or by owner/admin/team_member via the app, matching
-- the same "no client-side generation" pattern already used for
-- seo_audit_issues / seo_recommendations. Does not touch Stage 1-3 or Core.
-- =============================================================================

-- ===========================================================================
-- seo_page_inventory — one row per discovered/tracked page.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_page_inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  page_url text NOT NULL,
  normalized_page_path text,                               -- e.g. path with trailing slash/query stripped
  page_title text,
  meta_description text,
  page_type text NOT NULL DEFAULT 'other'
    CHECK (page_type IN (
      'homepage', 'service_page', 'blog', 'product_page', 'category_page',
      'location_page', 'landing_page', 'other')),
  indexability_status text NOT NULL DEFAULT 'unknown'
    CHECK (indexability_status IN ('indexable', 'noindex', 'blocked', 'unknown')),
  canonical_url text,
  last_seen_at timestamptz,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  content_status text NOT NULL DEFAULT 'unknown'
    CHECK (content_status IN ('fresh', 'aging', 'stale', 'unknown')),  -- feeds future Decline Diagnosis "freshness_issue"
  priority text CHECK (priority IN ('low', 'medium', 'high')),
  is_tracked boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_workspace ON public.seo_page_inventory (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_website ON public.seo_page_inventory (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_page_url ON public.seo_page_inventory (page_url);
CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_active ON public.seo_page_inventory (website_id, is_active);
CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_tracked ON public.seo_page_inventory (website_id, is_tracked);
CREATE INDEX IF NOT EXISTS idx_seo_page_inventory_type ON public.seo_page_inventory (page_type);

-- Prevents duplicate ACTIVE page rows per website + URL (a page can be
-- re-added after being archived, which is a fresh row, not a conflict).
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_page_inventory_active_url
  ON public.seo_page_inventory (website_id, page_url) WHERE is_active;

-- ---------------------------------------------------------------------------
-- updated_at trigger — reuses Stage 1 public.set_updated_at().
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_page_inventory_updated_at ON public.seo_page_inventory;
CREATE TRIGGER trg_seo_page_inventory_updated_at BEFORE UPDATE ON public.seo_page_inventory
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: any active workspace member (incl. client) + global admin.
-- Write: owner/admin/team_member + global admin only (system/service-layer
-- generated inventory, same pattern as seo_audit_issues). Clients never
-- insert/update/delete page inventory.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_page_inventory ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_page_inventory_select ON public.seo_page_inventory;
CREATE POLICY seo_page_inventory_select ON public.seo_page_inventory
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_page_inventory_write ON public.seo_page_inventory;
CREATE POLICY seo_page_inventory_write ON public.seo_page_inventory
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
