// P1a Step 4 — customer-safe frontend shape for Domain Ownership Verification.
// Derived ONLY from the Step 1 customer-safe verification-state table
// (seo_ownership_verifications). The internal claim/lease ledger, lease tokens,
// worker ids, internal diagnostics, correlation ids and service-role metadata
// are NEVER represented here.

/** Absence of a DB row maps to the explicit `unverified` state. */
export type OwnershipVerificationStatus =
  | "unverified"
  | "pending"
  | "verified"
  | "failed"
  | "revoked";

/** DNS TXT is the only MVP method (additively wideable later). */
export type OwnershipVerificationMethod = "dns_txt";

/**
 * Provenance seam. Only `standalone_dns` exists today; kept as a widenable union
 * so a FUTURE trusted Digibility ownership source can be added additively.
 */
export type OwnershipSource = "standalone_dns" | (string & {});

/** Customer-safe, UI-ready ownership-verification state for one website. */
export interface OwnershipVerificationView {
  /** null when unverified (no DB row exists). */
  verificationId: string | null;
  workspaceId: string | null;
  websiteId: string;
  status: OwnershipVerificationStatus;
  method: OwnershipVerificationMethod;
  /** Current host the proof is scoped to (verification_host). */
  verifiedHost: string | null;
  /** DNS TXT record name to place: `_digibility-site-verification.<host>`. */
  dnsTxtName: string | null;
  /** DNS TXT value to place (the challenge token). */
  dnsTxtValue: string | null;
  /** Customer-safe failure reason (never internal diagnostics). */
  failureReason: string | null;
  ownershipSource: OwnershipSource | null;
  /** When the verification/challenge was requested (challenge_created_at). */
  requestedAt: string | null;
  lastCheckedAt: string | null;
  verifiedAt: string | null;
  /**
   * When ownership was revoked. Step 1 has NO dedicated `revoked_at` column, so
   * this is derived (updated_at while status = 'revoked'); null otherwise.
   */
  revokedAt: string | null;
  createdAt: string | null;
  updatedAt: string | null;
}

/** Thrown when a Step 2A ownership RPC returns a REAL rejection (never masked). */
export class OwnershipVerificationWriteError extends Error {
  readonly kind = "ownership_verification_write" as const;
  constructor(message: string) {
    super(message);
    this.name = "OwnershipVerificationWriteError";
  }
}
