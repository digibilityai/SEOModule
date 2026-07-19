// HTML link discovery for page discovery ONLY — no rendering, no JS, no scoring.
// Extracts <a href> navigational links, resolves relatives against a conservative
// base, drops fragments, enforces the allowed origin, and normalizes + dedupes.
// A <base> that would widen beyond the approved origin is ignored.
import { parse } from "node-html-parser";
import { normalizeUrl, isAllowedOrigin, isNonCrawlableScheme, type AllowedOrigin } from "./urlSafety.js";

export function extractSameOriginLinks(html: string, pageUrl: string, origin: AllowedOrigin, maxLinks = 2000): string[] {
  let root;
  try {
    root = parse(html, { blockTextElements: { script: false, style: false } });
  } catch {
    return []; // malformed HTML must not crash discovery
  }

  // Conservative <base href>: only honour it if it is same-origin; otherwise the
  // page URL remains the resolution base (never widen the origin via <base>).
  let base = pageUrl;
  const baseHref = root.querySelector("base")?.getAttribute("href");
  if (baseHref) {
    try {
      const candidate = normalizeUrl(baseHref, pageUrl);
      if (isAllowedOrigin(candidate, origin)) base = candidate;
    } catch { /* ignore unsafe base */ }
  }

  const out = new Set<string>();
  for (const a of root.querySelectorAll("a")) {
    if (out.size >= maxLinks) break;
    const href = a.getAttribute("href");
    if (!href) continue;
    const raw = href.trim();
    if (raw === "" || raw.startsWith("#")) continue;
    if (isNonCrawlableScheme(raw)) continue; // mailto/tel/javascript/data/etc.
    let normalized: string;
    try {
      normalized = normalizeUrl(raw, base);
    } catch {
      continue;
    }
    if (!isAllowedOrigin(normalized, origin)) continue;
    out.add(normalized);
  }
  return [...out];
}
