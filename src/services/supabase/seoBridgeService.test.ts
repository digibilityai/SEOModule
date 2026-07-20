import { describe, expect, it } from "vitest";
import { parseBridgeRedemption } from "./seoBridgeService";

describe("parseBridgeRedemption", () => {
  it("accepts a valid bridge payload and safe deep link", () => {
    const result = parseBridgeRedemption({
      tokenHash: "a".repeat(64),
      verificationType: "magiclink",
      returnTo: "/seo/audit?tab=issues",
    });
    expect(result.returnTo).toBe("/seo/audit?tab=issues");
    expect(result.verificationType).toBe("magiclink");
  });

  it("falls back when the return path is unsafe", () => {
    const result = parseBridgeRedemption({
      tokenHash: "a".repeat(64),
      verificationType: "magiclink",
      returnTo: "https://evil.example",
    });
    expect(result.returnTo).toBe("/seo/dashboard");
  });

  it("rejects malformed token payloads", () => {
    expect(() =>
      parseBridgeRedemption({
        tokenHash: "short",
        verificationType: "magiclink",
        returnTo: "/seo/dashboard",
      }),
    ).toThrow("invalid response");
  });
});
