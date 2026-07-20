// Phase 16B — route constants + safe internal deep-link handling.
// The route-protection matrix itself is expressed declaratively in
// SeoRoutes.tsx via <ProtectedRoute> wrappers; this module holds the shared
// constants and the return-path sanitizer used by the login flow.
import { getDigibilityAppUrl } from "@/config/runtimeConfig";

export const SEO_LOGIN_PATH = "/seo/login";
export const SEO_BRIDGE_PATH = "/seo/auth/bridge";
export const SEO_LOGOUT_PATH = "/seo/auth/logout";
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
  if (
    basePath === SEO_LOGIN_PATH ||
    basePath === SEO_BRIDGE_PATH ||
    basePath === SEO_LOGOUT_PATH
  ) {
    return null;
  }
  return raw;
}

/** Builds `/seo/login?returnTo=<safe-encoded-path>` for an unauthenticated deep link. */
export function buildLoginRedirect(currentPathWithQuery: string): string {
  const safe = sanitizeReturnPath(currentPathWithQuery);
  if (!safe) return SEO_LOGIN_PATH;
  return `${SEO_LOGIN_PATH}?${RETURN_TO_PARAM}=${encodeURIComponent(safe)}`;
}

/** Cross-origin redirect to the canonical Digibility login. Only a sanitized
 * SEO path is carried; no session or credential is placed in the URL. */
export function buildDigibilityLoginUrl(
  currentPathWithQuery: string,
  appUrl = getDigibilityAppUrl(),
): string {
  const safe = sanitizeReturnPath(currentPathWithQuery) ?? SEO_DEFAULT_ROUTE;
  const base = appUrl.replace(/\/+$/, "");
  if (!base) return buildLoginRedirect(safe);
  return `${base}/login?seoReturnTo=${encodeURIComponent(safe)}`;
}

/**
 * After SEO signs out, clear Digibility via /logout (never pass seoReturnTo —
 * that would immediately re-launch SEO while Digibility was still signed in).
 */
export function buildDigibilityLogoutCascadeUrl(appUrl = getDigibilityAppUrl()): string {
  const base = appUrl.replace(/\/+$/, "");
  if (!base) return SEO_LOGIN_PATH;
  return `${base}/logout?source=seo&continue=${encodeURIComponent("/login")}`;
}

/** Absolute continue URL allowed only for configured Digibility origins. */
export function sanitizeLogoutContinueUrl(
  value: string | null | undefined,
  allowedOrigins: string[],
): string | null {
  if (!value || typeof value !== "string") return null;
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") return null;
    const origin = parsed.origin;
    const allowed = allowedOrigins.map((o) => o.replace(/\/+$/, ""));
    if (!allowed.includes(origin)) return null;
    if (parsed.pathname === "/logout") return `${origin}/login`;
    if (parsed.pathname === SEO_LOGOUT_PATH || parsed.pathname === SEO_BRIDGE_PATH) {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}
