/**
 * Canonical host normalization at the machine boundary.
 *
 * A mirror of Digi Brain's normalizeWebsiteHost (lib/identity/website-identity.ts):
 * lowercase the hostname, strip one leading "www.", keep a non-default port,
 * keep subdomains distinct, and perform no public-suffix reduction. SEO uses it
 * only to VALIDATE that a caller sent an already-canonical host; it never
 * rewrites a caller's host into something else and then resolves against that.
 *
 * The SQL twin of this function is public.seo_brain_normalize_host
 * (migration 20260920120000). The two must agree; normalize-host.test.ts pins
 * the behaviour both are held to.
 *
 * The two pre-existing SEO normalizers are deliberately NOT reused here:
 * seo_ownership_extract_host keeps "www." and drops the port, and the inline
 * normalizer inside seo_competitor_generate drops the port. Both live in locked
 * modules and neither matches the frozen Brain identity.
 */

export function normalizeWebsiteHost(websiteUrl: string): string | null {
  const trimmed = (websiteUrl ?? "").trim();
  if (!trimmed) return null;

  const hasScheme = /^[a-zA-Z][a-zA-Z\d+.-]*:\/\//.test(trimmed);
  let parsed: URL;
  try {
    parsed = new URL(hasScheme ? trimmed : `https://${trimmed}`);
  } catch {
    return null;
  }

  const hostname = parsed.hostname.toLowerCase();
  if (!hostname) return null;

  const strippedHostname = hostname.startsWith("www.")
    ? hostname.slice("www.".length)
    : hostname;
  return parsed.port ? `${strippedHostname}:${parsed.port}` : strippedHostname;
}

/**
 * True when `candidate` is already exactly what normalizeWebsiteHost would
 * produce for itself. A caller that sends a non-canonical host (a scheme, a
 * trailing slash, "www.", mixed case) is refused with invalid_request rather
 * than silently corrected, so the value SEO resolves against is always the
 * value the caller actually asked for.
 */
export function isCanonicalHost(candidate: string): boolean {
  if (typeof candidate !== "string" || candidate.length === 0) return false;
  return normalizeWebsiteHost(candidate) === candidate;
}
