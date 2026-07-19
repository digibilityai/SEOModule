import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { OwnerType, SeoWebsite } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { fetchWebsiteById } from "@/services/websiteService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { getCurrentSeoRole } from "@/services/supabase/seoWorkspaceService";
import {
  approveAuthorityCampaign,
  createAuthorityCampaign,
  fetchAuthorityCampaigns,
  fetchAuthorityOpportunities,
  fetchAuthorityOverview,
  fetchSpamRiskReview,
  rejectAuthorityCampaign,
  returnCampaignToDraft,
  submitAuthorityCampaignForApproval,
  transitionAuthorityOpportunity,
} from "@/services/offPageService";
import {
  findAccessibleWebsiteWithAuthorityData,
  type AuthorityOpportunityTransitionAction,
} from "@/services/supabase/seoOffPageAuthoritySupabaseService";
import { OFFPAGE_SAFETY_NOTICE } from "@/lib/safetyRules";
import { SafetyNotice } from "./shared/SafetyNotice";
import { AuthorityHeader } from "./offpage/AuthorityHeader";
import { SpamRiskReviewSection } from "./offpage/SpamRiskReviewSection";
import { OffPageFiltersBar } from "./offpage/OffPageFiltersBar";
import { OpportunityCard } from "./offpage/OpportunityCard";
import { CampaignBuilder } from "./offpage/CampaignBuilder";
import { CampaignList, CAMPAIGN_SUBMIT_ROLES } from "./offpage/CampaignList";

