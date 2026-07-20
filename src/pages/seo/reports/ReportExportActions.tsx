import { useMutation } from "@tanstack/react-query";
import type { ReportPeriodKey, SeoWebsite } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { fetchReportForExport } from "@/services/reportService";
import { downloadReportPdf } from "./reportPdf";

interface ReportExportActionsProps {
  website: SeoWebsite;
  period: ReportPeriodKey;
}

// Reports Stage 3 — PDF export. Download PDF is enabled; it fetches the
// already-persisted report through the read-only role-gated export path
// (owner/admin/team_member only) and renders the PDF client-side — it never
// regenerates. CSV / email / share remain disabled ("coming soon").
export function ReportExportActions({ website, period }: ReportExportActionsProps) {
  const download = useMutation({
    mutationFn: async () => {
      const report = await fetchReportForExport(website.id, period);
      if (!report) {
        throw new Error("No saved report is available to export for this period.");
      }
      downloadReportPdf(report, website);
    },
  });

  return (
    <Card>
      <CardContent className="flex flex-col gap-2 py-4">
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={() => download.mutate()} disabled={download.isPending}>
            {download.isPending ? "Preparing PDF..." : "Download PDF"}
          </Button>
          <Button variant="outline" size="sm" disabled title="Coming soon">
            Export CSV — coming soon
          </Button>
          <Button variant="outline" size="sm" disabled title="Coming soon">
            Share with client — coming soon
          </Button>
          <Button variant="outline" size="sm" disabled title="Coming soon">
            Email report — coming soon
          </Button>
        </div>
        {download.isError && (
          <p className="text-sm text-destructive">Couldn't prepare the PDF just now. Please try again.</p>
        )}
        {download.isSuccess && !download.isPending && (
          <p className="text-sm text-muted-foreground">PDF downloaded.</p>
        )}
      </CardContent>
    </Card>
  );
}
