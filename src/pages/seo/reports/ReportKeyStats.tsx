import type { ProgressReport } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";

interface ReportKeyStatsProps {
  report: ProgressReport;
}

export function ReportKeyStats({ report }: ReportKeyStatsProps) {
  const movement = report.overall_score_movement;
  const movementText = movement > 0 ? `+${movement}` : `${movement}`;

  return (
    <Card>
      <CardContent className="flex flex-wrap gap-2 py-4">
        <Badge variant={movement >= 0 ? "default" : "destructive"}>
          Visibility score: {report.overall_score_current} ({movementText})
        </Badge>
        <Badge variant="outline">
          Issues: {report.issues_fixed_count}/{report.issues_found_count} fixed
        </Badge>
        <Badge variant="outline">Pending approvals: {report.pending_approvals_count}</Badge>
        <Badge variant="outline">
          Content: {report.content_pieces_completed}/{report.content_pieces_planned} completed
        </Badge>
        <Badge variant="outline">Pages improving/declining: {report.improving_pages_count}/{report.declining_pages_count}</Badge>
        <Badge variant="outline">Authority opportunities: {report.authority_opportunities_count}</Badge>
        <Badge variant="outline">AI content gaps: {report.ai_content_gaps_count}</Badge>
        <Badge variant="outline">Competitor gaps: {report.competitor_gaps_count}</Badge>
        <Badge variant="outline">
          Roadmap: {report.roadmap_completed_count}/{report.roadmap_total_count} completed
        </Badge>
        <Badge variant="outline">Open support requests: {report.open_support_requests_count}</Badge>
      </CardContent>
    </Card>
  );
}
