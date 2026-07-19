import type { SeoWebsite, SupportSummary } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface SupportSummaryHeaderProps {
  website: SeoWebsite;
  summary: SupportSummary;
  onNewRequest: () => void;
}

export function SupportSummaryHeader({ website, summary, onNewRequest }: SupportSummaryHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>{website.name}</CardTitle>
            <CardDescription>{website.website_url}</CardDescription>
          </div>
          <Button onClick={onNewRequest}>New support request</Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">{summary.support_plan_status}</Badge>
          <Badge variant="outline">Open: {summary.open_requests_count}</Badge>
          <Badge variant="outline">Pending expert review: {summary.pending_expert_review_count}</Badge>
          <Badge variant="outline">Developer needed: {summary.developer_needed_count}</Badge>
          <Badge variant="outline">Completed: {summary.completed_requests_count}</Badge>
        </div>
        <p className="text-xs text-muted-foreground">Need help? Send this to Digibility experts.</p>
      </CardContent>
    </Card>
  );
}
