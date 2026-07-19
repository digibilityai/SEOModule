import { MOCK_WORKSPACE_ID } from "@/mocks/mockContext";
import { fetchWebsites } from "@/services/websiteService";
import { fetchAudits } from "@/services/auditService";
import { fetchRecommendations } from "@/services/recommendationService";
import { fetchApprovalQueue } from "@/services/approvalService";
import { fetchContentOpportunities } from "@/services/contentStudioService";

// =============================================================================
// Phase 13F — Admin Preview read-only summary.
//
// This is a *composition* service, not a new Supabase integration: every
// call below goes through a service that was already wired to Supabase in
// an earlier phase (13B-13E). Because each of those already resolves its
// own mock/Supabase behavior via the shared adapter, composing them here
// gives correct data in both data modes with zero new adapter code and zero
// direct Supabase queries.
//
// This intentionally does NOT reuse seoAdminService.ts — that file spans
// every SEO module (including ones explicitly out of scope this phase, like
// Off-Page, AI Visibility, Competitors, Roadmap, Reports, Support) and is
// tied to the eventual real admin panel. Keeping this service small and
// separate avoids scope creep and keeps /seo/admin-preview clearly a
// temporary, minimal, read-only dev preview — not the final Digibility
// Admin Panel integration.
//
// Read-only: no writes, no RPC calls, no role/billing/module-access data.
// =============================================================================

export interface AdminPreviewSummary {
  websites_count: number;
  active_websites_count: number;
  latest_audit_runs_count: number;
  recommendations_count: number;
  approval_queue_pending_count: number;
  content_opportunities_count: number;
  connection_status_summary: {
    gsc_connected_count: number;
    ga4_connected_count: number;
    cms_connected_count: number;
    gbp_connected_count: number;
  };
}

export async function fetchAdminPreviewSummary(): Promise<AdminPreviewSummary> {
  const websites = await fetchWebsites(MOCK_WORKSPACE_ID);

  const [audits, recommendations, approvals, contentOpportunities] = await Promise.all([
    Promise.all(websites.map((w) => fetchAudits(w.id))),
    Promise.all(websites.map((w) => fetchRecommendations(w.id))),
    Promise.all(websites.map((w) => fetchApprovalQueue(w.id))),
    Promise.all(websites.map((w) => fetchContentOpportunities(w.id))),
  ]);

  return {
    websites_count: websites.length,
    active_websites_count: websites.filter((w) => w.status === "active").length,
    latest_audit_runs_count: audits.reduce((sum, list) => sum + list.length, 0),
    recommendations_count: recommendations.reduce((sum, list) => sum + list.length, 0),
    approval_queue_pending_count: approvals.reduce(
      (sum, list) => sum + list.filter((a) => a.status === "suggested" || a.status === "needs_review").length,
      0,
    ),
    content_opportunities_count: contentOpportunities.reduce((sum, list) => sum + list.length, 0),
    connection_status_summary: {
      gsc_connected_count: websites.filter((w) => w.gsc_status === "connected").length,
      ga4_connected_count: websites.filter((w) => w.ga4_status === "connected").length,
      cms_connected_count: websites.filter((w) => w.cms_status === "connected").length,
      gbp_connected_count: websites.filter((w) => w.gbp_status === "connected").length,
    },
  };
}
