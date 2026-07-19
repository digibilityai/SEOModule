import type { CompetitorContentSummary } from "@/types";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface CompetitorSummarySectionProps {
  summaries: CompetitorContentSummary[];
}

export function CompetitorSummarySection({ summaries }: CompetitorSummarySectionProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Competitor Content Summary</CardTitle>
        <CardDescription>What's already ranking, so we can do it better.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {summaries.map((summary) => (
          <div key={summary.id} className="space-y-1 rounded-md border border-border p-3 text-sm">
            <p className="font-medium text-foreground">{summary.competitor_title}</p>
            <p className="break-all text-xs text-muted-foreground">{summary.competitor_url}</p>
            <p>
              <span className="font-medium text-foreground">Covered: </span>
              {summary.what_they_covered}
            </p>
            <p>
              <span className="font-medium text-foreground">Missed: </span>
              {summary.what_they_missed}
            </p>
            <p className="text-muted-foreground">
              <span className="font-medium text-foreground">Our opportunity: </span>
              {summary.our_opportunity}
            </p>
            <p className="text-muted-foreground">
              <span className="font-medium text-foreground">Content gap angle: </span>
              {summary.content_gap_angle}
            </p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
