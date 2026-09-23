import { describe, expect, it } from "vitest";
import { stripLaunchCodeFromUrl, type LaunchCodeUrlTarget } from "./brainConnectUrl";

interface FakeTarget extends LaunchCodeUrlTarget {
  calls: Array<{ state: unknown; url: string }>;
}

function fakeWindow(href: string, state: unknown = { idx: 0 }): FakeTarget {
  const calls: Array<{ state: unknown; url: string }> = [];
  const target: FakeTarget = {
    calls,
    location: { href },
    history: {
      state,
      replaceState(nextState: unknown, _unused: string, url: string) {
        calls.push({ state: nextState, url });
        target.location.href = new URL(url, href).href;
      },
    },
  };
  return target;
}

describe("stripLaunchCodeFromUrl", () => {
  it("removes launchCode from the visible URL", () => {
    const target = fakeWindow("https://search.digibility.com/seo/auth/brain-connect?launchCode=abc123");

    stripLaunchCodeFromUrl(target);

    expect(target.calls).toHaveLength(1);
    expect(target.calls[0].url).toBe("/seo/auth/brain-connect");
    expect(target.location.href).not.toContain("launchCode");
    expect(target.location.href).not.toContain("abc123");
  });

  it("keeps the path, other query params and the hash", () => {
    const target = fakeWindow(
      "https://search.digibility.com/seo/auth/brain-connect?source=brain&launchCode=abc123&locale=en#step",
    );

    stripLaunchCodeFromUrl(target);

    expect(target.calls[0].url).toBe("/seo/auth/brain-connect?source=brain&locale=en#step");
  });

  it("replaces the current history entry in place, preserving its state", () => {
    const target = fakeWindow("https://search.digibility.com/seo/auth/brain-connect?launchCode=abc123", {
      idx: 7,
    });

    stripLaunchCodeFromUrl(target);

    // `replaceState` (not pushState/assign) is the only thing called: no new
    // history entry, no navigation, no reload.
    expect(target.calls[0].state).toEqual({ idx: 7 });
  });

  it("is a no-op when there is no launchCode, and is safe to call twice", () => {
    const target = fakeWindow("https://search.digibility.com/seo/auth/brain-connect?source=brain");

    stripLaunchCodeFromUrl(target);
    stripLaunchCodeFromUrl(target);

    expect(target.calls).toHaveLength(0);

    const withCode = fakeWindow("https://search.digibility.com/seo/auth/brain-connect?launchCode=abc123");
    stripLaunchCodeFromUrl(withCode);
    stripLaunchCodeFromUrl(withCode);
    expect(withCode.calls).toHaveLength(1);
  });

  it("no-ops without a usable History API or a parseable href", () => {
    expect(() => stripLaunchCodeFromUrl(undefined)).not.toThrow();

    const unparseable = fakeWindow("https://search.digibility.com/seo/auth/brain-connect?launchCode=abc123");
    unparseable.location.href = "not a url";
    stripLaunchCodeFromUrl(unparseable);
    expect(unparseable.calls).toHaveLength(0);
  });
});
