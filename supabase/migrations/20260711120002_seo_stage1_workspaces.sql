-- =============================================================================
-- SEO Backend — Stage 1 (Phase 12C) — Migration 2 of 3: SEO Workspace layer
-- =============================================================================
-- Additive only. Temporary SEO workspace/membership tables (Core has no
-- workspace model yet). Nullable core_workspace_id / core_profile_id let this
-- merge into a future Core workspace model with no data migration.
--
-- SEO roles (owner | admin | team_member | client) live here — NOT on
-- profiles.role. A user may hold different SEO roles in different workspaces.
-- Depends on migration 1 (public.set_updated_at, public.seo_is_global_admin,
-- public.has_seo_module_access, public.seo_subscriptions, public.seo_usage_events).
-- =============================================================================

-- ===========================================================================
-- seo_workspaces — tenant boundary for SEO. Owner is a real auth user.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_tier text NOT NULL DEFAULT 'basic'
    REFERENCES public.seo_plan_limits(plan_tier) ON UPDATE CASCADE,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'archived')),
  core_workspace_id uuid,   -- future Core workspace mapping (nullable seam)
  core_profile_id uuid,     -- future Core profile mapping (nullable seam)
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_workspaces_owner ON public.seo_workspaces (owner_user_id);
CREATE INDEX IF NOT EXISTS idx_seo_workspaces_status ON public.seo_workspaces (status);
CREATE INDEX IF NOT EXISTS idx_seo_workspaces_core ON public.seo_workspaces (core_workspace_id);

-- ===========================================================================
-- seo_workspace_members — user ↔ workspace with SEO role.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_workspace_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seo_role text NOT NULL CHECK (seo_role IN ('owner', 'admin', 'team_member', 'client')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'invited', 'suspended', 'removed')),
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_seo_workspace_members_ws ON public.seo_workspace_members (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_workspace_members_user ON public.seo_workspace_members (user_id);
CREATE INDEX IF NOT EXISTS idx_seo_workspace_members_role ON public.seo_workspace_members (workspace_id, seo_role);

-- ---------------------------------------------------------------------------
-- Forward-reference FKs from migration 1 (added now that seo_workspaces exists).
-- Idempotent via pg_constraint guard.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seo_subscriptions_workspace_fk') THEN
    ALTER TABLE public.seo_subscriptions
      ADD CONSTRAINT seo_subscriptions_workspace_fk
      FOREIGN KEY (workspace_id) REFERENCES public.seo_workspaces(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seo_usage_events_workspace_fk') THEN
    ALTER TABLE public.seo_usage_events
      ADD CONSTRAINT seo_usage_events_workspace_fk
      FOREIGN KEY (workspace_id) REFERENCES public.seo_workspaces(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Membership helpers (SECURITY DEFINER → bypass RLS, avoid policy recursion).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_seo_workspace_member(ws_id uuid, uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.seo_workspace_members
    WHERE workspace_id = ws_id AND user_id = uid AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.seo_role_in(ws_id uuid, roles text[], uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.seo_workspace_members
    WHERE workspace_id = ws_id AND user_id = uid AND status = 'active'
      AND seo_role = ANY(roles)
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_seo_workspace(ws_id uuid, uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.seo_role_in(ws_id, ARRAY['owner', 'admin'], uid)
      OR public.seo_is_global_admin(uid);
$$;

-- ---------------------------------------------------------------------------
-- Owner bootstrap: auto-create the owner's membership row when a workspace is
-- created. Without this, a non-admin owner hits an RLS deadlock — membership
-- writes require an existing owner/admin member row, which they cannot create.
-- Mirrors Core's handle_new_user() SECURITY DEFINER auto-row convention.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_workspace_add_owner_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status, invited_by)
  VALUES (NEW.id, NEW.owner_user_id, 'owner', 'active', NEW.owner_user_id)
  ON CONFLICT (workspace_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_workspaces_add_owner_member ON public.seo_workspaces;
CREATE TRIGGER trg_seo_workspaces_add_owner_member AFTER INSERT ON public.seo_workspaces
  FOR EACH ROW EXECUTE FUNCTION public.seo_workspace_add_owner_member();

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_workspaces_updated_at ON public.seo_workspaces;
CREATE TRIGGER trg_seo_workspaces_updated_at BEFORE UPDATE ON public.seo_workspaces
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_workspace_members_updated_at ON public.seo_workspace_members;
CREATE TRIGGER trg_seo_workspace_members_updated_at BEFORE UPDATE ON public.seo_workspace_members
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS — seo_workspaces
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_workspaces ENABLE ROW LEVEL SECURITY;

-- owner_user_id is included so INSERT ... RETURNING works for the creator
-- (and the owner always sees their own workspace) independent of the
-- owner-member bootstrap trigger's timing.
DROP POLICY IF EXISTS seo_workspaces_select ON public.seo_workspaces;
CREATE POLICY seo_workspaces_select ON public.seo_workspaces
  FOR SELECT USING (
    owner_user_id = auth.uid()
    OR public.is_seo_workspace_member(id)
    OR public.seo_is_global_admin()
  );

-- Creator must have SEO access and be recorded as owner; or global admin.
DROP POLICY IF EXISTS seo_workspaces_insert ON public.seo_workspaces;
CREATE POLICY seo_workspaces_insert ON public.seo_workspaces
  FOR INSERT WITH CHECK (
    (public.has_seo_module_access() AND owner_user_id = auth.uid())
    OR public.seo_is_global_admin()
  );

-- Owner/admin (or global admin) can update the workspace.
DROP POLICY IF EXISTS seo_workspaces_update ON public.seo_workspaces;
CREATE POLICY seo_workspaces_update ON public.seo_workspaces
  FOR UPDATE USING (public.can_manage_seo_workspace(id))
  WITH CHECK (public.can_manage_seo_workspace(id));

-- Only owner (or global admin) can delete/archive at row level.
DROP POLICY IF EXISTS seo_workspaces_delete ON public.seo_workspaces;
CREATE POLICY seo_workspaces_delete ON public.seo_workspaces
  FOR DELETE USING (
    public.seo_role_in(id, ARRAY['owner']) OR public.seo_is_global_admin()
  );

-- ---------------------------------------------------------------------------
-- RLS — seo_workspace_members
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_workspace_members ENABLE ROW LEVEL SECURITY;

-- Any active member of the workspace can see the member list.
DROP POLICY IF EXISTS seo_workspace_members_select ON public.seo_workspace_members;
CREATE POLICY seo_workspace_members_select ON public.seo_workspace_members
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );

-- Only owner/admin (or global admin) manage membership. Clients cannot.
DROP POLICY IF EXISTS seo_workspace_members_write ON public.seo_workspace_members;
CREATE POLICY seo_workspace_members_write ON public.seo_workspace_members
  FOR ALL
  USING (public.can_manage_seo_workspace(workspace_id))
  WITH CHECK (public.can_manage_seo_workspace(workspace_id));

-- ---------------------------------------------------------------------------
-- Extend seo_subscriptions RLS: workspace owner/admin may also view a
-- workspace-linked subscription (read-only add-on to migration 1 policy).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS seo_subscriptions_ws_manager_select ON public.seo_subscriptions;
CREATE POLICY seo_subscriptions_ws_manager_select ON public.seo_subscriptions
  FOR SELECT USING (
    workspace_id IS NOT NULL AND public.can_manage_seo_workspace(workspace_id)
  );
