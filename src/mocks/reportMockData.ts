import type { ProgressReport, SeoBaseRecord, SeoWebsite } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const REPORTS_KEY = "progress_reports";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has a seeded report — siteB intentionally has none so the "no
// reports yet" empty state has something to demonstrate.
const seedReports: ProgressReport[] = [
  {
    id: "rpt_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-05T09:00:00.000Z",
    updated_at: "2026-07-05T09:00:00.000Z",
    period_key: "last_month",
    period_label: "June 2026",
    period_start: "2026-06-01",
    period_end: "2026-06-30",
    status: "generated",
    generated_at: "2026-07-05T09:00:00.000Z",
    overall_score_current: 62,
    overall_score_previous: 56,
    overall_score_movement: 6,
    technical_summary: "1 technical issue found and 1 fixed during this period.",
    issues_found_count: 1,
    issues_fixed_count: 1,
    pending_approvals_count: 1,
    content_summary: "1 content opportunity identified, nothing published yet.",
    content_pieces_planned: 4,
    content_pieces_completed: 0,
    performance_summary: "Homepage improving; 2 service pages declining.",
    declining_pages_count: 2,
    improving_pages_count: 1,
    offpage_summary: "9 authority opportunities identified, 2 flagged as risky and avoided.",
    authority_opportunities_count: 9,
    ai_visibility_summary: "Cited in 2 of 4 tracked AI answers so far.",
    ai_content_gaps_count: 3,
    competitor_summary: "2 competitors tracked; trailing on reviews and AI visibility.",
    competitor_gaps_count: 3,
    roadmap_summary: "90-day roadmap generated; early actions in progress.",
    roadmap_completed_count: 0,
    roadmap_total_count: 1,
    expert_support_summary: "No open support requests yet.",
    open_support_requests_count: 0,
    next_actions: [
      "Review the pending approval in the Approval Queue.",
      "Add pricing detail to the drain cleaning service page.",
      "Ask recent customers for Google reviews.",
    ],
  },
];

// Guards against stale localStorage from before the Phase 10 schema rewrite
// (old SeoReport shape had no `next_actions` array).
export const mockProgressReports: ProgressReport[] = loadMockCollection(
  REPORTS_KEY,
  seedReports,
  (item) => Array.isArray(item.next_actions),
);

function persist(): void {
  saveMockCollection(REPORTS_KEY, mockProgressReports);
}

export function listReports(websiteId: string): ProgressReport[] {
  return mockProgressReports.filter((r) => r.website_id === websiteId);
}

export function getReportForPeriod(
  websiteId: string,
  periodKey: ProgressReport["period_key"],
): ProgressReport | null {
  return mockProgressReports.find((r) => r.website_id === websiteId && r.period_key === periodKey) ?? null;
}

export function getLatestReport(websiteId: string): ProgressReport | null {
  const reports = listReports(websiteId);
  return reports.reduce<ProgressReport | null>((latest, r) => {
    if (!latest) return r;
    return new Date(r.generated_at).getTime() > new Date(latest.generated_at).getTime() ? r : latest;
  }, null);
}

// Replaces the snapshot for this website+period (creating one if it doesn't
// exist yet) — used whenever the user generates or refreshes a report.
export function upsertReport(
  website: SeoWebsite,
  periodKey: ProgressReport["period_key"],
  data: Omit<ProgressReport, keyof SeoBaseRecord | "period_key">,
): ProgressReport {
  const now = new Date().toISOString();
  const existing = getReportForPeriod(website.id, periodKey);

  const report: ProgressReport = {
    id: existing?.id ?? `rpt_mock_gen_${website.id}_${periodKey}`,
    workspace_id: website.workspace_id,
    website_id: website.id,
    website_url: website.website_url,
    user_id: website.user_id,
    created_by: website.user_id,
    created_at: existing?.created_at ?? now,
    updated_at: now,
    period_key: periodKey,
    ...data,
  };

  const remaining = mockProgressReports.filter((r) => !(r.website_id === website.id && r.period_key === periodKey));
  mockProgressReports.length = 0;
  mockProgressReports.push(...remaining, report);
  persist();
  return report;
}
