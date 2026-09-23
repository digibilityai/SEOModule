// D-026A SEO PR-1 continuation (Stage 2): the SEO-owned browser step that
// redeems a Brain-issued launchCode. Thin adapters only — every case A-D
// decision already lives server-side in `seo_brain_link_intent_redeem` and, for
// case A, in the `link-intent/provision` Edge Function route. This file never
// reinterprets those rules; it just types the exact outcomes they already
// return and calls them, the same way seoAccessService.ts wraps existing RPCs.
//
// Reference: supabase/migrations/20260921120000_seo_brain_link_intents.sql,
// SEO_BRAIN_MODULE_INTERFACE.md section 9.
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS } from "@/services/supabase/supabaseTypes";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import { getSupabaseAnonKey, getSupabaseUrl } from "@/config/runtimeConfig";

/**
 * Every literal `outcome` value `seo_brain_link_intent_redeem` can return
 * (migration lines 294-448). Kept as one exhaustive union so a new backend
 * outcome fails TypeScript compilation here instead of falling through
 * silently in the UI.
 */
export type BrainLinkIntentOutcome =
  | "invalid_or_expired_code"
  | "case_d_resolved"
  | "anonymous_session_not_eligible"
  | "seo_access_required"
  | "confirmation_required"
  | "case_b_confirmed"
  | "case_b_conflict"
  | "existing_account_verification_required"
  | "case_a_provisioning_required";

export interface BrainLinkIntentRedemption {
  outcome: BrainLinkIntentOutcome;
  intentId?: string;
  seoUserId?: string;
  brainConfirmedEmail?: string;
  businessDisplayName?: string | null;
  normalizedHost?: string;
}

function isKnownOutcome(value: unknown): value is BrainLinkIntentOutcome {
  return (
    typeof value === "string" &&
    (
      [
        "invalid_or_expired_code",
        "case_d_resolved",
        "anonymous_session_not_eligible",
        "seo_access_required",
        "confirmation_required",
        "case_b_confirmed",
        "case_b_conflict",
        "existing_account_verification_required",
        "case_a_provisioning_required",
      ] as const
    ).includes(value as BrainLinkIntentOutcome)
  );
}

/**
 * Calls `seo_brain_link_intent_redeem` directly, exactly as the customer's own
 * browser is documented to: no machine secret, no Edge Function. Pass
 * `confirm: true` only after the customer has explicitly confirmed the case B
 * connection shown on screen.
 */
export async function redeemBrainLinkIntent(
  launchCode: string,
  confirm: boolean,
): Promise<BrainLinkIntentRedemption> {
  const { data, error } = await supabase.rpc(SEO_RPCS.seoBrainLinkIntentRedeem, {
    p_launch_code: launchCode,
    p_confirm: confirm,
  });
  if (error) {
    throw new Error(`seoBrainLinkIntentService.redeemBrainLinkIntent: ${normalizeSupabaseError(error).message}`);
  }
  const body = data as Record<string, unknown> | null;
  if (!body || !isKnownOutcome(body.outcome)) {
    throw new Error("seoBrainLinkIntentService.redeemBrainLinkIntent: unrecognized redemption outcome.");
  }
  return {
    outcome: body.outcome,
    intentId: typeof body.intentId === "string" ? body.intentId : undefined,
    seoUserId: typeof body.seoUserId === "string" ? body.seoUserId : undefined,
    brainConfirmedEmail: typeof body.brainConfirmedEmail === "string" ? body.brainConfirmedEmail : undefined,
    businessDisplayName:
      typeof body.businessDisplayName === "string" || body.businessDisplayName === null
        ? (body.businessDisplayName as string | null)
        : undefined,
    normalizedHost: typeof body.normalizedHost === "string" ? body.normalizedHost : undefined,
  };
}

export interface ProvisionCaseAResult {
  intentId: string;
  tokenHash: string;
  otpType: "magiclink";
}

const PROVISION_ERROR_MESSAGES: Record<string, string> = {
  invalid_request: "This connection link is invalid.",
  not_pending: "This connection link has already been used or is no longer waiting for setup.",
  existing_account: "An SEO account already exists for this email. Sign in to it and confirm the connection.",
  provisioning_failed: "We could not create your SEO account. Please try again.",
  finalize_failed: "We could not finish setting up your SEO account. Please try again.",
  module_unavailable: "The SEO module is temporarily unavailable.",
};

/**
 * Case A only: POSTs to the `link-intent/provision` Edge Function route with
 * ONLY the launch code. Not machine-secret gated (a browser cannot hold that
 * secret); its safety is the code's own pending_provisioning server state.
 * Never sends brainActorId, brainBusinessId, normalizedHost, or the module
 * secret.
 */
export async function provisionCaseA(launchCode: string): Promise<ProvisionCaseAResult> {
  const base = getSupabaseUrl().replace(/\/+$/, "");
  if (!base) {
    throw new Error("seoBrainLinkIntentService.provisionCaseA: Supabase is not configured.");
  }
  const response = await fetch(`${base}/functions/v1/seo-module-api/link-intent/provision`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: getSupabaseAnonKey(),
    },
    body: JSON.stringify({ launchCode }),
  });
  const body = (await response.json().catch(() => ({}))) as {
    intentId?: unknown;
    tokenHash?: unknown;
    otpType?: unknown;
    error?: { code?: unknown };
  };
  if (!response.ok) {
    const code = typeof body.error?.code === "string" ? body.error.code : "";
    throw new Error(PROVISION_ERROR_MESSAGES[code] ?? "Your SEO account could not be set up. Please try again.");
  }
  if (
    typeof body.intentId !== "string" ||
    typeof body.tokenHash !== "string" ||
    body.otpType !== "magiclink"
  ) {
    throw new Error("seoBrainLinkIntentService.provisionCaseA: unrecognized provisioning response.");
  }
  return { intentId: body.intentId, tokenHash: body.tokenHash, otpType: "magiclink" };
}

/**
 * Signs the browser in as the account `provisionCaseA` just created, using the
 * single-use magic-link token it returned. Same call as the existing
 * Digibility Core bridge (seoBridgeService.establishSeoSession) — no new
 * authentication mechanism.
 */
export async function establishCaseASession(result: ProvisionCaseAResult): Promise<void> {
  const { error } = await supabase.auth.verifyOtp({
    token_hash: result.tokenHash,
    type: result.otpType,
  });
  if (error) {
    throw new Error("seoBrainLinkIntentService.establishCaseASession: SEO session creation failed.");
  }
}
