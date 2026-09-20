import { describe, expect, it } from "vitest";
import { isCanonicalHost, normalizeWebsiteHost } from "./normalize-host.ts";

/**
 * Parity pins for the canonical machine-boundary host.
 *
 * Every expectation here is the behaviour of Digi Brain's normalizeWebsiteHost
 * (lib/identity/website-identity.ts), which is the frozen identity Contract v1
 * carries. The SQL twin, public.seo_brain_normalize_host, must agree with every
 * row in this table; supabase/test/seo_brain_module_boundary_verification.sql
 * asserts the same cases against the database.
 */
describe("normalizeWebsiteHost parity with Digi Brain", () => {
  const cases: Array<[string, string | null]> = [
    ["https://example.com", "example.com"],
    ["https://example.com/pricing?q=1#top", "example.com"],
    ["example.com", "example.com"],
    ["HTTPS://EXAMPLE.COM", "example.com"],
    // A single leading www. is stripped; a deeper subdomain is not.
    ["https://www.example.com", "example.com"],
    ["https://shop.example.com", "shop.example.com"],
    ["https://www.shop.example.com", "shop.example.com"],
    // No public-suffix reduction: subdomains stay distinct identities.
    ["https://a.b.example.co.uk", "a.b.example.co.uk"],
    // A default port is absent in the parsed URL; any other port is identity.
    ["https://example.com:443", "example.com"],
    ["http://example.com:80", "example.com"],
    ["https://example.com:8443", "example.com:8443"],
    ["http://example.com:8080", "example.com:8080"],
    // www. stripping runs on the hostname alone and never touches the port.
    ["https://www.example.com:8443", "example.com:8443"],
    // Userinfo is not part of the identity.
    ["https://user:pass@example.com/x", "example.com"],
    ["", null],
    ["   ", null],
    ["not a url", null],
  ];

  it.each(cases)("normalizes %s", (input, expected) => {
    expect(normalizeWebsiteHost(input)).toBe(expected);
  });
});

describe("isCanonicalHost", () => {
  it("accepts a value that is already canonical", () => {
    expect(isCanonicalHost("example.com")).toBe(true);
    expect(isCanonicalHost("shop.example.com")).toBe(true);
    expect(isCanonicalHost("example.com:8443")).toBe(true);
  });

  it("rejects anything the caller should have normalized first", () => {
    // These are refused rather than silently corrected, so the value SEO
    // resolves against is always the value the caller actually asked for.
    expect(isCanonicalHost("https://example.com")).toBe(false);
    expect(isCanonicalHost("www.example.com")).toBe(false);
    expect(isCanonicalHost("EXAMPLE.COM")).toBe(false);
    expect(isCanonicalHost("example.com/")).toBe(false);
    expect(isCanonicalHost("example.com:443")).toBe(false);
    expect(isCanonicalHost("")).toBe(false);
  });
});
