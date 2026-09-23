import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * Structural proof of the machine-path isolation requirement.
 *
 * The rule is not "we remembered not to import the mocks", it is that the
 * browser service-adapter layer is not reachable from this directory at all.
 * These assertions fail the build the moment someone adds an import that would
 * put src/services/serviceAdapter.ts, src/services/dataMode.ts or src/mocks/
 * back in the machine path's import graph, which is the only way a Digi Brain
 * response could ever carry mock, sample or demo data.
 */

const here = dirname(fileURLToPath(import.meta.url));

function moduleFiles(): string[] {
  return readdirSync(here)
    .filter((name) => name.endsWith(".ts"))
    .filter((name) => !name.endsWith(".test.ts"))
    .sort();
}

function importSpecifiers(source: string): string[] {
  const specifiers: string[] = [];
  const patterns = [
    /\bfrom\s+["']([^"']+)["']/g,
    /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g,
    /\brequire\s*\(\s*["']([^"']+)["']\s*\)/g,
  ];
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) specifiers.push(match[1]);
  }
  return specifiers;
}

describe("machine path isolation", () => {
  const files = moduleFiles();

  it("covers every non-test file in the directory", () => {
    expect(files).toEqual([
      "capabilities.ts",
      "contract.ts",
      "handler.ts",
      "http.ts",
      "index.ts",
      "link-intent-http.ts",
      "link-intent-port.ts",
      "link-intent.ts",
      "normalize-host.ts",
      "port.ts",
      "supabase-port.ts",
      "test-support.ts",
    ]);
  });

  it.each(files)("%s imports nothing from the browser application", (name) => {
    const source = readFileSync(join(here, name), "utf8");
    for (const specifier of importSpecifiers(source)) {
      // No alias into src/, and no relative path that climbs out of
      // supabase/functions/ towards the application.
      expect(specifier.startsWith("@/")).toBe(false);
      expect(specifier).not.toMatch(/(^|\/)src\//);
      expect(specifier).not.toMatch(/\.\.\/\.\.\/\.\./);
    }
  });

  it.each(files)("%s never names the mock or service-adapter layer", (name) => {
    const source = readFileSync(join(here, name), "utf8");
    // Comments may explain why these are absent; code may not reference them.
    const code = source
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    expect(code).not.toContain("runWithServiceAdapter");
    expect(code).not.toContain("serviceAdapter");
    expect(code).not.toContain("getSeoDataMode");
    expect(code).not.toContain("getCurrentSeoWorkspace");
    expect(code).not.toContain("mocks/");
  });

  it("resolves a target only by Business plus host, never by a caller-named website", () => {
    // Every delegated RPC takes p_business_id and p_normalized_host only. If a
    // p_website_id or p_workspace_id argument ever appears here, a machine
    // caller could name a target it was not linked to.
    const source = readFileSync(join(here, "supabase-port.ts"), "utf8");
    expect(source).not.toContain("p_website_id");
    expect(source).not.toContain("p_workspace_id");
  });
});
