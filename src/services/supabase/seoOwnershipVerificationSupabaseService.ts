// P1a Step 4 — Supabase reads/writes for Domain Ownership Verification.
// Authoritative source is Supabase (RLS + the Step 2A guarded RPCs). This layer:
//   - reads ONLY the customer-safe seo_ownership_verifications table via RLS,
//   - NEVER reads the internal claim/lease ledger or the event audit,
//   - NEVER selects lease tokens / worker ids / internal diagnostics,
//   - NEVER updates the verification tables directly (only the Step 2A RPCs),
//   - NEVER uses a service-role credential (anon client + RLS only),
//   - does NOT fall back to another website/workspace (website-id scoped).
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES, SEO_RPCS } from "@/services/supabase/supabaseTypes";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import {
  requireAuthenticatedUser,
  requireValidUuid,
} from "@/services/supabase/supabaseServiceUtils";
import {
  mapOwnershipRow,
  unverifiedOwnershipView,
} from "@/lib/ownershipVerification";
import {
  OwnershipVerificationWriteError,
  type OwnershipVerificationView,
} from "@/types/ownershipVerification";

// Customer-SAFE columns only (the Step 1 table has no internal columns, but we
// still select explicitly so no future additive column is exposed by accident).
const VERIFICATION_COLUMNS =
  "id, workspace_id, website_id, verification_host, method, ownership_source, status, " +
  "challenge_token, challenge_created_at, challenge_rotated_at, last_checked_at, " +
  "verified_at, failure_reason, created_at, updated_at";

/**
 * Read the single DNS-TXT ownership-verification state for a website. Returns an
 * explicit `unverified` view when no row exists. Requires an authenticated user
 * (defense-in-depth; RLS is authoritative). Website-id scoped — never falls back
 * to another website.
 */
export async function fetchSupabaseOwnershipVerification(
  websiteId: string,
): Promise<OwnershipVerificationView> {
  const label = "seoOwnershipVerificationSupabaseService.fetch";
  await requireAuthenticatedUser(label);
  requireValidUuid(label, websiteId, "websiteId");

  const { data, error } = await supabase
    .from(SEO_TABLES.ownershipVerifications)
    .select(VERIFICATION_COLUMNS)
    .eq("website_id", websiteId)
    .eq("method", "dns_txt")
    .limit(1);
  if (error) throw new Error(`${label}: ${normalizeSupabaseError(error).message}`);

  const row = ((data ?? []) as unknown[])[0] as Record<string, unknown> | undefined;
  return row ? mapOwnershipRow(websiteId, row) : unverifiedOwnershipView(websiteId);
}

// --- writes: Step 2A customer RPCs only (never a direct table update) --------

async function callOwnershipRpc(
  label: string,
  rpcName: string,
  websiteId: string,
): Promise<OwnershipVerificationView> {
  await requireAuthenticatedUser(label);
  requireValidUuid(label, websiteId, "websiteId");
  // Only the website id is sent — workspace / role / host / status / source are
  // resolved server-side by the SECURITY DEFINER RPC and never trusted here.
  const { data, error } = await supabase.rpc(rpcName, { p_website_id: websiteId });
  if (error) {
    // A REAL RPC rejection (role denial, no record, illegal lifecycle) must
    // surface — never masked with a mock success.
    throw new OwnershipVerificationWriteError(normalizeSupabaseError(error).message);
  }
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
  if (!row?.id) {
    throw new OwnershipVerificationWriteError(`${label}: RPC returned no verification row.`);
  }
  return mapOwnershipRow(websiteId, row);
}

export function initiateSupabaseOwnershipVerification(websiteId: string) {
  return callOwnershipRpc(
    "seoOwnershipVerificationSupabaseService.initiate",
    SEO_RPCS.ownershipVerificationInitiate,
    websiteId,
  );
}

export function recheckSupabaseOwnershipVerification(websiteId: string) {
  return callOwnershipRpc(
    "seoOwnershipVerificationSupabaseService.recheck",
    SEO_RPCS.ownershipVerificationRecheck,
    websiteId,
  );
}

export function reverifySupabaseOwnershipVerification(websiteId: string) {
  return callOwnershipRpc(
    "seoOwnershipVerificationSupabaseService.reverify",
    SEO_RPCS.ownershipVerificationReverify,
    websiteId,
  );
}

export function revokeSupabaseOwnershipVerification(websiteId: string) {
  return callOwnershipRpc(
    "seoOwnershipVerificationSupabaseService.revoke",
    SEO_RPCS.ownershipVerificationRevoke,
    websiteId,
  );
}
