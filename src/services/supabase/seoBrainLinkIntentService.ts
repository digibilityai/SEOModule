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
 * Signs the browser in as the account `provisionCaseA` (or, for case D,
 * `continueCaseD`) just resolved, using the single-use magic-link token
 * returned. Same call as the existing Digibility Core bridge
 * (seoBridgeService.establishSeoSession), no new authentication mechanism.
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

const CONTINUE_ERROR_MESSAGES: Record<string, string> = {
  invalid_request: "This connection link is invalid.",
  not_continuable: "This connection link is no longer eligible for sign-in. Please start again from Marketing Brain.",
  continuation_failed: "We could not complete your secure sign-in. Please try again.",
  module_unavailable: "The SEO module is temporarily unavailable.",
};

/**
 * Case D only: POSTs to the `link-intent/continue` Edge Function route with
 * ONLY the launch code, exactly like `provisionCaseA`. Returns the same shape
 * `establishCaseASession` already accepts, so the frontend reuses that
 * mechanism unchanged. Call this ONLY after confirming, via
 * `decideCaseDSessionAction`, that the browser's current session (if any)
 * does not already belong to a different user; this function does not make
 * that check itself.
 */
export async function continueCaseD(launchCode: string): Promise<ProvisionCaseAResult> {
  const base = getSupabaseUrl().replace(/\/+$/, "");
  if (!base) {
    throw new Error("seoBrainLinkIntentService.continueCaseD: Supabase is not configured.");
  }
  const response = await fetch(`${base}/functions/v1/seo-module-api/link-intent/continue`, {
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
    throw new Error(CONTINUE_ERROR_MESSAGES[code] ?? "Your secure sign-in could not be completed. Please try again.");
  }
  if (
    typeof body.intentId !== "string" ||
    typeof body.tokenHash !== "string" ||
    body.otpType !== "magiclink"
  ) {
    throw new Error("seoBrainLinkIntentService.continueCaseD: unrecognized continuation response.");
  }
  return { intentId: body.intentId, tokenHash: body.tokenHash, otpType: "magiclink" };
}

export type CaseDSessionAction = "proceed_with_current_session" | "continue_required" | "session_mismatch";

/**
 * Case D's security boundary (application side): a live session mismatch must
 * refuse safely rather than silently switch identity. `seo_brain_link_intent_
 * redeem` resolves case D unconditionally, ahead of whatever session state the
 * browser happens to be in, so the browser itself must decide, BEFORE ever
 * calling `continueCaseD` (which would sign it in as a different user via
 * verifyOtp), whether its current session is safe to proceed with, needs
 * replacing, or must be refused outright.
 *
 *   - No current session: nothing to conflict with, continuation is required.
 *   - Current session already belongs to the mapped user: it is already the
 *     right session; skip continuation entirely.
 *   - Current session belongs to a DIFFERENT user: refuse. Continuing would
 *     silently sign the browser out of its own session and into another.
 */
export function decideCaseDSessionAction(
  currentUserId: string | null,
  mappedSeoUserId: string,
): CaseDSessionAction {
  if (!currentUserId) return "continue_required";
  return currentUserId === mappedSeoUserId ? "proceed_with_current_session" : "session_mismatch";
}

export type ResolveLinkWebsiteResolution =
  | "resolved"
  | "unauthorized"
  | "invalid_request"
  | "intent_not_redeemed"
  | "identity_mismatch"
  | "intent_expired"
  | "actor_mapping_inactive"
  | "website_ambiguous"
  | "workspace_ambiguous"
  | "conflicting_website";

export interface ResolveLinkWebsiteResult {
  resolution: ResolveLinkWebsiteResolution;
  websiteId?: string;
  verified?: boolean;
}

const RESOLVE_RESOLUTIONS: readonly ResolveLinkWebsiteResolution[] = [
  "resolved",
  "unauthorized",
  "invalid_request",
  "intent_not_redeemed",
  "identity_mismatch",
  "intent_expired",
  "actor_mapping_inactive",
  "website_ambiguous",
  "workspace_ambiguous",
  "conflicting_website",
];

/**
 * Calls `seo_brain_resolve_link_website` directly, the same ordinary
 * authenticated Supabase client every other customer-facing SEO RPC uses.
 * Call this only once a genuine SEO session exists for the redeemed intent's
 * user (case A/B immediately; case D only after `decideCaseDSessionAction`
 * clears it).
 */
export async function resolveLinkWebsite(intentId: string): Promise<ResolveLinkWebsiteResult> {
  const { data, error } = await supabase.rpc(SEO_RPCS.seoBrainResolveLinkWebsite, {
    p_intent_id: intentId,
  });
  if (error) {
    throw new Error(`seoBrainLinkIntentService.resolveLinkWebsite: ${normalizeSupabaseError(error).message}`);
  }
  const body = data as Record<string, unknown> | null;
  const resolution = body?.resolution;
  if (typeof resolution !== "string" || !RESOLVE_RESOLUTIONS.includes(resolution as ResolveLinkWebsiteResolution)) {
    throw new Error("seoBrainLinkIntentService.resolveLinkWebsite: unrecognized resolution.");
  }
  return {
    resolution: resolution as ResolveLinkWebsiteResolution,
    websiteId: typeof body?.websiteId === "string" ? body.websiteId : undefined,
    verified: typeof body?.verified === "boolean" ? body.verified : undefined,
  };
}

export type LinkAuthorizationResolution =
  | "resolved"
  | "already_linked"
  | "unauthorized"
  | "invalid_request"
  | "intent_not_redeemed"
  | "identity_mismatch"
  | "intent_expired"
  | "actor_mapping_inactive"
  | "website_not_found"
  | "website_inactive"
  | "host_mismatch"
  | "ownership_not_verified"
  | "business_host_already_linked"
  | "website_already_linked"
  | "conflicting_link";

export interface LinkAuthorizationResult {
  resolution: LinkAuthorizationResolution;
  linkId?: string;
  websiteId?: string;
}

const LINK_AUTHORIZATION_RESOLUTIONS: readonly LinkAuthorizationResolution[] = [
  "resolved",
  "already_linked",
  "unauthorized",
  "invalid_request",
  "intent_not_redeemed",
  "identity_mismatch",
  "intent_expired",
  "actor_mapping_inactive",
  "website_not_found",
  "website_inactive",
  "host_mismatch",
  "ownership_not_verified",
  "business_host_already_linked",
  "website_already_linked",
  "conflicting_link",
];

/**
 * Calls `seo_brain_link_authorize` directly. `resolution === "resolved"` is a
 * newly-created Brain <-> SEO website link; `"already_linked"` is the same
 * business+host+website relationship already existing and active (an
 * idempotent repeat, e.g. the customer running Connect SEO Intelligence again
 * for a business already genuinely connected). Both are a completed,
 * successful connection. Every other resolution must NOT be presented to the
 * customer as a successful connection.
 */
export async function authorizeLinkedWebsite(
  intentId: string,
  websiteId: string,
): Promise<LinkAuthorizationResult> {
  const { data, error } = await supabase.rpc(SEO_RPCS.seoBrainLinkAuthorize, {
    p_intent_id: intentId,
    p_website_id: websiteId,
  });
  if (error) {
    throw new Error(`seoBrainLinkIntentService.authorizeLinkedWebsite: ${normalizeSupabaseError(error).message}`);
  }
  const body = data as Record<string, unknown> | null;
  const resolution = body?.resolution;
  if (
    typeof resolution !== "string" ||
    !LINK_AUTHORIZATION_RESOLUTIONS.includes(resolution as LinkAuthorizationResolution)
  ) {
    throw new Error("seoBrainLinkIntentService.authorizeLinkedWebsite: unrecognized resolution.");
  }
  return {
    resolution: resolution as LinkAuthorizationResolution,
    linkId: typeof body?.linkId === "string" ? body.linkId : undefined,
    websiteId: typeof body?.websiteId === "string" ? body.websiteId : undefined,
  };
}
