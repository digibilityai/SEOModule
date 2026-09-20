/**
 * What the SEO Module declares to Digi Brain under Module Contract v1.
 *
 * Only capabilities that are genuine, tenant-safe and authorizable TODAY are
 * declared. An undeclared capability is refused with unsupported_capability,
 * which the contract defines as "a refusal, never an attempt". That is the
 * correct way to withhold a capability, and it is why the two write
 * capabilities below are absent from DECLARED_CAPABILITIES rather than present
 * and failing at run time.
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
/** Genuine crawler-detected findings from the latest completed audit run. */
export const CAP_CRAWL_FINDINGS = "analyse.crawl_findings" as const;
/** Current rule-generated recommendations for the linked website. */
export const CAP_CURRENT_RECOMMENDATIONS = "analyse.current_recommendations" as const;

export const DECLARED_CAPABILITIES: readonly CapabilityKey[] = [
  CAP_TARGET_LINKAGE,
  CAP_OWNERSHIP_VERIFICATION,
  CAP_CRAWL_FINDINGS,
  CAP_CURRENT_RECOMMENDATIONS,
];

/**
 * Capabilities that are approved in principle and implemented nowhere yet,
 * because both of them WRITE to SEO under a specific human's authority and SEO
 * cannot currently resolve Digi Brain's `actorId` to an SEO user identity.
 *
 * Both `public.seo_crawl_request` and `public.seo_recommendation_generate`
 * authorize on `auth.uid()`, require an owner/admin/team_member role in the
 * website's workspace, and write `created_by` plus append-only activity rows.
 * Digi Brain's `actorId` is an identifier in the Digi Brain Supabase project;
 * SEO users are rows in the SEO project's own `auth.users`. There is no table,
 * column or deterministic rule anywhere in this repository that maps one to the
 * other: `seo_identity_profiles` is keyed on the SEO user id and is unreferenced
 * by any code, and `seo_workspaces.core_profile_id` is an unused nullable seam.
 *
 * Contract v1 is explicit that `actorId` is "never a credential, never trusted
 * by this boundary as authorization", so possession of the machine secret
 * cannot stand in for the acting human. Inventing a mapping (by email, by
 * "the workspace owner", or by reusing the link's `linked_by`) would write a
 * false `created_by` into an audit trail the product treats as evidence.
 *
 * These stay undeclared until an explicit, human-authorized actor mapping
 * exists. See SEO_BRAIN_MODULE_INTERFACE.md, "Blocked write capabilities".
 */
export const WITHHELD_CAPABILITIES: Readonly<Record<string, string>> = {
  "execute.technical_crawl":
    "seo_crawl_request authorizes on auth.uid() and writes created_by; Brain actorId has no deterministic SEO user mapping.",
  "analyse.recommendation_generation":
    "seo_recommendation_generate authorizes on auth.uid() and writes created_by; Brain actorId has no deterministic SEO user mapping.",
};

export const SEO_MODULE_DECLARATION: ModuleCapabilityDeclaration = {
  moduleId: SEO_MODULE_ID,
  contractVersion: MODULE_CONTRACT_VERSION,
  capabilities: DECLARED_CAPABILITIES,
};

export function declaresCapability(capability: string): boolean {
  return (DECLARED_CAPABILITIES as readonly string[]).includes(capability);
}
