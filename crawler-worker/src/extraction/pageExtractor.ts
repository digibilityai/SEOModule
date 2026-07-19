// Bounded technical-fact extraction from an in-memory HTML body already fetched
// by SafeHttpTransport (NO second fetch). Extracts only technical metadata +
// counts + a content hash — never persists full HTML/text, scripts, JSON-LD,
// forms, cookies, headers, or personal data. No DB writes, no network.
import crypto from "node:crypto";
import { parse, type HTMLElement } from "node-html-parser";
import { normalizeText, comparisonKey } from "./textNormalize.js";
import { normalizeUrl, isAllowedOrigin, type AllowedOrigin } from "../discovery/urlSafety.js";
import type { DecodeStatus } from "../discovery/transport.js";

export type CanonicalClass =
  | "missing" | "self" | "same_origin_other" | "cross_origin"
  | "invalid" | "unsafe" | "multiple";

export interface PageFacts {
  extractionStatus: "extracted" | "decode_failed" | "parse_failed";
  extractionErrorCode?: string;
  titleCount: number; title: string; titleLen: number; titleTruncated: boolean;
  descriptionCount: number; description: string; descriptionLen: number;
  h1Count: number; firstH1: string;
  headingCounts: { h1: number; h2: number; h3: number; h4: number; h5: number; h6: number };
  htmlLang: string;
  canonicalCount: number; canonicalRaw: string; canonicalResolved: string; canonicalClass: CanonicalClass;
  metaRobots: string; effectiveIndex: boolean; effectiveFollow: boolean;
  wordCount: number; contentHash: string; contentKeyForDupe: string;
  htmlBytesMetric: number;
  internalLinkCount: number; externalLinkCount: number;
  imageCount: number; imagesMissingAlt: number;
  structuredDataBlocks: number;
  declaredCharset?: string; decodeStatus: DecodeStatus;
}

export interface ExtractContext {
  finalUrl: string; origin: AllowedOrigin; declaredCharset?: string; decodeStatus: DecodeStatus; xRobotsTag?: string;
}

const MAX_CANONICAL_RAW = 2048;
const MAX_TEXT_FOR_HASH = 500_000; // bound text processing

function metaByName(root: HTMLElement, name: string): HTMLElement[] {
  return root.querySelectorAll("meta").filter((m) => (m.getAttribute("name") ?? "").toLowerCase() === name);
}

function parseRobotsDirectives(...sources: string[]): { index: boolean; follow: boolean; raw: string } {
  const tokens = sources.join(",").toLowerCase().split(/[,\s]+/).filter(Boolean);
  let index = true, follow = true;
  for (const t of tokens) {
    if (t === "noindex") index = false;
    if (t === "nofollow") follow = false;
    if (t === "none") { index = false; follow = false; } // restrictive wins
  }
  return { index, follow, raw: normalizeText(sources.filter(Boolean).join("; "), 256).text };
}

function classifyCanonical(raws: string[], finalUrl: string, origin: AllowedOrigin): { cls: CanonicalClass; raw: string; resolved: string } {
  if (raws.length === 0) return { cls: "missing", raw: "", resolved: "" };
  if (raws.length > 1) return { cls: "multiple", raw: raws[0]!.slice(0, MAX_CANONICAL_RAW), resolved: "" };
  const raw = raws[0]!.trim().slice(0, MAX_CANONICAL_RAW);
  let resolved: string;
  try {
    resolved = normalizeUrl(raw, finalUrl); // same URL-safety primitives; resolves relative
  } catch {
    // unsupported scheme / userinfo / port / control chars → unsafe; malformed → invalid
    return { cls: /^\s*[a-z][a-z0-9+.-]*:/i.test(raw) ? "unsafe" : "invalid", raw, resolved: "" };
  }
  if (!isAllowedOrigin(resolved, origin)) return { cls: "cross_origin", raw, resolved };
  let self: string;
  try { self = normalizeUrl(finalUrl); } catch { self = finalUrl; }
  return { cls: resolved === self ? "self" : "same_origin_other", raw, resolved };
}

