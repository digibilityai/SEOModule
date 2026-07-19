import type { PriorityFixActionType, TopPriorityFix } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

const ACTION_TYPE_LABEL: Record<PriorityFixActionType, string> = {
  auto_suggest: "Auto Suggest",
  approval_required: "Approval Required",
  manual_support: "Manual Support",
  expert_review: "Expert Review",
  avoid: "Avoid",
};

const ACTION_TYPE_VARIANT: Record<
  PriorityFixActionType,
  "default" | "secondary" | "destructive" | "outline"
> = {
  auto_suggest: "secondary",
  approval_required: "default",
  manual_support: "outline",
  expert_review: "outline",
  avoid: "destructive",
};

interface TopPriorityFixesProps {
  fixes: TopPriorityFix[];
}

export function TopPriorityFixes({ fixes }: TopPriorityFixesProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Top Priority Fixes</CardTitle>
        <CardDescription>The SEO actions that matter most right now, ranked by impact.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {fixes.length === 0 && (
          <p className="text-sm text-muted-foreground">
            No priority fixes yet. Run an audit to generate some.
          </p>
        )}
        {fixes.map((fix) => (
          <div key={fix.id} className="space-y-2 rounded-md border border-border p-4">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <h3 className="font-medium text-foreground">{fix.title}</h3>
              <Badge variant={ACTION_TYPE_VARIANT[fix.action_type]}>
                {ACTION_TYPE_LABEL[fix.action_type]}
              </Badge>
            </div>
            <p className="text-sm text-muted-foreground">{fix.simple_explanation}</p>
            <div className="flex flex-wrap gap-2 text-xs">
              <Badge variant="outline">Impact: {fix.impact}</Badge>
              <Badge variant="outline">Effort: {fix.effort}</Badge>
              <Badge variant="outline">Risk: {fix.risk}</Badge>
              <Badge variant="outline">Confidence: {fix.confidence_percentage}%</Badge>
              <Badge variant="outline">Status: {fix.status.replace("_", " ")}</Badge>
            </div>
            <p className="text-sm font-medium text-foreground">
              Next action: <span className="font-normal">{fix.recommended_next_action}</span>
            </p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
