-- =============================================================================
-- SEO Stage 6 — Off-Page Authority + AI Visibility/GEO — DRY-RUN WRAPPER
-- =============================================================================
--                          ****  TEST ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Purpose: transaction-wrapped DRY-RUN of the 7 Stage 6 migration files
-- (…120017 through …120023). It CREATEs every Stage 6 object, verifies it, then
-- ROLLBACKs — so NOTHING from Stage 6 remains applied after this script runs.
-- This is a disposable test helper, NOT a migration file and NOT seed data.
--
-- HOW TO RUN: paste this whole file into the Supabase SQL Editor of the
-- DISPOSABLE TEST project that already has Stages 1-5 applied (…120001 through
-- …120016 — this wrapper depends on Stage 1's public.set_updated_at() and the
-- seo_workspaces / seo_websites tables / seo_workspace_members / the Stage 1
-- RLS helpers already existing). Run once. Read the result grids + the
-- Messages/Notices tab.
--
--   * If it reaches the "STAGE 6 DRY-RUN VERIFICATION PASS" NOTICE with no red
--     ERROR, the Stage 6 DDL is engine-valid and the objects / RLS / policies /
--     RPCs / trigger are all present. The final ROLLBACK then removes them all.
--   * If any statement errors, the transaction aborts; note the exact error +
--     statement — that is the migration file/line to fix. Nothing is applied
--     either way (the whole thing is inside BEGIN ... ROLLBACK).
--
-- This wrapper does NOT modify production, does NOT push migrations, and does
-- NOT persist anything. Postgres DDL is transactional, so the final ROLLBACK
-- undoes every CREATE below.
-- =============================================================================

BEGIN;

