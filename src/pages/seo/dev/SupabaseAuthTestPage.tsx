import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  checkSeoAccessForCurrentUser,
  checkWorkspaceAccessForCurrentUser,
  getDevAuthState,
  signInDevUser,
  signOutDevUser,
  type DevAuthState,
  type SeoAccessCheckResult,
  type WorkspaceAccessCheckResult,
} from "@/services/supabase/supabaseDevAuthService";
import type { SeoUserRole, SeoWebsite } from "@/types";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";
import { addWebsite, fetchWebsiteById, fetchWebsites } from "@/services/websiteService";
import { fetchOnboardingByWebsiteId } from "@/services/businessOnboardingService";
import { getCurrentSeoRole, getCurrentSeoWorkspace } from "@/services/supabase/seoWorkspaceService";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import { fetchAudits, fetchIssuesForAudit, fetchLatestAudit, runAudit } from "@/services/auditService";
import { fetchRecommendations } from "@/services/recommendationService";
import {
  addApprovalComment,
  ensureApprovalQueueGenerated,
  fetchApprovalQueue,
  updateApprovalItemFields,
} from "@/services/approvalService";
import {
  createCustomContentOpportunity,
  fetchContentOpportunities,
  fetchDraft,
  fetchKeywordPlan,
  fetchWireframe,
  startContentPlan,
} from "@/services/contentStudioService";
import { fetchPendingApprovalsSummary, fetchTopPriorityFixes } from "@/services/dashboardService";
import { fetchAdminPreviewSummary, type AdminPreviewSummary } from "@/services/adminPreviewSummaryService";
import { fetchPagePerformance } from "@/services/performanceService";
import {
  fetchSupabaseLatestPerformance,
  fetchSupabasePerformanceHistory,
  findAccessibleWebsiteWithPerformanceData,
  type WebsiteWithPerformanceData,
} from "@/services/supabase/seoPagePerformanceSupabaseService";
import {
  fetchSupabaseCurrentDiagnosisRows,
  fetchSupabaseDiagnosisEvidence,
  findAccessibleWebsiteWithDeclineDiagnosisData,
  type WebsiteWithDeclineDiagnosisData,
} from "@/services/supabase/seoDeclineDiagnosisSupabaseService";
import {
  fetchSupabaseAuthorityActivity,
  fetchSupabaseAuthorityCampaignRows,
  fetchSupabaseAuthorityOpportunityRows,
  findAccessibleWebsiteWithAuthorityData,
  type WebsiteWithAuthorityData,
} from "@/services/supabase/seoOffPageAuthoritySupabaseService";
import {
  fetchSupabaseContentGapRows,
  fetchSupabaseMentionRows,
  fetchSupabasePromptTrackingRows,
  findAccessibleWebsiteWithAiVisibilityData,
  type WebsiteWithAiVisibilityData,
} from "@/services/supabase/seoAiVisibilitySupabaseService";
import { MOCK_CURRENT_ROLE, MOCK_WORKSPACE_ID } from "@/mocks/mockContext";

interface WebsiteTestResult {
  count: number;
  // Full website object (not just id/url) so it can also be passed straight
  // into ensureApprovalQueueGenerated() for the Phase 13D approval check.
  firstWebsite: SeoWebsite | null;
}

interface OnboardingTestResult {
  found: boolean;
  websiteId: string;
}

interface AuditTestResult {
  count: number;
  latestStatus: string | null;
}

interface RecommendationTestResult {
  count: number;
}

interface ApprovalTestResult {
  count: number;
  firstItem: { id: string; status: string } | null;
}

interface ContentOpportunityTestResult {
  count: number;
  firstOpportunity: { id: string; title: string; status: string } | null;
}

interface ContentDetailTestResult {
  hasKeywordPlan: boolean;
  hasWireframe: boolean;
  hasDraft: boolean;
  sectionCount: number;
}

interface PagePerformanceTestResult {
  count: number;
  improvingCount: number;
  stableCount: number;
  decliningCount: number;
  needsRefreshCount: number;
  notEnoughDataCount: number;
  firstPageId: string | null;
}

interface PagePerformanceLatestViewTestResult {
  rowCount: number;
  movementCounts: Record<string, number>;
}

interface DeclineDiagnosisTestResult {
  count: number;
  typeCounts: Record<string, number>;
  firstDiagnosisId: string | null;
  firstDiagnosisType: string | null;
  firstDiagnosisSeverity: string | null;
  firstDiagnosisStatus: string | null;
  firstDiagnosisSummary: string | null;
}

interface DiagnosisEvidenceTestResult {
  count: number;
  firstEvidenceSummary: string | null;
}

interface AuthorityTestResult {
  requestedWebsiteId: string | null;
  opportunityCount: number;
  statusCounts: Record<string, number>;
  campaignCount: number;
  activityCount: number;
  firstOpportunityTitle: string | null;
}

interface AiVisibilityTestResult {
  requestedWebsiteId: string | null;
  promptCount: number;
  visibilityCounts: Record<string, number>;
  contentGapCount: number;
  mentionCount: number;
  mentionTypeCounts: Record<string, number>;
}

// One captured Supabase error from a single diagnostic step below — never
// invented, only ever populated from a real caught error via
// normalizeSupabaseError(). `code` is frequently null because the existing
// service-layer helpers (safeList/safeSingle) already re-wrap PostgREST
// errors into a plain Error with only a message by the time they reach here
// — this is displayed honestly as "—" rather than fabricated.
interface Stage6DiagnosticError {
  step: string;
  code: string | null;
  message: string;
}

// Read-only snapshot of how the two Stage 6 cross-workspace finders would
// resolve a website for AuthorityBuilderPage.tsx / AiVisibilityPage.tsx
// *right now*, for a developer debugging "why is the wrong website showing"
// without needing to load either real page. Nothing here is stored,
// mutated, or written back into shared app state — see
// handleRunStage6ResolutionDiagnostics.
interface Stage6ResolutionDiagnosticsResult {
  userEmail: string | null;
  userId: string | null;
  dataMode: string;
  resolvedWorkspaceId: string | null;
  resolvedWorkspaceReason: string | null;
  activeWebsiteId: string | null;
  activeWebsiteUrl: string | null;
  offPageFallbackRan: boolean;
  offPageRequestedWebsiteId: string | null;
  offPageCandidateWebsiteId: string | null;
  offPageCandidateCount: number;
  aiVisibilityFallbackRan: boolean;
  aiVisibilityRequestedWebsiteId: string | null;
  aiVisibilityCandidateWebsiteId: string | null;
  aiVisibilityCandidateCount: number;
  noRlsVisibleStage6Website: boolean;
  /** Workspace id passed into getCurrentSeoRole(); null = lookup skipped (no resolved workspace). */
  roleLookupWorkspaceId: string | null;
  /** The real seo_workspace_members.seo_role for roleLookupWorkspaceId; null = lookup ran but found no active membership row, or was skipped. */
  resolvedSeoRole: SeoUserRole | null;
  /** true = the lookup was attempted and threw; see `errors` for the exact message. */
  roleLookupFailed: boolean;
  errors: Stage6DiagnosticError[];
}

interface DashboardSummaryTestResult {
  topPriorityFixesCount: number;
  pendingApprovalsCount: number;
  expertReviewCount: number;
  developerNeededCount: number;
}

const DEFAULT_TEST_WEBSITE_URL = "https://example-dev-seo-test.local";

// Deliberately loose — this only needs to catch "obviously not an email yet"
// while typing, not fully validate RFC 5322. Real validation happens
// server-side when supabase.auth.signInWithPassword() is called.
const EMAIL_LOOKS_VALID_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function emailLooksValid(value: string): boolean {
  return EMAIL_LOOKS_VALID_PATTERN.test(value.trim());
}

