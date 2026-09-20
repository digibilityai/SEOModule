/**
 * What the SEO Module declares to Digi Brain under Module Contract v1.
 *
 * THE KEYS BELOW ARE DIGI BRAIN'S, NOT SEO'S.
 * Contract v1 leaves the operation half of a capability key to the module
 * ("the operation half is module-chosen and never enumerated here"), but Digi
 * Brain's Stage 2A adapter has already frozen the exact six keys it sends
 * (Digi_Brain 96baf21, server/modules/seo/capabilities.ts). Brain refuses any
 * capability its own declaration does not list, and this module refuses any key
 * it does not declare, so a naming disagreement is not a cosmetic difference:
 * it is a total integration failure on every mismatched capability. SEO
 * therefore adopts Brain's names verbatim. Four of them differ from the working
 * names used in the first Stage 2B commit; see SEO_BRAIN_MODULE_INTERFACE.md,
 * "Capability key reconciliation", for the mapping.
 *
 * Family placement is also Brain's. In particular, generating recommendations
 * is an EXECUTE capability there, not an ANALYSE one, because it triggers the
 * specialist's own domain logic and is followed by a separate ANALYSE read.
 *
 * A STATUS poll reuses the SAME capability key as the EXECUTE it follows up.
 * There is deliberately no `status.*` namespace.
 */

import {
  MODULE_CONTRACT_VERSION,
  SEO_MODULE_ID,
  type CapabilityKey,
  type ModuleCapabilityDeclaration,
} from "./contract.ts";

/** Is this Business linked to exactly one SEO website for this host. */
export const CAP_TARGET_LINKAGE = "analyse.target_linkage" as const;
/** Genuine DNS-TXT domain ownership state for the linked website. */
export const CAP_OWNERSHIP_VERIFICATION = "analyse.ownership_verification" as const;
/** Request a genuine technical crawl and audit. Asynchronous. */
export const CAP_REQUEST_TECHNICAL_AUDIT = "execute.technical_audit" as const;
/** Read genuine crawler findings from the latest completed audit run. */
export const CAP_READ_TECHNICAL_AUDIT = "analyse.technical_audit" as const;
/** Generate rule-based recommendations over genuine completed crawl findings. */
export const CAP_GENERATE_RECOMMENDATIONS = "execute.recommendations" as const;
/** Read the current rule-generated recommendation set. */
export const CAP_READ_RECOMMENDATIONS = "analyse.recommendations" as const;

export const DECLARED_CAPABILITIES: readonly CapabilityKey[] = [
  CAP_TARGET_LINKAGE,
  CAP_OWNERSHIP_VERIFICATION,
  CAP_REQUEST_TECHNICAL_AUDIT,
  CAP_READ_TECHNICAL_AUDIT,
  CAP_GENERATE_RECOMMENDATIONS,
  CAP_READ_RECOMMENDATIONS,
];

/** The two capabilities that carry a brainActionId and an idempotencyKey. */
export const EXECUTE_CAPABILITIES: readonly string[] = [
  CAP_REQUEST_TECHNICAL_AUDIT,
  CAP_GENERATE_RECOMMENDATIONS,
];

export const SEO_MODULE_DECLARATION: ModuleCapabilityDeclaration = {
  moduleId: SEO_MODULE_ID,
  contractVersion: MODULE_CONTRACT_VERSION,
  capabilities: DECLARED_CAPABILITIES,
};

export function declaresCapability(capability: string): boolean {
  return (DECLARED_CAPABILITIES as readonly string[]).includes(capability);
}

export function isExecuteCapability(capability: string): boolean {
  return EXECUTE_CAPABILITIES.includes(capability);
}
