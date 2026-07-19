// P1a Step 4 — deterministic mock adapter for Domain Ownership Verification.
// Clearly a PREVIEW: no Supabase call, no timers, no DNS network activity. State
// is held in-memory, isolated by website id, and moves through the Step 2A
// lifecycle deterministically. Does not touch any other mock/service.
import { deriveDnsTxtName, unverifiedOwnershipView } from "@/lib/ownershipVerification";
import type { OwnershipVerificationView } from "@/types/ownershipVerification";

// Per-website mock state (isolated by website id). Absent → unverified.
const store = new Map<string, OwnershipVerificationView>();

const MOCK_HOST = "preview-site.example";
const MOCK_DNS_NAME = deriveDnsTxtName(MOCK_HOST);
let tokenSeq = 0;

function mockToken(): string {
  tokenSeq += 1;
  return `digibility-site-verification=PREVIEWMOCKTOKEN${String(tokenSeq).padStart(6, "0")}`;
}

function nowIso(): string {
  // Deterministic-enough for a preview; no timers/scheduling depend on it.
  return new Date().toISOString();
}

function pendingView(websiteId: string, token: string): OwnershipVerificationView {
  return {
    ...unverifiedOwnershipView(websiteId),
    verificationId: `mock_ownverify_${websiteId}`,
    workspaceId: "mock_workspace",
    status: "pending",
    verifiedHost: MOCK_HOST,
    dnsTxtName: MOCK_DNS_NAME,
    dnsTxtValue: token,
    ownershipSource: "standalone_dns",
    requestedAt: nowIso(),
    createdAt: nowIso(),
    updatedAt: nowIso(),
  };
}

/** Read the mock state for a website (unverified when none). */
export function mockFetchOwnershipVerification(websiteId: string): OwnershipVerificationView {
  return store.get(websiteId) ?? unverifiedOwnershipView(websiteId);
}

/** initiate: create/restart a pending challenge; idempotent for pending/verified. */
export function mockInitiateOwnershipVerification(websiteId: string): OwnershipVerificationView {
  const cur = store.get(websiteId);
  if (cur && (cur.status === "pending" || cur.status === "verified")) {
    return cur; // idempotent: keep the existing challenge / verified state
  }
  const v = pendingView(websiteId, mockToken()); // none | failed | revoked → fresh pending
  store.set(websiteId, v);
  return v;
}

/** recheck: reuse the current challenge; stays pending (from pending/failed). */
export function mockRecheckOwnershipVerification(websiteId: string): OwnershipVerificationView {
  const cur = store.get(websiteId);
  if (!cur || (cur.status !== "pending" && cur.status !== "failed")) {
    // Mirror the RPC: recheck applies only to pending/failed. Preview: no-op read.
    return cur ?? unverifiedOwnershipView(websiteId);
  }
  const v: OwnershipVerificationView = {
    ...cur,
    status: "pending",
    failureReason: null,
    lastCheckedAt: nowIso(),
    updatedAt: nowIso(),
  }; // challenge token intentionally reused
  store.set(websiteId, v);
  return v;
}

/** reverify: rotate the challenge and set pending. */
export function mockReverifyOwnershipVerification(websiteId: string): OwnershipVerificationView {
  const cur = store.get(websiteId) ?? pendingView(websiteId, mockToken());
  const v: OwnershipVerificationView = {
    ...cur,
    status: "pending",
    dnsTxtValue: mockToken(), // rotated
    verifiedAt: null,
    failureReason: null,
    updatedAt: nowIso(),
  };
  store.set(websiteId, v);
  return v;
}

/** revoke: set revoked; idempotent. */
export function mockRevokeOwnershipVerification(websiteId: string): OwnershipVerificationView {
  const cur = store.get(websiteId);
  if (!cur) {
    // Nothing to revoke in preview — surface a clearly-revoked view deterministically.
    const v: OwnershipVerificationView = {
      ...unverifiedOwnershipView(websiteId),
      verificationId: `mock_ownverify_${websiteId}`,
      workspaceId: "mock_workspace",
      status: "revoked",
      verifiedHost: MOCK_HOST,
      ownershipSource: "standalone_dns",
      updatedAt: nowIso(),
      revokedAt: nowIso(),
    };
    store.set(websiteId, v);
    return v;
  }
  if (cur.status === "revoked") return cur; // idempotent
  const v: OwnershipVerificationView = {
    ...cur,
    status: "revoked",
    verifiedAt: null,
    updatedAt: nowIso(),
    revokedAt: nowIso(),
  };
  store.set(websiteId, v);
  return v;
}

/** TEST/preview helper: reset the in-memory mock store (no effect on Supabase). */
export function __resetOwnershipVerificationMock(): void {
  store.clear();
  tokenSeq = 0;
}
