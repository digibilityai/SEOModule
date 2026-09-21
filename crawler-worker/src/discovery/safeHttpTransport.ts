// SSRF- and DNS-rebinding-safe HTTP client. Every hop validates the URL, and a
// custom connection-time `lookup` resolves + validates ALL addresses and pins a
// single validated address for the socket (so the address connected to is the
// address validated — no check-then-connect rebinding window). TLS hostname
// verification stays enabled (never rejectUnauthorized:false). No cookies, no
// credential/header forwarding, fixed crawler user-agent, GET only, no body,
// bounded compressed + decompressed size, timeouts, MIME allowlist, abort.
import http from "node:http";
import https from "node:https";
import zlib from "node:zlib";
import dns from "node:dns";
import { classifyIp } from "./ipSafety.js";
import { normalizeUrl } from "./urlSafety.js";
import { decodeBody } from "./charset.js";
import { FetchError, type FetchOptions, type FetchResult, type Transport } from "./transport.js";

export const CRAWLER_USER_AGENT = "DigibilitySEO-Crawler/0.1 (+discovery; robots-respected)";

export interface LookupAddress { address: string; family: number }
/**
 * Node calls a custom `lookup` in one of TWO shapes and expects the callback to
 * answer in the SAME shape:
 *   options.all !== true  -> callback(err, address, family)
 *   options.all === true  -> callback(err, [{ address, family }, ...])
 * Both are covered here.
 */
export type LookupCb = {
  (err: NodeJS.ErrnoException | null, address: string, family: number): void;
  (err: NodeJS.ErrnoException | null, addresses: LookupAddress[]): void;
};
export interface LookupOptions { all?: boolean; family?: number; hints?: number }

// Connection-time DNS validation. Rejects the whole target if ANY resolved
// address is unsafe; otherwise returns only all-validated addresses.
//
// WHY THE `all` BRANCH EXISTS. Since Node 20, happy-eyeballs address-family
// autoselection (`net.getDefaultAutoSelectFamily() === true`) calls this lookup
// with `{ all: true }` and expects an ARRAY back. The previous implementation
// always replied with the single-address shape, so Node read `address` as
// undefined and every request died with ERR_INVALID_IP_ADDRESS, surfacing as an
// unexplained `network_error`. No host could be fetched on Node 20 or later.
// The fix is to honour the callback contract, NOT to disable autoselection:
// turning autoselection off would hide the contract break and give up IPv6/IPv4
// fallback for every crawl.
//
// SECURITY IS UNCHANGED AND STILL FAILS CLOSED. Every candidate address is
// classified before anything is returned, and a single unsafe address rejects
// the WHOLE target rather than filtering it out, exactly as before. Returning
// the full validated list is safe precisely because every member passed the
// same check the single pinned address had to pass: Node may connect to any of
// them, and all of them are validated, so the no-rebinding-window property is
// preserved.
function safeLookup(hostname: string, options: LookupOptions | undefined, callback: LookupCb): void {
  // Honour a requested address family; 0 or absent means "no preference".
  const family = options?.family === 4 || options?.family === 6 ? options.family : undefined;
  const resolveOptions = { all: true as const, verbatim: true, ...(family ? { family } : {}) };
  dns.lookup(hostname, resolveOptions, (err, addresses) => {
    if (err) return (callback as (e: NodeJS.ErrnoException | null, a: string, f: number) => void)(err as NodeJS.ErrnoException, "", 0);
    if (!addresses.length) {
      return (callback as (e: NodeJS.ErrnoException | null, a: string, f: number) => void)(new Error("no DNS answer") as NodeJS.ErrnoException, "", 0);
    }
    for (const a of addresses) {
      const d = classifyIp(a.address);
      if (!d.safe) {
        return (callback as (e: NodeJS.ErrnoException | null, a: string, f: number) => void)(
          new FetchError("ssrf_blocked", `blocked address for ${hostname}: ${d.reason}`) as unknown as NodeJS.ErrnoException, "", 0);
      }
    }
    if (options?.all === true) {
      const validated: LookupAddress[] = addresses.map((a) => ({ address: a.address, family: a.family }));
      return (callback as (e: NodeJS.ErrnoException | null, a: LookupAddress[]) => void)(null, validated);
    }
    const chosen = addresses[0]!;
    (callback as (e: NodeJS.ErrnoException | null, a: string, f: number) => void)(null, chosen.address, chosen.family);
  });
}

export const __testing = { safeLookup };

interface HopResult { status: number; location?: string; contentType: string; body: Buffer; truncated: boolean; xRobotsTag?: string; }

// Only these response headers are ever retained (indexing directive). No other
// header (set-cookie/authorization/etc.) is read or stored.
const RETAINED_HEADERS = ["x-robots-tag"];

