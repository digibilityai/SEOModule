import type { ProgressReport, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const STATUS_LABEL: Record<ProgressReport["status"], string> = {
  not_generated: "Not generated",
  generated: "Generated",
  stale: "Needs refresh",
};

interface ReportHeaderProps {
  website: SeoWebsite;
  report: ProgressReport;
  onGenerate: () => void;
  isGenerating: boolean;
}

export function ReportHeader({ website, report, onGenerate, isGenerating }: ReportHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>{website.name}</CardTitle>
            <CardDescription>{website.website_url}</CardDescription>
          </div>
          <Button onClick={onGenerate} disabled={isGenerating}>
            {isGenerating ? "Generating..." : "Generate / Refresh Report"}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">{report.period_label}</Badge>
          <Badge variant="outline">Status: {STATUS_LABEL[report.status]}</Badge>
          <Badge variant="outline">Last generated: {new Date(report.generated_at).toLocaleDateString()}</Badge>
        </div>
      </CardContent>
    </Card>
  );
}
