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

/**
 * Whitespace and control characters.
 *
 * The first controlled TEST run found a genuine parity defect: SQL returned
 * "not a url" verbatim where this function returns null, because the SQL
 * authority pattern excluded ":[]/?#" but not whitespace. Migration
 * 20260920120400 corrects the SQL; these cases pin the behaviour both sides are
 * now held to, and the same table appears in
 * supabase/test/seo_brain_module_boundary_verification.sql.
 *
 * Three distinct rules are at work here and they are easy to conflate:
 *   1. ASCII tab, LF and CR are REMOVED from the whole input by the URL parser
 *      before it reads anything, so a host containing one still normalizes.
 *   2. Any OTHER ASCII whitespace or control character in the HOST or PORT is a
 *      forbidden host code point and fails the parse.
 *   3. The same characters are perfectly legal in a path, a query, a fragment
 *      and in userinfo, none of which is part of the identity.
 */
describe("normalizeWebsiteHost whitespace and control characters", () => {
  // Built with fromCharCode so this source file never carries a raw control
  // character, which some editors and diff tools silently rewrite.
  const TAB = String.fromCharCode(0x09);
  const LF = String.fromCharCode(0x0a);
  const CR = String.fromCharCode(0x0d);
  const FF = String.fromCharCode(0x0c);
  const VT = String.fromCharCode(0x0b);

  const cases: Array<[string, string | null]> = [
    // 1. Removed by the parser, so these normalize.
    [`exa${TAB}mple.com`, "example.com"],
    [`exa${LF}mple.com`, "example.com"],
    [`exa${CR}mple.com`, "example.com"],
    // 2. Forbidden in the host.
    ["exa mple.com", null],
    ["example .com", null],
    [`exa${FF}mple.com`, null],
    [`exa${VT}mple.com`, null],
    // ...and in the port, which is part of the authority.
    ["https://example.com:84 43", null],
    [`https://example.com${FF}/x`, null],
    // Leading and trailing whitespace is trimmed, not only the space character.
    [" example.com ", "example.com"],
    [`${TAB}example.com`, "example.com"],
    [TAB, null],
    [FF, null],
    [VT, null],
    // 3. Legal outside the host and port.
    ["https://example.com/a b", "example.com"],
    ["https://example.com/?q=a b", "example.com"],
    ["https://example.com/x#a b", "example.com"],
    ["https://us er:pa ss@example.com/x", "example.com"],
    [`https://exa${TAB}mple.com:8443/p a th`, "example.com:8443"],
  ];

  it.each(cases)("normalizes %j", (input, expected) => {
    expect(normalizeWebsiteHost(input)).toBe(expected);
  });

  it("refuses a host carrying whitespace as already-canonical", () => {
    expect(isCanonicalHost("not a url")).toBe(false);
    expect(isCanonicalHost("exa mple.com")).toBe(false);
    expect(isCanonicalHost(`exa${TAB}mple.com`)).toBe(false);
    expect(isCanonicalHost(" example.com")).toBe(false);
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
