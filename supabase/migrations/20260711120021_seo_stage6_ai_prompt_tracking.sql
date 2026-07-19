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
