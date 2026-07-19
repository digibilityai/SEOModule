import type { RoadmapSummary, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface RoadmapSummaryHeaderProps {
  website: SeoWebsite;
  summary: RoadmapSummary;
  onGenerate: () => void;
  isGenerating: boolean;
}

export function RoadmapSummaryHeader({
  website,
  summary,
  onGenerate,
  isGenerating,
}: RoadmapSummaryHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>{website.name}</CardTitle>
            <CardDescription>{website.website_url}</CardDescription>
          </div>
          <Button onClick={onGenerate} disabled={isGenerating}>
            {isGenerating ? "Generating..." : "Generate / Refresh 90-Day Roadmap"}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">Total actions: {summary.total_actions}</Badge>
          <Badge variant="outline">Completed: {summary.completed_actions}</Badge>
          <Badge variant="outline">Pending: {summary.pending_actions}</Badge>
          <Badge variant="outline">High priority: {summary.high_priority_actions}</Badge>
          <Badge variant="outline">Expert support: {summary.expert_support_actions}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">{summary.health_summary}</p>
      </CardContent>
    </Card>
  );
}
