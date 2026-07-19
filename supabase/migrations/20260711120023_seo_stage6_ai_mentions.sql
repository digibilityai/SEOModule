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
