import { useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { RelatedModule, SupportRequestType, SupportStatus } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import {
  addSupportComment,
  cancelSupportRequest,
  createSupportRequest,
  fetchSupportRequests,
  fetchSupportSummary,
  markAdditionalInfoProvided,
  updateSupportRequestStatus,
} from "@/services/supportService";
import { SUPPORT_DESK_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { SupportSummaryHeader } from "./support/SupportSummaryHeader";
import { NewSupportRequestForm } from "./support/NewSupportRequestForm";
import { SupportRequestCard } from "./support/SupportRequestCard";

export function ExpertSupportPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [searchParams] = useSearchParams();
  const [isFormOpen, setIsFormOpen] = useState(
    searchParams.has("prefillTitle") || searchParams.has("prefillModule"),
  );

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const { data: requests = [], isLoading: isLoadingRequests } = useQuery({
    queryKey: ["seo-support-requests", activeWebsite?.id],
    queryFn: () => fetchSupportRequests(activeWebsite!.id),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const { data: summary } = useQuery({
    queryKey: ["seo-support-summary", activeWebsite?.id, requests.length],
    queryFn: () => fetchSupportSummary(activeWebsite!.id, activeWebsite!.website_url),
    enabled: !!activeWebsite && isOnboardingComplete,
  });

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["seo-support-requests", activeWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-support-summary", activeWebsite?.id] });
  };

  const createMutation = useMutation({
    mutationFn: (input: Parameters<typeof createSupportRequest>[1]) => createSupportRequest(activeWebsite!, input),
    onSuccess: () => {
      setIsFormOpen(false);
      invalidateAll();
    },
  });

  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: SupportStatus }) => updateSupportRequestStatus(id, status),
    onSuccess: invalidateAll,
  });

  const commentMutation = useMutation({
    mutationFn: ({ id, commentText }: { id: string; commentText: string }) =>
      addSupportComment(id, { author_role: "owner", comment_text: commentText }),
    onSuccess: invalidateAll,
  });

  const infoProvidedMutation = useMutation({
    mutationFn: (id: string) => markAdditionalInfoProvided(id),
    onSuccess: invalidateAll,
  });

  const cancelMutation = useMutation({
    mutationFn: (id: string) => cancelSupportRequest(id),
    onSuccess: invalidateAll,
  });

  const isMutating =
    statusMutation.isPending || commentMutation.isPending || infoProvidedMutation.isPending || cancelMutation.isPending;

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>Expert support is tied to a website. Add a website to get started.</CardDescription>
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
          <CardDescription>Support requests use your business context to route to the right expert.</CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/onboarding">Complete business onboarding</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (isLoadingRequests) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  const prefill = {
    title: searchParams.get("prefillTitle") ?? undefined,
    request_type: (searchParams.get("prefillType") as SupportRequestType | null) ?? undefined,
    related_module: (searchParams.get("prefillModule") as RelatedModule | null) ?? undefined,
    related_item_url: searchParams.get("prefillUrl") ?? undefined,
  };

  return (
    <div className="space-y-4">
      {summary && (
        <SupportSummaryHeader website={activeWebsite} summary={summary} onNewRequest={() => setIsFormOpen(true)} />
      )}
      <SafetyNotice text={SUPPORT_DESK_SAFETY_NOTICE} />

      {isFormOpen && (
        <NewSupportRequestForm
          prefill={prefill}
          isSubmitting={createMutation.isPending}
          onCancel={() => setIsFormOpen(false)}
          onSubmit={(input) => createMutation.mutate(input)}
        />
      )}

      {requests.length === 0 && !isFormOpen && (
        <Card>
          <CardHeader>
            <CardTitle>No support requests yet</CardTitle>
            <CardDescription>
              Need help with something? Send a request to Digibility experts — technical fixes, content
              review, off-page support and more.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button onClick={() => setIsFormOpen(true)}>New support request</Button>
          </CardContent>
        </Card>
      )}

      <div className="space-y-3">
        {requests.map((r) => (
          <SupportRequestCard
            key={r.id}
            request={r}
            isMutating={isMutating}
            onStatusChange={(id, status) => statusMutation.mutate({ id, status })}
            onAddComment={(id, commentText) => commentMutation.mutate({ id, commentText })}
            onMarkInfoProvided={(id) => infoProvidedMutation.mutate(id)}
            onCancelRequest={(id) => cancelMutation.mutate(id)}
          />
        ))}
      </div>
    </div>
  );
}
