// ---------------------------------------------------------------------------
// SEO runtime config: production Cloud Run injects window.RUNTIME_CONFIG via
// entrypoint.sh; local Vite continues to use VITE_* from .env.
// ---------------------------------------------------------------------------

export type SeoDataMode = "mock" | "supabase";

const VALID_DATA_MODES: readonly SeoDataMode[] = ["mock", "supabase"];

type SeoRuntimeConfig = {
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  SEO_DATA_MODE?: string;
  DIGIBILITY_APP_URL?: string;
  DIGIBILITY_BRIDGE_URL?: string;
  DIGIBILITY_ANON_KEY?: string;
};

declare global {
  interface Window {
    RUNTIME_CONFIG?: SeoRuntimeConfig;
  }
}

function isNonEmpty(value: string | undefined | null): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function readViteEnv(key: string): string | undefined {
  const raw = (import.meta.env as Record<string, unknown>)[key];
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function readConfigValue(
  runtimeKey: keyof SeoRuntimeConfig,
  viteKey: string,
): string {
  const runtimeValue = typeof window !== "undefined" ? window.RUNTIME_CONFIG?.[runtimeKey] : undefined;
  if (isNonEmpty(runtimeValue)) return runtimeValue.trim();
  return readViteEnv(viteKey) ?? "";
}

export function getSupabaseUrl(): string {
  const url = readConfigValue("SUPABASE_URL", "VITE_SUPABASE_URL");
  if (!url) {
    console.warn("SUPABASE_URL / VITE_SUPABASE_URL is not set. See .env.example.");
  }
  return url;
}

export function getSupabaseAnonKey(): string {
  const key = readConfigValue("SUPABASE_ANON_KEY", "VITE_SUPABASE_ANON_KEY");
  if (!key) {
    console.warn("SUPABASE_ANON_KEY / VITE_SUPABASE_ANON_KEY is not set. See .env.example.");
  }
  return key;
}

export function getDigibilityAppUrl(): string {
  return readConfigValue("DIGIBILITY_APP_URL", "VITE_DIGIBILITY_APP_URL").replace(/\/+$/, "");
}

export function getDigibilityBridgeUrl(): string {
  return readConfigValue("DIGIBILITY_BRIDGE_URL", "VITE_DIGIBILITY_BRIDGE_URL").replace(/\/+$/, "");
}

export function getDigibilityAnonKey(): string {
  return readConfigValue("DIGIBILITY_ANON_KEY", "VITE_DIGIBILITY_ANON_KEY");
}

/** Cross-project SSO is opt-in so existing TEST/local password auth remains
 * available until all bridge infrastructure has been deployed. */
export function hasDigibilityBridgeConfig(): boolean {
  return Boolean(
    getDigibilityAppUrl() &&
      getDigibilityBridgeUrl() &&
      getDigibilityAnonKey(),
  );
}

export function hasSupabaseConfig(): boolean {
  return Boolean(getSupabaseUrl() && getSupabaseAnonKey());
}

let hasWarnedInvalidMode = false;
let hasWarnedMissingConfigForSupabaseMode = false;

/**
 * Resolves the effective SEO data mode for this session.
 *
 * Safety rules (never throws, never crashes at import time):
 * - mode unset/blank             -> "mock"
 * - unrecognized value           -> "mock" (+ console warning, once)
 * - "supabase" but URL/key missing -> "mock" (+ console warning, once)
 */
export function getSeoDataMode(): SeoDataMode {
  const raw = readConfigValue("SEO_DATA_MODE", "VITE_SEO_DATA_MODE");

  if (!raw) {
    return "mock";
  }

  const normalized = raw.toLowerCase();

  if (!VALID_DATA_MODES.includes(normalized as SeoDataMode)) {
    if (!hasWarnedInvalidMode) {
      hasWarnedInvalidMode = true;
      console.warn(
        `[SEO data mode] SEO_DATA_MODE="${raw}" is not recognized (expected "mock" or "supabase"). Falling back to mock mode.`,
      );
    }
    return "mock";
  }

  if (normalized === "supabase" && !hasSupabaseConfig()) {
    if (!hasWarnedMissingConfigForSupabaseMode) {
      hasWarnedMissingConfigForSupabaseMode = true;
      console.warn(
        "[SEO data mode] SEO_DATA_MODE=supabase but SUPABASE_URL / SUPABASE_ANON_KEY are missing or invalid. Falling back to mock mode.",
      );
    }
    return "mock";
  }

  return normalized as SeoDataMode;
}

export function isMockMode(): boolean {
  return getSeoDataMode() === "mock";
}

export function isSupabaseMode(): boolean {
  return getSeoDataMode() === "supabase";
}

export function shouldUseSupabase(): boolean {
  return isSupabaseMode();
}
