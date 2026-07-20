import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { NewSeoWebsiteInput } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { fetchWebsites, addWebsite } from "@/services/websiteService";
import { getPlanConfig } from "@/registry/planRegistry";
import { MOCK_CURRENT_PLAN_TIER, MOCK_WORKSPACE_ID } from "@/mocks/mockContext";
import { HELP_ROUTES } from "@/help/routes";
import { WebsiteCard } from "./WebsiteCard";
import { WebsiteForm } from "./WebsiteForm";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

export function WebsitesPage() {
  const queryClient = useQueryClient();
  const [isFormOpen, setIsFormOpen] = useState(false);

  const { data: websites = [], isLoading } = useQuery({
    queryKey: ["seo-websites", MOCK_WORKSPACE_ID],
    queryFn: () => fetchWebsites(MOCK_WORKSPACE_ID),
  });

  const createMutation = useMutation({
    mutationFn: (input: NewSeoWebsiteInput) => addWebsite(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["seo-websites", MOCK_WORKSPACE_ID] });
      setIsFormOpen(false);
    },
  });

  const planConfig = getPlanConfig(MOCK_CURRENT_PLAN_TIER);
  const isAtWebsiteLimit = websites.length >= planConfig.websiteLimit;

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Websites</CardTitle>
          <CardDescription>
            Every SEO audit, recommendation and report is tied to a website. Add the sites you
            want Digibility to work on.
          </CardDescription>
          <Link to={HELP_ROUTES.ADDING_WEBSITE} className={HELP_LINK_CLASSNAME}>
            How adding a website works
          </Link>
        </CardHeader>
        <CardContent className="space-y-4">
          {isAtWebsiteLimit && (
            <p className="rounded-md bg-warning/10 px-3 py-2 text-sm text-warning-foreground">
              You've reached the {planConfig.name} plan limit of {planConfig.websiteLimit}{" "}
              website{planConfig.websiteLimit === 1 ? "" : "s"}. Upgrade your plan to add more.
            </p>
          )}

          {!isFormOpen && (
            <Button onClick={() => setIsFormOpen(true)} disabled={isAtWebsiteLimit}>
              Add website
            </Button>
          )}

          {isFormOpen && (
            <WebsiteForm
              onSubmit={(input) => createMutation.mutate(input)}
              onCancel={() => setIsFormOpen(false)}
              isSubmitting={createMutation.isPending}
              disabled={isAtWebsiteLimit}
              disabledReason={
                isAtWebsiteLimit
                  ? `You're at your ${planConfig.name} plan limit. Upgrade to add another website.`
                  : undefined
              }
            />
          )}
        </CardContent>
      </Card>

      {isLoading && <p className="text-sm text-muted-foreground">Loading websites...</p>}

      {!isLoading && websites.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            No websites yet. Add your first website to start SEO setup.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        {websites.map((website) => (
          <WebsiteCard key={website.id} website={website} />
        ))}
      </div>
    </div>
  );
}
