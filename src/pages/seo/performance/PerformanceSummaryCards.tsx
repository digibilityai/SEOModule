import type { PerformanceSummary } from "@/types";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatPercentage, formatPosition } from "./performanceLabels";

interface PerformanceSummaryCardsProps {
  summary: PerformanceSummary;
}

export function PerformanceSummaryCards({ summary }: PerformanceSummaryCardsProps) {
  const cards = [
    { label: "Improving pages", value: summary.improving_count },
    { label: "Declining pages", value: summary.declining_count },
    { label: "Pages needing refresh", value: summary.needs_refresh_count },
    { label: "Total clicks", value: summary.total_clicks.toLocaleString() },
    { label: "Total impressions", value: summary.total_impressions.toLocaleString() },
    { label: "Average CTR", value: formatPercentage(summary.average_ctr) },
    { label: "Average position", value: formatPosition(summary.average_position) },
  ];

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {cards.map((card) => (
        <Card key={card.label}>
          <CardHeader className="space-y-2 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{card.label}</CardTitle>
          </CardHeader>
          <CardContent>
            <span className="text-3xl font-semibold text-foreground">{card.value}</span>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
