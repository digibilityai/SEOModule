import {
  getSeoDataMode as resolveSeoDataMode,
  hasSupabaseConfig,
  type SeoDataMode,
} from "@/config/runtimeConfig";

export type { SeoDataMode };

/**
 * Effective SEO data mode for this session: "mock" or "supabase".
 * Already resolved safely by runtimeConfig — invalid/missing env values or a
 * "supabase" request without valid config are pre-resolved to "mock".
 */
export function getSeoDataMode(): SeoDataMode {
  return resolveSeoDataMode();
}

export function shouldUseSupabaseData(): boolean {
  return getSeoDataMode() === "supabase";
}

let hasWarnedThisSession = false;

/**
 * Logs a data-mode-related warning once per browser session (not once per
 * call) so repeated checks from render loops/hooks don't spam the console.
 */
export function logDataModeWarning(message: string): void {
  if (hasWarnedThisSession) return;
  hasWarnedThisSession = true;
  console.warn(`[SEO data mode] ${message}`);
}

/**
 * Guard for future Supabase-backed services. Returns true only when the
 * caller should proceed with a Supabase call; returns false (logging once)
 * when it should fall back to its mock adapter instead.
 *
 * Not used by any existing service yet — this is Phase 13A foundation only.
 * Future usage (illustrative, not wired):
 *
 *   export async function fetchWebsites(workspaceId: string) {
 *     if (!requireSupabaseOrFallback("websiteService.fetchWebsites")) {
 *       return mockFetchWebsites(workspaceId);
 *     }
 *     return supabaseFetchWebsites(workspaceId);
 *   }
 */
export function requireSupabaseOrFallback(callerLabel: string): boolean {
  if (!shouldUseSupabaseData()) {
    return false;
  }
  if (!hasSupabaseConfig()) {
    logDataModeWarning(
      `${callerLabel} requested Supabase mode but Supabase config is missing. Falling back to mock.`,
    );
    return false;
  }
  return true;
}
