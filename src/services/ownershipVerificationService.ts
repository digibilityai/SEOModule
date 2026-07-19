// P1a Step 4 — public data-mode dispatcher for Domain Ownership Verification.
// Read = the standard mock/Supabase adapter (runWithServiceAdapter). Writes =
// a non-masking helper (same rule as Phase 13D/13E/15C/16H writes): a REAL Step
// 2A RPC rejection is surfaced, never masked by a mock success; only pre-RPC
// failures (no session/config) fall back to the mock preview. Mock mode is
// permanent. No direct Supabase access lives outside the Supabase service file.
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { requireSupabaseOrFallback, logDataModeWarning } from "@/services/dataMode";
import { normalizeSupabaseErrorMessage } from "@/services/supabase/supabaseErrors";
import { toAsync } from "@/lib/mockAsync";
import {
  OwnershipVerificationWriteError,
  type OwnershipVerificationView,
} from "@/types/ownershipVerification";
import {
  fetchSupabaseOwnershipVerification,
  initiateSupabaseOwnershipVerification,
  recheckSupabaseOwnershipVerification,
  reverifySupabaseOwnershipVerification,
  revokeSupabaseOwnershipVerification,
} from "@/services/supabase/seoOwnershipVerificationSupabaseService";
import {
  mockFetchOwnershipVerification,
  mockInitiateOwnershipVerification,
  mockRecheckOwnershipVerification,
  mockReverifyOwnershipVerification,
  mockRevokeOwnershipVerification,
} from "@/mocks/ownershipVerificationMockData";

/** Fetch the customer-safe ownership-verification status for a website. */
export async function fetchOwnershipVerification(
  websiteId: string,
): Promise<OwnershipVerificationView> {
  return runWithServiceAdapter({
    label: "ownershipVerificationService.fetch",
    mock: () => toAsync(mockFetchOwnershipVerification(websiteId)),
    supabase: () => fetchSupabaseOwnershipVerification(websiteId),
  });
}

/**
 * Non-masking write: a real OwnershipVerificationWriteError (role denial, no
 * record, illegal lifecycle) is rethrown; only a missing session/config falls
 * back to the mock preview.
 */
async function runOwnershipWrite(
  label: string,
  mock: () => Promise<OwnershipVerificationView>,
  supabaseFn: () => Promise<OwnershipVerificationView>,
): Promise<OwnershipVerificationView> {
  if (!requireSupabaseOrFallback(label)) {
    return mock();
  }
  try {
    return await supabaseFn();
  } catch (error) {
    if (error instanceof OwnershipVerificationWriteError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}

export function initiateOwnershipVerification(websiteId: string) {
  return runOwnershipWrite(
    "ownershipVerificationService.initiate",
    () => toAsync(mockInitiateOwnershipVerification(websiteId)),
    () => initiateSupabaseOwnershipVerification(websiteId),
  );
}

export function recheckOwnershipVerification(websiteId: string) {
  return runOwnershipWrite(
    "ownershipVerificationService.recheck",
    () => toAsync(mockRecheckOwnershipVerification(websiteId)),
    () => recheckSupabaseOwnershipVerification(websiteId),
  );
}

export function reverifyOwnershipVerification(websiteId: string) {
  return runOwnershipWrite(
    "ownershipVerificationService.reverify",
    () => toAsync(mockReverifyOwnershipVerification(websiteId)),
    () => reverifySupabaseOwnershipVerification(websiteId),
  );
}

export function revokeOwnershipVerification(websiteId: string) {
  return runOwnershipWrite(
    "ownershipVerificationService.revoke",
    () => toAsync(mockRevokeOwnershipVerification(websiteId)),
    () => revokeSupabaseOwnershipVerification(websiteId),
  );
}
