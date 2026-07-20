import { HelpShell } from "./HelpShell";
import { HelpSearchBox } from "./components/HelpSearchBox";
import { ArticleCard } from "./components/ArticleCard";
import { CategoryCard } from "./components/CategoryCard";
import { StillNeedHelp } from "./components/StillNeedHelp";
import { HELP_CATEGORIES } from "@/help/categories";
import {
  publicArticles,
  publicArticlesByCategory,
  publicArticlesByIds,
  QUICK_START_ARTICLE_IDS,
  POPULAR_ARTICLE_IDS,
  FEATURED_ARTICLE_IDS,
} from "@/help/content/index";

const POPULAR_SEARCHES = [
  "verify domain ownership",
  "crawl statuses",
  "why is my crawl queued",
  "roles and permissions",
  "is this data real",
];

export function HelpHomePage() {
  const all = publicArticles();
  const quickStart = publicArticlesByIds(QUICK_START_ARTICLE_IDS);
  const popular = publicArticlesByIds(POPULAR_ARTICLE_IDS);
  const featured = publicArticlesByIds(FEATURED_ARTICLE_IDS);
  const learnSeo = publicArticlesByCategory("learn-seo-aeo-geo");
  const useDigibility = [
    ...publicArticlesByCategory("set-up-digibility-seo"),
    ...publicArticlesByCategory("domain-ownership"),
    ...publicArticlesByCategory("website-crawling"),
  ];
  const understandData = publicArticlesByCategory("feature-availability");
  const solveProblem = publicArticlesByCategory("troubleshooting");
  const forYourRole = publicArticlesByCategory("recommendations-approvals");

  return (
    <HelpShell>
      <div className="space-y-12">
        {/* 1. Hero */}
        <section className="space-y-4 text-center sm:text-left">
          <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">How can we help?</h1>
          <p className="max-w-2xl text-muted-foreground sm:mx-0 mx-auto">
            Search articles about setting up Digibility SEO, understanding your results, and
            solving common problems. No account needed to browse.
          </p>
          <div className="flex justify-center sm:justify-start">
            <HelpSearchBox autoFocus />
          </div>
        </section>

        {/* 2. Popular searches */}
        <section aria-label="Popular searches" className="flex flex-wrap gap-2">
          {POPULAR_SEARCHES.map((q) => (
            <a
              key={q}
              href={`/help/search?q=${encodeURIComponent(q)}`}
              className="rounded-full border border-border px-3 py-1 text-sm text-muted-foreground hover:bg-accent hover:text-foreground focus-visible:outline-2"
            >
              {q}
            </a>
          ))}
        </section>

        {/* 3. Quick-start row */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Get started</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {quickStart.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 4. Category index */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Browse by topic</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {HELP_CATEGORIES.map((c) => (
              <CategoryCard key={c.id} category={c} articleCount={publicArticlesByCategory(c.id).length} />
            ))}
          </div>
        </section>

        {/* 5. Learn SEO, AEO & GEO */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Learn SEO, AEO &amp; GEO</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {learnSeo.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 6. Use Digibility */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Use Digibility</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {useDigibility.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 7. Understand your data */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Understand your data</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {understandData.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 8. Solve a problem */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">Solve a problem</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {solveProblem.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 9. For your role */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">For your role</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {forYourRole.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 10. Featured / new */}
        <section className="space-y-4">
          <h2 className="text-xl font-semibold">New &amp; featured</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {featured.map((a) => (
              <ArticleCard key={a.id} article={a} />
            ))}
          </div>
        </section>

        {/* 11. Product-status honesty notice */}
        <section aria-label="About this preview build" className="rounded-lg border border-border bg-muted/40 p-4">
          <h2 className="text-sm font-semibold">About this preview build</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Digibility SEO is currently a test/preview build ({all.length} help articles available).
            Some data you see in the product is seeded demo content, not live analytics. Look for
            "Preview," "Demo data," or "Coming later" labels throughout this Help Center and the
            product.
          </p>
        </section>

        {/* 12. Still need help */}
        <StillNeedHelp />
      </div>
    </HelpShell>
  );
}
