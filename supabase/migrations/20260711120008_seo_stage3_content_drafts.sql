-- =============================================================================
-- SEO Backend — Stage 3 (Phase 12G) — Migration 8 of 9: Content Studio (drafts)
-- =============================================================================
-- Additive only. One current draft per opportunity + sections + append-only
-- section revision history (regeneration trail). Draft generation is a
-- service-role/system action; clients never write and see drafts only when the
-- opportunity is client-visible. Depends on migration 7.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Client draft-visibility helper. Managers (owner/admin/team_member) + global
-- admin see drafts at all stages; a client sees them only once the opportunity
-- reaches a client-visible draft status. Non-members see nothing. SECURITY
-- DEFINER → reads the opportunity regardless of the caller's RLS visibility.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_content_client_can_see_draft(p_opportunity_id uuid, uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.seo_is_global_admin(uid)
    OR EXISTS (
      SELECT 1 FROM public.seo_content_opportunities o
      WHERE o.id = p_opportunity_id
        AND (
          public.seo_role_in(o.workspace_id, ARRAY['owner', 'admin', 'team_member'], uid)
          OR (
            public.seo_role_of(o.workspace_id, uid) = 'client'
            AND o.status IN ('draft_client_review', 'draft_approved', 'ready_for_manual_publish', 'archived')
          )
        )
    );
$$;

-- ===========================================================================
-- seo_content_drafts — current draft (1:1 opportunity). No full versioning.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL UNIQUE REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  title text NOT NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_draft_opp ON public.seo_content_drafts (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_draft_ws ON public.seo_content_drafts (workspace_id);

-- ===========================================================================
-- seo_content_draft_sections — sections (current content).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_draft_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  draft_id uuid NOT NULL REFERENCES public.seo_content_drafts(id) ON DELETE CASCADE,
  content_opportunity_id uuid NOT NULL REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  position integer NOT NULL DEFAULT 0,
  heading text NOT NULL,
  content text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'generated' CHECK (status IN ('generated', 'approved', 'rejected', 'edited')),
  regeneration_count integer NOT NULL DEFAULT 0,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_sec_draft ON public.seo_content_draft_sections (draft_id, position);
CREATE INDEX IF NOT EXISTS idx_seo_content_sec_opp ON public.seo_content_draft_sections (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_sec_ws ON public.seo_content_draft_sections (workspace_id);

-- ===========================================================================
-- seo_content_section_revisions — append-only regeneration/rewrite history.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_section_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  draft_section_id uuid NOT NULL REFERENCES public.seo_content_draft_sections(id) ON DELETE CASCADE,
  content_opportunity_id uuid NOT NULL REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  revision_number integer NOT NULL,
  content text NOT NULL,
  reason text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_rev_section ON public.seo_content_section_revisions (draft_section_id, revision_number);
CREATE INDEX IF NOT EXISTS idx_seo_content_rev_opp ON public.seo_content_section_revisions (content_opportunity_id);

-- ---------------------------------------------------------------------------
-- Triggers: updated_at (non-append-only) + same-workspace guard.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_content_draft_updated_at ON public.seo_content_drafts;
CREATE TRIGGER trg_seo_content_draft_updated_at BEFORE UPDATE ON public.seo_content_drafts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trg_seo_content_draft_samews ON public.seo_content_drafts;
CREATE TRIGGER trg_seo_content_draft_samews BEFORE INSERT OR UPDATE ON public.seo_content_drafts
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

DROP TRIGGER IF EXISTS trg_seo_content_sec_updated_at ON public.seo_content_draft_sections;
CREATE TRIGGER trg_seo_content_sec_updated_at BEFORE UPDATE ON public.seo_content_draft_sections
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trg_seo_content_sec_samews ON public.seo_content_draft_sections;
CREATE TRIGGER trg_seo_content_sec_samews BEFORE INSERT OR UPDATE ON public.seo_content_draft_sections
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

DROP TRIGGER IF EXISTS trg_seo_content_rev_samews ON public.seo_content_section_revisions;
CREATE TRIGGER trg_seo_content_rev_samews BEFORE INSERT OR UPDATE ON public.seo_content_section_revisions
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

-- ---------------------------------------------------------------------------
-- RLS. Read: manager set at all stages; client only when the opportunity is
-- client-visible (helper). Write: owner/admin/team_member + global admin;
-- clients never write; service role bypasses. Revisions append-only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_content_drafts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_content_drafts_select ON public.seo_content_drafts;
CREATE POLICY seo_content_drafts_select ON public.seo_content_drafts
  FOR SELECT USING (public.seo_content_client_can_see_draft(content_opportunity_id));
DROP POLICY IF EXISTS seo_content_drafts_write ON public.seo_content_drafts;
CREATE POLICY seo_content_drafts_write ON public.seo_content_drafts
  FOR ALL
  USING (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin())
  WITH CHECK (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin());

ALTER TABLE public.seo_content_draft_sections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_content_sections_select ON public.seo_content_draft_sections;
CREATE POLICY seo_content_sections_select ON public.seo_content_draft_sections
  FOR SELECT USING (public.seo_content_client_can_see_draft(content_opportunity_id));
DROP POLICY IF EXISTS seo_content_sections_write ON public.seo_content_draft_sections;
CREATE POLICY seo_content_sections_write ON public.seo_content_draft_sections
  FOR ALL
  USING (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin())
  WITH CHECK (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin());

ALTER TABLE public.seo_content_section_revisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_content_rev_select ON public.seo_content_section_revisions;
CREATE POLICY seo_content_rev_select ON public.seo_content_section_revisions
  FOR SELECT USING (public.seo_content_client_can_see_draft(content_opportunity_id));
-- Append-only: INSERT policy only (manager set / service role); no update/delete.
DROP POLICY IF EXISTS seo_content_rev_insert ON public.seo_content_section_revisions;
CREATE POLICY seo_content_rev_insert ON public.seo_content_section_revisions
  FOR INSERT
  WITH CHECK (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin());
