import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyIp, isSafePublicIp } from "../src/discovery/ipSafety.js";
import { normalizeUrl, isAllowedOrigin, originFromWebsiteUrl, isNonCrawlableScheme, UrlError } from "../src/discovery/urlSafety.js";
import { parseRobots } from "../src/discovery/robots.js";
import { parseSitemap, SitemapError } from "../src/discovery/sitemap.js";
import { extractSameOriginLinks } from "../src/discovery/htmlLinks.js";
import { DiscoveryEngine, type DiscoveryCounters, type DiscoveredPage, type DiscoveredSitemap } from "../src/discovery/discovery.js";
import { FixtureTransport, type FixtureMap } from "../src/discovery/fixtureTransport.js";
import { budgetsFromConfig } from "../src/discovery/budgets.js";

// ---------- IP / SSRF safety ----------
test("ipSafety: blocks loopback/private/link-local/metadata/mapped, allows public", () => {
  for (const bad of ["127.0.0.1", "10.0.0.5", "192.168.1.1", "172.16.0.1", "169.254.169.254",
                     "100.64.0.1", "0.0.0.0", "224.0.0.1", "::1", "::", "fe80::1", "fc00::1",
                     "::ffff:127.0.0.1", "::ffff:10.0.0.1", "2001:db8::1"]) {
    assert.equal(isSafePublicIp(bad), false, `${bad} should be unsafe`);
  }
  for (const ok of ["1.1.1.1", "93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946", "::ffff:1.1.1.1"]) {
    assert.equal(isSafePublicIp(ok), true, `${ok} should be safe`);
  }
  assert.equal(classifyIp("not-an-ip").safe, false);
});

// ---------- URL safety / normalization ----------
test("urlSafety: scheme/userinfo/port/fragment/control rules", () => {
  assert.throws(() => normalizeUrl("ftp://x.example/"), UrlError);
  assert.throws(() => normalizeUrl("http://user:pass@x.example/"), UrlError);
  assert.throws(() => normalizeUrl("https://x.example:8443/"), UrlError); // non-default port
  assert.throws(() => normalizeUrl("javascript:alert(1)"), UrlError);
  assert.equal(normalizeUrl("https://X.Example.com/a/../b?q=1#frag"), "https://x.example.com/b?q=1");
  assert.equal(normalizeUrl("/rel/path", "https://x.example/base/"), "https://x.example/rel/path");
  assert.equal(normalizeUrl("HTTPS://x.example"), "https://x.example/");
});

test("urlSafety: allowed-origin is exact-host, non-default ports rejected, schemes", () => {
  const origin = originFromWebsiteUrl("https://x.example");
  assert.equal(isAllowedOrigin("https://x.example/a", origin), true);
  assert.equal(isAllowedOrigin("https://www.x.example/a", origin), false); // apex != www
  assert.equal(isAllowedOrigin("https://evil.example/a", origin), false);
  assert.equal(isNonCrawlableScheme("mailto:a@b.com"), true);
  assert.equal(isNonCrawlableScheme("/relative"), false);
});

// ---------- robots ----------
test("robots: allow/disallow precedence, wildcards, $, sitemaps, agent match", () => {
  const txt = [
    "User-agent: *", "Disallow: /private", "Allow: /private/ok", "Sitemap: https://x.example/sitemap.xml",
    "", "User-agent: DigibilitySEO", "Disallow: /nope$", "Allow: /",
  ].join("\n");
  const p = parseRobots(txt, "DigibilitySEO-Crawler/0.1");
  assert.equal(p.isAllowed("/anything"), true);   // our group: Allow /
  assert.equal(p.isAllowed("/nope"), false);       // $-anchored disallow
  assert.equal(p.isAllowed("/nope/child"), true);  // not exactly /nope
  assert.deepEqual(p.sitemaps, ["https://x.example/sitemap.xml"]);
  // star group precedence
  const g = parseRobots("User-agent: *\nDisallow: /private\nAllow: /private/ok", "other");
  assert.equal(g.isAllowed("/private/secret"), false);
  assert.equal(g.isAllowed("/private/ok"), true); // longer allow wins
});

