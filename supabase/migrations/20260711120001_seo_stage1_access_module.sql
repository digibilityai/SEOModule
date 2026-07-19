-- =============================================================================
-- SEO Backend — Stage 1 (Phase 12C) — Migration 1 of 3: Access / Module layer
-- =============================================================================
-- Additive only. Creates SEO module-access, subscription, plan-limit and usage
-- tables plus foundational SECURITY DEFINER helpers. Targets the SHARED
-- Digibility Supabase project (auth.users + public.profiles already exist).
-- Does NOT drop/alter any existing Core table. Safe to re-run (IF NOT EXISTS /
-- CREATE OR REPLACE / ON CONFLICT).
--
-- Decisions applied: SEO reuses Core auth (no new auth); SEO roles live in
-- seo_workspace_members (mig 2), not profiles.role; seo_subscriptions is
-- add-on/standalone (not Core billing); usage resets by subscription period.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Shared updated_at trigger fn — mirrors Core public.set_updated_at().
-- CREATE OR REPLACE keeps this idempotent whether or not Core defined it first.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Helper: global (platform) admin check.
-- Reuses Core convention (profiles.role IN super_admin/admin). Guarded so the
-- migration also runs in a standalone SEO test project where profiles is absent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_is_global_admin(uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result boolean;
BEGIN
  BEGIN
    SELECT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = uid AND role::text IN ('super_admin', 'admin')
    ) INTO result;
  EXCEPTION WHEN undefined_table THEN
    result := false;  -- standalone project without Core profiles
  END;
  RETURN COALESCE(result, false);
END;
$$;

-- ===========================================================================
-- user_module_access — which platform modules a user may use (seo | visibility)
-- Enables SEO-only, VM-only and both. User-scoped (no workspace/website).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.user_module_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  module_name text NOT NULL CHECK (module_name IN ('seo', 'visibility')),
  is_active boolean NOT NULL DEFAULT true,
  granted_at timestamptz NOT NULL DEFAULT now(),
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, module_name)
);
CREATE INDEX IF NOT EXISTS idx_user_module_access_user ON public.user_module_access (user_id);
CREATE INDEX IF NOT EXISTS idx_user_module_access_module ON public.user_module_access (module_name);
CREATE INDEX IF NOT EXISTS idx_user_module_access_active
  ON public.user_module_access (user_id, module_name) WHERE is_active;

-- Helper: does a user have active SEO module access? (SECURITY DEFINER → bypasses RLS)
CREATE OR REPLACE FUNCTION public.has_seo_module_access(uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_module_access
    WHERE user_id = uid AND module_name = 'seo' AND is_active
  );
$$;

