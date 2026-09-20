/**
 * Transport shell for the SEO machine boundary: authenticate the caller,
 * parse one JSON envelope, hand it to the handler, and normalize every outcome
 * into a Contract v1 shaped body.
 *
 * Written against the standard Request/Response types, which exist in both Deno
 * and Node 18+, so the whole file is exercisable by vitest without a Deno
 * runtime.
 *
 * Server to server only. There is no CORS allowance and no browser entry point:
 * a browser cannot usefully call this, and the service-role credential it
 * fronts is never exposed to one.
 */

import {
  ERROR_HTTP_STATUS,
  SeoModuleContractError,
  type ModuleErrorCode,
} from "./contract.ts";
import { SEO_MODULE_DECLARATION } from "./capabilities.ts";
import { handleModuleRequest, type HandlerDeps } from "./handler.ts";

/** Header carrying the shared machine credential. */
export const MODULE_SECRET_HEADER = "x-digibility-module-secret";

export interface TransportConfig {
  /** Shared secret held only by Digi Brain's server and this function. */
  moduleApiSecret: string;
}

/**
 * Length-checked, constant-time string comparison. Avoids leaking how much of a
 * presented secret was correct through response timing. Implemented inline
 * rather than with Node's timingSafeEqual so the same code runs under Deno.
 */
export function secretsMatch(presented: string, expected: string): boolean {
  if (presented.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= presented.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0;
}

export interface HeaderLike {
  get(name: string): string | null;
}

/**
 * Fails closed in both directions: a missing or wrong caller secret is
 * `unauthorized`, and a server that was deployed without its own secret
 * configured is `module_unavailable` rather than open. Neither case ever
 * reaches the handler or the database.
 */
export function authorizeCaller(headers: HeaderLike, config: TransportConfig): void {
  if (!config.moduleApiSecret || config.moduleApiSecret.trim().length < 32) {
    throw new SeoModuleContractError(
      "module_unavailable",
      "The SEO module endpoint is not configured.",
      "SEO_MODULE_API_SECRET is missing or shorter than 32 characters",
    );
  }
  const presented = headers.get(MODULE_SECRET_HEADER);
  if (!presented || !secretsMatch(presented, config.moduleApiSecret)) {
    throw new SeoModuleContractError(
      "unauthorized",
      "This caller is not authorized to use the SEO module interface.",
    );
  }
}

function errorBody(code: ModuleErrorCode, message: string): string {
  return JSON.stringify({ error: { code, message } });
}

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function toResponse(error: SeoModuleContractError): Response {
  return new Response(errorBody(error.code, error.message), {
    status: ERROR_HTTP_STATUS[error.code],
    headers: JSON_HEADERS,
  });
}

export async function serveModuleRequest(
  request: Request,
  config: TransportConfig,
  deps: HandlerDeps,
): Promise<Response> {
  try {
    if (request.method === "GET") {
      // Capability discovery. Authenticated like every other call: the set of
      // capabilities SEO exposes is not public information.
      authorizeCaller(request.headers, config);
      return new Response(JSON.stringify(SEO_MODULE_DECLARATION), {
        status: 200,
        headers: JSON_HEADERS,
      });
    }

    if (request.method !== "POST") {
      throw new SeoModuleContractError("invalid_request", "Only GET and POST are supported.");
    }

    authorizeCaller(request.headers, config);

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      throw new SeoModuleContractError("invalid_request", "Request body must be valid JSON.");
    }

    const result = await handleModuleRequest(body, deps);
    return new Response(JSON.stringify(result), { status: 200, headers: JSON_HEADERS });
  } catch (error) {
    if (error instanceof SeoModuleContractError) {
      // internalReason stays SEO-side. The wire body carries only the
      // normalized code and a message that reveals nothing about which
      // workspaces, websites or links exist.
      deps.log?.({
        event: "seo_module_error",
        code: error.code,
        internalReason: error.internalReason ?? null,
      });
      return toResponse(error);
    }
    deps.log?.({
      event: "seo_module_unhandled_error",
      detail: error instanceof Error ? error.message : String(error),
    });
    return toResponse(
      new SeoModuleContractError("module_unavailable", "The SEO module could not complete this request."),
    );
  }
}
