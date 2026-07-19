import type { KeywordPlan } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface KeywordPlanSectionProps {
  plan: KeywordPlan;
}

export function KeywordPlanSection({ plan }: KeywordPlanSectionProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Keyword Plan</CardTitle>
        <CardDescription>{plan.why_it_matters}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">
        <p>
          <span className="font-medium text-foreground">Primary keyword: </span>
          {plan.primary_keyword}
        </p>
        <p>
          <span className="font-medium text-foreground">Secondary keywords: </span>
          {plan.secondary_keywords.join(", ")}
        </p>
        <p>
          <span className="font-medium text-foreground">Semantic keywords: </span>
          {plan.semantic_keywords.join(", ")}
        </p>
        <p>
          <span className="font-medium text-foreground">Question keywords: </span>
          {plan.question_keywords.join(", ")}
        </p>
        <p className="text-muted-foreground">{plan.business_relevance}</p>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">Intent: {plan.intent}</Badge>
          <Badge variant="outline">Difficulty: {plan.difficulty}</Badge>
        </div>
      </CardContent>
    </Card>
  );
}
