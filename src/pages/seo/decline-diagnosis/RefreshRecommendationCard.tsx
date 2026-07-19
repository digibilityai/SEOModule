import { Link } from "react-router-dom";
import type { RefreshRecommendation } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface RefreshRecommendationCardProps {
  recommendation: RefreshRecommendation;
}

export function RefreshRecommendationCard({ recommendation }: RefreshRecommendationCardProps) {
  return (
    <Card className="border-dashed">
      <CardHeader>
        <CardTitle className="text-base">Refresh recommendation</CardTitle>
        <p className="text-sm text-muted-foreground">{recommendation.refresh_angle}</p>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        <div>
          <p className="font-medium text-foreground">What to update</p>
          <ul className="list-inside list-disc text-muted-foreground">
            {recommendation.what_to_update.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        </div>
        <div>
          <p className="font-medium text-foreground">What to add</p>
          <ul className="list-inside list-disc text-muted-foreground">
            {recommendation.what_to_add.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
        </div>
        {recommendation.what_to_remove.length > 0 && (
          <div>
            <p className="font-medium text-foreground">What to remove</p>
            <ul className="list-inside list-disc text-muted-foreground">
              {recommendation.what_to_remove.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </div>
        )}
        {recommendation.suggested_cta_improvement && (
          <div>
            <p className="font-medium text-foreground">Suggested CTA improvement</p>
            <p className="text-muted-foreground">{recommendation.suggested_cta_improvement}</p>
          </div>
        )}
        {recommendation.use_content_studio && (
          <div className="flex items-center gap-2 border-t border-border pt-3">
            <Badge variant="outline">Content Studio</Badge>
            <Button asChild size="sm" variant="outline">
              <Link to="/seo/content-studio">Open Content Studio</Link>
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
