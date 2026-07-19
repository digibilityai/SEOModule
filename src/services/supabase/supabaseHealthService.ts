import { supabase } from "@/integrations/supabase/client";
import { getSeoDataMode, hasSupabaseConfig, type SeoDataMode } from "@/config/runtimeConfig";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

export interface SupabaseReadinessResult {
  mode: SeoDataMode;
  configured: boolean;
  hasSession: boolean;
  userId: string | null;
  warnings: string[];
  checkedAt: string;
}

/**
 * Read-only diagnostic check for the Supabase data-mode switching
 * foundation. Never writes to the database and never queries protected SEO
 * tables. Does NOT require login to "pass" — an unauthenticated session is a
 * valid, reportable state, not a failure. Safe to call in mock mode too: it
 * simply reports `mode: "mock"` plus whatever config/session state exists.
 */
export async function checkSupabaseReadiness(): Promise<SupabaseReadinessResult> {
  const mode = getSeoDataMode();
  const configured = hasSupabaseConfig();
  const warnings: string[] = [];

  if (!configured) {
    warnings.push(
      "VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY are not set — Supabase mode is unavailable and the app is using mock mode.",
    );
  }

  if (mode === "mock" && configured) {
    warnings.push(
      'Supabase config is present but VITE_SEO_DATA_MODE is not "supabase" — the app is still using mock data.',
    );
  }

  let hasSession = false;
  let userId: string | null = null;

  if (configured) {
    try {
      const { data, error } = await supabase.auth.getSession();
      if (error) {
        warnings.push(
          `auth.getSession() returned an error: ${normalizeSupabaseError(error).message}`,
        );
      } else {
        hasSession = Boolean(data.session);
        userId = data.session?.user.id ?? null;
        if (!hasSession) {
          warnings.push(
            "No active Supabase session — expected if no one is logged in yet; this is not a failure.",
          );
        }
      }
    } catch (error) {
      warnings.push(`auth.getSession() threw: ${normalizeSupabaseError(error).message}`);
    }
  } else {
    warnings.push("Skipped auth.getSession() check because Supabase is not configured.");
  }

  return {
    mode,
    configured,
    hasSession,
    userId,
    warnings,
    checkedAt: new Date().toISOString(),
  };
}
