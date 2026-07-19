// Deterministic, budgeted page-discovery engine. Robots → sitemaps → BFS HTML
// link discovery, all through an injected Transport (SSRF-safe in production,
// fixture in tests). Records safe discovery metadata via hooks. Performs NO SEO
// analysis and never writes to Page Inventory / Audit tables.
import type { Transport } from "./transport.js";
import { FetchError } from "./transport.js";
import type { DiscoveryBudgets } from "./budgets.js";
import { originFromWebsiteUrl, normalizeUrl, isAllowedOrigin, UrlError, type AllowedOrigin } from "./urlSafety.js";
import { parseRobots, ALLOW_ALL, type RobotsPolicy } from "./robots.js";
import { parseSitemap, SitemapError } from "./sitemap.js";
import { extractSameOriginLinks } from "./htmlLinks.js";

export type DiscoveryOutcome = "completed" | "partially_completed" | "failed";
export type DiscoverySource = "start" | "sitemap" | "html_link";

export interface DiscoveredPage {
  normalizedUrl: string;
  discoveredUrl: string;
  finalUrl?: string;
  discoverySource: DiscoverySource;
  parentUrl?: string;
  sitemapUrl?: string;
  depth: number;
  queueOrder: number;
  robotsDecision: "allowed" | "disallowed" | "not_evaluated";
  fetchStatus: "fetched" | "blocked_robots" | "skipped" | "failed" | "queued";
  httpStatus?: number;
  contentType?: string;
  responseBytes?: number;
  redirectCount?: number;
  sitemapLastmod?: string;
  errorCode?: string;
}

export interface DiscoveredSitemap {
  sitemapUrl: string;
  parentSitemapUrl?: string;
  sitemapType: "urlset" | "sitemapindex" | "unknown";
  fetchStatus: "parsed" | "failed";
  urlsDiscovered: number;
  errorCode?: string;
  depth: number;
}

export interface DiscoveryCounters {
  urlsDiscovered: number; urlsQueued: number; pagesAttempted: number; pagesFetched: number;
  pagesBlockedRobots: number; pagesSkipped: number; pagesFailed: number;
  sitemapsAttempted: number; sitemapsParsed: number; bytesReceived: number;
}

export interface HtmlContext {
  url: string; finalUrl: string; httpStatus: number; redirectCount: number;
  contentType: string; responseBytes: number; depth: number; discoverySource: DiscoverySource;
  robotsDecision: "allowed" | "disallowed" | "not_evaluated";
  declaredCharset?: string; decodeStatus: "ok" | "unsupported"; xRobotsTag?: string;
}

export interface DiscoveryHooks {
  checkCancelled: () => Promise<boolean>;
  heartbeat: (c: DiscoveryCounters) => Promise<void>;
  onPages: (pages: DiscoveredPage[]) => Promise<void>;
  onSitemaps: (sitemaps: DiscoveredSitemap[]) => Promise<void>;
  /** Hands the already-fetched, bounded HTML body to the extraction layer.
   *  The discovery engine performs NO SEO analysis itself. Body is released after. */
  onHtml?: (ctx: HtmlContext, html: string) => Promise<void>;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
}

export interface DiscoveryResult { outcome: DiscoveryOutcome; counters: DiscoveryCounters; customerError?: { code: string; message: string }; }

const HTML_MIME = ["text/html", "application/xhtml+xml"];
const SITEMAP_MIME = ["application/xml", "text/xml", "application/gzip", "text/plain", ""];
const ROBOTS_MIME = ["text/plain", ""];
const HEARTBEAT_EVERY = 10;

export class CancelledDuringDiscovery extends Error {
  constructor() { super("cancelled during discovery"); this.name = "CancelledDuringDiscovery"; }
}

interface QueueItem {
  url: string; depth: number; source: DiscoverySource;
  parent?: string; sitemap?: string; lastmod?: string; queueOrder: number;
}

export class DiscoveryEngine {
  private counters: DiscoveryCounters = {
    urlsDiscovered: 0, urlsQueued: 0, pagesAttempted: 0, pagesFetched: 0,
    pagesBlockedRobots: 0, pagesSkipped: 0, pagesFailed: 0,
    sitemapsAttempted: 0, sitemapsParsed: 0, bytesReceived: 0,
  };
  private seen = new Set<string>();
  private pageBatch: DiscoveredPage[] = [];
  private hadFailures = false;
  private budgetReached = false;
  private order = 0;

  constructor(
    private readonly websiteUrl: string,
    private readonly transport: Transport,
    private readonly budgets: DiscoveryBudgets,
    private readonly hooks: DiscoveryHooks,
    private readonly userAgent: string,
  ) {}

