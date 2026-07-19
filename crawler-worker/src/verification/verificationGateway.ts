// Ownership-verification RPC gateway. The runner reaches Supabase ONLY through
// this gateway, and ONLY via the Step 2B service-role RPCs — it never reads or
// writes the seo_ownership_* tables directly, and it never touches any crawler
// object. Mirrors the crawler JobGateway conventions (typed rows + ContractError)
// but is a completely separate class (no crawl coupling).
import type { SupabaseClient } from "@supabase/supabase-js";
import { ContractError } from "../errors.js";

/** The fields the DNS worker needs, returned by seo_ownership_verification_claim. */
export interface ClaimedVerification {
  verificationId: string;
  workspaceId: string;
  websiteId: string;
  verificationHost: string;
  dnsTxtName: string;
  /** The exact TXT value to match. NEVER logged. */
  expectedChallengeValue: string;
  /** Lease ownership token. NEVER logged. */
  leaseToken: string;
  leaseExpiresAt: string;
}

export type VerificationOutcome = "verified" | "failed";

/** Raised when the result RPC rejects a stale/mismatched claim — a safe stop. */
export class VerificationResultRejected extends Error {
  readonly kind = "result_rejected" as const;
  constructor(message: string) { super(message); this.name = "VerificationResultRejected"; }
}

export class VerificationGateway {
  constructor(private readonly db: SupabaseClient) {}

  /** Claim ONE eligible pending/failed verification item (Step 2B RPC). */
  async claim(workerId: string, leaseSeconds: number): Promise<ClaimedVerification | null> {
    const { data, error } = await this.db.rpc("seo_ownership_verification_claim", {
      p_worker_id: workerId,
      p_lease_seconds: leaseSeconds,
    });
    if (error) throw new ContractError(`ownership claim failed: ${error.message}`);
    const rows = (data as unknown[]) ?? [];
    if (rows.length === 0) return null;
    const r = rows[0] as Record<string, unknown>;
    const claim: ClaimedVerification = {
      verificationId: String(r.verification_id),
      workspaceId: String(r.workspace_id),
      websiteId: String(r.website_id),
      verificationHost: String(r.verification_host),
      dnsTxtName: String(r.dns_txt_name),
      expectedChallengeValue: String(r.expected_challenge_value),
      leaseToken: String(r.lease_token),
      leaseExpiresAt: String(r.lease_expires_at),
    };
    if (!claim.verificationId || !claim.leaseToken || !claim.dnsTxtName || !claim.expectedChallengeValue) {
      throw new ContractError("ownership claim returned an incomplete row");
    }
    return claim;
  }

  /**
   * Persist a result via the Step 2B result RPC ONLY. A customer-safe reason and
   * (for failures) an internal code/detail that stays on the admin-only claim
   * row. Duplicate identical results are idempotent server-side. A stale/
   * mismatched claim raises VerificationResultRejected (the runner stops safely).
   */
  async recordResult(
    claim: ClaimedVerification,
    workerId: string,
    outcome: VerificationOutcome,
    failureReason?: string,
    internalCode?: string,
    internalDetail?: string,
  ): Promise<void> {
    const { error } = await this.db.rpc("seo_ownership_verification_record_result", {
      p_verification_id: claim.verificationId,
      p_worker_id: workerId,
      p_lease_token: claim.leaseToken,
      p_outcome: outcome,
      p_failure_reason: failureReason ?? null,
      p_internal_error_code: internalCode ?? null,
      p_internal_error_detail: internalDetail ?? null,
    });
    if (error) {
      // The RPC rejects stale/mismatched/cross-scope claims; treat as a safe stop.
      if (/stale|mismatch|claim/i.test(error.message)) {
        throw new VerificationResultRejected(error.message);
      }
      throw new ContractError(`ownership result failed: ${error.message}`);
    }
  }
}
