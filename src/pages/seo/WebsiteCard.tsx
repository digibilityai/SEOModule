import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import type { SeoWebsite } from "@/types";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";
import { WebsiteConnectionHealth } from "./WebsiteConnectionHealth";
import { OwnershipVerificationPanel } from "./websites/OwnershipVerificationPanel";

const ONBOARDING_STATUS_LABEL = {
  completed: "Onboarding complete",
  in_progress: "Onboarding in progress",
  not_started: "Onboarding not started",
} as const;

interface WebsiteCardProps {
  website: SeoWebsite;
}

export function WebsiteCard({ website }: WebsiteCardProps) {
  const navigate = useNavigate();
  const { activeWebsiteId, setActiveWebsiteId } = useActiveWebsite();
  const isActive = activeWebsiteId === website.id;

  const { data: onboarding } = useQuery({
    queryKey: ["seo-onboarding", website.id],
    queryFn: () => fetchOnboardingByWebsiteId(website.id),
  });

  const onboardingStatus = onboarding?.status ?? "not_started";

  return (
    <Card className={isActive ? "border-primary" : undefined}>
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div>
            <CardTitle className="text-lg">{website.name}</CardTitle>
            <CardDescription>{website.website_url}</CardDescription>
          </div>
          {isActive ? (
            <Badge>Active</Badge>
          ) : (
            <Button size="sm" variant="outline" onClick={() => setActiveWebsiteId(website.id)}>
              Set active
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2 text-sm text-muted-foreground">
          <Badge variant="outline">{website.business_name}</Badge>
          {website.industry && <Badge variant="outline">{website.industry}</Badge>}
          {website.target_location && <Badge variant="outline">{website.target_location}</Badge>}
          <Badge variant="outline">{website.website_type.replace("_", " ")}</Badge>
          <Badge variant="secondary">{website.plan} plan</Badge>
        </div>

        <div className="flex items-center gap-2">
          <Badge variant={website.status === "active" ? "default" : "outline"}>
            Setup status: {website.status}
          </Badge>
          <Badge variant={onboardingStatus === "completed" ? "default" : "secondary"}>
            {ONBOARDING_STATUS_LABEL[onboardingStatus]}
          </Badge>
        </div>

        <Separator />

        <WebsiteConnectionHealth website={website} />

        <Separator />

        <OwnershipVerificationPanel websiteId={website.id} websiteUrl={website.website_url} />

        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            setActiveWebsiteId(website.id);
            navigate("/seo/onboarding");
          }}
        >
          Manage business onboarding
        </Button>
      </CardContent>
    </Card>
  );
}
