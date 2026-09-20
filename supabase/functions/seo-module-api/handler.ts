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
  type ExecutionAcknowledgement,
  type FindingSeverity,
  type StatusResult,
  type ModuleWebsiteIdentity,
  type ObservationMethod,
  type ProvenanceBasis,
} from "./contract.ts";
import {
  CAP_GENERATE_RECOMMENDATIONS,
  CAP_OWNERSHIP_VERIFICATION,
  CAP_READ_RECOMMENDATIONS,
  CAP_READ_TECHNICAL_AUDIT,
  CAP_REQUEST_TECHNICAL_AUDIT,
  CAP_TARGET_LINKAGE,
  declaresCapability,
  isExecuteCapability,
} from "./capabilities.ts";
import { isCanonicalHost } from "./normalize-host.ts";
import type {
  DelegatedOperation,
  SeoDataPort,
  TargetResolutionCode,
} from "./port.ts";

/**
 * Which capability-family HTTP path an exchange arrived on. Digi Brain's
 * transport posts one path per family (Digi_Brain 96baf21,
 * server/modules/seo/transport.ts). A STATUS poll arrives on /status while
 * still carrying the originating `execute.*` capability key, per the frozen
 * convention that a status poll is not a second capability.
 */
export type ExchangeFamily = "analyse" | "execute" | "status";

