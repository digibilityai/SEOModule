// Digibility SEO Help Center — pure, client-side search (Slice 1).
//
// Guarantees:
//  - no network request; no persistence; no logging of user queries;
//  - only articles with published===true && visibility==="public" are ever
//    considered (enforced here AND in publicArticles(), belt-and-braces);
//  - deterministic ranking with a stable tie-break;
//  - typo tolerance is bounded to short fields (title/aliases/tags), never a
//    full-body fuzzy scan, so it stays cheap and predictable.
import type { HelpArticle } from "./types";
import { expandSynonymPhrase } from "./synonyms";

export interface HelpSearchResult {
  article: HelpArticle;
  score: number;
  /** Short, safe excerpt showing why the article matched (no raw query logging elsewhere). */
  matchReason: string;
}

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

/** Lowercase, diacritic-strip, whitespace-normalize, and remove safe punctuation. */
export function normalizeText(input: string): string {
  return input
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // strip diacritics
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s'-]/gu, " ") // drop punctuation except ' and - (keep words like "on-page")
    .replace(/\s+/g, " ")
    .trim();
}

/** Very small, safe plural-tolerance: strip a single trailing "s" for matching only. */
function singularize(token: string): string {
  if (token.length > 3 && token.endsWith("s") && !token.endsWith("ss")) {
    return token.slice(0, -1);
  }
  return token;
}

export function tokenize(input: string): string[] {
  const normalized = normalizeText(input);
  if (!normalized) return [];
  return normalized.split(" ").filter(Boolean);
}

// ---------------------------------------------------------------------------
// Bounded typo tolerance (Levenshtein with early-exit cap; never used on body text)
// ---------------------------------------------------------------------------

export function boundedLevenshtein(a: string, b: string, maxDistance: number): number {
  if (Math.abs(a.length - b.length) > maxDistance) return maxDistance + 1;
  const prev = new Array(b.length + 1);
  const curr = new Array(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    let rowMin = curr[0];
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
      if (curr[j] < rowMin) rowMin = curr[j];
    }
    if (rowMin > maxDistance) return maxDistance + 1;
    for (let j = 0; j <= b.length; j++) prev[j] = curr[j];
  }
  return prev[b.length];
}

function isFuzzyMatch(queryToken: string, fieldToken: string): boolean {
  if (queryToken.length < 4 || fieldToken.length < 4) return queryToken === fieldToken;
  const maxDist = queryToken.length <= 5 ? 1 : 2;
  return boundedLevenshtein(queryToken, fieldToken, maxDist) <= maxDist;
}

// ---------------------------------------------------------------------------
// Field weights
// ---------------------------------------------------------------------------

const WEIGHTS = {
  title: 10,
  aliases: 8,
  summary: 5,
  tags: 4,
  categoryOrArea: 3,
  body: 1,
};

// Common English words that carry little topical signal for this small,
// domain-specific corpus. Filtered out of the QUERY only (never out of field
// text) so a query like "why is my crawl queued" scores on "crawl"/"queued",
// not on incidental repeats of "is"/"why"/"my" in an unrelated article's title.
const STOPWORDS = new Set([
  "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
  "i", "my", "me", "mine", "you", "your", "it", "its", "this", "that",
  "do", "does", "did", "doing", "to", "of", "in", "on", "for", "with",
  "and", "or", "but", "why", "how", "what", "when", "where", "who",
  "can", "could", "would", "should", "will", "shall", "not", "no",
]);

/** Drops stopwords, but never returns an empty list (an all-stopword query still searches). */
function filterStopwords(tokens: string[]): string[] {
  const filtered = tokens.filter((t) => !STOPWORDS.has(t));
  return filtered.length > 0 ? filtered : tokens;
}

// Per-query-token match strength is capped so an article can't win purely by
// repeating one word many times in a long field (e.g. several aliases that
// each happen to contain "crawl") — distinct topical alignment matters more
// than raw repetition.
const MAX_MATCH_MULTIPLIER = 2;

