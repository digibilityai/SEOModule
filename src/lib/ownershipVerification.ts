// P1a Step 4 — PURE, review-verifiable helpers for ownership verification.
// No Supabase, no React, no side effects — safe to reason about + reuse from the
// Supabase service, the mock adapter, and the hooks (the repo has no frontend
// unit-test framework; keeping this logic pure keeps it review-verifiable).
import type {
  OwnershipSource,
  OwnershipVerificationMethod,
  OwnershipVerificationStatus,
  OwnershipVerificationView,
} from "@/types/ownershipVerification";

/** The DNS TXT record NAME the customer must create for a host. */
export function deriveDnsTxtName(host: string | null | undefined): string | null {
  const h = (host ?? "").trim().toLowerCase();
  return h ? `_digibility-site-verification.${h}` : null;
}

/** The explicit `unverified` state for a website with NO DB row. */
export function unverifiedOwnershipView(websiteId: string): OwnershipVerificationView {
  return {
    verificationId: null,
    workspaceId: null,
    websiteId,
    status: "unverified",
    method: "dns_txt",
    verifiedHost: null,
    dnsTxtName: null,
    dnsTxtValue: null,
    failureReason: null,
    ownershipSource: null,
    requestedAt: null,
    lastCheckedAt: null,
    verifiedAt: null,
    revokedAt: null,
    createdAt: null,
    updatedAt: null,
  };
}

const KNOWN_STATUSES: OwnershipVerificationStatus[] = ["pending", "verified", "failed", "revoked"];

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

/**
 * Map a customer-safe `seo_ownership_verifications` row (snake_case) into the
 * frontend view. Malformed rows are handled safely: a missing/unknown status or
 * a missing id falls back to the `unverified` view for the website (never
 * throws, never surfaces partial internal data). `dnsTxtName` is DERIVED from
 * the authoritative host (same convention the worker/claim RPC uses) — never
 * built from an untrusted client value.
 */
export function mapOwnershipRow(
  websiteId: string,
  row: Record<string, unknown> | null | undefined,
): OwnershipVerificationView {
  if (!row) return unverifiedOwnershipView(websiteId);

  const id = str(row.id);
  const rawStatus = str(row.status);
  const status = (rawStatus && (KNOWN_STATUSES as string[]).includes(rawStatus)
    ? rawStatus
    : null) as OwnershipVerificationStatus | null;
  if (!id || !status) return unverifiedOwnershipView(websiteId);

  const host = str(row.verification_host);
  const method = (str(row.method) ?? "dns_txt") as OwnershipVerificationMethod;
  const updatedAt = str(row.updated_at);

  return {
    verificationId: id,
    workspaceId: str(row.workspace_id),
    websiteId,
    status,
    method,
    verifiedHost: host,
    dnsTxtName: deriveDnsTxtName(host),
    dnsTxtValue: str(row.challenge_token),
    failureReason: str(row.failure_reason),
    ownershipSource: (str(row.ownership_source) as OwnershipSource | null),
    requestedAt: str(row.challenge_created_at),
    lastCheckedAt: str(row.last_checked_at),
    verifiedAt: str(row.verified_at),
    // Step 1 has no dedicated revoked_at column — derive from updated_at while revoked.
    revokedAt: status === "revoked" ? updatedAt : null,
    createdAt: str(row.created_at),
    updatedAt,
  };
}

/** User + website scoped query key (SessionSync clears cache on user change). */
export function ownershipVerificationQueryKey(
  websiteId: string | null | undefined,
  userId: string | null | undefined,
): (string | null)[] {
  return ["seo-ownership-verification", websiteId ?? null, userId ?? null];
}