export function AuthorityBuilderPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [filter, setFilter] = useState("all");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [hasSearchedForAuthorityWebsite, setHasSearchedForAuthorityWebsite] = useState(false);
  const [authorityOverrideWebsite, setAuthorityOverrideWebsite] = useState<SeoWebsite | null>(null);

  // The website this page actually displays. Normally the app-wide active
  // website, but overridden (Supabase mode only, see effect below) when that
  // website has zero Off-Page Authority opportunities while a DIFFERENT
  // accessible website — possibly in another workspace entirely — has real
  // seeded data. Same page-local-override pattern as
  // DeclineDiagnosisPage.tsx's displayWebsite (Phase 14B.2) — never mutates
  // the shared ActiveWebsiteContext, which cannot represent a cross-workspace
  // switch.
  const displayWebsite = authorityOverrideWebsite ?? activeWebsite;

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", displayWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(displayWebsite!.id),
    enabled: !!displayWebsite,
  });
  const isOnboardingComplete = onboarding?.status === "completed";

  const { data: opportunities = [], isLoading: isLoadingOpportunities } = useQuery({
    queryKey: ["seo-authority-opportunities", displayWebsite?.id],
    queryFn: () => fetchAuthorityOpportunities(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: campaigns = [] } = useQuery({
    queryKey: ["seo-authority-campaigns", displayWebsite?.id],
    queryFn: () => fetchAuthorityCampaigns(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: overview } = useQuery({
    queryKey: ["seo-authority-overview", displayWebsite?.id, opportunities.length, campaigns.length],
    queryFn: () => fetchAuthorityOverview(displayWebsite!.id, displayWebsite!.website_url),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  const { data: spamRiskReviews = [] } = useQuery({
    queryKey: ["seo-spam-risk-review", displayWebsite?.id, opportunities.length],
    queryFn: () => fetchSpamRiskReview(displayWebsite!.id),
    enabled: !!displayWebsite && isOnboardingComplete,
  });

  // Phase 15C Step 1: the signed-in user's REAL seo_workspace_members.seo_role
  // for this website's workspace — the actual authorization source Stage 6's
  // RLS/RPCs check, via getCurrentSeoRole (read-only, added in the prior
  // step). Supabase mode only: mock mode has no seo_workspace_members rows
  // at all, so role gating is skipped there entirely (see
  // OpportunityCard.tsx's roleGatingActive) and every legal-by-status action
  // stays enabled, unchanged from the app's pre-existing mock behavior.
  const { data: currentSeoRole } = useQuery({
    queryKey: ["seo-current-role", displayWebsite?.workspace_id],
    queryFn: () => getCurrentSeoRole(displayWebsite!.workspace_id),
    enabled: !!displayWebsite && isSupabaseMode(),
  });

  // Supabase-mode-only safety net: the auto-selected active website can
  // legitimately have zero Off-Page Authority opportunities while a
  // DIFFERENT accessible website has real seeded data. Search every
  // workspace/website the current user can access instead of showing an
  // empty state (or an onboarding-incomplete block) for what's likely just
  // the wrong website. Mirrors DeclineDiagnosisPage.tsx's corrected effect
  // (Phase 14B.2 §11) from the start — it searches when EITHER the active
  // website's onboarding is incomplete (nothing to wait for) OR onboarding
  // is complete but there are zero opportunities once that query has
  // settled, so it can fire for the common case of an auto-selected,
  // never-onboarded smoke-test website. Runs at most once per page mount;
  // never touches mock mode.
  useEffect(() => {
    if (!isSupabaseMode()) return;
    if (isLoadingWebsite || isLoadingOnboarding || hasSearchedForAuthorityWebsite) return;
    if (!activeWebsite) return;
    if (isOnboardingComplete && (isLoadingOpportunities || opportunities.length > 0)) return;

    setHasSearchedForAuthorityWebsite(true);
    findAccessibleWebsiteWithAuthorityData().then(async (found) => {
      if (!found || found.websiteId === activeWebsite.id) return;
      const website = await fetchWebsiteById(found.websiteId);
      if (website) setAuthorityOverrideWebsite(website);
    });
  }, [
    isLoadingWebsite,
    isLoadingOnboarding,
    isOnboardingComplete,
    isLoadingOpportunities,
    hasSearchedForAuthorityWebsite,
    activeWebsite,
    opportunities.length,
  ]);

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ["seo-authority-opportunities", displayWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-authority-campaigns", displayWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-authority-overview", displayWebsite?.id] });
    queryClient.invalidateQueries({ queryKey: ["seo-spam-risk-review", displayWebsite?.id] });
  };

  const transitionMutation = useMutation({
    mutationFn: ({ id, action }: { id: string; action: AuthorityOpportunityTransitionAction }) =>
      transitionAuthorityOpportunity(id, action),
    onSuccess: invalidateAll,
  });

  const createCampaignMutation = useMutation({
    mutationFn: (input: { name: string; goal: string; owner: OwnerType; due_date?: string }) =>
      createAuthorityCampaign(displayWebsite!, { ...input, opportunity_ids: selectedIds }),
    onSuccess: () => {
      setSelectedIds([]);
      invalidateAll();
    },
  });

  // Phase 15D Step 2A: Draft -> Pending Approval only. Does not touch
  // transitionMutation (opportunity workflow) or createCampaignMutation.
  const submitCampaignMutation = useMutation({
    mutationFn: (id: string) => submitAuthorityCampaignForApproval(id, displayWebsite!.id),
    onSuccess: invalidateAll,
  });

  // Phase 15D Step 2B: Pending Approval -> Approved only. Does not touch
  // transitionMutation, createCampaignMutation, or submitCampaignMutation.
  const approveCampaignMutation = useMutation({
    mutationFn: (id: string) => approveAuthorityCampaign(id, displayWebsite!.id),
    onSuccess: invalidateAll,
  });

  // Phase 15D Step 2C: Pending Approval -> Rejected only. Does not touch
  // transitionMutation, createCampaignMutation, submitCampaignMutation, or
  // approveCampaignMutation.
  const rejectCampaignMutation = useMutation({
    mutationFn: (id: string) => rejectAuthorityCampaign(id, displayWebsite!.id),
    onSuccess: invalidateAll,
  });

  // Phase 15D Step 2D: Rejected -> Draft only. Does not touch
  // transitionMutation, createCampaignMutation, submitCampaignMutation,
  // approveCampaignMutation, or rejectCampaignMutation.
  const returnToDraftMutation = useMutation({
    mutationFn: (id: string) => returnCampaignToDraft(id, displayWebsite!.id),
    onSuccess: invalidateAll,
  });

  const toggleSelected = (id: string) => {
    setSelectedIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!displayWebsite) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Add a website first</CardTitle>
          <CardDescription>
            The Authority Builder is tied to a website. Add a website to get started.
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

  if (!onboarding || !isOnboardingComplete) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Complete business onboarding first</CardTitle>
          <CardDescription>
            The Authority Builder uses your business context to suggest relevant opportunities.
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

  if (isLoadingOpportunities) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (opportunities.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No authority opportunities yet</CardTitle>
          <CardDescription>
            Once opportunities are identified for {displayWebsite.name}, they'll show up here for
            review before any action is taken.
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const filteredOpportunities =
    filter === "all" ? opportunities : opportunities.filter((o) => o.opportunity_type === filter);
  const selectedOpportunities = opportunities.filter((o) => selectedIds.includes(o.id));

  // Phase 15D create-gating fix — campaign creation is an owner/admin/team_member
  // privilege (same CAMPAIGN_SUBMIT_ROLES the RPC enforces). Supabase mode only:
  // mock mode has no real seo_role, so creation stays enabled there (unchanged).
  const createRolePermitted =
    !isSupabaseMode() || (currentSeoRole != null && CAMPAIGN_SUBMIT_ROLES.includes(currentSeoRole));

  return (
    <div className="space-y-4">
      {overview && <AuthorityHeader website={displayWebsite} overview={overview} />}
      <SafetyNotice text={OFFPAGE_SAFETY_NOTICE} />
      <SpamRiskReviewSection reviews={spamRiskReviews} />

      {/* Phase 15C Step 1: a real seo_authority_opportunity_transition
          rejection (illegal transition, role denied, not found) is never
          masked by a mock fallback — see offPageService.runAuthorityOpportunityWrite
          / AuthorityOpportunityTransitionError. Surfaced here verbatim,
          matching the Phase 13D/13E non-masking-write contract. */}
      {transitionMutation.isError && (
        <Card className="border-destructive/40">
          <CardContent className="py-3 text-sm text-destructive">
            {(transitionMutation.error as Error)?.message ?? "The requested action was rejected."}
          </CardContent>
        </Card>
      )}

      {/* Phase 15D Step 1: a real campaign-creation rejection (RLS denial,
          junction/task insert failure after compensating cleanup) is never
          masked by a mock fallback — see offPageService.runAuthorityCampaignWrite
          / AuthorityCampaignCreationError. Same non-masking-write contract as
          the opportunity transition error above. */}
      {createCampaignMutation.isError && (
        <Card className="border-destructive/40">
          <CardContent className="py-3 text-sm text-destructive">
            {(createCampaignMutation.error as Error)?.message ?? "The campaign could not be created."}
          </CardContent>
        </Card>
      )}

      {/* Phase 15D Step 2A: a real seo_authority_campaign_transition rejection
          (illegal transition, role denied, not found) is never masked by a
          mock fallback — see offPageService.runAuthorityCampaignTransitionWrite
          / AuthorityCampaignTransitionError. Same non-masking-write contract
          as the two error blocks above. */}
      {submitCampaignMutation.isError && (
        <Card className="border-destructive/40">
          <CardContent className="py-3 text-sm text-destructive">
            {(submitCampaignMutation.error as Error)?.message ?? "The campaign could not be submitted for approval."}
          </CardContent>
        </Card>
      )}

      {/* Phase 15D Step 2B: a real seo_authority_campaign_transition rejection
          (illegal transition, role denied, not found) is never masked by a
          mock fallback — see offPageService.runAuthorityCampaignTransitionWrite
          / AuthorityCampaignTransitionError. Same non-masking-write contract
          as the three error blocks above. */}
      {approveCampaignMutation.isError && (
        <Card className="border-destructive/40">
          <CardContent className="py-3 text-sm text-destructive">
            {(approveCampaignMutation.error as Error)?.message ?? "The campaign could not be approved."}
          </CardContent>
        </Card>
      )}

      {/* Phase 15D Step 2C: a real seo_authority_campaign_transition rejection
          (illegal transition, role denied, not found) is never masked by a
          mock fallback — see offPageService.runAuthorityCampaignTransitionWrite
          / AuthorityCampaignTransitionError. Same non-masking-write contract
          as the four error blocks above. */}
      {rejectCampaignMutation.isError && (
        <Card className="border-destructive/40">
          <CardContent className="py-3 text-sm text-destructive">
            {(rejectCampaignMutation.error as Error)?.message ?? "The campaign could not be rejected."}
          </CardContent>
        </Card>
      )}

      {/* Phase 15D Step 2D: a real seo_authority_campaign_transition rejection
          (illegal transition, role denied, not found) is never masked by a
          mock fallback — see offPageService.runAuthorityCampaignTransitionWrite
          / AuthorityCampaignTransitionError. Same non-masking-write contract
          as the five error blocks above. */}
      {returnToDraftMutation.isError && (
        <Card className="border-destructive/40">
          <CardContent className="py-3 text-sm text-destructive">
            {(returnToDraftMutation.error as Error)?.message ?? "The campaign could not be returned to draft."}
          </CardContent>
        </Card>
      )}

      <OffPageFiltersBar active={filter} onChange={setFilter} />

      <div className="space-y-3">
        {filteredOpportunities.map((o) => (
          <OpportunityCard
            key={o.id}
            opportunity={o}
            isSelected={selectedIds.includes(o.id)}
            onToggleSelected={toggleSelected}
            onTransition={(id, action) => transitionMutation.mutate({ id, action })}
            isMutating={transitionMutation.isPending}
            role={currentSeoRole ?? null}
            roleGatingActive={isSupabaseMode()}
          />
        ))}
      </div>

      <CampaignBuilder
        selectedOpportunities={selectedOpportunities}
        onCreate={(input) => createCampaignMutation.mutate(input)}
        onClearSelection={() => setSelectedIds([])}
        isMutating={createCampaignMutation.isPending}
        createRolePermitted={createRolePermitted}
      />

      <h2 className="text-sm font-medium text-muted-foreground">Campaigns</h2>
      <CampaignList
        campaigns={campaigns}
        onSubmitForApproval={(id) => submitCampaignMutation.mutate(id)}
        onApprove={(id) => approveCampaignMutation.mutate(id)}
        onReject={(id) => rejectCampaignMutation.mutate(id)}
        onReturnToDraft={(id) => returnToDraftMutation.mutate(id)}
        isMutating={
          submitCampaignMutation.isPending ||
          approveCampaignMutation.isPending ||
          rejectCampaignMutation.isPending ||
          returnToDraftMutation.isPending
        }
        role={currentSeoRole ?? null}
        roleGatingActive={isSupabaseMode()}
      />
    </div>
  );
}
