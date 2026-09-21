import { test } from "node:test";
import assert from "node:assert/strict";
import dns from "node:dns";
import { __testing } from "../src/discovery/safeHttpTransport.js";

const { safeLookup } = __testing;

/**
 * Regression cover for the Node 20+ lookup callback contract.
 *
 * THE DEFECT THESE PIN. Since Node 20, address-family autoselection calls a
 * custom `lookup` with `{ all: true }` and expects an ARRAY back. safeLookup
 * always answered with the single-address shape, so Node read `address` as
 * undefined, raised ERR_INVALID_IP_ADDRESS, and the transport reported an
 * unexplained `network_error`. No host could be fetched at all.
 *
 * DNS is stubbed so these stay deterministic and offline. The genuine
 * end-to-end network proof lives in test/integration/realTransport.test.ts,
 * which is deliberately NOT part of the default suite.
 */
function withStubbedDns<T>(answers: Array<{ address: string; family: number }> | Error, run: () => T): T {
  const original = dns.lookup;
  (dns as unknown as { lookup: unknown }).lookup = (
    _host: string,
    _opts: unknown,
    cb: (e: unknown, a?: unknown) => void,
  ) => {
    if (answers instanceof Error) return queueMicrotask(() => cb(answers));
    queueMicrotask(() => cb(null, answers));
  };
  try {
    return run();
  } finally {
    (dns as unknown as { lookup: unknown }).lookup = original;
  }
}

const PUBLIC_V6 = { address: "2001:4860:4802:32::15", family: 6 };
const PUBLIC_V4 = { address: "216.239.34.21", family: 4 };

test("safeLookup: all:true returns the ARRAY shape Node expects", async () => {
  const result = await withStubbedDns([PUBLIC_V6, PUBLIC_V4], () =>
    new Promise<unknown[]>((resolve) => {
      safeLookup("example.test", { all: true }, ((err: unknown, addresses: unknown) => {
        assert.equal(err, null);
        resolve(addresses as unknown[]);
      }) as never);
    }));
  assert.ok(Array.isArray(result), "all:true must call back with an array");
  // Every entry must be {address, family}: this is exactly what Node reads, and
  // reading `address` off a string is what produced ERR_INVALID_IP_ADDRESS.
  for (const entry of result as Array<{ address: string; family: number }>) {
    assert.equal(typeof entry.address, "string");
    assert.ok(entry.address.length > 0);
    assert.ok(entry.family === 4 || entry.family === 6);
  }
});

test("safeLookup: all:true keeps every safe address, IPv6 and IPv4, in order", async () => {
  const result = await withStubbedDns([PUBLIC_V6, PUBLIC_V4], () =>
    new Promise<Array<{ address: string; family: number }>>((resolve) => {
      safeLookup("example.test", { all: true }, ((_e: unknown, a: unknown) =>
        resolve(a as Array<{ address: string; family: number }>)) as never);
    }));
  assert.deepEqual(result, [PUBLIC_V6, PUBLIC_V4]);
});

test("safeLookup: a single unsafe address fails the WHOLE target closed", async () => {
  // The unsafe entry is last on purpose: a filter-and-continue implementation
  // would happily return the safe one and silently allow the SSRF target.
  for (const unsafe of [
    { address: "127.0.0.1", family: 4 },
    { address: "169.254.169.254", family: 4 },
    { address: "10.0.0.5", family: 4 },
    { address: "::1", family: 6 },
    { address: "::ffff:127.0.0.1", family: 6 },
  ]) {
    for (const opts of [{ all: true }, {}]) {
      const err = await withStubbedDns([PUBLIC_V4, unsafe], () =>
        new Promise<{ code?: string } | null>((resolve) => {
          safeLookup("evil.test", opts, ((e: unknown) => resolve(e as { code?: string } | null)) as never);
        }));
      assert.ok(err, `${unsafe.address} with ${JSON.stringify(opts)} must be rejected`);
      assert.equal((err as { code?: string }).code, "ssrf_blocked");
    }
  }
});

test("safeLookup: without all, the original single-address shape is preserved", async () => {
  const got = await withStubbedDns([PUBLIC_V6, PUBLIC_V4], () =>
    new Promise<{ address: unknown; family: unknown }>((resolve) => {
      safeLookup("example.test", {}, ((_e: unknown, address: unknown, family: unknown) =>
        resolve({ address, family })) as never);
    }));
  // Pins the first validated address, exactly as before the correction.
  assert.equal(got.address, PUBLIC_V6.address);
  assert.equal(got.family, 6);
});

test("safeLookup: an empty answer and a resolver error both fail closed", async () => {
  const empty = await withStubbedDns([], () =>
    new Promise<unknown>((resolve) => {
      safeLookup("example.test", { all: true }, ((e: unknown) => resolve(e)) as never);
    }));
  assert.ok(empty, "an empty DNS answer must be an error, never an empty address list");

  const failed = await withStubbedDns(new Error("SERVFAIL"), () =>
    new Promise<unknown>((resolve) => {
      safeLookup("example.test", { all: true }, ((e: unknown) => resolve(e)) as never);
    }));
  assert.ok(failed, "a resolver error must propagate");
});
