import { describe, expect, it } from "vitest";
import {
  SEO_DEFAULT_ROUTE,
  SEO_LOGIN_PATH,
  SEO_LOGOUT_PATH,
  buildDigibilityLoginUrl,
  buildDigibilityLogoutCascadeUrl,
  sanitizeLogoutContinueUrl,
  sanitizeReturnPath,
} from "./routeAccess";

describe("sanitizeReturnPath", () => {
  it("preserves safe SEO deep links", () => {
    expect(sanitizeReturnPath("/seo/audit?tab=issues#latest")).toBe(
      "/seo/audit?tab=issues#latest",
    );
  });

  it.each([
    "https://evil.example/seo/dashboard",
    "//evil.example/seo/dashboard",
    "/admin",
    "/seo/../admin",
    "/seo\\dashboard",
    "/seo/login",
    "/seo/auth/bridge",
    "/seo/auth/logout",
  ])("rejects unsafe return path %s", (value) => {
    expect(sanitizeReturnPath(value)).toBeNull();
  });
});

describe("buildDigibilityLoginUrl", () => {
  it("carries only a sanitized SEO return path", () => {
    expect(
      buildDigibilityLoginUrl("/seo/page-performance?range=30d", "https://app.digibility.com/"),
    ).toBe(
      "https://app.digibility.com/login?seoReturnTo=%2Fseo%2Fpage-performance%3Frange%3D30d",
    );
  });

  it("falls back to the SEO dashboard for an unsafe path", () => {
    const url = buildDigibilityLoginUrl("https://evil.example", "https://app.digibility.com");
    expect(url).toContain(encodeURIComponent(SEO_DEFAULT_ROUTE));
    expect(url).not.toContain("evil.example");
  });
});

describe("linked logout helpers", () => {
  it("builds Digibility logout cascade without seoReturnTo", () => {
    const url = buildDigibilityLogoutCascadeUrl("http://localhost:8080");
    expect(url).toBe("http://localhost:8080/logout?source=seo&continue=%2Flogin");
    expect(url).not.toContain("seoReturnTo");
  });

  it("falls back to SEO login when Digibility URL is missing", () => {
    expect(buildDigibilityLogoutCascadeUrl("")).toBe(SEO_LOGIN_PATH);
  });

  it("rejects untrusted logout continue URLs", () => {
    expect(
      sanitizeLogoutContinueUrl("http://localhost:8080/login", ["http://localhost:8080"]),
    ).toBe("http://localhost:8080/login");
    expect(
      sanitizeLogoutContinueUrl("https://evil.example/login", ["http://localhost:8080"]),
    ).toBeNull();
    expect(
      sanitizeLogoutContinueUrl(`http://localhost:8090${SEO_LOGOUT_PATH}`, [
        "http://localhost:8080",
      ]),
    ).toBeNull();
  });
});
