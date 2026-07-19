import type { CompetitorMentionSummary } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface CompetitorMentionCardProps {
  summaries: CompetitorMentionSummary[];
}

export function CompetitorMentionCard({ summaries }: CompetitorMentionCardProps) {
  if (summaries.length === 0) {
    return (
      <Card>
        <CardContent className="py-6 text-center text-sm text-muted-foreground">
          No competitors have appeared in tracked AI answers yet.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {summaries.map((s) => (
        <Card key={s.competitor_name}>
          <CardHeader className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <CardTitle className="text-base">{s.competitor_name}</CardTitle>
              <Badge variant="outline">Mentions: {s.mention_count}</Badge>
            </div>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div>
              <p className="font-medium text-foreground">Where they appear</p>
              <p className="text-muted-foreground">{s.where_competitor_appears.join(", ")}</p>
            </div>
            <div>
              <p className="font-medium text-foreground">What they're doing better</p>
              <p className="text-muted-foreground">{s.what_competitor_does_better}</p>
            </div>
            <div>
              <p className="font-medium text-foreground">Digibility recommends</p>
              <p className="text-muted-foreground">{s.recommended_next_step}</p>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
