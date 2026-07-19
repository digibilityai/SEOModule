import type { SeoAdminOverview } from "@/types";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface AdminOverviewCardsProps {
  overview: SeoAdminOverview;
}

// Reusable — safe to mount inside the main Digibility Admin Panel later.
export function AdminOverviewCards({ overview }: AdminOverviewCardsProps) {
  const cards = [
    { label: "Total websites", value: overview.total_websites },
    { label: "Active SEO websites", value: overview.active_websites },
    { label: "Average visibility score", value: `${overview.average_visibility_score}/100` },
    { label: "Open support requests", value: overview.open_support_requests },
    { label: "Pending approvals", value: overview.pending_approvals },
    { label: "High-risk recommendations", value: overview.high_risk_recommendations },
    { label: "Failed audits", value: overview.failed_audits },
    { label: "Content items in review", value: overview.content_items_in_review },
    { label: "Reports generated", value: overview.reports_generated },
    { label: "AI visibility gaps", value: overview.ai_visibility_gaps },
    { label: "Roadmap actions pending", value: overview.roadmap_actions_pending },
  ];

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {cards.map((card) => (
        <Card key={card.label}>
          <CardHeader className="space-y-2 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">{card.label}</CardTitle>
          </CardHeader>
          <CardContent>
            <span className="text-3xl font-semibold text-foreground">{card.value}</span>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
