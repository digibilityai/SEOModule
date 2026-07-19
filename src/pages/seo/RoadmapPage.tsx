import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { RoadmapFilterKey, RoadmapStatus } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import {
  fetchRoadmapItems,
  fetchRoadmapSummary,
  generateRoadmapFromFindings,
  updateRoadmapItemStatus,
} from "@/services/roadmapService";
import { filterRoadmapItems } from "@/lib/roadmapFilters";
import { ROADMAP_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { RoadmapSummaryHeader } from "./roadmap/RoadmapSummaryHeader";
import { RoadmapFiltersBar } from "./roadmap/RoadmapFiltersBar";
import { RoadmapItemCard } from "./roadmap/RoadmapItemCard";

export function RoadmapPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [filter, setFilter] = useState<RoadmapFilterKey>("all");

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const { data: items = [], isLoading: isLoadingItems } = useQuery({
    queryKey: ["seo-roadmap-items", activeWebsite?.id],
    queryFn: () => fetchRoadmapItems(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: summary } = useQuery({
    queryKey: ["seo-roadmap-summary", activeWebsite?.id, items.length],
    queryFn: () => fetchRoadmapSummary(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["seo-roadmap-items", activeWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-roadmap-summary", activeWebsite?.id] });
  };

  const generateMutation = useMutation({
    mutationFn: () => generateRoadmapFromFindings(activeWebsite!),
    onSuccess: invalidateAll,
  });

  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: RoadmapStatus }) => updateRoadmapItemStatus(id, status),
    onSuccess: invalidateAll,
  });

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>The 90-day roadmap is tied to a website. Add a website to get started.</CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/websites">Add your website</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (isLoadingOnboarding) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!onboarding || !isOnboardingComplete) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Complete business onboarding first</CardTitle>
          <CardDescription>
            The roadmap uses your business context to prioritize the right actions.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/onboarding">Complete business onboarding</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (isLoadingItems) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (items.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No roadmap yet</CardTitle>
          <CardDescription>
            Generate a 90-day plan for {activeWebsite.name} from your audit, recommendations,
            performance, off-page and AI visibility findings.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button onClick={() => generateMutation.mutate()} disabled={generateMutation.isPending}>
            {generateMutation.isPending ? "Generating..." : "Generate 90-Day Roadmap"}
          </Button>
        </CardContent>
      </Card>
    );
  }

  const filteredItems = [...filterRoadmapItems(items, filter)].sort((a, b) => a.week_number - b.week_number);
  const isFullyCompleted = summary ? summary.total_actions > 0 && summary.completed_actions === summary.total_actions : false;

  return (
    <div className="space-y-4">
      {summary && (
        <RoadmapSummaryHeader
          website={activeWebsite}
          summary={summary}
          onGenerate={() => generateMutation.mutate()}
          isGenerating={generateMutation.isPending}
        />
      )}
      <SafetyNotice text={ROADMAP_SAFETY_NOTICE} />

      {isFullyCompleted && (
        <Card>
          <CardContent className="py-4 text-center text-sm text-foreground">
            Every action in this roadmap is marked complete. Generate a fresh roadmap to plan the next
            90 days.
          </CardContent>
        </Card>
      )}

      <RoadmapFiltersBar active={filter} onChange={setFilter} />

      {filteredItems.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            No actions match this filter.
          </CardContent>
        </Card>
      )}

      <div className="space-y-3">
        {filteredItems.map((item) => (
          <RoadmapItemCard
            key={item.id}
            item={item}
            onStatusChange={(id, status) => statusMutation.mutate({ id, status })}
            isMutating={statusMutation.isPending}
          />
        ))}
      </div>
    </div>
  );
}
