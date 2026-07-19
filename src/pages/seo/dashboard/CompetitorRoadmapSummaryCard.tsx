import { Link } from "react-router-dom";
import type { RoadmapSummary } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface CompetitorRoadmapSummaryCardProps {
  competitorGapCount: number;
  roadmapSummary?: RoadmapSummary;
}

export function CompetitorRoadmapSummaryCard({
  competitorGapCount,
  roadmapSummary,
}: CompetitorRoadmapSummaryCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Competitors & Roadmap</CardTitle>
        <CardDescription>Where competitors are ahead, and your 90-day execution plan.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Competitor gaps</span>
          <span className="font-medium text-foreground">{competitorGapCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">High-priority roadmap actions</span>
          <span className="font-medium text-foreground">{roadmapSummary?.high_priority_actions ?? 0}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Completed roadmap actions</span>
          <span className="font-medium text-foreground">{roadmapSummary?.completed_actions ?? 0}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Expert support actions</span>
          <span className="font-medium text-foreground">{roadmapSummary?.expert_support_actions ?? 0}</span>
        </div>
        <div className="mt-2 flex gap-2">
          <Button asChild variant="outline" size="sm" className="flex-1">
            <Link to="/seo/competitor-analysis">Competitors</Link>
          </Button>
          <Button asChild variant="outline" size="sm" className="flex-1">
            <Link to="/seo/roadmap">90-Day Roadmap</Link>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
