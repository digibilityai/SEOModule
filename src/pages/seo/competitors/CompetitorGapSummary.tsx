import { Link } from "react-router-dom";
import type { CompetitorGap } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { RELATED_MODULE_LABEL, RELATED_MODULE_ROUTE } from "./competitorLabels";

const PRIORITY_VARIANT: Record<CompetitorGap["priority"], "destructive" | "default" | "secondary"> = {
  high: "destructive",
  medium: "default",
  low: "secondary",
};

const OWNER_LABEL: Record<CompetitorGap["suggested_owner"], string> = {
  client_action: "Client action",
  developer_needed: "Developer needed",
  digibility_expert: "Digibility expert",
  system_suggestion: "System suggestion",
};

interface CompetitorGapSummaryProps {
  gaps: CompetitorGap[];
}

export function CompetitorGapSummary({ gaps }: CompetitorGapSummaryProps) {
  if (gaps.length === 0) {
    return (
      <Card>
        <CardContent className="py-6 text-center text-sm text-muted-foreground">
          No significant gaps found — you're holding your own against tracked competitors right now.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      <h2 className="text-sm font-medium text-muted-foreground">Competitor Gap Summary</h2>
      {gaps.map((gap) => {
        const route = RELATED_MODULE_ROUTE[gap.related_module];
        return (
          <Card key={gap.id}>
            <CardHeader className="space-y-2">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <CardTitle className="text-base">{gap.title}</CardTitle>
                <Badge variant={PRIORITY_VARIANT[gap.priority]}>Priority: {gap.priority}</Badge>
              </div>
              <div className="flex flex-wrap gap-2 text-xs">
                <Badge variant="outline">Owner: {OWNER_LABEL[gap.suggested_owner]}</Badge>
                <Badge variant="outline">{RELATED_MODULE_LABEL[gap.related_module]}</Badge>
              </div>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <div>
                <p className="font-medium text-foreground">Why this matters</p>
                <p className="text-muted-foreground">{gap.why_it_matters}</p>
              </div>
              <div>
                <p className="font-medium text-foreground">Recommended action</p>
                <p className="text-muted-foreground">{gap.recommended_action}</p>
              </div>
              {route && (
                <Button asChild size="sm" variant="outline">
                  <Link to={route}>Open {RELATED_MODULE_LABEL[gap.related_module]}</Link>
                </Button>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
