// Centralized localStorage persistence for mock adapters only. Lets mock
// data (e.g. business onboarding) survive a browser refresh during local
// development, since there's no real backend yet. Mock adapters are the only
// callers — never use this directly from page/UI components.
const PREFIX = "digibility_seo_mock:";

// `isValid` lets callers reject stale-shaped items left over from an earlier
// phase's schema (e.g. a renamed/added field) — falls back to the fresh seed
// instead of handing components data that will crash on the new shape.
export function loadMockCollection<T>(key: string, seed: T[], isValid?: (item: T) => boolean): T[] {
  if (typeof window === "undefined") return seed;
  try {
    const raw = window.localStorage.getItem(PREFIX + key);
    if (!raw) return seed;
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return seed;
    if (isValid && !parsed.every((item) => isValid(item as T))) return seed;
    return parsed as T[];
  } catch {
    return seed;
  }
}

export function saveMockCollection<T>(key: string, collection: T[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PREFIX + key, JSON.stringify(collection));
  } catch {
    // Mock persistence is best-effort — ignore quota/serialization errors.
  }
}
