import { describe, expect, it } from "vitest";
import { MODULE_SECRET_HEADER, secretsMatch, serveModuleRequest } from "./http.ts";
import { createSupabaseSeoDataPort, type RpcCaller } from "./supabase-port.ts";
import { FakeSeoDataPort, baseStore, moduleRequest } from "./test-support.ts";

const SECRET = "a".repeat(48);
const config = { moduleApiSecret: SECRET };

function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://seo.example/functions/v1/seo-module-api", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

function withSecret(secret = SECRET): Record<string, string> {
  return { [MODULE_SECRET_HEADER]: secret };
}

function deps() {
  return { db: new FakeSeoDataPort(baseStore()) };
}

describe("machine credential", () => {
  it("accepts a caller presenting the configured secret", async () => {
    const response = await serveModuleRequest(post(moduleRequest(), withSecret()), config, deps());
    expect(response.status).toBe(200);
  });

  it.each([
    ["no secret header", {}],
    ["an empty secret", { [MODULE_SECRET_HEADER]: "" }],
    ["a wrong secret of the same length", { [MODULE_SECRET_HEADER]: "b".repeat(48) }],
    ["a truncated secret", { [MODULE_SECRET_HEADER]: "a".repeat(47) }],
  ])("refuses a caller with %s", async (_label, headers) => {
    const dependencies = deps();
    const response = await serveModuleRequest(post(moduleRequest(), headers), config, dependencies);
    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: { code: "unauthorized", message: expect.any(String) },
    });
    // Refused before any database read.
    expect(dependencies.db.calls).toHaveLength(0);
  });

  it("fails closed, not open, when the server has no secret configured", async () => {
    const dependencies = deps();
    const response = await serveModuleRequest(
      post(moduleRequest(), withSecret()),
      { moduleApiSecret: "" },
      dependencies,
    );
    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: { code: "module_unavailable", message: expect.any(String) },
    });
    expect(dependencies.db.calls).toHaveLength(0);
  });

  it("refuses a too-short configured secret rather than trusting it", async () => {
    const response = await serveModuleRequest(
      post(moduleRequest(), withSecret("short")),
      { moduleApiSecret: "short" },
      deps(),
    );
    expect(response.status).toBe(503);
  });

  it("compares secrets without short-circuiting on the first differing character", () => {
    expect(secretsMatch("abcd", "abcd")).toBe(true);
    expect(secretsMatch("abcd", "abce")).toBe(false);
    expect(secretsMatch("abc", "abcd")).toBe(false);
  });
});

