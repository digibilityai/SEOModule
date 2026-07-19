import type { SeoAdminWebsiteRow } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import {
  AUDIT_STATUS_LABEL,
  HEALTH_LABEL,
  HEALTH_VARIANT,
  ONBOARDING_STATUS_LABEL,
} from "../adminLabels";

interface AdminWebsiteListProps {
  rows: SeoAdminWebsiteRow[];
  selectedId: string | null;
  onSelect: (websiteId: string) => void;
}

// Reusable — safe to mount inside the main Digibility Admin Panel later.
export function AdminWebsiteList({ rows, selectedId, onSelect }: AdminWebsiteListProps) {
  if (rows.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-sm text-muted-foreground">
          No websites match this filter.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-2">
      {rows.map((row) => (
        <Card
          key={row.website_id}
          className={cn(
            "cursor-pointer transition-colors hover:border-primary/40",
            selectedId === row.website_id && "border-primary",
          )}
          onClick={() => onSelect(row.website_id)}
        >
          <CardHeader className="space-y-2 py-4">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <h3 className="font-medium text-foreground">{row.website_name}</h3>
                <p className="break-all text-xs text-muted-foreground">{row.website_url}</p>
              </div>
              <Badge variant={HEALTH_VARIANT[row.health]}>{HEALTH_LABEL[row.health]}</Badge>
            </div>
            <div className="flex flex-wrap gap-2 text-xs">
              <Badge variant="outline">{row.business_name}</Badge>
              <Badge variant="outline">Plan: {row.plan}</Badge>
              <Badge variant="outline">Onboarding: {ONBOARDING_STATUS_LABEL[row.onboarding_status]}</Badge>
              <Badge variant="outline">Audit: {AUDIT_STATUS_LABEL[row.latest_audit_status]}</Badge>
              <Badge variant="outline">Visibility: {row.visibility_score}/100</Badge>
              <Badge variant="outline">Pending approvals: {row.pending_approvals_count}</Badge>
              <Badge variant="outline">Open support: {row.open_support_requests_count}</Badge>
              <Badge variant="outline">
                Last activity: {row.last_activity_at ? new Date(row.last_activity_at).toLocaleDateString() : "—"}
              </Badge>
            </div>
          </CardHeader>
        </Card>
      ))}
    </div>
  );
}
