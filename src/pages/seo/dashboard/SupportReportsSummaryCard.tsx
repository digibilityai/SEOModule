import { Link } from "react-router-dom";
import type { ProgressReport, SupportSummary } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface SupportReportsSummaryCardProps {
  supportSummary?: SupportSummary;
  latestReport?: ProgressReport | null;
}

export function SupportReportsSummaryCard({ supportSummary, latestReport }: SupportReportsSummaryCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Support & Reports</CardTitle>
        <CardDescription>Help requests and your latest client-friendly progress report.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Open support requests</span>
          <span className="font-medium text-foreground">{supportSummary?.open_requests_count ?? 0}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Pending expert review</span>
          <span className="font-medium text-foreground">{supportSummary?.pending_expert_review_count ?? 0}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Latest report generated</span>
          <span className="font-medium text-foreground">
            {latestReport ? new Date(latestReport.generated_at).toLocaleDateString() : "Not yet"}
          </span>
        </div>
        <p className="text-xs text-muted-foreground">
          {latestReport ? "Review it for next recommended actions." : "Generate your first progress report."}
        </p>
        <div className="mt-2 flex gap-2">
          <Button asChild variant="outline" size="sm" className="flex-1">
            <Link to="/seo/support">Expert Support</Link>
          </Button>
          <Button asChild variant="outline" size="sm" className="flex-1">
            <Link to="/seo/reports">Reports</Link>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
