import type { SeoIssue, SeverityLevel } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const SEVERITY_ORDER: SeverityLevel[] = ["critical", "high", "medium", "low"];

const SEVERITY_VARIANT: Record<SeverityLevel, "destructive" | "default" | "secondary" | "outline"> = {
  critical: "destructive",
  high: "default",
  medium: "secondary",
  low: "outline",
};

interface IssueSeveritySummaryProps {
  issues: SeoIssue[];
}

export function IssueSeveritySummary({ issues }: IssueSeveritySummaryProps) {
  const counts = SEVERITY_ORDER.map((severity) => ({
    severity,
    count: issues.filter((i) => i.severity === severity).length,
  }));

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Issues by severity</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-wrap gap-2">
        {counts.map(({ severity, count }) => (
          <Badge key={severity} variant={SEVERITY_VARIANT[severity]}>
            {severity}: {count}
          </Badge>
        ))}
      </CardContent>
    </Card>
  );
}
