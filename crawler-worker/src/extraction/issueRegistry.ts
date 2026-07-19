// One explicit, versioned issue-rule registry. No issue-code strings are
// scattered across the worker; no AI judgment; no overall SEO score. Thresholds
// are product GUIDANCE (not search-engine laws) and are versioned with results.

export const RULESET_VERSION = "1.0.0";

export type Severity = "critical" | "error" | "warning" | "info";
export type IssueScope = "page" | "site";
export type IssueCategory =
  | "indexability" | "metadata" | "headings" | "canonical" | "content" | "images" | "duplicate";
export type IssueImpact = "blocks_indexing" | "degrades_quality" | "informational";

export interface IssueRule {
  code: string;
  title: string;
  description: string;      // customer-safe
  category: IssueCategory;
  severity: Severity;
  scope: IssueScope;
  impact: IssueImpact;
  // Documentation: where this maps in the future Phase 1E audit-issue contract.
  futureMap?: string;
}

// Length/content thresholds are guidance (NOT Google requirements). Snapshotted
// with each detection run via RULESET_VERSION. Not caller-controlled in 1D.
export interface Thresholds {
  titleMin: number; titleMax: number;
  descMin: number; descMax: number;
  lowContentWords: number;
  redirectChainMax: number;
  duplicateEvidenceMax: number; // max sample URLs stored per duplicate group
}
export const DEFAULT_THRESHOLDS: Thresholds = {
  titleMin: 15, titleMax: 60,      // common display guidance, not a rule
  descMin: 50, descMax: 160,
  lowContentWords: 100,
  redirectChainMax: 3,
  duplicateEvidenceMax: 10,
};

function r(code: string, title: string, description: string, category: IssueCategory, severity: Severity, scope: IssueScope, impact: IssueImpact, futureMap?: string): IssueRule {
  return { code, title, description, category, severity, scope, impact, futureMap };
}

export const ISSUE_RULES: Record<string, IssueRule> = Object.fromEntries([
  // indexability
  r("REDIRECT_CHAIN_LONG", "Long redirect chain", "This page was reached through several redirects, which wastes crawl budget and can dilute signals.", "indexability", "warning", "page", "degrades_quality"),
  r("EFFECTIVE_NOINDEX", "Page set to noindex", "This page asks search engines not to index it (via meta robots or X-Robots-Tag).", "indexability", "info", "page", "blocks_indexing"),
  r("CONFLICTING_ROBOTS", "Conflicting robots directives", "This page declares both index and noindex directives; the restrictive one applies.", "indexability", "warning", "page", "blocks_indexing"),
  r("DECODE_UNSUPPORTED", "Unsupported character encoding", "The page declared a character encoding we could not fully decode; extracted text may be unreliable.", "content", "warning", "page", "degrades_quality"),
  // title
  r("TITLE_MISSING", "Missing title", "This page has no <title> element.", "metadata", "error", "page", "degrades_quality"),
  r("TITLE_EMPTY", "Empty title", "The page's <title> element is empty.", "metadata", "error", "page", "degrades_quality"),
  r("TITLE_MULTIPLE", "Multiple title elements", "The page has more than one <title> element.", "metadata", "warning", "page", "degrades_quality"),
  r("TITLE_TOO_SHORT", "Title below guidance length", "The title is shorter than the configured guidance.", "metadata", "info", "page", "informational"),
  r("TITLE_TOO_LONG", "Title above guidance length", "The title is longer than the configured guidance and may be truncated in results.", "metadata", "info", "page", "informational"),
  // description
  r("DESCRIPTION_MISSING", "Missing meta description", "This page has no meta description.", "metadata", "warning", "page", "degrades_quality"),
  r("DESCRIPTION_EMPTY", "Empty meta description", "The meta description is empty.", "metadata", "warning", "page", "degrades_quality"),
  r("DESCRIPTION_MULTIPLE", "Multiple meta descriptions", "The page has more than one meta description.", "metadata", "warning", "page", "degrades_quality"),
  r("DESCRIPTION_TOO_SHORT", "Meta description below guidance length", "The meta description is shorter than the configured guidance.", "metadata", "info", "page", "informational"),
  r("DESCRIPTION_TOO_LONG", "Meta description above guidance length", "The meta description is longer than the configured guidance and may be truncated.", "metadata", "info", "page", "informational"),
  // headings
  r("H1_MISSING", "Missing H1", "This page has no <h1> heading.", "headings", "warning", "page", "degrades_quality"),
  r("H1_MULTIPLE", "Multiple H1 elements", "The page has more than one <h1>.", "headings", "info", "page", "informational"),
  r("H1_EMPTY", "Empty H1", "The first <h1> element is empty.", "headings", "warning", "page", "degrades_quality"),
  // canonical
  r("CANONICAL_MISSING", "Missing canonical", "This page has no canonical link element.", "canonical", "info", "page", "informational"),
  r("CANONICAL_MULTIPLE", "Multiple canonical elements", "The page declares more than one canonical link.", "canonical", "warning", "page", "degrades_quality"),
  r("CANONICAL_INVALID", "Invalid canonical URL", "The canonical link is not a valid URL.", "canonical", "warning", "page", "degrades_quality"),
  r("CANONICAL_UNSAFE", "Unsafe canonical URL", "The canonical link uses an unsupported/unsafe scheme.", "canonical", "warning", "page", "degrades_quality"),
  r("CANONICAL_CROSS_ORIGIN", "Cross-origin canonical", "The canonical points to a different host.", "canonical", "info", "page", "informational"),
  r("CANONICAL_NON_SELF", "Canonical points elsewhere on this site", "The canonical points to a different URL on the same site.", "canonical", "info", "page", "informational"),
  // document basics
  r("HTML_LANG_MISSING", "Missing HTML language", "The <html> element has no lang attribute.", "content", "info", "page", "informational"),
  r("LOW_CONTENT", "Low text content", "This indexable page has very little visible text.", "content", "info", "page", "informational"),
  r("IMAGES_MISSING_ALT", "Images missing alt text", "One or more images have no alt text.", "images", "info", "page", "informational"),
  // site-level duplicates
  r("DUPLICATE_TITLE", "Duplicate title across pages", "Two or more indexable pages share the same title.", "duplicate", "warning", "site", "degrades_quality"),
  r("DUPLICATE_DESCRIPTION", "Duplicate meta description across pages", "Two or more indexable pages share the same meta description.", "duplicate", "info", "site", "degrades_quality"),
  r("DUPLICATE_CONTENT", "Duplicate page content", "Two or more indexable pages have identical normalized visible text.", "duplicate", "warning", "site", "degrades_quality"),
].map((rule) => [rule.code, rule]));

export function isKnownIssueCode(code: string): boolean {
  return Object.prototype.hasOwnProperty.call(ISSUE_RULES, code);
}
