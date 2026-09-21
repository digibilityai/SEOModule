/**
 * Digi Brain Module Contract v1, as spoken by the SEO Module.
 *
 * This file is a deliberate MIRROR of the frozen contract that lives in the
 * Digi Brain repository (server/modules/types.ts, merged at 0159a3f,
 * "feat(modular-arch): Stage 1, generic Module Contract v1"). It is not an
 * import and must never become one: the two systems are separate repositories
 * and separate deployments, so SEO carries its own copy of the wire shape and
 * keeps it identical by review, exactly as Digi Brain itself mirrors its
 * EvidenceSourceType list inside lib/evidence/claim-type.v1.ts rather than
 * importing across a boundary.
 *
 * SEO does not own this contract and must not extend it here. Anything SEO
 * needs that the contract does not express is reported as a contract
 * requirement, never added locally.
 */

export const MODULE_CONTRACT_VERSION = "module-contract.v1" as const;
export type ModuleContractVersion = typeof MODULE_CONTRACT_VERSION;

export const SEO_MODULE_ID = "seo" as const;

export const CAPABILITY_FAMILIES = [
  "analyse",
  "execute",
  "status",
  "verify",
  "result_evidence",
] as const;
export type CapabilityFamily = (typeof CAPABILITY_FAMILIES)[number];

export type CapabilityKey = `${CapabilityFamily}.${string}`;

/** Identical rule to Digi Brain's isCapabilityKey. */
export function isCapabilityKey(value: unknown): value is CapabilityKey {
  if (typeof value !== "string") return false;
  const separatorIndex = value.indexOf(".");
  if (separatorIndex <= 0 || separatorIndex === value.length - 1) return false;
  const family = value.slice(0, separatorIndex);
  const operation = value.slice(separatorIndex + 1);
  return (
    (CAPABILITY_FAMILIES as readonly string[]).includes(family) &&
    /^[a-z][a-z0-9_]*$/.test(operation)
  );
}

export const DATA_AUTHENTICITY_VALUES = ["genuine", "not_genuine"] as const;
export type DataAuthenticity = (typeof DATA_AUTHENTICITY_VALUES)[number];

/** Digi Brain's ClaimType (lib/evidence/claim-type.v1.ts). Mirrored verbatim. */
export const CLAIM_TYPES = [
  "measured_external",
  "first_party_connected",
  "public_signal",
  "customer_provided",
  "calculated",
  "inference",
] as const;
export type ObservationMethod = (typeof CLAIM_TYPES)[number];

export const PROVENANCE_BASIS_VALUES = [
  "measured",
  "derived",
  "estimated",
  "declared",
] as const;
export type ProvenanceBasis = (typeof PROVENANCE_BASIS_VALUES)[number];

export interface ModuleProvenance {
  basis: ProvenanceBasis;
  generationMethod?: string;
}

export interface ModuleWebsiteIdentity {
  normalizedHost: string;
  assessedUrl: string;
}

export interface ModuleRequestBase {
  contractVersion: ModuleContractVersion;
  moduleId: string;
  capability: CapabilityKey;
  requestId: string;
  businessId: string;
  websiteIdentity?: ModuleWebsiteIdentity;
  actorId?: string;
}

export interface ModuleResponseBase {
  businessId: string;
  websiteIdentity?: ModuleWebsiteIdentity;
  actorId?: string;
  dataAuthenticity: DataAuthenticity;
  observationMethod: ObservationMethod;
  provenance: ModuleProvenance;
}

export const FINDING_SEVERITIES = ["low", "medium", "high"] as const;
export type FindingSeverity = (typeof FINDING_SEVERITIES)[number];

export interface AnalysisFinding {
  findingKey: string;
  title: string;
  observation: string;
  recommendedAction: string;
  severity: FindingSeverity;
}

export interface AnalysisResult extends ModuleResponseBase {
  findings: readonly AnalysisFinding[];
}

/**
 * EXECUTE family. Accepting a request is an acknowledgement, not a completion.
 * `accepted: false` is a valid genuine response: it is how a module says it
 * received a well formed request and declined to start work, for example
 * because a precondition such as verified domain ownership is not met.
 */
export interface ExecutionAcknowledgement extends ModuleResponseBase {
  brainActionId: string;
  accepted: boolean;
  /** The module's own status vocabulary, carried unmapped. */
  moduleStatus: string;
  /** The module's own stable handle for a genuinely asynchronous operation. */
  moduleOperationId?: string;
}

export interface StatusResult extends ModuleResponseBase {
  brainActionId: string;
  moduleStatus: string;
  moduleOperationId?: string;
}

export interface ModuleCapabilityDeclaration {
  moduleId: string;
  contractVersion: ModuleContractVersion;
  capabilities: readonly CapabilityKey[];
}

export const MODULE_ERROR_CODES = [
  "unsupported_capability",
  "unauthorized",
  "identity_mismatch",
  "target_not_linked",
  "invalid_request",
  "not_genuine",
  "rate_limited",
  "module_unavailable",
  "execution_failed",
  "timeout",
] as const;
export type ModuleErrorCode = (typeof MODULE_ERROR_CODES)[number];

/**
 * A normalized failure this module returns across the boundary. Every failure
 * path produces exactly one of these, so the Brain adapter never has to
 * interpret a transport detail or a Postgres message.
 */
export class SeoModuleContractError extends Error {
  readonly code: ModuleErrorCode;
  /** SEO-side detail for logs only. Never part of the wire body. */
  readonly internalReason?: string;

  constructor(code: ModuleErrorCode, message: string, internalReason?: string) {
    super(message);
    this.name = "SeoModuleContractError";
    this.code = code;
    this.internalReason = internalReason;
  }
}

/** HTTP status the transport uses for each normalized code. */
export const ERROR_HTTP_STATUS: Record<ModuleErrorCode, number> = {
  unsupported_capability: 404,
  unauthorized: 403,
  identity_mismatch: 409,
  target_not_linked: 404,
  invalid_request: 400,
  not_genuine: 422,
  rate_limited: 429,
  module_unavailable: 503,
  execution_failed: 500,
  timeout: 504,
};
