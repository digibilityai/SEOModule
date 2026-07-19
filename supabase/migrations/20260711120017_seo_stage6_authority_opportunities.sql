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
