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
 * Two paths only. Redemption itself (seo_brain_link_intent_redeem) and
 * authorization (seo_brain_link_authorize) are plain Postgres RPCs the
 * customer's own browser calls directly over the ordinary anon/authenticated
 * Supabase client, the same way every other customer-facing SEO RPC already
 * works. They do not go through this Edge Function at all, and are not
 * implemented here.
 *
 *   create: Brain server -> SEO. Authenticated by the caller of this module
 *     (serveModuleRequest's authorizeCaller, the same SEO_MODULE_API_SECRET
 *     used by every Contract v1 exchange) before this file is ever reached.
 *   provision: browser -> SEO, for the one case A step no SQL function can
 *     safely perform: creating a passwordless auth user. Not machine-secret
 *     gated, because a browser cannot hold that secret. Its safety comes from
 *     requiring a genuinely pending_provisioning intentId, which
 *     seo_brain_link_intent_pending_email only ever returns for a real,
 *     unexpired, still-pending intent, and from never trusting a
 *     caller-supplied email for account creation.
 */

export class LinkIntentError extends Error {
  readonly code:
    | "invalid_request"
    | "not_pending"
    | "provisioning_failed"
    | "finalize_failed"
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
  provisioning_failed: 502,
  finalize_failed: 500,
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
  /** The one authoritative source for the confirmed email behind a pending_provisioning intent. */
  pendingProvisioningEmail(intentId: string): Promise<string | null>;
  finalizeCaseA(
    intentId: string,
    seoUserId: string,
  ): Promise<{ resolution: string; intentId?: string; seoUserId?: string }>;
}

export interface AdminAuthPort {
  /** supabase.auth.admin.createUser({ email, email_confirm: true }), no password set. */
  createPasswordlessUser(email: string): Promise<{ userId: string } | { error: string }>;
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
  intentId: string;
}

export interface ProvisionCaseAResult {
  intentId: string;
  seoUserId: string;
}

export function validateProvisionRequest(rawBody: unknown): ProvisionCaseARequest {
  if (typeof rawBody !== "object" || rawBody === null || Array.isArray(rawBody)) {
    throw new LinkIntentError("invalid_request", "Request body must be a JSON object.");
  }
  const body = rawBody as Record<string, unknown>;
  if (!isNonEmptyString(body.intentId)) {
    throw new LinkIntentError("invalid_request", "intentId is required.");
  }
  return { intentId: body.intentId.trim() };
}

/**
 * The email used for account creation is ALWAYS the one SEO already has on
 * file for this intent, read fresh from seo_brain_link_intent_pending_email,
 * never anything the caller supplies. A caller who has learned a real
 * intentId (a random uuid) still cannot bind an email of their own choosing
 * to it.
 */
export async function handleProvisionCaseA(
  rawBody: unknown,
  deps: LinkIntentDeps,
): Promise<ProvisionCaseAResult> {
  const { intentId } = validateProvisionRequest(rawBody);

  const email = await deps.db.pendingProvisioningEmail(intentId);
  if (!isNonEmptyString(email)) {
    throw new LinkIntentError(
      "not_pending",
      "This intent is not currently awaiting provisioning.",
      "pendingProvisioningEmail returned nothing",
    );
  }

  const created = await deps.admin.createPasswordlessUser(email);
  if ("error" in created) {
    deps.log?.({ event: "seo_link_intent_provision_failed", intentId, detail: created.error });
    throw new LinkIntentError("provisioning_failed", "Could not create the SEO account.", created.error);
  }

  const finalized = await deps.db.finalizeCaseA(intentId, created.userId);
  if (finalized.resolution !== "resolved" || !isNonEmptyString(finalized.seoUserId)) {
    deps.log?.({
      event: "seo_link_intent_finalize_failed",
      intentId,
      resolution: finalized.resolution,
    });
    throw new LinkIntentError(
      "finalize_failed",
      "The SEO account was created but the intent could not be finalized.",
      finalized.resolution,
    );
  }

  return { intentId, seoUserId: finalized.seoUserId };
}
