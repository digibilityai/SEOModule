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
