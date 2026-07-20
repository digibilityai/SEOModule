// Digibility SEO Help Center — content integrity validation (Slice 1).
//
// Pure, deterministic, side-effect-free. Never logs full article bodies or any
// user search query (there is no query input here at all — this validates the
// static corpus only). Invoked from the dev-only `/help/dev/content-check`
// route (see HelpDevContentCheckPage.tsx), mirroring the existing
// `/seo/dev/*` diagnostic-page convention — no new test runner is added.
import type { HelpArticle } from "./types";
import { ALL_ARTICLES, publicArticles, QUICK_START_ARTICLE_IDS, POPULAR_ARTICLE_IDS, FEATURED_ARTICLE_IDS } from "./content/index";
import { HELP_CATEGORIES } from "./categories";
import { searchArticles } from "./search";

export interface ValidationFinding {
  level: "error" | "warning";
  code: string;
  message: string;
}

export interface ValidationReport {
  ok: boolean;
  findings: ValidationFinding[];
  counts: {
    total: number;
    public: number;
    internal: number;
    categories: number;
  };
}

// Content that must never appear in the public corpus (internal identifiers,
// secret-shaped strings, or private project references). Deliberately does
// not include the literal TEST project ref/keys in this file's own source —
// only pattern-based detectors, so this validator itself carries no secret.
const PROHIBITED_PATTERNS: RegExp[] = [
  /\bseo_[a-z_]+\(/i, // internal RPC-call-shaped names
  /\bseo_(crawl|ownership|authority|ai)_[a-z_]+\b/i, // internal table/RPC name prefixes
  /\beyJ[a-zA-Z0-9_-]{10,}\b/, // JWT-looking token
  /\bsk-[a-zA-Z0-9]{10,}\b/, // API-key-shaped token
  /\bsupabase\.co\b/i, // any concrete Supabase project host
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, // UUID (workspace/website/user/job ids)
  // Deliberately underscore-only: matches the internal Postgres/Supabase role
  // name and env-var identifier (e.g. SUPABASE_SERVICE_ROLE_KEY), but NOT the
  // natural-language hyphenated phrase "service-role key" used in legitimate
  // customer-facing security guidance (see contacting-support-safely.ts).
  /service_role/i,
  /\bP1B-[A-Z-]+-TOKEN\b/,
  /\b\d{14}_seo_/, // migration-timestamp-shaped identifiers
];

function articleSearchableText(a: HelpArticle): string {
  const bodyText = a.body
    .map((b) => {
      switch (b.type) {
        case "paragraph": case "callout": case "warning": case "statusNotice":
        case "expectedResult": case "troubleshootingNote": case "escalationNote":
          return b.text;
        case "heading": return b.text;
        case "steps": case "list": return b.items.join(" ");
        case "definition": return `${b.term} ${b.text}`;
        case "table": return [...b.headers, ...b.rows.flat()].join(" ");
        case "relatedLink": return b.label;
        default: return "";
      }
    })
    .join(" ");
  return [a.title, a.summary, bodyText, a.tags.join(" "), a.searchAliases.join(" ")].join(" ");
}

function headingIds(a: HelpArticle): string[] {
  return a.body.filter((b): b is Extract<typeof b, { type: "heading" }> => b.type === "heading").map((b) => b.id);
}

export function validateHelpContent(): ValidationReport {
  const findings: ValidationFinding[] = [];
  const all = ALL_ARTICLES;
  const pub = publicArticles();

  // 1. Unique ids / slugs (across ALL articles, public + internal).
  const idCounts = new Map<string, number>();
  const slugCounts = new Map<string, number>();
  for (const a of all) {
    idCounts.set(a.id, (idCounts.get(a.id) ?? 0) + 1);
    slugCounts.set(a.slug, (slugCounts.get(a.slug) ?? 0) + 1);
  }
  for (const [id, count] of idCounts) if (count > 1) findings.push({ level: "error", code: "duplicate-id", message: `Article id "${id}" is used ${count} times.` });
  for (const [slug, count] of slugCounts) if (count > 1) findings.push({ level: "error", code: "duplicate-slug", message: `Article slug "${slug}" is used ${count} times.` });

  // 2. Category slugs valid; every article's category resolves.
  const categoryIds = new Set(HELP_CATEGORIES.map((c) => c.id));
  for (const a of all) {
    if (!categoryIds.has(a.category)) {
      findings.push({ level: "error", code: "unknown-category", message: `Article "${a.slug}" references unknown category "${a.category}".` });
    }
  }

  // 3. Related article ids resolve (within the full corpus).
  const idSet = new Set(all.map((a) => a.id));
  for (const a of all) {
    for (const relId of a.relatedArticleIds) {
      if (!idSet.has(relId)) {
        findings.push({ level: "error", code: "broken-related-id", message: `Article "${a.slug}" has an unresolved relatedArticleId "${relId}".` });
      }
    }
  }

  // 4. No internal/unpublished article appears in the public index.
  for (const a of pub) {
    if (a.visibility !== "public" || a.published !== true) {
      findings.push({ level: "error", code: "leaked-internal-article", message: `Article "${a.slug}" appears in publicArticles() but is not public+published.` });
    }
  }
  for (const a of all) {
    if (a.visibility === "internal" && pub.some((p) => p.id === a.id)) {
      findings.push({ level: "error", code: "internal-in-public-index", message: `Internal article "${a.slug}" leaked into the public index.` });
    }
  }

  // 5. Required metadata present on all published public articles.
  for (const a of pub) {
    const required: Array<[unknown, string]> = [
      [a.title, "title"], [a.summary, "summary"], [a.slug, "slug"], [a.category, "category"],
      [a.contentType, "contentType"], [a.featureStatus, "featureStatus"], [a.level, "level"],
      [a.lastReviewed, "lastReviewed"], [a.version, "version"],
    ];
    for (const [val, field] of required) {
      if (val === undefined || val === null || val === "") {
        findings.push({ level: "error", code: "missing-metadata", message: `Article "${a.slug}" is missing required field "${field}".` });
      }
    }
    if (a.body.length === 0) findings.push({ level: "error", code: "empty-body", message: `Article "${a.slug}" has an empty body.` });
  }

  // 6. Anchors unique within an article.
  for (const a of all) {
    const ids = headingIds(a);
    const seen = new Set<string>();
    for (const id of ids) {
      if (seen.has(id)) findings.push({ level: "error", code: "duplicate-anchor", message: `Article "${a.slug}" has a duplicate anchor id "${id}".` });
      seen.add(id);
    }
  }

  // 7. Homepage / popular / featured references resolve to public articles.
  const pubIdSet = new Set(pub.map((a) => a.id));
  for (const id of QUICK_START_ARTICLE_IDS) {
    if (!pubIdSet.has(id)) findings.push({ level: "error", code: "broken-quickstart-ref", message: `Quick-start reference "${id}" does not resolve to a public article.` });
  }
  for (const id of POPULAR_ARTICLE_IDS) {
    if (!pubIdSet.has(id)) findings.push({ level: "error", code: "broken-popular-ref", message: `Popular-article reference "${id}" does not resolve to a public article.` });
  }
  for (const id of FEATURED_ARTICLE_IDS) {
    if (!pubIdSet.has(id)) findings.push({ level: "error", code: "broken-featured-ref", message: `Featured-article reference "${id}" does not resolve to a public article.` });
  }

  // 8. Search result ordering is deterministic (run twice, compare).
  const sampleQueries = ["crawl", "verify domain", "roles"];
  for (const q of sampleQueries) {
    const r1 = searchArticles(pub, q).map((r) => r.article.id);
    const r2 = searchArticles(pub, q).map((r) => r.article.id);
    if (JSON.stringify(r1) !== JSON.stringify(r2)) {
      findings.push({ level: "error", code: "nondeterministic-search", message: `Search for "${q}" produced different orderings across two runs.` });
    }
  }

  // 9. No prohibited sensitive/internal token-like content in the PUBLIC corpus.
  for (const a of pub) {
    const text = articleSearchableText(a);
    for (const pattern of PROHIBITED_PATTERNS) {
      if (pattern.test(text)) {
        findings.push({ level: "error", code: "prohibited-content", message: `Public article "${a.slug}" matches a prohibited pattern (${pattern}).` });
      }
    }
  }

  const ok = findings.every((f) => f.level !== "error");
  return {
    ok,
    findings,
    counts: {
      total: all.length,
      public: pub.length,
      internal: all.length - pub.length,
      categories: HELP_CATEGORIES.length,
    },
  };
}
