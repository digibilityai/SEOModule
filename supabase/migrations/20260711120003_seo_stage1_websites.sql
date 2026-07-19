-- =============================================================================
-- SEO Backend — Stage 1 (Phase 12C) — Migration 3 of 3: Website foundation
-- =============================================================================
-- Additive only. seo_websites is the anchor every later SEO record links to.
-- website_id is the source of truth; website_url is stored as a snapshot on
-- child records so historical context survives a URL change.
-- Depends on migrations 1 & 2 (plan limits, workspaces, membership helpers,
-- seo_usage_events).
-- =============================================================================

-- ===========================================================================
-- seo_websites — the "website URL" anchor entity.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_websites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  website_name text NOT NULL,
  business_name text NOT NULL,
  industry text,
  target_location text,
  website_type text NOT NULL DEFAULT 'other'
    CHECK (website_type IN ('service', 'local_business', 'ecommerce', 'content', 'saas', 'other')),
  plan_snapshot text,                                   -- plan tier at creation (optional)
  setup_status text NOT NULL DEFAULT 'pending'
    CHECK (setup_status IN ('not_connected', 'pending', 'connected', 'error')),
  is_high_risk_industry boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, website_url)
);
CREATE INDEX IF NOT EXISTS idx_seo_websites_workspace ON public.seo_websites (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_websites_url ON public.seo_websites (website_url);
CREATE INDEX IF NOT EXISTS idx_seo_websites_active ON public.seo_websites (workspace_id, is_active);

-- Forward-reference FK from migration 1 (seo_usage_events.website_id).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seo_usage_events_website_fk') THEN
    ALTER TABLE public.seo_usage_events
      ADD CONSTRAINT seo_usage_events_website_fk
      FOREIGN KEY (website_id) REFERENCES public.seo_websites(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ===========================================================================
-- seo_business_onboarding — business context per website (1:1).
-- website_url stored as snapshot per decision (website_id = source of truth).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_business_onboarding (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                             -- snapshot
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  services_products text,
  target_audience text,
  main_seo_goal text,
  target_locations text[] NOT NULL DEFAULT '{}',
  competitors text[] NOT NULL DEFAULT '{}',
  proof_trust_signals text,
  important_pages text[] NOT NULL DEFAULT '{}',
  preferred_content_tone text,
  sensitive_industry text NOT NULL DEFAULT 'none',
  notes text,
  onboarding_status text NOT NULL DEFAULT 'not_started'
    CHECK (onboarding_status IN ('not_started', 'in_progress', 'completed')),
  completion_percentage integer NOT NULL DEFAULT 0
    CHECK (completion_percentage BETWEEN 0 AND 100),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (website_id)
);
CREATE INDEX IF NOT EXISTS idx_seo_onboarding_workspace ON public.seo_business_onboarding (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_onboarding_website ON public.seo_business_onboarding (website_id);

-- ===========================================================================
-- seo_connection_status — integration/connection placeholders per website (1:1).
-- No real GSC/GA4/CMS/GBP integration yet — status fields only.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_connection_status (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                             -- snapshot
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_reachable text NOT NULL DEFAULT 'pending'
    CHECK (website_reachable IN ('not_connected', 'pending', 'connected', 'error')),
  sitemap_status text NOT NULL DEFAULT 'not_connected'
    CHECK (sitemap_status IN ('not_connected', 'pending', 'connected', 'error')),
  robots_status text NOT NULL DEFAULT 'not_connected'
    CHECK (robots_status IN ('not_connected', 'pending', 'connected', 'error')),
  gsc_status text NOT NULL DEFAULT 'not_connected'
    CHECK (gsc_status IN ('not_connected', 'pending', 'connected', 'error')),
  ga4_status text NOT NULL DEFAULT 'not_connected'
    CHECK (ga4_status IN ('not_connected', 'pending', 'connected', 'error')),
  cms_status text NOT NULL DEFAULT 'not_connected'
    CHECK (cms_status IN ('not_connected', 'pending', 'connected', 'error')),
  gbp_status text NOT NULL DEFAULT 'not_connected'
    CHECK (gbp_status IN ('not_connected', 'pending', 'connected', 'error')),
  last_checked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (website_id)
);
CREATE INDEX IF NOT EXISTS idx_seo_connection_workspace ON public.seo_connection_status (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_connection_website ON public.seo_connection_status (website_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_websites_updated_at ON public.seo_websites;
CREATE TRIGGER trg_seo_websites_updated_at BEFORE UPDATE ON public.seo_websites
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_onboarding_updated_at ON public.seo_business_onboarding;
CREATE TRIGGER trg_seo_onboarding_updated_at BEFORE UPDATE ON public.seo_business_onboarding
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_connection_updated_at ON public.seo_connection_status;
CREATE TRIGGER trg_seo_connection_updated_at BEFORE UPDATE ON public.seo_connection_status
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS. Read: any workspace member (incl. client). Write: owner/admin/team_member
-- (assigned members can set up the site); client cannot manage setup. Delete:
-- owner/admin (or global admin) only.
-- ---------------------------------------------------------------------------

-- seo_websites
ALTER TABLE public.seo_websites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_websites_select ON public.seo_websites;
CREATE POLICY seo_websites_select ON public.seo_websites
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_websites_insert ON public.seo_websites;
CREATE POLICY seo_websites_insert ON public.seo_websites
  FOR INSERT WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_websites_update ON public.seo_websites;
CREATE POLICY seo_websites_update ON public.seo_websites
  FOR UPDATE USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_websites_delete ON public.seo_websites;
CREATE POLICY seo_websites_delete ON public.seo_websites
  FOR DELETE USING (public.can_manage_seo_workspace(workspace_id));

-- seo_business_onboarding
ALTER TABLE public.seo_business_onboarding ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_onboarding_select ON public.seo_business_onboarding;
CREATE POLICY seo_onboarding_select ON public.seo_business_onboarding
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_onboarding_write ON public.seo_business_onboarding;
CREATE POLICY seo_onboarding_write ON public.seo_business_onboarding
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

-- seo_connection_status
ALTER TABLE public.seo_connection_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_connection_select ON public.seo_connection_status;
CREATE POLICY seo_connection_select ON public.seo_connection_status
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_connection_write ON public.seo_connection_status;
CREATE POLICY seo_connection_write ON public.seo_connection_status
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
