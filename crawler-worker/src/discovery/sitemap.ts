// XXE-safe sitemap parsing. Uses fast-xml-parser with entity processing OFF and
// an explicit DOCTYPE/ENTITY rejection, so no external-entity resolution is ever
// possible. Supports urlset + sitemapindex only. Bounds URL count. A malformed
// sitemap yields a safe error, never a crash.
import { XMLParser } from "fast-xml-parser";

export interface SitemapUrl { loc: string; lastmod?: string; }
export type SitemapKind = "urlset" | "sitemapindex" | "unknown";

export interface ParsedSitemap {
  kind: SitemapKind;
  urls: SitemapUrl[];      // urlset locs
  sitemaps: string[];      // sitemapindex child locs
}

export class SitemapError extends Error {
  constructor(message: string) { super(message); this.name = "SitemapError"; }
}

const parser = new XMLParser({
  ignoreAttributes: true,
  processEntities: false, // no entity expansion → no XXE billion-laughs vector
  htmlEntities: false,
  parseTagValue: true,
  trimValues: true,
});

function asArray<T>(v: T | T[] | undefined): T[] {
  if (v === undefined || v === null) return [];
  return Array.isArray(v) ? v : [v];
}

export function parseSitemap(xml: string, maxUrls = 5000): ParsedSitemap {
  // Hard-reject any DTD/entity declarations before parsing.
  if (/<!DOCTYPE/i.test(xml) || /<!ENTITY/i.test(xml)) {
    throw new SitemapError("sitemap contains a DTD/ENTITY declaration (rejected)");
  }
  let doc: Record<string, unknown>;
  try {
    doc = parser.parse(xml) as Record<string, unknown>;
  } catch {
    throw new SitemapError("sitemap XML is malformed");
  }
  if (doc.urlset && typeof doc.urlset === "object") {
    const entries = asArray((doc.urlset as Record<string, unknown>).url).slice(0, maxUrls);
    const urls: SitemapUrl[] = [];
    for (const e of entries) {
      const loc = pickLoc(e);
      if (loc) urls.push({ loc, lastmod: pickStr((e as Record<string, unknown>)?.lastmod) });
    }
    return { kind: "urlset", urls, sitemaps: [] };
  }
  if (doc.sitemapindex && typeof doc.sitemapindex === "object") {
    const entries = asArray((doc.sitemapindex as Record<string, unknown>).sitemap).slice(0, maxUrls);
    const sitemaps: string[] = [];
    for (const e of entries) { const loc = pickLoc(e); if (loc) sitemaps.push(loc); }
    return { kind: "sitemapindex", urls: [], sitemaps };
  }
  return { kind: "unknown", urls: [], sitemaps: [] };
}

function pickLoc(entry: unknown): string | undefined {
  if (typeof entry === "string") return entry.trim() || undefined;
  const loc = (entry as Record<string, unknown>)?.loc;
  return pickStr(loc);
}
function pickStr(v: unknown): string | undefined {
  if (typeof v === "string") return v.trim() || undefined;
  if (typeof v === "number") return String(v);
  return undefined;
}
