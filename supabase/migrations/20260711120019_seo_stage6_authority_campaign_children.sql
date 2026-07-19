-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 19 of 23: Campaign Children
-- =============================================================================
-- Additive only. Builds on migrations 17 (opportunities) + 18 (campaigns). Two
-- child structures of a campaign:
--   * seo_authority_campaign_tasks — the campaign's checklist (label + done).
--   * seo_authority_campaign_opportunities — the normalized junction that is the
--     SOURCE OF TRUTH for which opportunities a campaign includes (D1). No
--     opportunity_ids[] array lives on the campaign.
--
-- Both children carry workspace_id/website_id/website_url so RLS can call
-- is_seo_workspace_member(workspace_id) on the row itself (the Stage 5
-- seo_decline_diagnosis_evidence precedent). A BEFORE INSERT/UPDATE integrity
-- trigger on the junction enforces that the linked campaign and opportunity
-- both belong to the SAME workspace/website as the junction row (no
-- cross-workspace linkage), mirroring Stage 2's seo_set_hrc_from_issue guard.
-- Clients read-only (D3). Additive to Stage 1-5 + Core.
-- =============================================================================

-- ===========================================================================
-- seo_authority_campaign_tasks — checklist items for a campaign.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_authority_campaign_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  campaign_id uuid NOT NULL REFERENCES public.seo_authority_campaigns(id) ON DELETE CASCADE,
  -- Optional provenance: a task is often generated from an opportunity's
  -- suggested_action. ON DELETE SET NULL so deleting the opportunity keeps the task.
  opportunity_id uuid REFERENCES public.seo_authority_opportunities(id) ON DELETE SET NULL,
  label text NOT NULL,                                    -- matches the frontend CampaignTask.label
  task_type text,                                         -- optional free label, additive
  owner_type text CHECK (owner_type IS NULL OR owner_type IN (
    'client_action', 'developer_needed', 'digibility_expert', 'system_suggestion')),
  is_complete boolean NOT NULL DEFAULT false,             -- frontend CampaignTask.is_complete
  external_action_required boolean NOT NULL DEFAULT false,-- flags a task that touches an external platform
  position integer NOT NULL DEFAULT 0,                    -- display order within the campaign
  due_date date,
  completed_at timestamptz,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_authority_task_workspace ON public.seo_authority_campaign_tasks (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_task_website ON public.seo_authority_campaign_tasks (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_task_campaign ON public.seo_authority_campaign_tasks (campaign_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_task_opportunity ON public.seo_authority_campaign_tasks (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_task_complete ON public.seo_authority_campaign_tasks (campaign_id, is_complete);

-- Ordered tasks: positions are unique within a campaign.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_authority_task_position
  ON public.seo_authority_campaign_tasks (campaign_id, position);

DROP TRIGGER IF EXISTS trg_seo_authority_task_updated_at ON public.seo_authority_campaign_tasks;
CREATE TRIGGER trg_seo_authority_task_updated_at BEFORE UPDATE ON public.seo_authority_campaign_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- seo_authority_campaign_opportunities — junction (D1). Source of truth for
-- campaign membership. PK prevents duplicate links; both FKs cascade.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_authority_campaign_opportunities (
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  campaign_id uuid NOT NULL REFERENCES public.seo_authority_campaigns(id) ON DELETE CASCADE,
  opportunity_id uuid NOT NULL REFERENCES public.seo_authority_opportunities(id) ON DELETE CASCADE,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, opportunity_id)
);

CREATE INDEX IF NOT EXISTS idx_seo_authority_camp_opp_opportunity
  ON public.seo_authority_campaign_opportunities (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_camp_opp_workspace
  ON public.seo_authority_campaign_opportunities (workspace_id);

-- Integrity: the junction row, its campaign, and its opportunity must all share
-- the same workspace_id + website_id — no cross-workspace/website linkage.
-- SECURITY DEFINER so it reads the parent rows regardless of the writer's RLS.
-- Mirrors Stage 2's seo_set_hrc_from_issue integrity pattern.
CREATE OR REPLACE FUNCTION public.seo_authority_campaign_opportunity_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_camp_ws uuid; v_camp_web uuid;
  v_opp_ws uuid;  v_opp_web uuid;
BEGIN
  SELECT workspace_id, website_id INTO v_camp_ws, v_camp_web
  FROM public.seo_authority_campaigns WHERE id = NEW.campaign_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Campaign % does not exist', NEW.campaign_id;
  END IF;

  SELECT workspace_id, website_id INTO v_opp_ws, v_opp_web
  FROM public.seo_authority_opportunities WHERE id = NEW.opportunity_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Opportunity % does not exist', NEW.opportunity_id;
  END IF;

  IF v_camp_ws <> v_opp_ws OR v_camp_web <> v_opp_web THEN
    RAISE EXCEPTION 'Campaign and opportunity belong to different workspace/website';
  END IF;
  IF NEW.workspace_id <> v_camp_ws OR NEW.website_id <> v_camp_web THEN
    RAISE EXCEPTION 'Junction workspace/website must match the campaign/opportunity';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_authority_camp_opp_integrity ON public.seo_authority_campaign_opportunities;
CREATE TRIGGER trg_seo_authority_camp_opp_integrity
  BEFORE INSERT OR UPDATE ON public.seo_authority_campaign_opportunities
  FOR EACH ROW EXECUTE FUNCTION public.seo_authority_campaign_opportunity_integrity();

-- ---------------------------------------------------------------------------
-- RLS — both children: read = member + global admin; write = owner/admin/
-- team_member + global admin (clients read-only, D3).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_authority_campaign_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_authority_campaign_tasks_select ON public.seo_authority_campaign_tasks;
CREATE POLICY seo_authority_campaign_tasks_select ON public.seo_authority_campaign_tasks
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_authority_campaign_tasks_write ON public.seo_authority_campaign_tasks;
CREATE POLICY seo_authority_campaign_tasks_write ON public.seo_authority_campaign_tasks
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

ALTER TABLE public.seo_authority_campaign_opportunities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_authority_campaign_opportunities_select ON public.seo_authority_campaign_opportunities;
CREATE POLICY seo_authority_campaign_opportunities_select ON public.seo_authority_campaign_opportunities
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_authority_campaign_opportunities_write ON public.seo_authority_campaign_opportunities;
CREATE POLICY seo_authority_campaign_opportunities_write ON public.seo_authority_campaign_opportunities
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
