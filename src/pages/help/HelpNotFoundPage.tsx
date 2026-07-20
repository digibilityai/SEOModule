// Safe not-found state. Used for: unknown article slugs, unknown category
// slugs, INTERNAL article slugs, and UNPUBLISHED article slugs — all render
// this exact same page, so a public visitor can never distinguish "doesn't
// exist" from "exists but is internal/unpublished."
import { HelpShell } from "./HelpShell";
import { HelpSearchBox } from "./components/HelpSearchBox";
import { ArticleCard } from "./components/ArticleCard";
import { StillNeedHelp } from "./components/StillNeedHelp";
import { publicArticlesByIds, POPULAR_ARTICLE_IDS } from "@/help/content/index";

export function HelpNotFoundPage() {
  const popular = publicArticlesByIds(POPULAR_ARTICLE_IDS);
  return (
    <HelpShell>
      <div className="space-y-8">
        <div className="space-y-2">
          <h1 className="text-2xl font-bold">We couldn't find that page</h1>
          <p className="text-muted-foreground">
            The article or category you're looking for doesn't exist, or may have moved. Try a
            search or browse popular articles below.
          </p>
        </div>
        <HelpSearchBox autoFocus />
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
    </HelpShell>
  );
}
