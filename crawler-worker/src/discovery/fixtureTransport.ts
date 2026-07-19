// TEST-ONLY transport that serves canned responses from a JSON fixture — no
// network access at all. Loaded only when CRAWLER_ENV starts with "test" and a
// fixture path is configured (see config.ts). The production process can never
// enable it. Used to make the discovery security + logic deterministically
// testable (robots/sitemaps/redirects/HTML/timeouts/oversized/etc.).
import { readFileSync } from "node:fs";
import { FetchError, type FetchOptions, type FetchResult, type Transport } from "./transport.js";

interface FixtureResponse {
  status?: number;
  contentType?: string;
  body?: string;
  location?: string;       // for a redirect response
  error?: string;          // e.g. "timeout" | "ssrf_blocked" — throws a FetchError
  bytes?: number;
  declaredCharset?: string;
  decodeStatus?: "ok" | "unsupported";
  xRobotsTag?: string;
}
export type FixtureMap = Record<string, FixtureResponse>;

export class FixtureTransport implements Transport {
  constructor(private readonly map: FixtureMap) {}

  static fromFile(path: string): FixtureTransport {
    return new FixtureTransport(JSON.parse(readFileSync(path, "utf8")) as FixtureMap);
  }

  async fetch(url: string, opts: FetchOptions): Promise<FetchResult> {
    let current = url;
    let redirectCount = 0;
    for (;;) {
      const r = this.map[current];
      if (!r) return { finalUrl: current, status: 404, contentType: "text/plain", bodyText: "", bytes: 0, redirectCount, truncated: false, durationMs: 0, decodeStatus: "ok" };
      if (r.error) throw new FetchError(r.error, `fixture error: ${r.error}`, r.error === "timeout" || r.error === "network_error");
      const status = r.status ?? 200;
      if (status >= 300 && status < 400 && r.location) {
        redirectCount++;
        if (redirectCount > opts.maxRedirects) throw new FetchError("too_many_redirects", "redirect limit exceeded");
        current = new URL(r.location, current).toString();
        continue;
      }
      const contentType = (r.contentType ?? "text/html").split(";")[0]!.trim().toLowerCase();
      if (opts.allowedMimeTypes.length && contentType && !opts.allowedMimeTypes.includes(contentType)) {
        throw new FetchError("disallowed_mime", `mime not allowed: ${contentType}`);
      }
      const body = r.body ?? "";
      const bytes = r.bytes ?? Buffer.byteLength(body);
      if (bytes > opts.maxBytes) throw new FetchError("response_too_large", "fixture body exceeds limit");
      return { finalUrl: current, status, contentType, bodyText: body, bytes, redirectCount, truncated: false, durationMs: 0,
               declaredCharset: r.declaredCharset, decodeStatus: r.decodeStatus ?? "ok", xRobotsTag: r.xRobotsTag };
    }
  }
}
