import type { SeoAudit, SeoIssue } from "@/types";
import { toAsync } from "@/lib/mockAsync";
import {
  listAudits,
  getAuditById,
  getLatestAudit,
  listIssuesForAudit,
  generateAuditRun,
  recordFailedAudit,
} from "@/mocks/auditMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  fetchSupabaseAuditById,
  fetchSupabaseAudits,
  fetchSupabaseIssuesForAudit,
  fetchSupabaseLatestAudit,
  runSupabaseAudit,
} from "@/services/supabase/seoAuditSupabaseService";

// Simulated crawl failure rate, purely for exercising the "failed" empty
// state until a real crawler is wired up.
const SIMULATED_FAILURE_RATE = 0.15;
const SIMULATED_AUDIT_DELAY_MS = 1400;

export async function fetchAudits(websiteId: string): Promise<SeoAudit[]> {
  return runWithServiceAdapter({
    label: "auditService.fetchAudits",
    mock: () => toAsync(listAudits(websiteId)),
    supabase: () => fetchSupabaseAudits(websiteId),
  });
}

export async function fetchLatestAudit(websiteId: string): Promise<SeoAudit | null> {
  return runWithServiceAdapter({
    label: "auditService.fetchLatestAudit",
    mock: () => toAsync(getLatestAudit(websiteId)),
    supabase: () => fetchSupabaseLatestAudit(websiteId),
  });
}

export async function fetchAuditById(id: string): Promise<SeoAudit | null> {
  return runWithServiceAdapter({
    label: "auditService.fetchAuditById",
    mock: () => toAsync(getAuditById(id)),
    supabase: () => fetchSupabaseAuditById(id),
  });
}

export async function fetchIssuesForAudit(auditId: string): Promise<SeoIssue[]> {
  return runWithServiceAdapter({
    label: "auditService.fetchIssuesForAudit",
    mock: () => toAsync(listIssuesForAudit(auditId)),
    supabase: () => fetchSupabaseIssuesForAudit(auditId),
  });
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Mock path: simulates crawl time + an occasional failure so the UI's
// running/failed states are exercised even without a real backend.
//
// Supabase path: triggers Stage 2's `seo_run_audit` RPC, which only creates
// a "running" run row (Stage 2 has no crawler) — this NEVER fabricates a
// "completed" audit or issues client-side in Supabase mode. The run stays
// "running" until a future service-role/crawler backend completes it. The
// only current caller (WebsiteAuditPage) already gates recommendation
// generation behind `status === "completed"`, so that path is naturally
// never reached in Supabase mode either.
export async function runAudit(
  websiteId: string,
  websiteUrl: string,
): Promise<{ audit: SeoAudit; issues: SeoIssue[] }> {
  return runWithServiceAdapter({
    label: "auditService.runAudit",
    mock: async () => {
      await wait(SIMULATED_AUDIT_DELAY_MS);
      if (Math.random() < SIMULATED_FAILURE_RATE) {
        const audit = recordFailedAudit(websiteId, websiteUrl);
        return { audit, issues: [] };
      }
      const { audit, issues } = generateAuditRun(websiteId, websiteUrl);
      return { audit, issues };
    },
    supabase: () => runSupabaseAudit(websiteId),
  });
}
