import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PUBLICATION_VERSION, parsePublicationResult, classifyPublishError, publishJobResults,
} from "../src/publishing/publisher.js";
import {
  LeaseLostError, CancellationRequestedError,
  RetryableExecutionError, NonRetryableExecutionError,
} from "../src/errors.js";

// A minimal JobGateway stand-in exposing only publishResults.
function fakeGateway(impl: (v: number) => Promise<Record<string, unknown>>): any {
  return { publishResults: (_j: string, _w: string, _t: string, v: number) => impl(v) };
}

test("publication version is a single stable contract version", () => {
  assert.equal(PUBLICATION_VERSION, 1);
});

test("parse: published result is validated and normalized", () => {
  const out = parsePublicationResult({
    status: "published", pagesEligible: 3, pagesPublished: 3,
    issuesEligible: 5, issuesPublished: 5, auditRunId: "run-1", publicationId: "pub-1",
  });
  assert.equal(out.status, "published");
  assert.equal(out.pagesPublished, 3);
  assert.equal(out.issuesPublished, 5);
  assert.equal(out.auditRunId, "run-1");
});

test("parse: skipped_no_association is a valid generic-crawl outcome", () => {
  const out = parsePublicationResult({ status: "skipped_no_association" });
  assert.equal(out.status, "skipped_no_association");
  assert.equal(out.pagesPublished, 0);
  assert.equal(out.auditRunId, null);
});

test("parse: no_results is a valid outcome", () => {
  const out = parsePublicationResult({ status: "no_results", pagesEligible: 0 });
  assert.equal(out.status, "no_results");
});

test("parse: unknown status is a non-retryable contract error", () => {
  assert.throws(() => parsePublicationResult({ status: "weird" }), NonRetryableExecutionError);
});

test("parse: published cannot claim more written than eligible", () => {
  assert.throws(
    () => parsePublicationResult({ status: "published", pagesEligible: 1, pagesPublished: 9 }),
    NonRetryableExecutionError,
  );
});

test("classify: lease loss maps to LeaseLostError (no terminal write)", () => {
  assert.throws(() => classifyPublishError(new Error("lease lost or reassigned (stale worker)")), LeaseLostError);
});

test("classify: cancellation status maps to CancellationRequestedError", () => {
  assert.throws(
    () => classifyPublishError(new Error("publish not allowed in status cancellation_requested")),
    CancellationRequestedError,
  );
});

test("classify: deterministic contract violations are non-retryable", () => {
  for (const m of [
    "audit run / crawl job workspace or website mismatch",
    "unmapped crawler issue code present; refusing partial publish",
    "audit run already completed by a different source; refusing to publish",
    "associated audit run is not in a publishable state (failed)",
  ]) {
    assert.throws(() => classifyPublishError(new Error(m)), NonRetryableExecutionError, m);
  }
});

test("classify: transient/unknown DB errors are retryable", () => {
  assert.throws(() => classifyPublishError(new Error("connection reset by peer")), RetryableExecutionError);
});

test("publishJobResults: passes the publication version and returns the outcome", async () => {
  let seenVersion = -1;
  const gw = fakeGateway(async (v) => {
    seenVersion = v;
    return { status: "published", pagesEligible: 2, pagesPublished: 2, issuesEligible: 1, issuesPublished: 1, auditRunId: "r", publicationId: "p" };
  });
  const out = await publishJobResults(gw, "job-1", "worker-1", "token-1");
  assert.equal(seenVersion, PUBLICATION_VERSION);
  assert.equal(out.status, "published");
  assert.equal(out.pagesPublished, 2);
});

test("publishJobResults: idempotent replay (same counts) is a success", async () => {
  const reply = { status: "published", pagesEligible: 4, pagesPublished: 4, issuesEligible: 3, issuesPublished: 3, auditRunId: "r", publicationId: "p" };
  const gw = fakeGateway(async () => reply);
  const a = await publishJobResults(gw, "j", "w", "t");
  const b = await publishJobResults(gw, "j", "w", "t");
  assert.deepEqual(a, b);
});

test("publishJobResults: a lease-lost RPC error becomes LeaseLostError", async () => {
  const gw = fakeGateway(async () => { throw new Error("publishResults failed: lease lost or reassigned"); });
  await assert.rejects(publishJobResults(gw, "j", "w", "t"), LeaseLostError);
});

test("publishJobResults: a transient RPC error becomes RetryableExecutionError", async () => {
  const gw = fakeGateway(async () => { throw new Error("publishResults failed: timeout"); });
  await assert.rejects(publishJobResults(gw, "j", "w", "t"), RetryableExecutionError);
});

test("publisher never builds product-table payloads (contract: only version is sent)", async () => {
  // The gateway is called with (jobId, workerId, token, version) ONLY — the
  // worker sends no page/issue arrays, statuses or counts.
  let argCount = -1;
  const gw = { publishResults: (...args: unknown[]) => { argCount = args.length; return Promise.resolve({ status: "skipped_no_association" }); } } as any;
  await publishJobResults(gw, "j", "w", "t");
  assert.equal(argCount, 4);
});
