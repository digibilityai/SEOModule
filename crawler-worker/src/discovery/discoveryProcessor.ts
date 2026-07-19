// Phase 1D pipeline: discovery (Phase 1C) → extraction → deterministic issue
// detection → site-level duplicate detection → worker-only persistence. Consumes
// the already-fetched bounded HTML (no second fetch), never persists full HTML/
// text, and never writes Page Inventory / Audit / Recommendations / locked tables.
// Refuses non-test jobs (like Phase 1B/1C).
import type { WorkerConfig } from "../config.js";
import type { ClaimedJob, JobGateway, JobMeta } from "../jobGateway.js";
import { NonRetryableExecutionError, CancellationRequestedError, RetryableExecutionError } from "../errors.js";
import type { Transport } from "./transport.js";
import { SafeHttpTransport, CRAWLER_USER_AGENT } from "./safeHttpTransport.js";
import { FixtureTransport } from "./fixtureTransport.js";
import { budgetsFromConfig } from "./budgets.js";
import { DiscoveryEngine, CancelledDuringDiscovery, type DiscoveryResult, type HtmlContext } from "./discovery.js";
import { originFromWebsiteUrl, type AllowedOrigin } from "./urlSafety.js";
import { sleep } from "../util.js";
import { extractPageFacts, type PageFacts } from "../extraction/pageExtractor.js";
import { detectPageIssues, detectSiteDuplicates, type SnapshotForDupe } from "../extraction/issueDetector.js";
import { RULESET_VERSION } from "../extraction/issueRegistry.js";
import { publishJobResults, type PublishOutcome } from "../publishing/publisher.js";

export interface ProcessResult { pagesCrawled: number; pagesDiscovered: number; partial: boolean; published?: PublishOutcome; }

interface Collected { facts: PageFacts; ctx: HtmlContext; }

export class DiscoveryProcessor {
  constructor(private readonly cfg: WorkerConfig, private readonly gateway: JobGateway) {}

  isTestJob(meta: JobMeta): boolean {
    return meta.idempotencyKey.startsWith(this.cfg.testJobPrefix);
  }

  private buildTransport(): Transport {
    if (this.cfg.fixtureTransportPath) return FixtureTransport.fromFile(this.cfg.fixtureTransportPath);
    return new SafeHttpTransport();
  }