function fieldScore(queryTokens: string[], fieldTokens: string[], weight: number, allowFuzzy: boolean): number {
  if (fieldTokens.length === 0 || queryTokens.length === 0) return 0;
  let score = 0;
  for (const qt of queryTokens) {
    const qtSing = singularize(qt);
    let matchStrength = 0;
    for (const ft of fieldTokens) {
      const ftSing = singularize(ft);
      if (qt === ft || qtSing === ftSing) {
        matchStrength += 1;
      } else if (allowFuzzy && isFuzzyMatch(qtSing, ftSing)) {
        matchStrength += 0.6; // typo match scores lower than exact
      }
    }
    score += weight * Math.min(matchStrength, MAX_MATCH_MULTIPLIER);
  }
  return score;
}

function bodyText(article: HelpArticle): string {
  return article.body
    .map((block) => {
      switch (block.type) {
        case "paragraph":
        case "callout":
        case "warning":
        case "statusNotice":
        case "expectedResult":
        case "troubleshootingNote":
        case "escalationNote":
          return block.text;
        case "heading":
          return block.text;
        case "steps":
        case "list":
          return block.items.join(" ");
        case "definition":
          return `${block.term} ${block.text}`;
        case "table":
          return [...block.headers, ...block.rows.flat()].join(" ");
        default:
          return "";
      }
    })
    .join(" ");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Only public, published articles may ever be searched. */
export function publicOnly(articles: HelpArticle[]): HelpArticle[] {
  return articles.filter((a) => a.published === true && a.visibility === "public");
}

export function searchArticles(articles: HelpArticle[], rawQuery: string, limit = 20): HelpSearchResult[] {
  const candidates = publicOnly(articles);
  const normalized = normalizeText(rawQuery);
  if (!normalized) return [];

  const expanded = expandSynonymPhrase(normalized);
  const queryTokens = filterStopwords(Array.from(new Set(tokenize(expanded))));

  const scored: HelpSearchResult[] = candidates
    .map((article) => {
      const titleTokens = tokenize(article.title);
      const aliasTokens = tokenize(article.searchAliases.join(" "));
      const summaryTokens = tokenize(article.summary);
      const tagTokens = tokenize(article.tags.join(" "));
      const areaTokens = tokenize(`${article.category} ${article.productArea}`);
      const bodyTokens = tokenize(bodyText(article));

      let score = 0;
      score += fieldScore(queryTokens, titleTokens, WEIGHTS.title, true);
      score += fieldScore(queryTokens, aliasTokens, WEIGHTS.aliases, true);
      score += fieldScore(queryTokens, summaryTokens, WEIGHTS.summary, true);
      score += fieldScore(queryTokens, tagTokens, WEIGHTS.tags, true);
      score += fieldScore(queryTokens, areaTokens, WEIGHTS.categoryOrArea, false);
      score += fieldScore(queryTokens, bodyTokens, WEIGHTS.body, false);

      // Freshness nudge (deterministic, tiny) — more recently reviewed articles
      // break near-ties slightly in their favour.
      score += Math.min(1, new Date(article.lastReviewed).getTime() / 1e13);

      // Priority nudge — P0 content surfaces marginally before P1-P3 on ties.
      const priorityBonus = { P0: 0.5, P1: 0.3, P2: 0.15, P3: 0 }[article.priority];
      score += priorityBonus;

      const matchReason = titleTokens.some((t) => queryTokens.includes(t))
        ? "Matched title"
        : aliasTokens.some((t) => queryTokens.includes(t))
          ? "Matched a related question"
          : summaryTokens.some((t) => queryTokens.includes(t))
            ? "Matched summary"
            : "Matched content";

      return { article, score, matchReason };
    })
    .filter((r) => r.score > 0);

  // Deterministic sort: score desc, then title asc, then id asc (stable tie-break).
  scored.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if (a.article.title !== b.article.title) return a.article.title.localeCompare(b.article.title);
    return a.article.id.localeCompare(b.article.id);
  });

  return scored.slice(0, limit);
}

export function suggestBroaderTerms(articles: HelpArticle[]): string[] {
  const cats = new Set(publicOnly(articles).map((a) => a.category));
  return Array.from(cats).slice(0, 5);
}
