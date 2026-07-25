import { Link } from "react-router-dom";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface RecommendationGenerationPanelProps {
  recommendationCount: number;
  issueCount: number;
  isGenerating: boolean;
  isError: boolean;
  generatePermitted: boolean;
  deniedReason: string;
  onGenerate: () => void;
}

// Recommendation Generation Stage 2 — the manual trigger for the guarded
// seo_recommendation_generate RPC (Stage 1), shown only in Supabase mode on
// a completed audit. Converts real, eligible audit findings (plus the fixed
// on-page template set) into governed recommendations pending Approval
// Queue review — it never publishes anything automatically.
export function RecommendationGenerationPanel({
  recommendationCount,
  issueCount,
  isGenerating,
  isError,
  generatePermitted,
  deniedReason,
  onGenerate,
}: RecommendationGenerationPanelProps) {
  const hasRecommendations = recommendationCount > 0;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Recommendations</CardTitle>
        <CardDescription>
          Generate converts eligible audit findings into governed recommendations for review — it does
          not publish or apply anything automatically. Approved changes are handled separately in the
          Approval Queue.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          {hasRecommendations ? (
            <Badge variant="secondary">
              {recommendationCount} current recommendation{recommendationCount === 1 ? "" : "s"}
            </Badge>
          ) : (
            <Badge variant="outline">No recommendations generated yet</Badge>
          )}
          {hasRecommendations && (
            <Link
              to="/seo/approvals"
              className="text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm"
            >
              Review in Approval Queue
            </Link>
          )}
        </div>

        {issueCount === 0 && (
          <p className="text-xs text-muted-foreground">
            No open technical findings on this audit — generation will still refresh the standard
            on-page recommendations.
          </p>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <Button
            onClick={onGenerate}
            disabled={isGenerating || !generatePermitted}
            title={!generatePermitted ? deniedReason : undefined}
            aria-disabled={isGenerating || !generatePermitted}
          >
            {isGenerating ? "Generating..." : hasRecommendations ? "Refresh Recommendations" : "Generate Recommendations"}
          </Button>
        </div>

        {isError && (
          <p role="status" aria-live="polite" className="text-sm text-destructive">
            Couldn't generate recommendations just now. Please try again.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
