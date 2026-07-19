-- =============================================================================
-- SEO Backend — P1a Step 1 — Migration 31: Domain Ownership Verification
--                            DATABASE CONTRACT (additive)
-- =============================================================================
-- Additive only. Establishes ONLY the database foundation for DNS-TXT domain
-- ownership verification: a customer-facing verification-state table and an
-- APPEND-ONLY audit table, with constraints, indexes, RLS and (reused) triggers.
--
-- SCOPE (P1a Step 1 — approved plan):
--   * seo_ownership_verifications        — one verification record per website
--                                          (per method); customer-safe fields;
--                                          RLS member-read; NO customer writes.
--   * seo_ownership_verification_events  — append-only audit of the verification
--                                          lifecycle; RLS member-read; immutable.
--
-- EXPLICITLY NOT IN THIS STEP (later P1a steps / P1b):
--   * No customer RPCs (initiate/retry/revoke/re-verify) — Step 2A.
--   * No service-role claim/result RPCs — Step 2A.
--   * No DNS resolution / token comparison / worker code — Step 3.
--   * No frontend service/component/hook/mock; no supabaseTypes.ts constants.
--   * No crawl-authorization change; no verified-only enqueue enforcement — P1b.
--   * seo_crawl_request / seo_crawl_request_audit / seo_crawl_cancel UNCHANGED.
--
-- DESIGN (approved P1a decisions):
--   * DNS TXT is the ONLY MVP method (method CHECK allows 'dns_txt' only; the
--     CHECK is additively wideable later).
--   * Verification is scoped to workspace + website + current host
--     (verification_host snapshot).
--   * Existing websites are unverified by default: a website with NO record is
--     treated as unverified. This migration creates NO verification rows.
--   * Lifecycle states: pending / verified / failed / revoked. No 'expired'
--     state — verification does NOT auto-expire; invalidation is event-driven.
--   * Verification state is authoritative in Supabase; audit is append-only.
--   * Customers get NO direct table writes; writes arrive only via the Step 2A
--     SECURITY DEFINER RPCs / the Step 3 service-role worker (both future).
--   * ownership_source is a forward-compatible provenance seam so a FUTURE
--     Digibility ownership signal can be added additively as another trusted
--     source WITHOUT replacing the standalone DNS model.
--
-- SECURITY MODEL mirrors the Stage 6 activity table + the Phase 16C crawl
-- control-plane: RLS default-deny for writes; workspace-member SELECT only;
-- append-only audit (SELECT-only policy, no UPDATE/DELETE); a defense-in-depth
-- workspace/website integrity trigger; reuse of the existing set_updated_at().
-- No secrets/credentials are stored. No existing object is altered.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. seo_ownership_verifications — one verification record per website+method.
--    Customer-safe. Absence of a row == unverified (no default row created).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_ownership_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  website_url text NOT NULL,                                  -- snapshot at request time
  verification_host text NOT NULL,                            -- host the proof is scoped to
  method text NOT NULL DEFAULT 'dns_txt'
    CHECK (method IN ('dns_txt')),                            -- DNS TXT only (MVP); wideable later
  ownership_source text NOT NULL DEFAULT 'standalone_dns'
    CHECK (ownership_source IN ('standalone_dns')),           -- provenance seam (future: platform)
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'verified', 'failed', 'revoked')),
  challenge_token text NOT NULL,                              -- customer-safe TXT value to place
  challenge_created_at timestamptz NOT NULL DEFAULT now(),
  challenge_rotated_at timestamptz,
  last_checked_at timestamptz,
  verified_at timestamptz,
  failure_reason text,                                        -- customer-safe friendly reason
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- One verification record per website per method (host lives inside the row;
  -- a host change invalidates + updates this same row, it does not fork it).
  CONSTRAINT seo_ownership_verifications_website_method_uniq UNIQUE (website_id, method)
);