describe("transport behaviour", () => {
  it("serves the capability declaration on an authenticated GET", async () => {
    const request = new Request("https://seo.example/functions/v1/seo-module-api", {
      method: "GET",
      headers: withSecret(),
    });
    const response = await serveModuleRequest(request, config, deps());
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      moduleId: "seo",
      contractVersion: "module-contract.v1",
      capabilities: [
        "analyse.target_linkage",
        "analyse.ownership_verification",
        "analyse.crawl_findings",
        "analyse.current_recommendations",
      ],
    });
  });

  it("does not serve the capability declaration to an unauthenticated caller", async () => {
    const request = new Request("https://seo.example/functions/v1/seo-module-api", { method: "GET" });
    const response = await serveModuleRequest(request, config, deps());
    expect(response.status).toBe(403);
  });

  it("refuses a method other than GET or POST", async () => {
    const request = new Request("https://seo.example/functions/v1/seo-module-api", {
      method: "DELETE",
      headers: withSecret(),
    });
    const response = await serveModuleRequest(request, config, deps());
    expect(response.status).toBe(400);
  });

  it("refuses a body that is not valid JSON", async () => {
    const request = new Request("https://seo.example/functions/v1/seo-module-api", {
      method: "POST",
      headers: { "content-type": "application/json", ...withSecret() },
      body: "{not json",
    });
    const response = await serveModuleRequest(request, config, deps());
    expect(response.status).toBe(400);
  });

  it("maps an unlinked target onto target_not_linked without leaking the reason", async () => {
    const response = await serveModuleRequest(
      post(moduleRequest({ businessId: "biz-unknown" }), withSecret()),
      config,
      deps(),
    );
    expect(response.status).toBe(404);
    const body = (await response.json()) as { error: { code: string; message: string } };
    expect(body.error.code).toBe("target_not_linked");
    // The specific SEO-side reason stays server-side.
    expect(body.error.message).not.toContain("revoked");
    expect(body.error.message).not.toContain("host_changed");
  });

  it("keeps the internal reason out of the wire body but hands it to the log sink", async () => {
    const events: Array<Record<string, unknown>> = [];
    const store = baseStore();
    store.links = [
      { businessId: "biz-1", websiteId: "site-a", normalizedHost: "example.com", linkStatus: "revoked" },
    ];
    const response = await serveModuleRequest(post(moduleRequest(), withSecret()), config, {
      db: new FakeSeoDataPort(store),
      log: (event) => events.push(event),
    });

    expect(response.status).toBe(404);
    expect(events).toContainEqual(
      expect.objectContaining({ event: "seo_module_target_not_linked", reason: "revoked" }),
    );
  });

  it("returns module_unavailable rather than any fallback when the database fails", async () => {
    const failing: RpcCaller = {
      rpc: async () => ({ data: null, error: { message: "connection refused" } }),
    };
    const response = await serveModuleRequest(post(moduleRequest(), withSecret()), config, {
      db: createSupabaseSeoDataPort(failing),
    });
    expect(response.status).toBe(503);
    const body = (await response.json()) as { error: { code: string } };
    expect(body.error.code).toBe("module_unavailable");
  });

  it("returns module_unavailable when the RPC layer throws", async () => {
    const throwing: RpcCaller = {
      rpc: async () => {
        throw new Error("socket hang up");
      },
    };
    const response = await serveModuleRequest(post(moduleRequest(), withSecret()), config, {
      db: createSupabaseSeoDataPort(throwing),
    });
    expect(response.status).toBe(503);
  });
});

describe("supabase port mapping", () => {
  it("maps the resolve_target row set onto the port shape", async () => {
    const caller: RpcCaller = {
      rpc: async (fn, args) => {
        expect(fn).toBe("seo_brain_resolve_target");
        expect(args).toEqual({ p_business_id: "biz-1", p_normalized_host: "example.com" });
        return {
          data: [
            {
              resolution: "resolved",
              workspace_id: "ws-1",
              website_id: "site-a",
              normalized_host: "example.com",
              website_url: "https://www.example.com",
              linked_at: "2026-09-01T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    };
    const port = createSupabaseSeoDataPort(caller);
    await expect(port.resolveTarget("biz-1", "example.com")).resolves.toEqual({
      resolution: "resolved",
      workspaceId: "ws-1",
      websiteId: "site-a",
      normalizedHost: "example.com",
      websiteUrl: "https://www.example.com",
      linkedAt: "2026-09-01T00:00:00.000Z",
    });
  });

  it("maps a jsonb findings payload, including the resolved-but-empty case", async () => {
    const caller: RpcCaller = {
      rpc: async () => ({
        data: {
          resolution: "resolved",
          websiteId: "site-a",
          auditRunId: "run-1",
          auditCompletedAt: "2026-09-10T00:00:00.000Z",
          findings: [],
        },
        error: null,
      }),
    };
    const page = await createSupabaseSeoDataPort(caller).crawlFindings("biz-1", "example.com");
    // Distinguishable from "did not resolve", which is the whole point of the
    // single-payload shape.
    expect(page.resolution).toBe("resolved");
    expect(page.findings).toEqual([]);
  });

  it("treats an unrecognized resolution as module_unavailable rather than guessing", async () => {
    const caller: RpcCaller = {
      rpc: async () => ({ data: { resolution: "something_new" }, error: null }),
    };
    await expect(
      createSupabaseSeoDataPort(caller).ownershipStatus("biz-1", "example.com"),
    ).rejects.toMatchObject({ code: "module_unavailable" });
  });
});
