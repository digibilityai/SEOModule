-- =============================================================================
-- SEO Backend — Stage 2 (Phase 12E) — Migration 5 of 6: Recommendations
-- =============================================================================
-- Additive only. Recommendations derived from audit issues + on-page templates.
-- History preserved via is_current + superseded_by (no separate history table).
-- System/service-role generated; clients cannot write. Depends on migration 4.
-- =============================================================================

-- ===========================================================================
-- seo_recommendations — versioned fixes. is_current=true is the live version;
-- superseded rows are retained (is_current=false, superseded_by set).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  audit_run_id uuid REFERENCES public.seo_audit_runs(id) ON DELETE SET NULL,
  issue_id uuid REFERENCES public.seo_audit_issues(id) ON DELETE SET NULL,
  area text NOT NULL CHECK (area IN (
    'title', 'meta_description', 'h1', 'faq', 'schema', 'internal_links', 'content', 'technical')),
  title text NOT NULL,
  current_value text,
  suggested_change text NOT NULL,
  why_it_helps text NOT NULL,
  action_type text NOT NULL CHECK (action_type IN (
    'auto_suggest', 'approval_required', 'manual_support', 'expert_review', 'avoid')),
  impact text NOT NULL CHECK (impact IN ('low', 'medium', 'high')),
  effort text NOT NULL CHECK (effort IN ('low', 'medium', 'high')),
  risk text NOT NULL CHECK (risk IN ('low', 'medium', 'high')),
  confidence_percentage integer NOT NULL DEFAULT 0 CHECK (confidence_percentage BETWEEN 0 AND 100),
  is_high_risk_category boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'suggested' CHECK (status IN (
    'suggested', 'needs_review', 'approved', 'rejected',
    'expert_review_requested', 'developer_needed', 'ready_to_publish', 'completed')),
  is_current boolean NOT NULL DEFAULT true,
  superseded_by uuid REFERENCES public.seo_recommendations(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_recommendations_website ON public.seo_recommendations (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_recommendations_workspace ON public.seo_recommendations (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_recommendations_run ON public.seo_recommendations (audit_run_id);
CREATE INDEX IF NOT EXISTS idx_seo_recommendations_issue ON public.seo_recommendations (issue_id);
CREATE INDEX IF NOT EXISTS idx_seo_recommendations_status ON public.seo_recommendations (status);
CREATE INDEX IF NOT EXISTS idx_seo_recommendations_current
  ON public.seo_recommendations (website_id) WHERE is_current;

-- Security-critical + integrity guard. When a row (recommendation or approval
-- item) is linked to an audit issue:
--   * the issue must exist and belong to the SAME workspace_id AND website_id
--     (else raise — no silent fallback / cross-workspace linkage);
--   * is_high_risk_category is forced from the issue's category (non-forgeable).
-- With no source issue: false on INSERT (on-page items are never a dangerous
-- technical category); on UPDATE the prior value is preserved (blocks tampering
-- and avoids downgrading if a source issue was later detached).
-- SECURITY DEFINER so the integrity/derivation reads the real issue regardless
-- of the writer's RLS visibility. Reused by seo_approval_items in migration 6.
CREATE OR REPLACE FUNCTION public.seo_set_hrc_from_issue()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iws uuid;
  v_iweb uuid;
  v_hrc boolean;
BEGIN
  IF NEW.issue_id IS NOT NULL THEN
    SELECT workspace_id, website_id, public.seo_is_high_risk_category(category)
      INTO v_iws, v_iweb, v_hrc
    FROM public.seo_audit_issues WHERE id = NEW.issue_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked audit issue % does not exist', NEW.issue_id;
    END IF;
    IF v_iws <> NEW.workspace_id OR v_iweb <> NEW.website_id THEN
      RAISE EXCEPTION 'Linked audit issue % belongs to a different workspace/website', NEW.issue_id;
    END IF;
    NEW.is_high_risk_category := v_hrc;
  ELSIF TG_OP = 'INSERT' THEN
    NEW.is_high_risk_category := false;
  ELSE
    NEW.is_high_risk_category := OLD.is_high_risk_category;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_recommendations_hrc ON public.seo_recommendations;
CREATE TRIGGER trg_seo_recommendations_hrc BEFORE INSERT OR UPDATE ON public.seo_recommendations
  FOR EACH ROW EXECUTE FUNCTION public.seo_set_hrc_from_issue();

DROP TRIGGER IF EXISTS trg_seo_recommendations_updated_at ON public.seo_recommendations;
CREATE TRIGGER trg_seo_recommendations_updated_at BEFORE UPDATE ON public.seo_recommendations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- seo_supersede_recommendation(old, new) — safely retire an old recommendation
-- in favor of a new one (same website). SECURITY DEFINER; used by the audit
-- regeneration flow (service role) or a workspace manager. Never deletes.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_supersede_recommendation(p_old_id uuid, p_new_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_ws uuid;
  v_old_web uuid;
  v_new_web uuid;
BEGIN
  SELECT workspace_id, website_id INTO v_old_ws, v_old_web
  FROM public.seo_recommendations WHERE id = p_old_id;
  SELECT website_id INTO v_new_web
  FROM public.seo_recommendations WHERE id = p_new_id;

  IF v_old_ws IS NULL OR v_new_web IS NULL THEN
    RAISE EXCEPTION 'Recommendation not found';
  END IF;
  IF v_old_web <> v_new_web THEN
    RAISE EXCEPTION 'Cannot supersede across different websites';
  END IF;
  IF NOT (public.seo_role_in(v_old_ws, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not permitted to supersede recommendations in this workspace';
  END IF;

  UPDATE public.seo_recommendations
    SET is_current = false, superseded_by = p_new_id, updated_at = now()
  WHERE id = p_old_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seo_supersede_recommendation(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS — recommendations. Read: member. Write: owner/admin/team_member + global
-- admin (system-generated; clients cannot insert/update/delete). Service role
-- bypasses RLS for generation.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_recommendations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_recommendations_select ON public.seo_recommendations;
CREATE POLICY seo_recommendations_select ON public.seo_recommendations
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_recommendations_write ON public.seo_recommendations;
CREATE POLICY seo_recommendations_write ON public.seo_recommendations
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
