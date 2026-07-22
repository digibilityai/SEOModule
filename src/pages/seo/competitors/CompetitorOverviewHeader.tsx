import type { CompetitorOverview, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface CompetitorOverviewHeaderProps {
  website: SeoWebsite;
  overview: CompetitorOverview;
  onRefresh: () => void;
  isRefreshing: boolean;
  /**
   * When true, the Refresh control is disabled (e.g. real-data mode where
   * benchmark generation is a later stage). Optional — omitted keeps the
   * previous always-enabled behaviour.
   */
  refreshDisabled?: boolean;
  refreshDisabledReason?: string;
}

export function CompetitorOverviewHeader({
  website,
  overview,
  onRefresh,
  isRefreshing,
  refreshDisabled = false,
  refreshDisabledReason,
}: CompetitorOverviewHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>{website.name}</CardTitle>
            <CardDescription>{website.website_url}</CardDescription>
          </div>
          <Button
            onClick={onRefresh}
            disabled={isRefreshing || refreshDisabled}
            title={refreshDisabled ? refreshDisabledReason : undefined}
            variant="outline"
            size="sm"
          >
            {isRefreshing ? "Refreshing..." : "Refresh benchmark data"}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">Competitors tracked: {overview.competitor_count}</Badge>
          <Badge variant="outline">Benchmark score: {overview.benchmark_score}/100</Badge>
          <Badge variant="outline">
            {overview.last_updated
              ? `Last updated: ${new Date(overview.last_updated).toLocaleDateString()}`
              : "Not updated yet"}
          </Badge>
        </div>
        <p className="text-xs text-muted-foreground">{overview.data_source_status}</p>
      </CardContent>
    </Card>
  );
}