// ---------- sitemap (XXE-safe) ----------
test("sitemap: parses urlset + index, rejects DTD/entities, tolerates malformed", () => {
  const urlset = "<urlset><url><loc>https://x.example/a</loc><lastmod>2026-01-01</lastmod></url><url><loc>https://x.example/b</loc></url></urlset>";
  const p = parseSitemap(urlset);
  assert.equal(p.kind, "urlset");
  assert.deepEqual(p.urls.map(u => u.loc), ["https://x.example/a", "https://x.example/b"]);
  const idx = parseSitemap("<sitemapindex><sitemap><loc>https://x.example/s1.xml</loc></sitemap></sitemapindex>");
  assert.equal(idx.kind, "sitemapindex");
  assert.deepEqual(idx.sitemaps, ["https://x.example/s1.xml"]);
  assert.throws(() => parseSitemap('<!DOCTYPE x [<!ENTITY e "boom">]><urlset></urlset>'), SitemapError);
});

// ---------- html links ----------
test("html: extracts same-origin nav links, skips schemes/cross-origin/fragments, safe base", () => {
  const origin = originFromWebsiteUrl("https://x.example");
  const html = `<base href="https://x.example/base/"><a href="/a">a</a><a href="rel">r</a>
    <a href="https://x.example/c#x">c</a><a href="https://evil.example/e">e</a>
    <a href="mailto:z@x.com">m</a><a href="#frag">f</a><a href="/a">dup</a>`;
  const links = extractSameOriginLinks(html, "https://x.example/page", origin);
  assert.ok(links.includes("https://x.example/a"));
  assert.ok(links.includes("https://x.example/base/rel"));
  assert.ok(links.includes("https://x.example/c"));
  assert.ok(!links.some(l => l.includes("evil.example")));
  assert.ok(!links.some(l => l.includes("mailto")));
  assert.equal(new Set(links).size, links.length); // deduped
});

test("html: an unsafe <base> that widens origin is ignored", () => {
  const origin = originFromWebsiteUrl("https://x.example");
  const html = `<base href="https://evil.example/"><a href="/a">a</a>`;
  const links = extractSameOriginLinks(html, "https://x.example/p", origin);
  assert.deepEqual(links, ["https://x.example/a"]); // resolved against page, not evil base
});

// ---------- discovery engine (fixture transport) ----------
function makeHooks(cancelAfter = Infinity) {
  const pages: DiscoveredPage[] = []; const sitemaps: DiscoveredSitemap[] = [];
  let ticks = 0;
  return {
    pages, sitemaps,
    hooks: {
      checkCancelled: async () => ++ticks > cancelAfter,
      heartbeat: async (_c: DiscoveryCounters) => {},
      onPages: async (p: DiscoveredPage[]) => { pages.push(...p); },
      onSitemaps: async (s: DiscoveredSitemap[]) => { sitemaps.push(...s); },
      now: () => Date.now(),
      sleep: async () => {},
    },
  };
}
const UA = "DigibilitySEO-Crawler/0.1";

