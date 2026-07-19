import type { PerformanceSummary, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface PerformanceHeaderProps {
  website: SeoWebsite;
  summary: PerformanceSummary;
}

export function PerformanceHeader({ website, summary }: PerformanceHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{website.name}</CardTitle>
        <CardDescription>{website.website_url}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline">
            {summary.last_updated
              ? `Last updated: ${new Date(summary.last_updated).toLocaleDateString()}`
              : "Not updated yet"}
          </Badge>
          <Badge variant="secondary">Tracked pages: {summary.tracked_pages_count}</Badge>
          <Badge variant="secondary">Tracked keywords: {summary.tracked_keywords_count}</Badge>
        </div>
        <p className="text-xs text-muted-foreground">{summary.data_source_status}</p>
      </CardContent>
    </Card>
  );
}
