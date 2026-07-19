import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Logger } from "../src/logger.js";
import { loadConfig } from "../src/config.js";
import { parseMode } from "../src/modes.js";
import { ConfigError } from "../src/config.js";
import { SkeletonProcessor } from "../src/processor.js";
import {
  classifyDnsError, txtRecordsMatch, DNS_FAILURES, DnsTimeoutError,
  FixtureDnsTxtResolver, type DnsTxtResolver,
} from "../src/verification/dns.js";
import {
  VerificationGateway, VerificationResultRejected, type ClaimedVerification,
} from "../src/verification/verificationGateway.js";
import { runVerificationOnce } from "../src/verification/runner.js";

// A distinctive secret challenge + raw TXT value used to prove they are NEVER logged.
const TOKEN = "digibility-site-verification=SECRETTOKENabcdef0123456789";
const RAW_TXT_SECRET = "SENSITIVE-RAW-TXT-VALUE-DO-NOT-LOG";

const CLAIM: ClaimedVerification = {
  verificationId: "v-1",
  workspaceId: "ws-1",
  websiteId: "site-1",
  verificationHost: "example.com",
  dnsTxtName: "_digibility-site-verification.example.com",
  expectedChallengeValue: TOKEN,
  leaseToken: "11111111-1111-1111-1111-111111111111",
  leaseExpiresAt: "2026-07-16T00:02:00.000Z",
};

interface Recorded { outcome: string; reason?: string; code?: string; detail?: string }

class FakeGateway {
  claimCalls = 0;
  recorded: Recorded[] = [];
  throwOnResult?: Error;
  private queue: (ClaimedVerification | null)[];
  constructor(...claims: (ClaimedVerification | null)[]) { this.queue = claims.length ? claims : [null]; }
  async claim(): Promise<ClaimedVerification | null> {
    this.claimCalls++;
    return this.queue.length ? (this.queue.shift() as ClaimedVerification | null) : null;
  }
  async recordResult(_c: ClaimedVerification, _w: string, outcome: string, reason?: string, code?: string, detail?: string): Promise<void> {
    this.recorded.push({ outcome, reason, code, detail });
    if (this.throwOnResult) throw this.throwOnResult;
  }
}

function fakeResolver(fn: (host: string) => string[][] | Promise<string[][]>): DnsTxtResolver {
  return { resolveTxt: async (host: string) => fn(host) };
}

function throwingResolver(err: unknown): DnsTxtResolver {
  return { resolveTxt: async () => { throw err; } };
}

function makeDeps(gateway: FakeGateway, resolver: DnsTxtResolver, opts: { level?: "debug" | "error"; stop?: boolean } = {}) {
  return {
    gateway: gateway as unknown as VerificationGateway,
    resolver,
    log: new Logger(opts.level ?? "error", { workerId: "w-test", environment: "test" }),
    workerId: "w-test",
    leaseSeconds: 120,
    timeoutMs: 1000,
    isStopRequested: () => opts.stop === true,
  };
}

/** Capture stdout+stderr written during fn(). */
async function captureLogs(fn: () => Promise<void>): Promise<string> {
  const out: string[] = [];
  const so = process.stdout.write.bind(process.stdout);
  const se = process.stderr.write.bind(process.stderr);
  (process.stdout.write as unknown as (s: string) => boolean) = (s: string) => { out.push(String(s)); return true; };
  (process.stderr.write as unknown as (s: string) => boolean) = (s: string) => { out.push(String(s)); return true; };
  try { await fn(); } finally {
    process.stdout.write = so;
    process.stderr.write = se;
  }
  return out.join("");
}

// ---- pure helpers -----------------------------------------------------------

test("txt match: exact single record matches", () => {
  assert.equal(txtRecordsMatch([[TOKEN]], TOKEN), true);
});

test("#3 multi-string TXT fragments are flattened (joined) then compared", () => {
  assert.equal(txtRecordsMatch([["digibility-site-verification=", "SECRETTOKENabcdef0123456789"]], TOKEN), true);
  assert.equal(txtRecordsMatch([["digibility-site-verification="]], TOKEN), false); // partial != match
});

test("txt match: no substring / case-normalized acceptance", () => {
  assert.equal(txtRecordsMatch([[TOKEN.toUpperCase()]], TOKEN), false);
  assert.equal(txtRecordsMatch([[TOKEN + "extra"]], TOKEN), false);
});

