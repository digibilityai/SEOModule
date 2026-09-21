import { test } from "node:test";
import assert from "node:assert/strict";
import { SafeHttpTransport } from "../../src/discovery/safeHttpTransport.js";

/**
 * GENUINE NETWORK PROOF. Deliberately NOT in the default `npm test` glob
 * (test/*.test.ts): the unit suite must stay deterministic and offline. Run it
 * with `npm run test:integration`, which is what the Stage 2B acceptance uses.
 *
 * This is the check that would have caught the Node 20+ lookup defect. Every
 * unit test used FixtureTransport, so nothing ever exercised safeLookup against
 * a real socket and the transport was broken for every host in the field while
 * the suite stayed green.
 */
const OPTS = {
  purpose: "html" as const,
  maxBytes: 2_000_000,
  timeoutMs: 15_000,
  maxRedirects: 5,
  allowedMimeTypes: ["text/html", "text/plain", "application/xml", "text/xml"],
};

test("SafeHttpTransport performs a real HTTPS request on this Node runtime", async () => {
  const transport = new SafeHttpTransport();
  for (const url of ["https://example.com/", "https://digibility.ai/"]) {
    const result = await transport.fetch(url, OPTS);
    assert.equal(typeof result.status, "number");
    assert.ok(result.status >= 200 && result.status < 400, `${url} returned ${result.status}`);
  }
});

test("SafeHttpTransport still refuses a private address target", async () => {
  const transport = new SafeHttpTransport();
  await assert.rejects(() => transport.fetch("http://127.0.0.1/", OPTS));
});
