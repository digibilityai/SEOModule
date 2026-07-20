// Search is fully client-side. The query is read from the URL (never
// persisted, never logged) and matched entirely in-browser via help/search.ts.
import { useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import { HelpShell } from "./HelpShell";
import { HelpSearchBox } from "./components/HelpSearchBox";
import { ArticleCard } from "./components/ArticleCard";
import { CategoryCard } from "./components/CategoryCard";
import { StillNeedHelp } from "./components/StillNeedHelp";
import { publicArticles, publicArticlesByIds, publicArticlesByCategory, POPULAR_ARTICLE_IDS } from "@/help/content/index";
import { searchArticles, suggestBroaderTerms } from "@/help/search";
import { HELP_CATEGORIES } from "@/help/categories";

export function HelpSearchPage() {
  const [searchParams] = useSearchParams();
  const query = searchParams.get("q") ?? "";
  const all = publicArticles();

  const results = useMemo(() => (query.trim() ? searchArticles(all, query) : []), [all, query]);
  const popular = publicArticlesByIds(POPULAR_ARTICLE_IDS);
  const broaderCategoryIds = useMemo(() => (query.trim() && results.length === 0 ? suggestBroaderTerms(all) : []), [all, query, results.length]);

  return (
    <HelpShell>
      <div className="space-y-8">
        <div className="space-y-3">
          <h1 className="text-2xl font-bold">Search the Help Center</h1>
          <HelpSearchBox initialQuery={query} autoFocus />
        </div>

        {!query.trim() && (
          <div className="space-y-6">
            <p className="text-muted-foreground">Type a question above, or browse a popular topic:</p>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {popular.map((a) => (
                <ArticleCard key={a.id} article={a} />
              ))}
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {HELP_CATEGORIES.map((c) => (
                <CategoryCard key={c.id} category={c} articleCount={publicArticlesByCategory(c.id).length} />
              ))}
            </div>
          </div>
        )}

        {query.trim() && results.length > 0 && (
          <div className="space-y-4">
            <p aria-live="polite" className="text-sm text-muted-foreground">
              {results.length} result{results.length === 1 ? "" : "s"} for "{query}"
            </p>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {results.map((r) => (
                <ArticleCard key={r.article.id} article={r.article} />
              ))}
            </div>
          </div>
        )}

        {query.trim() && results.length === 0 && (
          <div className="space-y-6">
            <p role="status" className="text-muted-foreground">
              No results for "{query}". Try a different term, or browse a related topic:
            </p>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {broaderCategoryIds
                .map((id) => HELP_CATEGORIES.find((c) => c.id === id))
                .filter((c): c is NonNullable<typeof c> => Boolean(c))
                .map((c) => (
                  <CategoryCard key={c.id} category={c} articleCount={publicArticlesByCategory(c.id).length} />
                ))}
            </div>
            <div className="space-y-3">
              <p className="text-sm font-medium">Popular articles</p>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {popular.map((a) => (
                  <ArticleCard key={a.id} article={a} />
                ))}
              </div>
            </div>
            <StillNeedHelp />
          </div>
        )}
      </div>
    </HelpShell>
  );
}