test("classifyDnsError maps resolver codes deterministically", () => {
  assert.equal(classifyDnsError({ code: "ENOTFOUND" }), "not_found");
  assert.equal(classifyDnsError({ code: "ENODATA" }), "not_found");
  assert.equal(classifyDnsError(new DnsTimeoutError()), "timeout");
  assert.equal(classifyDnsError({ code: "ESERVFAIL" }), "temporary");
  assert.equal(classifyDnsError({ code: "EBADRESP" }), "malformed");
  assert.equal(classifyDnsError(new Error("weird")), "internal");
});

// ---- runner outcomes --------------------------------------------------------

test("#1 exact TXT match -> verified", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]])));
  assert.equal(res.outcome, "verified");
  assert.equal(gw.recorded[0]!.outcome, "verified");
  assert.equal(gw.recorded.length, 1);
});

test("#2 multiple TXT records, one exact match -> verified", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [["other=1"], [TOKEN], ["z"]])));
  assert.equal(res.outcome, "verified");
});

test("#3 multi-string record fragments flattened -> verified", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [["digibility-site-verification=", "SECRETTOKENabcdef0123456789"]])));
  assert.equal(res.outcome, "verified");
});

test("#4 TXT records exist but no exact match -> failed(dns_mismatch)", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [["nope"], ["still-nope"]])));
  assert.equal(res.outcome, "failed");
  assert.equal(gw.recorded[0]!.code, DNS_FAILURES.mismatch.code);
  assert.equal(gw.recorded[0]!.reason, DNS_FAILURES.mismatch.reason);
});

test("#5 NXDOMAIN / not found -> failed(dns_not_found) customer-safe", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, throwingResolver(Object.assign(new Error("nx"), { code: "ENOTFOUND" }))));
  assert.equal(res.outcome, "failed");
  assert.equal(gw.recorded[0]!.code, "dns_not_found");
  assert.match(gw.recorded[0]!.reason ?? "", /not found/i);
});

test("#6 timeout -> failed(dns_timeout)", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, throwingResolver(new DnsTimeoutError())));
  assert.equal(res.outcome, "failed");
  assert.equal(gw.recorded[0]!.code, "dns_timeout");
});

test("#7 temporary resolver failure -> failed(dns_temporary)", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, throwingResolver({ code: "ESERVFAIL" })));
  assert.equal(res.outcome, "failed");
  assert.equal(gw.recorded[0]!.code, "dns_temporary");
});

test("#8 unexpected internal error -> safe failed(internal_error), no throw, no secret in detail", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, throwingResolver(new Error("weird internal boom"))));
  assert.equal(res.outcome, "failed");
  assert.equal(gw.recorded[0]!.code, "internal_error");
  assert.equal(gw.recorded[0]!.detail?.includes(TOKEN), false);
});

test("#9 raw challenge value is NEVER logged", async () => {
  const gw = new FakeGateway(CLAIM);
  const logs = await captureLogs(async () => {
    await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]]), { level: "debug" }));
  });
  assert.equal(logs.includes(TOKEN), false);
  assert.equal(logs.includes(CLAIM.leaseToken), false);
});

test("#10 raw TXT response is NEVER logged", async () => {
  const gw = new FakeGateway(CLAIM);
  const logs = await captureLogs(async () => {
    await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[RAW_TXT_SECRET]]), { level: "debug" }));
  });
  assert.equal(logs.includes(RAW_TXT_SECRET), false);
});

test("#11 no available claim -> no_work exit, no result recorded", async () => {
  const gw = new FakeGateway(null);
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]])));
  assert.equal(res.outcome, "no_work");
  assert.equal(gw.recorded.length, 0);
});

test("#12 claim is retrieved through the gateway", async () => {
  const gw = new FakeGateway(CLAIM);
  await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]])));
  assert.equal(gw.claimCalls, 1);
});

test("#13 result is persisted through the gateway result RPC only (exactly once)", async () => {
  const gw = new FakeGateway(CLAIM);
  await runVerificationOnce(makeDeps(gw, fakeResolver(() => [["mismatch"]])));
  assert.equal(gw.recorded.length, 1);
});

test("#14 stale/mismatched claim rejection is handled safely (no throw)", async () => {
  const gw = new FakeGateway(CLAIM);
  gw.throwOnResult = new VerificationResultRejected("Stale or mismatched claim for verification v-1");
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]])));
  assert.equal(res.outcome, "rejected");
});

