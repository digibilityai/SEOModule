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

// WHY NO POSIX CLASS APPEARS IN THIS MODEL, and why that is the whole point.
// Migration 20260920120400 wrote the leading trim as Postgres '[[:space:]]' on
// the assumption that it equals JS String.trim()'s ASCII set. The controlled
// TEST run disproved it in Section 0: on glibc, '[[:space:]]' is
//   9,10,11,12,13,28,29,30,31,32
// because FS/GS/RS/US are classified as space characters, which JavaScript does
// NOT do. A leading U+001C..U+001F was therefore trimmed and a clean canonical
// host was returned for a value the twin rejects. 20260920120500 writes the
// parity classes out explicitly, and so does this model. A POSIX class must
// never be used where the result has to MATCH JavaScript.
//
// FORBIDDEN is the one place a POSIX class survives in the SQL, because there
// it is a REJECTION gate rather than a parity target: '[:space:]'/'[:cntrl:]'
// reject MORE than ASCII (U+0085, U+00A0, U+2028, U+3000 and friends on this
// database), and rejecting more fails closed. The explicit chr(1)..chr(32) and
// chr(127) floor guarantees the ASCII part cannot shrink with the locale. The
// model mirrors both halves.
const FORBIDDEN =
  /[\u0001-\u0020\u007f\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]/;
// THE TRIM IS ASYMMETRIC, because the TypeScript twin is: it runs JS
// String.trim() on the RAW value and only then prefixes 'https://', so the URL
// parser's leading trim never sees the start of the caller's string.
//   LEADING  = '[chr(9)-chr(13)chr(32)]', JS String.trim()'s ASCII set written
//              out. A leading C0 control (SOH, FS, GS, RS, US) or DEL is NOT
//              trimmed and falls through to FORBIDDEN, as TypeScript fails it.
//   TRAILING = '[chr(1)-chr(32)]', the parser's own C0-or-space strip. DEL
//              (\u007f) is excluded on purpose: it is not a C0 control, the
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
    // SYSTEMATIC SWEEP over every ASCII character either side treats
    // specially: 9..13 (JS whitespace), 28..31 (glibc-only "space", the
    // 20260920120500 defect), 32 (space), 1 (a plain C0 control) and 127
    // (DEL). Four positions each: leading, trailing, alone and inner. NUL is
    // absent because PostgreSQL text cannot contain chr(0).
    ...[0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x01, 0x7f].flatMap(
      (n) => {
        const ch = String.fromCharCode(n);
        return [`${ch}example.com`, `example.com${ch}`, ch, `exa${ch}mple.com`];
      },
    ),
    // IPv4 and IPv6 literals, including a port and an uppercase IPv6 literal.
    "192.168.1.1",
    "https://192.168.1.1:8443",
    "http://192.168.1.1:80",
    "[::1]",
    "https://[::1]:8443",
    "http://[2001:db8::1]:80",
    "https://[2001:DB8::1]",
    // --------------------------------------------------------------------
    // LEADING C0 controls and DEL. These are the cases a symmetric
    // '[[:space:][:cntrl:]]' trim got WRONG: it stripped them and returned a
    // clean canonical host, where TypeScript fails the parse. JS String.trim()
    // does not remove them, and the URL parser never sees the start of the
    // caller's string because 'https://' is prefixed first, so they survive
    // into the authority and are rejected there. All four must be null.
    `${SOH}example.com`,
    `${US}example.com`,
    `${DEL}example.com`,
    `${DEL}https://example.com`,
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
    for (const input of [`${SOH}example.com`, `${DEL}example.com`]) {
      expect(sqlNormalizeHost(input)).toBeNull();
      expect(normalizeWebsiteHost(input)).toBeNull();
    }

    // The trailing end is genuinely different, and both sides agree on it.
    expect(sqlNormalizeHost(`example.com${SOH}`)).toBe("example.com");
    expect(normalizeWebsiteHost(`example.com${SOH}`)).toBe("example.com");

    // DEL is not a C0 control, so neither side strips it from the tail.
    expect(sqlNormalizeHost(`example.com${DEL}`)).toBeNull();
    expect(normalizeWebsiteHost(`example.com${DEL}`)).toBeNull();

    // NUL IS EXCLUDED FROM THE CORPUS ENTIRELY, stated rather than hidden.
    // PostgreSQL text cannot contain chr(0), so the real function can never be
    // handed a value containing one and the SQL classes all start at chr(1).
    // The twin does define a behaviour for it, and the model happens to agree,
    // but neither is authoritative here because the input is unreachable.
    expect(normalizeWebsiteHost(`example.com${NUL}`)).toBe("example.com");
  });

  it("does not trim ASCII 28 to 31, which only glibc calls whitespace", () => {
    // THE 20260920120500 DEFECT, pinned. Postgres '[[:space:]]' on glibc is
    // 9,10,11,12,13,28,29,30,31,32. JS String.trim() is 9,10,11,12,13,32. Using
    // the POSIX class for the leading trim therefore stripped FS/GS/RS/US and
    // returned a clean canonical host for a value the twin rejects.
    for (const n of [0x1c, 0x1d, 0x1e, 0x1f]) {
      const ch = String.fromCharCode(n);
      expect(sqlNormalizeHost(`${ch}example.com`)).toBeNull();
      expect(normalizeWebsiteHost(`${ch}example.com`)).toBeNull();
      // ...but the TRAILING end is the parser's own C0 strip, so these DO
      // normalize, and a trim that was merely narrowed at both ends would have
      // broken them.
      expect(sqlNormalizeHost(`example.com${ch}`)).toBe("example.com");
      expect(normalizeWebsiteHost(`example.com${ch}`)).toBe("example.com");
    }
    // The five JS whitespace characters keep being trimmed at BOTH ends.
    for (const n of [0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20]) {
      const ch = String.fromCharCode(n);
      expect(sqlNormalizeHost(`${ch}example.com`)).toBe("example.com");
      expect(normalizeWebsiteHost(`${ch}example.com`)).toBe("example.com");
    }
  });

  it("leaves the pre-existing IPv6 canonicalization divergence fail-closed", () => {
    // An IPv4-mapped IPv6 literal is recompressed by the URL parser and left
    // alone by SQL. Deferred, not hidden: the SQL output can never equal a
    // canonical host Digi Brain would send, so the comparison refuses rather
    // than resolving the wrong site. Fixing it would mean an IPv6 canonicalizer
    // in PL/pgSQL, which is out of scope for Stage 2B.
    expect(normalizeWebsiteHost("https://[::ffff:192.168.1.1]")).toBe("[::ffff:c0a8:101]");
    expect(sqlNormalizeHost("https://[::ffff:192.168.1.1]")).toBe("[::ffff:192.168.1.1]");
    // Plain IPv6 literals, including an uppercase one, agree exactly.
    for (const input of ["[::1]", "https://[::1]:8443", "https://[2001:DB8::1]"]) {
      expect(sqlNormalizeHost(input)).toBe(normalizeWebsiteHost(input));
    }
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
