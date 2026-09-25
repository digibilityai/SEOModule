/**
 * D-026A SEO PR-1: the cross-repo linking foundation.
 *
 * This is deliberately NOT part of Digi Brain Module Contract v1. It shares
 * this Edge Function's deployment and its machine secret for create_intent,
 * because that is the existing Brain-server-to-SEO trust boundary and no new
 * secret is needed, but it has its own request/response shapes and is dispatched
 * on its own path (link-intent/*, not analyse/execute/status), so it can never
 * be confused with a capability exchange and never needs a capability key.
 *
 * Pure with respect to I/O, exactly like handler.ts: every database and Admin
 * API touch goes through the injected LinkIntentDeps, so this file has no Deno
 * dependency and is exercisable by vitest.
 *
 * Redemption itself (seo_brain_link_intent_redeem), website resolution
 * (seo_brain_resolve_link_website) and authorization (seo_brain_link_authorize)
 * are plain Postgres RPCs the customer's own browser calls directly over the
 * ordinary anon/authenticated Supabase client, the same way every other
 * customer-facing SEO RPC already works. They do not go through this Edge
 * Function at all, and are not implemented here.
 *
 *   create: Brain server -> SEO. Authenticated by the caller of this module
 *     (serveModuleRequest's authorizeCaller, the same SEO_MODULE_API_SECRET
 *     used by every Contract v1 exchange) before this file is ever reached.
 *   provision: browser -> SEO, for the one case A step no SQL function can
 *     safely perform: creating a passwordless auth user and handing the browser
 *     the material to sign in as it. Not machine-secret gated, because a
 *     browser cannot hold that secret. The browser presents the ORIGINAL
 *     LAUNCH CODE (never an intent id). Its safety comes from that code
 *     resolving, via seo_brain_link_intent_pending_by_code, to a real,
 *     unexpired, pending_provisioning intent, and from never trusting a
 *     caller-supplied email. Only a single-use magic-link token hash for the
 *     browser's supabase.auth.verifyOtp leaves this function; no service-role
 *     credential ever does.
 *   continue: browser -> SEO, for the analogous case D step: minting a
 *     magic-link sign-in for a user who is already durably mapped, but whose
 *     browser currently has no live session for them. Not machine-secret
 *     gated either. Its safety comes from the launch code resolving, via
 *     seo_brain_link_intent_continue_by_code, to a real, still-consented case D
 *     redemption backed by an active, consent-provenanced actor mapping. It
 *     creates nothing: no new user, no new module access, no new mapping.
 */

export class LinkIntentError extends Error {
  readonly code:
    | "invalid_request"
    | "not_pending"
    | "existing_account"
    | "provisioning_failed"
    | "finalize_failed"
    | "not_continuable"
    | "continuation_failed"
    | "module_unavailable";
  readonly internalReason?: string;

  constructor(code: LinkIntentError["code"], message: string, internalReason?: string) {
    super(message);
    this.name = "LinkIntentError";
    this.code = code;
    this.internalReason = internalReason;
  }
}

export const LINK_INTENT_ERROR_HTTP_STATUS: Record<LinkIntentError["code"], number> = {
  invalid_request: 400,
  not_pending: 409,
  existing_account: 409,
  provisioning_failed: 502,
  finalize_failed: 500,
  not_continuable: 409,
  continuation_failed: 502,
  module_unavailable: 503,
};

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

// ---------------------------------------------------------------------------
// create_intent
// ---------------------------------------------------------------------------

export interface CreateLinkIntentRequest {
  brainActorId: string;
  brainConfirmedEmail: string;
  brainBusinessId: string;
  normalizedHost: string;
  businessDisplayName?: string;
}

export interface CreateLinkIntentResult {
  intentId: string;
  launchCode: string;
  redemptionExpiresAt: string;
}

export interface CreateIntentDbResult {
  resolution: "created" | "invalid_request";
  intentId?: string;
  launchCode?: string;
  redemptionExpiresAt?: string;
  detail?: string;
}

export interface LinkIntentDataPort {
  createIntent(request: CreateLinkIntentRequest): Promise<CreateIntentDbResult>;
  /**
   * The one authoritative source for the intent and confirmed email behind a
   * pending_provisioning launch code. Null unless genuinely pending.
   */
  pendingProvisioning(launchCode: string): Promise<{ intentId: string; email: string } | null>;
  finalizeCaseA(
    intentId: string,
    seoUserId: string,
  ): Promise<{ resolution: string; intentId?: string; seoUserId?: string }>;
  /**
   * The one authoritative source for a case D continuation: the intent id, the
   * already-mapped SEO user id, and that user's own auth.users email, behind a
   * launch code that is genuinely `redeemed` via `case_d_existing_mapping`,
   * within its consent window, and backed by an active mapping with a
   * non-NULL link_method. Null for anything else.
   */
  continuationByCode(
    launchCode: string,
  ): Promise<{ intentId: string; seoUserId: string; email: string } | null>;
}

