import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export function ReportExportActions() {
  return (
    <Card>
      <CardContent className="flex flex-wrap gap-2 py-4">
        <Button variant="outline" size="sm" disabled title="Coming soon">
          Download PDF — coming soon
        </Button>
        <Button variant="outline" size="sm" disabled title="Coming soon">
          Share with client — coming soon
        </Button>
        <Button variant="outline" size="sm" disabled title="Coming soon">
          Email report — coming soon
        </Button>
      </CardContent>
    </Card>
  );
}
