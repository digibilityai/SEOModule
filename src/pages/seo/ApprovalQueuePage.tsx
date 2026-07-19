import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { RecommendationStatus, SeoUserRole } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchLatestAudit, fetchIssuesForAudit } from "@/services/auditService";
import { fetchRecommendations } from "@/services/recommendationService";
import {
  fetchApprovalQueue,
  ensureApprovalQueueGenerated,
  updateApprovalItemFields,
  addApprovalComment,
} from "@/services/approvalService";
import { MOCK_CURRENT_ROLE } from "@/mocks/mockContext";
import { filterApprovalItems, type ApprovalFilterKey } from "@/lib/approvalPermissions";
import { APPROVAL_QUEUE_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { RoleSwitcher } from "./approvals/RoleSwitcher";
import { ApprovalFiltersBar } from "./approvals/ApprovalFiltersBar";
import { ApprovalItemCard } from "./approvals/ApprovalItemCard";

export function ApprovalQueuePage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [role, setRole] = useState<SeoUserRole>(MOCK_CURRENT_ROLE);
  const [filter, setFilter] = useState<ApprovalFilterKey>("all");

  const { data: latestAudit, isLoading: isLoadingAudit } = useQuery({
    queryKey: ["seo-audits-latest", activeWebsite?.id],
    queryFn: () => fetchLatestAudit(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  const { data: issues = [] } = useQuery({
    queryKey: ["seo-issues", latestAudit?.id],
    queryFn: () => fetchIssuesForAudit(latestAudit!.id),
    enabled: !!latestAudit && latestAudit.status === "completed",
  });

  const { data: recommendations = [], isLoading: isLoadingRecommendations } = useQuery({
    queryKey: ["seo-recommendations", activeWebsite?.id],
    queryFn: () => fetchRecommendations(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  const { data: approvalItems = [], isLoading: isLoadingQueue } = useQuery({
    queryKey: ["seo-approval-queue", activeWebsite?.id, recommendations.length],
    queryFn: async () => {
      await ensureApprovalQueueGenerated(activeWebsite!, recommendations, issues);
      return fetchApprovalQueue(activeWebsite!.id);
    },
    enabled: !!activeWebsite && recommendations.length > 0,
  });

  const invalidateQueue = () => {
    queryClient.invalidateQueries({ queryKey: ["seo-approval-queue", activeWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-approvals-summary", activeWebsite?.id] });
  };

  const statusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: RecommendationStatus }) =>
      updateApprovalItemFields(id, { status }),
    onSuccess: invalidateQueue,
  });

  const editMutation = useMutation({
    mutationFn: ({ id, suggestedChange }: { id: string; suggestedChange: string }) =>
      updateApprovalItemFields(id, { suggested_change: suggestedChange }),
    onSuccess: invalidateQueue,
  });

  const commentMutation = useMutation({
    mutationFn: ({ id, commentText }: { id: string; commentText: string }) =>
      addApprovalComment(id, { author_role: role, comment_text: commentText }),
    onSuccess: invalidateQueue,
  });

  const isMutating = statusMutation.isPending || editMutation.isPending || commentMutation.isPending;

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>
            The approval queue is tied to a website. Add a website to get started.
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

  if (isLoadingAudit || isLoadingRecommendations) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (recommendations.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Nothing to review yet</CardTitle>
          <CardDescription>
            Run a technical SEO audit to generate recommendations, then review them here before
            anything is applied.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button asChild>
            <Link to="/seo/audit">Run SEO audit</Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  const filteredItems = filterApprovalItems(approvalItems, filter);

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <CardTitle>Approval Queue</CardTitle>
              <CardDescription>
                Review before action — nothing here is applied to {activeWebsite.name} until you
                approve it.
              </CardDescription>
            </div>
            <RoleSwitcher role={role} onChange={setRole} />
          </div>
        </CardHeader>
      </Card>

      <SafetyNotice text={APPROVAL_QUEUE_SAFETY_NOTICE} />

      <ApprovalFiltersBar active={filter} onChange={setFilter} />

      {isLoadingQueue && <p className="text-sm text-muted-foreground">Loading queue...</p>}

      {!isLoadingQueue && filteredItems.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            No items match this filter.
          </CardContent>
        </Card>
      )}

      <div className="space-y-3">
        {filteredItems.map((item) => (
          <ApprovalItemCard
            key={item.id}
            item={item}
            role={role}
            isMutating={isMutating}
            onStatusChange={(id, status) => statusMutation.mutate({ id, status })}
            onSaveSuggestedChange={(id, suggestedChange) =>
              editMutation.mutate({ id, suggestedChange })
            }
            onAddComment={(id, commentText) => commentMutation.mutate({ id, commentText })}
          />
        ))}
      </div>
    </div>
  );
}
