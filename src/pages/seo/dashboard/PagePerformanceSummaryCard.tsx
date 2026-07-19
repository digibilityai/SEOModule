import { Link } from "react-router-dom";
import type { PerformanceSummary } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface PagePerformanceSummaryCardProps {
  summary: PerformanceSummary;
}

export function PagePerformanceSummaryCard({ summary }: PagePerformanceSummaryCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Page Performance</CardTitle>
        <CardDescription>How your important pages are trending.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Improving</span>
          <span className="font-medium text-foreground">{summary.improving_count}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Declining</span>
          <span className="font-medium text-foreground">{summary.declining_count}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Needs refresh</span>
          <span className="font-medium text-foreground">{summary.needs_refresh_count}</span>
        </div>
        <Button asChild variant="outline" size="sm" className="mt-2 w-full">
          <Link to="/seo/page-performance">Go to Page Performance Tracker</Link>
        </Button>
      </CardContent>
    </Card>
  );
}
