import { Link } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { HelpArticle } from "@/help/types";
import { FeatureStatusBadge } from "./FeatureStatusBadge";

export function ArticleCard({ article }: { article: HelpArticle }) {
  return (
    <Link
      to={`/help/article/${article.slug}`}
      className="block rounded-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
      <Card className="h-full transition-colors hover:border-primary/50">
        <CardHeader>
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle className="text-base">{article.title}</CardTitle>
            <FeatureStatusBadge status={article.featureStatus} />
          </div>
          <CardDescription>{article.summary}</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground">
            {article.estimatedReadingMinutes} min read
          </p>
        </CardContent>
      </Card>
    </Link>
  );
}