-- ===========================================================================
-- seo_plan_limits — static plan catalog (basic | standard | pro). Read-only ref.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_plan_limits (
  plan_tier text PRIMARY KEY CHECK (plan_tier IN ('basic', 'standard', 'pro')),
  website_limit integer NOT NULL,
  audit_frequency text NOT NULL,
  content_opportunity_limit integer NOT NULL,          -- -1 = unlimited
  draft_limit integer NOT NULL,
  tracked_page_limit integer NOT NULL,
  tracked_keyword_limit integer NOT NULL,
  competitor_limit integer NOT NULL,
  ai_prompt_limit integer NOT NULL,
  offpage_opportunity_limit integer NOT NULL,           -- -1 = advanced/unbounded
  expert_support_limit integer NOT NULL,                -- -1 = priority/bundled
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Safe default limits (catalog reference, not production/customer data).
INSERT INTO public.seo_plan_limits (
  plan_tier, website_limit, audit_frequency, content_opportunity_limit, draft_limit,
  tracked_page_limit, tracked_keyword_limit, competitor_limit, ai_prompt_limit,
  offpage_opportunity_limit, expert_support_limit
) VALUES
  ('basic',    1,  'monthly',                        3,  2,   50,   25,  2,   0,   0,  0),
  ('standard', 3,  'weekly',                         10,  5,  250,  150,  5,  10,  50,  5),
  ('pro',     10,  'weekly_plus_change_monitoring',  -1, 15, 1000, 1000, 10, 100,  -1, -1)
ON CONFLICT (plan_tier) DO NOTHING;

-- ===========================================================================
-- seo_subscriptions — SEO plan/access per user (optionally per workspace).
-- Add-on OR standalone. No payment gateway wired yet (external_ref/status seeded
-- manually for now). workspace_id FK added in migration 2.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id uuid,                                    -- FK added in mig 2 (forward ref)
  plan_tier text NOT NULL DEFAULT 'basic'
    REFERENCES public.seo_plan_limits(plan_tier) ON UPDATE CASCADE,
  status text NOT NULL DEFAULT 'trialing'
    CHECK (status IN ('trialing', 'active', 'past_due', 'cancelled', 'expired')),
  is_addon boolean NOT NULL DEFAULT false,              -- true when user also has VM
  period_start date,
  period_end date,
  external_ref text,                                    -- future payment/webhook id
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_subscriptions_user ON public.seo_subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_seo_subscriptions_workspace ON public.seo_subscriptions (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_subscriptions_status ON public.seo_subscriptions (status);

-- ===========================================================================
-- seo_usage_events — append-only usage log. period_start/end snapshot the
-- owning subscription window so limits reset by subscription period (not month).
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.seo_usage_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id uuid,                                    -- FK added in mig 2
  website_id uuid,                                      -- FK added in mig 3
  subscription_id uuid REFERENCES public.seo_subscriptions(id) ON DELETE SET NULL,
  metric text NOT NULL,                                 -- audit_run | content_opportunity | draft | tracked_page | tracked_keyword | competitor | ai_prompt | offpage_opportunity | expert_support
  amount integer NOT NULL DEFAULT 1,
  period_start date,
  period_end date,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_seo_usage_events_user ON public.seo_usage_events (user_id);
CREATE INDEX IF NOT EXISTS idx_seo_usage_events_workspace ON public.seo_usage_events (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_usage_events_website ON public.seo_usage_events (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_usage_events_metric ON public.seo_usage_events (metric);
CREATE INDEX IF NOT EXISTS idx_seo_usage_events_subscription ON public.seo_usage_events (subscription_id);
CREATE INDEX IF NOT EXISTS idx_seo_usage_events_occurred ON public.seo_usage_events (occurred_at);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_user_module_access_updated_at ON public.user_module_access;
CREATE TRIGGER trg_user_module_access_updated_at BEFORE UPDATE ON public.user_module_access
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_plan_limits_updated_at ON public.seo_plan_limits;
CREATE TRIGGER trg_seo_plan_limits_updated_at BEFORE UPDATE ON public.seo_plan_limits
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seo_subscriptions_updated_at ON public.seo_subscriptions;
CREATE TRIGGER trg_seo_subscriptions_updated_at BEFORE UPDATE ON public.seo_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.user_module_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_module_access_select ON public.user_module_access;
CREATE POLICY user_module_access_select ON public.user_module_access
  FOR SELECT USING (auth.uid() = user_id OR public.seo_is_global_admin());
-- Module grants are platform-managed → only global admin writes.
DROP POLICY IF EXISTS user_module_access_admin_write ON public.user_module_access;
CREATE POLICY user_module_access_admin_write ON public.user_module_access
  FOR ALL USING (public.seo_is_global_admin()) WITH CHECK (public.seo_is_global_admin());

ALTER TABLE public.seo_plan_limits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_plan_limits_read ON public.seo_plan_limits;
CREATE POLICY seo_plan_limits_read ON public.seo_plan_limits
  FOR SELECT USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS seo_plan_limits_admin_write ON public.seo_plan_limits;
CREATE POLICY seo_plan_limits_admin_write ON public.seo_plan_limits
  FOR ALL USING (public.seo_is_global_admin()) WITH CHECK (public.seo_is_global_admin());

ALTER TABLE public.seo_subscriptions ENABLE ROW LEVEL SECURITY;
-- View own subscription, or global admin. (Workspace-manager visibility added
-- in mig 2 once workspace helpers exist.)
DROP POLICY IF EXISTS seo_subscriptions_select ON public.seo_subscriptions;
CREATE POLICY seo_subscriptions_select ON public.seo_subscriptions
  FOR SELECT USING (auth.uid() = user_id OR public.seo_is_global_admin());
-- Stage 1: subscription writes are global-admin only. Payment gateway is not
-- wired yet and subscriptions are seeded manually, so a plain user must NOT be
-- able to self-provision an arbitrary paid plan_tier (billing-integrity bypass).
-- Real self-serve/owner provisioning arrives with the billing + service-role
-- (webhook) flow; the service role bypasses RLS, so this does not block that.
-- Clients (workspace members) are excluded here as well.
DROP POLICY IF EXISTS seo_subscriptions_write ON public.seo_subscriptions;
CREATE POLICY seo_subscriptions_write ON public.seo_subscriptions
  FOR ALL
  USING (public.seo_is_global_admin())
  WITH CHECK (public.seo_is_global_admin());

ALTER TABLE public.seo_usage_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_usage_events_select ON public.seo_usage_events;
CREATE POLICY seo_usage_events_select ON public.seo_usage_events
  FOR SELECT USING (auth.uid() = user_id OR public.seo_is_global_admin());
-- Append-only from the acting user; no client-side update/delete of usage.
DROP POLICY IF EXISTS seo_usage_events_insert ON public.seo_usage_events;
CREATE POLICY seo_usage_events_insert ON public.seo_usage_events
  FOR INSERT WITH CHECK (auth.uid() = user_id AND public.has_seo_module_access());
