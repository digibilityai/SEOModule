/**
 * Transport shell for the two link-intent HTTP paths. Deliberately separate
 * from http.ts: this is NOT a Contract v1 exchange (no capability key, no
 * contractVersion envelope), so it is never dispatched through
 * handleModuleRequest and can never be mistaken for one of the six declared
 * capabilities.
 *
 * link-intent/create reuses authorizeCaller from http.ts, the SAME
 * SEO_MODULE_API_SECRET check every Contract v1 exchange already uses: this is
 * still Brain server to SEO, over the existing machine trust boundary.
 *
 * link-intent/provision is NOT secret-gated. A browser cannot hold that
 * secret. Its safety is entirely in handleProvisionCaseA: it only ever acts on
 * a launch code that genuinely, currently resolves to a pending_provisioning
 * intent, and it never trusts a caller-supplied email.
 *
 * CORS exists ONLY for link-intent/provision, because the SEO browser calls it
 * directly. It uses an explicit, configured allow-list of SEO origins: never
 * "*", never a reflected arbitrary Origin, and no CORS headers at all on
 * link-intent/create, which is a server-to-server path a browser never needs.
 */

import { authorizeCaller, type TransportConfig } from "./http.ts";

export interface LinkIntentTransportConfig extends TransportConfig {
  /** Exact SEO frontend origins (scheme + host + port) that may call provision from a browser. */
  allowedOrigins: readonly string[];
}

/** Parses SEO_LINK_INTENT_ALLOWED_ORIGINS: comma separated exact origins. "*" is discarded. */
export function parseAllowedOrigins(raw: string | undefined | null): string[] {
  return (raw ?? "")
    .split(",")
    .map((origin) => origin.trim().replace(/\/+$/, ""))
    .filter((origin) => origin.length > 0 && origin !== "*");
}

function originAllowed(request: Request, config: LinkIntentTransportConfig): string | null {
  const origin = request.headers.get("origin");
  return origin !== null && config.allowedOrigins.includes(origin) ? origin : null;
}

function corsHeaders(origin: string): Record<string, string> {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
    "access-control-max-age": "600",
    vary: "Origin",
  };
}
import { LinkIntentError, LINK_INTENT_ERROR_HTTP_STATUS, type LinkIntentDeps } from "./link-intent.ts";
import { handleCreateLinkIntent, handleProvisionCaseA } from "./link-intent.ts";

export type LinkIntentPath = "create" | "provision";

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

/**
 * Takes the last two non-empty path segments, so this works whether the
 * function is mounted at /functions/v1/seo-module-api/link-intent/create or a
 * rewritten /api/seo/link-intent/create.
 */
export function linkIntentPathFromUrl(url: string): LinkIntentPath | null {
  let pathname: string;
  try {
    pathname = new URL(url).pathname;
  } catch {
    return null;
  }
  const segments = pathname.split("/").filter((segment) => segment.length > 0);
  const last = segments[segments.length - 1] ?? "";
  const secondLast = segments[segments.length - 2] ?? "";
  if (secondLast !== "link-intent") return null;
  return last === "create" || last === "provision" ? (last as LinkIntentPath) : null;
}

function errorBody(code: string, message: string): string {
  return JSON.stringify({ error: { code, message } });
}

function toErrorResponse(error: LinkIntentError, extra: Record<string, string> = {}): Response {
  return new Response(errorBody(error.code, error.message), {
    status: LINK_INTENT_ERROR_HTTP_STATUS[error.code],
    headers: { ...JSON_HEADERS, ...extra },
  });
}

export async function serveLinkIntentRequest(
  request: Request,
  path: LinkIntentPath,
  config: LinkIntentTransportConfig,
  deps: LinkIntentDeps,
): Promise<Response> {
  // Only provision ever answers a browser. A preflight or a request from an
  // origin outside the allow-list is refused outright, with no CORS headers.
  let cors: Record<string, string> = {};
  if (path === "provision") {
    const requestOrigin = request.headers.get("origin");
    const allowed = originAllowed(request, config);
    if (requestOrigin !== null && allowed === null) {
      deps.log?.({ event: "seo_link_intent_origin_refused", path });
      return new Response(errorBody("origin_not_allowed", "This origin is not allowed."), {
        status: 403,
        headers: JSON_HEADERS,
      });
    }
    if (allowed !== null) cors = corsHeaders(allowed);
    if (request.method === "OPTIONS" && allowed !== null) {
      return new Response(null, { status: 204, headers: cors });
    }
  }

  try {
    if (request.method !== "POST") {
      throw new LinkIntentError("invalid_request", "Only POST is supported.");
    }

    if (path === "create") {
      // Same machine secret, same failure mode, as every Contract v1 exchange.
      authorizeCaller(request.headers, config);
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      throw new LinkIntentError("invalid_request", "Request body must be valid JSON.");
    }

    const result =
      path === "create" ? await handleCreateLinkIntent(body, deps) : await handleProvisionCaseA(body, deps);

    return new Response(JSON.stringify(result), { status: 200, headers: { ...JSON_HEADERS, ...cors } });
  } catch (error) {
    if (error instanceof LinkIntentError) {
      deps.log?.({ event: "seo_link_intent_error", path, code: error.code, internalReason: error.internalReason ?? null });
      return toErrorResponse(error, cors);
    }
    // authorizeCaller throws SeoModuleContractError, not LinkIntentError, on a
    // bad or missing secret. Its shape is close enough (code + message) that
    // rethrowing its own Response is simpler than translating the type here.
    if (error && typeof error === "object" && "code" in error && "message" in error) {
      const contractError = error as { code: string; message: string };
      deps.log?.({ event: "seo_link_intent_unauthorized", path, code: contractError.code });
      return new Response(errorBody(contractError.code, contractError.message), {
        status: contractError.code === "unauthorized" ? 403 : 503,
        headers: { ...JSON_HEADERS, ...cors },
      });
    }
    deps.log?.({
      event: "seo_link_intent_unhandled_error",
      path,
      detail: error instanceof Error ? error.message : String(error),
    });
    return toErrorResponse(
      new LinkIntentError("module_unavailable", "The SEO module could not complete this request."),
      cors,
    );
  }
}
