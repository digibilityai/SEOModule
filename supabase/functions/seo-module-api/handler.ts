/**
 * The transport-neutral request handler for the SEO machine boundary.
 *
 * Pure with respect to I/O: every database touch goes through the injected
 * SeoDataPort, so this whole file is exercisable in Node by vitest and is
 * structurally incapable of reaching src/, src/services/serviceAdapter.ts or
 * src/mocks/. Fails closed: every path either returns a validated Contract v1
 * result or throws exactly one normalized SeoModuleContractError.
 */

import {
  MODULE_CONTRACT_VERSION,
  SEO_MODULE_ID,
  SeoModuleContractError,
  isCapabilityKey,
  type AnalysisFinding,
  type AnalysisResult,
  type FindingSeverity,
  type ModuleWebsiteIdentity,
  type ObservationMethod,
  type ProvenanceBasis,
} from "./contract.ts";
import {
  CAP_CRAWL_FINDINGS,
  CAP_CURRENT_RECOMMENDATIONS,
  CAP_OWNERSHIP_VERIFICATION,
  CAP_TARGET_LINKAGE,
  WITHHELD_CAPABILITIES,
  declaresCapability,
} from "./capabilities.ts";
import { isCanonicalHost } from "./normalize-host.ts";
import type {
  SeoDataPort,
  TargetResolutionCode,
} from "./port.ts";

export interface ValidatedRequest {
  contractVersion: typeof MODULE_CONTRACT_VERSION;
  moduleId: string;
  capability: string;
  requestId: string;
  businessId: string;
  websiteIdentity: ModuleWebsiteIdentity;
  actorId?: string;
}