-- Fail loudly if the Stage 1-5 prerequisites are missing (wrong project / order).
DO $preflight$
BEGIN
  IF to_regclass('public.seo_workspaces') IS NULL
     OR to_regclass('public.seo_websites') IS NULL
     OR to_regclass('public.seo_workspace_members') IS NULL
     OR to_regprocedure('public.set_updated_at()') IS NULL
     OR to_regprocedure('public.is_seo_workspace_member(uuid, uuid)') IS NULL
     OR to_regprocedure('public.seo_role_in(uuid, text[], uuid)') IS NULL
     OR to_regprocedure('public.seo_is_global_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Prerequisite missing: apply Stages 1-5 (…120001-…120016) before this dry-run.';
  END IF;
END
$preflight$;

-- ############################################################################
-- ####  BEGIN inlined Stage 6 migration files, in order …120017-…120023  ####
-- ############################################################################


-- ==== >>> inlined: 20260711120017_seo_stage6_authority_opportunities.sql  >>>====

-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 17 of 23: Authority Opportunities
-- =============================================================================
-- Additive only. First table of the Off-Page Authority Builder. Builds on
-- Stage 1 (seo_workspaces/seo_websites + helpers). One row per off-page
-- trust-signal OPPORTUNITY (backlink / mention / citation / review / PR /
-- social-community / partnership) — a suggested, human-reviewed action, NOT an
-- automated one.
--
-- Safety, encoded in the schema (see SUPABASE_MIGRATION_STAGE_6_..._PLAN.md §8):
--   * No spammy backlink automation, no fake reviews, no mass outreach — this
--     table stores opportunities + decisions; it never executes anything.
--   * `requires_approval` defaults TRUE (external-facing actions need approval).
--   * `spam_risk_flags` + the `avoided` status exist to record and steer AWAY
--     from risky actions.
--   * `source` records provenance only (`manual_seed`/`import`/`system`) — no
--     crawler, GSC/GA4, LLM, cron, or external API ships in Stage 6.
--
-- Status changes go through the guarded seo_authority_opportunity_transition
-- RPC (migration 20), not free-form UPDATEs — see that file. Rows are written by
-- owner/admin/team_member (+ global admin); clients are read-only. Does not
-- touch Stage 1-5 or Core.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_authority_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  opportunity_type text NOT NULL CHECK (opportunity_type IN (
    'backlink', 'mention', 'citation', 'review', 'pr', 'social_community', 'partnership')),
  title text NOT NULL,
  source_platform text NOT NULL,                          -- e.g. a directory/site/community name
  target_url text,                                        -- nullable (some ideas have no single URL)
  target_domain text,                                     -- nullable, app-populated; future domain-level grouping (D7)
  suggested_action text NOT NULL,
  why_it_matters text NOT NULL,
  expected_authority_impact text NOT NULL DEFAULT 'medium'
    CHECK (expected_authority_impact IN ('low', 'medium', 'high')),
  effort text NOT NULL DEFAULT 'medium' CHECK (effort IN ('low', 'medium', 'high')),
  risk text NOT NULL DEFAULT 'low' CHECK (risk IN ('low', 'medium', 'high')),
  confidence_percentage integer
    CHECK (confidence_percentage IS NULL OR confidence_percentage BETWEEN 0 AND 100),
  -- Defaults TRUE: an off-page action is external-facing until proven otherwise,
  -- so it needs approval/manual sign-off before execution (requirement 7).
  requires_approval boolean NOT NULL DEFAULT true,
  fix_owner text NOT NULL DEFAULT 'system_suggestion' CHECK (fix_owner IN (
    'client_action', 'developer_needed', 'digibility_expert', 'system_suggestion')),
  -- Values match the frontend OffPageOpportunityStatus type exactly (src/types/
  -- offpage.ts) so a later wiring phase maps 1:1. Movement is guarded by the
  -- seo_authority_opportunity_transition RPC (migration 20). Terminal states:
  -- completed, rejected, avoided.
  status text NOT NULL DEFAULT 'suggested' CHECK (status IN (
    'suggested', 'shortlisted', 'approval_required', 'in_progress',
    'expert_review_requested', 'completed', 'rejected', 'avoided')),
  -- Array-of-enum via containment CHECK: every element must be an allowed spam
  -- flag. Keeps the frontend's spam_risk_flags[] shape without a child table.
  spam_risk_flags text[] NOT NULL DEFAULT '{}'
    CHECK (spam_risk_flags <@ ARRAY[
      'paid_link_risk', 'irrelevant_directory', 'pbn_like_site',
      'exact_match_anchor_manipulation', 'fake_review_risk', 'mass_outreach_risk',
      'low_relevance', 'low_trust']::text[]),
  recommended_next_action text,                           -- optional, additive
  notes text,                                             -- optional rationale/notes, additive
  source text NOT NULL DEFAULT 'manual_seed' CHECK (source IN ('manual_seed', 'import', 'system')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_workspace ON public.seo_authority_opportunities (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_website ON public.seo_authority_opportunities (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_type ON public.seo_authority_opportunities (opportunity_type);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_status ON public.seo_authority_opportunities (status);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_risk ON public.seo_authority_opportunities (risk);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_source ON public.seo_authority_opportunities (source);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_created ON public.seo_authority_opportunities (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_authority_opp_website_status
  ON public.seo_authority_opportunities (website_id, status);

-- Soft, active-only duplicate guard (D7). Blocks a duplicate ACTIVE opportunity
-- for the same website + type + target URL when a URL is present. Terminal
-- (completed/rejected/avoided) and URL-less opportunities are excluded, so a
-- resolved/avoided idea never blocks a future one, and pure ideas (no URL) may
-- repeat freely. Never dedupes by title.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_authority_opp_active_url
  ON public.seo_authority_opportunities (website_id, opportunity_type, lower(target_url))
  WHERE target_url IS NOT NULL
    AND status IN ('suggested', 'shortlisted', 'approval_required', 'in_progress', 'expert_review_requested');

-- updated_at trigger — reuses Stage 1 public.set_updated_at().
DROP TRIGGER IF EXISTS trg_seo_authority_opp_updated_at ON public.seo_authority_opportunities;
CREATE TRIGGER trg_seo_authority_opp_updated_at BEFORE UPDATE ON public.seo_authority_opportunities
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: any active workspace member (incl. client) + global admin.
-- Write: owner/admin/team_member + global admin only. Clients read-only (D3).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_authority_opportunities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_authority_opportunities_select ON public.seo_authority_opportunities;
CREATE POLICY seo_authority_opportunities_select ON public.seo_authority_opportunities
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_authority_opportunities_write ON public.seo_authority_opportunities;
CREATE POLICY seo_authority_opportunities_write ON public.seo_authority_opportunities
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

-- ==== <<< end: 20260711120017_seo_stage6_authority_opportunities.sql  <<<====

-- ==== >>> inlined: 20260711120018_seo_stage6_authority_campaigns.sql  >>>====

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

-- ==== <<< end: 20260711120018_seo_stage6_authority_campaigns.sql  <<<====

-- ==== >>> inlined: 20260711120019_seo_stage6_authority_campaign_children.sql  >>>====

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

-- ==== <<< end: 20260711120019_seo_stage6_authority_campaign_children.sql  <<<====

-- ==== >>> inlined: 20260711120020_seo_stage6_authority_activity.sql  >>>====

-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 20 of 23: Authority Activity + RPCs
-- =============================================================================
-- Additive only. Builds on migrations 17 (opportunities) + 18 (campaigns).
-- Provides:
--   * seo_authority_activity — an APPEND-ONLY audit trail of off-page workflow
--     transitions + notes (D5a). No UPDATE/DELETE policy for anyone; matches the
--     Stage 2/3 activity-table pattern.
--   * seo_authority_opportunity_transition / seo_authority_campaign_transition —
--     guarded SECURITY DEFINER RPCs (D5) that enforce valid action→status
--     movement, role checks INSIDE the function, and write an activity row. These
--     are the ONLY intended path for off-page status changes — the `start`
--     action for an opportunity is only reachable after approval/expert review,
--     which is the schema-enforced guarantee that an external-facing action
--     passes approval before execution (requirement 7). No automation, no
--     external call — additive to Stage 1-5 + Core.
--
-- Placed before the AI-visibility tables because the RPCs depend only on the
-- off-page tables (17/18) + this activity table, not on any AI table.
-- =============================================================================

-- ===========================================================================
-- seo_authority_activity — append-only audit of opportunity/campaign actions.
-- Exactly one of opportunity_id / campaign_id is set, consistent with
-- subject_type. No updated_at (immutable). Deleting the subject cascades.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_authority_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  subject_type text NOT NULL CHECK (subject_type IN ('opportunity', 'campaign')),
  opportunity_id uuid REFERENCES public.seo_authority_opportunities(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES public.seo_authority_campaigns(id) ON DELETE CASCADE,
  activity_type text NOT NULL,                            -- the transition action (e.g. 'approve', 'start')
  from_status text,
  to_status text,
  note text,
  actor_role_snapshot text,                               -- caller's SEO role at action time
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,  -- the actor
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Exactly one subject, consistent with subject_type.
  CHECK (
    (subject_type = 'opportunity' AND opportunity_id IS NOT NULL AND campaign_id IS NULL)
    OR (subject_type = 'campaign' AND campaign_id IS NOT NULL AND opportunity_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_seo_authority_activity_workspace ON public.seo_authority_activity (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_activity_website ON public.seo_authority_activity (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_activity_opportunity ON public.seo_authority_activity (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_activity_campaign ON public.seo_authority_activity (campaign_id);
CREATE INDEX IF NOT EXISTS idx_seo_authority_activity_created ON public.seo_authority_activity (created_at DESC);

-- ---------------------------------------------------------------------------
-- RLS — APPEND-ONLY. Read: member + global admin. Insert: owner/admin/
-- team_member + global admin (also written by the transition RPCs, which are
-- SECURITY DEFINER and bypass RLS). NO update/delete policy → immutable.
-- Clients read-only (D3).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_authority_activity ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_authority_activity_select ON public.seo_authority_activity;
CREATE POLICY seo_authority_activity_select ON public.seo_authority_activity
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_authority_activity_insert ON public.seo_authority_activity;
CREATE POLICY seo_authority_activity_insert ON public.seo_authority_activity
  FOR INSERT WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
-- No UPDATE/DELETE policy on purpose — append-only.

-- ===========================================================================
-- seo_authority_opportunity_transition — guarded off-page opportunity workflow.
-- SECURITY DEFINER (same pattern as Stage 2/3 transition RPCs) so the read +
-- update + activity insert run regardless of the caller's own RLS, AFTER the
-- in-function role check. Rejects clients/non-members. No external call.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_authority_opportunity_transition(
  p_opportunity_id uuid,
  p_action text,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o public.seo_authority_opportunities%ROWTYPE;
  v_from text;
  v_to text;
  v_role text;
BEGIN
  SELECT * INTO o FROM public.seo_authority_opportunities WHERE id = p_opportunity_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authority opportunity % does not exist', p_opportunity_id;
  END IF;

  -- Base permission: manager in this workspace (or global admin). Clients and
  -- non-members are rejected here even though EXECUTE is granted to authenticated.
  IF NOT (public.seo_role_in(o.workspace_id, ARRAY['owner', 'admin', 'team_member'])
          OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not permitted to transition authority opportunities in this workspace';
  END IF;

  v_from := o.status;

  CASE p_action
    WHEN 'shortlist' THEN
      IF v_from <> 'suggested' THEN RAISE EXCEPTION 'Illegal transition: % via shortlist', v_from; END IF;
      v_to := 'shortlisted';
    WHEN 'request_approval' THEN
      IF v_from <> 'shortlisted' THEN RAISE EXCEPTION 'Illegal transition: % via request_approval', v_from; END IF;
      v_to := 'approval_required';
    WHEN 'request_expert_review' THEN
      IF v_from NOT IN ('shortlisted', 'approval_required', 'in_progress') THEN
        RAISE EXCEPTION 'Illegal transition: % via request_expert_review', v_from;
      END IF;
      v_to := 'expert_review_requested';
    WHEN 'start' THEN
      -- Guardrail (requirement 7): execution only after approval/expert review.
      IF v_from NOT IN ('approval_required', 'expert_review_requested') THEN
        RAISE EXCEPTION 'Illegal transition: % via start — an external-facing action must pass approval/expert review first', v_from;
      END IF;
      v_to := 'in_progress';
    WHEN 'complete' THEN
      IF v_from <> 'in_progress' THEN RAISE EXCEPTION 'Illegal transition: % via complete', v_from; END IF;
      v_to := 'completed';
    WHEN 'reject' THEN
      IF v_from IN ('completed', 'rejected', 'avoided') THEN
        RAISE EXCEPTION 'Illegal transition: % via reject (terminal state)', v_from;
      END IF;
      IF NOT (public.seo_role_in(o.workspace_id, ARRAY['owner', 'admin']) OR public.seo_is_global_admin()) THEN
        RAISE EXCEPTION 'Only owner/admin may reject an authority opportunity';
      END IF;
      v_to := 'rejected';
    WHEN 'avoid' THEN
      IF v_from IN ('completed', 'rejected', 'avoided') THEN
        RAISE EXCEPTION 'Illegal transition: % via avoid (terminal state)', v_from;
      END IF;
      v_to := 'avoided';
    ELSE
      RAISE EXCEPTION 'Unknown authority opportunity action: %', p_action;
  END CASE;

  UPDATE public.seo_authority_opportunities
    SET status = v_to, updated_at = now()
  WHERE id = p_opportunity_id;

  SELECT seo_role INTO v_role FROM public.seo_workspace_members
    WHERE workspace_id = o.workspace_id AND user_id = auth.uid() AND status = 'active'
    LIMIT 1;
  IF v_role IS NULL AND public.seo_is_global_admin() THEN v_role := 'global_admin'; END IF;

  INSERT INTO public.seo_authority_activity
    (workspace_id, website_id, website_url, subject_type, opportunity_id, campaign_id,
     activity_type, from_status, to_status, note, actor_role_snapshot, created_by)
  VALUES
    (o.workspace_id, o.website_id, o.website_url, 'opportunity', p_opportunity_id, NULL,
     p_action, v_from, v_to, p_note, v_role, auth.uid());

  RETURN v_to;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seo_authority_opportunity_transition(uuid, text, text) TO authenticated;

-- ===========================================================================
-- seo_authority_campaign_transition — guarded campaign approval workflow.
-- submit/return are owner/admin/team_member; approve/reject are owner/admin
-- (+ global admin) only — a team_member may submit + rework but not self-approve.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_authority_campaign_transition(
  p_campaign_id uuid,
  p_action text,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.seo_authority_campaigns%ROWTYPE;
  v_from text;
  v_to text;
  v_role text;
  v_is_owner_admin boolean;
BEGIN
  SELECT * INTO c FROM public.seo_authority_campaigns WHERE id = p_campaign_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authority campaign % does not exist', p_campaign_id;
  END IF;

  IF NOT (public.seo_role_in(c.workspace_id, ARRAY['owner', 'admin', 'team_member'])
          OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not permitted to transition authority campaigns in this workspace';
  END IF;

  v_is_owner_admin := public.seo_role_in(c.workspace_id, ARRAY['owner', 'admin'])
                      OR public.seo_is_global_admin();
  v_from := c.approval_status;

  CASE p_action
    WHEN 'submit_for_approval' THEN
      IF v_from <> 'draft' THEN RAISE EXCEPTION 'Illegal transition: % via submit_for_approval', v_from; END IF;
      v_to := 'pending_approval';
    WHEN 'approve' THEN
      IF NOT v_is_owner_admin THEN RAISE EXCEPTION 'Only owner/admin may approve a campaign'; END IF;
      IF v_from <> 'pending_approval' THEN RAISE EXCEPTION 'Illegal transition: % via approve', v_from; END IF;
      v_to := 'approved';
    WHEN 'reject' THEN
      IF NOT v_is_owner_admin THEN RAISE EXCEPTION 'Only owner/admin may reject a campaign'; END IF;
      IF v_from <> 'pending_approval' THEN RAISE EXCEPTION 'Illegal transition: % via reject', v_from; END IF;
      v_to := 'rejected';
    WHEN 'return_to_draft' THEN
      IF v_from NOT IN ('pending_approval', 'rejected') THEN
        RAISE EXCEPTION 'Illegal transition: % via return_to_draft', v_from;
      END IF;
      v_to := 'draft';
    ELSE
      RAISE EXCEPTION 'Unknown authority campaign action: %', p_action;
  END CASE;

  UPDATE public.seo_authority_campaigns
    SET approval_status = v_to, updated_at = now()
  WHERE id = p_campaign_id;

  SELECT seo_role INTO v_role FROM public.seo_workspace_members
    WHERE workspace_id = c.workspace_id AND user_id = auth.uid() AND status = 'active'
    LIMIT 1;
  IF v_role IS NULL AND public.seo_is_global_admin() THEN v_role := 'global_admin'; END IF;

  INSERT INTO public.seo_authority_activity
    (workspace_id, website_id, website_url, subject_type, opportunity_id, campaign_id,
     activity_type, from_status, to_status, note, actor_role_snapshot, created_by)
  VALUES
    (c.workspace_id, c.website_id, c.website_url, 'campaign', NULL, p_campaign_id,
     p_action, v_from, v_to, p_note, v_role, auth.uid());

  RETURN v_to;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seo_authority_campaign_transition(uuid, text, text) TO authenticated;

-- ==== <<< end: 20260711120020_seo_stage6_authority_activity.sql  <<<====

-- ==== >>> inlined: 20260711120021_seo_stage6_ai_prompt_tracking.sql  >>>====

-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 21 of 23: AI Prompt Tracking
-- =============================================================================
-- Additive only. First AI Visibility / GEO table. Builds on Stage 1. One row
-- per OBSERVED AI-answer check for a prompt — how a business appears when an AI
-- assistant answers a question. This is TIME-SERIES observation data (D4):
-- repeated observations of the SAME prompt on later `observed_on` dates are
-- allowed and first-class, so there is deliberately NO uniqueness on prompt_text.
--
-- Observed/manual/imported ONLY (requirement 9/10): `source` ∈
-- (manual_seed/import/system). NO LLM call, NO scraper, NO external API, NO cron
-- ships in Stage 6 — these rows are entered/imported by managers. Managers write
-- via plain RLS (no transition RPC — this is reporting data, not an
-- external-facing execution action). Clients read-only. Additive to Stage 1-5
-- + Core.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_ai_prompt_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  prompt_text text NOT NULL,
  topic text NOT NULL,                                    -- prompt category/topic (frontend PromptTrackingRecord.topic)
  observed_on date NOT NULL DEFAULT current_date,         -- the observation date (D4 time-series)
  visibility_status text NOT NULL DEFAULT 'unknown'
    CHECK (visibility_status IN ('visible', 'partially_visible', 'not_visible', 'unknown')),
  brand_mentioned boolean NOT NULL DEFAULT false,
  brand_position integer,                                 -- optional rank/order the brand appeared at, if known
  competitors_mentioned text[] NOT NULL DEFAULT '{}',     -- free text (competitor names) — no CHECK
  citation_sources text[] NOT NULL DEFAULT '{}',          -- free text (URLs/source names) — no CHECK
  our_site_cited boolean NOT NULL DEFAULT false,
  gap_summary text NOT NULL DEFAULT '',                   -- observed-answer summary / why we are/aren't visible
  recommended_next_step text NOT NULL DEFAULT '',
  source text NOT NULL DEFAULT 'manual_seed' CHECK (source IN ('manual_seed', 'import', 'system')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (brand_position IS NULL OR brand_position >= 1)
);

CREATE INDEX IF NOT EXISTS idx_seo_ai_prompt_workspace ON public.seo_ai_prompt_tracking (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_prompt_website ON public.seo_ai_prompt_tracking (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_prompt_observed ON public.seo_ai_prompt_tracking (website_id, observed_on DESC);
CREATE INDEX IF NOT EXISTS idx_seo_ai_prompt_visibility ON public.seo_ai_prompt_tracking (visibility_status);
CREATE INDEX IF NOT EXISTS idx_seo_ai_prompt_topic ON public.seo_ai_prompt_tracking (topic);
CREATE INDEX IF NOT EXISTS idx_seo_ai_prompt_source ON public.seo_ai_prompt_tracking (source);
-- NOTE: intentionally NO unique index on prompt_text (D4 — same prompt may be
-- re-observed on later dates).

DROP TRIGGER IF EXISTS trg_seo_ai_prompt_updated_at ON public.seo_ai_prompt_tracking;
CREATE TRIGGER trg_seo_ai_prompt_updated_at BEFORE UPDATE ON public.seo_ai_prompt_tracking
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: member + global admin. Write: owner/admin/team_member + global
-- admin (clients read-only, D3). Plain RLS writes — no transition RPC.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_ai_prompt_tracking ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_ai_prompt_tracking_select ON public.seo_ai_prompt_tracking;
CREATE POLICY seo_ai_prompt_tracking_select ON public.seo_ai_prompt_tracking
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_ai_prompt_tracking_write ON public.seo_ai_prompt_tracking;
CREATE POLICY seo_ai_prompt_tracking_write ON public.seo_ai_prompt_tracking
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

-- ==== <<< end: 20260711120021_seo_stage6_ai_prompt_tracking.sql  <<<====

-- ==== >>> inlined: 20260711120022_seo_stage6_ai_content_gaps.sql  >>>====

-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 22 of 23: AI Content Gaps
-- =============================================================================
-- Additive only. Builds on Stage 1 + migration 21 (prompt tracking). One row per
-- AI-visibility content gap — a topic/question where the site is under-cited or
-- absent from AI answers, with a suggested next action. Optionally linked to the
-- prompt-tracking observation that surfaced it (`related_prompt_id`).
--
-- Observed/manual/imported ONLY: `source` ∈ (manual_seed/import/system). No LLM,
-- crawler, or external API. Managers write via plain RLS; clients read-only.
-- Additive to Stage 1-5 + Core.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_ai_content_gaps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  -- Optional link to the prompt observation that surfaced this gap. ON DELETE
  -- SET NULL so the gap survives if the prompt row is removed.
  related_prompt_id uuid REFERENCES public.seo_ai_prompt_tracking(id) ON DELETE SET NULL,
  topic text NOT NULL,
  missing_answer_angle text NOT NULL,
  suggested_content_type text NOT NULL,
  related_keyword_or_question text NOT NULL,
  gap_type text,                                          -- optional free label, additive
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
  recommended_next_action text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'planned', 'addressed', 'dismissed')),
  source text NOT NULL DEFAULT 'manual_seed' CHECK (source IN ('manual_seed', 'import', 'system')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_workspace ON public.seo_ai_content_gaps (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_website ON public.seo_ai_content_gaps (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_prompt ON public.seo_ai_content_gaps (related_prompt_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_priority ON public.seo_ai_content_gaps (priority);
CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_status ON public.seo_ai_content_gaps (status);
CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_source ON public.seo_ai_content_gaps (source);
CREATE INDEX IF NOT EXISTS idx_seo_ai_gap_website_status ON public.seo_ai_content_gaps (website_id, status);

DROP TRIGGER IF EXISTS trg_seo_ai_gap_updated_at ON public.seo_ai_content_gaps;
CREATE TRIGGER trg_seo_ai_gap_updated_at BEFORE UPDATE ON public.seo_ai_content_gaps
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: member + global admin. Write: owner/admin/team_member + global
-- admin (clients read-only, D3).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_ai_content_gaps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_ai_content_gaps_select ON public.seo_ai_content_gaps;
CREATE POLICY seo_ai_content_gaps_select ON public.seo_ai_content_gaps
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_ai_content_gaps_write ON public.seo_ai_content_gaps;
CREATE POLICY seo_ai_content_gaps_write ON public.seo_ai_content_gaps
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

-- ==== <<< end: 20260711120022_seo_stage6_ai_content_gaps.sql  <<<====

-- ==== >>> inlined: 20260711120023_seo_stage6_ai_mentions.sql  >>>====

-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15A) — Migration 23 of 23: AI Mentions
-- =============================================================================
-- Additive only. Builds on Stage 1 + migration 21 (prompt tracking). Normalized
-- mention rows (D2): one row per brand / competitor / citation-source appearance
-- observed in an AI answer. This is the stored, queryable source that feeds
-- brand/competitor summaries and future reporting — replacing the current
-- mock's derive-from-prompt-arrays approach. Optionally linked to the
-- prompt-tracking observation it came from (`prompt_tracking_id`).
--
-- Observed/manual/imported ONLY: `source` ∈ (manual_seed/import/system). This
-- table does NOT imply live scraping — no LLM, crawler, or external API ships in
-- Stage 6; managers enter/import rows. Managers write via plain RLS; clients
-- read-only. Additive to Stage 1-5 + Core.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_ai_mentions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  -- Optional link to the observation this mention came from. Nullable so a
  -- mention can be recorded independently; cascade when linked.
  prompt_tracking_id uuid REFERENCES public.seo_ai_prompt_tracking(id) ON DELETE CASCADE,
  mention_type text NOT NULL CHECK (mention_type IN ('brand', 'competitor', 'citation_source')),
  entity_name text NOT NULL,                              -- brand / competitor / cited source name
  entity_url text,                                        -- optional
  citation_url text,                                      -- optional (for citation_source rows)
  -- For citation_source rows: whether the cited source is the tracked website —
  -- supports "our site cited" reporting without re-parsing prompt arrays.
  is_our_site boolean NOT NULL DEFAULT false,
  mention_position integer CHECK (mention_position IS NULL OR mention_position >= 1),
  sentiment text CHECK (sentiment IS NULL OR sentiment IN ('positive', 'neutral', 'negative')),
  prominence text CHECK (prominence IS NULL OR prominence IN ('low', 'medium', 'high')),
  where_appears text,                                     -- prompt/answer context snippet
  notes text,
  source text NOT NULL DEFAULT 'manual_seed' CHECK (source IN ('manual_seed', 'import', 'system')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_workspace ON public.seo_ai_mentions (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_website ON public.seo_ai_mentions (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_prompt ON public.seo_ai_mentions (prompt_tracking_id);
CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_type ON public.seo_ai_mentions (mention_type);
CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_entity ON public.seo_ai_mentions (entity_name);
CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_source ON public.seo_ai_mentions (source);
CREATE INDEX IF NOT EXISTS idx_seo_ai_mention_website_type ON public.seo_ai_mentions (website_id, mention_type);

DROP TRIGGER IF EXISTS trg_seo_ai_mention_updated_at ON public.seo_ai_mentions;
CREATE TRIGGER trg_seo_ai_mention_updated_at BEFORE UPDATE ON public.seo_ai_mentions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — read: member + global admin. Write: owner/admin/team_member + global
-- admin (clients read-only, D3).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_ai_mentions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_ai_mentions_select ON public.seo_ai_mentions;
CREATE POLICY seo_ai_mentions_select ON public.seo_ai_mentions
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_ai_mentions_write ON public.seo_ai_mentions;
CREATE POLICY seo_ai_mentions_write ON public.seo_ai_mentions
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

-- ==== <<< end: 20260711120023_seo_stage6_ai_mentions.sql  <<<====

-- ############################################################################
-- ####  END inlined migrations. BEGIN in-transaction DRY-RUN VERIFICATION  ####
-- ############################################################################
-- All SELECTs below run INSIDE the open transaction (objects exist here); the
-- final ROLLBACK removes everything. Read each result grid, then the summary.

-- ---------------------------------------------------------------------------
-- CHECK 1 — all 8 Stage 6 tables are visible (expect exactly 8 rows).
-- ---------------------------------------------------------------------------
SELECT 'CHECK 1: tables' AS check, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'seo_authority_opportunities', 'seo_authority_campaigns',
    'seo_authority_campaign_tasks', 'seo_authority_campaign_opportunities',
    'seo_authority_activity', 'seo_ai_prompt_tracking',
    'seo_ai_content_gaps', 'seo_ai_mentions')
ORDER BY table_name;

-- ---------------------------------------------------------------------------
-- CHECK 2 — RLS enabled on all 8 tables (expect relrowsecurity = true for all).
-- ---------------------------------------------------------------------------
SELECT 'CHECK 2: RLS' AS check, c.relname AS table_name, c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'seo_authority_opportunities', 'seo_authority_campaigns',
    'seo_authority_campaign_tasks', 'seo_authority_campaign_opportunities',
    'seo_authority_activity', 'seo_ai_prompt_tracking',
    'seo_ai_content_gaps', 'seo_ai_mentions')
ORDER BY c.relname;

-- ---------------------------------------------------------------------------
-- CHECK 3 — the 2 transition RPCs are visible (expect 2 rows).
-- ---------------------------------------------------------------------------
SELECT 'CHECK 3: RPCs' AS check, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'seo_authority_opportunity_transition', 'seo_authority_campaign_transition')
ORDER BY p.proname;

-- ---------------------------------------------------------------------------
-- CHECK 4 — the junction integrity trigger function + its trigger are visible.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 4a: integrity fn' AS check, p.proname AS function_name, p.prosecdef AS security_definer
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'seo_authority_campaign_opportunity_integrity';

SELECT 'CHECK 4b: integrity trg' AS check, t.tgname AS trigger_name, c.relname AS on_table
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND t.tgname = 'trg_seo_authority_camp_opp_integrity'
  AND NOT t.tgisinternal;

-- ---------------------------------------------------------------------------
-- CHECK 5 — policies exist and match the intended shape.
--   * SELECT policy on all 8 tables.
--   * write (FOR ALL) policy on the 7 manager-written tables.
--   * seo_authority_activity: INSERT policy present, NO update/delete policy.
-- ---------------------------------------------------------------------------
-- 5a: full policy inventory (cmd: r=SELECT, a=INSERT, w=UPDATE, d=DELETE, *=ALL).
SELECT 'CHECK 5a: policies' AS check, c.relname AS table_name, pol.polname AS policy_name,
       CASE pol.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                       WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE'
                       WHEN '*' THEN 'ALL' END AS command
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'seo_authority_opportunities', 'seo_authority_campaigns',
    'seo_authority_campaign_tasks', 'seo_authority_campaign_opportunities',
    'seo_authority_activity', 'seo_ai_prompt_tracking',
    'seo_ai_content_gaps', 'seo_ai_mentions')
ORDER BY c.relname, command;

-- 5b: per-table policy shape summary — expect for the 7 manager tables:
--     select_policies=1, write_all_policies=1, update_or_delete=0;
--     for seo_authority_activity: select=1, insert=1, write_all=0, update_or_delete=0.
SELECT 'CHECK 5b: shape' AS check, c.relname AS table_name,
       count(*) FILTER (WHERE pol.polcmd = 'r') AS select_policies,
       count(*) FILTER (WHERE pol.polcmd = '*') AS write_all_policies,
       count(*) FILTER (WHERE pol.polcmd = 'a') AS insert_policies,
       count(*) FILTER (WHERE pol.polcmd IN ('w', 'd')) AS update_or_delete_policies
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policy pol ON pol.polrelid = c.oid
WHERE n.nspname = 'public'
  AND c.relname IN (
    'seo_authority_opportunities', 'seo_authority_campaigns',
    'seo_authority_campaign_tasks', 'seo_authority_campaign_opportunities',
    'seo_authority_activity', 'seo_ai_prompt_tracking',
    'seo_ai_content_gaps', 'seo_ai_mentions')
GROUP BY c.relname
ORDER BY c.relname;

-- ---------------------------------------------------------------------------
-- CHECK 6 — no unintended production/core changes: every table/function/trigger
-- created here is Stage-6-prefixed and additive. This lists what THIS wrapper
-- would add; confirm nothing outside the Stage 6 object set appears.
-- (Because everything runs in one aborted transaction, no Core/Stage 1-5 object
--  is altered — this is a visual confirmation of the additive object set only.)
-- ---------------------------------------------------------------------------
SELECT 'CHECK 6: new objects' AS check, 'table' AS kind, c.relname AS object_name
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname LIKE 'seo_a%'
  AND c.relname IN (
    'seo_authority_opportunities', 'seo_authority_campaigns',
    'seo_authority_campaign_tasks', 'seo_authority_campaign_opportunities',
    'seo_authority_activity', 'seo_ai_prompt_tracking',
    'seo_ai_content_gaps', 'seo_ai_mentions')
UNION ALL
SELECT 'CHECK 6: new objects', 'function', p.proname
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'seo_authority_opportunity_transition', 'seo_authority_campaign_transition',
    'seo_authority_campaign_opportunity_integrity')
ORDER BY kind, object_name;

-- ---------------------------------------------------------------------------
-- SUMMARY GUARD — raises unless every structural expectation is met, so a
-- failure is loud even if the result grids are skimmed.
-- ---------------------------------------------------------------------------
DO $verify$
DECLARE
  v_tables int; v_rls int; v_rpcs int; v_intg_fn int; v_intg_trg int;
  v_select int; v_write int; v_activity_ins int; v_activity_ud int;
BEGIN
  SELECT count(*) INTO v_tables FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name IN (
    'seo_authority_opportunities','seo_authority_campaigns',
    'seo_authority_campaign_tasks','seo_authority_campaign_opportunities',
    'seo_authority_activity','seo_ai_prompt_tracking',
    'seo_ai_content_gaps','seo_ai_mentions');

  SELECT count(*) INTO v_rls FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relrowsecurity AND c.relname IN (
    'seo_authority_opportunities','seo_authority_campaigns',
    'seo_authority_campaign_tasks','seo_authority_campaign_opportunities',
    'seo_authority_activity','seo_ai_prompt_tracking',
    'seo_ai_content_gaps','seo_ai_mentions');

  SELECT count(*) INTO v_rpcs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'seo_authority_opportunity_transition','seo_authority_campaign_transition');

  SELECT count(*) INTO v_intg_fn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='seo_authority_campaign_opportunity_integrity';

  SELECT count(*) INTO v_intg_trg FROM pg_trigger t
  WHERE t.tgname='trg_seo_authority_camp_opp_integrity' AND NOT t.tgisinternal;

  SELECT count(*) INTO v_select FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND pol.polcmd='r' AND c.relname IN (
    'seo_authority_opportunities','seo_authority_campaigns',
    'seo_authority_campaign_tasks','seo_authority_campaign_opportunities',
    'seo_authority_activity','seo_ai_prompt_tracking',
    'seo_ai_content_gaps','seo_ai_mentions');

  -- write (FOR ALL) policies expected on the 7 manager-written tables (NOT activity).
  SELECT count(*) INTO v_write FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND pol.polcmd='*' AND c.relname IN (
    'seo_authority_opportunities','seo_authority_campaigns',
    'seo_authority_campaign_tasks','seo_authority_campaign_opportunities',
    'seo_ai_prompt_tracking','seo_ai_content_gaps','seo_ai_mentions');

  SELECT count(*) INTO v_activity_ins FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND pol.polcmd='a' AND c.relname='seo_authority_activity';

  SELECT count(*) INTO v_activity_ud FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND pol.polcmd IN ('w','d') AND c.relname='seo_authority_activity';

  RAISE NOTICE 'Stage 6 dry-run counts: tables=% (exp 8), rls=% (exp 8), rpcs=% (exp 2), integrity_fn=% (exp 1), integrity_trg=% (exp 1), select_policies=% (exp 8), write_all_policies=% (exp 7), activity_insert=% (exp 1), activity_update_delete=% (exp 0)',
    v_tables, v_rls, v_rpcs, v_intg_fn, v_intg_trg, v_select, v_write, v_activity_ins, v_activity_ud;

  IF v_tables=8 AND v_rls=8 AND v_rpcs=2 AND v_intg_fn=1 AND v_intg_trg=1
     AND v_select=8 AND v_write=7 AND v_activity_ins=1 AND v_activity_ud=0 THEN
    RAISE NOTICE '===== STAGE 6 DRY-RUN VERIFICATION PASS =====';
  ELSE
    RAISE EXCEPTION 'STAGE 6 DRY-RUN VERIFICATION FAILED — see counts above.';
  END IF;
END
$verify$;

-- ############################################################################
-- ####  ROLLBACK — nothing from Stage 6 remains applied after this runs.   ####
-- ############################################################################
ROLLBACK;

-- (Optional) sanity-check AFTER rollback that Stage 6 left nothing behind —
-- run this line separately; it must return 0 rows on the TEST project:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema='public' AND table_name LIKE 'seo_authority_%';
