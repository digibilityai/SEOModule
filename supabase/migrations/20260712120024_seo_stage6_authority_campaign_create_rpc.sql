-- =============================================================================
-- SEO Backend — Stage 6 (Phase 15D) — Migration 24: Authority Campaign Create RPC
-- =============================================================================
-- Additive only. Builds on migrations 17 (opportunities), 18 (campaigns), and
-- 19 (campaign children: junction + tasks). Does NOT edit any already-applied
-- Stage 6 migration.
--
-- Adds ONE guarded, atomic campaign-creation RPC. Campaign creation has no RPC
-- of its own before this — the two existing Stage 6 RPCs
-- (seo_authority_opportunity_transition / seo_authority_campaign_transition,
-- migration 20) only ever TRANSITION an existing row's status. The frontend
-- previously created a campaign with three separate PostgREST requests
-- (campaign INSERT, junction INSERT, task INSERT) plus a best-effort
-- client-side compensating DELETE — which is NOT one PostgreSQL transaction and
-- can leave a partial campaign if the compensating delete itself fails. This
-- RPC does all three inserts inside a single PL/pgSQL function body, so any
-- failure rolls back the entire call and leaves zero rows behind.
--
-- Security model: SAME pattern as the two existing Stage 6 transition RPCs —
-- SECURITY DEFINER + explicit `SET search_path = public`, with the manager
-- role check performed INSIDE the function (owner/admin/team_member or global
-- admin), so clients and non-members are rejected in-function even though
-- EXECUTE is granted to `authenticated`. Additionally REVOKEs the implicit
-- PUBLIC execute grant so only `authenticated` may call it. No automation, no
-- external call — additive to Stage 1-6 + Core.
--
-- Scope guardrails:
--   * approval_status is NOT written — the column's own DEFAULT 'draft' applies.
--     A campaign is NEVER created directly as 'pending_approval'; submission for
--     approval is the separate seo_authority_campaign_transition('submit_for_approval')
--     action (migration 20), out of scope here.
--   * No activity row is written. Campaign CREATION is not a transition and the
--     Stage 6 design (D5a) documents seo_authority_activity for transitions
--     only; no 'create' activity_type is introduced here (no silent scope
--     expansion).
--   * `source` is left at its column DEFAULT ('manual_seed') — the campaigns
--     CHECK allows only manual_seed/import/system, none of which mean
--     "app-created", and adding a new source value would require altering an
--     already-applied migration. Left as the default deliberately; revisit if a
--     dedicated source value is ever added.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.seo_authority_campaign_create(
  p_website_id uuid,
  p_name text,
  p_goal text,
  p_owner text,
  p_due_date date DEFAULT NULL,
  p_opportunity_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ws uuid;
  v_url text;
  v_name text := btrim(coalesce(p_name, ''));
  v_goal text := btrim(coalesce(p_goal, ''));
  v_ids uuid[];
  v_bad_count int;
  v_campaign_id uuid;
BEGIN
  -- 1. Authenticated caller required. (Belt-and-suspenders: the role check
  --    below would also reject a NULL uid, but this gives a clearer message.)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. Resolve workspace_id + website_url SERVER-SIDE from the website id.
  --    Client-supplied workspace_id / website_url are intentionally NOT
  --    accepted by this function's signature and are never trusted.
  SELECT workspace_id, website_url INTO v_ws, v_url
  FROM public.seo_websites WHERE id = p_website_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Website % does not exist', p_website_id;
  END IF;

  -- 3. Manager role check (owner/admin/team_member) or global admin. Clients
  --    and non-members are rejected here — same predicate as the campaigns
  --    write RLS policy and the transition RPCs' base check.
  IF NOT (public.seo_role_in(v_ws, ARRAY['owner', 'admin', 'team_member'])
          OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not permitted to create authority campaigns in this workspace';
  END IF;

  -- 4. Field validation.
  IF v_name = '' THEN
    RAISE EXCEPTION 'Campaign name must not be empty';
  END IF;
  IF v_goal = '' THEN
    RAISE EXCEPTION 'Campaign goal must not be empty';
  END IF;
  IF p_owner NOT IN ('client_action', 'developer_needed', 'digibility_expert', 'system_suggestion') THEN
    RAISE EXCEPTION 'Invalid owner value: %', p_owner;
  END IF;

  -- 5. Deduplicate opportunity ids, preserving first-occurrence order so task
  --    positions are deterministic. (Duplicate ids in the input therefore
  --    produce exactly one junction row + one task per distinct opportunity.)
  SELECT array_agg(opp_id ORDER BY ord) INTO v_ids
  FROM (
    SELECT opp_id, min(ord) AS ord
    FROM unnest(coalesce(p_opportunity_ids, '{}'::uuid[])) WITH ORDINALITY AS u(opp_id, ord)
    GROUP BY opp_id
  ) deduped;
  v_ids := coalesce(v_ids, '{}'::uuid[]);

  -- 6. Every supplied opportunity must EXIST and belong to THIS workspace +
  --    website. Rejects cross-workspace / cross-website / unknown ids before
  --    any write. (The junction integrity trigger would also reject a
  --    cross-workspace link, but validating up front gives one clear error.)
  IF array_length(v_ids, 1) IS NOT NULL THEN
    SELECT count(*) INTO v_bad_count
    FROM unnest(v_ids) AS x(opp_id)
    LEFT JOIN public.seo_authority_opportunities o ON o.id = x.opp_id
    WHERE o.id IS NULL
       OR o.workspace_id <> v_ws
       OR o.website_id <> p_website_id;
    IF v_bad_count > 0 THEN
      RAISE EXCEPTION 'One or more opportunities do not exist or do not belong to this workspace/website';
    END IF;
  END IF;

  -- 7. Insert the campaign row. approval_status intentionally omitted so the
  --    column DEFAULT 'draft' applies — never 'pending_approval'.
  INSERT INTO public.seo_authority_campaigns
    (workspace_id, website_id, website_url, name, goal, owner, due_date, created_by)
  VALUES
    (v_ws, p_website_id, v_url, v_name, v_goal, p_owner, p_due_date, auth.uid())
  RETURNING id INTO v_campaign_id;

  -- 8. Junction links (source of truth for membership, D1). The integrity
  --    trigger re-validates the workspace/website match per row.
  INSERT INTO public.seo_authority_campaign_opportunities
    (workspace_id, website_id, website_url, campaign_id, opportunity_id, created_by)
  SELECT v_ws, p_website_id, v_url, v_campaign_id, x.opp_id, auth.uid()
  FROM unnest(v_ids) AS x(opp_id);

  -- 9. One task per selected opportunity, label = that opportunity's own
  --    suggested_action, is_complete = false, deterministic 0-based position in
  --    first-occurrence order. Mirrors the frontend mock's task generation
  --    exactly — no invented task/status/owner/workflow behavior.
  INSERT INTO public.seo_authority_campaign_tasks
    (workspace_id, website_id, website_url, campaign_id, opportunity_id, label, is_complete, position, created_by)
  SELECT v_ws, p_website_id, v_url, v_campaign_id, o.id, o.suggested_action, false, (t.ord - 1)::int, auth.uid()
  FROM unnest(v_ids) WITH ORDINALITY AS t(opp_id, ord)
  JOIN public.seo_authority_opportunities o ON o.id = t.opp_id;

  RETURN v_campaign_id;
END;
$$;

-- Only authenticated may call it (the in-function role check narrows further to
-- managers). Revoke BOTH the implicit PUBLIC grant AND the Supabase
-- default-privilege grant to `anon`, so an unauthenticated (anon-key-only)
-- caller cannot execute it at all — stricter than the two existing Stage 6
-- transition RPCs, which left anon's default grant in place (anon is rejected
-- in-function anyway for lack of auth.uid(), but revoking here is the
-- requirement-6 "authenticated only" hardening). `service_role` (Supabase's
-- trusted backend role, never exposed to the browser) keeps its default grant,
-- as with every other RPC in this project.
REVOKE ALL ON FUNCTION public.seo_authority_campaign_create(uuid, text, text, text, date, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_authority_campaign_create(uuid, text, text, text, date, uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_authority_campaign_create(uuid, text, text, text, date, uuid[]) TO authenticated;
