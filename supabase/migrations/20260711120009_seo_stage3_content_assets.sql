-- =============================================================================
-- SEO Backend — Stage 3 (Phase 12G) — Migration 9 of 9: comments/activity/
-- assets + private Storage bucket + seo_content_transition RPC
-- =============================================================================
-- Additive only. Append-only comments + activity; file METADATA only (bytes in
-- a private Supabase Storage bucket); the workflow-transition RPC enforcing the
-- locked status→action matrix. Depends on migrations 7 & 8. No LLM/CMS/publish.
-- =============================================================================

-- ===========================================================================
-- seo_content_comments — append-only feedback. actor_role_snapshot = role now.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  draft_section_id uuid REFERENCES public.seo_content_draft_sections(id) ON DELETE SET NULL,
  author_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role_snapshot text NOT NULL,
  comment_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_comments_opp ON public.seo_content_comments (content_opportunity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_content_comments_ws ON public.seo_content_comments (workspace_id);

-- ===========================================================================
-- seo_content_activity — append-only workflow timeline.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid NOT NULL REFERENCES public.seo_content_opportunities(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role_snapshot text NOT NULL,
  activity_type text NOT NULL CHECK (activity_type IN (
    'created', 'status_changed', 'wireframe_approved', 'draft_generated', 'section_regenerated',
    'comment_added', 'client_review_sent', 'client_approved', 'client_rejected',
    'changes_requested', 'team_review_requested', 'expert_review_requested',
    'ready_for_manual_publish', 'archived')),
  from_status text,
  to_status text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_activity_opp ON public.seo_content_activity (content_opportunity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_seo_content_activity_ws ON public.seo_content_activity (workspace_id);

-- ===========================================================================
-- seo_content_assets — file METADATA only (never bytes). Soft-delete only.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_content_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,
  content_opportunity_id uuid REFERENCES public.seo_content_opportunities(id) ON DELETE SET NULL,  -- nullable
  draft_id uuid REFERENCES public.seo_content_drafts(id) ON DELETE SET NULL,
  comment_id uuid REFERENCES public.seo_content_comments(id) ON DELETE SET NULL,
  format_input_id uuid REFERENCES public.seo_content_format_inputs(id) ON DELETE SET NULL,
  asset_scope text NOT NULL CHECK (asset_scope IN ('workspace', 'website', 'opportunity', 'draft', 'comment')),
  asset_kind text CHECK (asset_kind IN ('source_pdf', 'source_docx', 'reference_image', 'brand_sample', 'other')),
  bucket_name text NOT NULL DEFAULT 'seo-content-assets',
  storage_path text NOT NULL UNIQUE,
  original_file_name text NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN (
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/png', 'image/jpeg', 'image/webp')),
  file_size bigint,
  uploaded_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_content_assets_ws ON public.seo_content_assets (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_assets_opp ON public.seo_content_assets (content_opportunity_id);
CREATE INDEX IF NOT EXISTS idx_seo_content_assets_scope ON public.seo_content_assets (asset_scope);
CREATE INDEX IF NOT EXISTS idx_seo_content_assets_mime ON public.seo_content_assets (mime_type);
CREATE INDEX IF NOT EXISTS idx_seo_content_assets_deleted ON public.seo_content_assets (is_deleted);
CREATE INDEX IF NOT EXISTS idx_seo_content_assets_created ON public.seo_content_assets (created_at DESC);

-- Forward-ref FK from migration 7: format_inputs.asset_id → seo_content_assets.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seo_content_format_inputs_asset_fk') THEN
    ALTER TABLE public.seo_content_format_inputs
      ADD CONSTRAINT seo_content_format_inputs_asset_fk
      FOREIGN KEY (asset_id) REFERENCES public.seo_content_assets(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Triggers: updated_at on assets; same-workspace guard on comments/activity/assets.
DROP TRIGGER IF EXISTS trg_seo_content_assets_updated_at ON public.seo_content_assets;
CREATE TRIGGER trg_seo_content_assets_updated_at BEFORE UPDATE ON public.seo_content_assets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_content_comments_samews ON public.seo_content_comments;
CREATE TRIGGER trg_seo_content_comments_samews BEFORE INSERT OR UPDATE ON public.seo_content_comments
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();
DROP TRIGGER IF EXISTS trg_seo_content_activity_samews ON public.seo_content_activity;
CREATE TRIGGER trg_seo_content_activity_samews BEFORE INSERT OR UPDATE ON public.seo_content_activity
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();
DROP TRIGGER IF EXISTS trg_seo_content_assets_samews ON public.seo_content_assets;
CREATE TRIGGER trg_seo_content_assets_samews BEFORE INSERT OR UPDATE ON public.seo_content_assets
  FOR EACH ROW EXECUTE FUNCTION public.seo_content_assert_same_workspace();

-- ---------------------------------------------------------------------------
-- RLS — comments (append-only; clients comment ONLY via the RPC, not direct).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_content_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_content_comments_select ON public.seo_content_comments;
CREATE POLICY seo_content_comments_select ON public.seo_content_comments
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());
-- Direct INSERT limited to manager set as self; client comments are written by
-- the SECURITY DEFINER RPC (status-gated). No update/delete → append-only.
DROP POLICY IF EXISTS seo_content_comments_insert ON public.seo_content_comments;
CREATE POLICY seo_content_comments_insert ON public.seo_content_comments
  FOR INSERT WITH CHECK (
    (author_user_id = auth.uid() AND public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']))
    OR public.seo_is_global_admin());

-- ---------------------------------------------------------------------------
-- RLS — activity (append-only; clients cannot forge; RPC writes via definer).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_content_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_content_activity_select ON public.seo_content_activity;
CREATE POLICY seo_content_activity_select ON public.seo_content_activity
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());
DROP POLICY IF EXISTS seo_content_activity_insert ON public.seo_content_activity;
CREATE POLICY seo_content_activity_insert ON public.seo_content_activity
  FOR INSERT WITH CHECK (
    (actor_user_id = auth.uid() AND public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']))
    OR public.seo_is_global_admin());

-- ---------------------------------------------------------------------------
-- RLS — assets (read: members; write: manager set; clients cannot upload).
-- No hard-delete policy → hard DELETE denied for all (soft-delete via UPDATE).
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_content_assets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_content_assets_select ON public.seo_content_assets;
CREATE POLICY seo_content_assets_select ON public.seo_content_assets
  FOR SELECT USING (public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin());
DROP POLICY IF EXISTS seo_content_assets_insert ON public.seo_content_assets;
CREATE POLICY seo_content_assets_insert ON public.seo_content_assets
  FOR INSERT WITH CHECK (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin());
DROP POLICY IF EXISTS seo_content_assets_update ON public.seo_content_assets;
CREATE POLICY seo_content_assets_update ON public.seo_content_assets
  FOR UPDATE USING (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin())
  WITH CHECK (public.seo_role_in(workspace_id, ARRAY['owner', 'admin', 'team_member']) OR public.seo_is_global_admin());

-- =============================================================================
-- Private Storage bucket + object policies (no public/anon access).
-- Path convention: {workspace_id}/{website_id}/{scope}/{asset_id}_{filename}
-- → first path segment = workspace_id, used for membership authorization.
-- =============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'seo-content-assets', 'seo-content-assets', false, 20971520,  -- 20 MB
  ARRAY['application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/png', 'image/jpeg', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Read/download: active workspace members (incl. client) of the path's workspace.
DROP POLICY IF EXISTS "seo_content_assets_obj_select" ON storage.objects;
CREATE POLICY "seo_content_assets_obj_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'seo-content-assets'
    AND (public.seo_is_global_admin()
         OR public.is_seo_workspace_member(((storage.foldername(name))[1])::uuid)));

-- Upload: manager set only (clients cannot upload). No update/delete policies →
-- object hard-delete deferred to a later admin/service cleanup job (service role).
DROP POLICY IF EXISTS "seo_content_assets_obj_insert" ON storage.objects;
CREATE POLICY "seo_content_assets_obj_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'seo-content-assets'
    AND (public.seo_is_global_admin()
         OR public.seo_role_in(((storage.foldername(name))[1])::uuid, ARRAY['owner', 'admin', 'team_member'])));

-- =============================================================================
-- seo_content_transition(opportunity, action, note) — the sanctioned workflow
-- path. Enforces the locked status→action matrix + role checks, logs activity,
-- and captures p_note as a comment where relevant. SECURITY DEFINER; membership
-- verified inside. No action publishes or writes to a CMS.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.seo_content_transition(
  p_opportunity_id uuid,
  p_action text,
  p_note text DEFAULT NULL
)
RETURNS TABLE (opportunity_id uuid, new_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ws uuid;
  v_web uuid;
  v_url text;
  v_status text;
  v_role text;
  v_is_admin boolean;
  v_can_all boolean;   -- owner/admin/team_member (or global admin)
  v_is_client boolean;
  v_snap text;
  v_target text := NULL;
  v_activity text := 'status_changed';
  v_client_gate boolean;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT workspace_id, website_id, website_url, status
    INTO v_ws, v_web, v_url, v_status
  FROM public.seo_content_opportunities WHERE id = p_opportunity_id;
  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Content opportunity not found: %', p_opportunity_id;
  END IF;

  v_role := public.seo_role_of(v_ws, v_uid);
  v_is_admin := public.seo_is_global_admin(v_uid);
  IF v_role IS NULL AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Not a member of this workspace';
  END IF;
  v_can_all := v_is_admin OR v_role IN ('owner', 'admin', 'team_member');
  v_is_client := (v_role = 'client');
  v_snap := COALESCE(v_role, 'global_admin');
  v_client_gate := v_status IN ('wireframe_client_review', 'draft_client_review');

  -- ---- comment (any member; clients only during client review) -------------
  IF p_action = 'comment' THEN
    IF v_note IS NULL THEN RAISE EXCEPTION 'Comment text required'; END IF;
    IF v_is_client AND NOT v_client_gate THEN
      RAISE EXCEPTION 'Clients can only comment while content is in client review (current: %)', v_status;
    END IF;
    v_target := NULL; v_activity := 'comment_added';

  -- ---- manager/team actions ------------------------------------------------
  ELSIF p_action IN ('mark_plan_ready','start_wireframe','submit_wireframe_internal_review',
                     'send_wireframe_client_review','approve_wireframe_internal','request_wireframe_changes',
                     'start_draft','submit_draft_internal_review','send_draft_client_review',
                     'approve_draft_internal','request_draft_changes','mark_ready_for_manual_publish','archive') THEN
    IF NOT v_can_all THEN
      RAISE EXCEPTION 'Not permitted: only owner/admin/team_member can perform %', p_action;
    END IF;
    IF p_action = 'mark_plan_ready' THEN
      IF v_status <> 'idea' THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'plan_ready';
    ELSIF p_action = 'start_wireframe' THEN
      IF v_status NOT IN ('plan_ready','wireframe_changes_requested') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'wireframe_in_progress';
    ELSIF p_action = 'submit_wireframe_internal_review' THEN
      IF v_status <> 'wireframe_in_progress' THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'wireframe_internal_review';
    ELSIF p_action = 'send_wireframe_client_review' THEN
      IF v_status NOT IN ('wireframe_in_progress','wireframe_internal_review') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'wireframe_client_review'; v_activity := 'client_review_sent';
    ELSIF p_action = 'approve_wireframe_internal' THEN
      IF v_status NOT IN ('wireframe_in_progress','wireframe_internal_review') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'wireframe_approved'; v_activity := 'wireframe_approved';
    ELSIF p_action = 'request_wireframe_changes' THEN
      IF v_status NOT IN ('wireframe_internal_review','wireframe_client_review') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'wireframe_changes_requested'; v_activity := 'changes_requested';
    ELSIF p_action = 'start_draft' THEN
      IF v_status NOT IN ('wireframe_approved','draft_changes_requested') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'draft_in_progress';
    ELSIF p_action = 'submit_draft_internal_review' THEN
      IF v_status <> 'draft_in_progress' THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'draft_internal_review';
    ELSIF p_action = 'send_draft_client_review' THEN
      IF v_status NOT IN ('draft_in_progress','draft_internal_review') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'draft_client_review'; v_activity := 'client_review_sent';
    ELSIF p_action = 'approve_draft_internal' THEN
      IF v_status NOT IN ('draft_in_progress','draft_internal_review') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'draft_approved';
    ELSIF p_action = 'request_draft_changes' THEN
      IF v_status NOT IN ('draft_internal_review','draft_client_review') THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'draft_changes_requested'; v_activity := 'changes_requested';
    ELSIF p_action = 'mark_ready_for_manual_publish' THEN
      IF v_status <> 'draft_approved' THEN RAISE EXCEPTION 'Invalid transition % from %', p_action, v_status; END IF;
      v_target := 'ready_for_manual_publish'; v_activity := 'ready_for_manual_publish';
    ELSIF p_action = 'archive' THEN
      IF v_status = 'archived' THEN RAISE EXCEPTION 'Already archived'; END IF;
      v_target := 'archived'; v_activity := 'archived';
    END IF;

  -- ---- client review actions (client or global admin; *_client_review only) --
  ELSIF p_action IN ('client_approve_wireframe','client_reject_wireframe','client_approve_draft',
                     'client_reject_draft','request_team_review','request_expert_review') THEN
    IF NOT (v_is_client OR v_is_admin) THEN
      RAISE EXCEPTION 'Not permitted: % is a client review action', p_action;
    END IF;
    IF NOT v_client_gate THEN
      RAISE EXCEPTION 'Client actions are only allowed while content is in client review (current: %)', v_status;
    END IF;
    IF p_action = 'client_approve_wireframe' THEN
      IF v_status <> 'wireframe_client_review' THEN RAISE EXCEPTION 'Invalid: % requires wireframe_client_review', p_action; END IF;
      v_target := 'wireframe_approved'; v_activity := 'client_approved';
    ELSIF p_action = 'client_reject_wireframe' THEN
      IF v_status <> 'wireframe_client_review' THEN RAISE EXCEPTION 'Invalid: % requires wireframe_client_review', p_action; END IF;
      v_target := 'wireframe_changes_requested'; v_activity := 'client_rejected';
    ELSIF p_action = 'client_approve_draft' THEN
      IF v_status <> 'draft_client_review' THEN RAISE EXCEPTION 'Invalid: % requires draft_client_review', p_action; END IF;
      v_target := 'draft_approved'; v_activity := 'client_approved';
    ELSIF p_action = 'client_reject_draft' THEN
      IF v_status <> 'draft_client_review' THEN RAISE EXCEPTION 'Invalid: % requires draft_client_review', p_action; END IF;
      v_target := 'draft_changes_requested'; v_activity := 'client_rejected';
    ELSIF p_action = 'request_team_review' THEN
      v_target := CASE v_status WHEN 'wireframe_client_review' THEN 'wireframe_internal_review'
                                ELSE 'draft_internal_review' END;
      v_activity := 'team_review_requested';
    ELSIF p_action = 'request_expert_review' THEN
      v_target := NULL;  -- no status change in Stage 3 (no expert module yet)
      v_activity := 'expert_review_requested';
    END IF;

  ELSE
    RAISE EXCEPTION 'Unknown action: %', p_action;
  END IF;

  -- ---- apply ---------------------------------------------------------------
  IF v_target IS NOT NULL THEN
    UPDATE public.seo_content_opportunities
      SET status = v_target, updated_at = now(), updated_by = v_uid,
          archived_at = CASE WHEN v_target = 'archived' THEN now() ELSE archived_at END
    WHERE id = p_opportunity_id;
  END IF;

  INSERT INTO public.seo_content_activity (
    workspace_id, website_id, website_url, content_opportunity_id, actor_user_id,
    actor_role_snapshot, activity_type, from_status, to_status, note
  ) VALUES (
    v_ws, v_web, v_url, p_opportunity_id, v_uid, v_snap, v_activity, v_status, COALESCE(v_target, v_status), v_note
  );

  -- Attach the note as a comment for non-comment actions that carried feedback.
  IF v_note IS NOT NULL AND p_action <> 'comment' THEN
    INSERT INTO public.seo_content_comments (
      workspace_id, website_id, website_url, content_opportunity_id, author_user_id, actor_role_snapshot, comment_text
    ) VALUES (v_ws, v_web, v_url, p_opportunity_id, v_uid, v_snap, v_note);
  ELSIF p_action = 'comment' THEN
    INSERT INTO public.seo_content_comments (
      workspace_id, website_id, website_url, content_opportunity_id, author_user_id, actor_role_snapshot, comment_text
    ) VALUES (v_ws, v_web, v_url, p_opportunity_id, v_uid, v_snap, v_note);
  END IF;

  opportunity_id := p_opportunity_id;
  new_status := COALESCE(v_target, v_status);
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.seo_content_transition(uuid, text, text) TO authenticated;
