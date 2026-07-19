import type { BusinessOnboarding, SeoAudit, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { getPlanConfig } from "@/registry/planRegistry";

interface DashboardHeaderProps {
  website: SeoWebsite;
  onboarding: BusinessOnboarding | null;
  latestAudit: SeoAudit | null;
}

export function DashboardHeader({ website, onboarding, latestAudit }: DashboardHeaderProps) {
  const planConfig = getPlanConfig(website.plan);

  return (
    <Card>
      <CardContent className="flex flex-wrap items-center justify-between gap-3 py-4">
        <div>
          <h1 className="text-xl font-semibold text-foreground">{website.name}</h1>
          <p className="text-sm text-muted-foreground">{website.website_url}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={website.status === "active" ? "default" : "outline"}>
            Setup: {website.status}
          </Badge>
          <Badge variant={onboarding?.status === "completed" ? "default" : "secondary"}>
            Onboarding: {(onboarding?.status ?? "not_started").replace("_", " ")}
          </Badge>
          <Badge variant="outline">{planConfig.name} plan</Badge>
          <Badge variant={latestAudit ? "secondary" : "outline"}>
            {latestAudit
              ? `Last audit: ${new Date(latestAudit.completed_at ?? latestAudit.started_at).toLocaleDateString()} (${latestAudit.status})`
              : "No audit yet"}
          </Badge>
        </div>
      </CardContent>
    </Card>
  );
}
