import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchOnPageRecommendations } from "@/services/recommendationService";
import { recommendationRequiresApproval } from "@/lib/safetyRules";
import { HELP_ROUTES } from "@/help/routes";
import { SafetyNotice } from "./shared/SafetyNotice";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

const AREA_LABEL: Record<string, string> = {
  title: "Title tag",
  meta_description: "Meta description",
  h1: "H1",
  faq: "FAQ section",
  schema: "Schema",
  internal_links: "Internal links",
  content: "Content",
};

export function PageOptimizerPage() {
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();

  const { data: recommendations = [], isLoading } = useQuery({
    queryKey: ["seo-onpage-recommendations", activeWebsite?.id],
    queryFn: () => fetchOnPageRecommendations(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>
            On-page recommendations are tied to a website. Add a website to get started.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/websites">Add your website</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Page Optimizer</CardTitle>
          <CardDescription>
            On-page suggestions for {activeWebsite.name}. Run an audit on the Technical SEO Audit
            page to refresh these.
          </CardDescription>
          <Link to={HELP_ROUTES.APPROVAL_WORKFLOW} className={HELP_LINK_CLASSNAME}>
            Why some suggestions need approval
          </Link>
        </CardHeader>
      </Card>

      <SafetyNotice />

      {isLoading && <p className="text-sm text-muted-foreground">Loading recommendations...</p>}

      {!isLoading && recommendations.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            No on-page recommendations yet. Run an audit to generate some.
          </CardContent>
        </Card>
      )}

      <div className="space-y-3">
        {recommendations.map((rec) => {
          const needsApproval = recommendationRequiresApproval(rec);
          return (
            <Card key={rec.id}>
              <CardHeader className="space-y-2">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <h3 className="font-medium text-foreground">{rec.title}</h3>
                  <Badge variant="outline">{AREA_LABEL[rec.area] ?? rec.area}</Badge>
                </div>
              </CardHeader>
              <CardContent className="space-y-2 text-sm">
                {rec.current_value && (
                  <p>
                    <span className="font-medium text-foreground">Current: </span>
                    <span className="text-muted-foreground">{rec.current_value}</span>
                  </p>
                )}
                <p>
                  <span className="font-medium text-foreground">Suggested: </span>
                  <span className="text-muted-foreground">{rec.suggested_change}</span>
                </p>
                <p className="text-muted-foreground">{rec.why_it_helps}</p>
                <div className="flex flex-wrap gap-2 text-xs">
                  <Badge variant="outline">Risk: {rec.risk}</Badge>
                  <Badge variant={needsApproval ? "default" : "secondary"}>
                    {needsApproval ? "Approval required" : "No approval needed"}
                  </Badge>
                  <Badge variant="outline">Status: {rec.status.replace("_", " ")}</Badge>
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