export function extractPageFacts(html: string, ctx: ExtractContext): PageFacts {
  const base: Pick<PageFacts, "declaredCharset" | "decodeStatus"> = { declaredCharset: ctx.declaredCharset, decodeStatus: ctx.decodeStatus };
  let root: HTMLElement;
  try {
    root = parse(html, { blockTextElements: { script: false, style: false, noscript: false } });
  } catch {
    return { ...emptyFacts(), ...base, extractionStatus: "parse_failed", extractionErrorCode: "html_parse_failed" };
  }

  const titles = root.querySelectorAll("title");
  const titleN = normalizeText(titles[0]?.text, 512);
  const descs = metaByName(root, "description");
  const descN = normalizeText(descs[0]?.getAttribute("content"), 1024);
  const h1s = root.querySelectorAll("h1");
  const firstH1 = normalizeText(h1s[0]?.text, 512);

  const canonEls = root.querySelectorAll("link").filter((l) => (l.getAttribute("rel") ?? "").toLowerCase() === "canonical");
  const canon = classifyCanonical(canonEls.map((c) => c.getAttribute("href") ?? "").filter(Boolean), ctx.finalUrl, ctx.origin);

  const metaRobots = metaByName(root, "robots").map((m) => m.getAttribute("content") ?? "").join(", ");
  const rob = parseRobotsDirectives(metaRobots, ctx.xRobotsTag ?? "");

  // Count structured-data blocks BEFORE removing scripts for text extraction.
  const structuredDataBlocks = root.querySelectorAll('script[type="application/ld+json"]').length;

  // visible text (script/style/noscript/template excluded), bounded, hashed.
  for (const el of root.querySelectorAll("script, style, noscript, template")) el.remove();
  let visible = root.text.replace(/\s+/g, " ").trim();
  if (visible.length > MAX_TEXT_FOR_HASH) visible = visible.slice(0, MAX_TEXT_FOR_HASH);
  const wordCount = visible === "" ? 0 : visible.split(" ").length;
  const contentHash = crypto.createHash("sha256").update(comparisonKey(visible)).digest("hex");

  // links (same-origin vs external), images, structured-data blocks.
  let internal = 0, external = 0;
  for (const a of root.querySelectorAll("a")) {
    const href = a.getAttribute("href"); if (!href) continue;
    try { if (isAllowedOrigin(normalizeUrl(href, ctx.finalUrl), ctx.origin)) internal++; else external++; } catch { /* skip */ }
  }
  const imgs = root.querySelectorAll("img");
  const imagesMissingAlt = imgs.filter((i) => { const a = i.getAttribute("alt"); return a === undefined || a === null || a.trim() === ""; }).length;

  return {
    ...base,
    extractionStatus: "extracted",
    titleCount: titles.length, title: titleN.text, titleLen: titleN.text.length, titleTruncated: titleN.truncated,
    descriptionCount: descs.length, description: descN.text, descriptionLen: descN.text.length,
    h1Count: h1s.length, firstH1: firstH1.text,
    headingCounts: {
      h1: h1s.length, h2: root.querySelectorAll("h2").length, h3: root.querySelectorAll("h3").length,
      h4: root.querySelectorAll("h4").length, h5: root.querySelectorAll("h5").length, h6: root.querySelectorAll("h6").length,
    },
    htmlLang: normalizeText(root.querySelector("html")?.getAttribute("lang"), 32).text,
    canonicalCount: canonEls.length, canonicalRaw: canon.raw, canonicalResolved: canon.resolved, canonicalClass: canon.cls,
    metaRobots: rob.raw, effectiveIndex: rob.index, effectiveFollow: rob.follow,
    wordCount, contentHash, contentKeyForDupe: contentHash,
    htmlBytesMetric: Buffer.byteLength(html),
    internalLinkCount: internal, externalLinkCount: external,
    imageCount: imgs.length, imagesMissingAlt,
    structuredDataBlocks,
  };
}

function emptyFacts(): PageFacts {
  return {
    extractionStatus: "extracted", titleCount: 0, title: "", titleLen: 0, titleTruncated: false,
    descriptionCount: 0, description: "", descriptionLen: 0, h1Count: 0, firstH1: "",
    headingCounts: { h1: 0, h2: 0, h3: 0, h4: 0, h5: 0, h6: 0 }, htmlLang: "",
    canonicalCount: 0, canonicalRaw: "", canonicalResolved: "", canonicalClass: "missing",
    metaRobots: "", effectiveIndex: true, effectiveFollow: true,
    wordCount: 0, contentHash: "", contentKeyForDupe: "", htmlBytesMetric: 0,
    internalLinkCount: 0, externalLinkCount: 0, imageCount: 0, imagesMissingAlt: 0, structuredDataBlocks: 0,
    decodeStatus: "ok",
  };
}
