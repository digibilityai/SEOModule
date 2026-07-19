// Deterministic issue detection. Page-level rules run on one page's facts;
// site-level duplicate rules run after all pages are extracted. No network, no
// lifecycle mutation, no AI. Evidence is bounded + customer-safe.
import crypto from "node:crypto";
import type { PageFacts } from "./pageExtractor.js";
import { ISSUE_RULES, RULESET_VERSION, DEFAULT_THRESHOLDS, type Thresholds, type Severity, type IssueCategory, type IssueScope } from "./issueRegistry.js";
import { comparisonKey } from "./textNormalize.js";

export interface DetectedIssue {
  code: string;
  category: IssueCategory;
  severity: Severity;
  scope: IssueScope;
  ruleVersion: string;
  fingerprint: string;         // idempotency key within (job, code)
  summary: string;             // customer-safe
  evidence: Record<string, unknown>; // bounded, customer-safe
}

export interface PageFetchContext {
  normalizedUrl: string;
  httpStatus?: number;
  redirectCount?: number;
  robotsDecision?: string;
}

function mk(code: string, fingerprint: string, evidence: Record<string, unknown>, summary?: string): DetectedIssue {
  const rule = ISSUE_RULES[code];
  if (!rule) throw new Error(`unknown issue code ${code}`);
  return { code, category: rule.category, severity: rule.severity, scope: rule.scope, ruleVersion: RULESET_VERSION, fingerprint, summary: summary ?? rule.title, evidence };
}

/** Page-level issues for a single extracted page. Fingerprint = the page URL, so
 *  reruns converge (unique (job, code, fingerprint)). */
export function detectPageIssues(facts: PageFacts, ctx: PageFetchContext, t: Thresholds = DEFAULT_THRESHOLDS): DetectedIssue[] {
  const url = ctx.normalizedUrl;
  const out: DetectedIssue[] = [];
  const add = (code: string, evidence: Record<string, unknown> = {}) => out.push(mk(code, url, evidence));

  if (facts.extractionStatus !== "extracted") return out; // parse/decode failures recorded on the snapshot, not as issues here
  if (facts.decodeStatus === "unsupported") add("DECODE_UNSUPPORTED", { declaredCharset: facts.declaredCharset ?? null });
  if ((ctx.redirectCount ?? 0) > t.redirectChainMax) add("REDIRECT_CHAIN_LONG", { redirectCount: ctx.redirectCount });
  if (!facts.effectiveIndex) add("EFFECTIVE_NOINDEX", { metaRobots: facts.metaRobots });
  // conflict: raw contains both a standalone "index" and "noindex"
  const rl = facts.metaRobots.toLowerCase();
  if (/\bnoindex\b/.test(rl) && /(?<!no)\bindex\b/.test(rl)) add("CONFLICTING_ROBOTS", { metaRobots: facts.metaRobots });

  // title
  if (facts.titleCount === 0) add("TITLE_MISSING");
  else {
    if (facts.titleCount > 1) add("TITLE_MULTIPLE", { count: facts.titleCount });
    if (facts.title === "") add("TITLE_EMPTY");
    else {
      if (facts.titleLen < t.titleMin) add("TITLE_TOO_SHORT", { length: facts.titleLen, min: t.titleMin });
      if (facts.titleLen > t.titleMax) add("TITLE_TOO_LONG", { length: facts.titleLen, max: t.titleMax });
    }
  }
  // description
  if (facts.descriptionCount === 0) add("DESCRIPTION_MISSING");
  else {
    if (facts.descriptionCount > 1) add("DESCRIPTION_MULTIPLE", { count: facts.descriptionCount });
    if (facts.description === "") add("DESCRIPTION_EMPTY");
    else {
      if (facts.descriptionLen < t.descMin) add("DESCRIPTION_TOO_SHORT", { length: facts.descriptionLen, min: t.descMin });
      if (facts.descriptionLen > t.descMax) add("DESCRIPTION_TOO_LONG", { length: facts.descriptionLen, max: t.descMax });
    }
  }
  // headings
  if (facts.h1Count === 0) add("H1_MISSING");
  else {
    if (facts.h1Count > 1) add("H1_MULTIPLE", { count: facts.h1Count });
    if (facts.firstH1 === "") add("H1_EMPTY");
  }
  // canonical
  switch (facts.canonicalClass) {
    case "missing": add("CANONICAL_MISSING"); break;
    case "multiple": add("CANONICAL_MULTIPLE", { count: facts.canonicalCount }); break;
    case "invalid": add("CANONICAL_INVALID", { raw: facts.canonicalRaw }); break;
    case "unsafe": add("CANONICAL_UNSAFE", { raw: facts.canonicalRaw }); break;
    case "cross_origin": add("CANONICAL_CROSS_ORIGIN", { resolved: facts.canonicalResolved }); break;
    case "same_origin_other": add("CANONICAL_NON_SELF", { resolved: facts.canonicalResolved }); break;
    case "self": break;
  }
  // document basics
  if (facts.htmlLang === "") add("HTML_LANG_MISSING");
  if (facts.effectiveIndex && facts.wordCount < t.lowContentWords) add("LOW_CONTENT", { wordCount: facts.wordCount, min: t.lowContentWords });
  if (facts.imagesMissingAlt > 0) add("IMAGES_MISSING_ALT", { missing: facts.imagesMissingAlt, total: facts.imageCount });
  return out;
}

export interface SnapshotForDupe {
  normalizedUrl: string;
  title: string;
  description: string;
  contentHash: string;
  hasContent: boolean;   // false for empty/near-empty visible text (excluded from content dupes)
  indexable: boolean;
  decodedOk: boolean;
}

/** Site-level duplicate detection across the job's extracted pages. Only
 *  indexable, reliably-decoded, non-empty values participate. Fingerprint =
 *  hash(code+groupKey) so reruns converge and evidence is bounded. */
export function detectSiteDuplicates(snapshots: SnapshotForDupe[], t: Thresholds = DEFAULT_THRESHOLDS): DetectedIssue[] {
  const eligible = snapshots.filter((s) => s.indexable && s.decodedOk);
  const out: DetectedIssue[] = [];
  const groupBy = (keyFn: (s: SnapshotForDupe) => string | null, code: string, label: string) => {
    const groups = new Map<string, string[]>();
    for (const s of eligible) {
      const k = keyFn(s);
      if (!k) continue;
      (groups.get(k) ?? groups.set(k, []).get(k)!).push(s.normalizedUrl);
    }
    for (const [key, urls] of groups) {
      if (urls.length < 2) continue;
      const fp = crypto.createHash("sha256").update(`${code}:${key}`).digest("hex").slice(0, 40);
      out.push(mk(code, fp, {
        pageCount: urls.length,
        sampleUrls: urls.slice(0, t.duplicateEvidenceMax),
        truncatedEvidence: urls.length > t.duplicateEvidenceMax,
      }, `${label} shared by ${urls.length} pages`));
    }
  };
  groupBy((s) => (s.title ? comparisonKey(s.title) : null), "DUPLICATE_TITLE", "Duplicate title");
  groupBy((s) => (s.description ? comparisonKey(s.description) : null), "DUPLICATE_DESCRIPTION", "Duplicate description");
  groupBy((s) => (s.contentHash && s.hasContent ? s.contentHash : null), "DUPLICATE_CONTENT", "Duplicate content");
  return out;
}
