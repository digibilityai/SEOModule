-- =============================================================================
-- SEO Backend — Stage 3 (Phase 12G) — Migration 7 of 9: Content Studio (plan layer)
-- =============================================================================
-- Additive only. Content opportunity/brief anchor + keyword plan + competitor
-- summaries + wireframe + format input. Builds on Stage 1 (workspaces/websites
-- + helpers) and Stage 2 (conventions). No LLM, no CMS, no publishing.
-- website_id = source of truth; website_url = snapshot. Does not touch Stage 1/2.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Integrity guard: any content child row that carries content_opportunity_id
-- must belong to the SAME workspace_id + website_id as that opportunity
-- (raises otherwise; no silent/cross-workspace linkage). SECURITY DEFINER so
-- it reads the parent regardless of the writer's RLS visibility. Reused by the
-- draft/asset migrations. Nullable content_opportunity_id (workspace-level
-- assets) is skipped.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_content_assert_same_workspace()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ws uuid;
  v_web uuid;
BEGIN
  IF NEW.content_opportunity_id IS NOT NULL THEN
    SELECT workspace_id, website_id INTO v_ws, v_web
    FROM public.seo_content_opportunities WHERE id = NEW.content_opportunity_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked content opportunity % does not exist', NEW.content_opportunity_id;
    END IF;
    IF v_ws <> NEW.workspace_id OR v_web <> NEW.website_id THEN
      RAISE EXCEPTION 'Linked content opportunity % belongs to a different workspace/website', NEW.content_opportunity_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ===========================================================================
