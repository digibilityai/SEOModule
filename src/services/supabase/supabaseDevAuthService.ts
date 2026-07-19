import { supabase } from "@/integrations/supabase/client";
import { getSeoDataMode, hasSupabaseConfig, type SeoDataMode } from "@/config/runtimeConfig";
import { getCurrentUserId } from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { getCurrentSeoWorkspace } from "@/services/supabase/seoWorkspaceService";

// =============================================================================
// DEV-ONLY Supabase Auth Test Harness (Phase 13B.1).
//
// Lets a developer sign in against a TEST Supabase project with a real
// email/password to exercise authenticated RLS behavior — no fake auth, no
// hardcoded test users, no service role key, no user creation. Only the
// anon client (src/integrations/supabase/client.ts) is used, exactly like
// every other frontend Supabase call. Passwords are never stored, logged, or
// echoed back — they exist only as a function argument passed straight to
// supabase-js.
//
// Not used by any customer-facing page. See SupabaseAuthTestPage.tsx.
// =============================================================================

export interface DevAuthState {
  mode: SeoDataMode;
  configured: boolean;
  hasSession: boolean;
  userId: string | null;
  userEmail: string | null;
  warnings: string[];
  checkedAt: string;
}

export interface DevSignInResult {
  success: boolean;
  userId: string | null;
  userEmail: string | null;
  /** Friendly, dev-facing message — set on failure, or occasionally as an informational note. */
  warning?: string;
}

export interface DevSignOutResult {
  success: boolean;
  warning?: string;
}

export interface SeoAccessCheckResult {
  /** Whether the check could actually run (false only when there's no session). */
  checked: boolean;
  /** true/false = determined; null = could not be determined (see warning). */
  hasAccess: boolean | null;
  method: "rpc" | "table" | "none";
  warning?: string;
}

export interface WorkspaceAccessCheckResult {
  checked: boolean;
  hasWorkspace: boolean | null;
  workspaceId: string | null;
  workspaceName: string | null;
  warning?: string;
}

/**
 * Snapshot of data mode + Supabase config + current session. Never throws;
 * safe to call in mock mode or with no config/session at all.
 */
export async function getDevAuthState(): Promise<DevAuthState> {
  const mode = getSeoDataMode();
  const configured = hasSupabaseConfig();
  const warnings: string[] = [];

  if (mode !== "supabase") {
    warnings.push(
      `VITE_SEO_DATA_MODE is "${mode}", not "supabase" — you can still sign in here to test auth/RLS, but wired services (websiteService, businessOnboardingService) will keep using mock data until VITE_SEO_DATA_MODE=supabase.`,
    );
  }
  if (!configured) {
    warnings.push(
      "VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY are not set — sign-in cannot work until both are configured in .env.",
    );
  }

  let hasSession = false;
  let userId: string | null = null;
  let userEmail: string | null = null;

  if (configured) {
    try {
      const { data, error } = await supabase.auth.getSession();
      if (error) {
        warnings.push(`auth.getSession() returned an error: ${normalizeSupabaseError(error).message}`);
      } else {
        hasSession = Boolean(data.session);
        userId = data.session?.user.id ?? null;
        userEmail = data.session?.user.email ?? null;
      }
    } catch (error) {
      warnings.push(`auth.getSession() threw: ${normalizeSupabaseError(error).message}`);
    }
  }

  return { mode, configured, hasSession, userId, userEmail, warnings, checkedAt: new Date().toISOString() };
}

/**
 * Signs in with a real Supabase Auth email/password against the configured
 * (test) project via `supabase.auth.signInWithPassword()`. Does not create
 * users, does not store the password anywhere, never logs it. Returns a
 * friendly result object instead of throwing — this is a dev tool, not a
 * customer-facing form, but errors are still normalized rather than raw.
 */
