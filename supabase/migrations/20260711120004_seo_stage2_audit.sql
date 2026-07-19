-- =============================================================================
-- SEO Backend — Stage 2 (Phase 12E) — Migration 4 of 6: Audit runs + issues
-- =============================================================================
-- Additive only. Builds on Stage 1 (seo_websites/workspaces + helpers).
-- Preserves audit history: every run is a new row; exactly one is_latest per
-- website. Client may TRIGGER an audit via seo_run_audit(); issues are written
-- later by the service role / system (never directly by clients).
-- No crawler, no LLM, no CMS writes. Does not touch Stage 1 or Core objects.
-- =============================================================================

-- Risk-category helper (immutable) — the categories where an automated change
-- could break indexing/navigation and therefore always need sign-off.
CREATE OR REPLACE FUNCTION public.seo_is_high_risk_category(cat text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT cat IN ('robots_txt', 'canonical', 'redirects', 'sitemap', 'indexability');
$$;

-- ===========================================================================
-- seo_audit_runs — one row per audit run (history preserved).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_audit_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot; website_id is source of truth
  frequency text NOT NULL DEFAULT 'monthly'
    CHECK (frequency IN ('monthly', 'weekly', 'weekly_plus_change_monitoring')),
  status text NOT NULL DEFAULT 'running'
    CHECK (status IN ('not_started', 'running', 'completed', 'failed')),
  overall_visibility_score integer NOT NULL DEFAULT 0 CHECK (overall_visibility_score BETWEEN 0 AND 100),
  technical_health_score integer NOT NULL DEFAULT 0 CHECK (technical_health_score BETWEEN 0 AND 100),
  onpage_score integer NOT NULL DEFAULT 0 CHECK (onpage_score BETWEEN 0 AND 100),
  authority_score integer NOT NULL DEFAULT 0 CHECK (authority_score BETWEEN 0 AND 100),
  ai_discovery_score integer NOT NULL DEFAULT 0 CHECK (ai_discovery_score BETWEEN 0 AND 100),
  issue_count integer NOT NULL DEFAULT 0,
  is_latest boolean NOT NULL DEFAULT false,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  error_message text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_audit_runs_website ON public.seo_audit_runs (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_audit_runs_workspace ON public.seo_audit_runs (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_audit_runs_started ON public.seo_audit_runs (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_audit_runs_status ON public.seo_audit_runs (status);
-- Enforces exactly one latest run per website + fast dashboard lookup.
CREATE UNIQUE INDEX IF NOT EXISTS uq_seo_audit_runs_latest
  ON public.seo_audit_runs (website_id) WHERE is_latest;

-- ===========================================================================
-- seo_audit_issues — issues found in a specific run (per-run snapshot).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_audit_issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  audit_run_id uuid NOT NULL REFERENCES public.seo_audit_runs(id) ON DELETE CASCADE,
  category text NOT NULL CHECK (category IN (
    'crawl', 'indexability', 'speed', 'mobile', 'schema', 'duplicate_content',
    'broken_links', 'sitemap', 'robots_txt', 'canonical', 'redirects')),
  severity text NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
  title text NOT NULL,
  simple_explanation text NOT NULL,
  why_it_matters text NOT NULL,
  technical_explanation text NOT NULL,
  affected_page_url text NOT NULL,
  impact text NOT NULL CHECK (impact IN ('low', 'medium', 'high')),
  effort text NOT NULL CHECK (effort IN ('low', 'medium', 'high')),
  risk text NOT NULL CHECK (risk IN ('low', 'medium', 'high')),
  confidence_percentage integer NOT NULL DEFAULT 0 CHECK (confidence_percentage BETWEEN 0 AND 100),
  fix_owner text NOT NULL CHECK (fix_owner IN (
    'client_action', 'developer_needed', 'digibility_expert', 'system_suggestion')),
  suggested_next_action text NOT NULL,
  is_high_risk_category boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'in_review', 'approved', 'fixed', 'ignored')),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_audit_issues_run ON public.seo_audit_issues (audit_run_id);
CREATE INDEX IF NOT EXISTS idx_seo_audit_issues_website ON public.seo_audit_issues (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_audit_issues_workspace ON public.seo_audit_issues (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_audit_issues_status ON public.seo_audit_issues (status);
CREATE INDEX IF NOT EXISTS idx_seo_audit_issues_severity ON public.seo_audit_issues (severity);
CREATE INDEX IF NOT EXISTS idx_seo_audit_issues_highrisk ON public.seo_audit_issues (is_high_risk_category);

-- ---------------------------------------------------------------------------
-- Security-critical: force is_high_risk_category to the correct value derived
-- from the issue category, so the client high-risk approval gate cannot be
-- bypassed by a generator writing a wrong flag. Deterministic; overrides any
-- provided value.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_set_hrc_from_category()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.is_high_risk_category := public.seo_is_high_risk_category(NEW.category);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_audit_issues_hrc ON public.seo_audit_issues;
CREATE TRIGGER trg_seo_audit_issues_hrc BEFORE INSERT OR UPDATE ON public.seo_audit_issues
  FOR EACH ROW EXECUTE FUNCTION public.seo_set_hrc_from_category();

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_audit_runs_updated_at ON public.seo_audit_runs;
CREATE TRIGGER trg_seo_audit_runs_updated_at BEFORE UPDATE ON public.seo_audit_runs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_audit_issues_updated_at ON public.seo_audit_issues;
CREATE TRIGGER trg_seo_audit_issues_updated_at BEFORE UPDATE ON public.seo_audit_issues
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- seo_run_audit(p_website_id) — client-callable audit trigger.
-- Creates the run row (status='running'); does NOT create issues/recs (those
-- are written by the service role / system afterwards). SECURITY DEFINER so a
-- client can trigger it, but membership is verified inside.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_run_audit(p_website_id uuid)
RETURNS TABLE (audit_run_id uuid, run_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_url text;
  v_freq text;
  v_new_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT w.workspace_id, w.website_url, ws.plan_tier
    INTO v_ws, v_url, v_freq
  FROM public.seo_websites w
  JOIN public.seo_workspaces ws ON ws.id = w.workspace_id
  WHERE w.id = p_website_id;

  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Website not found: %', p_website_id;
  END IF;

  -- Any active workspace member (owner/admin/team_member/client) or global admin.
  IF NOT (public.is_seo_workspace_member(v_ws, v_uid) OR public.seo_is_global_admin(v_uid)) THEN
    RAISE EXCEPTION 'Not a member of this website''s workspace';
  END IF;

  -- Map plan tier → default audit frequency (best-effort; not enforcement).
  v_freq := CASE v_freq
    WHEN 'pro' THEN 'weekly_plus_change_monitoring'
    WHEN 'standard' THEN 'weekly'
    ELSE 'monthly' END;

  -- Only one latest per website: clear prior latest first, then insert new one.
  UPDATE public.seo_audit_runs
    SET is_latest = false, updated_at = now()
  WHERE website_id = p_website_id AND is_latest;

  INSERT INTO public.seo_audit_runs (
    workspace_id, website_id, website_url, frequency, status, is_latest, started_at, created_by
  ) VALUES (
    v_ws, p_website_id, v_url, v_freq, 'running', true, now(), v_uid
  )
  RETURNING id INTO v_new_id;

  audit_run_id := v_new_id;
  run_status := 'running';
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seo_run_audit(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS — audit runs. Read: any workspace member (incl client). Direct write:
-- owner/admin/team_member (+ global admin); clients trigger via RPC only.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_audit_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_audit_runs_select ON public.seo_audit_runs;
CREATE POLICY seo_audit_runs_select ON public.seo_audit_runs
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_audit_runs_insert ON public.seo_audit_runs;
CREATE POLICY seo_audit_runs_insert ON public.seo_audit_runs
  FOR INSERT WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_audit_runs_update ON public.seo_audit_runs;
CREATE POLICY seo_audit_runs_update ON public.seo_audit_runs
  FOR UPDATE USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_audit_runs_delete ON public.seo_audit_runs;
CREATE POLICY seo_audit_runs_delete ON public.seo_audit_runs
  FOR DELETE USING (public.can_manage_seo_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- RLS — audit issues. Read: member. Write: owner/admin/team_member + global
-- admin only (system-generated; clients CANNOT insert/update/delete issues).
-- Service role bypasses RLS for the actual generation.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_audit_issues ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_audit_issues_select ON public.seo_audit_issues;
CREATE POLICY seo_audit_issues_select ON public.seo_audit_issues
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_audit_issues_write ON public.seo_audit_issues;
CREATE POLICY seo_audit_issues_write ON public.seo_audit_issues
  FOR ALL
  USING (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  ) WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );
