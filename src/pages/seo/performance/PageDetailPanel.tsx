import { Link } from "react-router-dom";
import type { PagePerformance } from "@/types";
import { Badge } from "@/components/ui/badge";
import { formatPosition, formatSignedNumber } from "./performanceLabels";

interface PageDetailPanelProps {
  page: PagePerformance;
  relatedIssueTitle?: string;
  relatedRecommendationTitle?: string;
}

export function PageDetailPanel({
  page,
  relatedIssueTitle,
  relatedRecommendationTitle,
}: PageDetailPanelProps) {
  const clicksMovement = page.clicks - page.clicks_previous_period;
  const impressionsMovement = page.impressions - page.impressions_previous_period;
  const ctrMovement = page.ctr - page.previous_ctr;

  return (
    <div className="space-y-4 text-sm">
      <div>
        <p className="font-medium text-foreground">Mapped keywords</p>
        <div className="mt-1 flex flex-wrap gap-1.5">
          <Badge variant="default">{page.primary_keyword}</Badge>
          {page.secondary_keywords.map((k) => (
            <Badge key={k} variant="outline">
              {k}
            </Badge>
          ))}
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <p className="font-medium text-foreground">Position</p>
          <p className="text-muted-foreground">
            Current: {formatPosition(page.avg_position)} · Previous:{" "}
            {formatPosition(page.previous_avg_position)}
          </p>
        </div>
        <div>
          <p className="font-medium text-foreground">Click movement</p>
          <p className="text-muted-foreground">{formatSignedNumber(clicksMovement)} clicks</p>
        </div>
        <div>
          <p className="font-medium text-foreground">Impression movement</p>
          <p className="text-muted-foreground">{formatSignedNumber(impressionsMovement)} impressions</p>
        </div>
        <div>
          <p className="font-medium text-foreground">CTR movement</p>
          <p className="text-muted-foreground">{formatSignedNumber(ctrMovement * 100, "pt")}</p>
        </div>
      </div>

      {page.main_seo_issue && (
        <div>
          <p className="font-medium text-foreground">Main SEO issue</p>
          <p className="text-muted-foreground">{page.main_seo_issue}</p>
        </div>
      )}

      {page.recommended_next_action && (
        <div>
          <p className="font-medium text-foreground">Recommended next action</p>
          <p className="text-muted-foreground">{page.recommended_next_action}</p>
        </div>
      )}

      {(relatedIssueTitle || relatedRecommendationTitle) && (
        <div className="space-y-1 border-t border-border pt-3">
          <p className="font-medium text-foreground">Related items</p>
          {relatedIssueTitle && (
            <p className="text-muted-foreground">
              Audit issue: "{relatedIssueTitle}" —{" "}
              <Link to="/seo/audit" className="underline">
                view in Technical SEO Audit
              </Link>
            </p>
          )}
          {relatedRecommendationTitle && (
            <p className="text-muted-foreground">
              Recommendation: "{relatedRecommendationTitle}" —{" "}
              <Link to="/seo/approvals" className="underline">
                view in Approval Queue
              </Link>
            </p>
          )}
        </div>
      )}
    </div>
  );
}
