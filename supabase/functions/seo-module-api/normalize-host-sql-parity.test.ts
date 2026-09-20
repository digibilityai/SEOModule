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
// THE TRIM IS ASYMMETRIC, because the TypeScript twin is: it runs JS
// String.trim() on the RAW value and only then prefixes 'https://', so the URL
// parser's leading trim never sees the start of the caller's string.
//   LEADING  = Postgres '[[:space:]]', which is JS String.trim()'s ASCII set.
//              A leading C0 control (NUL, SOH, US) or DEL is NOT trimmed and
//              falls through to FORBIDDEN, exactly as TypeScript fails it.
//   TRAILING = Postgres '[chr(1)-chr(32)]', the parser's own C0-or-space strip.
//              DEL (\u007f) is excluded on purpose: it is not a C0 control, the
//              parser does not strip it, and it must reach FORBIDDEN.
const TRIM_LEAD = /^[\u0009-\u000d\u0020]+/;
const TRIM_TRAIL = /[\u0001-\u0020]+$/;
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

  raw = raw.replace(TRIM_LEAD, "");
  raw = raw.replace(TRIM_TRAIL, "");
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
  const NUL = String.fromCharCode(0x00);
  const SOH = String.fromCharCode(0x01);
  const US = String.fromCharCode(0x1f);
  const DEL = String.fromCharCode(0x7f);

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
    // --------------------------------------------------------------------
    // LEADING C0 controls and DEL. These are the cases a symmetric
    // '[[:space:][:cntrl:]]' trim got WRONG: it stripped them and returned a
    // clean canonical host, where TypeScript fails the parse. JS String.trim()
    // does not remove them, and the URL parser never sees the start of the
    // caller's string because 'https://' is prefixed first, so they survive
    // into the authority and are rejected there. All four must be null.
    `${NUL}example.com`,
    `${SOH}example.com`,
    `${US}example.com`,
    `${DEL}example.com`,
    `${NUL}https://example.com`,
    `${DEL}https://example.com`,
    NUL,
    SOH,
    US,
    DEL,
    // TRAILING. After the scheme is prefixed the caller's tail IS the parser's
    // tail, so the parser's C0-or-space strip applies and these normalize.
    `example.com${SOH}`,
    `example.com${US}`,
    // ...but DEL is not a C0 control, so the parser does not strip it and the
    // host fails. This is why the trailing class stops at chr(32).
    `example.com${DEL}`,
    // Leading and trailing ASCII whitespace that is not the space character.
    `${FF}example.com`,
    `${VT}example.com`,
    `example.com${FF}`,
    `example.com${VT}`,
    `${CR}${LF}example.com`,
    `example.com${CR}${LF}`,
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

  it("trims each end with the set that end actually uses", () => {
    const NUL = String.fromCharCode(0x00);
    const SOH = String.fromCharCode(0x01);
    const DEL = String.fromCharCode(0x7f);

    // A symmetric '[[:space:][:cntrl:]]' trim on BOTH ends would return
    // 'example.com' for every one of these, which is a fail-OPEN divergence:
    // SQL would hand back a clean canonical host for a value TypeScript
    // refuses to parse.
    for (const input of [`${NUL}example.com`, `${SOH}example.com`, `${DEL}example.com`]) {
      expect(sqlNormalizeHost(input)).toBeNull();
      expect(normalizeWebsiteHost(input)).toBeNull();
    }

    // The trailing end is genuinely different, and both sides agree on it.
    expect(sqlNormalizeHost(`example.com${SOH}`)).toBe("example.com");
    expect(normalizeWebsiteHost(`example.com${SOH}`)).toBe("example.com");

    // DEL is not a C0 control, so neither side strips it from the tail.
    expect(sqlNormalizeHost(`example.com${DEL}`)).toBeNull();
    expect(normalizeWebsiteHost(`example.com${DEL}`)).toBeNull();

    // THE ONE INPUT THAT IS NOT COMPARABLE, stated rather than hidden: a
    // trailing NUL. TypeScript normalizes it to 'example.com' because the URL
    // parser strips it; the model returns null because the trailing class
    // starts at chr(1). That gap is unreachable in SQL, because PostgreSQL
    // text cannot contain chr(0) at all, so the real function can never be
    // handed this value. It is excluded from the corpus for that reason.
    expect(normalizeWebsiteHost(`example.com${NUL}`)).toBe("example.com");
    expect(sqlNormalizeHost(`example.com${NUL}`)).toBeNull();
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