export interface HandlerDeps {
  db: SeoDataPort;
  /** Optional sink for SEO-side diagnostic detail that never crosses the wire. */
  log?: (event: Record<string, unknown>) => void;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * Every non-'resolved' resolution the SQL layer can report collapses to
 * target_not_linked at the contract boundary, which is exactly what Contract v1
 * defines that code to mean: "no linked or resolvable record at all for the
 * requested Business and/or website". The specific reason is kept SEO-side for
 * logs and is never leaked to the caller, so a machine caller cannot probe this
 * endpoint to learn which websites exist.
 */
const NOT_LINKED_REASONS: ReadonlySet<TargetResolutionCode> = new Set([
  "not_linked",
  "revoked",
  "host_changed",
  "website_inactive",
  "website_missing",
  "invalid_target",
]);

function requireResolved(
  resolution: TargetResolutionCode,
  deps: HandlerDeps,
  request: ValidatedRequest,
): void {
  if (resolution === "resolved" || resolution === "no_completed_audit") return;
  if (NOT_LINKED_REASONS.has(resolution)) {
    deps.log?.({
      event: "seo_module_target_not_linked",
      requestId: request.requestId,
      capability: request.capability,
      reason: resolution,
    });
    throw new SeoModuleContractError(
      "target_not_linked",
      "No active Digi Brain link exists for this Business and website.",
      resolution,
    );
  }
  throw new SeoModuleContractError(
    "module_unavailable",
    "The SEO module returned an unrecognized target resolution.",
    resolution,
  );
}

/**
 * SEO carries a four-level severity (critical/high/medium/low); Contract v1
 * carries three. `critical` collapses onto `high` because the contract has no
 * higher level, and collapsing upward is the only direction that cannot
 * understate a finding.
 */
function toFindingSeverity(seoSeverity: string | null | undefined): FindingSeverity {
  switch ((seoSeverity ?? "").toLowerCase()) {
    case "critical":
    case "high":
      return "high";
    case "medium":
      return "medium";
    case "low":
      return "low";
    default:
      return "medium";
  }
}

/** Returns the single shared value of a column, or undefined when it varies. */
function uniformValue(values: readonly (string | null)[]): string | undefined {
  const present = values.filter(isNonEmptyString);
  if (present.length === 0 || present.length !== values.length) return undefined;
  const first = present[0];
  return present.every((value) => value === first) ? first : undefined;
}

export function validateRequest(rawBody: unknown): ValidatedRequest {
  if (typeof rawBody !== "object" || rawBody === null || Array.isArray(rawBody)) {
    throw new SeoModuleContractError("invalid_request", "Request body must be a JSON object.");
  }
  const body = rawBody as Record<string, unknown>;

  if (body.contractVersion !== MODULE_CONTRACT_VERSION) {
    throw new SeoModuleContractError(
      "invalid_request",
      `Unsupported contract version; this module speaks "${MODULE_CONTRACT_VERSION}".`,
    );
  }
  if (body.moduleId !== SEO_MODULE_ID) {
    throw new SeoModuleContractError(
      "invalid_request",
      `This endpoint serves moduleId "${SEO_MODULE_ID}".`,
    );
  }
  if (!isNonEmptyString(body.requestId)) {
    throw new SeoModuleContractError("invalid_request", "requestId is required.");
  }
  if (!isNonEmptyString(body.businessId)) {
    throw new SeoModuleContractError("invalid_request", "businessId is required.");
  }
  if (!isCapabilityKey(body.capability)) {
    throw new SeoModuleContractError("invalid_request", "capability is not a valid capability key.");
  }
  if (body.actorId !== undefined && !isNonEmptyString(body.actorId)) {
    throw new SeoModuleContractError("invalid_request", "actorId, when present, must be non-empty.");
  }

  if (!declaresCapability(body.capability)) {
    const withheld = WITHHELD_CAPABILITIES[body.capability];
    throw new SeoModuleContractError(
      "unsupported_capability",
      `The SEO module does not declare capability "${body.capability}".`,
      withheld,
    );
  }

  // Every capability this module declares is website scoped.
  const identity = body.websiteIdentity as ModuleWebsiteIdentity | undefined;
  if (
    typeof identity !== "object" ||
    identity === null ||
    !isNonEmptyString(identity.normalizedHost) ||
    !isNonEmptyString(identity.assessedUrl)
  ) {
    throw new SeoModuleContractError(
      "invalid_request",
      "websiteIdentity with normalizedHost and assessedUrl is required for this capability.",
    );
  }
  // The caller must already have normalized the host. SEO refuses a
  // non-canonical value rather than rewriting it, so the value resolved against
  // is always the value the caller actually asked for.
  if (!isCanonicalHost(identity.normalizedHost)) {
    throw new SeoModuleContractError(
      "invalid_request",
      "websiteIdentity.normalizedHost is not a canonical normalized host.",
    );
  }

  return {
    contractVersion: MODULE_CONTRACT_VERSION,
    moduleId: SEO_MODULE_ID,
    capability: body.capability,
    requestId: body.requestId.trim(),
    businessId: body.businessId.trim(),
    websiteIdentity: {
      normalizedHost: identity.normalizedHost,
      assessedUrl: identity.assessedUrl,
    },
    ...(isNonEmptyString(body.actorId) ? { actorId: body.actorId.trim() } : {}),
  };
}

function baseResponse(
  request: ValidatedRequest,
  observationMethod: ObservationMethod,
  basis: ProvenanceBasis,
  generationMethod: string | undefined,
  findings: AnalysisFinding[],
): AnalysisResult {
  return {
    // Echoed verbatim. Digi Brain refuses any response whose businessId or
    // normalizedHost differs from the request, so echoing the resolved values
    // instead of the requested ones would turn a substitution into a silent
    // success. SEO echoes the request and separately asserts that what it
    // resolved matches it.
    businessId: request.businessId,
    websiteIdentity: request.websiteIdentity,
    ...(request.actorId ? { actorId: request.actorId } : {}),
    dataAuthenticity: "genuine",
    observationMethod,
    provenance: {
      basis,
      ...(generationMethod ? { generationMethod } : {}),
    },
    findings,
  };
}

/**
 * Independent restatement of the anti-substitution guarantee the SQL layer
 * already enforces. If SEO ever resolved a host other than the one asked for,
 * this refuses rather than returning data under the requested identity.
 */
function assertNoSubstitution(request: ValidatedRequest, resolvedHost: string | null): void {
  if (resolvedHost !== null && resolvedHost !== request.websiteIdentity.normalizedHost) {
    throw new SeoModuleContractError(
      "identity_mismatch",
      "The SEO module resolved a different website than the one requested.",
      `requested=${request.websiteIdentity.normalizedHost} resolved=${resolvedHost}`,
    );
  }
}

export async function handleModuleRequest(
  rawBody: unknown,
  deps: HandlerDeps,
): Promise<AnalysisResult> {
  const request = validateRequest(rawBody);

  switch (request.capability) {
    case CAP_TARGET_LINKAGE:
      return handleTargetLinkage(request, deps);
    case CAP_OWNERSHIP_VERIFICATION:
      return handleOwnershipVerification(request, deps);
    case CAP_CRAWL_FINDINGS:
      return handleCrawlFindings(request, deps);
    case CAP_CURRENT_RECOMMENDATIONS:
      return handleCurrentRecommendations(request, deps);
    default:
      // Unreachable: validateRequest already refused anything undeclared.
      throw new SeoModuleContractError(
        "unsupported_capability",
        `The SEO module does not declare capability "${request.capability}".`,
      );
  }
}

/**
 * Linkage. A successful result with zero findings IS the answer: this Business
 * resolves to exactly one active SEO website for this host. An unlinked,
 * revoked or diverged target raises target_not_linked instead.
 *
 * Provenance: the link is a statement a human owner/admin made, so it is
 * `declared`, carried under the `customer_provided` claim type. It is genuine
 * (a real, human-authorized row) but it is not a measurement.
 */
async function handleTargetLinkage(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<AnalysisResult> {
  const target = await deps.db.resolveTarget(
    request.businessId,
    request.websiteIdentity.normalizedHost,
  );
  requireResolved(target.resolution, deps, request);
  assertNoSubstitution(request, target.normalizedHost);
  return baseResponse(request, "customer_provided", "declared", undefined, []);
}

/**
 * Domain ownership. The only genuinely externally verified fact SEO holds: the
 * DNS-TXT challenge is resolved against real DNS by the verification worker.
 *
 * Provenance: `measured_external` / `measured` once a check has actually run
 * (last_checked_at present). When no check has ever run, the returned state is
 * SEO's own record of "not started", which is derived from the absence of a
 * verification, not measured; it is reported as `calculated` / `derived` so it
 * can never be mistaken for a performed DNS observation.
 */
async function handleOwnershipVerification(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<AnalysisResult> {
  const ownership = await deps.db.ownershipStatus(
    request.businessId,
    request.websiteIdentity.normalizedHost,
  );
  requireResolved(ownership.resolution, deps, request);

  const checked = isNonEmptyString(ownership.lastCheckedAt);
  const status = (ownership.status ?? "not_started").toLowerCase();
  const verified = status === "verified";

  const findings: AnalysisFinding[] = verified
    ? []
    : [
        {
          findingKey: "seo.ownership.dns_txt_not_verified",
          title: "Domain ownership is not verified",
          observation:
            `Domain ownership for ${request.websiteIdentity.normalizedHost} is "${status}"` +
            (isNonEmptyString(ownership.failureReason) ? `: ${ownership.failureReason}` : "."),
          recommendedAction:
            "Publish the Digibility DNS TXT verification record for this domain, then re-run verification. " +
            "Technical crawling and auditing stay blocked until ownership is verified.",
          severity: "high",
        },
      ];

  return baseResponse(
    request,
    checked ? "measured_external" : "calculated",
    checked ? "measured" : "derived",
    checked ? "dns_txt_ownership_verification" : undefined,
    findings,
  );
}

/**
 * Crawler findings. Restricted in SQL to source = 'crawler' rows from the
 * latest COMPLETED audit run, so a manual, seeded or imported issue can never
 * be returned here. `findingKey` is the crawler's own issue fingerprint, which
 * is the stable evidence anchor back to the crawl that produced it.
 *
 * Provenance: `measured_external` / `measured`. The crawler performs real
 * outbound HTTP against the customer's own site; fixture transport is gated to
 * a test-only CRAWLER_ENV and cannot be enabled in a non-test worker.
 */
async function handleCrawlFindings(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<AnalysisResult> {
  const page = await deps.db.crawlFindings(
    request.businessId,
    request.websiteIdentity.normalizedHost,
  );
  requireResolved(page.resolution, deps, request);

  // A linked website with no completed audit yet is a legitimate empty result,
  // not a failure and not a reason to substitute anything.
  if (page.resolution === "no_completed_audit") {
    return baseResponse(request, "measured_external", "measured", undefined, []);
  }

  // Defence in depth behind the SQL authenticity gate.
  const nonCrawler = page.findings.find((finding) => finding.source !== "crawler");
  if (nonCrawler) {
    throw new SeoModuleContractError(
      "not_genuine",
      "The SEO module refused to return a finding that did not originate from the crawler.",
      `findingKey=${nonCrawler.findingKey} source=${String(nonCrawler.source)}`,
    );
  }

  const findings: AnalysisFinding[] = page.findings.map((finding) => ({
    findingKey: finding.findingKey,
    title: finding.title,
    observation: finding.observation,
    recommendedAction: finding.recommendedAction,
    severity: toFindingSeverity(finding.severity),
  }));

  return baseResponse(
    request,
    "measured_external",
    "measured",
    uniformValue(page.findings.map((finding) => finding.sourceRuleVersion)),
    findings,
  );
}

/**
 * Current recommendations. Restricted in SQL to is_current rows carrying a
 * non-null generation_method, which is what distinguishes a row the rule-based
 * generator produced from a legacy, manual or seeded row.
 *
 * Provenance: `calculated` / `derived`, with generationMethod carrying the
 * value stored on the rows themselves (rule_based_v1 today) rather than a
 * constant written here, so the response can never overstate how a
 * recommendation was produced.
 */
async function handleCurrentRecommendations(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<AnalysisResult> {
  const page = await deps.db.currentRecommendations(
    request.businessId,
    request.websiteIdentity.normalizedHost,
  );
  requireResolved(page.resolution, deps, request);

  const ungenerated = page.recommendations.find(
    (recommendation) => !isNonEmptyString(recommendation.generationMethod),
  );
  if (ungenerated) {
    throw new SeoModuleContractError(
      "not_genuine",
      "The SEO module refused to return a recommendation with no recorded generation method.",
      `recommendationId=${ungenerated.recommendationId}`,
    );
  }

  const findings: AnalysisFinding[] = page.recommendations.map((recommendation) => ({
    findingKey: recommendation.findingKey,
    title: recommendation.title,
    observation: recommendation.whyItHelps,
    recommendedAction: recommendation.suggestedChange,
    severity: toFindingSeverity(recommendation.impact),
  }));

  return baseResponse(
    request,
    "calculated",
    "derived",
    uniformValue(page.recommendations.map((recommendation) => recommendation.generationMethod)),
    findings,
  );
}
