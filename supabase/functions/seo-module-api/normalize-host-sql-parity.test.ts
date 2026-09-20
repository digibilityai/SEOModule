import { describe, expect, it } from "vitest";
import { normalizeWebsiteHost } from "./normalize-host.ts";

/**
 * A FAITHFUL MODEL of public.seo_brain_normalize_host, as corrected by
 * migration 20260920120400, checked against the TypeScript twin.
 *
 * WHAT THIS IS, PRECISELY. It does NOT execute the SQL. No Postgres, Docker or
 * Supabase runtime exists in the environment this repository is developed in,
 * so the only way to run the real function is an operator session against
 * Digi_SEO_Test, which is what
 * supabase/test/seo_brain_module_boundary_verification.sql Section 0 is for.
 * This file transcribes the PL/pgSQL control flow statement for statement and
 * runs the same parity corpus through it, so a divergence in the ALGORITHM is
 * caught here at `npm test` instead of surviving until an operator run.
 *
 * WHY IT IS WORTH HAVING. The defect the first controlled TEST run found was
 * exactly of this kind: an authority pattern that excluded ":[]/?#" but not
 * whitespace, so SQL accepted 'not a url' while TypeScript rejected it. Nothing
 * in the previous test suite could see that, because nothing compared the two
 * implementations' logic. This does.
 *
 * WHAT IT CANNOT PROVE. Postgres regex and string semantics are modelled, not
 * executed, so a Postgres-specific behaviour difference would slip through.
 * The operator SQL run remains the authority; this is the fast guard in front
 * of it.
 */

// Postgres '[[:space:][:cntrl:]]' is exactly space + C0 + DEL:
//   [:space:] = {space, TAB, LF, VT, FF, CR}  (all within \x00-\x20)
//   [:cntrl:] = \x00-\x1f plus \x7f
// The union is \x00-\x20 plus \x7f. JS \s is NOT used here: it additionally
// matches non-ASCII whitespace, which Postgres would not, and the model has to
// be faithful rather than convenient.
const FORBIDDEN = /[\u0000-\u0020\u007f]/;
const FORBIDDEN_LEAD = /^[\u0000-\u0020\u007f]+/;
const FORBIDDEN_TRAIL = /[\u0000-\u0020\u007f]+$/;
// ASCII tab, LF, CR: removed from the input by the URL parser (translate()).
const STRIP = /[\u0009\u000a\u000d]/g;


const DEFAULT_PORTS: Record<string, number> = {
  https: 443,
  http: 80,
  wss: 443,
  ws: 80,
  ftp: 21,
};

/** Line-for-line model of the corrected PL/pgSQL body. */
function sqlNormalizeHost(input: string | null): string | null {
  let raw = input ?? ""; // coalesce(p_website_url, '')

  raw = raw.replace(FORBIDDEN_LEAD, "");
  raw = raw.replace(FORBIDDEN_TRAIL, "");
  raw = raw.replace(STRIP, "");

  if (raw === "") return null;

  const schemeMatch = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\//.exec(raw);
  let scheme: string;
  let authority: string;
  if (schemeMatch === null) {
    scheme = "https";
    authority = raw;
  } else {
    scheme = schemeMatch[1].toLowerCase();
    authority = raw.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "");
  }

  authority = authority.replace(/^[^/?#@]*@/, "");
  // Postgres '.' matches a newline; [\s\S] is the JS equivalent.
  authority = authority.replace(/[/?#][\s\S]*$/, "");
  if (authority === "") return null;

  // THE FIX: whitespace and controls are forbidden in the host and the port.
  if (FORBIDDEN.test(authority)) return null;

  let host: string;
  let portText: string | null;
  const ipv6 = /^\[[0-9A-Fa-f:.]+\](:[0-9]*)?$/;
  const named = /^[^:[\]/?#]+(:[0-9]*)?$/;
  if (ipv6.test(authority)) {
    host = /^(\[[0-9A-Fa-f:.]+\])/.exec(authority)![1].toLowerCase();
    portText = /:([0-9]*)$/.exec(authority)?.[1] ?? null;
  } else if (named.test(authority)) {
    host = authority.split(":")[0].toLowerCase();
    portText = /:([0-9]*)$/.exec(authority)?.[1] ?? null;
    if (host.startsWith("www.")) host = host.slice(4);
  } else {
    return null;
  }

  if (host === "") return null;
  if (portText === null || portText === "") return host;

  const port = parseInt(portText, 10); // also drops leading zeros
  if (port < 0 || port > 65535) return null;
  if (DEFAULT_PORTS[scheme] === port) return host;

  return `${host}:${port}`;
}

describe("seo_brain_normalize_host (modelled) agrees with normalizeWebsiteHost", () => {
  const TAB = String.fromCharCode(0x09);
  const LF = String.fromCharCode(0x0a);
  const CR = String.fromCharCode(0x0d);
  const FF = String.fromCharCode(0x0c);
  const VT = String.fromCharCode(0x0b);

  // The union of both corpora in normalize-host.test.ts, which is also the
  // corpus Section 0 of the verification script runs against the real function.
  const corpus: string[] = [
    "https://example.com",
    "https://example.com/pricing?q=1#top",
    "example.com",
    "HTTPS://EXAMPLE.COM",
    "https://www.example.com",
    "https://shop.example.com",
    "https://www.shop.example.com",
    "https://a.b.example.co.uk",
    "https://example.com:443",
    "http://example.com:80",
    "https://example.com:8443",
    "http://example.com:8080",
    "https://www.example.com:8443",
    "https://user:pass@example.com/x",
    "",
    "   ",
    "not a url",
    `exa${TAB}mple.com`,
    `exa${LF}mple.com`,
    `exa${CR}mple.com`,
    "exa mple.com",
    "example .com",
    `exa${FF}mple.com`,
    `exa${VT}mple.com`,
    "https://example.com:84 43",
    `https://example.com${FF}/x`,
    " example.com ",
    `${TAB}example.com`,
    TAB,
    FF,
    VT,
    "https://example.com/a b",
    "https://example.com/?q=a b",
    "https://example.com/x#a b",
    "https://us er:pa ss@example.com/x",
    `https://exa${TAB}mple.com:8443/p a th`,
  ];

  it.each(corpus)("agrees on %j", (input) => {
    expect(sqlNormalizeHost(input)).toBe(normalizeWebsiteHost(input));
  });

  it("models the exact defect the TEST run found", () => {
    // The pre-correction authority pattern, for contrast: it excluded ":[]/?#"
    // and nothing else, so a space sailed through and the input came back as
    // if it were a canonical host.
    expect(/^[^:[\]/?#]+(:[0-9]*)?$/.test("not a url")).toBe(true);
    // The corrected function rejects it, and so does TypeScript.
    expect(sqlNormalizeHost("not a url")).toBeNull();
    expect(normalizeWebsiteHost("not a url")).toBeNull();
  });

  it("changes no canonical valid-host output", () => {
    // Every host the boundary actually carries is ASCII letters, digits, dots,
    // hyphens and an optional port; none of that is in the rejected set, so the
    // correction cannot move a valid result.
    for (const host of [
      "example.com",
      "shop.example.com",
      "a.b.example.co.uk",
      "example.com:8443",
      "xn--mnchen-3ya.de",
    ]) {
      expect(sqlNormalizeHost(host)).toBe(host);
    }
  });
});
