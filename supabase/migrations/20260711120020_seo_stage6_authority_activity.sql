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
