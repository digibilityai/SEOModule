// Phase 16B — route constants + safe internal deep-link handling.
// The route-protection matrix itself is expressed declaratively in
// SeoRoutes.tsx via <ProtectedRoute> wrappers; this module holds the shared
// constants and the return-path sanitizer used by the login flow.

export const SEO_LOGIN_PATH = "/seo/login";
export const SEO_DEFAULT_ROUTE = "/seo/dashboard";
export const SEO_SETUP_WORKSPACE_ROUTE = "/seo/onboarding";
export const SEO_SETUP_WEBSITE_ROUTE = "/seo/websites";
export const RETURN_TO_PARAM = "returnTo";

/**
 * Accepts a post-login return destination ONLY when it is a safe internal
 * `/seo/...` path. Rejects absolute URLs, protocol-relative paths, path
 * traversal, and the login route itself (loop prevention). Query + hash are
 * preserved when the base path is safe. Never used to carry credentials.
 */
export function sanitizeReturnPath(raw: string | null | undefined): string | null {
  if (!raw || typeof raw !== "string") return null;
  // Must be an absolute-internal path under /seo/.
  if (!raw.startsWith("/seo/")) return null;
  // Reject protocol-relative ("//host"), smuggled absolute URLs, backslashes,
  // and path traversal.
  if (raw.startsWith("//")) return null;
  if (raw.includes("://")) return null;
  if (raw.includes("\\")) return null;
  if (raw.includes("..")) return null;
  const basePath = raw.split(/[?#]/)[0];
  // Never return to the login page (would loop).
  if (basePath === SEO_LOGIN_PATH) return null;
  return raw;
}

/** Builds `/seo/login?returnTo=<safe-encoded-path>` for an unauthenticated deep link. */
export function buildLoginRedirect(currentPathWithQuery: string): string {
  const safe = sanitizeReturnPath(currentPathWithQuery);
  if (!safe) return SEO_LOGIN_PATH;
  return `${SEO_LOGIN_PATH}?${RETURN_TO_PARAM}=${encodeURIComponent(safe)}`;
}
