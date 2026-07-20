import type { HelpArticle } from "@/help/types";
import { ArticleCard } from "./ArticleCard";

export function RelatedArticles({ articles }: { articles: HelpArticle[] }) {
  if (articles.length === 0) return null;
  return (
    <section aria-labelledby="related-articles-heading" className="space-y-3">
      <h2 id="related-articles-heading" className="text-lg font-semibold">
        Related articles
      </h2>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {articles.map((a) => (
          <ArticleCard key={a.id} article={a} />
        ))}
      </div>
    </section>
  );
}
