import type { AuthorityOverview, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface AuthorityHeaderProps {
  website: SeoWebsite;
  overview: AuthorityOverview;
}

export function AuthorityHeader({ website, overview }: AuthorityHeaderProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{website.name}</CardTitle>
        <CardDescription>{website.website_url}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="secondary">Authority score: {overview.authority_score}/100</Badge>
          <Badge variant="outline">Opportunities: {overview.opportunity_count}</Badge>
          <Badge variant="outline">Campaigns: {overview.campaign_count}</Badge>
          {overview.high_risk_count > 0 && (
            <Badge variant="destructive">Needs review: {overview.high_risk_count}</Badge>
          )}
        </div>
        <p className="text-sm text-muted-foreground">{overview.trust_signal_summary}</p>
        <p className="text-xs text-muted-foreground">{overview.data_source_status}</p>
      </CardContent>
    </Card>
  );
}
