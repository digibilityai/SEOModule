import type { BenchmarkComparison } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { GAP_LEVEL_VARIANT } from "./competitorLabels";

interface BenchmarkComparisonSectionProps {
  comparisons: BenchmarkComparison[];
}

export function BenchmarkComparisonSection({ comparisons }: BenchmarkComparisonSectionProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Benchmark Comparison</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {comparisons.map((c) => (
          <div key={c.dimension} className="rounded-md border border-border p-3 text-sm">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-medium text-foreground">{c.label}</p>
              <Badge variant={GAP_LEVEL_VARIANT[c.gap_level]}>Gap: {c.gap_level}</Badge>
            </div>
            <div className="mt-1 flex flex-wrap gap-4 text-xs text-muted-foreground">
              <span>Your score: {c.our_score}</span>
              <span>Competitor average: {c.competitor_average}</span>
              <span>
                Strongest: {c.strongest_competitor_name} ({c.strongest_competitor_score})
              </span>
            </div>
            <p className="mt-2 text-muted-foreground">{c.explanation}</p>
            <p className="mt-1 text-foreground">{c.recommended_next_step}</p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