-- seo_content_opportunities — content item / brief anchor + workflow status.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_opportunities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  title text NOT NULL,
  target_keyword text NOT NULL,
  content_type text NOT NULL DEFAULT 'blog_post'
    CHECK (content_type IN ('blog_post', 'landing_page', 'service_page', 'faq', 'guide', 'other')),
  search_intent text CHECK (search_intent IN ('informational', 'navigational', 'transactional', 'commercial')),
  funnel_stage text CHECK (funnel_stage IN ('awareness', 'consideration', 'conversion')),
  difficulty text CHECK (difficulty IN ('low', 'medium', 'high')),
  opportunity_score integer NOT NULL DEFAULT 0 CHECK (opportunity_score BETWEEN 0 AND 100),
  reason text,
  brief_notes text,
  is_custom boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'idea' CHECK (status IN (
    'idea', 'plan_ready',
    'wireframe_in_progress', 'wireframe_internal_review', 'wireframe_client_review',
    'wireframe_changes_requested', 'wireframe_approved',
    'draft_in_progress', 'draft_internal_review', 'draft_client_review',
    'draft_changes_requested', 'draft_approved',
    'ready_for_manual_publish', 'archived')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_opp_ws_status ON public.seo_content_opportunities (workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_seo_content_opp_website ON public.seo_content_opportunities (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_opp_keyword ON public.seo_content_opportunities (target_keyword);
CREATE INDEX IF NOT EXISTS idx_seo_content_opp_type ON public.seo_content_opportunities (content_type);
CREATE INDEX IF NOT EXISTS idx_seo_content_opp_created ON public.seo_content_opportunities (created_at DESC);

-- ===========================================================================
-- seo_content_keyword_plans — 1:1 keyword plan.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_keyword_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL UNIQUE REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  primary_keyword text NOT NULL,
  secondary_keywords text[] NOT NULL DEFAULT '{}',
  semantic_keywords text[] NOT NULL DEFAULT '{}',
  question_keywords text[] NOT NULL DEFAULT '{}',
  intent text CHECK (intent IN ('informational', 'navigational', 'transactional', 'commercial')),
  difficulty text CHECK (difficulty IN ('low', 'medium', 'high')),
  business_relevance text,
  why_it_matters text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_kw_opp ON public.seo_content_keyword_plans (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_kw_ws ON public.seo_content_keyword_plans (workspace_id);

-- ===========================================================================
-- seo_content_competitor_summaries — n per opportunity.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_competitor_summaries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  competitor_title text,
  competitor_url text,
  what_they_covered text,
  what_they_missed text,
  our_opportunity text,
  content_gap_angle text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_comp_opp ON public.seo_content_competitor_summaries (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_comp_ws ON public.seo_content_competitor_summaries (workspace_id);

-- ===========================================================================
-- seo_content_wireframes — 1:1 wireframe + approval snapshot.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_wireframes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL UNIQUE REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  suggested_h1 text,
  intro_angle text,
  cta_suggestion text,
  section_outline text[] NOT NULL DEFAULT '{}',
  faq_section text[] NOT NULL DEFAULT '{}',
  internal_link_suggestions text[] NOT NULL DEFAULT '{}',
  schema_suggestion text,
  is_approved boolean NOT NULL DEFAULT false,
  approved_at timestamptz,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_wf_opp ON public.seo_content_wireframes (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_wf_ws ON public.seo_content_wireframes (workspace_id);

-- ===========================================================================
-- seo_content_format_inputs — 1:1 format/tone/reference input.
-- asset_id FK is added in migration 9 (forward-ref to seo_content_assets).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_format_inputs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL UNIQUE REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  format_type text NOT NULL DEFAULT 'default'
    CHECK (format_type IN ('default', 'url_reference', 'file_reference', 'match_brand_style', 'custom_instructions')),
  reference_url text,
  custom_instructions text,
  asset_id uuid,                                     -- FK added in migration 9
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_fmt_opp ON public.seo_content_format_inputs (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_fmt_ws ON public.seo_content_format_inputs (workspace_id);

-- ---------------------------------------------------------------------------
-- Triggers: updated_at on all + same-workspace guard on children.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_content_opp_updated_at ON public.seo_content_opportunities;
CREATE TRIGGER trg_seo_content_opp_updated_at BEFORE UPDATE ON public.seo_content_opportunities
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_content_kw_updated_at ON public.seo_content_keyword_plans;
CREATE TRIGGER trg_seo_content_kw_updated_at BEFORE UPDATE ON public.seo_content_keyword_plans
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trg_seo_content_kw_samews ON public.seo_content_keyword_plans;
CREATE TRIGGER trg_seo_content_kw_samews BEFORE INSERT OR UPDATE ON public.seo_content_keyword_plans
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

DROP TRIGGER IF EXISTS trg_seo_content_comp_updated_at ON public.seo_content_competitor_summaries;
CREATE TRIGGER trg_seo_content_comp_updated_at BEFORE UPDATE ON public.seo_content_competitor_summaries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trg_seo_content_comp_samews ON public.seo_content_competitor_summaries;
CREATE TRIGGER trg_seo_content_comp_samews BEFORE INSERT OR UPDATE ON public.seo_content_competitor_summaries
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

DROP TRIGGER IF EXISTS trg_seo_content_wf_updated_at ON public.seo_content_wireframes;
CREATE TRIGGER trg_seo_content_wf_updated_at BEFORE UPDATE ON public.seo_content_wireframes
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trg_seo_content_wf_samews ON public.seo_content_wireframes;
CREATE TRIGGER trg_seo_content_wf_samews BEFORE INSERT OR UPDATE ON public.seo_content_wireframes
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

DROP TRIGGER IF EXISTS trg_seo_content_fmt_updated_at ON public.seo_content_format_inputs;
CREATE TRIGGER trg_seo_content_fmt_updated_at BEFORE UPDATE ON public.seo_content_format_inputs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS trg_seo_content_fmt_samews ON public.seo_content_format_inputs;
CREATE TRIGGER trg_seo_content_fmt_samews BEFORE INSERT OR UPDATE ON public.seo_content_format_inputs
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

-- ---------------------------------------------------------------------------
-- RLS. Read: any workspace member (incl. client) — plan/wireframe are member-
-- readable at all stages. Write: owner/admin/team_member + global admin only
-- (clients never write; status changes go through the Stage-3 RPC). Service
-- role bypasses RLS for system generation.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'seo_content_opportunities','seo_content_keyword_plans','seo_content_competitor_summaries',
    'seo_content_wireframes','seo_content_format_inputs'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', t||'_select', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());',
      t||'_select', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', t||'_write', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL USING (public.seo_role_in(workspace_id, ARRAY[''owner'',''admin'',''team_member'']) OR public.seo_is_global_admin()) WITH CHECK (public.seo_role_in(workspace_id, ARRAY[''owner'',''admin'',''team_member'']) OR public.seo_is_global_admin());',
      t||'_write', t);
  END LOOP;
END $$;
