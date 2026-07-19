// ---------------------------------------------------------------------------
// SEO data mode: lets services switch between local mock adapters and a real
// (test) Supabase project without rewriting call sites. Mock is always the
// default and the safe fallback. Nothing in this file throws or performs
// network/IO at import time — it only reads Vite env vars.
// ---------------------------------------------------------------------------

export type SeoDataMode = "mock" | "supabase";

const VALID_DATA_MODES: readonly SeoDataMode[] = ["mock", "supabase"];

function readEnvValue(key: string): string | undefined {
  const raw = (import.meta.env as Record<string, unknown>)[key];
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function getSupabaseUrl(): string {
  const url = readEnvValue("VITE_SUPABASE_URL");
  if (!url) {
    console.warn("VITE_SUPABASE_URL is not set. See .env.example.");
  }
  return url ?? "";
}

export function getSupabaseAnonKey(): string {
  const key = readEnvValue("VITE_SUPABASE_ANON_KEY");
  if (!key) {
    console.warn("VITE_SUPABASE_ANON_KEY is not set. See .env.example.");
  }
  return key ?? "";
}

// Silent presence check (no console.warn) — safe to call as often as needed,
// e.g. on every data-mode resolution, without spamming the console.
export function hasSupabaseConfig(): boolean {
  return Boolean(readEnvValue("VITE_SUPABASE_URL") && readEnvValue("VITE_SUPABASE_ANON_KEY"));
}

let hasWarnedInvalidMode = false;
let hasWarnedMissingConfigForSupabaseMode = false;

/**
 * Resolves the effective SEO data mode for this session.
 *
 * Safety rules (never throws, never crashes at import time):
 * - VITE_SEO_DATA_MODE unset/blank             -> "mock"
 * - VITE_SEO_DATA_MODE has an unrecognized value -> "mock" (+ console warning, once)
 * - VITE_SEO_DATA_MODE="supabase" but URL/anon key missing -> "mock" (+ console warning, once)
 * - VITE_SEO_DATA_MODE="mock"                  -> "mock"
 * - VITE_SEO_DATA_MODE="supabase" and config present -> "supabase"
 */
export function getSeoDataMode(): SeoDataMode {
  const raw = readEnvValue("VITE_SEO_DATA_MODE");

  if (!raw) {
    return "mock";
  }

  const normalized = raw.toLowerCase();

  if (!VALID_DATA_MODES.includes(normalized as SeoDataMode)) {
    if (!hasWarnedInvalidMode) {
      hasWarnedInvalidMode = true;
      console.warn(
        `[SEO data mode] VITE_SEO_DATA_MODE="${raw}" is not recognized (expected "mock" or "supabase"). Falling back to mock mode.`,
      );
    }
    return "mock";
  }

  if (normalized === "supabase" && !hasSupabaseConfig()) {
    if (!hasWarnedMissingConfigForSupabaseMode) {
      hasWarnedMissingConfigForSupabaseMode = true;
      console.warn(
        "[SEO data mode] VITE_SEO_DATA_MODE=supabase but VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY are missing or invalid. Falling back to mock mode.",
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

// Reads more naturally at service call sites, e.g. `if (shouldUseSupabase())`.
// Equivalent to isSupabaseMode().
export function shouldUseSupabase(): boolean {
  return isSupabaseMode();
}
