import { Link } from "react-router-dom";
import type { AuthorityOverview, AiVisibilityOverview } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface AuthorityAiVisibilitySummaryCardProps {
  authorityOverview?: AuthorityOverview;
  aiVisibilityOverview?: AiVisibilityOverview;
}

export function AuthorityAiVisibilitySummaryCard({
  authorityOverview,
  aiVisibilityOverview,
}: AuthorityAiVisibilitySummaryCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Authority & AI Visibility</CardTitle>
        <CardDescription>Safe opportunities to review, and how AI tools currently see you.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Authority opportunities</span>
          <span className="font-medium text-foreground">{authorityOverview?.opportunity_count ?? 0}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Needs risk review</span>
          <span className="font-medium text-foreground">{authorityOverview?.high_risk_count ?? 0}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">AI visibility gaps</span>
          <span className="font-medium text-foreground">
            {(aiVisibilityOverview?.citation_gap_count ?? 0) + (aiVisibilityOverview?.content_gap_count ?? 0)}
          </span>
        </div>
        <div className="mt-2 flex gap-2">
          <Button asChild variant="outline" size="sm" className="flex-1">
            <Link to="/seo/off-page">Authority Builder</Link>
          </Button>
          <Button asChild variant="outline" size="sm" className="flex-1">
            <Link to="/seo/ai-visibility">AI Visibility</Link>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
