-- Cross-project identity mirror for Digibility-authenticated users.
-- The canonical account remains in Digibility Core. This table stores only the
-- minimum attributes required for SEO authorization/admin display.

CREATE TABLE IF NOT EXISTS public.seo_identity_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  display_name text,
  core_role text NOT NULL DEFAULT 'user',
  core_status text NOT NULL DEFAULT 'active',
  synced_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_seo_identity_profiles_core_role
  ON public.seo_identity_profiles (core_role);

ALTER TABLE public.seo_identity_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seo_identity_profiles_select_own ON public.seo_identity_profiles;
CREATE POLICY seo_identity_profiles_select_own
  ON public.seo_identity_profiles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP TRIGGER IF EXISTS trg_seo_identity_profiles_updated_at
  ON public.seo_identity_profiles;
CREATE TRIGGER trg_seo_identity_profiles_updated_at
  BEFORE UPDATE ON public.seo_identity_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Preserve the existing Core-profiles behavior for shared/test projects, while
-- adding the dedicated-SEO-project mirror as a supported source.
CREATE OR REPLACE FUNCTION public.seo_is_global_admin(uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result boolean := false;
BEGIN
  IF uid IS NULL THEN
    RETURN false;
  END IF;

  IF to_regclass('public.profiles') IS NOT NULL THEN
    EXECUTE
      'SELECT EXISTS (
         SELECT 1 FROM public.profiles
         WHERE id = $1
           AND role::text IN (''super_admin'', ''admin'')
       )'
      INTO result
      USING uid;
    IF result THEN
      RETURN true;
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.seo_identity_profiles
    WHERE user_id = uid
      AND core_role IN ('super_admin', 'admin')
      AND core_status NOT IN ('suspended', 'inactive')
  )
  INTO result;

  RETURN result;
EXCEPTION
  WHEN undefined_column OR undefined_table THEN
    RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.seo_is_global_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seo_is_global_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seo_is_global_admin(uuid) TO service_role;
