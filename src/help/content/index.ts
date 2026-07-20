import type { HelpArticle } from "../types";
import { START_HERE_ARTICLES } from "./startHere";
import { SETUP_ARTICLES } from "./setup";
import { OWNERSHIP_ARTICLES } from "./ownership";
import { CRAWL_ARTICLES } from "./crawl";
import { WORKFLOW_ARTICLES } from "./workflow";
import { HONESTY_ARTICLES } from "./honesty";
import { ACADEMY_ARTICLES, AI_VISIBILITY_STUB_ARTICLE } from "./academy";
import { DECLINE_ARTICLES } from "./decline";
import { INTERNAL_ARTICLES } from "./internal";

/** Every article, public and internal. Do not render this list directly. */
export const ALL_ARTICLES: HelpArticle[] = [
  ...START_HERE_ARTICLES,
  ...SETUP_ARTICLES,
  ...OWNERSHIP_ARTICLES,
  ...CRAWL_ARTICLES,
  ...WORKFLOW_ARTICLES,
  ...HONESTY_ARTICLES,
  ...ACADEMY_ARTICLES,
  AI_VISIBILITY_STUB_ARTICLE,
  ...DECLINE_ARTICLES,
  ...INTERNAL_ARTICLES,
];

/**
 * THE public/internal visibility boundary. Only articles that are published
 * AND public may ever reach a public route, the public search index, a
 * category page, or the homepage. Every public-facing consumer must go
 * through this function (never `ALL_ARTICLES` directly).
 */
export function publicArticles(): HelpArticle[] {
  return ALL_ARTICLES.filter((a) => a.published === true && a.visibility === "public");
}

export function findPublicArticleBySlug(slug: string): HelpArticle | undefined {
  return publicArticles().find((a) => a.slug === slug);
}

export function publicArticlesByCategory(categoryId: string): HelpArticle[] {
  return publicArticles().filter((a) => a.category === categoryId);
}

export function publicArticlesByIds(ids: string[]): HelpArticle[] {
  const byId = new Map(publicArticles().map((a) => [a.id, a]));
  return ids.map((id) => byId.get(id)).filter((a): a is HelpArticle => Boolean(a));
}

/** Curated P0 quick-start picks for the homepage (ids must resolve — validated). */
export const QUICK_START_ARTICLE_IDS = [
  "getting-started-with-digibility-seo",
  "adding-a-website",
  "verifying-domain-ownership",
  "starting-and-monitoring-a-crawl",
  "understanding-crawl-statuses",
  "the-approval-workflow",
];

/** Curated "popular" picks (static in Slice 1 — no analytics yet). */
export const POPULAR_ARTICLE_IDS = [
  "verifying-domain-ownership",
  "why-a-crawl-may-remain-queued",
  "understanding-crawl-statuses",
  "preview-data-versus-live-data",
  "roles-and-permissions",
];

/** Featured/new for Slice 1 (all articles are new at launch). */
export const FEATURED_ARTICLE_IDS = [
  "getting-started-with-digibility-seo",
  "preview-data-versus-live-data",
  "how-digibility-connects-insights-actions-approvals-reporting",
];
