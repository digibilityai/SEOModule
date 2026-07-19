import type { SeoIssue, SeoIssueCategory } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const CATEGORY_LABEL: Record<SeoIssueCategory, string> = {
  crawl: "Crawl",
  indexability: "Indexability",
  speed: "Speed",
  mobile: "Mobile",
  schema: "Schema",
  duplicate_content: "Duplicate content",
  broken_links: "Broken links",
  sitemap: "Sitemap",
  robots_txt: "Robots.txt",
  canonical: "Canonical",
  redirects: "Redirects",
};

const CATEGORY_ORDER: SeoIssueCategory[] = [
  "crawl",
  "indexability",
  "speed",
  "mobile",
  "schema",
  "duplicate_content",
  "broken_links",
  "sitemap",
  "robots_txt",
  "canonical",
  "redirects",
];

interface IssueCategorySummaryProps {
  issues: SeoIssue[];
}

export function IssueCategorySummary({ issues }: IssueCategorySummaryProps) {
  const counts = CATEGORY_ORDER.map((category) => ({
    category,
    count: issues.filter((i) => i.category === category).length,
  })).filter((c) => c.count > 0);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Issues by category</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-wrap gap-2">
        {counts.length === 0 && (
          <p className="text-sm text-muted-foreground">No issues found.</p>
        )}
        {counts.map(({ category, count }) => (
          <Badge key={category} variant="outline">
            {CATEGORY_LABEL[category]}: {count}
          </Badge>
        ))}
      </CardContent>
    </Card>
  );
}
