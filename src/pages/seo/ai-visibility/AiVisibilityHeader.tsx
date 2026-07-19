import type { AiVisibilityOverview, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface AiVisibilityHeaderProps {
  website: SeoWebsite;
  overview: AiVisibilityOverview;
}

export function AiVisibilityHeader({ website, overview }: AiVisibilityHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{website.name}</CardTitle>
        <CardDescription>{website.website_url}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">AI Discovery / GEO score: {overview.ai_discovery_score}/100</Badge>
          <Badge variant="outline">Brand mentions: {overview.brand_mention_count}</Badge>
          <Badge variant="outline">Competitor mentions: {overview.competitor_mention_count}</Badge>
          <Badge variant="outline">Citation gaps: {overview.citation_gap_count}</Badge>
          <Badge variant="outline">Content gaps: {overview.content_gap_count}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">{overview.prompt_tracking_status}</p>
        <p className="text-xs text-muted-foreground">{overview.data_source_status}</p>
      </CardContent>
    </Card>
  );
}