export interface AdminAuthPort {
  /**
   * supabase.auth.admin.createUser({ email, email_confirm: true }), no password
   * set. `duplicate: true` marks the email-already-registered race, which must
   * never lead to touching the pre-existing user.
   */
  createPasswordlessUser(
    email: string,
  ): Promise<{ userId: string } | { error: string; duplicate?: boolean }>;
  /** supabase.auth.admin.generateLink({ type: 'magiclink', email }). Sends no email. */
  generateMagicLinkToken(email: string): Promise<{ tokenHash: string } | { error: string }>;
  /** Cleanup for an account THIS request just created. Never called for a pre-existing user. */
  deleteUser(userId: string): Promise<{ ok: true } | { error: string }>;
}

export interface LinkIntentDeps {
  db: LinkIntentDataPort;
  admin: AdminAuthPort;
  log?: (event: Record<string, unknown>) => void;
}

export function validateCreateLinkIntentRequest(rawBody: unknown): CreateLinkIntentRequest {
  if (typeof rawBody !== "object" || rawBody === null || Array.isArray(rawBody)) {
    throw new LinkIntentError("invalid_request", "Request body must be a JSON object.");
  }
  const body = rawBody as Record<string, unknown>;

  if (!isNonEmptyString(body.brainActorId)) {
    throw new LinkIntentError("invalid_request", "brainActorId is required.");
  }
  if (!isNonEmptyString(body.brainConfirmedEmail)) {
    throw new LinkIntentError("invalid_request", "brainConfirmedEmail is required.");
  }
  if (!isNonEmptyString(body.brainBusinessId)) {
    throw new LinkIntentError("invalid_request", "brainBusinessId is required.");
  }
  if (!isNonEmptyString(body.normalizedHost)) {
    throw new LinkIntentError("invalid_request", "normalizedHost is required.");
  }
  if (body.businessDisplayName !== undefined && typeof body.businessDisplayName !== "string") {
    throw new LinkIntentError("invalid_request", "businessDisplayName, when present, must be a string.");
  }

  return {
    brainActorId: body.brainActorId.trim(),
    brainConfirmedEmail: body.brainConfirmedEmail.trim(),
    brainBusinessId: body.brainBusinessId.trim(),
    normalizedHost: body.normalizedHost.trim(),
    ...(isNonEmptyString(body.businessDisplayName)
      ? { businessDisplayName: (body.businessDisplayName as string).trim() }
      : {}),
  };
}

/**
 * SQL independently re-validates every one of these (canonical host, email
 * shape, id lengths) and is the actual authority; this is a fast, honest
 * rejection at the edge for the common malformed case, not a substitute.
 */
export async function handleCreateLinkIntent(
  rawBody: unknown,
  deps: LinkIntentDeps,
): Promise<CreateLinkIntentResult> {
  const request = validateCreateLinkIntentRequest(rawBody);
  const result = await deps.db.createIntent(request);

  if (result.resolution === "invalid_request") {
    throw new LinkIntentError("invalid_request", "The SEO module refused this intent.", result.detail);
  }
  if (
    result.resolution !== "created" ||
    !isNonEmptyString(result.intentId) ||
    !isNonEmptyString(result.launchCode) ||
    !isNonEmptyString(result.redemptionExpiresAt)
  ) {
    throw new LinkIntentError(
      "module_unavailable",
      "The SEO module returned an unrecognized create_intent result.",
    );
  }

  return {
    intentId: result.intentId,
    launchCode: result.launchCode,
    redemptionExpiresAt: result.redemptionExpiresAt,
  };
}

// ---------------------------------------------------------------------------
// provision (case A only)
// ---------------------------------------------------------------------------

export interface ProvisionCaseARequest {
  launchCode: string;
}

/** Exactly what the browser needs for supabase.auth.verifyOtp({ token_hash, type }). */
export interface ProvisionCaseAResult {
  intentId: string;
  tokenHash: string;
  otpType: "magiclink";
}

export function validateProvisionRequest(rawBody: unknown): ProvisionCaseARequest {
  if (typeof rawBody !== "object" || rawBody === null || Array.isArray(rawBody)) {
    throw new LinkIntentError("invalid_request", "Request body must be a JSON object.");
  }
  const body = rawBody as Record<string, unknown>;
  if (!isNonEmptyString(body.launchCode)) {
    throw new LinkIntentError("invalid_request", "launchCode is required.");
  }
  return { launchCode: body.launchCode.trim() };
}

