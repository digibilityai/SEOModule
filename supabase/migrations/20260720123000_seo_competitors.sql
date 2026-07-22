-- =============================================================================
-- SEO Backend — Competitor Benchmarking Stage 1 — Migration: seo_competitors
-- =============================================================================
-- Additive only. Introduces ONE new table, public.seo_competitors, the
-- persisted per-(workspace, website, competitor) benchmarking record the
-- Competitor Analysis UI reads.
--
-- SCOPE (Competitor Benchmarking Stage 1 — persisted READ foundation only):
--   * Persist competitor rows with workspace/website-scoped RLS (member SELECT
--     incl. client; owner/admin/team_member write) — same pattern as
--     seo_page_performance_snapshots.
--   * NO generation RPC, NO write path from a generation action, NO worker, NO
--     external competitor-data provider ships here. Rows are written by a future
--     Stage 2 generation path (or, in TEST, by the read-path verification
--     fixtures).
--
-- TRUTHFUL PROVENANCE (mandatory): competitor scores in this product are
--   *synthetic heuristic estimates* generated locally — they are NOT sourced
--   from SEMrush / Ahrefs / GSC or any external intelligence provider. The
--   `data_provenance` column is CHECK-constrained to 'estimated' so a persisted
--   row can never be mislabelled as live/measured/verified/observed/external.
--   `generation_method` optionally identifies the heuristic model version.
--
-- Does NOT touch any locked module, table, RPC, or contract. Additive new
-- table only.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.seo_competitors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                               -- snapshot; website_id is source of truth
  competitor_name text NOT NULL,
  competitor_url text NOT NULL,
  normalized_competitor_url text NOT NULL,                 -- host/path-normalized; uniqueness key
  business_category text,
  target_location text,
  content_strength_score integer NOT NULL DEFAULT 0 CHECK (content_strength_score BETWEEN 0 AND 100),
  technical_health_score integer NOT NULL DEFAULT 0 CHECK (technical_health_score BETWEEN 0 AND 100),
  authority_score integer NOT NULL DEFAULT 0 CHECK (authority_score BETWEEN 0 AND 100),
  ai_visibility_score integer NOT NULL DEFAULT 0 CHECK (ai_visibility_score BETWEEN 0 AND 100),
  review_strength_score integer NOT NULL DEFAULT 0 CHECK (review_strength_score BETWEEN 0 AND 100),
  overall_strength_score integer NOT NULL DEFAULT 0 CHECK (overall_strength_score BETWEEN 0 AND 100),
  status text NOT NULL DEFAULT 'unknown'
    CHECK (status IN ('stronger', 'similar', 'weaker', 'unknown')),
  what_they_do_better text[] NOT NULL DEFAULT '{}',
  what_they_are_missing text[] NOT NULL DEFAULT '{}',
  content_opportunities text[] NOT NULL DEFAULT '{}',
  authority_opportunities text[] NOT NULL DEFAULT '{}',
  ai_visibility_opportunities text[] NOT NULL DEFAULT '{}',
  suggested_next_action text NOT NULL DEFAULT '',
  -- Truthful provenance: these scores are heuristic ESTIMATES, never external
  -- measured data. Constrained to 'estimated' so nothing can be mislabelled.
  data_provenance text NOT NULL DEFAULT 'estimated'
    CHECK (data_provenance IN ('estimated')),
  generation_method text,                                  -- e.g. 'heuristic_v1'; identifies the estimate model
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- One row per website + normalized competitor URL (a website's competitor set
  -- is de-duplicated by the normalized URL).
  UNIQUE (website_id, normalized_competitor_url)
);

CREATE INDEX IF NOT EXISTS idx_seo_competitors_workspace ON public.seo_competitors (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_competitors_website ON public.seo_competitors (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_competitors_overall ON public.seo_competitors (website_id, overall_strength_score DESC);

-- ---------------------------------------------------------------------------
-- updated_at trigger (shared public.set_updated_at(), same as Stage 1 tables).
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_competitors_updated_at ON public.seo_competitors;
CREATE TRIGGER trg_seo_competitors_updated_at BEFORE UPDATE ON public.seo_competitors
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — same pattern as seo_page_performance_snapshots / seo_websites:
--   read  = any workspace member (incl. client) or global admin
--   write = owner/admin/team_member or global admin (client cannot write)
-- Table DML is granted to anon/authenticated by Supabase default privileges;
-- RLS is the authoritative gate. anon has no membership -> blocked by the
-- member-only SELECT policy.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_competitors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_competitors_select ON public.seo_competitors;
CREATE POLICY seo_competitors_select ON public.seo_competitors
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_competitors_write ON public.seo_competitors;
CREATE POLICY seo_competitors_write ON public.seo_competitors
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
