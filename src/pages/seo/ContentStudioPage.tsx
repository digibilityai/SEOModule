import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { ContentFormatType, ContentWorkflowStatus } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import {
  fetchContentOpportunities,
  createCustomContentOpportunity,
  startContentPlan,
  fetchKeywordPlan,
  fetchCompetitorContentSummary,
  fetchWireframe,
  generateWireframe,
  approveWireframe,
  fetchFormatInput,
  saveFormatInput,
  fetchDraft,
  generateDraft,
  updateDraftSection,
  regenerateDraftSection,
  addDraftFeedback,
  updateContentStatus,
} from "@/services/contentStudioService";
import { MOCK_CURRENT_ROLE } from "@/mocks/mockContext";
import { SafetyNotice } from "./shared/SafetyNotice";
import { ContentStudioHeader } from "./contentStudio/ContentStudioHeader";
import { ContentOpportunityList } from "./contentStudio/ContentOpportunityList";
import { KeywordPlanSection } from "./contentStudio/KeywordPlanSection";
import { CompetitorSummarySection } from "./contentStudio/CompetitorSummarySection";
import { WireframeSection } from "./contentStudio/WireframeSection";
import { FormatInputSection } from "./contentStudio/FormatInputSection";
import { DraftReviewSection } from "./contentStudio/DraftReviewSection";
import { PublishQueueSection } from "./contentStudio/PublishQueueSection";

const RESEARCH_VISIBLE_STATUSES: ContentWorkflowStatus[] = [
  "plan_started",
  "keyword_plan_ready",
  "wireframe_ready",
  "wireframe_approved",
  "draft_ready",
  "draft_in_review",
  "draft_approved",
  "expert_review_requested",
  "ready_for_publish",
  "completed",
];

export function ContentStudioPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [regenerateError, setRegenerateError] = useState<string | null>(null);

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  const { data: opportunities = [], isLoading: isLoadingOpportunities } = useQuery({
    queryKey: ["content-opportunities", activeWebsite?.id],
    queryFn: () => fetchContentOpportunities(activeWebsite!.id),
    enabled: !!activeWebsite && onboarding?.status === "completed",
  });

  const selected = opportunities.find((o) => o.id === selectedId) ?? null;
  const researchUnlocked = !!selected && RESEARCH_VISIBLE_STATUSES.includes(selected.status);

  const { data: keywordPlan } = useQuery({
    queryKey: ["content-keyword-plan", selected?.id],
    queryFn: () => fetchKeywordPlan(selected!.id),
    enabled: researchUnlocked,
  });

  const { data: competitorSummaries = [] } = useQuery({
    queryKey: ["content-competitor-summary", selected?.id],
    queryFn: () => fetchCompetitorContentSummary(selected!.id, activeWebsite!),
    enabled: researchUnlocked && !!activeWebsite,
  });

  const { data: wireframe } = useQuery({
    queryKey: ["content-wireframe", selected?.id],
    queryFn: () => fetchWireframe(selected!.id),
    enabled: !!keywordPlan,
  });

  const { data: formatInput } = useQuery({
    queryKey: ["content-format-input", selected?.id],
    queryFn: () => fetchFormatInput(selected!.id),
    enabled: !!wireframe?.is_approved,
  });

  const { data: draft } = useQuery({
    queryKey: ["content-draft", selected?.id],
    queryFn: () => fetchDraft(selected!.id),
    enabled: !!wireframe?.is_approved,
  });

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["content-opportunities", activeWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["content-keyword-plan", selected?.id] });
    queryClient.invalidateQueries({ queryKey: ["content-competitor-summary", selected?.id] });
    queryClient.invalidateQueries({ queryKey: ["content-wireframe", selected?.id] });
    queryClient.invalidateQueries({ queryKey: ["content-format-input", selected?.id] });
    queryClient.invalidateQueries({ queryKey: ["content-draft", selected?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-recent-activity", activeWebsite?.id] });
  };

  const startPlanMutation = useMutation({
    mutationFn: (id: string) => startContentPlan(id),
    onSuccess: invalidateAll,
  });

  const addCustomMutation = useMutation({
    mutationFn: (input: { title: string; target_keyword: string }) =>
      createCustomContentOpportunity(activeWebsite!, input),
    onSuccess: invalidateAll,
  });

  const generateWireframeMutation = useMutation({
    mutationFn: () => generateWireframe(selected!.id, activeWebsite!),
    onSuccess: invalidateAll,
  });

  const approveWireframeMutation = useMutation({
    mutationFn: () => approveWireframe(selected!.id),
    onSuccess: invalidateAll,
  });

  const saveFormatMutation = useMutation({
    mutationFn: (input: {
      format_type: ContentFormatType;
      reference_url?: string;
      uploaded_file_name?: string;
      custom_instructions?: string;
    }) => saveFormatInput(selected!.id, input),
    onSuccess: invalidateAll,
  });

  const generateDraftMutation = useMutation({
    mutationFn: () => generateDraft(selected!.id),
    onSuccess: invalidateAll,
  });

  const draftSectionMutation = useMutation({
    mutationFn: ({
      sectionId,
      action,
      editedContent,
    }: {
      sectionId: string;
      action: Parameters<typeof updateDraftSection>[2];
      editedContent?: string;
    }) => updateDraftSection(selected!.id, sectionId, action, editedContent),
    onSuccess: invalidateAll,
  });

  // Kept separate from isMutating below so regenerating one section doesn't
  // disable the Approve/Reject/Edit buttons on every other section.
  const regenerateSectionMutation = useMutation({
    mutationFn: (sectionId: string) => regenerateDraftSection(selected!.id, sectionId),
    onSuccess: () => {
      setRegenerateError(null);
      invalidateAll();
    },
    onError: (error: unknown) => {
      setRegenerateError(error instanceof Error ? error.message : "Regenerate failed. Try again.");
    },
  });

  const feedbackMutation = useMutation({
    mutationFn: (text: string) => addDraftFeedback(selected!.id, MOCK_CURRENT_ROLE, text),
    onSuccess: invalidateAll,
  });

  const statusMutation = useMutation({
    mutationFn: (status: ContentWorkflowStatus) => updateContentStatus(selected!.id, status),
    onSuccess: invalidateAll,
  });

  const isMutating =
    startPlanMutation.isPending ||
    addCustomMutation.isPending ||
    generateWireframeMutation.isPending ||
    approveWireframeMutation.isPending ||
    saveFormatMutation.isPending ||
    generateDraftMutation.isPending ||
    draftSectionMutation.isPending ||
    feedbackMutation.isPending ||
    statusMutation.isPending;

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>
            Content Studio is tied to a website. Add a website to get started.
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

  if (isLoadingOnboarding) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!onboarding || onboarding.status !== "completed") {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Complete business onboarding first</CardTitle>
          <CardDescription>
            Content Studio uses your business context to suggest relevant titles and keywords.
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

  return (
    <div className="space-y-4">
      <ContentStudioHeader website={activeWebsite} onboarding={onboarding} opportunities={opportunities} />
      <SafetyNotice />

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-3">
          <h2 className="text-sm font-medium text-muted-foreground">Content Opportunities</h2>
          {isLoadingOpportunities ? (
            <p className="text-sm text-muted-foreground">Loading...</p>
          ) : (
            <ContentOpportunityList
              opportunities={opportunities}
              selectedId={selectedId}
              onSelect={setSelectedId}
              onStartPlan={(id) => startPlanMutation.mutate(id)}
              onAddCustomTitle={(title, target_keyword) =>
                addCustomMutation.mutate({ title, target_keyword })
              }
              isMutating={isMutating}
            />
          )}
        </div>

        <div className="space-y-3">
          <h2 className="text-sm font-medium text-muted-foreground">Active Content Workflow</h2>
          {!selected && (
            <Card>
              <CardContent className="py-8 text-center text-sm text-muted-foreground">
                Select a content opportunity and start a plan to see its workflow here.
              </CardContent>
            </Card>
          )}

          {selected && keywordPlan && <KeywordPlanSection plan={keywordPlan} />}
          {selected && competitorSummaries.length > 0 && (
            <CompetitorSummarySection summaries={competitorSummaries} />
          )}
          {selected && keywordPlan && (
            <WireframeSection
              wireframe={wireframe ?? null}
              isMutating={isMutating}
              onGenerate={() => generateWireframeMutation.mutate()}
              onApprove={() => approveWireframeMutation.mutate()}
            />
          )}

          {selected && wireframe?.is_approved && (
            <FormatInputSection
              formatInput={formatInput ?? null}
              isMutating={isMutating}
              onSave={(input) => saveFormatMutation.mutate(input)}
            />
          )}

          {selected && wireframe?.is_approved && !draft && (
            <Card>
              <CardContent className="space-y-2 py-6 text-center text-sm text-muted-foreground">
                <p>Wireframe approved. Generate a draft when you're ready.</p>
                <Button size="sm" onClick={() => generateDraftMutation.mutate()} disabled={isMutating}>
                  Generate draft
                </Button>
              </CardContent>
            </Card>
          )}

          {selected && wireframe && !wireframe.is_approved && (
            <Card>
              <CardContent className="py-6 text-center text-sm text-muted-foreground">
                Approve the wireframe above before a draft can be generated.
              </CardContent>
            </Card>
          )}

          {selected && draft && (
            <DraftReviewSection
              draft={draft}
              isMutating={isMutating}
              isRegeneratingSectionId={
                regenerateSectionMutation.isPending ? (regenerateSectionMutation.variables ?? null) : null
              }
              regenerateError={regenerateError}
              onSectionAction={(sectionId, action, editedContent) =>
                draftSectionMutation.mutate({ sectionId, action, editedContent })
              }
              onRegenerateSection={(sectionId) => {
                setRegenerateError(null);
                regenerateSectionMutation.mutate(sectionId);
              }}
              onApproveDraft={() => statusMutation.mutate("draft_approved")}
              onRejectDraft={() => statusMutation.mutate("rejected")}
              onSendToExpertReview={() => statusMutation.mutate("expert_review_requested")}
              onAddFeedback={(text) => feedbackMutation.mutate(text)}
            />
          )}

          {selected &&
            ["draft_approved", "expert_review_requested", "ready_for_publish", "completed"].includes(
              selected.status,
            ) && (
              <PublishQueueSection
                status={selected.status}
                isMutating={isMutating}
                onSetStatus={(status) => statusMutation.mutate(status)}
              />
            )}
        </div>
      </div>
    </div>
  );
}