test("engine Scenario A: sitemap-led + html discovery completes, no cross-origin", async () => {
  const map: FixtureMap = {
    "https://x.example/robots.txt": { contentType: "text/plain", body: "User-agent: *\nAllow: /\nSitemap: https://x.example/sitemap.xml" },
    "https://x.example/sitemap.xml": { contentType: "application/xml", body: "<urlset><url><loc>https://x.example/a</loc></url></urlset>" },
    "https://x.example/": { contentType: "text/html", body: `<a href="/a">a</a><a href="/b">b</a><a href="https://evil.example/x">e</a>` },
    "https://x.example/a": { contentType: "text/html", body: `<a href="/b">b</a>` },
    "https://x.example/b": { contentType: "text/html", body: `<a href="/a">dup</a>` },
  };
  const { hooks, pages } = makeHooks();
  const eng = new DiscoveryEngine("https://x.example", new FixtureTransport(map), budgetsFromConfig({ per_host_delay_ms: 0 }), hooks, UA);
  const r = await eng.run();
  assert.equal(r.outcome, "completed");
  const fetched = pages.filter(p => p.fetchStatus === "fetched").map(p => p.normalizedUrl).sort();
  assert.deepEqual(fetched, ["https://x.example/", "https://x.example/a", "https://x.example/b"]);
  assert.ok(!pages.some(p => p.normalizedUrl.includes("evil.example"))); // cross-origin never queued
});

test("engine Scenario B: robots blocks a path", async () => {
  const map: FixtureMap = {
    "https://x.example/robots.txt": { contentType: "text/plain", body: "User-agent: *\nDisallow: /secret" },
    "https://x.example/": { contentType: "text/html", body: `<a href="/secret">s</a><a href="/ok">o</a>` },
    "https://x.example/ok": { contentType: "text/html", body: `ok` },
  };
  const { hooks, pages } = makeHooks();
  const eng = new DiscoveryEngine("https://x.example", new FixtureTransport(map), budgetsFromConfig({ per_host_delay_ms: 0, use_sitemap: false }), hooks, UA);
  await eng.run();
  assert.ok(pages.some(p => p.normalizedUrl.endsWith("/secret") && p.fetchStatus === "blocked_robots"));
  assert.ok(pages.some(p => p.normalizedUrl.endsWith("/ok") && p.fetchStatus === "fetched"));
});

test("engine Scenario C: fetch error (ssrf/timeout) is recorded, not crashed", async () => {
  const map: FixtureMap = {
    "https://x.example/robots.txt": { status: 404 },
    "https://x.example/": { error: "ssrf_blocked" },
  };
  const { hooks, pages } = makeHooks();
  const eng = new DiscoveryEngine("https://x.example", new FixtureTransport(map), budgetsFromConfig({ per_host_delay_ms: 0, use_sitemap: false }), hooks, UA);
  const r = await eng.run();
  assert.equal(r.outcome, "failed");
  assert.ok(pages.some(p => p.fetchStatus === "failed" && p.errorCode === "ssrf_blocked"));
});

test("engine Scenario F: page budget is respected", async () => {
  const map: FixtureMap = {
    "https://x.example/robots.txt": { status: 404 },
    "https://x.example/": { contentType: "text/html", body: `<a href="/a">a</a><a href="/b">b</a><a href="/c">c</a>` },
    "https://x.example/a": { contentType: "text/html", body: "a" },
    "https://x.example/b": { contentType: "text/html", body: "b" },
    "https://x.example/c": { contentType: "text/html", body: "c" },
  };
  const { hooks, pages } = makeHooks();
  const eng = new DiscoveryEngine("https://x.example", new FixtureTransport(map), budgetsFromConfig({ per_host_delay_ms: 0, use_sitemap: false, max_pages: 2 }), hooks, UA);
  const r = await eng.run();
  assert.equal(pages.filter(p => p.fetchStatus === "fetched").length, 2);
  assert.equal(r.outcome, "partially_completed");
});

test("engine Scenario E: cancellation stops discovery", async () => {
  const map: FixtureMap = {
    "https://x.example/robots.txt": { status: 404 },
    "https://x.example/": { contentType: "text/html", body: `<a href="/a">a</a>` },
    "https://x.example/a": { contentType: "text/html", body: "a" },
  };
  const { hooks } = makeHooks(0); // cancelled on first check
  const eng = new DiscoveryEngine("https://x.example", new FixtureTransport(map), budgetsFromConfig({ per_host_delay_ms: 0, use_sitemap: false }), hooks, UA);
  await assert.rejects(() => eng.run(), /cancelled during discovery/);
});
