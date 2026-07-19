import type { VisibilityScoreCard, VisibilityScoreLabel } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const LABEL_TEXT: Record<VisibilityScoreLabel, string> = {
  good: "Good",
  needs_attention: "Needs Attention",
  critical: "Critical",
};

const LABEL_VARIANT: Record<VisibilityScoreLabel, "default" | "secondary" | "destructive"> = {
  good: "default",
  needs_attention: "secondary",
  critical: "destructive",
};

interface VisibilityScoreCardsProps {
  cards: VisibilityScoreCard[];
}

export function VisibilityScoreCards({ cards }: VisibilityScoreCardsProps) {
  if (cards.length === 0) {
    return (
      <Card>
        <CardContent className="py-6 text-sm text-muted-foreground">
          No audit yet, so visibility scores aren't available. Run your first audit to see them
          here.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
      {cards.map((card) => (
        <Card key={card.key}>
          <CardHeader className="space-y-2 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              {card.label}
            </CardTitle>
            <div className="flex items-baseline gap-2">
              <span className="text-3xl font-semibold text-foreground">{card.score}</span>
              <span className="text-sm text-muted-foreground">/100</span>
            </div>
            <Badge variant={LABEL_VARIANT[card.status_label]}>{LABEL_TEXT[card.status_label]}</Badge>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">{card.explanation}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