CREATE INDEX IF NOT EXISTS idx_seo_ownership_verifications_workspace
  ON public.seo_ownership_verifications (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_ownership_verifications_website
  ON public.seo_ownership_verifications (website_id);
CREATE INDEX IF NOT EXISTS idx_seo_ownership_verifications_status
  ON public.seo_ownership_verifications (status);

-- ---------------------------------------------------------------------------
-- 2. seo_ownership_verification_events — append-only lifecycle audit.
--    Customer-safe. No updated_at (immutable). Deleting the subject cascades.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seo_ownership_verification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verification_id uuid NOT NULL REFERENCES public.seo_ownership_verifications(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL REFERENCES public.seo_workspaces(id) ON DELETE CASCADE,
  website_id uuid NOT NULL REFERENCES public.seo_websites(id) ON DELETE CASCADE,
  event_type text NOT NULL
    CHECK (event_type IN ('initiated', 'challenge_rotated', 'check_started',
                          'verified', 'failed', 'revoked',
                          're_verification_requested', 'invalidated', 'admin_override')),
  from_status text,
  to_status text,
  actor text NOT NULL CHECK (actor IN ('customer', 'worker', 'system', 'global_admin')),
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role_snapshot text,
  note text,                                                  -- customer-safe only
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_ownership_verification_events_verification
  ON public.seo_ownership_verification_events (verification_id, created_at);
CREATE INDEX IF NOT EXISTS idx_seo_ownership_verification_events_workspace
  ON public.seo_ownership_verification_events (workspace_id);
CREATE INDEX IF NOT EXISTS idx_seo_ownership_verification_events_website
  ON public.seo_ownership_verification_events (website_id);

-- ---------------------------------------------------------------------------
-- 3. Triggers: updated_at (reuses existing set_updated_at) + workspace/website
--    integrity (defense-in-depth; a website must belong to its stated
--    workspace). Mirrors the Phase 16C seo_crawl_job_integrity pattern.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_seo_ownership_verifications_updated_at ON public.seo_ownership_verifications;
CREATE TRIGGER trg_seo_ownership_verifications_updated_at
  BEFORE UPDATE ON public.seo_ownership_verifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.seo_ownership_verification_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ws uuid;
BEGIN
  SELECT workspace_id INTO v_ws FROM public.seo_websites WHERE id = NEW.website_id;
  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'seo_ownership_verification: website % does not exist', NEW.website_id;
  END IF;
  IF v_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'seo_ownership_verification: website % does not belong to workspace %',
      NEW.website_id, NEW.workspace_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seo_ownership_verifications_integrity ON public.seo_ownership_verifications;
CREATE TRIGGER trg_seo_ownership_verifications_integrity
  BEFORE INSERT OR UPDATE OF workspace_id, website_id ON public.seo_ownership_verifications
  FOR EACH ROW EXECUTE FUNCTION public.seo_ownership_verification_integrity();

DROP TRIGGER IF EXISTS trg_seo_ownership_verification_events_integrity ON public.seo_ownership_verification_events;
CREATE TRIGGER trg_seo_ownership_verification_events_integrity
  BEFORE INSERT OR UPDATE OF workspace_id, website_id ON public.seo_ownership_verification_events
  FOR EACH ROW EXECUTE FUNCTION public.seo_ownership_verification_integrity();

-- ---------------------------------------------------------------------------
-- 4. RLS — default deny; workspace-member SELECT only; NO customer writes.
--    Writes arrive only via the future Step 2A SECURITY DEFINER RPCs and the
--    Step 3 service-role worker (both bypass RLS). The audit table is
--    APPEND-ONLY: SELECT policy only, no UPDATE/DELETE policy ever.
-- ---------------------------------------------------------------------------
ALTER TABLE public.seo_ownership_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_ownership_verifications_select ON public.seo_ownership_verifications;
CREATE POLICY seo_ownership_verifications_select ON public.seo_ownership_verifications
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );
-- No INSERT/UPDATE/DELETE policy for authenticated → all customer writes denied.

ALTER TABLE public.seo_ownership_verification_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS seo_ownership_verification_events_select ON public.seo_ownership_verification_events;
CREATE POLICY seo_ownership_verification_events_select ON public.seo_ownership_verification_events
  FOR SELECT USING (
    public.is_seo_workspace_member(workspace_id) OR public.seo_is_global_admin()
  );
-- No INSERT/UPDATE/DELETE policy on purpose — append-only, writes via RPC/worker.

-- =============================================================================
-- End P1a Step 1 ownership-verification database contract. Deferred to Step 2A+:
-- the guarded customer RPCs (initiate/retry/revoke/re-verify), the service-role
-- claim/result RPCs, the DNS-TXT worker module, the frontend, and (P1b) the
-- verified-only enqueue enforcement. No existing object was altered; no crawl
-- behaviour changed; production untouched.
-- =============================================================================
