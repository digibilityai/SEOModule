-- =============================================================================
-- SEO Backend — Stage 2 (Phase 12E) — Migration 6 of 6: Approval queue
-- =============================================================================
-- Additive only. Approval items (1 per recommendation), append-only comments +
-- activity, and the role-aware seo_approval_transition() RPC. No live-publish
-- path for any role. Depends on migrations 4 & 5.
-- =============================================================================

-- Helper: caller's active SEO role in a workspace (or null). SECURITY DEFINER
-- → bypasses RLS on seo_workspace_members (no policy recursion).
CREATE OR REPLACE FUNCTION public.seo_role_of(ws_id uuid, uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT seo_role FROM public.seo_workspace_members
  WHERE workspace_id = ws_id AND user_id = uid AND status = 'active'
  LIMIT 1;
$$;

-- ===========================================================================
-- seo_approval_items — one per recommendation (UNIQUE recommendation_id).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_approval_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  recommendation_id uuid NOT NULL UNIQUE REFERENCES public.seo_recommendations(id) ON DELETE CASCADE,
  issue_id uuid REFERENCES public.seo_audit_issues(id) ON DELETE SET NULL,
  title text NOT NULL,
  page_url text,
  simple_explanation text NOT NULL,
  suggested_change text NOT NULL,
  action_type text NOT NULL CHECK (action_type IN (
    'auto_suggest', 'approval_required', 'manual_support', 'expert_review', 'avoid')),
  impact text NOT NULL CHECK (impact IN ('low', 'medium', 'high')),
  effort text NOT NULL CHECK (effort IN ('low', 'medium', 'high')),
  risk text NOT NULL CHECK (risk IN ('low', 'medium', 'high')),
  confidence_percentage integer NOT NULL DEFAULT 0 CHECK (confidence_percentage BETWEEN 0 AND 100),
  fix_owner text NOT NULL CHECK (fix_owner IN (
    'client_action', 'developer_needed', 'digibility_expert', 'system_suggestion')),
  is_high_risk_category boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'suggested' CHECK (status IN (
    'suggested', 'needs_review', 'approved', 'rejected',
    'expert_review_requested', 'developer_needed', 'ready_to_publish', 'completed')),
  assignee_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,  -- placeholder; no assignment flow yet
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_approval_items_website ON public.seo_approval_items (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_approval_items_workspace ON public.seo_approval_items (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_approval_items_status ON public.seo_approval_items (status);
CREATE INDEX IF NOT EXISTS idx_seo_approval_items_highrisk ON public.seo_approval_items (is_high_risk_category);

-- ===========================================================================
-- seo_approval_comments — append-only. actor_role_snapshot = role at the time.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_approval_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  approval_item_id uuid NOT NULL REFERENCES public.seo_approval_items(id) ON DELETE CASCADE,
  author_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,  -- nullable so history survives user deletion
  actor_role_snapshot text NOT NULL,
  comment_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_approval_comments_item ON public.seo_approval_comments (approval_item_id);
CREATE INDEX IF NOT EXISTS idx_seo_approval_comments_workspace ON public.seo_approval_comments (workspace_id);

-- ===========================================================================
-- seo_approval_activity — append-only status/action timeline.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_approval_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                              -- snapshot
  approval_item_id uuid NOT NULL REFERENCES public.seo_approval_items(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role_snapshot text NOT NULL,
  activity_type text NOT NULL CHECK (activity_type IN (
    'created', 'status_changed', 'comment_added', 'edited',
    'expert_review_requested', 'developer_needed', 'completed', 'reassigned')),
  from_status text,
  to_status text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_approval_activity_item ON public.seo_approval_activity (approval_item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_approval_activity_workspace ON public.seo_approval_activity (workspace_id);

-- Security-critical: same derive-from-issue guard as recommendations — forces
-- is_high_risk_category from the linked issue (non-forgeable), enforces the
-- linked issue is in the same workspace/website (raises otherwise), so the
-- client/team_member high-risk gate + RLS cannot be bypassed.
-- (Reuses public.seo_set_hrc_from_issue() from migration 5.)
DROP TRIGGER IF EXISTS trg_seo_approval_items_hrc ON public.seo_approval_items;
CREATE TRIGGER trg_seo_approval_items_hrc BEFORE INSERT OR UPDATE ON public.seo_approval_items
  FOR EACH ROW EXECUTE FUNCTION public.seo_set_hrc_from_issue();

DROP TRIGGER IF EXISTS trg_seo_approval_items_updated_at ON public.seo_approval_items;
CREATE TRIGGER trg_seo_approval_items_updated_at BEFORE UPDATE ON public.seo_approval_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- seo_approval_transition(item, action, comment) — the sanctioned status path.
-- Enforces the approved role/risk matrix, mirrors status onto the linked
-- recommendation, logs activity, and optionally appends a comment. No action
-- performs a live website change. SECURITY DEFINER; membership/role verified.
-- Allowed actions: approve | reject | expert_review | developer_needed |
-- completed | comment. (Editing suggested_change is a direct RLS-gated UPDATE,
-- not a transition — clients have no UPDATE.)
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.seo_approval_transition(
  p_approval_item_id uuid,
  p_action text,
  p_comment text DEFAULT NULL
)
RETURNS TABLE (approval_item_id uuid, new_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_web uuid;
  v_url text;
  v_rec uuid;
  v_status text;
  v_risk text;
  v_hrc boolean;
  v_atype text;
  v_role text;
  v_is_admin boolean;
  v_can_all boolean;
  v_high_risk boolean;
  v_dangerous boolean;
  v_low_simple boolean;
  v_snap text;
  v_target text := NULL;
  v_activity text;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT workspace_id, website_id, website_url, recommendation_id, status, risk, is_high_risk_category, action_type
    INTO v_ws, v_web, v_url, v_rec, v_status, v_risk, v_hrc, v_atype
  FROM public.seo_approval_items WHERE id = p_approval_item_id;

  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Approval item not found: %', p_approval_item_id;
  END IF;

  v_role := public.seo_role_of(v_ws, v_uid);
  v_is_admin := public.seo_is_global_admin(v_uid);
  IF v_role IS NULL AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Not a member of this workspace';
  END IF;

  v_can_all := v_is_admin OR v_role IN ('owner', 'admin');
  -- v_high_risk: general "not a simple/low item" (used for client send-to-developer).
  -- v_dangerous: the set a team_member must NOT approve = high risk OR a dangerous
  -- technical category (URLs/redirects/canonical/noindex/robots.txt/sitemap).
  -- team_member may approve low AND medium risk that are not dangerous categories.
  v_high_risk := (v_risk <> 'low') OR v_hrc;
  v_dangerous := (v_risk = 'high') OR v_hrc;
  v_low_simple := (v_risk = 'low') AND (NOT v_hrc) AND (v_atype IN ('auto_suggest', 'manual_support'));
  v_snap := COALESCE(v_role, 'global_admin');

  IF p_action = 'comment' THEN
    IF v_comment IS NULL THEN
      RAISE EXCEPTION 'Comment text required';
    END IF;
    -- any active member (incl. client) may comment; no status change.
  ELSIF p_action = 'approve' THEN
    -- team_member: low + medium risk OK; blocked on high risk or dangerous
    -- technical category. client: only low-risk simple.
    IF NOT (v_can_all
            OR (v_role = 'team_member' AND NOT v_dangerous)
            OR (v_role = 'client' AND v_low_simple)) THEN
      RAISE EXCEPTION 'Not permitted: % cannot approve this item%',
        v_snap,
        CASE WHEN v_dangerous THEN ' (high-risk — use Request Expert Review or Send to Developer)'
             WHEN v_high_risk THEN ' (needs a higher role — use Request Expert Review or Send to Developer)'
             ELSE '' END;
    END IF;
    v_target := 'approved'; v_activity := 'status_changed';
  ELSIF p_action = 'reject' THEN
    IF NOT (v_can_all
            OR v_role = 'team_member'
            OR (v_role = 'client' AND v_low_simple)) THEN
      RAISE EXCEPTION 'Not permitted: % cannot reject this item', v_snap;
    END IF;
    v_target := 'rejected'; v_activity := 'status_changed';
  ELSIF p_action = 'expert_review' THEN
    IF NOT (v_can_all OR v_role IN ('team_member', 'client')) THEN
      RAISE EXCEPTION 'Not permitted';
    END IF;
    v_target := 'expert_review_requested'; v_activity := 'expert_review_requested';
  ELSIF p_action = 'developer_needed' THEN
    IF NOT (v_can_all
            OR v_role = 'team_member'
            OR (v_role = 'client' AND v_high_risk)) THEN
      RAISE EXCEPTION 'Not permitted: clients can only send high-risk items to a developer';
    END IF;
    v_target := 'developer_needed'; v_activity := 'developer_needed';
  ELSIF p_action = 'completed' THEN
    IF NOT v_can_all THEN
      RAISE EXCEPTION 'Only owner/admin can mark an item completed';
    END IF;
    v_target := 'completed'; v_activity := 'completed';
  ELSE
    RAISE EXCEPTION 'Unknown action: %', p_action;
  END IF;

  -- Apply status change (mirror onto the linked recommendation) + log activity.
  IF v_target IS NOT NULL THEN
    UPDATE public.seo_approval_items
      SET status = v_target, updated_at = now()
    WHERE id = p_approval_item_id;

    UPDATE public.seo_recommendations
      SET status = v_target, updated_at = now()
    WHERE id = v_rec;

    INSERT INTO public.seo_approval_activity (
      workspace_id, website_id, website_url, approval_item_id, actor_user_id,
      actor_role_snapshot, activity_type, from_status, to_status, note
    ) VALUES (
      v_ws, v_web, v_url, p_approval_item_id, v_uid, v_snap, v_activity, v_status, v_target, v_comment
    );
  END IF;

  -- Optional/required comment.
  IF v_comment IS NOT NULL THEN
    INSERT INTO public.seo_approval_comments (
      workspace_id, website_id, website_url, approval_item_id, author_user_id, actor_role_snapshot, comment_text
    ) VALUES (
      v_ws, v_web, v_url, p_approval_item_id, v_uid, v_snap, v_comment
    );
    IF v_target IS NULL THEN
      INSERT INTO public.seo_approval_activity (
        workspace_id, website_id, website_url, approval_item_id, actor_user_id,
        actor_role_snapshot, activity_type, from_status, to_status, note
      ) VALUES (
        v_ws, v_web, v_url, p_approval_item_id, v_uid, v_snap, 'comment_added', v_status, v_status, v_comment
      );
    END IF;
  END IF;

  approval_item_id := p_approval_item_id;
  new_status := COALESCE(v_target, v_status);
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seo_approval_transition(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS — approval items. Read: member. Insert: owner/admin/team_member (+ admin)
-- — generated from recommendations, clients cannot create. Update: RPC is the
-- primary path (SECURITY DEFINER bypasses RLS); direct UPDATE is defense-in-
-- depth for owner/admin/team_member edits, with team_member status guardrails.
-- Clients have NO direct UPDATE (must use the RPC for their allowed actions).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_approval_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_approval_items_select ON public.seo_approval_items;
CREATE POLICY seo_approval_items_select ON public.seo_approval_items
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_approval_items_insert ON public.seo_approval_items;
CREATE POLICY seo_approval_items_insert ON public.seo_approval_items
  FOR INSERT WITH CHECK (
    public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member'])
    OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_approval_items_update ON public.seo_approval_items;
CREATE POLICY seo_approval_items_update ON public.seo_approval_items
  FOR UPDATE
  USING (
    public.seo_is_global_admin()
    OR public.seo_role_of(workspace_id) IN ('owner', 'admin', 'team_member')
  )
  WITH CHECK (
    public.seo_is_global_admin()
    OR public.seo_role_of(workspace_id) IN ('owner', 'admin')
    OR (
      -- team_member: may approve low/medium; never mark completed; never approve
      -- a high-risk or dangerous-technical-category item.
      public.seo_role_of(workspace_id) = 'team_member'
      AND status <> 'completed'
      AND NOT (status = 'approved' AND (risk = 'high' OR is_high_risk_category))
    )
  );

DROP POLICY IF EXISTS seo_approval_items_delete ON public.seo_approval_items;
CREATE POLICY seo_approval_items_delete ON public.seo_approval_items
  FOR DELETE USING (public.can_manage_seo_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- RLS — approval comments. Append-only: SELECT + INSERT policies only, NO
-- update/delete policy (so updates/deletes are denied for everyone).
-- Any active member (incl. client) may add a comment as themselves.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_approval_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_approval_comments_select ON public.seo_approval_comments;
CREATE POLICY seo_approval_comments_select ON public.seo_approval_comments
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_approval_comments_insert ON public.seo_approval_comments;
CREATE POLICY seo_approval_comments_insert ON public.seo_approval_comments
  FOR INSERT WITH CHECK (
    (author_user_id = auth.uid() AND public.is_seo_workspace_member(workspace_id))
    OR public.seo_is_global_admin()
  );

-- ---------------------------------------------------------------------------
-- RLS — approval activity. Append-only. Written primarily by the RPC (definer
-- bypass). Direct insert limited to owner/admin/team_member acting as self
-- (clients cannot forge activity). NO update/delete policy.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_approval_activity ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_approval_activity_select ON public.seo_approval_activity;
CREATE POLICY seo_approval_activity_select ON public.seo_approval_activity
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

DROP POLICY IF EXISTS seo_approval_activity_insert ON public.seo_approval_activity;
CREATE POLICY seo_approval_activity_insert ON public.seo_approval_activity
  FOR INSERT WITH CHECK (
    (actor_user_id = auth.uid()
      AND public.seo_role_of(workspace_id) IN ('owner', 'admin', 'team_member'))
    OR public.seo_is_global_admin()
  );