  async run(): Promise<DiscoveryResult> {
    let origin: AllowedOrigin;
    let start: string;
    try {
      origin = originFromWebsiteUrl(this.websiteUrl);
      start = normalizeUrl(this.websiteUrl);
    } catch (e) {
      return { outcome: "failed", counters: this.counters, customerError: { code: "invalid_origin", message: "The website address is not a crawlable http(s) URL." } };
    }
    const deadline = this.hooks.now() + this.budgets.crawlTimeoutMs;

    const robots = this.budgets.respectRobots ? await this.loadRobots(origin) : ALLOW_ALL;

    // Queue: [url, depth, source, parent, sitemap, lastmod]
    const queue: QueueItem[] = [];
    this.enqueue(queue, start, 0, "start");

    if (this.budgets.useSitemap) {
      const sitemapUrls = await this.discoverSitemaps(origin, robots, deadline);
      for (const s of sitemapUrls) this.enqueue(queue, s.loc, 0, "sitemap", undefined, s.sitemapUrl, s.lastmod);
    }

    let processed = 0;
    while (queue.length > 0) {
      if (this.counters.pagesFetched >= this.budgets.maxPages) { this.budgetReached = true; break; }
      if (this.hooks.now() >= deadline) { this.budgetReached = true; break; }
      if (await this.hooks.checkCancelled()) throw new CancelledDuringDiscovery();

      const item = queue.shift()!;
      if (robots.isAllowed(new URL(item.url).pathname)) {
        await this.hooks.sleep(this.budgets.perHostDelayMs);
        await this.fetchPage(item, origin, robots, queue);
      } else {
        this.counters.pagesBlockedRobots++;
        this.record({ normalizedUrl: item.url, discoveredUrl: item.url, discoverySource: item.source, parentUrl: item.parent, sitemapUrl: item.sitemap, depth: item.depth, queueOrder: item.queueOrder, robotsDecision: "disallowed", fetchStatus: "blocked_robots" });
      }
      processed++;
      if (processed % HEARTBEAT_EVERY === 0) await this.flushAndBeat();
    }

    await this.flushAndBeat();

    let outcome: DiscoveryOutcome;
    if (this.counters.pagesFetched === 0 && this.counters.urlsDiscovered <= 1 && this.hadFailures) outcome = "failed";
    else if (this.budgetReached || this.hadFailures) outcome = "partially_completed";
    else outcome = "completed";
    return { outcome, counters: this.counters };
  }

  private enqueue(queue: QueueItem[], url: string, depth: number, source: DiscoverySource, parent?: string, sitemap?: string, lastmod?: string): void {
    let n: string;
    try { n = normalizeUrl(url); } catch { return; }
    if (this.seen.has(n)) return;
    this.seen.add(n);
    this.counters.urlsDiscovered++;
    this.counters.urlsQueued++;
    const qo = this.order++;
    queue.push({ url: n, depth, source, parent, sitemap, lastmod, queueOrder: qo });
  }

  private async fetchPage(item: QueueItem, origin: AllowedOrigin, robots: RobotsPolicy, queue: QueueItem[]): Promise<void> {
    this.counters.pagesAttempted++;
    try {
      const res = await this.transport.fetch(item.url, {
        purpose: "html", maxBytes: this.budgets.maxResponseBytes, timeoutMs: this.budgets.requestTimeoutMs,
        maxRedirects: this.budgets.maxRedirects, allowedMimeTypes: HTML_MIME,
      });
      this.counters.bytesReceived += res.bytes;
      if (res.status >= 200 && res.status < 300 && res.contentType.startsWith("text/html")) {
        this.counters.pagesFetched++;
        this.record({ normalizedUrl: item.url, discoveredUrl: item.url, finalUrl: res.finalUrl, discoverySource: item.source, parentUrl: item.parent, sitemapUrl: item.sitemap, depth: item.depth, queueOrder: item.queueOrder, robotsDecision: "allowed", fetchStatus: "fetched", httpStatus: res.status, contentType: res.contentType, responseBytes: res.bytes, redirectCount: res.redirectCount, sitemapLastmod: item.lastmod });
        // Hand the bounded body to the extraction layer (no second fetch).
        if (this.hooks.onHtml) {
          await this.hooks.onHtml({
            url: item.url, finalUrl: res.finalUrl, httpStatus: res.status, redirectCount: res.redirectCount,
            contentType: res.contentType, responseBytes: res.bytes, depth: item.depth, discoverySource: item.source,
            robotsDecision: "allowed", declaredCharset: res.declaredCharset, decodeStatus: res.decodeStatus, xRobotsTag: res.xRobotsTag,
          }, res.bodyText);
        }
        if (item.depth < this.budgets.maxDepth) {
          for (const link of extractSameOriginLinks(res.bodyText, res.finalUrl, origin)) {
            this.enqueue(queue, link, item.depth + 1, "html_link", item.url);
          }
        }
      } else {
        this.counters.pagesSkipped++;
        this.record({ normalizedUrl: item.url, discoveredUrl: item.url, finalUrl: res.finalUrl, discoverySource: item.source, parentUrl: item.parent, depth: item.depth, queueOrder: item.queueOrder, robotsDecision: "allowed", fetchStatus: "skipped", httpStatus: res.status, contentType: res.contentType, responseBytes: res.bytes });
      }
    } catch (e) {
      this.counters.pagesFailed++;
      this.hadFailures = true;
      const code = e instanceof FetchError ? e.code : e instanceof UrlError ? "unsafe_url" : "fetch_error";
      this.record({ normalizedUrl: item.url, discoveredUrl: item.url, discoverySource: item.source, parentUrl: item.parent, depth: item.depth, queueOrder: item.queueOrder, robotsDecision: "allowed", fetchStatus: "failed", errorCode: code });
    }
  }