export async function signInDevUser(email: string, password: string): Promise<DevSignInResult> {
  if (!hasSupabaseConfig()) {
    return {
      success: false,
      userId: null,
      userEmail: null,
      warning: "Supabase is not configured — set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY first.",
    };
  }

  const trimmedEmail = email.trim();
  if (!trimmedEmail || !password) {
    return {
      success: false,
      userId: null,
      userEmail: null,
      warning: "Email and password are both required.",
    };
  }

  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: trimmedEmail,
      password,
    });
    if (error) {
      return {
        success: false,
        userId: null,
        userEmail: null,
        warning: `Sign-in failed: ${normalizeSupabaseError(error).message}`,
      };
    }
    return { success: true, userId: data.user?.id ?? null, userEmail: data.user?.email ?? null };
  } catch (error) {
    return {
      success: false,
      userId: null,
      userEmail: null,
      warning: `Sign-in threw: ${normalizeSupabaseError(error).message}`,
    };
  }
}

/** Signs out the current Supabase session (test project only — same anon client as everywhere else). */
export async function signOutDevUser(): Promise<DevSignOutResult> {
  try {
    const { error } = await supabase.auth.signOut();
    if (error) {
      return { success: false, warning: `Sign-out failed: ${normalizeSupabaseError(error).message}` };
    }
    return { success: true };
  } catch (error) {
    return { success: false, warning: `Sign-out threw: ${normalizeSupabaseError(error).message}` };
  }
}

/** Re-reads the current auth state. supabase-js already auto-refreshes tokens in the background. */
export async function refreshDevSession(): Promise<DevAuthState> {
  return getDevAuthState();
}

/**
 * Checks whether the current authenticated user has active SEO module
 * access (Stage 1 `user_module_access`, module='seo'). Tries the same
 * SECURITY DEFINER helper Stage 1 RLS itself uses (`has_seo_module_access`)
 * via RPC first; if that RPC call fails for any reason (e.g. not exposed on
 * this project), falls back to a direct table read, which Stage 1 RLS
 * explicitly allows for a user's own row. Never throws, never auto-grants
 * access, never uses the service role key.
 */
export async function checkSeoAccessForCurrentUser(): Promise<SeoAccessCheckResult> {
  const userId = await getCurrentUserId();
  if (!userId) {
    return {
      checked: false,
      hasAccess: null,
      method: "none",
      warning: "No authenticated Supabase user (session missing).",
    };
  }

  try {
    const { data, error } = await supabase.rpc(SEO_RPCS.hasSeoModuleAccess);
    if (!error) {
      return { checked: true, hasAccess: Boolean(data), method: "rpc" };
    }
  } catch {
    // Fall through to the direct table read below.
  }

  try {
    const { data, error } = await supabase
      .from(SEO_TABLES.userModuleAccess)
      .select("is_active")
      .eq("user_id", userId)
      .eq("module_name", "seo")
      .maybeSingle();

    if (error) {
      return {
        checked: false,
        hasAccess: null,
        method: "none",
        warning: `Could not read SEO module access: ${normalizeSupabaseError(error).message}`,
      };
    }

    return { checked: true, hasAccess: Boolean(data?.is_active), method: "table" };
  } catch (error) {
    return {
      checked: false,
      hasAccess: null,
      method: "none",
      warning: normalizeSupabaseError(error).message,
    };
  }
}

/**
 * Checks whether the current user already has an SEO workspace membership
 * (Stage 1 `seo_workspace_members`, via `seoWorkspaceService`). Read-only —
 * does NOT create a workspace (unlike `getOrCreateDefaultSeoWorkspace`,
 * which the wired website/onboarding services use). Use the "Test website
 * service" action on the page to exercise the create-on-first-use path.
 */
export async function checkWorkspaceAccessForCurrentUser(): Promise<WorkspaceAccessCheckResult> {
  const { workspace, reason } = await getCurrentSeoWorkspace();
  if (workspace) {
    return {
      checked: true,
      hasWorkspace: true,
      workspaceId: workspace.id,
      workspaceName: workspace.name,
    };
  }
  return { checked: true, hasWorkspace: false, workspaceId: null, workspaceName: null, warning: reason };
}
