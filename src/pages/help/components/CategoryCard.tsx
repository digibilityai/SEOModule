import { Link } from "react-router-dom";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { HelpCategory } from "@/help/types";

export function CategoryCard({ category, articleCount }: { category: HelpCategory; articleCount: number }) {
  return (
    <Link
      to={`/help/category/${category.slug}`}
      className="block rounded-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
      <Card className="h-full transition-colors hover:border-primary/50">
        <CardHeader>
          <CardTitle className="text-base">{category.title}</CardTitle>
          <CardDescription>{category.description}</CardDescription>
        </CardHeader>
        <p className="px-6 pb-4 text-xs text-muted-foreground">
          {articleCount} article{articleCount === 1 ? "" : "s"}
        </p>
      </Card>
    </Link>
  );
}
