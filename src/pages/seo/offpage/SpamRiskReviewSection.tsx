import type { SpamRiskReview } from "@/types";
import { ShieldAlert } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { SPAM_FLAG_LABEL } from "./offPageLabels";

interface SpamRiskReviewSectionProps {
  reviews: SpamRiskReview[];
}

export function SpamRiskReviewSection({ reviews }: SpamRiskReviewSectionProps) {
  if (reviews.length === 0) {
    return (
      <Card>
        <CardContent className="py-6 text-center text-sm text-muted-foreground">
          No risky opportunities detected right now — everything currently listed looks safe to
          consider.
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-destructive/40">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <ShieldAlert className="h-4 w-4 text-destructive" />
          Spam Risk Review
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {reviews.map((review) => (
          <div key={review.opportunity_id} className="rounded-md border border-destructive/30 bg-destructive/5 p-3 text-sm">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-medium text-foreground">{review.opportunity_title}</p>
              <Badge variant="destructive">
                Recommended: {review.recommended_action === "avoid" ? "Avoid" : "Expert review"}
              </Badge>
            </div>
            <div className="mt-1 flex flex-wrap gap-1.5">
              {review.flags.map((flag) => (
                <Badge key={flag} variant="outline">
                  {SPAM_FLAG_LABEL[flag]}
                </Badge>
              ))}
            </div>
            <p className="mt-2 text-muted-foreground">{review.explanation}</p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