export interface ValidatedRequest {
  contractVersion: typeof MODULE_CONTRACT_VERSION;
  moduleId: string;
  capability: string;
  requestId: string;
  businessId: string;
  websiteIdentity: ModuleWebsiteIdentity;
  actorId?: string;
  brainActionId?: string;
  idempotencyKey?: string;
  moduleOperationId?: string;
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

/**
 * Refusals that concern the acting human rather than the target. All three are
 * `unauthorized`: Contract v1 has no separate code for "identity established
 * but not permitted", and collapsing them keeps the wire from disclosing
 * whether a given Brain actor is mapped at all.
 */
const UNAUTHORIZED_REASONS: ReadonlySet<TargetResolutionCode> = new Set([
  "actor_required",
  "actor_not_linked",
  "actor_unauthorized",
]);

function requireResolved(
  resolution: TargetResolutionCode,
  deps: HandlerDeps,
  request: ValidatedRequest,
): void {
  if (resolution === "resolved" || resolution === "no_completed_audit") return;
  if (UNAUTHORIZED_REASONS.has(resolution)) {
    deps.log?.({
      event: "seo_module_actor_refused",
      requestId: request.requestId,
      capability: request.capability,
      reason: resolution,
    });
    throw new SeoModuleContractError(
      "unauthorized",
      "The acting user is not authorized to perform this SEO operation.",
      resolution,
    );
  }
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

export function validateRequest(rawBody: unknown, family: ExchangeFamily): ValidatedRequest {
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
    throw new SeoModuleContractError(
      "unsupported_capability",
      `The SEO module does not declare capability "${body.capability}".`,
    );
  }

  // The HTTP path and the capability key must agree. A STATUS poll is the one
  // deliberate exception: it arrives on /status carrying the originating
  // execute.* key, which is the frozen convention on both sides.
  if (family === "analyse" && isExecuteCapability(body.capability)) {
    throw new SeoModuleContractError(
      "invalid_request",
      `Capability "${body.capability}" is not an analyse exchange.`,
    );
  }
  if ((family === "execute" || family === "status") && !isExecuteCapability(body.capability)) {
    throw new SeoModuleContractError(
      "invalid_request",
      `Capability "${body.capability}" is not an ${family} exchange.`,
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

  // Action scoped exchanges carry Brain's own correlation identity.
  if (family === "execute" || family === "status") {
    if (!isNonEmptyString(body.brainActionId)) {
      throw new SeoModuleContractError(
        "invalid_request",
        "brainActionId is required for this capability exchange.",
      );
    }
    if (body.moduleOperationId !== undefined && !isNonEmptyString(body.moduleOperationId)) {
      throw new SeoModuleContractError(
        "invalid_request",
        "moduleOperationId, when present, must be non-empty.",
      );
    }
  }
  if (family === "execute" && !isNonEmptyString(body.idempotencyKey)) {
    throw new SeoModuleContractError(
      "invalid_request",
      "idempotencyKey is required for an execution request.",
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
    ...(isNonEmptyString(body.brainActionId) ? { brainActionId: body.brainActionId.trim() } : {}),
    ...(isNonEmptyString(body.idempotencyKey) ? { idempotencyKey: body.idempotencyKey.trim() } : {}),
    ...(isNonEmptyString(body.moduleOperationId)
      ? { moduleOperationId: body.moduleOperationId.trim() }
      : {}),
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
  family: ExchangeFamily,
  deps: HandlerDeps,
): Promise<AnalysisResult | ExecutionAcknowledgement | StatusResult> {
  const request = validateRequest(rawBody, family);

  if (family === "status") {
    return handleStatus(request, deps);
  }

  switch (request.capability) {
    case CAP_TARGET_LINKAGE:
      return handleTargetLinkage(request, deps);
    case CAP_OWNERSHIP_VERIFICATION:
      return handleOwnershipVerification(request, deps);
    case CAP_READ_TECHNICAL_AUDIT:
      return handleCrawlFindings(request, deps);
    case CAP_READ_RECOMMENDATIONS:
      return handleCurrentRecommendations(request, deps);
    case CAP_REQUEST_TECHNICAL_AUDIT:
      return handleRequestTechnicalAudit(request, deps);
    case CAP_GENERATE_RECOMMENDATIONS:
      return handleGenerateRecommendations(request, deps);
    default:
      // Unreachable: validateRequest already refused anything undeclared.
      throw new SeoModuleContractError(
        "unsupported_capability",
        `The SEO module does not declare capability "${request.capability}".`,
      );
  }
}

// ---------------------------------------------------------------------------
// Delegated EXECUTE and STATUS
// ---------------------------------------------------------------------------

/**
 * Shared shape for both acknowledgements and status results.
 *
 * Provenance is `calculated` / `derived` for every one of these: the value
 * being reported is the state of an operation inside SEO's own control plane,
 * computed from SEO's own records. Nothing about the customer's website is
 * measured by accepting a request or by reporting a job's status, and saying
 * `measured` here would overstate what the response actually knows.
 */
function operationResponseBase(
  request: ValidatedRequest,
  generationMethod: string | undefined,
): Omit<StatusResult, "brainActionId" | "moduleStatus"> {
  return {
    businessId: request.businessId,
    websiteIdentity: request.websiteIdentity,
    ...(request.actorId ? { actorId: request.actorId } : {}),
    dataAuthenticity: "genuine",
    observationMethod: "calculated",
    provenance: {
      basis: "derived",
      ...(generationMethod ? { generationMethod } : {}),
    },
  };
}

/**
 * Refusals that are a legitimate, genuine "we did not start this" rather than
 * an error. Contract v1 models exactly this with `accepted: false`, so a
 * precondition failure is reported as a real acknowledgement carrying SEO's own
 * status, not as a thrown error that would discard the reason.
 */
const NOT_ACCEPTED_REASONS: ReadonlySet<TargetResolutionCode> = new Set([
  "ownership_not_verified",
  "no_completed_audit",
  "no_genuine_audit_evidence",
]);

function toAcknowledgement(
  request: ValidatedRequest,
  operation: DelegatedOperation,
  deps: HandlerDeps,
): ExecutionAcknowledgement {
  const brainActionId = request.brainActionId as string;

  if (operation.resolution === "execution_failed" || operation.resolution === "invalid_request") {
    throw new SeoModuleContractError(
      operation.resolution === "invalid_request" ? "invalid_request" : "execution_failed",
      "The SEO module could not start this operation.",
      operation.detail ?? operation.resolution,
    );
  }

  if (NOT_ACCEPTED_REASONS.has(operation.resolution)) {
    deps.log?.({
      event: "seo_module_operation_not_accepted",
      requestId: request.requestId,
      capability: request.capability,
      reason: operation.resolution,
    });
    return {
      ...operationResponseBase(request, undefined),
      brainActionId,
      accepted: false,
      // SEO's own vocabulary, carried unmapped, so Brain can tell a blocked
      // precondition apart from a started operation without parsing prose.
      moduleStatus: operation.resolution,
    };
  }

  requireResolved(operation.resolution, deps, request);

  return {
    ...operationResponseBase(request, operation.generationMethod ?? undefined),
    brainActionId,
    accepted: true,
    moduleStatus: operation.moduleStatus ?? "queued",
    ...(operation.moduleOperationId ? { moduleOperationId: operation.moduleOperationId } : {}),
  };
}

/**
 * Requests a genuine technical crawl and audit.
 *
 * The SQL wrapper resolves the target and the acting human, re-checks the
 * existing workspace role matrix, and then invokes the unchanged
 * seo_crawl_request_audit as that human, so verified ownership, single active
 * job, idempotency and truthful requested_by all behave exactly as they do for
 * a person in the browser. moduleOperationId is the real seo_crawl_jobs id.
 */
async function handleRequestTechnicalAudit(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<ExecutionAcknowledgement> {
  const operation = await deps.db.requestTechnicalAudit({
    businessId: request.businessId,
    normalizedHost: request.websiteIdentity.normalizedHost,
    brainActorId: request.actorId ?? "",
    brainActionId: request.brainActionId as string,
    idempotencyKey: request.idempotencyKey as string,
  });
  return toAcknowledgement(request, operation, deps);
}

/**
 * Generates rule-based recommendations over genuine completed crawl findings.
 *
 * The SQL wrapper refuses outright unless the latest completed audit run
 * actually contains crawler-sourced issues, so generation can never be
 * delegated over a seeded or manual audit. generationMethod is read back from
 * the stored rows rather than asserted here.
 */
async function handleGenerateRecommendations(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<ExecutionAcknowledgement> {
  const operation = await deps.db.generateRecommendations({
    businessId: request.businessId,
    normalizedHost: request.websiteIdentity.normalizedHost,
    brainActorId: request.actorId ?? "",
    brainActionId: request.brainActionId as string,
    idempotencyKey: request.idempotencyKey as string,
  });
  return toAcknowledgement(request, operation, deps);
}

/**
 * STATUS for either execute capability, keyed by the originating capability.
 *
 * Scoped to the exact linked Business and website. An operation this module
 * never accepted is `invalid_request`; a real moduleOperationId belonging to a
 * different website or a different action is `identity_mismatch`, never an
 * answer about some other operation.
 */
async function handleStatus(
  request: ValidatedRequest,
  deps: HandlerDeps,
): Promise<StatusResult> {
  const args = {
    businessId: request.businessId,
    normalizedHost: request.websiteIdentity.normalizedHost,
    brainActionId: request.brainActionId as string,
    ...(request.moduleOperationId ? { moduleOperationId: request.moduleOperationId } : {}),
  };

  const operation =
    request.capability === CAP_REQUEST_TECHNICAL_AUDIT
      ? await deps.db.technicalAuditStatus(args)
      : await deps.db.recommendationStatus(args);

  if (operation.resolution === "operation_mismatch") {
    deps.log?.({
      event: "seo_module_operation_mismatch",
      requestId: request.requestId,
      capability: request.capability,
    });
    throw new SeoModuleContractError(
      "identity_mismatch",
      "The supplied moduleOperationId does not belong to this operation.",
      "operation_mismatch",
    );
  }
  if (operation.resolution === "operation_not_found") {
    throw new SeoModuleContractError(
      "invalid_request",
      "The SEO module has no record of this operation for this Business and website.",
      "operation_not_found",
    );
  }

  requireResolved(operation.resolution, deps, request);

  return {
    ...operationResponseBase(request, undefined),
    brainActionId: request.brainActionId as string,
    moduleStatus: operation.moduleStatus ?? "unknown",
    ...(operation.moduleOperationId ? { moduleOperationId: operation.moduleOperationId } : {}),
  };
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
 * Provenance: `measured_external` / `measured` once a crawl has actually
 * completed. The crawler performs real outbound HTTP against the customer's own
 * site; fixture transport is gated to a test-only CRAWLER_ENV and cannot be
 * enabled in a non-test worker. When no completed audit exists the empty result
 * is SEO's own record of "nothing has been crawled yet", derived from the
 * absence of a run rather than measured, so it is reported as `calculated` /
 * `derived`. Reporting that state as `measured` would claim an outbound
 * observation that never happened. This mirrors exactly how ownership
 * verification reports its own not-yet-checked state.
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
  // not a failure and not a reason to substitute anything. Nothing was
  // measured, so nothing claims to have been.
  if (page.resolution === "no_completed_audit") {
    return baseResponse(request, "calculated", "derived", undefined, []);
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
