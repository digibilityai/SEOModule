// Phase 16B — customer-facing auth/access helpers built ONLY on existing
// Supabase contracts. These are UX/navigation gates; RLS + guarded RPCs remain
// the authoritative authorization layer. No service-role key, no token logging,
// no RPC/RLS change.
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS } from "@/services/supabase/supabaseTypes";
import { getCurrentUserId } from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

export interface SeoSignInResult {
  success: boolean;
  /** Safe, human-readable message; never contains tokens or the password. */
  errorMessage?: string;
}

/**
 * Customer sign-in for EXISTING Supabase users (Phase 16B scope = login only).
 * Thin wrapper over `supabase.auth.signInWithPassword`; never creates users,
 * never resets passwords, never logs credentials or session values.
 */
export async function signInSeoCustomer(email: string, password: string): Promise<SeoSignInResult> {
  try {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      return { success: false, errorMessage: normalizeSupabaseError(error).message };
    }
    return { success: true };
  } catch (error) {
    return { success: false, errorMessage: normalizeSupabaseError(error).message };
  }
}

/**
 * SEO module-access check via the existing `has_seo_module_access` RPC (Stage 1).
 * Presentation-only — RLS still enforces access on every real query. Returns
 * false when there's no session; throws on a genuine RPC error so the guard can
 * show a recoverable error rather than a false "no access".
 */
export async function checkSeoModuleAccess(): Promise<boolean> {
  const userId = await getCurrentUserId();
  if (!userId) return false;
  const { data, error } = await supabase.rpc(SEO_RPCS.hasSeoModuleAccess);
  if (error) {
    throw new Error(`seoAccessService.checkSeoModuleAccess: ${normalizeSupabaseError(error).message}`);
  }
  return Boolean(data);
}

/**
 * Global-admin capability check via the existing `seo_is_global_admin` RPC
 * (Stage 1 SECURITY DEFINER helper reading `public.profiles`). Used only to gate
 * the `/seo/admin-preview` route in the UI; the DB helper + RLS remain
 * authoritative. Never inferred from `seo_workspace_members.seo_role`.
 */
export async function checkSeoGlobalAdmin(): Promise<boolean> {
  const userId = await getCurrentUserId();
  if (!userId) return false;
  const { data, error } = await supabase.rpc(SEO_RPCS.seoIsGlobalAdmin);
  if (error) {
    throw new Error(`seoAccessService.checkSeoGlobalAdmin: ${normalizeSupabaseError(error).message}`);
  }
  return Boolean(data);
}