  private async loadRobots(origin: AllowedOrigin): Promise<RobotsPolicy> {
    const robotsUrl = `${origin.scheme}://${origin.host}/robots.txt`;
    try {
      const res = await this.transport.fetch(robotsUrl, { purpose: "robots", maxBytes: 524_288, timeoutMs: this.budgets.requestTimeoutMs, maxRedirects: this.budgets.maxRedirects, allowedMimeTypes: ROBOTS_MIME });
      if (res.status === 200) return parseRobots(res.bodyText, this.userAgent);
      // 4xx (missing) → allow-all; 5xx → conservative allow-all but recorded.
      return ALLOW_ALL;
    } catch {
      return ALLOW_ALL; // missing/unreachable robots → treat as allowed (standard)
    }
  }

  private async discoverSitemaps(origin: AllowedOrigin, robots: RobotsPolicy, deadline: number): Promise<Array<{ loc: string; sitemapUrl: string; lastmod?: string }>> {
    const found: Array<{ loc: string; sitemapUrl: string; lastmod?: string }> = [];
    const sitemapRecords: DiscoveredSitemap[] = [];
    const roots = [...robots.sitemaps, `${origin.scheme}://${origin.host}/sitemap.xml`];
    const queue: Array<{ url: string; depth: number; parent?: string }> = [];
    const seenSm = new Set<string>();
    for (const r of roots) { try { const n = normalizeUrl(r); if (isAllowedOrigin(n, origin) && !seenSm.has(n)) { seenSm.add(n); queue.push({ url: n, depth: 0 }); } } catch { /* skip */ } }

    while (queue.length && sitemapRecords.length < this.budgets.maxSitemaps) {
      if (this.hooks.now() >= deadline) break;
      const s = queue.shift()!;
      this.counters.sitemapsAttempted++;
      try {
        const res = await this.transport.fetch(s.url, { purpose: "sitemap", maxBytes: this.budgets.maxResponseBytes, timeoutMs: this.budgets.requestTimeoutMs, maxRedirects: this.budgets.maxRedirects, allowedMimeTypes: SITEMAP_MIME });
        if (res.status !== 200) { sitemapRecords.push({ sitemapUrl: s.url, parentSitemapUrl: s.parent, sitemapType: "unknown", fetchStatus: "failed", urlsDiscovered: 0, errorCode: `http_${res.status}`, depth: s.depth }); continue; }
        const parsed = parseSitemap(res.bodyText, this.budgets.maxUrlsPerSitemap);
        this.counters.sitemapsParsed++;
        let added = 0;
        for (const u of parsed.urls) { try { const n = normalizeUrl(u.loc); if (isAllowedOrigin(n, origin)) { found.push({ loc: n, sitemapUrl: s.url, lastmod: u.lastmod }); added++; } } catch { /* skip */ } }
        if (parsed.kind === "sitemapindex" && s.depth < this.budgets.maxSitemapDepth) {
          for (const child of parsed.sitemaps) { try { const n = normalizeUrl(child); if (isAllowedOrigin(n, origin) && !seenSm.has(n)) { seenSm.add(n); queue.push({ url: n, depth: s.depth + 1, parent: s.url }); } } catch { /* skip */ } }
        }
        sitemapRecords.push({ sitemapUrl: s.url, parentSitemapUrl: s.parent, sitemapType: parsed.kind, fetchStatus: "parsed", urlsDiscovered: added, depth: s.depth });
      } catch (e) {
        this.hadFailures = true;
        const code = e instanceof SitemapError ? "sitemap_malformed" : e instanceof FetchError ? e.code : "sitemap_error";
        sitemapRecords.push({ sitemapUrl: s.url, parentSitemapUrl: s.parent, sitemapType: "unknown", fetchStatus: "failed", urlsDiscovered: 0, errorCode: code, depth: s.depth });
      }
    }
    if (sitemapRecords.length) await this.hooks.onSitemaps(sitemapRecords);
    return found;
  }

  private record(p: DiscoveredPage): void { this.pageBatch.push(p); }

  private async flushAndBeat(): Promise<void> {
    if (this.pageBatch.length) { const b = this.pageBatch; this.pageBatch = []; await this.hooks.onPages(b); }
    await this.hooks.heartbeat(this.counters);
  }
}
