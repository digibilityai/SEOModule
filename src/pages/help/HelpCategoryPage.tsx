import { useParams } from "react-router-dom";
import { HelpShell } from "./HelpShell";
import { HelpBreadcrumbs } from "./components/HelpBreadcrumbs";
import { ArticleCard } from "./components/ArticleCard";
import { CategoryCard } from "./components/CategoryCard";
import { HelpNotFoundPage } from "./HelpNotFoundPage";
import { getCategoryBySlug, HELP_CATEGORIES } from "@/help/categories";
import { publicArticlesByCategory } from "@/help/content/index";

export function HelpCategoryPage() {
  const { categorySlug } = useParams<{ categorySlug: string }>();
  const category = categorySlug ? getCategoryBySlug(categorySlug) : undefined;

  // Unknown/internal category slugs render the SAME safe not-found state as an
  // unknown article — no distinction is revealed to the requester.
  if (!category) {
    return <HelpNotFoundPage />;
  }

  const articles = publicArticlesByCategory(category.id)
    .slice()
    .sort((a, b) => a.title.localeCompare(b.title)); // deterministic sort

  const related = HELP_CATEGORIES.filter((c) => c.id !== category.id).slice(0, 3);

  return (
    <HelpShell>
      <div className="space-y-8">
        <HelpBreadcrumbs items={[{ label: "Help Center", to: "/help" }, { label: category.title }]} />

        <div className="space-y-2">
          <h1 className="text-2xl font-bold">{category.title}</h1>
          <p className="text-muted-foreground">{category.description}</p>
        </div>

        {articles.length === 0 ? (
          <p className="text-muted-foreground">No articles are published in this category yet.</p>
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {articles.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        )}

        <section className="space-y-3">
          <h2 className="text-lg font-semibold">Related categories</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {related.map((c) => (
              <CategoryCard key={c.id} category={c} articleCount={publicArticlesByCategory(c.id).length} />
            ))}
          </div>
        </section>
      </div>
    </HelpShell>
  );
}
