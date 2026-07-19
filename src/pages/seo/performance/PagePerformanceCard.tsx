import { useState } from "react";
import { Link } from "react-router-dom";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";
import type { PagePerformance } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  PAGE_TYPE_LABEL,
  PERFORMANCE_STATUS_LABEL,
  PERFORMANCE_STATUS_VARIANT,
  formatPercentage,
  formatPosition,
  formatSignedNumber,
} from "./performanceLabels";
import { PageDetailPanel } from "./PageDetailPanel";

interface PagePerformanceCardProps {
  page: PagePerformance;
  relatedIssueTitle?: string;
  relatedRecommendationTitle?: string;
}

function MovementIcon({ value }: { value: number }) {
  if (value > 0) return <TrendingUp className="h-3.5 w-3.5" />;
  if (value < 0) return <TrendingDown className="h-3.5 w-3.5" />;
  return <Minus className="h-3.5 w-3.5" />;
}

export function PagePerformanceCard({
  page,
  relatedIssueTitle,
  relatedRecommendationTitle,
}: PagePerformanceCardProps) {
  const [expanded, setExpanded] = useState(false);
  const canDiagnose = page.performance_status === "declining" || page.performance_status === "needs_refresh";

  return (
    <Card>
      <CardHeader className="cursor-pointer select-none space-y-2" onClick={() => setExpanded((e) => !e)}>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h3 className="font-medium text-foreground">{page.page_title}</h3>
            <p className="break-all text-xs text-muted-foreground">{page.page_url}</p>
          </div>
          <Badge variant={PERFORMANCE_STATUS_VARIANT[page.performance_status]}>
            {PERFORMANCE_STATUS_LABEL[page.performance_status]}
          </Badge>
        </div>

        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">{PAGE_TYPE_LABEL[page.page_type]}</Badge>
          <Badge variant="outline">Keyword: {page.primary_keyword}</Badge>
          <Badge variant="outline">Secondary keywords: {page.secondary_keywords.length}</Badge>
        </div>

        <div className="flex flex-wrap gap-4 text-xs text-muted-foreground">
          <span>Clicks: {page.clicks.toLocaleString()}</span>
          <span>Impressions: {page.impressions.toLocaleString()}</span>
          <span>CTR: {formatPercentage(page.ctr)}</span>
          <span>Avg. position: {formatPosition(page.avg_position)}</span>
          <span className="inline-flex items-center gap-1">
            <MovementIcon value={page.ranking_movement} />
            Ranking: {formatSignedNumber(page.ranking_movement)}
          </span>
          <span className="inline-flex items-center gap-1">
            <MovementIcon value={page.traffic_movement_percentage} />
            Traffic: {formatSignedNumber(page.traffic_movement_percentage, "%")}
          </span>
          <span>Updated {new Date(page.updated_at).toLocaleDateString()}</span>
        </div>
      </CardHeader>

      {expanded && (
        <CardContent className="space-y-4 border-t border-border pt-4">
          <PageDetailPanel
            page={page}
            relatedIssueTitle={relatedIssueTitle}
            relatedRecommendationTitle={relatedRecommendationTitle}
          />
          <div className="flex flex-wrap gap-2">
            {canDiagnose && (
              <Button asChild size="sm" onClick={(e) => e.stopPropagation()}>
                <Link to={`/seo/decline-diagnosis?pageId=${page.id}`}>View Diagnosis</Link>
              </Button>
            )}
            <Button variant="outline" size="sm" onClick={() => setExpanded(false)}>
              Collapse
            </Button>
          </div>
        </CardContent>
      )}
    </Card>
  );
}
