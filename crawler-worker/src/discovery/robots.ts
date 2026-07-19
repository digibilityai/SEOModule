// RFC 9309 robots.txt parsing + evaluation. Robots is a CRAWL INSTRUCTION, never
// an authorization mechanism (SSRF/ownership are enforced elsewhere). Longest-match
// wins; on equal specificity, Allow wins. Supports `*` and `$`. `Crawl-delay` is a
// non-standard politeness input only and never lowers the configured minimum delay.

interface Rule { allow: boolean; pattern: string; }
interface Group { agents: string[]; rules: Rule[]; crawlDelay?: number; }

export interface RobotsPolicy {
  isAllowed(path: string): boolean;
  sitemaps: string[];
  crawlDelaySeconds?: number;
}

export const ALLOW_ALL: RobotsPolicy = { isAllowed: () => true, sitemaps: [] };
export const DISALLOW_ALL: RobotsPolicy = { isAllowed: () => false, sitemaps: [] };

function tokenAgent(ua: string): string { return ua.trim().toLowerCase(); }

export function parseRobots(text: string, ourAgent: string): RobotsPolicy {
  const sitemaps: string[] = [];
  const groups: Group[] = [];
  let current: Group | null = null;
  let sawRuleInCurrent = false;

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    if (line === "") continue;
    const idx = line.indexOf(":");
    if (idx < 0) continue;
    const field = line.slice(0, idx).trim().toLowerCase();
    const value = line.slice(idx + 1).trim();
    if (field === "user-agent") {
      if (current && sawRuleInCurrent) { current = null; }
      if (!current) { current = { agents: [], rules: [] }; groups.push(current); sawRuleInCurrent = false; }
      current.agents.push(tokenAgent(value));
    } else if (field === "allow" || field === "disallow") {
      if (!current) { current = { agents: ["*"], rules: [] }; groups.push(current); }
      sawRuleInCurrent = true;
      current.rules.push({ allow: field === "allow", pattern: value });
    } else if (field === "crawl-delay") {
      if (current) { const n = Number(value); if (Number.isFinite(n) && n >= 0) current.crawlDelay = n; }
    } else if (field === "sitemap") {
      sitemaps.push(value);
    }
  }

  const me = ourAgent.toLowerCase();
  // Pick the most specific matching group (longest agent token that is a prefix
  // of our UA), else the '*' group, else allow-all.
  let best: Group | undefined;
  let bestLen = -1;
  for (const g of groups) {
    for (const a of g.agents) {
      if (a === "*") { if (bestLen < 0) { best = g; bestLen = 0; } continue; }
      if (me.includes(a) && a.length > bestLen) { best = g; bestLen = a.length; }
    }
  }
  const rules = best?.rules ?? [];
  const crawlDelay = best?.crawlDelay;

  const isAllowed = (path: string): boolean => {
    // Empty Disallow means allow-all for that group.
    let decision = true;
    let bestMatch = -1;
    for (const r of rules) {
      if (r.pattern === "" && !r.allow) continue; // empty Disallow = no rule
      const len = matchLength(r.pattern, path);
      if (len < 0) continue;
      if (len > bestMatch || (len === bestMatch && r.allow)) {
        bestMatch = len;
        decision = r.allow;
      }
    }
    return decision;
  };
  return { isAllowed, sitemaps, crawlDelaySeconds: crawlDelay };
}

// Returns the match "specificity" (pattern length used) or -1 if no match.
// Supports `*` (any sequence) and `$` (end anchor).
function matchLength(pattern: string, path: string): number {
  const anchored = pattern.endsWith("$");
  const pat = anchored ? pattern.slice(0, -1) : pattern;
  // Build a regex from the pattern, escaping regex metachars except '*'.
  const re = "^" + pat.split("*").map((seg) => seg.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + (anchored ? "$" : "");
  try {
    if (new RegExp(re).test(path)) return pat.length;
  } catch {
    return -1;
  }
  return -1;
}
