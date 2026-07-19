import type { ReportSection } from "@/types";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface ReportSectionCardProps {
  section: ReportSection;
}

export function ReportSectionCard({ section }: ReportSectionCardProps) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{section.title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ul className="list-inside list-disc space-y-1 text-sm text-muted-foreground">
          {section.body.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
