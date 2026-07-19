import type { BusinessOnboarding, ContentOpportunity, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getPlanConfig } from "@/registry/planRegistry";

interface ContentStudioHeaderProps {
  website: SeoWebsite;
  onboarding: BusinessOnboarding;
  opportunities: ContentOpportunity[];
}

export function ContentStudioHeader({ website, onboarding, opportunities }: ContentStudioHeaderProps) {
  const planConfig = getPlanConfig(website.plan);
  const opportunityCount = opportunities.length;
  const draftCount = opportunities.filter((o) =>
    ["draft_ready", "draft_in_review", "draft_approved", "expert_review_requested", "ready_for_publish", "completed"].includes(
      o.status,
    ),
  ).length;

  const opportunityLimit = planConfig.contentOpportunitiesLimit;
  const draftLimit = planConfig.contentDraftLimit;
  const overOpportunityLimit =
    typeof opportunityLimit === "number" && opportunityCount >= opportunityLimit;
  const overDraftLimit = typeof draftLimit === "number" && draftCount >= draftLimit;

  return (
    <Card>
      <CardHeader>
        <CardTitle>{website.name}</CardTitle>
        <CardDescription>{website.website_url}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="rounded-md bg-muted/40 p-3 text-sm text-muted-foreground">
          <span className="font-medium text-foreground">{website.business_name}</span> —{" "}
          {onboarding.services_products}. Target audience: {onboarding.target_audience}. Preferred
          tone: {onboarding.preferred_content_tone}.
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">{planConfig.name} plan</Badge>
          <Badge variant={overOpportunityLimit ? "destructive" : "secondary"}>
            Content plans: {opportunityCount}/{opportunityLimit === "unlimited" ? "∞" : opportunityLimit}
          </Badge>
          <Badge variant={overDraftLimit ? "destructive" : "secondary"}>
            Drafts: {draftCount}/{draftLimit === "unlimited" ? "∞" : draftLimit}
          </Badge>
        </div>
        {(overOpportunityLimit || overDraftLimit) && (
          <p className="text-xs text-warning-foreground">
            You're at your {planConfig.name} plan limit. Upgrade to plan or generate more this
            month.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
