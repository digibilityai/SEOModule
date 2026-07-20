// Digibility SEO Help Center — public/typed content model (Slice 1).
//
// PUBLIC BY DEFAULT BOUNDARY: only articles with `published === true` AND
// `visibility === "public"` may appear in the public search index, category
// pages, homepage, or be reachable through a public article route. This file
// defines the shape only; enforcement lives in `publicArticles()` (index.ts)
// and is checked by `validate.ts`.
//
// No article body ever contains raw HTML. Bodies are structured blocks
// rendered by a safe renderer (no `dangerouslySetInnerHTML`).

export type FeatureStatus =
  | "available"
  | "available_on_test"
  | "preview"
  | "demo_data"
  | "mock_only"
  | "coming_later"
  | "internal_only";

export type Visibility = "public" | "internal";

export type ContentType =
  | "concept"
  | "quick_start"
  | "how_to"
  | "workflow"
  | "report_interpretation"
  | "role_guide"
  | "troubleshooting"
  | "faq"
  | "checklist"
  | "glossary"
  | "video"
  | "micro_video"
  | "support_runbook"
  | "product_status_notice";

export type AudienceRole = "owner" | "admin" | "team_member" | "client" | "agency" | "all" | "internal";

export type ArticleLevel = "beginner" | "intermediate" | "advanced";

export type ArticlePriority = "P0" | "P1" | "P2" | "P3";

/** Safe, structured body blocks — never raw HTML. */
export type HelpBodyBlock =
  | { type: "paragraph"; text: string }
  | { type: "heading"; id: string; text: string }
  | { type: "steps"; items: string[] }
  | { type: "list"; items: string[] }
  | { type: "callout"; text: string }
  | { type: "warning"; text: string }
  | { type: "statusNotice"; text: string }
  | { type: "definition"; term: string; text: string }
  | { type: "table"; headers: string[]; rows: string[][] }
  | { type: "relatedLink"; articleSlug: string; label: string }
  | { type: "expectedResult"; text: string }
  | { type: "troubleshootingNote"; text: string }
  | { type: "escalationNote"; text: string };

export interface HelpVideoMeta {
  title: string;
  lengthSeconds: number;
  /** Not populated in Slice 1 — no video assets exist yet. */
  url?: string;
}

export interface HelpArticle {
  id: string;
  slug: string;
  title: string;
  summary: string;
  body: HelpBodyBlock[];
  category: string;
  subcategory?: string;
  contentType: ContentType;
  audienceRoles: AudienceRole[];
  level: ArticleLevel;
  productArea: string;
  featureStatus: FeatureStatus;
  estimatedReadingMinutes: number;
  tags: string[];
  /** Search synonyms / natural-language question phrasings specific to this article. */
  searchAliases: string[];
  relatedArticleIds: string[];
  /** Informational only — the SEO-module routes this article explains. */
  relevantRoutes: string[];
  /** Informational only — e.g. "crawl:queued", "ownership:pending". */
  contextualStates?: string[];
  priority: ArticlePriority;
  /** ISO date (YYYY-MM-DD). */
  lastReviewed: string;
  version: string;
  published: boolean;
  visibility: Visibility;
  supportEscalationType?: string;
  /** True for content describing how search engines / AI systems rank or answer. */
  externalReviewRequired?: boolean;
  video?: HelpVideoMeta;
}

export interface HelpCategory {
  id: string;
  slug: string;
  title: string;
  description: string;
}

export const FEATURE_STATUS_LABEL: Record<FeatureStatus, string> = {
  available: "Available",
  available_on_test: "Available on TEST",
  preview: "Preview",
  demo_data: "Demo data",
  mock_only: "Mock-only",
  coming_later: "Coming later",
  internal_only: "Internal only",
};
