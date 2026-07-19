import type {
  PendingApprovalsSummary,
  RecentActivityItem,
  RecommendedNextStep,
  SeoAudit,
  SeoWebsite,
  SetupChecklistItem,
  SetupChecklistItemKey,
  TopPriorityFix,
  VisibilityScoreCard,
  VisibilityScoreLabel,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { listTopPriorityFixes, listRecentActivity, addRecentActivity } from "@/mocks/dashboardMockData";
import { listApprovalQueue } from "@/mocks/approvalMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  fetchSupabasePendingApprovalsSummary,
  fetchSupabaseTopPriorityFixes,
} from "@/services/supabase/seoDashboardSupabaseService";

const IMPACT_WEIGHT: Record<string, number> = { high: 3, medium: 2, low: 1 };

export async function fetchTopPriorityFixes(websiteId: string): Promise<TopPriorityFix[]> {
  return runWithServiceAdapter({
    label: "dashboardService.fetchTopPriorityFixes",
    mock: () => {
      const fixes = [...listTopPriorityFixes(websiteId)].sort(
        (a, b) =>
          IMPACT_WEIGHT[b.impact] - IMPACT_WEIGHT[a.impact] ||
          b.confidence_percentage - a.confidence_percentage,
      );
      return toAsync(fixes);
    },
    supabase: () => fetchSupabaseTopPriorityFixes(websiteId),
  });
}

// Not wired this phase — no Stage 1-3 activity table is in the allowed
// read-only list for Phase 13F, and merging Stage 2 seo_approval_activity +
// Stage 3 seo_content_activity into one feed is a bigger scope than a
// read-only dashboard summary. Stays mock-only in every data mode.
export async function fetchRecentActivity(websiteId: string): Promise<RecentActivityItem[]> {
  const items = [...listRecentActivity(websiteId)].sort(
    (a, b) => new Date(b.occurred_at).getTime() - new Date(a.occurred_at).getTime(),
  );
  return toAsync(items);
}

export async function logRecentActivity(
  entry: Pick<
    RecentActivityItem,
    "workspace_id" | "website_id" | "website_url" | "user_id" | "activity_type" | "summary"
  >,
): Promise<RecentActivityItem> {
  return toAsync(addRecentActivity(entry));
}

export async function fetchPendingApprovalsSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<PendingApprovalsSummary> {
  return runWithServiceAdapter({
    label: "dashboardService.fetchPendingApprovalsSummary",
    mock: () => {
      const items = listApprovalQueue(websiteId);
      const pending = items.filter((i) => ["suggested", "needs_review"].includes(i.status)).length;
      const expertReview = items.filter((i) => i.status === "expert_review_requested").length;
      const developerNeeded = items.filter(
        (i) => i.fix_owner === "developer_needed" || i.status === "developer_needed",
      ).length;

      return toAsync({
        website_id: websiteId,
        website_url: websiteUrl,
        pending_count: pending,
        expert_review_count: expertReview,
        developer_needed_count: developerNeeded,
      });
    },
    supabase: () => fetchSupabasePendingApprovalsSummary(websiteId, websiteUrl),
  });
}

const SCORE_EXPLANATIONS: Record<VisibilityScoreCard["key"], string> = {
  overall: "How visible your business is in search overall.",
  technical_health: "How well search engines can crawl and understand your site.",
  onpage: "How well your pages are optimized for what customers search for.",
  authority: "How much trust and credibility your site has built online.",
  ai_discovery: "How often AI tools like ChatGPT might recommend your business.",
};

function scoreLabel(score: number): VisibilityScoreLabel {
  if (score >= 80) return "good";
  if (score >= 50) return "needs_attention";
  return "critical";
}

export function buildVisibilityScoreCards(audit: SeoAudit): VisibilityScoreCard[] {
  const entries: { key: VisibilityScoreCard["key"]; label: string; score: number }[] = [
    { key: "overall", label: "Overall Visibility", score: audit.overall_visibility_score },
    { key: "technical_health", label: "Technical Health", score: audit.technical_health_score },
    { key: "onpage", label: "On-Page SEO", score: audit.onpage_score },
    { key: "authority", label: "Authority", score: audit.authority_score },
    { key: "ai_discovery", label: "AI Discovery / GEO", score: audit.ai_discovery_score },
  ];

  return entries.map((entry) => ({
    ...entry,
    status_label: scoreLabel(entry.score),
    explanation: SCORE_EXPLANATIONS[entry.key],
  }));
}

const CHECKLIST_LABELS: Record<SetupChecklistItemKey, string> = {
  website_added: "Website added",
  sitemap_checked: "Sitemap checked",
  robots_checked: "Robots.txt checked",
  onboarding_completed: "Business onboarding completed",
  gsc_connected: "Google Search Console",
  ga4_connected: "GA4",
  cms_connected: "CMS",
};

export function buildSetupChecklist(
  website: SeoWebsite,
  isOnboardingComplete: boolean,
): SetupChecklistItem[] {
  const items: { key: SetupChecklistItemKey; isComplete: boolean; isFuture: boolean }[] = [
    { key: "website_added", isComplete: true, isFuture: false },
    { key: "sitemap_checked", isComplete: website.sitemap_status === "connected", isFuture: false },
    { key: "robots_checked", isComplete: website.robots_status === "connected", isFuture: false },
    { key: "onboarding_completed", isComplete: isOnboardingComplete, isFuture: false },
    { key: "gsc_connected", isComplete: false, isFuture: true },
    { key: "ga4_connected", isComplete: false, isFuture: true },
    { key: "cms_connected", isComplete: false, isFuture: true },
  ];

  return items.map(({ key, isComplete, isFuture }) => ({
    key,
    label: CHECKLIST_LABELS[key],
    is_complete: isComplete,
    is_future_integration: isFuture,
    status_label: isFuture ? "Coming soon" : isComplete ? "Done" : "Not connected",
  }));
}

interface NextStepParams {
  hasWebsite: boolean;
  isOnboardingComplete: boolean;
  hasCompletedAudit: boolean;
  hasPriorityFixes: boolean;
}

export function resolveRecommendedNextStep(params: NextStepParams): RecommendedNextStep {
  if (!params.hasWebsite) {
    return {
      type: "add_website",
      label: "Add your website",
      description: "Every SEO action starts with a website.",
      route: "/seo/websites",
    };
  }
  if (!params.isOnboardingComplete) {
    return {
      type: "complete_onboarding",
      label: "Complete business onboarding",
      description: "So recommendations aren't generic.",
      route: "/seo/onboarding",
    };
  }
  if (!params.hasCompletedAudit) {
    return {
      type: "run_first_audit",
      label: "Run your first audit",
      description: "See what's helping or hurting your visibility.",
      route: "/seo/audit",
    };
  }
  if (params.hasPriorityFixes) {
    return {
      type: "review_priority_fixes",
      label: "Review your priority fixes",
      description: "These are the actions that matter most right now.",
      route: "/seo/audit",
    };
  }
  return {
    type: "request_expert_support",
    label: "Request expert support",
    description: "Get hands-on help from a Digibility SEO expert.",
  };
}
