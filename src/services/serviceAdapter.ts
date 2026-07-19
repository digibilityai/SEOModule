import { requireSupabaseOrFallback, logDataModeWarning } from "@/services/dataMode";
import { normalizeSupabaseErrorMessage } from "@/services/supabase/supabaseErrors";

/**
 * Foundation for switching an individual service function between its mock
 * implementation and a future Supabase implementation, without touching call
 * sites or removing the mock adapter. Phase 13A only — no existing service
 * uses this yet.
 *
 * Example (future, illustrative — not wired to any real service today):
 *
 *   export function fetchWebsites(workspaceId: string) {
 *     return runWithServiceAdapter({
 *       label: "websiteService.fetchWebsites",
 *       mock: () => mockFetchWebsites(workspaceId),
 *       supabase: () => supabaseFetchWebsites(workspaceId),
 *     });
 *   }
 */
export interface ServiceAdapterOptions<T> {
  /** Used in warning/log messages, e.g. "websiteService.fetchWebsites". */
  label: string;
  /** Mock implementation. Always safe to call; never touches Supabase. */
  mock: () => Promise<T> | T;
  /**
   * Supabase implementation. Only invoked when Supabase mode is active AND
   * configured (checked via requireSupabaseOrFallback); otherwise `mock`
   * runs instead.
   */
  supabase: () => Promise<T> | T;
  /**
   * When true (default), a Supabase call that throws falls back to `mock`
   * instead of propagating the error — a safety net while services are
   * first being wired. Set to false once a service's Supabase path is
   * considered stable and errors should surface instead of being masked.
   */
  fallbackToMockOnError?: boolean;
}

export async function runWithServiceAdapter<T>({
  label,
  mock,
  supabase,
  fallbackToMockOnError = true,
}: ServiceAdapterOptions<T>): Promise<T> {
  if (!requireSupabaseOrFallback(label)) {
    return mock();
  }

  try {
    return await supabase();
  } catch (error) {
    if (!fallbackToMockOnError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}