function oneHop(url: string, opts: FetchOptions): Promise<HopResult> {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const isHttps = u.protocol === "https:";
    const lib = isHttps ? https : http;
    const req = lib.request(
      url,
      {
        method: "GET",
        lookup: safeLookup as unknown as typeof dns.lookup,
        servername: isHttps ? u.hostname : undefined,
        timeout: opts.timeoutMs,
        headers: {
          "user-agent": CRAWLER_USER_AGENT,
          accept: opts.purpose === "html" ? "text/html" : "text/plain, application/xml, text/xml, application/gzip",
          "accept-encoding": "gzip, deflate, br",
        },
        // never inherit an implicit proxy / never forward credentials
      },
      (res) => {
        const status = res.statusCode ?? 0;
        const location = res.headers.location;
        const contentType = String(res.headers["content-type"] ?? "");
        const xr = res.headers[RETAINED_HEADERS[0]!];
        const xRobotsTag = Array.isArray(xr) ? xr.join(", ") : xr ? String(xr) : undefined;
        // Redirects: don't download the body — the caller revalidates + re-fetches.
        if (status >= 300 && status < 400 && location) {
          res.destroy();
          return resolve({ status, location, contentType, body: Buffer.alloc(0), truncated: false, xRobotsTag });
        }
        const chunks: Buffer[] = [];
        let total = 0;
        let truncated = false;
        res.on("data", (c: Buffer) => {
          total += c.length;
          if (total > opts.maxBytes) {
            truncated = true;
            res.destroy();
            return;
          }
          chunks.push(c);
        });
        res.on("end", () => {
          const raw = Buffer.concat(chunks);
          const enc = String(res.headers["content-encoding"] ?? "").toLowerCase();
          try {
            const body = decompress(raw, enc, opts.maxBytes);
            resolve({ status, contentType, body: body.buf, truncated: truncated || body.truncated, xRobotsTag });
          } catch (e) {
            reject(new FetchError("decompress_failed", "response could not be decompressed"));
          }
        });
        res.on("error", () => reject(new FetchError("response_error", "response stream error", true)));
      },
    );
    req.on("timeout", () => { req.destroy(new FetchError("timeout", "request timed out", true)); });
    req.on("error", (e) => {
      if (e instanceof FetchError) return reject(e);
      // Keep the underlying cause in the INTERNAL message. The FetchError code
      // stays "network_error", so nothing that is stored or shown to a customer
      // changes; this only stops a failure like ERR_INVALID_IP_ADDRESS from
      // being reduced to an unexplained "network request failed" in logs.
      const cause = (e as NodeJS.ErrnoException)?.code;
      reject(new FetchError("network_error", cause ? `network request failed (${cause})` : "network request failed", true));
    });
    if (opts.signal) {
      if (opts.signal.aborted) { req.destroy(new FetchError("cancelled", "aborted")); }
      opts.signal.addEventListener("abort", () => req.destroy(new FetchError("cancelled", "aborted")), { once: true });
    }
    req.end();
  });
}

function decompress(raw: Buffer, enc: string, maxBytes: number): { buf: Buffer; truncated: boolean } {
  const o = { maxOutputLength: maxBytes };
  try {
    if (enc === "gzip") return { buf: zlib.gunzipSync(raw, o), truncated: false };
    if (enc === "deflate") return { buf: zlib.inflateSync(raw, o), truncated: false };
    if (enc === "br") return { buf: zlib.brotliDecompressSync(raw, { maxOutputLength: maxBytes }), truncated: false };
    return { buf: raw.subarray(0, maxBytes), truncated: raw.length > maxBytes };
  } catch (e) {
    // maxOutputLength exceeded → treat as oversized (bounded), not a crash.
    if (e instanceof RangeError) throw new FetchError("response_too_large", "decompressed body exceeds limit");
    throw e;
  }
}

export class SafeHttpTransport implements Transport {
  async fetch(url: string, opts: FetchOptions): Promise<FetchResult> {
    const started = Date.now();
    let current = normalizeUrl(url); // validates scheme/host/port/userinfo/control-chars
    let redirectCount = 0;
    for (;;) {
      const hop = await oneHop(current, opts);
      if (hop.status >= 300 && hop.status < 400 && hop.location) {
        redirectCount += 1;
        if (redirectCount > opts.maxRedirects) throw new FetchError("too_many_redirects", "redirect limit exceeded");
        // Re-validate the redirect target independently (SSRF is enforced again
        // by safeLookup on the next hop; here we enforce scheme/host safety).
        current = normalizeUrl(hop.location, current);
        continue;
      }
      const contentType = hop.contentType.split(";")[0]!.trim().toLowerCase();
      if (opts.allowedMimeTypes.length && contentType && !opts.allowedMimeTypes.includes(contentType)) {
        throw new FetchError("disallowed_mime", `mime not allowed: ${contentType}`);
      }
      const decoded = decodeBody(hop.body, hop.contentType);
      return {
        finalUrl: current,
        status: hop.status,
        contentType,
        bodyText: decoded.text,
        bytes: hop.body.length,
        redirectCount,
        truncated: hop.truncated,
        durationMs: Date.now() - started,
        declaredCharset: decoded.declaredCharset,
        decodeStatus: decoded.decodeStatus,
        xRobotsTag: hop.xRobotsTag,
      };
    }
  }
}
