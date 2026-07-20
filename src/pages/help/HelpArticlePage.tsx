import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { HelpShell } from "./HelpShell";
import { HelpBreadcrumbs } from "./components/HelpBreadcrumbs";
import { FeatureStatusBadge } from "./components/FeatureStatusBadge";
import { BodyRenderer } from "./components/BodyRenderer";
import { RelatedArticles } from "./components/RelatedArticles";
import { StillNeedHelp } from "./components/StillNeedHelp";
import { HelpNotFoundPage } from "./HelpNotFoundPage";
import { Button } from "@/components/ui/button";
import { getCategoryBySlug, HELP_CATEGORIES } from "@/help/categories";
import { findPublicArticleBySlug, publicArticlesByCategory, publicArticlesByIds } from "@/help/content/index";

export function HelpArticlePage() {
  const { articleSlug } = useParams<{ articleSlug: string }>();
  const [copied, setCopied] = useState(false);

  // Unknown, internal, and unpublished slugs ALL resolve through
  // findPublicArticleBySlug() (which only ever returns public+published
  // articles) — so they all fall through to the same not-found state below.
  const article = articleSlug ? findPublicArticleBySlug(articleSlug) : undefined;

  // Scroll to a #anchor within the article once it renders.
  useEffect(() => {
    if (!article) return;
    const hash = window.location.hash?.replace("#", "");
    if (!hash) return;
    const el = document.getElementById(hash);
    el?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [article]);

  if (!article) {
    return <HelpNotFoundPage />;
  }

  const category = getCategoryBySlug(HELP_CATEGORIES.find((c) => c.id === article.category)?.slug ?? "");
  const related = publicArticlesByIds(article.relatedArticleIds).slice(0, 4);

  const siblingArticles = publicArticlesByCategory(article.category)
    .slice()
    .sort((a, b) => a.title.localeCompare(b.title));
  const idx = siblingArticles.findIndex((a) => a.id === article.id);
  const prev = idx > 0 ? siblingArticles[idx - 1] : undefined;
  const next = idx >= 0 && idx < siblingArticles.length - 1 ? siblingArticles[idx + 1] : undefined;

  const onCopyLink = async () => {
    const url = `${window.location.origin}/help/article/${article.slug}`;
    try {
      await navigator.clipboard?.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard unavailable — link is still visible in the address bar */
    }
  };

  return (
    <HelpShell>
      <article className="space-y-8">
        <HelpBreadcrumbs
          items={[
            { label: "Help Center", to: "/help" },
            ...(category ? [{ label: category.title, to: `/help/category/${category.slug}` }] : []),
            { label: article.title },
          ]}
        />

        <header className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-2xl font-bold">{article.title}</h1>
            <FeatureStatusBadge status={article.featureStatus} />
          </div>
          <p className="text-muted-foreground">{article.summary}</p>
          <dl className="flex flex-wrap gap-x-6 gap-y-1 text-xs text-muted-foreground">
            <div>
              <dt className="inline font-medium">Content type: </dt>
              <dd className="inline">{article.contentType.replace(/_/g, " ")}</dd>
            </div>
            <div>
              <dt className="inline font-medium">Audience: </dt>
              <dd className="inline">{article.audienceRoles.map((r) => r.replace(/_/g, " ")).join(", ")}</dd>
            </div>
            <div>
              <dt className="inline font-medium">Reading time: </dt>
              <dd className="inline">{article.estimatedReadingMinutes} min</dd>
            </div>
            <div>
              <dt className="inline font-medium">Last reviewed: </dt>
              <dd className="inline">{article.lastReviewed}</dd>
            </div>
          </dl>
          {article.externalReviewRequired && (
            <p className="text-xs text-muted-foreground">
              This article is a general educational overview and is flagged for subject-matter
              review before it is treated as final guidance.
            </p>
          )}
          <Button variant="outline" size="sm" onClick={onCopyLink} type="button">
            {copied ? "Link copied" : "Copy link"}
          </Button>
        </header>

        <BodyRenderer blocks={article.body} />

        <nav aria-label="Article navigation" className="flex flex-col gap-2 border-t border-border pt-4 sm:flex-row sm:justify-between">
          {prev ? (
            <Link to={`/help/article/${prev.slug}`} className="text-sm text-muted-foreground hover:text-foreground focus-visible:outline-2">
              ← {prev.title}
            </Link>
          ) : (
            <span />
          )}
          {next && (
            <Link to={`/help/article/${next.slug}`} className="text-sm text-muted-foreground hover:text-foreground focus-visible:outline-2">
              {next.title} →
            </Link>
          )}
        </nav>

        <RelatedArticles articles={related} />

        <StillNeedHelp />
      </article>
    </HelpShell>
  );
}