// Development-only Supabase Auth test harness (Phase 13B.1). Reachable only
// by navigating directly to /seo/dev/auth-test — not in the sidebar or
// module registry, and not linked from any customer-facing page. Lets a
// developer sign in with a real email/password against the configured TEST
// Supabase project to exercise authenticated RLS behavior for the Website +
// Business Onboarding wiring (Phase 13B). No fake auth, no hardcoded users,
// no user creation, no service role key — same anon client as the rest of
// the app. See PHASE_13B1_DEV_AUTH_TEST_NOTES.md.
export function SupabaseAuthTestPage() {
  const [authState, setAuthState] = useState<DevAuthState | null>(null);
  const [seoAccess, setSeoAccess] = useState<SeoAccessCheckResult | null>(null);
  const [workspaceAccess, setWorkspaceAccess] = useState<WorkspaceAccessCheckResult | null>(null);
  const [isLoadingState, setIsLoadingState] = useState(true);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isSigningIn, setIsSigningIn] = useState(false);
  const [signInWarning, setSignInWarning] = useState<string | null>(null);
  const [isSigningOut, setIsSigningOut] = useState(false);
  const [signOutWarning, setSignOutWarning] = useState<string | null>(null);

  const [websiteTest, setWebsiteTest] = useState<WebsiteTestResult | null>(null);
  const [isTestingWebsites, setIsTestingWebsites] = useState(false);
  const [websiteTestWarning, setWebsiteTestWarning] = useState<string | null>(null);

  const [onboardingTest, setOnboardingTest] = useState<OnboardingTestResult | null>(null);
  const [isTestingOnboarding, setIsTestingOnboarding] = useState(false);
  const [onboardingTestWarning, setOnboardingTestWarning] = useState<string | null>(null);

  const [newWebsiteUrl, setNewWebsiteUrl] = useState(DEFAULT_TEST_WEBSITE_URL);
  const [isCreatingWebsite, setIsCreatingWebsite] = useState(false);
  const [createWebsiteWarning, setCreateWebsiteWarning] = useState<string | null>(null);
  const [createWebsiteResult, setCreateWebsiteResult] = useState<string | null>(null);

  const [auditTest, setAuditTest] = useState<AuditTestResult | null>(null);
  const [isTestingAudit, setIsTestingAudit] = useState(false);
  const [auditTestWarning, setAuditTestWarning] = useState<string | null>(null);

  const [recommendationTest, setRecommendationTest] = useState<RecommendationTestResult | null>(null);
  const [isTestingRecommendation, setIsTestingRecommendation] = useState(false);
  const [recommendationTestWarning, setRecommendationTestWarning] = useState<string | null>(null);

  const [runAuditTestResult, setRunAuditTestResult] = useState<string | null>(null);
  const [isRunningTestAudit, setIsRunningTestAudit] = useState(false);
  const [runAuditTestWarning, setRunAuditTestWarning] = useState<string | null>(null);

  const [approvalTest, setApprovalTest] = useState<ApprovalTestResult | null>(null);
  const [isTestingApproval, setIsTestingApproval] = useState(false);
  const [approvalTestWarning, setApprovalTestWarning] = useState<string | null>(null);

  const [approvalCommentTestResult, setApprovalCommentTestResult] = useState<string | null>(null);
  const [isTestingApprovalComment, setIsTestingApprovalComment] = useState(false);
  const [approvalCommentTestWarning, setApprovalCommentTestWarning] = useState<string | null>(null);

  const [approvalTransitionResult, setApprovalTransitionResult] = useState<string | null>(null);
  const [isRunningApprovalTransition, setIsRunningApprovalTransition] = useState(false);
  const [approvalTransitionWarning, setApprovalTransitionWarning] = useState<string | null>(null);

  const [contentOpportunityTest, setContentOpportunityTest] = useState<ContentOpportunityTestResult | null>(
    null,
  );
  const [isTestingContentOpportunity, setIsTestingContentOpportunity] = useState(false);
  const [contentOpportunityTestWarning, setContentOpportunityTestWarning] = useState<string | null>(null);

  const [contentDetailTest, setContentDetailTest] = useState<ContentDetailTestResult | null>(null);
  const [isTestingContentDetail, setIsTestingContentDetail] = useState(false);
  const [contentDetailTestWarning, setContentDetailTestWarning] = useState<string | null>(null);

  const [createContentOpportunityResult, setCreateContentOpportunityResult] = useState<string | null>(
    null,
  );
  const [isCreatingContentOpportunity, setIsCreatingContentOpportunity] = useState(false);
  const [createContentOpportunityWarning, setCreateContentOpportunityWarning] = useState<string | null>(
    null,
  );

  const [contentTransitionResult, setContentTransitionResult] = useState<string | null>(null);
  const [isRunningContentTransition, setIsRunningContentTransition] = useState(false);
  const [contentTransitionWarning, setContentTransitionWarning] = useState<string | null>(null);

  const [dashboardSummaryTest, setDashboardSummaryTest] = useState<DashboardSummaryTestResult | null>(
    null,
  );
  const [isTestingDashboardSummary, setIsTestingDashboardSummary] = useState(false);
  const [dashboardSummaryTestWarning, setDashboardSummaryTestWarning] = useState<string | null>(null);

  const [adminPreviewSummaryTest, setAdminPreviewSummaryTest] = useState<AdminPreviewSummary | null>(
    null,
  );
  const [isTestingAdminPreviewSummary, setIsTestingAdminPreviewSummary] = useState(false);
  const [adminPreviewSummaryTestWarning, setAdminPreviewSummaryTestWarning] = useState<string | null>(
    null,
  );

  const [pagePerformanceTest, setPagePerformanceTest] = useState<PagePerformanceTestResult | null>(null);
  const [isTestingPagePerformance, setIsTestingPagePerformance] = useState(false);
  const [pagePerformanceTestWarning, setPagePerformanceTestWarning] = useState<string | null>(null);

  const [pagePerformanceLatestViewTest, setPagePerformanceLatestViewTest] =
    useState<PagePerformanceLatestViewTestResult | null>(null);
  const [isTestingPagePerformanceLatestView, setIsTestingPagePerformanceLatestView] = useState(false);
  const [pagePerformanceLatestViewTestWarning, setPagePerformanceLatestViewTestWarning] = useState<
    string | null
  >(null);

  const [pagePerformanceHistoryTestResult, setPagePerformanceHistoryTestResult] = useState<
    string | null
  >(null);
  const [isTestingPagePerformanceHistory, setIsTestingPagePerformanceHistory] = useState(false);
  const [pagePerformanceHistoryTestWarning, setPagePerformanceHistoryTestWarning] = useState<
    string | null
  >(null);

  const [performanceBackedWebsite, setPerformanceBackedWebsite] =
    useState<WebsiteWithPerformanceData | null>(null);
  const [isFindingPerformanceWebsite, setIsFindingPerformanceWebsite] = useState(false);
  const [findPerformanceWebsiteWarning, setFindPerformanceWebsiteWarning] = useState<string | null>(
    null,
  );

  const [diagnosisBackedWebsite, setDiagnosisBackedWebsite] =
    useState<WebsiteWithDeclineDiagnosisData | null>(null);
  const [isFindingDiagnosisWebsite, setIsFindingDiagnosisWebsite] = useState(false);
  const [findDiagnosisWebsiteWarning, setFindDiagnosisWebsiteWarning] = useState<string | null>(null);

  const [declineDiagnosisTest, setDeclineDiagnosisTest] = useState<DeclineDiagnosisTestResult | null>(
    null,
  );
  const [isTestingDeclineDiagnosis, setIsTestingDeclineDiagnosis] = useState(false);
  const [declineDiagnosisTestWarning, setDeclineDiagnosisTestWarning] = useState<string | null>(null);

  const [diagnosisEvidenceTest, setDiagnosisEvidenceTest] = useState<DiagnosisEvidenceTestResult | null>(
    null,
  );
  const [isTestingDiagnosisEvidence, setIsTestingDiagnosisEvidence] = useState(false);
  const [diagnosisEvidenceTestWarning, setDiagnosisEvidenceTestWarning] = useState<string | null>(null);

  const [authorityBackedWebsite, setAuthorityBackedWebsite] = useState<WebsiteWithAuthorityData | null>(
    null,
  );
  const [isFindingAuthorityWebsite, setIsFindingAuthorityWebsite] = useState(false);
  const [findAuthorityWebsiteWarning, setFindAuthorityWebsiteWarning] = useState<string | null>(null);

  const [authorityTest, setAuthorityTest] = useState<AuthorityTestResult | null>(null);
  const [isTestingAuthority, setIsTestingAuthority] = useState(false);
  const [authorityTestWarning, setAuthorityTestWarning] = useState<string | null>(null);

  const [aiVisibilityBackedWebsite, setAiVisibilityBackedWebsite] =
    useState<WebsiteWithAiVisibilityData | null>(null);
  const [isFindingAiVisibilityWebsite, setIsFindingAiVisibilityWebsite] = useState(false);
  const [findAiVisibilityWebsiteWarning, setFindAiVisibilityWebsiteWarning] = useState<string | null>(
    null,
  );

  const [aiVisibilityTest, setAiVisibilityTest] = useState<AiVisibilityTestResult | null>(null);
  const [isTestingAiVisibility, setIsTestingAiVisibility] = useState(false);
  const [aiVisibilityTestWarning, setAiVisibilityTestWarning] = useState<string | null>(null);

  const [stage6ResolutionDiagnostics, setStage6ResolutionDiagnostics] =
    useState<Stage6ResolutionDiagnosticsResult | null>(null);
  const [isRunningStage6ResolutionDiagnostics, setIsRunningStage6ResolutionDiagnostics] = useState(false);
  const [stage6ResolutionDiagnosticsWarning, setStage6ResolutionDiagnosticsWarning] = useState<
    string | null
  >(null);

  // Read-only context accessor — unlike useResolvedActiveWebsite(), this does
  // NOT auto-select/persist a website on mount. Used below purely to READ
  // whatever active website id (if any) is already resolved elsewhere in the
  // app; this page never calls setActiveWebsiteId.
  const { activeWebsiteId } = useActiveWebsite();

  async function loadAuthAndAccessState() {
    setIsLoadingState(true);
    const nextAuthState = await getDevAuthState();
    setAuthState(nextAuthState);

    if (nextAuthState.hasSession) {
      const [nextSeoAccess, nextWorkspaceAccess] = await Promise.all([
        checkSeoAccessForCurrentUser(),
        checkWorkspaceAccessForCurrentUser(),
      ]);
      setSeoAccess(nextSeoAccess);
      setWorkspaceAccess(nextWorkspaceAccess);
    } else {
      setSeoAccess(null);
      setWorkspaceAccess(null);
    }
    setIsLoadingState(false);
  }

  useEffect(() => {
    loadAuthAndAccessState();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!import.meta.env.DEV) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Not available</CardTitle>
          <CardDescription>This diagnostics page is development-only.</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const handleSignIn = async () => {
    setIsSigningIn(true);
    setSignInWarning(null);
    const result = await signInDevUser(email, password);
    // Never keep the password in state after submit, success or failure.
    setPassword("");
    if (!result.success) {
      setSignInWarning(result.warning ?? "Sign-in failed.");
    } else {
      setSignInWarning(null);
      await loadAuthAndAccessState();
    }
    setIsSigningIn(false);
  };

  const handleSignOut = async () => {
    setIsSigningOut(true);
    setSignOutWarning(null);
    const result = await signOutDevUser();
    if (!result.success) {
      setSignOutWarning(result.warning ?? "Sign-out failed.");
    }
    // Previous session's test results no longer apply either way.
    setWebsiteTest(null);
    setOnboardingTest(null);
    setCreateWebsiteResult(null);
    setAuditTest(null);
    setRecommendationTest(null);
    setRunAuditTestResult(null);
    setApprovalTest(null);
    setApprovalCommentTestResult(null);
    setApprovalTransitionResult(null);
    setContentOpportunityTest(null);
    setContentDetailTest(null);
    setCreateContentOpportunityResult(null);
    setContentTransitionResult(null);
    setDashboardSummaryTest(null);
    setAdminPreviewSummaryTest(null);
    setPagePerformanceTest(null);
    setPagePerformanceLatestViewTest(null);
    setPagePerformanceHistoryTestResult(null);
    setPerformanceBackedWebsite(null);
    setFindPerformanceWebsiteWarning(null);
    setDiagnosisBackedWebsite(null);
    setFindDiagnosisWebsiteWarning(null);
    setDeclineDiagnosisTest(null);
    setDeclineDiagnosisTestWarning(null);
    setDiagnosisEvidenceTest(null);
    setDiagnosisEvidenceTestWarning(null);
    await loadAuthAndAccessState();
    setIsSigningOut(false);
  };

  const handleTestWebsites = async () => {
    setIsTestingWebsites(true);
    setWebsiteTestWarning(null);
    try {
      const websites = await fetchWebsites(MOCK_WORKSPACE_ID);
      setWebsiteTest({
        count: websites.length,
        firstWebsite: websites[0] ?? null,
      });
    } catch (error) {
      setWebsiteTestWarning(error instanceof Error ? error.message : "Website service check failed.");
    }
    setIsTestingWebsites(false);
  };

  const handleTestOnboarding = async () => {
    const websiteId = websiteTest?.firstWebsite?.id;
    if (!websiteId) return;
    setIsTestingOnboarding(true);
    setOnboardingTestWarning(null);
    try {
      const onboarding = await fetchOnboardingByWebsiteId(websiteId);
      setOnboardingTest({ found: Boolean(onboarding), websiteId });
    } catch (error) {
      setOnboardingTestWarning(
        error instanceof Error ? error.message : "Onboarding service check failed.",
      );
    }
    setIsTestingOnboarding(false);
  };

  const handleTestAuditService = async () => {
    const websiteId = websiteTest?.firstWebsite?.id;
    if (!websiteId) return;
    setIsTestingAudit(true);
    setAuditTestWarning(null);
    try {
      const [audits, latest] = await Promise.all([
        fetchAudits(websiteId),
        fetchLatestAudit(websiteId),
      ]);
      setAuditTest({ count: audits.length, latestStatus: latest?.status ?? null });
    } catch (error) {
      setAuditTestWarning(error instanceof Error ? error.message : "Audit service check failed.");
    }
    setIsTestingAudit(false);
  };

  const handleTestRecommendationService = async () => {
    const websiteId = websiteTest?.firstWebsite?.id;
    if (!websiteId) return;
    setIsTestingRecommendation(true);
    setRecommendationTestWarning(null);
    try {
      const recommendations = await fetchRecommendations(websiteId);
      setRecommendationTest({ count: recommendations.length });
    } catch (error) {
      setRecommendationTestWarning(
        error instanceof Error ? error.message : "Recommendation service check failed.",
      );
    }
    setIsTestingRecommendation(false);
  };

  // Dev-only: triggers a real audit run. In Supabase mode this calls the
  // Stage 2 seo_run_audit RPC, which only creates a "running" row (no
  // crawler exists) — no external crawling, no deletes, ever. In mock mode
  // it runs the existing simulated audit exactly as the real Audit page does.
  const handleRunTestAudit = async () => {
    const website = websiteTest?.firstWebsite;
    if (!website) return;
    setIsRunningTestAudit(true);
    setRunAuditTestWarning(null);
    setRunAuditTestResult(null);
    try {
      const result = await runAudit(website.id, website.website_url);
      setRunAuditTestResult(
        `Audit run status: ${result.audit.status} (id: ${result.audit.id}, issues: ${result.issues.length}).`,
      );
    } catch (error) {
      setRunAuditTestWarning(error instanceof Error ? error.message : "Run audit failed.");
    }
    setIsRunningTestAudit(false);
  };

  // Mirrors ApprovalQueuePage's own query chain: recommendations + issues →
  // ensure approval items exist for them → read the queue. On a fresh
  // Supabase test site (no crawler, so no issues/recommendations exist yet
  // — see Phase 13C notes) this legitimately reports 0 items; that's an
  // empty state, not a failure.
  const handleTestApprovalService = async () => {
    const website = websiteTest?.firstWebsite;
    if (!website) return;
    setIsTestingApproval(true);
    setApprovalTestWarning(null);
    try {
      const [recommendations, latestAudit] = await Promise.all([
        fetchRecommendations(website.id),
        fetchLatestAudit(website.id),
      ]);
      const issues =
        latestAudit && latestAudit.status === "completed"
          ? await fetchIssuesForAudit(latestAudit.id)
          : [];
      if (recommendations.length > 0) {
        await ensureApprovalQueueGenerated(website, recommendations, issues);
      }
      const items = await fetchApprovalQueue(website.id);
      setApprovalTest({
        count: items.length,
        firstItem: items[0] ? { id: items[0].id, status: items[0].status } : null,
      });
    } catch (error) {
      setApprovalTestWarning(
        error instanceof Error ? error.message : "Approval service check failed.",
      );
    }
    setIsTestingApproval(false);
  };

  // Adds a comment via the RPC's "comment" action (Supabase mode) or the
  // mock adapter. The role shown here is only ever a request — Stage 2
  // always stamps comments with the caller's real workspace role.
  const handleTestApprovalComment = async () => {
    const itemId = approvalTest?.firstItem?.id;
    if (!itemId) return;
    setIsTestingApprovalComment(true);
    setApprovalCommentTestWarning(null);
    try {
      const updated = await addApprovalComment(itemId, {
        author_role: MOCK_CURRENT_ROLE,
        comment_text: "Dev harness test comment (Phase 13D) — safe to ignore.",
      });
      setApprovalCommentTestResult(
        updated
          ? `Comment added — item now has ${updated.comments.length} comment(s).`
          : "No item returned.",
      );
    } catch (error) {
      setApprovalCommentTestWarning(
        error instanceof Error ? error.message : "Approval comment check failed.",
      );
    }
    setIsTestingApprovalComment(false);
  };

  // Dev-only: applies ONE harmless, reversible transition ("Request expert
  // review") via seo_approval_transition — the only action the RPC allows
  // for every role (owner/admin/team_member/client), so it never fails on
  // role grounds regardless of which test user is signed in. No delete, no
  // publish, no external call. A real backend rejection (e.g. unexpected
  // role/risk denial) is shown as-is, not silently swallowed — see
  // approvalService.ts's runApprovalWrite().
  const handleRunSafeApprovalTransition = async () => {
    const itemId = approvalTest?.firstItem?.id;
    if (!itemId) return;
    setIsRunningApprovalTransition(true);
    setApprovalTransitionWarning(null);
    setApprovalTransitionResult(null);
    try {
      const updated = await updateApprovalItemFields(itemId, { status: "expert_review_requested" });
      setApprovalTransitionResult(
        updated ? `Transition applied — new status: ${updated.status}.` : "No item returned.",
      );
    } catch (error) {
      setApprovalTransitionWarning(
        error instanceof Error ? error.message : "Approval transition failed.",
      );
    }
    setIsRunningApprovalTransition(false);
  };

  const handleTestContentOpportunityService = async () => {
    const website = websiteTest?.firstWebsite;
    if (!website) return;
    setIsTestingContentOpportunity(true);
    setContentOpportunityTestWarning(null);
    try {
      const opportunities = await fetchContentOpportunities(website.id);
      setContentOpportunityTest({
        count: opportunities.length,
        firstOpportunity: opportunities[0]
          ? { id: opportunities[0].id, title: opportunities[0].title, status: opportunities[0].status }
          : null,
      });
    } catch (error) {
      setContentOpportunityTestWarning(
        error instanceof Error ? error.message : "Content opportunity service check failed.",
      );
    }
    setIsTestingContentOpportunity(false);
  };

  const handleTestContentDetailService = async () => {
    const opportunityId = contentOpportunityTest?.firstOpportunity?.id;
    if (!opportunityId) return;
    setIsTestingContentDetail(true);
    setContentDetailTestWarning(null);
    try {
      const [keywordPlan, wireframe, draft] = await Promise.all([
        fetchKeywordPlan(opportunityId),
        fetchWireframe(opportunityId),
        fetchDraft(opportunityId),
      ]);
      setContentDetailTest({
        hasKeywordPlan: Boolean(keywordPlan),
        hasWireframe: Boolean(wireframe),
        hasDraft: Boolean(draft),
        sectionCount: draft?.sections.length ?? 0,
      });
    } catch (error) {
      setContentDetailTestWarning(
        error instanceof Error ? error.message : "Content detail service check failed.",
      );
    }
    setIsTestingContentDetail(false);
  };

  // Dev-only: direct insert-only creation (no LLM, no crawling, no deletes).
  const handleCreateDevContentOpportunity = async () => {
    const website = websiteTest?.firstWebsite;
    if (!website) return;
    setIsCreatingContentOpportunity(true);
    setCreateContentOpportunityWarning(null);
    setCreateContentOpportunityResult(null);
    try {
      const created = await createCustomContentOpportunity(website, {
        title: "Dev Test Content Opportunity",
        target_keyword: "dev test keyword",
      });
      setCreateContentOpportunityResult(
        `Created: "${created.title}" (id: ${created.id}, status: ${created.status})`,
      );
    } catch (error) {
      setCreateContentOpportunityWarning(
        error instanceof Error ? error.message : "Create content opportunity failed.",
      );
    }
    setIsCreatingContentOpportunity(false);
  };

  // Dev-only: applies ONE safe, early transition (idea → plan_ready via
  // startContentPlan, using the Stage 3 seo_content_transition RPC). No LLM,
  // no crawling, no publish, no deletes. A real backend rejection is shown
  // as-is, not silently swallowed — see contentStudioService.ts's
  // runContentWrite().
  const handleRunSafeContentTransition = async () => {
    const opportunityId = contentOpportunityTest?.firstOpportunity?.id;
    if (!opportunityId) return;
    setIsRunningContentTransition(true);
    setContentTransitionWarning(null);
    setContentTransitionResult(null);
    try {
      const updated = await startContentPlan(opportunityId);
      setContentTransitionResult(
        updated ? `Transition applied — new status: ${updated.status}.` : "No opportunity returned.",
      );
    } catch (error) {
      setContentTransitionWarning(
        error instanceof Error ? error.message : "Content transition failed.",
      );
    }
    setIsRunningContentTransition(false);
  };

  // Phase 13F, read-only: exercises the two dashboard summary reads
  // (top priority fixes + pending approvals) for the first known website.
  // No writes.
  const handleTestDashboardSummary = async () => {
    const website = websiteTest?.firstWebsite;
    if (!website) return;
    setIsTestingDashboardSummary(true);
    setDashboardSummaryTestWarning(null);
    try {
      const [fixes, approvalsSummary] = await Promise.all([
        fetchTopPriorityFixes(website.id),
        fetchPendingApprovalsSummary(website.id, website.website_url),
      ]);
      setDashboardSummaryTest({
        topPriorityFixesCount: fixes.length,
        pendingApprovalsCount: approvalsSummary.pending_count,
        expertReviewCount: approvalsSummary.expert_review_count,
        developerNeededCount: approvalsSummary.developer_needed_count,
      });
    } catch (error) {
      setDashboardSummaryTestWarning(
        error instanceof Error ? error.message : "Dashboard summary service check failed.",
      );
    }
    setIsTestingDashboardSummary(false);
  };

  // Phase 13F, read-only: exercises the admin-preview composition summary.
  // No website prerequisite — it resolves its own website list internally.
  // No writes, no role/billing data.
  const handleTestAdminPreviewSummary = async () => {
    setIsTestingAdminPreviewSummary(true);
    setAdminPreviewSummaryTestWarning(null);
    try {
      const summary = await fetchAdminPreviewSummary();
      setAdminPreviewSummaryTest(summary);
    } catch (error) {
      setAdminPreviewSummaryTestWarning(
        error instanceof Error ? error.message : "Admin preview summary service check failed.",
      );
    }
    setIsTestingAdminPreviewSummary(false);
  };

  // Read-only, Supabase-only diagnostic: searches every SEO workspace/website
  // the signed-in user can access (not just the "current" one
  // getCurrentSeoWorkspace defaults to) for the first one with real Stage 4
  // performance rows. Fixes the live-test gap where getCurrentSeoWorkspace
  // resolves to a newer disposable smoke-test workspace instead of the
  // workspace holding the actual seeded Page Performance data. When found,
  // the three Page Performance buttons below prefer this website over
  // "Test website service"'s auto-resolved one.
  const handleFindPerformanceWebsite = async () => {
    setIsFindingPerformanceWebsite(true);
    setFindPerformanceWebsiteWarning(null);
    try {
      const found = await findAccessibleWebsiteWithPerformanceData();
      setPerformanceBackedWebsite(found);
      if (!found) {
        setFindPerformanceWebsiteWarning(
          "No accessible workspace/website has Page Performance rows yet.",
        );
      }
    } catch (error) {
      setFindPerformanceWebsiteWarning(
        error instanceof Error ? error.message : "Find performance website check failed.",
      );
    }
    setIsFindingPerformanceWebsite(false);
  };

  // Phase 14A.2, read-only: exercises the adapter-wired app-facing page
  // performance read exactly as PagePerformancePage does. No writes.
  // Prefers the performance-backed website found above (if any) over the
  // generic "Test website service" auto-resolved website, since the latter
  // may legitimately have zero performance rows (see handleFindPerformanceWebsite).
  const handleTestPagePerformance = async () => {
    const website = performanceBackedWebsite
      ? { id: performanceBackedWebsite.websiteId }
      : websiteTest?.firstWebsite;
    if (!website) return;
    setIsTestingPagePerformance(true);
    setPagePerformanceTestWarning(null);
    try {
      const pages = await fetchPagePerformance(website.id);
      setPagePerformanceTest({
        count: pages.length,
        improvingCount: pages.filter((p) => p.performance_status === "improving").length,
        stableCount: pages.filter((p) => p.performance_status === "stable").length,
        decliningCount: pages.filter((p) => p.performance_status === "declining").length,
        needsRefreshCount: pages.filter((p) => p.performance_status === "needs_refresh").length,
        notEnoughDataCount: pages.filter((p) => p.performance_status === "not_enough_data").length,
        firstPageId: pages[0]?.id ?? null,
      });
    } catch (error) {
      setPagePerformanceTestWarning(
        error instanceof Error ? error.message : "Page performance service check failed.",
      );
    }
    setIsTestingPagePerformance(false);
  };

  // Phase 14A.2, read-only, Supabase-only diagnostic: calls the Stage 4
  // seo_page_performance_latest VIEW directly (not through the adapter) to
  // prove the view + its RLS work, independent of the flattening logic
  // above. In mock mode (or without a session) this throws a clear "no
  // authenticated Supabase user" error, shown as a warning below — there is
  // no mock equivalent of "the Supabase view," by design.
  const handleTestPagePerformanceLatestView = async () => {
    const website = performanceBackedWebsite
      ? { id: performanceBackedWebsite.websiteId }
      : websiteTest?.firstWebsite;
    if (!website) return;
    setIsTestingPagePerformanceLatestView(true);
    setPagePerformanceLatestViewTestWarning(null);
    try {
      const rows = await fetchSupabaseLatestPerformance(website.id);
      const movementCounts = rows.reduce<Record<string, number>>((acc, row) => {
        acc[row.movement_status] = (acc[row.movement_status] ?? 0) + 1;
        return acc;
      }, {});
      setPagePerformanceLatestViewTest({ rowCount: rows.length, movementCounts });
    } catch (error) {
      setPagePerformanceLatestViewTestWarning(
        error instanceof Error
          ? error.message
          : "Page performance latest-view check failed (expected in mock mode or without a Supabase session).",
      );
    }
    setIsTestingPagePerformanceLatestView(false);
  };

  // Phase 14A.2, read-only, Supabase-only diagnostic: reads raw snapshot
  // history (page-level aggregate) for the first page found by the button
  // above. Same "no mock equivalent" caveat as the latest-view check.
  const handleTestPagePerformanceHistory = async () => {
    const pageId = pagePerformanceTest?.firstPageId;
    if (!pageId) return;
    setIsTestingPagePerformanceHistory(true);
    setPagePerformanceHistoryTestWarning(null);
    setPagePerformanceHistoryTestResult(null);
    try {
      const rows = await fetchSupabasePerformanceHistory(pageId);
      setPagePerformanceHistoryTestResult(`${rows.length} page-level snapshot(s) found for this page.`);
    } catch (error) {
      setPagePerformanceHistoryTestWarning(
        error instanceof Error
          ? error.message
          : "Page performance history check failed (expected in mock mode or without a Supabase session).",
      );
    }
    setIsTestingPagePerformanceHistory(false);
  };

  // Phase 14B.2, read-only, Supabase-only diagnostic: mirrors
  // handleFindPerformanceWebsite for Decline Diagnosis — searches every
  // accessible SEO workspace/website for the current user for the first one
  // with live decline diagnosis rows. The two buttons below prefer this
  // website over "Test website service"'s auto-resolved one, same pattern as
  // the Page Performance section above.
  const handleFindDiagnosisWebsite = async () => {
    setIsFindingDiagnosisWebsite(true);
    setFindDiagnosisWebsiteWarning(null);
    try {
      const found = await findAccessibleWebsiteWithDeclineDiagnosisData();
      setDiagnosisBackedWebsite(found);
      if (!found) {
        setFindDiagnosisWebsiteWarning(
          "No accessible workspace/website has live Decline Diagnosis rows yet.",
        );
      }
    } catch (error) {
      setFindDiagnosisWebsiteWarning(
        error instanceof Error ? error.message : "Find decline diagnosis website check failed.",
      );
    }
    setIsFindingDiagnosisWebsite(false);
  };

  // Phase 14B.2, read-only, Supabase-only diagnostic: calls the Stage 5
  // seo_decline_diagnoses_current VIEW directly (not through the adapter) to
  // prove the view + its RLS work, independent of the DeclineDiagnosis
  // flattening/mapping logic. No mock equivalent, so this is expected to show
  // a warning in mock mode or without a signed-in Supabase session — same
  // caveat as the Page Performance latest-view check above.
  const handleTestDeclineDiagnosis = async () => {
    const website = diagnosisBackedWebsite
      ? { id: diagnosisBackedWebsite.websiteId }
      : websiteTest?.firstWebsite;
    if (!website) return;
    setIsTestingDeclineDiagnosis(true);
    setDeclineDiagnosisTestWarning(null);
    try {
      const rows = await fetchSupabaseCurrentDiagnosisRows(website.id);
      const typeCounts = rows.reduce<Record<string, number>>((acc, row) => {
        acc[row.diagnosis_type] = (acc[row.diagnosis_type] ?? 0) + 1;
        return acc;
      }, {});
      const first = rows[0] ?? null;
      setDeclineDiagnosisTest({
        count: rows.length,
        typeCounts,
        firstDiagnosisId: first?.id ?? null,
        firstDiagnosisType: first?.diagnosis_type ?? null,
        firstDiagnosisSeverity: first?.severity ?? null,
        firstDiagnosisStatus: first?.status ?? null,
        firstDiagnosisSummary: first?.business_summary ?? null,
      });
    } catch (error) {
      setDeclineDiagnosisTestWarning(
        error instanceof Error
          ? error.message
          : "Decline diagnosis current-view check failed (expected in mock mode or without a Supabase session).",
      );
    }
    setIsTestingDeclineDiagnosis(false);
  };

  // Phase 14B.2, read-only, Supabase-only diagnostic, optional: reads raw
  // evidence rows for the first diagnosis found by the button above. Same
  // no-mock-equivalent caveat.
  const handleTestDiagnosisEvidence = async () => {
    const diagnosisId = declineDiagnosisTest?.firstDiagnosisId;
    if (!diagnosisId) return;
    setIsTestingDiagnosisEvidence(true);
    setDiagnosisEvidenceTestWarning(null);
    try {
      const rows = await fetchSupabaseDiagnosisEvidence(diagnosisId);
      setDiagnosisEvidenceTest({
        count: rows.length,
        firstEvidenceSummary: rows[0]?.evidence_summary ?? null,
      });
    } catch (error) {
      setDiagnosisEvidenceTestWarning(
        error instanceof Error
          ? error.message
          : "Diagnosis evidence check failed (expected in mock mode or without a Supabase session).",
      );
    }
    setIsTestingDiagnosisEvidence(false);
  };

  // Phase 15A, read-only, Supabase-only diagnostic: mirrors
  // handleFindDiagnosisWebsite for Off-Page Authority — searches every
  // accessible SEO workspace/website for the current user for the one with
  // the most seo_authority_opportunities rows.
  const handleFindAuthorityWebsite = async () => {
    setIsFindingAuthorityWebsite(true);
    setFindAuthorityWebsiteWarning(null);
    try {
      const found = await findAccessibleWebsiteWithAuthorityData();
      setAuthorityBackedWebsite(found);
      if (!found) {
        setFindAuthorityWebsiteWarning(
          "No accessible workspace/website has Off-Page Authority opportunities yet.",
        );
      }
    } catch (error) {
      setFindAuthorityWebsiteWarning(
        error instanceof Error ? error.message : "Find Off-Page Authority website check failed.",
      );
    }
    setIsFindingAuthorityWebsite(false);
  };

  // Root-cause fix: this used to resolve its website id from
  // `authorityBackedWebsite ?? websiteTest?.firstWebsite` — a DIFFERENT
  // resolution path than the one proven correct by the Stage 6 Resolution
  // Diagnostics section below (which uses the cross-workspace finder result
  // only when it differs from the resolved active website, else the active
  // website itself). `websiteTest.firstWebsite` comes from
  // websiteService.fetchWebsites() and is unrelated to Stage 6 data — if the
  // developer clicked "Test website service" without first clicking "Find
  // website with Off-Page Authority data", this handler silently queried
  // whatever website fetchWebsites() happened to resolve first, which has no
  // guarantee of holding any Stage 6 rows — hence "0 opportunities" even
  // though the diagnostics prove a Stage 6-backed website is resolvable.
  //
  // Fix: resolve the requested website id here using the EXACT SAME logic as
  // handleRunStage6ResolutionDiagnostics's offPageRequestedWebsiteId — the
  // finder's candidate when it found one that differs from the active
  // website (no Stage 6 data there yet), otherwise the active website
  // itself. Read-only: does not mutate ActiveWebsiteContext. No id is
  // hardcoded — driven entirely by useActiveWebsite() + the existing,
  // unmodified finder function.
  const resolveOffPageRequestedWebsiteId = async (): Promise<{
    requestedWebsiteId: string | null;
    candidate: WebsiteWithAuthorityData | null;
  }> => {
    const currentActiveWebsiteId = activeWebsiteId;
    let candidate: WebsiteWithAuthorityData | null = null;
    try {
      candidate = await findAccessibleWebsiteWithAuthorityData();
    } catch {
      candidate = null;
    }
    const fallbackRan = !!candidate && candidate.websiteId !== currentActiveWebsiteId;
    return {
      requestedWebsiteId: fallbackRan ? candidate!.websiteId : currentActiveWebsiteId,
      candidate,
    };
  };

  // Phase 15A, read-only, Supabase-only diagnostic: calls the Stage 6
  // seo_authority_opportunities / seo_authority_campaigns / seo_authority_activity
  // tables directly (not through the adapter) to prove they + their RLS work,
  // independent of the OffPageOpportunity/AuthorityCampaign mapping logic. No
  // mock equivalent, so this is expected to show a warning in mock mode or
  // without a signed-in Supabase session — same caveat as the Decline
  // Diagnosis current-view check above.
  const handleTestAuthority = async () => {
    setIsTestingAuthority(true);
    setAuthorityTestWarning(null);
    try {
      const { requestedWebsiteId } = await resolveOffPageRequestedWebsiteId();
      if (!requestedWebsiteId) {
        setAuthorityTestWarning(
          "No resolved website id — sign in and ensure an active website is set (or that a Stage 6-backed website is accessible).",
        );
        setIsTestingAuthority(false);
        return;
      }
      const [opportunities, campaigns, activity] = await Promise.all([
        fetchSupabaseAuthorityOpportunityRows(requestedWebsiteId),
        fetchSupabaseAuthorityCampaignRows(requestedWebsiteId),
        fetchSupabaseAuthorityActivity(requestedWebsiteId),
      ]);
      const statusCounts = opportunities.reduce<Record<string, number>>((acc, row) => {
        acc[row.status] = (acc[row.status] ?? 0) + 1;
        return acc;
      }, {});
      setAuthorityTest({
        requestedWebsiteId,
        opportunityCount: opportunities.length,
        statusCounts,
        campaignCount: campaigns.length,
        activityCount: activity.length,
        firstOpportunityTitle: opportunities[0]?.title ?? null,
      });
    } catch (error) {
      setAuthorityTestWarning(
        error instanceof Error
          ? error.message
          : "Off-Page Authority check failed (expected in mock mode or without a Supabase session).",
      );
    }
    setIsTestingAuthority(false);
  };

  // Phase 15A, read-only, Supabase-only diagnostic: mirrors
  // handleFindAuthorityWebsite for AI Visibility — searches every accessible
  // SEO workspace/website for the current user for the one with the most
  // seo_ai_prompt_tracking rows.
  const handleFindAiVisibilityWebsite = async () => {
    setIsFindingAiVisibilityWebsite(true);
    setFindAiVisibilityWebsiteWarning(null);
    try {
      const found = await findAccessibleWebsiteWithAiVisibilityData();
      setAiVisibilityBackedWebsite(found);
      if (!found) {
        setFindAiVisibilityWebsiteWarning(
          "No accessible workspace/website has AI Visibility prompt-tracking rows yet.",
        );
      }
    } catch (error) {
      setFindAiVisibilityWebsiteWarning(
        error instanceof Error ? error.message : "Find AI Visibility website check failed.",
      );
    }
    setIsFindingAiVisibilityWebsite(false);
  };

  // Root-cause fix (same as resolveOffPageRequestedWebsiteId above): this
  // used to resolve from `aiVisibilityBackedWebsite ?? websiteTest?.firstWebsite`
  // — a different resolution path than the one proven correct by the Stage 6
  // Resolution Diagnostics section. Now resolves the same way:
  // finder-candidate-if-it-differs-from-active, else active. Read-only, no
  // ActiveWebsiteContext mutation, no hardcoded id.
  const resolveAiVisibilityRequestedWebsiteId = async (): Promise<{
    requestedWebsiteId: string | null;
    candidate: WebsiteWithAiVisibilityData | null;
  }> => {
    const currentActiveWebsiteId = activeWebsiteId;
    let candidate: WebsiteWithAiVisibilityData | null = null;
    try {
      candidate = await findAccessibleWebsiteWithAiVisibilityData();
    } catch {
      candidate = null;
    }
    const fallbackRan = !!candidate && candidate.websiteId !== currentActiveWebsiteId;
    return {
      requestedWebsiteId: fallbackRan ? candidate!.websiteId : currentActiveWebsiteId,
      candidate,
    };
  };

  // Phase 15A, read-only, Supabase-only diagnostic: calls the Stage 6
  // seo_ai_prompt_tracking / seo_ai_content_gaps / seo_ai_mentions tables
  // directly. Same no-mock-equivalent caveat as handleTestAuthority above.
  const handleTestAiVisibility = async () => {
    setIsTestingAiVisibility(true);
    setAiVisibilityTestWarning(null);
    try {
      const { requestedWebsiteId } = await resolveAiVisibilityRequestedWebsiteId();
      if (!requestedWebsiteId) {
        setAiVisibilityTestWarning(
          "No resolved website id — sign in and ensure an active website is set (or that a Stage 6-backed website is accessible).",
        );
        setIsTestingAiVisibility(false);
        return;
      }
      const [prompts, contentGaps, mentions] = await Promise.all([
        fetchSupabasePromptTrackingRows(requestedWebsiteId),
        fetchSupabaseContentGapRows(requestedWebsiteId),
        fetchSupabaseMentionRows(requestedWebsiteId),
      ]);
      const visibilityCounts = prompts.reduce<Record<string, number>>((acc, row) => {
        acc[row.visibility_status] = (acc[row.visibility_status] ?? 0) + 1;
        return acc;
      }, {});
      const mentionTypeCounts = mentions.reduce<Record<string, number>>((acc, row) => {
        acc[row.mention_type] = (acc[row.mention_type] ?? 0) + 1;
        return acc;
      }, {});
      setAiVisibilityTest({
        requestedWebsiteId,
        promptCount: prompts.length,
        visibilityCounts,
        contentGapCount: contentGaps.length,
        mentionCount: mentions.length,
        mentionTypeCounts,
      });
    } catch (error) {
      setAiVisibilityTestWarning(
        error instanceof Error
          ? error.message
          : "AI Visibility check failed (expected in mock mode or without a Supabase session).",
      );
    }
    setIsTestingAiVisibility(false);
  };

  // Read-only diagnostic: captures a snapshot of exactly how
  // AuthorityBuilderPage.tsx / AiVisibilityPage.tsx would resolve a website
  // to query right now — without loading either real page. Reproduces each
  // page's own override condition
  // (`if (!found || found.websiteId === activeWebsite.id) return;`)
  // structurally, driven entirely by live data (the shared active-website
  // context read via useActiveWebsite() above, and the two existing Stage 6
  // finder functions) — no seed/workspace/website id is ever hardcoded here.
  // Nothing is written: no setActiveWebsiteId call, no INSERT/UPDATE/DELETE,
  // no mutation of any kind. Each step is wrapped in its own try/catch so a
  // single failing call doesn't blank the rest of the diagnostic; every
  // caught error is recorded (step + normalized Supabase code/message) in
  // the `errors` array rather than dropped.
  const handleRunStage6ResolutionDiagnostics = async () => {
    setIsRunningStage6ResolutionDiagnostics(true);
    setStage6ResolutionDiagnosticsWarning(null);

    const errors: Stage6DiagnosticError[] = [];
    const recordError = (step: string, error: unknown) => {
      const normalized = normalizeSupabaseError(error);
      errors.push({ step, code: normalized.code ?? null, message: normalized.message });
    };

    let resolvedWorkspaceId: string | null = null;
    let resolvedWorkspaceReason: string | null = null;
    try {
      const resolution = await getCurrentSeoWorkspace();
      resolvedWorkspaceId = resolution.workspace?.id ?? null;
      resolvedWorkspaceReason = resolution.reason ?? null;
    } catch (error) {
      recordError("SEO workspace resolution", error);
    }

    // Real seo_workspace_members.seo_role for resolvedWorkspaceId — the
    // actual authorization source Stage 6's RLS/RPCs check (seo_role_in()),
    // as opposed to MOCK_CURRENT_ROLE / RoleSwitcher's local simulated role.
    // Only attempted when a workspace was actually resolved above (a role
    // lookup needs a workspace id); skipped otherwise, not treated as "no
    // active membership."
    let resolvedSeoRole: SeoUserRole | null = null;
    let roleLookupFailed = false;
    if (resolvedWorkspaceId) {
      try {
        resolvedSeoRole = await getCurrentSeoRole(resolvedWorkspaceId);
      } catch (error) {
        roleLookupFailed = true;
        recordError("SEO role lookup", error);
      }
    }

    // Read-only: whatever website id (if any) the shared context already
    // holds right now — this page never sets it.
    const currentActiveWebsiteId = activeWebsiteId;
    let activeWebsiteUrl: string | null = null;
    if (currentActiveWebsiteId) {
      try {
        const website = await fetchWebsiteById(currentActiveWebsiteId);
        activeWebsiteUrl = website?.website_url ?? null;
      } catch (error) {
        recordError("Active website lookup", error);
      }
    }

    let offPageCandidate: WebsiteWithAuthorityData | null = null;
    try {
      offPageCandidate = await findAccessibleWebsiteWithAuthorityData();
    } catch (error) {
      recordError("Off-Page Authority finder", error);
    }

    let aiVisibilityCandidate: WebsiteWithAiVisibilityData | null = null;
    try {
      aiVisibilityCandidate = await findAccessibleWebsiteWithAiVisibilityData();
    } catch (error) {
      recordError("AI Visibility finder", error);
    }

    // Same condition as the two pages' own fallback effects: the override
    // only applies when a candidate was found AND it differs from the
    // currently active website (mirrors "if (!found || found.websiteId ===
    // activeWebsite.id) return;" in AuthorityBuilderPage.tsx/AiVisibilityPage.tsx).
    const offPageFallbackRan =
      !!offPageCandidate && offPageCandidate.websiteId !== currentActiveWebsiteId;
    const offPageRequestedWebsiteId = offPageFallbackRan
      ? offPageCandidate!.websiteId
      : currentActiveWebsiteId;

    const aiVisibilityFallbackRan =
      !!aiVisibilityCandidate && aiVisibilityCandidate.websiteId !== currentActiveWebsiteId;
    const aiVisibilityRequestedWebsiteId = aiVisibilityFallbackRan
      ? aiVisibilityCandidate!.websiteId
      : currentActiveWebsiteId;

    setStage6ResolutionDiagnostics({
      userEmail: authState?.userEmail ?? null,
      userId: authState?.userId ?? null,
      dataMode: authState?.mode ?? "unknown",
      resolvedWorkspaceId,
      resolvedWorkspaceReason,
      activeWebsiteId: currentActiveWebsiteId,
      activeWebsiteUrl,
      offPageFallbackRan,
      offPageRequestedWebsiteId,
      offPageCandidateWebsiteId: offPageCandidate?.websiteId ?? null,
      offPageCandidateCount: offPageCandidate?.candidateCount ?? 0,
      aiVisibilityFallbackRan,
      aiVisibilityRequestedWebsiteId,
      aiVisibilityCandidateWebsiteId: aiVisibilityCandidate?.websiteId ?? null,
      aiVisibilityCandidateCount: aiVisibilityCandidate?.candidateCount ?? 0,
      noRlsVisibleStage6Website: !offPageCandidate && !aiVisibilityCandidate,
      roleLookupWorkspaceId: resolvedWorkspaceId,
      resolvedSeoRole,
      roleLookupFailed,
      errors,
    });
    setIsRunningStage6ResolutionDiagnostics(false);
  };

  const handleCreateTestWebsite = async () => {
    setIsCreatingWebsite(true);
    setCreateWebsiteWarning(null);
    setCreateWebsiteResult(null);
    try {
      const created = await addWebsite({
        website_url: newWebsiteUrl.trim() || DEFAULT_TEST_WEBSITE_URL,
        name: "Dev Auth Test Website",
        business_name: "Dev Auth Test Co",
        industry: undefined,
        target_location: undefined,
        website_type: "other",
        plan: "basic",
      });
      setCreateWebsiteResult(`Created: ${created.website_url} (id: ${created.id})`);
    } catch (error) {
      setCreateWebsiteWarning(error instanceof Error ? error.message : "Create website failed.");
    }
    setIsCreatingWebsite(false);
  };

  // Sign-in disabled state + the visible reason shown to the developer.
  // Priority mirrors the checks in signInDevUser() itself: config first
  // (nothing else matters without it), then the two required fields. `null`
  // means the button is ready to click (loading state is handled separately
  // via isSigningIn so it doesn't get confused with "missing input").
  const signInDisabledReason = !authState
    ? "Checking Supabase configuration..."
    : !authState.configured
      ? "Sign in disabled because Supabase URL or anon key is missing."
      : !emailLooksValid(email)
        ? "Enter an email address."
        : !password
          ? "Enter a password."
          : null;
  const isSignInDisabled = isSigningIn || signInDisabledReason !== null;
  const signInDisabledReasonDisplay = isSigningIn
    ? "Sign-in in progress."
    : (signInDisabledReason ?? "None — ready to sign in.");

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle>Supabase Auth Test</CardTitle>
            <Badge variant="outline">development only</Badge>
          </div>
          <CardDescription>
            Sign in with a real test-project user to exercise authenticated Supabase/RLS behavior
            for Website Setup + Business Onboarding (Phase 13B). No fake auth, no hardcoded users,
            no service role key. Passwords are never stored, logged, or displayed after entry.{" "}
            <Link to="/seo/dev/supabase-readiness" className="underline">
              Supabase Readiness →
            </Link>
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          {isLoadingState && <p className="text-muted-foreground">Checking…</p>}

          {authState && (
            <div className="space-y-2">
              <InfoRow label="Data mode" value={authState.mode} />
              <InfoRow label="Supabase config present" value={authState.configured ? "yes" : "no"} />
              <InfoRow label="Session present" value={authState.hasSession ? "yes" : "no"} />
              <InfoRow label="Current user email" value={authState.userEmail ?? "(none)"} />
              <InfoRow label="Current user id" value={authState.userId ?? "(none)"} />
              <InfoRow
                label="SEO module access"
                value={
                  !authState.hasSession
                    ? "(sign in first)"
                    : seoAccess?.hasAccess === null || seoAccess === null
                      ? "unknown"
                      : seoAccess.hasAccess
                        ? `yes (via ${seoAccess.method})`
                        : `no (via ${seoAccess.method})`
                }
              />
              <InfoRow
                label="Workspace access"
                value={
                  !authState.hasSession
                    ? "(sign in first)"
                    : workspaceAccess?.hasWorkspace
                      ? `yes — "${workspaceAccess.workspaceName}"`
                      : "no workspace yet"
                }
              />

              {(authState.warnings.length > 0 ||
                seoAccess?.warning ||
                workspaceAccess?.warning) && (
                <div className="mt-3">
                  <p className="mb-1 font-medium">Warnings</p>
                  <ul className="list-inside list-disc space-y-1 text-muted-foreground">
                    {authState.warnings.map((warning) => (
                      <li key={warning}>{warning}</li>
                    ))}
                    {seoAccess?.warning && <li>{seoAccess.warning}</li>}
                    {workspaceAccess?.warning && <li>{workspaceAccess.warning}</li>}
                  </ul>
                </div>
              )}
            </div>
          )}

          <Button
            variant="outline"
            size="sm"
            onClick={loadAuthAndAccessState}
            disabled={isLoadingState}
          >
            {isLoadingState ? "Checking..." : "Refresh / check"}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Sign in (test project only)</CardTitle>
          <CardDescription>
            Uses <code>supabase.auth.signInWithPassword()</code> against the configured project. The
            user must already exist in Supabase Auth — this does not create users.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {authState?.hasSession ? (
            <div className="space-y-2">
              <p className="text-sm text-muted-foreground">
                Signed in as <span className="font-medium">{authState.userEmail}</span>.
              </p>
              <Button variant="outline" onClick={handleSignOut} disabled={isSigningOut}>
                {isSigningOut ? "Signing out..." : "Sign out"}
              </Button>
              {signOutWarning && <p className="text-sm text-destructive">{signOutWarning}</p>}
            </div>
          ) : (
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="dev-auth-email">Email</Label>
                <Input
                  id="dev-auth-email"
                  type="email"
                  autoComplete="off"
                  placeholder="test-user@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  // Browser autofill (esp. password-manager "fill" clicks) can
                  // populate the DOM value without reliably firing React's
                  // onChange. onInput is a native event that always fires on
                  // any value change, so this keeps controlled state in sync.
                  onInput={(e) => setEmail(e.currentTarget.value)}
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="dev-auth-password">Password</Label>
                <Input
                  id="dev-auth-password"
                  type="password"
                  autoComplete="off"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  onInput={(e) => setPassword(e.currentTarget.value)}
                />
              </div>
              <div className="flex items-end sm:col-span-2">
                <Button onClick={handleSignIn} disabled={isSignInDisabled}>
                  {isSigningIn ? "Signing in..." : "Sign in"}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground sm:col-span-2">
                Disabled reason: {signInDisabledReasonDisplay}
              </p>
              {signInWarning && (
                <p className="text-sm text-destructive sm:col-span-2">{signInWarning}</p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Service checks</CardTitle>
          <CardDescription>
            Exercises the wired services exactly as the real pages do. In mock mode these always
            use mock data; in Supabase mode they attempt a real read/write and fall back to mock on
            failure (see console for the fallback warning).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Button variant="outline" onClick={handleTestWebsites} disabled={isTestingWebsites}>
              {isTestingWebsites ? "Checking..." : "Test website service (fetchWebsites)"}
            </Button>
            {websiteTest && (
              <p className="text-sm text-muted-foreground">
                {websiteTest.count} website(s) found
                {websiteTest.firstWebsite ? ` — first: ${websiteTest.firstWebsite.website_url}` : ""}
                .
              </p>
            )}
            {websiteTestWarning && <p className="text-sm text-destructive">{websiteTestWarning}</p>}
          </div>

          <div className="space-y-2">
            <Button
              variant="outline"
              onClick={handleTestOnboarding}
              disabled={isTestingOnboarding || !websiteTest?.firstWebsite}
            >
              {isTestingOnboarding ? "Checking..." : "Test onboarding service (fetchOnboardingByWebsiteId)"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {onboardingTest && (
              <p className="text-sm text-muted-foreground">
                {onboardingTest.found
                  ? `Onboarding record found for website ${onboardingTest.websiteId}.`
                  : `No onboarding record yet for website ${onboardingTest.websiteId} (not a failure).`}
              </p>
            )}
            {onboardingTestWarning && (
              <p className="text-sm text-destructive">{onboardingTestWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">Phase 13C — Audit + Recommendation</p>

            <Button
              variant="outline"
              onClick={handleTestAuditService}
              disabled={isTestingAudit || !websiteTest?.firstWebsite}
            >
              {isTestingAudit ? "Checking..." : "Test audit service (fetchAudits / fetchLatestAudit)"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {auditTest && (
              <p className="text-sm text-muted-foreground">
                {auditTest.count} audit run(s) found — latest status:{" "}
                {auditTest.latestStatus ?? "(none yet)"}.
              </p>
            )}
            {auditTestWarning && <p className="text-sm text-destructive">{auditTestWarning}</p>}
          </div>

          <div className="space-y-2">
            <Button
              variant="outline"
              onClick={handleTestRecommendationService}
              disabled={isTestingRecommendation || !websiteTest?.firstWebsite}
            >
              {isTestingRecommendation ? "Checking..." : "Test recommendation service (fetchRecommendations)"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {recommendationTest && (
              <p className="text-sm text-muted-foreground">
                {recommendationTest.count} current recommendation(s) found.
              </p>
            )}
            {recommendationTestWarning && (
              <p className="text-sm text-destructive">{recommendationTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Run test audit (dev-only — no external crawling, no deletes; Supabase mode only
              creates a "running" row via seo_run_audit, since no crawler exists yet)
            </Label>
            <Button
              variant="outline"
              onClick={handleRunTestAudit}
              disabled={isRunningTestAudit || !websiteTest?.firstWebsite}
            >
              {isRunningTestAudit ? "Running..." : "Run test audit"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {runAuditTestResult && (
              <p className="text-sm text-muted-foreground">{runAuditTestResult}</p>
            )}
            {runAuditTestWarning && (
              <p className="text-sm text-destructive">{runAuditTestWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">Phase 13D — Approval Queue</p>

            <Button
              variant="outline"
              onClick={handleTestApprovalService}
              disabled={isTestingApproval || !websiteTest?.firstWebsite}
            >
              {isTestingApproval ? "Checking..." : "Test approval service (fetchApprovalQueue)"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {approvalTest && (
              <p className="text-sm text-muted-foreground">
                {approvalTest.count} approval item(s) found
                {approvalTest.firstItem ? ` — first status: ${approvalTest.firstItem.status}` : ""}.
              </p>
            )}
            {approvalTestWarning && <p className="text-sm text-destructive">{approvalTestWarning}</p>}
          </div>

          <div className="space-y-2">
            <Button
              variant="outline"
              onClick={handleTestApprovalComment}
              disabled={isTestingApprovalComment || !approvalTest?.firstItem}
            >
              {isTestingApprovalComment ? "Checking..." : "Test approval comments (addApprovalComment)"}
            </Button>
            {!approvalTest?.firstItem && (
              <p className="text-xs text-muted-foreground">
                No approval item available to test transition.
              </p>
            )}
            {approvalCommentTestResult && (
              <p className="text-sm text-muted-foreground">{approvalCommentTestResult}</p>
            )}
            {approvalCommentTestWarning && (
              <p className="text-sm text-destructive">{approvalCommentTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Run safe approval transition (dev-only — "Request expert review" only; no delete,
              no publish, no external call; uses the Stage 2 seo_approval_transition RPC)
            </Label>
            <Button
              variant="outline"
              onClick={handleRunSafeApprovalTransition}
              disabled={isRunningApprovalTransition || !approvalTest?.firstItem}
            >
              {isRunningApprovalTransition ? "Running..." : "Run safe approval transition"}
            </Button>
            {!approvalTest?.firstItem && (
              <p className="text-xs text-muted-foreground">
                No approval item available to test transition.
              </p>
            )}
            {approvalTransitionResult && (
              <p className="text-sm text-muted-foreground">{approvalTransitionResult}</p>
            )}
            {approvalTransitionWarning && (
              <p className="text-sm text-destructive">{approvalTransitionWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">Phase 13E — Content Studio</p>

            <Button
              variant="outline"
              onClick={handleTestContentOpportunityService}
              disabled={isTestingContentOpportunity || !websiteTest?.firstWebsite}
            >
              {isTestingContentOpportunity
                ? "Checking..."
                : "Test content opportunity service (fetchContentOpportunities)"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {contentOpportunityTest && (
              <p className="text-sm text-muted-foreground">
                {contentOpportunityTest.count} content opportunity(ies) found
                {contentOpportunityTest.firstOpportunity
                  ? ` — first: "${contentOpportunityTest.firstOpportunity.title}" (${contentOpportunityTest.firstOpportunity.status})`
                  : ""}
                .
              </p>
            )}
            {contentOpportunityTestWarning && (
              <p className="text-sm text-destructive">{contentOpportunityTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Button
              variant="outline"
              onClick={handleTestContentDetailService}
              disabled={isTestingContentDetail || !contentOpportunityTest?.firstOpportunity}
            >
              {isTestingContentDetail
                ? "Checking..."
                : "Test content detail service (keyword plan / wireframe / draft)"}
            </Button>
            {!contentOpportunityTest?.firstOpportunity && (
              <p className="text-xs text-muted-foreground">No content opportunity available.</p>
            )}
            {contentDetailTest && (
              <p className="text-sm text-muted-foreground">
                Keyword plan: {contentDetailTest.hasKeywordPlan ? "yes" : "no"} · Wireframe:{" "}
                {contentDetailTest.hasWireframe ? "yes" : "no"} · Draft:{" "}
                {contentDetailTest.hasDraft ? "yes" : "no"}
                {contentDetailTest.hasDraft ? ` (${contentDetailTest.sectionCount} section(s))` : ""}.
              </p>
            )}
            {contentDetailTestWarning && (
              <p className="text-sm text-destructive">{contentDetailTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Create dev content opportunity (dev-only — no LLM, no crawling, no publish;
              insert-only, no deletes)
            </Label>
            <Button
              variant="outline"
              onClick={handleCreateDevContentOpportunity}
              disabled={isCreatingContentOpportunity || !websiteTest?.firstWebsite}
            >
              {isCreatingContentOpportunity ? "Creating..." : "Create dev content opportunity"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {createContentOpportunityResult && (
              <p className="text-sm text-muted-foreground">{createContentOpportunityResult}</p>
            )}
            {createContentOpportunityWarning && (
              <p className="text-sm text-destructive">{createContentOpportunityWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Run safe content transition (dev-only — "Start content plan" only, idea → plan_ready;
              no LLM, no crawling, no publish, no deletes; uses the Stage 3 seo_content_transition
              RPC)
            </Label>
            <Button
              variant="outline"
              onClick={handleRunSafeContentTransition}
              disabled={isRunningContentTransition || !contentOpportunityTest?.firstOpportunity}
            >
              {isRunningContentTransition ? "Running..." : "Run safe content transition"}
            </Button>
            {!contentOpportunityTest?.firstOpportunity && (
              <p className="text-xs text-muted-foreground">No content opportunity available.</p>
            )}
            {contentTransitionResult && (
              <p className="text-sm text-muted-foreground">{contentTransitionResult}</p>
            )}
            {contentTransitionWarning && (
              <p className="text-sm text-destructive">{contentTransitionWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">
              Phase 13F — Dashboard + Admin Preview (read-only)
            </p>

            <Button
              variant="outline"
              onClick={handleTestDashboardSummary}
              disabled={isTestingDashboardSummary || !websiteTest?.firstWebsite}
            >
              {isTestingDashboardSummary ? "Checking..." : "Test Dashboard Summary Service"}
            </Button>
            {!websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {dashboardSummaryTest && (
              <p className="text-sm text-muted-foreground">
                {dashboardSummaryTest.topPriorityFixesCount} top priority fix(es) ·{" "}
                {dashboardSummaryTest.pendingApprovalsCount} pending approval(s) ·{" "}
                {dashboardSummaryTest.expertReviewCount} awaiting expert review ·{" "}
                {dashboardSummaryTest.developerNeededCount} needing a developer.
              </p>
            )}
            {dashboardSummaryTestWarning && (
              <p className="text-sm text-destructive">{dashboardSummaryTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Button
              variant="outline"
              onClick={handleTestAdminPreviewSummary}
              disabled={isTestingAdminPreviewSummary}
            >
              {isTestingAdminPreviewSummary ? "Checking..." : "Test Admin Preview Read Service"}
            </Button>
            {adminPreviewSummaryTest && (
              <p className="text-sm text-muted-foreground">
                {adminPreviewSummaryTest.websites_count} website(s),{" "}
                {adminPreviewSummaryTest.active_websites_count} active ·{" "}
                {adminPreviewSummaryTest.latest_audit_runs_count} audit run(s) ·{" "}
                {adminPreviewSummaryTest.recommendations_count} recommendation(s) ·{" "}
                {adminPreviewSummaryTest.approval_queue_pending_count} pending approval(s) ·{" "}
                {adminPreviewSummaryTest.content_opportunities_count} content opportunit(y/ies) ·
                connections: GSC {adminPreviewSummaryTest.connection_status_summary.gsc_connected_count},
                GA4 {adminPreviewSummaryTest.connection_status_summary.ga4_connected_count}, CMS{" "}
                {adminPreviewSummaryTest.connection_status_summary.cms_connected_count}, GBP{" "}
                {adminPreviewSummaryTest.connection_status_summary.gbp_connected_count}.
              </p>
            )}
            {adminPreviewSummaryTestWarning && (
              <p className="text-sm text-destructive">{adminPreviewSummaryTestWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">
              Phase 14A.2 — Page Performance Tracker (read-only)
            </p>

            <div className="space-y-2">
              <Label>
                Find website with Page Performance data (dev-only, Supabase-only — searches every
                accessible SEO workspace/website for the current user, not just the one
                getCurrentSeoWorkspace defaults to; used automatically by the buttons below when
                found)
              </Label>
              <Button
                variant="outline"
                onClick={handleFindPerformanceWebsite}
                disabled={isFindingPerformanceWebsite}
              >
                {isFindingPerformanceWebsite ? "Searching..." : "Find website with Page Performance data"}
              </Button>
              {performanceBackedWebsite && (
                <p className="text-sm text-muted-foreground">
                  Found — workspace: "{performanceBackedWebsite.workspaceName}", website:{" "}
                  {performanceBackedWebsite.websiteUrl}, latest-view row count:{" "}
                  {performanceBackedWebsite.latestRowCount}.
                </p>
              )}
              {findPerformanceWebsiteWarning && (
                <p className="text-sm text-destructive">{findPerformanceWebsiteWarning}</p>
              )}
            </div>

            <Button
              variant="outline"
              onClick={handleTestPagePerformance}
              disabled={isTestingPagePerformance || (!performanceBackedWebsite && !websiteTest?.firstWebsite)}
            >
              {isTestingPagePerformance ? "Checking..." : "Test Page Performance Service"}
            </Button>
            {performanceBackedWebsite && (
              <p className="text-xs text-muted-foreground">
                Using performance-backed website: {performanceBackedWebsite.websiteUrl}.
              </p>
            )}
            {!performanceBackedWebsite && !websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {pagePerformanceTest && (
              <p className="text-sm text-muted-foreground">
                {pagePerformanceTest.count} page(s) found — improving: {pagePerformanceTest.improvingCount}
                , stable: {pagePerformanceTest.stableCount}, declining: {pagePerformanceTest.decliningCount}
                , needs refresh: {pagePerformanceTest.needsRefreshCount}, not enough data:{" "}
                {pagePerformanceTest.notEnoughDataCount}.
              </p>
            )}
            {pagePerformanceTestWarning && (
              <p className="text-sm text-destructive">{pagePerformanceTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Test Page Performance Latest View (dev-only, Supabase-only diagnostic — reads the Stage
              4 seo_page_performance_latest view directly; no mock equivalent, so this is expected to
              show a warning in mock mode or without a signed-in Supabase session)
            </Label>
            <Button
              variant="outline"
              onClick={handleTestPagePerformanceLatestView}
              disabled={
                isTestingPagePerformanceLatestView || (!performanceBackedWebsite && !websiteTest?.firstWebsite)
              }
            >
              {isTestingPagePerformanceLatestView ? "Checking..." : "Test Page Performance Latest View"}
            </Button>
            {performanceBackedWebsite && (
              <p className="text-xs text-muted-foreground">
                Using performance-backed website: {performanceBackedWebsite.websiteUrl}.
              </p>
            )}
            {!performanceBackedWebsite && !websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {pagePerformanceLatestViewTest && (
              <p className="text-sm text-muted-foreground">
                {pagePerformanceLatestViewTest.rowCount} latest-view row(s) found — movement counts:{" "}
                {Object.entries(pagePerformanceLatestViewTest.movementCounts)
                  .map(([status, count]) => `${status}: ${count}`)
                  .join(", ") || "none"}
                .
              </p>
            )}
            {pagePerformanceLatestViewTestWarning && (
              <p className="text-sm text-destructive">{pagePerformanceLatestViewTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Test Page Performance History (dev-only, Supabase-only diagnostic, optional — reads raw
              snapshot history for the first page found above; same no-mock-equivalent caveat)
            </Label>
            <Button
              variant="outline"
              onClick={handleTestPagePerformanceHistory}
              disabled={isTestingPagePerformanceHistory || !pagePerformanceTest?.firstPageId}
            >
              {isTestingPagePerformanceHistory ? "Checking..." : "Test Page Performance History"}
            </Button>
            {!pagePerformanceTest?.firstPageId && (
              <p className="text-xs text-muted-foreground">
                Run "Test Page Performance Service" first — needs a page id.
              </p>
            )}
            {pagePerformanceHistoryTestResult && (
              <p className="text-sm text-muted-foreground">{pagePerformanceHistoryTestResult}</p>
            )}
            {pagePerformanceHistoryTestWarning && (
              <p className="text-sm text-destructive">{pagePerformanceHistoryTestWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">
              Phase 14B.2 — Decline Diagnosis Engine (read-only)
            </p>

            <div className="space-y-2">
              <Label>
                Find website with Decline Diagnosis data (dev-only, Supabase-only — searches every
                accessible SEO workspace/website for the current user for live diagnoses; used
                automatically by the buttons below when found)
              </Label>
              <Button
                variant="outline"
                onClick={handleFindDiagnosisWebsite}
                disabled={isFindingDiagnosisWebsite}
              >
                {isFindingDiagnosisWebsite ? "Searching..." : "Find website with Decline Diagnosis data"}
              </Button>
              {diagnosisBackedWebsite && (
                <p className="text-sm text-muted-foreground">
                  Found — workspace: "{diagnosisBackedWebsite.workspaceName}", website:{" "}
                  {diagnosisBackedWebsite.websiteUrl}, live diagnosis count:{" "}
                  {diagnosisBackedWebsite.diagnosisCount} (highest among{" "}
                  {diagnosisBackedWebsite.candidateCount} accessible website
                  {diagnosisBackedWebsite.candidateCount === 1 ? "" : "s"} with diagnoses).
                </p>
              )}
              {findDiagnosisWebsiteWarning && (
                <p className="text-sm text-destructive">{findDiagnosisWebsiteWarning}</p>
              )}
            </div>

            <Button
              variant="outline"
              onClick={handleTestDeclineDiagnosis}
              disabled={isTestingDeclineDiagnosis || (!diagnosisBackedWebsite && !websiteTest?.firstWebsite)}
            >
              {isTestingDeclineDiagnosis ? "Checking..." : "Test Decline Diagnosis Current View"}
            </Button>
            {diagnosisBackedWebsite && (
              <p className="text-xs text-muted-foreground">
                Using diagnosis-backed website: {diagnosisBackedWebsite.websiteUrl}.
              </p>
            )}
            {!diagnosisBackedWebsite && !websiteTest?.firstWebsite && (
              <p className="text-xs text-muted-foreground">
                Run "Test website service" first — needs a website id.
              </p>
            )}
            {declineDiagnosisTest && (
              <p className="text-sm text-muted-foreground">
                {declineDiagnosisTest.count} live diagnosis(es) found — by type:{" "}
                {Object.entries(declineDiagnosisTest.typeCounts)
                  .map(([type, count]) => `${type}: ${count}`)
                  .join(", ") || "none"}
                {declineDiagnosisTest.firstDiagnosisSummary && (
                  <>
                    . First: [{declineDiagnosisTest.firstDiagnosisType}/
                    {declineDiagnosisTest.firstDiagnosisSeverity}/{declineDiagnosisTest.firstDiagnosisStatus}]{" "}
                    {declineDiagnosisTest.firstDiagnosisSummary}
                  </>
                )}
                .
              </p>
            )}
            {declineDiagnosisTestWarning && (
              <p className="text-sm text-destructive">{declineDiagnosisTestWarning}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label>
              Test Diagnosis Evidence (dev-only, Supabase-only diagnostic, optional — reads raw evidence
              rows for the first diagnosis found above; same no-mock-equivalent caveat)
            </Label>
            <Button
              variant="outline"
              onClick={handleTestDiagnosisEvidence}
              disabled={isTestingDiagnosisEvidence || !declineDiagnosisTest?.firstDiagnosisId}
            >
              {isTestingDiagnosisEvidence ? "Checking..." : "Test Diagnosis Evidence"}
            </Button>
            {!declineDiagnosisTest?.firstDiagnosisId && (
              <p className="text-xs text-muted-foreground">
                Run "Test Decline Diagnosis Current View" first — needs a diagnosis id.
              </p>
            )}
            {diagnosisEvidenceTest && (
              <p className="text-sm text-muted-foreground">
                {diagnosisEvidenceTest.count} evidence row(s) found
                {diagnosisEvidenceTest.firstEvidenceSummary
                  ? ` — first: "${diagnosisEvidenceTest.firstEvidenceSummary}"`
                  : ""}
                .
              </p>
            )}
            {diagnosisEvidenceTestWarning && (
              <p className="text-sm text-destructive">{diagnosisEvidenceTestWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">
              Phase 15A — Off-Page Authority + AI Visibility/GEO (read-only)
            </p>

            <div className="space-y-2">
              <Label>
                Find website with Off-Page Authority data (dev-only, Supabase-only — searches every
                accessible SEO workspace/website for the current user for opportunities; used
                automatically by the button below when found)
              </Label>
              <Button
                variant="outline"
                onClick={handleFindAuthorityWebsite}
                disabled={isFindingAuthorityWebsite}
              >
                {isFindingAuthorityWebsite ? "Searching..." : "Find website with Off-Page Authority data"}
              </Button>
              {authorityBackedWebsite && (
                <p className="text-sm text-muted-foreground">
                  Found — workspace: "{authorityBackedWebsite.workspaceName}", website:{" "}
                  {authorityBackedWebsite.websiteUrl}, opportunity count:{" "}
                  {authorityBackedWebsite.opportunityCount} (highest among{" "}
                  {authorityBackedWebsite.candidateCount} accessible website
                  {authorityBackedWebsite.candidateCount === 1 ? "" : "s"} with opportunities).
                </p>
              )}
              {findAuthorityWebsiteWarning && (
                <p className="text-sm text-destructive">{findAuthorityWebsiteWarning}</p>
              )}
            </div>

            <Button
              variant="outline"
              onClick={handleTestAuthority}
              disabled={isTestingAuthority}
            >
              {isTestingAuthority ? "Checking..." : "Test Off-Page Authority Service"}
            </Button>
            <p className="text-xs text-muted-foreground">
              Resolves its own website id the same way the Stage 6 Resolution Diagnostics section
              below does (cross-workspace fallback if the active website has no Stage 6 data) — no
              need to click "Find website with Off-Page Authority data" or "Test website service"
              first.
            </p>
            {authorityTest && (
              <p className="text-sm text-muted-foreground">
                Queried website id: {authorityTest.requestedWebsiteId ?? "(none)"}. {" "}
                {authorityTest.opportunityCount} opportunit{authorityTest.opportunityCount === 1 ? "y" : "ies"} — by
                status:{" "}
                {Object.entries(authorityTest.statusCounts)
                  .map(([status, count]) => `${status}: ${count}`)
                  .join(", ") || "none"}
                . {authorityTest.campaignCount} campaign(s), {authorityTest.activityCount} activity row(s)
                {authorityTest.firstOpportunityTitle && (
                  <> . First: "{authorityTest.firstOpportunityTitle}"</>
                )}
                .
              </p>
            )}
            {authorityTestWarning && (
              <p className="text-sm text-destructive">{authorityTestWarning}</p>
            )}

            <div className="space-y-2 border-t border-border pt-3">
              <Label>
                Find website with AI Visibility data (dev-only, Supabase-only — searches every
                accessible SEO workspace/website for the current user for prompt-tracking rows; used
                automatically by the button below when found)
              </Label>
              <Button
                variant="outline"
                onClick={handleFindAiVisibilityWebsite}
                disabled={isFindingAiVisibilityWebsite}
              >
                {isFindingAiVisibilityWebsite ? "Searching..." : "Find website with AI Visibility data"}
              </Button>
              {aiVisibilityBackedWebsite && (
                <p className="text-sm text-muted-foreground">
                  Found — workspace: "{aiVisibilityBackedWebsite.workspaceName}", website:{" "}
                  {aiVisibilityBackedWebsite.websiteUrl}, prompt count:{" "}
                  {aiVisibilityBackedWebsite.promptCount} (highest among{" "}
                  {aiVisibilityBackedWebsite.candidateCount} accessible website
                  {aiVisibilityBackedWebsite.candidateCount === 1 ? "" : "s"} with prompts).
                </p>
              )}
              {findAiVisibilityWebsiteWarning && (
                <p className="text-sm text-destructive">{findAiVisibilityWebsiteWarning}</p>
              )}
            </div>

            <Button
              variant="outline"
              onClick={handleTestAiVisibility}
              disabled={isTestingAiVisibility}
            >
              {isTestingAiVisibility ? "Checking..." : "Test AI Visibility Service"}
            </Button>
            <p className="text-xs text-muted-foreground">
              Resolves its own website id the same way the Stage 6 Resolution Diagnostics section
              below does (cross-workspace fallback if the active website has no Stage 6 data) — no
              need to click "Find website with AI Visibility data" or "Test website service" first.
            </p>
            {aiVisibilityTest && (
              <p className="text-sm text-muted-foreground">
                Queried website id: {aiVisibilityTest.requestedWebsiteId ?? "(none)"}. {" "}
                {aiVisibilityTest.promptCount} prompt(s) — by visibility:{" "}
                {Object.entries(aiVisibilityTest.visibilityCounts)
                  .map(([status, count]) => `${status}: ${count}`)
                  .join(", ") || "none"}
                . {aiVisibilityTest.contentGapCount} content gap(s), {aiVisibilityTest.mentionCount} mention(s) — by
                type:{" "}
                {Object.entries(aiVisibilityTest.mentionTypeCounts)
                  .map(([type, count]) => `${type}: ${count}`)
                  .join(", ") || "none"}
                .
              </p>
            )}
            {aiVisibilityTestWarning && (
              <p className="text-sm text-destructive">{aiVisibilityTestWarning}</p>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="text-xs font-medium text-muted-foreground">
              Stage 6 Resolution Diagnostics (dev-only, read-only)
            </p>
            <p className="text-xs text-muted-foreground">
              Snapshots exactly how AuthorityBuilderPage.tsx / AiVisibilityPage.tsx would resolve a
              website to query right now, without loading either page. Read-only: does not mutate the
              shared active-website context, does not write anything, and does not hardcode any
              workspace/website id.
            </p>
            <Button
              variant="outline"
              onClick={handleRunStage6ResolutionDiagnostics}
              disabled={isRunningStage6ResolutionDiagnostics}
            >
              {isRunningStage6ResolutionDiagnostics ? "Running..." : "Run Stage 6 Resolution Diagnostics"}
            </Button>
            {stage6ResolutionDiagnosticsWarning && (
              <p className="text-sm text-destructive">{stage6ResolutionDiagnosticsWarning}</p>
            )}

            {stage6ResolutionDiagnostics && (
              <div className="space-y-3">
                <div className="space-y-2">
                  <InfoRow
                    label="Signed-in user email"
                    value={stage6ResolutionDiagnostics.userEmail ?? "(none)"}
                  />
                  <InfoRow
                    label="Signed-in user id"
                    value={stage6ResolutionDiagnostics.userId ?? "(none)"}
                  />
                  <InfoRow label="Current service mode" value={stage6ResolutionDiagnostics.dataMode} />
                  <InfoRow
                    label="Resolved SEO workspace id"
                    value={
                      stage6ResolutionDiagnostics.resolvedWorkspaceId ??
                      `(none${stage6ResolutionDiagnostics.resolvedWorkspaceReason ? ` — ${stage6ResolutionDiagnostics.resolvedWorkspaceReason}` : ""})`
                    }
                  />
                  <InfoRow
                    label="Resolved active website id"
                    value={stage6ResolutionDiagnostics.activeWebsiteId ?? "(none)"}
                  />
                  <InfoRow
                    label="Resolved active website URL"
                    value={stage6ResolutionDiagnostics.activeWebsiteUrl ?? "(none)"}
                  />
                </div>

                <div className="space-y-2 border-t border-border pt-2">
                  <InfoRow
                    label="Off-Page Authority requested website id"
                    value={stage6ResolutionDiagnostics.offPageRequestedWebsiteId ?? "(none)"}
                  />
                  <InfoRow
                    label="Off-Page cross-workspace fallback ran"
                    value={stage6ResolutionDiagnostics.offPageFallbackRan ? "yes" : "no"}
                  />
                  <InfoRow
                    label="Off-Page finder candidate website id"
                    value={stage6ResolutionDiagnostics.offPageCandidateWebsiteId ?? "(none found)"}
                  />
                  <InfoRow
                    label="Off-Page finder candidate count"
                    value={String(stage6ResolutionDiagnostics.offPageCandidateCount)}
                  />
                </div>

                <div className="space-y-2 border-t border-border pt-2">
                  <InfoRow
                    label="AI Visibility requested website id"
                    value={stage6ResolutionDiagnostics.aiVisibilityRequestedWebsiteId ?? "(none)"}
                  />
                  <InfoRow
                    label="AI Visibility cross-workspace fallback ran"
                    value={stage6ResolutionDiagnostics.aiVisibilityFallbackRan ? "yes" : "no"}
                  />
                  <InfoRow
                    label="AI Visibility finder candidate website id"
                    value={stage6ResolutionDiagnostics.aiVisibilityCandidateWebsiteId ?? "(none found)"}
                  />
                  <InfoRow
                    label="AI Visibility finder candidate count"
                    value={String(stage6ResolutionDiagnostics.aiVisibilityCandidateCount)}
                  />
                </div>

                <div className="space-y-2 border-t border-border pt-2">
                  <InfoRow
                    label="No RLS-visible Stage 6 website found (either finder)"
                    value={stage6ResolutionDiagnostics.noRlsVisibleStage6Website ? "yes" : "no"}
                  />
                </div>

                <div className="space-y-2 border-t border-border pt-2">
                  <p className="text-xs font-medium text-muted-foreground">
                    Real seo_workspace_members.seo_role (via getCurrentSeoRole — not
                    MOCK_CURRENT_ROLE)
                  </p>
                  <InfoRow
                    label="Workspace id used for the role lookup"
                    value={
                      stage6ResolutionDiagnostics.roleLookupWorkspaceId ??
                      "(skipped — no resolved workspace id)"
                    }
                  />
                  <InfoRow
                    label="Resolved seo_role"
                    value={
                      stage6ResolutionDiagnostics.roleLookupFailed
                        ? "(lookup failed — see error below)"
                        : !stage6ResolutionDiagnostics.roleLookupWorkspaceId
                          ? "(not attempted)"
                          : (stage6ResolutionDiagnostics.resolvedSeoRole ??
                            "(none — no active membership role found)")
                    }
                  />
                </div>

                {stage6ResolutionDiagnostics.errors.length > 0 && (
                  <div className="space-y-1 border-t border-border pt-2">
                    <p className="text-xs font-medium text-muted-foreground">
                      Supabase error code / message (per step, when present)
                    </p>
                    {stage6ResolutionDiagnostics.errors.map((err, index) => (
                      <p key={`${err.step}-${index}`} className="text-sm text-destructive">
                        {err.step}: [{err.code ?? "—"}] {err.message}
                      </p>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <Label htmlFor="dev-new-website-url">
              Create test website (dev-only — no crawling, insert-only, no deletes)
            </Label>
            <div className="flex flex-wrap gap-2">
              <Input
                id="dev-new-website-url"
                className="max-w-sm"
                value={newWebsiteUrl}
                onChange={(e) => setNewWebsiteUrl(e.target.value)}
              />
              <Button variant="outline" onClick={handleCreateTestWebsite} disabled={isCreatingWebsite}>
                {isCreatingWebsite ? "Creating..." : "Create test website"}
              </Button>
            </div>
            {createWebsiteResult && (
              <p className="text-sm text-muted-foreground">{createWebsiteResult}</p>
            )}
            {createWebsiteWarning && (
              <p className="text-sm text-destructive">{createWebsiteWarning}</p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between border-b border-border py-1 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
