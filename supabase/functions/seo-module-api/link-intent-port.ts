/**
 * LinkIntentDataPort and AdminAuthPort backed by the real service-role
 * Supabase client. Mirrors supabase-port.ts: depends on minimal interfaces
 * rather than a concrete client type, so it is testable in Node and carries no
 * Deno dependency.
 */

import type {
  AdminAuthPort,
  CreateIntentDbResult,
  CreateLinkIntentRequest,
  LinkIntentDataPort,
} from "./link-intent.ts";

export interface RpcError {
  message: string;
  code?: string;
}

export interface RpcCaller {
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: RpcError | null }>;
}

/** The minimal slice of supabase-js's GoTrueAdminApi this module actually uses. */
export interface AdminUserApi {
  createUser(attrs: {
    email: string;
    email_confirm: boolean;
  }): Promise<{ data: { user: { id: string } | null } | null; error: { message: string } | null }>;
}

async function callRpc(caller: RpcCaller, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await caller.rpc(fn, args);
  if (response.error) {
    throw new Error(`${fn}: ${response.error.message}`);
  }
  return response.data;
}

function asRecord(value: unknown, fn: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null) {
    throw new Error(`${fn} returned a non-object result`);
  }
  return value as Record<string, unknown>;
}

export function createSupabaseLinkIntentDataPort(caller: RpcCaller): LinkIntentDataPort {
  return {
    async createIntent(request: CreateLinkIntentRequest): Promise<CreateIntentDbResult> {
      const data = asRecord(
        await callRpc(caller, "seo_brain_create_link_intent", {
          p_brain_actor_id: request.brainActorId,
          p_brain_confirmed_email: request.brainConfirmedEmail,
          p_brain_business_id: request.brainBusinessId,
          p_normalized_host: request.normalizedHost,
          p_business_display_name: request.businessDisplayName ?? null,
        }),
        "seo_brain_create_link_intent",
      );
      return {
        resolution: data.resolution as CreateIntentDbResult["resolution"],
        intentId: typeof data.intentId === "string" ? data.intentId : undefined,
        launchCode: typeof data.launchCode === "string" ? data.launchCode : undefined,
        redemptionExpiresAt:
          typeof data.redemptionExpiresAt === "string" ? data.redemptionExpiresAt : undefined,
        detail: typeof data.detail === "string" ? data.detail : undefined,
      };
    },

    async pendingProvisioningEmail(intentId: string): Promise<string | null> {
      const data = await callRpc(caller, "seo_brain_link_intent_pending_email", { p_intent_id: intentId });
      return typeof data === "string" && data.length > 0 ? data : null;
    },

    async finalizeCaseA(intentId: string, seoUserId: string) {
      const data = asRecord(
        await callRpc(caller, "seo_brain_link_intent_finalize_case_a", {
          p_intent_id: intentId,
          p_seo_user_id: seoUserId,
        }),
        "seo_brain_link_intent_finalize_case_a",
      );
      return {
        resolution: String(data.resolution ?? "module_unavailable"),
        intentId: typeof data.intentId === "string" ? data.intentId : undefined,
        seoUserId: typeof data.seoUserId === "string" ? data.seoUserId : undefined,
      };
    },
  };
}

/**
 * Passwordless: no password is ever set. email_confirm is true because Brain
 * already confirmed this address; SEO does not re-run its own confirmation
 * email for an account it originated on the customer's behalf.
 */
export function createSupabaseAdminAuthPort(adminApi: AdminUserApi): AdminAuthPort {
  return {
    async createPasswordlessUser(email: string) {
      const { data, error } = await adminApi.createUser({ email, email_confirm: true });
      if (error || !data?.user?.id) {
        return { error: error?.message ?? "createUser returned no user" };
      }
      return { userId: data.user.id };
    },
  };
}
