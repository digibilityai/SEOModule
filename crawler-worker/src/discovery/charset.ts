// Bounded charset detection + decoding using Node's built-in TextDecoder (ICU),
// so no i18n dependency is added. Order: HTTP charset → bounded meta sniff →
// utf-8 default. An unknown/unsupported label falls back to utf-8 and is
// reported as "unsupported" (never silently treated as valid).
import type { DecodeStatus } from "./transport.js";

export interface DecodedBody { text: string; declaredCharset?: string; decodeStatus: DecodeStatus; }

const SNIFF_BYTES = 2048;

export function charsetFromContentType(contentType: string): string | undefined {
  const m = /;\s*charset\s*=\s*"?([a-zA-Z0-9_\-:.]+)"?/i.exec(contentType);
  return m ? m[1]!.toLowerCase() : undefined;
}

export function sniffMetaCharset(buf: Buffer): string | undefined {
  const head = buf.subarray(0, SNIFF_BYTES).toString("latin1");
  let m = /<meta[^>]+charset\s*=\s*["']?([a-zA-Z0-9_\-:.]+)/i.exec(head);
  if (m) return m[1]!.toLowerCase();
  m = /<meta[^>]+http-equiv\s*=\s*["']?content-type["']?[^>]*content\s*=\s*["'][^"']*charset=([a-zA-Z0-9_\-:.]+)/i.exec(head);
  return m ? m[1]!.toLowerCase() : undefined;
}

/** Decode a bounded body buffer using the best available charset. */
export function decodeBody(buf: Buffer, contentType: string): DecodedBody {
  const declared = charsetFromContentType(contentType) ?? sniffMetaCharset(buf);
  const label = declared ?? "utf-8";
  try {
    // fatal:false → replacement chars rather than throwing on bad bytes.
    const text = new TextDecoder(label, { fatal: false }).decode(buf);
    return { text, declaredCharset: declared, decodeStatus: "ok" };
  } catch {
    // Unknown/unsupported label → utf-8 fallback, reported honestly.
    const text = new TextDecoder("utf-8", { fatal: false }).decode(buf);
    return { text, declaredCharset: declared, decodeStatus: "unsupported" };
  }
}
