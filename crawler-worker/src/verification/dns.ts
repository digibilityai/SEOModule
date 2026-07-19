// DNS-TXT resolution for ownership verification. DNS TXT only — NO HTTP, so no
// SSRF surface is introduced. The resolver is injectable so unit/integration
// tests use a deterministic fake and never depend on public DNS.
//
// Node's resolveTxt returns string[][]: one entry per TXT record, each entry an
// array of the record's string chunks. A record's value is the chunks JOINED
// (RFC 1035 multi-string flattening). Matching is EXACT against the expected
// challenge value returned by the Step 2B claim RPC — no substring, no case
// normalization, no cross-record reconstruction.
import { promises as dns } from "node:dns";
import { readFileSync } from "node:fs";

/** Injectable resolver. Returns raw Node semantics: string[][] (records × chunks). */
export interface DnsTxtResolver {
  resolveTxt(host: string, timeoutMs: number): Promise<string[][]>;
}

/** Deterministic outcome of comparing resolved TXT records to the challenge. */
export type DnsFailureKind =
  | "not_found"
  | "mismatch"
  | "timeout"
  | "temporary"
  | "malformed"
  | "internal";

interface FailureSpec {
  /** Customer-safe reason — safe for seo_ownership_verifications.failure_reason. */
  reason: string;
  /** Stable internal code — stored ONLY on the admin-only claim row. */
  code: string;
}

export const DNS_FAILURES: Record<DnsFailureKind, FailureSpec> = {
  not_found:  { reason: "The DNS TXT record was not found. Add the record and re-check.", code: "dns_not_found" },
  mismatch:   { reason: "A DNS TXT record was found but did not match the expected verification value.", code: "dns_mismatch" },
  timeout:    { reason: "The DNS lookup timed out. Please re-check shortly.", code: "dns_timeout" },
  temporary:  { reason: "DNS is temporarily unavailable. Please re-check shortly.", code: "dns_temporary" },
  malformed:  { reason: "The DNS response could not be read.", code: "dns_malformed" },
  internal:   { reason: "Verification could not be completed due to an internal error.", code: "internal_error" },
};

/** Marker for a bounded-timeout rejection so classification is deterministic. */
export class DnsTimeoutError extends Error {
  readonly code = "ETIMEOUT" as const;
  constructor(message = "dns lookup timed out") { super(message); this.name = "DnsTimeoutError"; }
}

/**
 * Map a resolver error (or a "records exist but no match") to a deterministic
 * failure kind. `mismatch` is passed explicitly by the runner (it is not an
 * error); everything else is derived from the error's `.code`.
 */
export function classifyDnsError(err: unknown): DnsFailureKind {
  const code = (err && typeof err === "object" && "code" in err ? String((err as { code?: unknown }).code) : "") || "";
  switch (code) {
    case "ENOTFOUND":
    case "ENODATA":
      return "not_found";
    case "ETIMEOUT":
    case "ETIMEDOUT":
      return "timeout";
    case "ESERVFAIL":
    case "ETRYAGAIN":
    case "EREFUSED":
    case "ECONNREFUSED":
      return "temporary";
    case "EBADRESP":
    case "EBADNAME":
      return "malformed";
    default:
      return "internal";
  }
}

/**
 * Does any resolved TXT record EXACTLY equal the expected challenge value once
 * its multi-string chunks are flattened (joined)? Exact, case-sensitive.
 */
export function txtRecordsMatch(records: string[][], expected: string): boolean {
  if (!Array.isArray(records)) return false;
  for (const chunks of records) {
    if (!Array.isArray(chunks)) continue;
    if (chunks.join("") === expected) return true;
  }
  return false;
}

/** Production resolver: Node DNS with a bounded timeout. No HTTP. */
export class NodeDnsTxtResolver implements DnsTxtResolver {
  async resolveTxt(host: string, timeoutMs: number): Promise<string[][]> {
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new DnsTimeoutError()), timeoutMs);
      timer.unref?.();
    });
    try {
      return (await Promise.race([dns.resolveTxt(host), timeout])) as string[][];
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}

/**
 * TEST-ONLY fixture resolver. Reads a JSON map { "<txtName>": string[][] } so a
 * `verify-once` run can be exercised without public DNS. Honoured only when the
 * config supplies a fixture path (test environment). A missing host resolves to
 * an ENOTFOUND-shaped error so the failure path is exercised deterministically.
 */
export class FixtureDnsTxtResolver implements DnsTxtResolver {
  private readonly map: Record<string, string[][]>;
  constructor(fixturePathOrMap: string | Record<string, string[][]>) {
    this.map = typeof fixturePathOrMap === "string"
      ? (JSON.parse(readFileSync(fixturePathOrMap, "utf8")) as Record<string, string[][]>)
      : fixturePathOrMap;
  }
  async resolveTxt(host: string): Promise<string[][]> {
    const rec = this.map[host];
    if (rec === undefined) throw Object.assign(new Error(`no fixture TXT for ${host}`), { code: "ENOTFOUND" });
    return rec;
  }
}
