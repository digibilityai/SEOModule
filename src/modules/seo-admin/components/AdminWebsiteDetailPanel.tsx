import type { SeoAdminWebsiteDetail } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { CONNECTION_STATUS_LABEL, HEALTH_LABEL, HEALTH_VARIANT } from "../adminLabels";

interface AdminWebsiteDetailPanelProps {
  detail: SeoAdminWebsiteDetail;
}

// Reusable — safe to mount inside the main Digibility Admin Panel later.
export function AdminWebsiteDetailPanel({ detail }: AdminWebsiteDetailPanelProps) {
  const rows: { label: string; value: string }[] = [
    { label: "Business onboarding", value: detail.onboarding_summary },
    { label: "Audit summary", value: detail.audit_summary },
    { label: "Recommendation summary", value: detail.recommendation_summary },
    { label: "Approval summary", value: detail.approval_summary },
    { label: "Content Studio summary", value: detail.content_summary },
    { label: "Page Performance summary", value: detail.performance_summary },
    { label: "Off-page summary", value: detail.offpage_summary },
    { label: "AI visibility summary", value: detail.ai_visibility_summary },
    { label: "Competitor summary", value: detail.competitor_summary },
    { label: "Roadmap summary", value: detail.roadmap_summary },
    { label: "Support summary", value: detail.support_summary },
    { label: "Report summary", value: detail.report_summary },
  ];

  return (
    <Card>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <CardTitle>{detail.row.website_name}</CardTitle>
            <CardDescription>{detail.website_url}</CardDescription>
          </div>
          <Badge variant={HEALTH_VARIANT[detail.row.health]}>{HEALTH_LABEL[detail.row.health]}</Badge>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">{detail.business_name}</Badge>
          {detail.industry && <Badge variant="outline">{detail.industry}</Badge>}
          {detail.target_location && <Badge variant="outline">{detail.target_location}</Badge>}
        </div>
      </CardHeader>
      <CardContent className="space-y-4 border-t border-border pt-4 text-sm">
        <div>
          <p className="font-medium text-foreground">Connected tools (placeholder — no real integration yet)</p>
          <div className="mt-1 flex flex-wrap gap-2 text-xs">
            <Badge variant="outline">GSC: {CONNECTION_STATUS_LABEL[detail.connected_tools.gsc_status]}</Badge>
            <Badge variant="outline">GA4: {CONNECTION_STATUS_LABEL[detail.connected_tools.ga4_status]}</Badge>
            <Badge variant="outline">CMS: {CONNECTION_STATUS_LABEL[detail.connected_tools.cms_status]}</Badge>
            <Badge variant="outline">GBP: {CONNECTION_STATUS_LABEL[detail.connected_tools.gbp_status]}</Badge>
          </div>
        </div>

        {rows.map((r) => (
          <div key={r.label}>
            <p className="font-medium text-foreground">{r.label}</p>
            <p className="text-muted-foreground">{r.value}</p>
          </div>
        ))}

        <div className="border-t border-border pt-3">
          <p className="font-medium text-foreground">Admin notes</p>
          <p className="text-muted-foreground">{detail.admin_notes || "No admin notes yet."}</p>
        </div>
      </CardContent>
    </Card>
  );
}
