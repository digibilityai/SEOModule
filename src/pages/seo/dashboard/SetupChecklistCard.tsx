import { CheckCircle2, Circle, Clock } from "lucide-react";
import type { SetupChecklistItem } from "@/types";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface SetupChecklistCardProps {
  items: SetupChecklistItem[];
}

export function SetupChecklistCard({ items }: SetupChecklistCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Setup Progress</CardTitle>
        <CardDescription>Getting your SEO foundation in place.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {items.map((item) => {
          const Icon = item.is_future_integration ? Clock : item.is_complete ? CheckCircle2 : Circle;
          return (
            <div key={item.key} className="flex items-center justify-between gap-3 text-sm">
              <span className="flex items-center gap-2 text-foreground">
                <Icon
                  className={
                    item.is_future_integration
                      ? "h-4 w-4 text-muted-foreground"
                      : item.is_complete
                        ? "h-4 w-4 text-success"
                        : "h-4 w-4 text-muted-foreground"
                  }
                />
                {item.label}
              </span>
              <span className="text-xs text-muted-foreground">{item.status_label}</span>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}
