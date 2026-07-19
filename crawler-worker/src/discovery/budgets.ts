// Budgets derived from the job's request-time config snapshot (validated by the
// request RPC). The worker uses these snapshotted values and never exceeds them.

export interface DiscoveryBudgets {
  maxPages: number;
  maxDepth: number;
  crawlTimeoutMs: number;
  perHostDelayMs: number;
  useSitemap: boolean;
  respectRobots: boolean;
  maxResponseBytes: number;
  // Fixed safety caps (not customer-configurable in Phase 1C).
  maxRedirects: number;
  maxSitemaps: number;
  maxSitemapDepth: number;
  maxUrlsPerSitemap: number;
  requestTimeoutMs: number;
}

function num(config: Record<string, unknown>, key: string, def: number): number {
  const v = config[key];
  return typeof v === "number" && Number.isFinite(v) ? v : def;
}
function bool(config: Record<string, unknown>, key: string, def: boolean): boolean {
  const v = config[key];
  return typeof v === "boolean" ? v : def;
}

export function budgetsFromConfig(config: Record<string, unknown>): DiscoveryBudgets {
  const maxResponseBytes = num(config, "max_response_bytes", 5_242_880);
  return {
    maxPages: num(config, "max_pages", 100),
    maxDepth: num(config, "max_depth", 3),
    crawlTimeoutMs: num(config, "crawl_timeout_seconds", 900) * 1000,
    perHostDelayMs: num(config, "per_host_delay_ms", 1000),
    useSitemap: bool(config, "use_sitemap", true),
    respectRobots: bool(config, "respect_robots", true),
    maxResponseBytes,
    maxRedirects: 5,
    maxSitemaps: 50,
    maxSitemapDepth: 5,
    maxUrlsPerSitemap: 5000,
    requestTimeoutMs: 15_000,
  };
}
