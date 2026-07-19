import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export interface AdminOperationsMetric {
  label: string;
  value: string | number;
}

interface AdminOperationsCardProps {
  title: string;
  metrics: AdminOperationsMetric[];
  comingSoonLabel: string;
}

// Generic, reusable admin section card — one component reused across every
// admin operations area so it can be mounted inside the main Digibility
// Admin Panel later without duplicating layout code.
export function AdminOperationsCard({ title, metrics, comingSoonLabel }: AdminOperationsCardProps) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {metrics.map((m) => (
          <div key={m.label} className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">{m.label}</span>
            <span className="font-medium text-foreground">{m.value}</span>
          </div>
        ))}
        <Badge variant="outline" className="mt-2">
          {comingSoonLabel}
        </Badge>
      </CardContent>
    </Card>
  );
}