  async process(job: ClaimedJob, meta: JobMeta, isCancelledNow: () => Promise<boolean>): Promise<ProcessResult> {
    if (!this.isTestJob(meta) && !this.cfg.allowNonTestJobs) {
      throw new NonRetryableExecutionError("crawler_not_implemented", "Crawling is not yet available for this website.", "refused non-test job");
    }
    const transport = this.buildTransport();
    const budgets = budgetsFromConfig(job.config);
    let origin: AllowedOrigin;
    try { origin = originFromWebsiteUrl(job.websiteUrl); }
    catch { throw new NonRetryableExecutionError("invalid_origin", "The website address is not a crawlable http(s) URL.", "invalid origin"); }

    const collected: Collected[] = [];

    const engine = new DiscoveryEngine(job.websiteUrl, transport, budgets, {
      checkCancelled: isCancelledNow,
      heartbeat: async (c) => {
        await this.gateway.heartbeat(job.jobId, this.cfg.workerId, job.leaseToken, this.cfg.leaseSeconds, c.pagesFetched, c.urlsDiscovered);
        await this.gateway.updateDiscoveryProgress(job.jobId, this.cfg.workerId, job.leaseToken, c);
      },
      onPages: async (pages) => { await this.gateway.recordDiscovery(job.jobId, this.cfg.workerId, job.leaseToken, pages, []); },
      onSitemaps: async (sitemaps) => { await this.gateway.recordDiscovery(job.jobId, this.cfg.workerId, job.leaseToken, [], sitemaps); },
      onHtml: async (ctx, html) => {
        // Extraction happens here (extractor module) — the engine does no analysis.
        const facts = extractPageFacts(html, { finalUrl: ctx.finalUrl, origin, declaredCharset: ctx.declaredCharset, decodeStatus: ctx.decodeStatus, xRobotsTag: ctx.xRobotsTag });
        collected.push({ facts, ctx });
        // html is released when this callback returns (never stored/logged).
      },
      now: () => Date.now(), sleep,
    }, CRAWLER_USER_AGENT);

    let result: DiscoveryResult;
    try { result = await engine.run(); }
    catch (e) {
      if (e instanceof CancelledDuringDiscovery) throw new CancellationRequestedError();
      throw new RetryableExecutionError("discovery_error", "The crawl could not complete.", e instanceof Error ? e.message : String(e));
    }
    if (result.outcome === "failed") {
      throw new NonRetryableExecutionError(result.customerError?.code ?? "discovery_failed", result.customerError?.message ?? "The crawl could not be completed.", "discovery failed");
    }

    // ---- Persist extraction snapshots + issues (idempotent) ----
    let extractionFailed = false;
    try {
      const snapshots = collected.map((c) => this.snapshotPayload(c));
      for (let i = 0; i < snapshots.length; i += 200) await this.gateway.recordSnapshots(job.jobId, this.cfg.workerId, job.leaseToken, snapshots.slice(i, i + 200));
      const idByUrl = await this.gateway.getSnapshotIds(job.jobId);

      for (const c of collected) {
        if (c.facts.extractionStatus !== "extracted") { extractionFailed = true; continue; }
        const url = c.ctx.url;
        const issues = detectPageIssues(c.facts, { normalizedUrl: url, httpStatus: c.ctx.httpStatus, redirectCount: c.ctx.redirectCount, robotsDecision: c.ctx.robotsDecision });
        const snapId = idByUrl.get(url);
        if (issues.length && snapId) await this.gateway.recordIssues(job.jobId, this.cfg.workerId, job.leaseToken, issues, snapId);
      }

      const dupeInput: SnapshotForDupe[] = collected.filter((c) => c.facts.extractionStatus === "extracted").map((c) => ({
        normalizedUrl: c.ctx.url, title: c.facts.title, description: c.facts.description,
        contentHash: c.facts.contentHash, hasContent: c.facts.wordCount > 0,
        indexable: c.facts.effectiveIndex, decodedOk: c.facts.decodeStatus === "ok",
      }));
      const siteIssues = detectSiteDuplicates(dupeInput);
      if (siteIssues.length) await this.gateway.recordIssues(job.jobId, this.cfg.workerId, job.leaseToken, siteIssues, null);

      const indexable = collected.filter((c) => c.facts.effectiveIndex).length;
      await this.gateway.updateExtractionProgress(job.jobId, this.cfg.workerId, job.leaseToken, {
        htmlEligible: collected.length,
        pagesExtracted: collected.filter((c) => c.facts.extractionStatus === "extracted").length,
        extractionFailed: collected.filter((c) => c.facts.extractionStatus !== "extracted").length,
        indexable, noindex: collected.length - indexable,
        issuesDetected: undefined, duplicateGroups: siteIssues.length, rulesetVersion: RULESET_VERSION,
      });
    } catch (e) {
      throw new RetryableExecutionError("persistence_error", "The crawl results could not be saved.", e instanceof Error ? e.message : String(e));
    }

    // ---- Publish into Page Inventory + Audit (Phase 1E) ----
    // Runs BEFORE the worker's terminal completion. The RPC derives the audit
    // run from the job's explicit association (no association => skipped). A
    // publishing failure is an execution failure/retry — never an SEO issue.
    if (await isCancelledNow()) throw new CancellationRequestedError();
    const published = await publishJobResults(this.gateway, job.jobId, this.cfg.workerId, job.leaseToken);
    if (published.status === "no_results") {
      // The associated audit run was marked failed inside the transaction; fail
      // the crawl honestly (no usable output was published).
      throw new NonRetryableExecutionError("no_results", "The crawl produced no usable pages to publish.", "no eligible snapshots to publish");
    }

    const partial = result.outcome === "partially_completed" || extractionFailed;
    return { pagesCrawled: result.counters.pagesFetched, pagesDiscovered: result.counters.urlsDiscovered, partial, published };
  }

  private snapshotPayload(c: Collected): Record<string, unknown> {
    const f = c.facts; const ctx = c.ctx;
    return {
      requestedUrl: ctx.url, finalUrl: ctx.finalUrl, httpStatus: ctx.httpStatus, redirectCount: ctx.redirectCount,
      contentType: ctx.contentType, declaredCharset: f.declaredCharset ?? null, decodeStatus: f.decodeStatus,
      responseBytes: ctx.responseBytes, discoverySource: ctx.discoverySource, depth: ctx.depth, robotsDecision: ctx.robotsDecision,
      title: f.title, titleLen: f.titleLen, titleCount: f.titleCount,
      description: f.description, descriptionLen: f.descriptionLen, descriptionCount: f.descriptionCount,
      h1Count: f.h1Count, firstH1: f.firstH1, h2Count: f.headingCounts.h2, h3Count: f.headingCounts.h3,
      h4Count: f.headingCounts.h4, h5Count: f.headingCounts.h5, h6Count: f.headingCounts.h6,
      htmlLang: f.htmlLang, canonicalCount: f.canonicalCount, canonicalRaw: f.canonicalRaw, canonicalResolved: f.canonicalResolved,
      canonicalClass: f.canonicalClass, metaRobots: f.metaRobots, effectiveIndex: f.effectiveIndex, effectiveFollow: f.effectiveFollow,
      wordCount: f.wordCount, contentHash: f.contentHash, htmlBytesMetric: f.htmlBytesMetric,
      internalLinkCount: f.internalLinkCount, externalLinkCount: f.externalLinkCount, imageCount: f.imageCount,
      imagesMissingAlt: f.imagesMissingAlt, structuredDataBlocks: f.structuredDataBlocks,
      extractionStatus: f.extractionStatus, extractorVersion: RULESET_VERSION, extractionErrorCode: f.extractionErrorCode ?? null,
    };
  }
}
