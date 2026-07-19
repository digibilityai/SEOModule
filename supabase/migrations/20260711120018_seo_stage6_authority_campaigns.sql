-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 18 of 23: Authority Campaigns
-- =============================================================================
-- Additive only. Builds on Stage 1 + migration 17. A campaign groups off-page
-- opportunities into an approvable plan of tasks. Campaign ↔ opportunity
-- membership lives in the seo_authority_campaign_opportunities junction
-- (migration 19), NOT an array on this table (D1). Progress is DERIVED from
-- campaign tasks in the service layer — there is intentionally no stored
-- progress_percentage column (D6).
--
-- `approval_status` values match the frontend CampaignApprovalStatus type
-- exactly (src/types/offpage.ts). Movement is guarded by the
-- seo_authority_campaign_transition RPC (migration 20): a team_member submits
-- for approval and reworks; only owner/admin (+ global admin) approve/reject.
-- No automation, no external execution — additive to Stage 1-5 + Core.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_authority_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  name text NOT NULL,
  goal text NOT NULL,                                     -- the campaign's objective, plain language
  campaign_type text,                                     -- optional free label (e.g. "local trust", "content pr")
  approval_status text NOT NULL DEFAULT 'draft'
    CHECK (approval_status IN ('draft', 'pending_approval', 'approved', 'rejected')),
  owner text NOT NULL DEFAULT 'client_action' CHECK (owner IN (
    'client_action', 'developer_needed', 'digibility_expert', 'system_suggestion')),
  due_date date,
  started_at timestamptz,                                 -- optional, set by the app when execution begins
  completed_at timestamptz,                               -- optional, set by the app when execution ends
  -- NO progress_percentage (D6): derived from seo_authority_campaign_tasks
  -- (complete / total) in the service layer / a future view.
  source text NOT NULL DEFAULT 'manual_seed' CHECK (source IN ('manual_seed', 'import', 'system')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_workspace ON public.seo_authority_campaigns (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_website ON public.seo_authority_campaigns (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_status ON public.seo_authority_campaigns (approval_status);
CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_due ON public.seo_authority_campaigns (due_date);
CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_source ON public.seo_authority_campaigns (source);
CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_created ON public.seo_authority_campaigns (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_authority_campaign_website_status
  ON public.seo_authority_campaigns (website_id, approval_status);

DROP TRIGGER IF EXISTS trg_seo_authority_campaign_updated_at ON public.seo_authority_campaigns;
CREATE TRIGGER trg_seo_authority_campaign_updated_at BEFORE UPDATE ON public.seo_authority_campaigns
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: member (incl. client) + global admin. Write: owner/admin/
-- team_member + global admin. Clients read-only (D3). Approve/reject are
-- further restricted to owner/admin inside the transition RPC (migration 20).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_authority_campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_authority_campaigns_select ON public.seo_authority_campaigns;
CREATE POLICY seo_authority_campaigns_select ON public.seo_authority_campaigns
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_authority_campaigns_write ON public.seo_authority_campaigns;
CREATE POLICY seo_authority_campaigns_write ON public.seo_authority_campaigns
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
