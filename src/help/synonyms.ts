// Digibility SEO Help Center — synonym / natural-language phrase map (Slice 1).
// Phrase-level entries are expanded BEFORE tokenization so multi-word phrases
// ("site scan" -> "crawl") match correctly. Keys and values are normalized
// (lowercase) at lookup time by search.ts — write them in plain lowercase here.
//
// Grounded in DIGIBILITY_SEO_HELP_CENTER_INFORMATION_ARCHITECTURE.md §4 and the
// exact required list from the Slice-1 task.

export const HELP_SYNONYMS: ReadonlyArray<readonly [phrase: string, expandsTo: string]> = [
  // Crawl
  ["site scan", "crawl"],
  ["website scan", "crawl"],
  ["website audit scan", "crawl audit"],
  ["scan stuck", "crawl queued"],
  ["crawl stuck", "crawl queued"],
  ["cannot start crawl", "crawl rejection troubleshooting"],
  ["can't start crawl", "crawl rejection troubleshooting"],
  ["crawel status", "crawl status"],
  ["craw", "crawl"],
  ["crwal", "crawl"],

  // Ownership
  ["verify website", "domain ownership verification"],
  ["verify my website", "domain ownership verification"],
  ["verfy domain", "verify domain ownership"],
  ["domain verification", "domain ownership verification"],
  ["prove website ownership", "domain ownership verification"],
  ["domain pending", "ownership pending"],

  // Metrics
  ["search position", "average position"],
  ["ranking position", "average position"],

  // Decline diagnosis
  ["traffic dropped", "decline diagnosis"],
  ["rankings dropped", "decline diagnosis"],
  ["lost traffic", "decline diagnosis"],
  ["why did my traffic drop", "decline diagnosis"],

  // AEO / GEO / AI visibility
  ["ai search", "geo ai visibility"],
  ["answer engine", "aeo"],
  ["generative search", "geo"],
  ["genrative engine optimisation", "generative engine optimization geo"],
  ["generative engine optimisation", "generative engine optimization geo"],
  ["what is answer engine optimization", "aeo"],
  ["ai search visibility", "geo ai visibility"],

  // Reports / freshness
  ["report not updating", "freshness troubleshooting"],

  // Active website
  ["wrong website data", "active website"],
  ["wrong site data", "active website"],

  // Roles / access
  ["cannot approve", "roles permissions"],
  ["can't approve", "roles permissions"],
  ["i cannot approve", "roles permissions"],
  ["permission denied", "roles permissions"],
  ["permision denied", "roles permissions"],
  ["no access", "entitlement access"],

  // Support
  ["how do i contact support", "contact support"],

  // Honesty / data-real
  ["is this real data", "preview data versus live data"],
  ["is this real", "preview data versus live data"],
];

/**
 * Expands a normalized query string by replacing known phrases with their
 * canonical expansion. Longer phrases are matched first so shorter substrings
 * don't shadow a more specific phrase.
 */
export function expandSynonymPhrase(normalizedQuery: string): string {
  const sorted = [...HELP_SYNONYMS].sort((a, b) => b[0].length - a[0].length);
  let expanded = normalizedQuery;
  for (const [phrase, expansion] of sorted) {
    if (expanded.includes(phrase)) {
      expanded = `${expanded} ${expansion}`;
    }
  }
  return expanded;
}