test("#15 repeated execution is safe/deterministic (verified then no_work)", async () => {
  const gw = new FakeGateway(CLAIM, null);
  const first = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]])));
  const second = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]])));
  assert.equal(first.outcome, "verified");
  assert.equal(second.outcome, "no_work");
});

test("#16 verification module does NOT import the crawl processor / worker / job gateway", () => {
  for (const f of ["runner.ts", "verificationGateway.ts", "dns.ts"]) {
    const src = readFileSync(new URL(`../src/verification/${f}`, import.meta.url), "utf8");
    // Inspect only import statements (comments legitimately name these to explain independence).
    const importLines = src.split("\n").filter((l) => /^\s*import\b/.test(l)).join("\n");
    assert.equal(/processor|SkeletonProcessor|jobGateway|\.\/worker/i.test(importLines), false, `${f} must not import crawl internals`);
  }
});

test("#17 crawl dry-run mode is unchanged", () => {
  assert.equal(parseMode(["--mode=dry-run"]), "dry-run");
  // crawl processor still refuses non-test jobs (behaviour unchanged)
  const proc = new SkeletonProcessor({ testJobPrefix: "PHASE16D-VERIFY-", allowNonTestJobs: false } as never);
  assert.equal(proc.isTestJob({ idempotencyKey: "not-a-test-job" } as never), false);
});

test("#18 crawl one-shot mode is unchanged", () => {
  assert.equal(parseMode(["--mode=one-shot"]), "one-shot");
});

test("#19 gated-poll protection is unchanged (default allowNonTestJobs=false)", () => {
  assert.equal(parseMode(["--mode=poll"]), "poll");
  const cfg = loadConfig({
    SUPABASE_URL: "https://x.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "eyTESTKEY.aa.bb",
  } as NodeJS.ProcessEnv);
  assert.equal(cfg.allowNonTestJobs, false);
  assert.equal(cfg.verificationLeaseSeconds, 120); // additive default
});

test("verify-once is an accepted mode; unknown modes still rejected", () => {
  assert.equal(parseMode(["--mode=verify-once"]), "verify-once");
  assert.throws(() => parseMode(["--mode=bogus"]), ConfigError);
});

test("#20 graceful shutdown during verification abandons the claim (no result recorded)", async () => {
  const gw = new FakeGateway(CLAIM);
  const res = await runVerificationOnce(makeDeps(gw, fakeResolver(() => [[TOKEN]]), { stop: true }));
  assert.equal(res.outcome, "aborted");
  assert.equal(gw.recorded.length, 0);
});

// ---- gateway wiring (fake supabase) ----------------------------------------

test("gateway.claim maps the Step 2B RPC row; recordResult calls the result RPC only", async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const fakeDb = {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      if (fn === "seo_ownership_verification_claim") {
        return {
          data: [{
            verification_id: "v-9", workspace_id: "ws-9", website_id: "site-9",
            verification_host: "acme.test", dns_txt_name: "_digibility-site-verification.acme.test",
            expected_challenge_value: TOKEN, lease_token: "22222222-2222-2222-2222-222222222222",
            lease_expires_at: "2026-07-16T00:02:00.000Z",
          }], error: null,
        };
      }
      return { data: null, error: null };
    },
  };
  const gw = new VerificationGateway(fakeDb as never);
  const claim = await gw.claim("w", 120);
  assert.ok(claim);
  assert.equal(claim!.verificationId, "v-9");
  assert.equal(claim!.dnsTxtName, "_digibility-site-verification.acme.test");
  await gw.recordResult(claim!, "w", "verified");
  // only the two ownership RPCs were called — never a crawl RPC or a table write
  assert.deepEqual(calls.map((c) => c.fn), ["seo_ownership_verification_claim", "seo_ownership_verification_record_result"]);
  assert.equal(calls.every((c) => c.fn.startsWith("seo_ownership_verification_")), true);
});

test("FixtureDnsTxtResolver returns fixture records and NXDOMAINs unknown hosts", async () => {
  const r = new FixtureDnsTxtResolver({ "_digibility-site-verification.example.com": [[TOKEN]] });
  assert.deepEqual(await r.resolveTxt("_digibility-site-verification.example.com"), [[TOKEN]]);
  await assert.rejects(() => r.resolveTxt("unknown.host"), (e: unknown) => (e as { code?: string }).code === "ENOTFOUND");
});
