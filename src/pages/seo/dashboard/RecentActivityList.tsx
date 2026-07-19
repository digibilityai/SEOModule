import type { RecentActivityItem } from "@/types";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface RecentActivityListProps {
  items: RecentActivityItem[];
}

export function RecentActivityList({ items }: RecentActivityListProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Recent Activity</CardTitle>
        <CardDescription>What's happened lately for this website.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {items.length === 0 && (
          <p className="text-sm text-muted-foreground">No activity yet.</p>
        )}
        {items.map((item) => (
          <div key={item.id} className="flex items-center justify-between gap-3 text-sm">
            <span className="text-foreground">{item.summary}</span>
            <span className="whitespace-nowrap text-xs text-muted-foreground">
              {new Date(item.occurred_at).toLocaleDateString()}
            </span>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
