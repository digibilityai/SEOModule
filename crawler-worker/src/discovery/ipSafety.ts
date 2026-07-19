// SSRF address classifier — treats an IP as UNSAFE unless it is a normal public
// address. Covers IPv4 + IPv6, including IPv4-mapped IPv6 and cloud metadata.
// Deterministic + dependency-free so it is fully unit-testable.
import net from "node:net";

export interface IpDecision {
  safe: boolean;
  reason?: string;
}

function ipv4ToBytes(ip: string): number[] | null {
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  const bytes: number[] = [];
  for (const p of parts) {
    if (!/^\d{1,3}$/.test(p)) return null;
    const n = Number(p);
    if (n < 0 || n > 255) return null;
    bytes.push(n);
  }
  return bytes;
}

/** Expand an IPv6 (possibly with :: and trailing IPv4) to 16 bytes. */
function ipv6ToBytes(ip: string): number[] | null {
  let s = ip;
  let tail4: number[] | null = null;
  const lastColon = s.lastIndexOf(":");
  const afterLast = s.slice(lastColon + 1);
  if (afterLast.includes(".")) {
    tail4 = ipv4ToBytes(afterLast);
    if (!tail4) return null;
    s = s.slice(0, lastColon + 1) + "0:0";
  }
  const hasDoubleColon = s.includes("::");
  const halves = s.split("::");
  if (halves.length > 2) return null;
  const parseGroups = (str: string): number[] | null => {
    if (str === "") return [];
    const groups = str.split(":");
    const out: number[] = [];
    for (const g of groups) {
      if (!/^[0-9a-fA-F]{1,4}$/.test(g)) return null;
      const v = parseInt(g, 16);
      out.push((v >> 8) & 0xff, v & 0xff);
    }
    return out;
  };
  const head = parseGroups(halves[0] ?? "");
  const tail = parseGroups(halves[1] ?? "");
  if (head === null || tail === null) return null;
  let bytes: number[];
  if (hasDoubleColon) {
    const missing = 16 - head.length - tail.length;
    if (missing < 0) return null;
    bytes = [...head, ...new Array(missing).fill(0), ...tail];
  } else {
    bytes = [...head];
  }
  if (tail4) bytes = [...bytes.slice(0, 12), ...tail4];
  return bytes.length === 16 ? bytes : null;
}

function classifyIpv4(b: number[]): IpDecision {
  const [a, c] = [b[0]!, b[1]!];
  if (a === 0) return { safe: false, reason: "unspecified/this-network 0.0.0.0/8" };
  if (a === 10) return { safe: false, reason: "private 10.0.0.0/8" };
  if (a === 127) return { safe: false, reason: "loopback 127.0.0.0/8" };
  if (a === 169 && c === 254) return { safe: false, reason: "link-local/metadata 169.254.0.0/16" };
  if (a === 172 && c >= 16 && c <= 31) return { safe: false, reason: "private 172.16.0.0/12" };
  if (a === 192 && c === 168) return { safe: false, reason: "private 192.168.0.0/16" };
  if (a === 100 && c >= 64 && c <= 127) return { safe: false, reason: "CGNAT 100.64.0.0/10" };
  if (a === 192 && c === 0 && b[2] === 0) return { safe: false, reason: "IETF protocol 192.0.0.0/24" };
  if (a === 192 && c === 0 && b[2] === 2) return { safe: false, reason: "TEST-NET-1 192.0.2.0/24" };
  if (a === 198 && (c === 18 || c === 19)) return { safe: false, reason: "benchmark 198.18.0.0/15" };
  if (a === 198 && c === 51 && b[2] === 100) return { safe: false, reason: "TEST-NET-2 198.51.100.0/24" };
  if (a === 203 && c === 0 && b[2] === 113) return { safe: false, reason: "TEST-NET-3 203.0.113.0/24" };
  if (a >= 224) return { safe: false, reason: "multicast/reserved >=224.0.0.0" };
  return { safe: true };
}

function classifyIpv6(b: number[]): IpDecision {
  const isZero = (from: number, to: number) => b.slice(from, to).every((x) => x === 0);
  if (isZero(0, 15) && b[15] === 0) return { safe: false, reason: "unspecified ::" };
  if (isZero(0, 15) && b[15] === 1) return { safe: false, reason: "loopback ::1" };
  if ((b[0]! & 0xfe) === 0xfc) return { safe: false, reason: "ULA fc00::/7" };
  if (b[0] === 0xfe && (b[1]! & 0xc0) === 0x80) return { safe: false, reason: "link-local fe80::/10" };
  if (b[0] === 0xff) return { safe: false, reason: "multicast ff00::/8" };
  if (b[0] === 0x20 && b[1] === 0x01 && b[2] === 0x0d && b[3] === 0xb8) return { safe: false, reason: "documentation 2001:db8::/32" };
  // IPv4-mapped ::ffff:a.b.c.d — re-check the embedded v4.
  if (isZero(0, 10) && b[10] === 0xff && b[11] === 0xff) {
    return classifyIpv4(b.slice(12, 16));
  }
  // IPv4-compatible / NAT64 64:ff9b::/96 → embedded v4.
  if (b[0] === 0x00 && b[1] === 0x64 && b[2] === 0xff && b[3] === 0x9b) {
    return classifyIpv4(b.slice(12, 16));
  }
  return { safe: true };
}

/** Classify a literal IP address string. Anything unparseable is UNSAFE. */
export function classifyIp(ip: string): IpDecision {
  const fam = net.isIP(ip);
  if (fam === 4) {
    const b = ipv4ToBytes(ip);
    return b ? classifyIpv4(b) : { safe: false, reason: "unparseable IPv4" };
  }
  if (fam === 6) {
    const b = ipv6ToBytes(ip);
    return b ? classifyIpv6(b) : { safe: false, reason: "unparseable IPv6" };
  }
  return { safe: false, reason: "not an IP literal" };
}

export function isSafePublicIp(ip: string): boolean {
  return classifyIp(ip).safe;
}
