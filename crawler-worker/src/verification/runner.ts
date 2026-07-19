// Isolated DNS-TXT ownership-verification runner (P1a Step 3).
//
// Flow: claim ONE item (Step 2B claim RPC) → resolve its DNS TXT record →
// EXACT-match the expected challenge → persist verified | failed (Step 2B result
// RPC). No automatic retry / scheduling — the customer re-triggers `recheck`.
//
// INDEPENDENCE: this module imports nothing from the crawl processor / worker /
// job gateway and never processes crawl jobs. It reaches the database only via
// VerificationGateway (Step 2B RPCs) and reaches DNS only via an injected
// DnsTxtResolver (no HTTP → no SSRF surface).
//
// SECRET-SAFE LOGGING: only verificationId / websiteId / outcome are logged.
// The challenge value, the lease token, and the raw TXT response are NEVER
// logged (and the logger additionally redacts token/secret-shaped fields).
import type { BoundLogger, Logger } from "../logger.js";
import { classifyUnknown } from "../errors.js";
import { classifyDnsError, DNS_FAILURES, txtRecordsMatch, type DnsTxtResolver } from "./dns.js";
import {
  VerificationGateway,
  VerificationResultRejected,
  type ClaimedVerification,
} from "./verificationGateway.js";

export type VerificationRunOutcome = "verified" | "failed" | "no_work" | "aborted" | "rejected";

export interface VerificationRunResult {
  outcome: VerificationRunOutcome;
  verificationId?: string;
}

export interface VerificationRunnerDeps {
  gateway: VerificationGateway;
  resolver: DnsTxtResolver;
  log: Logger;
  workerId: string;
  leaseSeconds: number;
  timeoutMs: number;
  /** Cooperative shutdown check; abandon a claim if requested (lease expires). */
  isStopRequested?: () => boolean;
}

/** Cap internal diagnostics so nothing large/sensitive is stored on the claim row. */
function safeInternal(detail: string): string {
  return detail.slice(0, 300);
}

/**
 * Claim + verify at most ONE ownership-verification item, then return. Safe to
 * call repeatedly (each call is one bounded unit of work).
 */
export async function runVerificationOnce(deps: VerificationRunnerDeps): Promise<VerificationRunResult> {
  const { gateway, resolver, log, workerId, leaseSeconds, timeoutMs, isStopRequested } = deps;

  const claim = await gateway.claim(workerId, leaseSeconds);
  if (!claim) {
    log.info("ownership verify: no eligible work", { action: "verify_once", outcome: "no_work" });
    return { outcome: "no_work" };
  }

  // Bind ONLY safe correlation fields (never the token / expected value).
  const jlog: BoundLogger = log.child({
    action: "verify_once",
    verificationId: claim.verificationId,
    websiteId: claim.websiteId,
  });

  // Graceful shutdown before doing any work: abandon the claim; its lease expires
  // and the item becomes re-claimable (no false state written).
  if (isStopRequested?.()) {
    jlog.warn("shutdown requested — abandoning claim (lease will expire)", { outcome: "aborted" });
    return { outcome: "aborted", verificationId: claim.verificationId };
  }

  const decision = await decideOutcome(resolver, claim, timeoutMs);

  if (isStopRequested?.()) {
    jlog.warn("shutdown requested — not recording (lease will expire)", { outcome: "aborted" });
    return { outcome: "aborted", verificationId: claim.verificationId };
  }

  try {
    if (decision.verified) {
      await gateway.recordResult(claim, workerId, "verified");
      jlog.info("ownership verified", { outcome: "verified" });
      return { outcome: "verified", verificationId: claim.verificationId };
    }
    await gateway.recordResult(claim, workerId, "failed", decision.reason, decision.code, decision.internal);
    jlog.info("ownership verification failed", { outcome: "failed", reasonCode: decision.code });
    return { outcome: "failed", verificationId: claim.verificationId };
  } catch (err) {
    if (err instanceof VerificationResultRejected) {
      // Stale/mismatched claim (e.g. lease expired + reclaimed elsewhere). Stop
      // safely; the current owner will finalize. Message is customer-safe.
      jlog.warn("verification result rejected (stale/mismatched claim)", { outcome: "rejected" });
      return { outcome: "rejected", verificationId: claim.verificationId };
    }
    throw err;
  }
}

interface OutcomeDecision {
  verified: boolean;
  reason?: string;
  code?: string;
  internal?: string;
}

/** Resolve + compare, mapping every failure to a deterministic customer-safe reason. */
async function decideOutcome(
  resolver: DnsTxtResolver,
  claim: ClaimedVerification,
  timeoutMs: number,
): Promise<OutcomeDecision> {
  let records: string[][];
  try {
    records = await resolver.resolveTxt(claim.dnsTxtName, timeoutMs);
  } catch (err) {
    const kind = classifyDnsError(err);
    const spec = DNS_FAILURES[kind];
    const internal = kind === "internal"
      ? safeInternal(`unexpected: ${classifyUnknown(err).message}`)
      : safeInternal(`dns ${kind}`);
    return { verified: false, reason: spec.reason, code: spec.code, internal };
  }

  if (!Array.isArray(records)) {
    const spec = DNS_FAILURES.malformed;
    return { verified: false, reason: spec.reason, code: spec.code, internal: "malformed resolver response" };
  }

  if (txtRecordsMatch(records, claim.expectedChallengeValue)) {
    return { verified: true };
  }
  const spec = records.length === 0 ? DNS_FAILURES.not_found : DNS_FAILURES.mismatch;
  return { verified: false, reason: spec.reason, code: spec.code, internal: `no matching TXT (${records.length} record(s))` };
}