/**
 * Order matters, and every failure after account creation removes the account
 * this request just created, so a failed attempt never leaves a permanent
 * orphan and never leaves a usable session material behind:
 *   1. resolve the launch code to the pending intent and its trusted email;
 *   2. create the passwordless user (a duplicate email is a race with an
 *      existing account: refuse, and touch nothing, since that user is not ours);
 *   3. generate the magic-link token (before finalize, so a failure here is
 *      cleaned up together with everything else);
 *   4. finalize (module access, actor mapping, intent redeemed);
 *   5. only now return the token hash.
 * The intent stays pending_provisioning after a cleaned-up failure, so the same
 * launch code can be retried until its own short window closes.
 */
export async function handleProvisionCaseA(
  rawBody: unknown,
  deps: LinkIntentDeps,
): Promise<ProvisionCaseAResult> {
  const { launchCode } = validateProvisionRequest(rawBody);

  const pending = await deps.db.pendingProvisioning(launchCode);
  if (!pending || !isNonEmptyString(pending.email) || !isNonEmptyString(pending.intentId)) {
    throw new LinkIntentError(
      "not_pending",
      "This launch code is not currently awaiting provisioning.",
      "pendingProvisioning returned nothing",
    );
  }
  const { intentId, email } = pending;

  const created = await deps.admin.createPasswordlessUser(email);
  if ("error" in created) {
    if (created.duplicate) {
      deps.log?.({ event: "seo_link_intent_provision_duplicate_email", intentId });
      throw new LinkIntentError(
        "existing_account",
        "An SEO account already exists for this email. Sign in to it and confirm the link.",
        created.error,
      );
    }
    deps.log?.({ event: "seo_link_intent_provision_failed", intentId, detail: created.error });
    throw new LinkIntentError("provisioning_failed", "Could not create the SEO account.", created.error);
  }

  const userId = created.userId;
  const cleanup = async (reason: string) => {
    const removed = await deps.admin.deleteUser(userId);
    deps.log?.({
      event: "seo_link_intent_provision_cleanup",
      intentId,
      reason,
      removed: !("error" in removed),
      ...("error" in removed ? { detail: removed.error } : {}),
    });
  };

  try {
    const token = await deps.admin.generateMagicLinkToken(email);
    if ("error" in token) {
      await cleanup("generate_link_failed");
      throw new LinkIntentError("provisioning_failed", "Could not prepare the sign-in for the SEO account.", token.error);
    }

    const finalized = await deps.db.finalizeCaseA(intentId, userId);
    if (finalized.resolution !== "resolved" || !isNonEmptyString(finalized.seoUserId)) {
      deps.log?.({ event: "seo_link_intent_finalize_failed", intentId, resolution: finalized.resolution });
      await cleanup("finalize_failed");
      throw new LinkIntentError(
        "finalize_failed",
        "The SEO account could not be finalized.",
        finalized.resolution,
      );
    }

    return { intentId, tokenHash: token.tokenHash, otpType: "magiclink" };
  } catch (error) {
    if (error instanceof LinkIntentError) throw error;
    // An unexpected throw (network, RPC transport) between creation and
    // completion: the same rule applies, the account we created must not linger.
    await cleanup("unexpected_error");
    throw error;
  }
}

// ---------------------------------------------------------------------------
// continue (case D only)
// ---------------------------------------------------------------------------

export interface ContinueCaseDRequest {
  launchCode: string;
}

/** Same shape as ProvisionCaseAResult: the browser calls the same verifyOtp. */
export interface ContinueCaseDResult {
  intentId: string;
  tokenHash: string;
  otpType: "magiclink";
}

/**
 * Case D only: the intent already redeemed server-side to an existing,
 * durably-mapped SEO user (seo_brain_link_intent_redeem's case_d_resolved),
 * but the calling browser may have no live session for that user at all. This
 * mints a magic-link sign-in for the SAME already-mapped user; it creates no
 * account, no module access grant and no actor mapping, all three of which
 * already exist. deps.db.continuationByCode fails closed (returns null) for
 * anything not currently eligible, including a mapping whose link_method is
 * NULL, so this function has exactly one place to refuse.
 */
export async function handleContinueCaseD(
  rawBody: unknown,
  deps: LinkIntentDeps,
): Promise<ContinueCaseDResult> {
  const { launchCode } = validateProvisionRequest(rawBody);

  const eligible = await deps.db.continuationByCode(launchCode);
  if (!eligible || !isNonEmptyString(eligible.intentId) || !isNonEmptyString(eligible.email)) {
    throw new LinkIntentError(
      "not_continuable",
      "This connection link is not currently eligible for continuation.",
      "continuationByCode returned nothing",
    );
  }
  const { intentId, email } = eligible;

  const token = await deps.admin.generateMagicLinkToken(email);
  if ("error" in token) {
    deps.log?.({ event: "seo_link_intent_continue_failed", intentId, detail: token.error });
    throw new LinkIntentError("continuation_failed", "Could not prepare the sign-in for your SEO account.", token.error);
  }

  return { intentId, tokenHash: token.tokenHash, otpType: "magiclink" };
}
