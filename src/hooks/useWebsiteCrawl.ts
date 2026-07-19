// Phase 16H / Crawler 1F — focused hooks for the customer crawl workflow.
// Supabase is the single authoritative status source: polling via TanStack
// Query, stopped at terminal states, paused while the tab is hidden (default
// refetchIntervalInBackground=false), and reconciled on refresh. No second
// backend, no local fake progress. Query keys are user + website scoped;
// SessionSync already clears cache on user change (Phase 16B).
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/contexts/AuthContext";
import { useSeoAccess } from "@/hooks/useSeoAccess";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { getCurrentSeoRole } from "@/services/supabase/seoWorkspaceService";
import {
  requestAuditCrawl,
  fetchLatestCrawl,
  fetchCrawlPublication,
  cancelCrawl,
} from "@/services/crawlService";
import { isActiveCrawlStatus, CRAWL_REQUEST_ROLES } from "@/lib/crawlStatus";
import type { SeoUserRole } from "@/types/role";
import type { CrawlJobView, CrawlPublicationView, RequestCrawlResult } from "@/types/crawl";

const POLL_MS = 4000;

export function useWebsiteCrawlStatus(websiteId: string | null | undefined) {
  const { user } = useAuth();
  return useQuery<CrawlJobView | null>({
    queryKey: ["seo-crawl-status", websiteId, user?.id ?? null],
    queryFn: () => fetchLatestCrawl(websiteId!),
    enabled: !!websiteId,
    // Poll only while the job is active; stop at any terminal state.
    refetchInterval: (query) => {
      const s = query.state.data?.status;
      return s && isActiveCrawlStatus(s) ? POLL_MS : false;
    },
  });
}

export function useCrawlPublication(
  websiteId: string | null | undefined,
  jobId: string | null | undefined,
  enabled: boolean,
) {
  const { user } = useAuth();
  return useQuery<CrawlPublicationView | null>({
    queryKey: ["seo-crawl-publication", jobId, user?.id ?? null],
    queryFn: () => fetchCrawlPublication(websiteId!, jobId!),
    enabled: enabled && !!websiteId && !!jobId,
  });
}

/**
 * The signed-in user's real seo_role for the active workspace — used ONLY as a
 * frontend affordance gate (the RPC + RLS remain authoritative). Mock mode has
 * no real role concept, so gating is inactive there (matches the Stage 6 UX).
 */
export function useCrawlRequestPermission(): { canRequest: boolean; role: SeoUserRole | null; gatingActive: boolean } {
  const { user } = useAuth();
  const { workspaceId } = useSeoAccess();
  const gatingActive = isSupabaseMode();
  const roleQuery = useQuery<SeoUserRole | null>({
    queryKey: ["seo-crawl-role", workspaceId, user?.id ?? null],
    queryFn: () => getCurrentSeoRole(workspaceId!),
    enabled: gatingActive && !!workspaceId && !!user?.id,
    retry: false,
  });
  const role = roleQuery.data ?? null;
  const canRequest = !gatingActive || (role !== null && (CRAWL_REQUEST_ROLES as readonly string[]).includes(role));
  return { canRequest, role, gatingActive };
}

export function useRequestWebsiteCrawl(websiteId: string | null | undefined) {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  return useMutation<RequestCrawlResult, Error>({
    mutationFn: () => requestAuditCrawl(websiteId!),
    onSuccess: () => {
      // Re-read the authoritative job and audit history. The orchestration RPC
      // returns the exact ids; no client-side "latest audit" guessing occurs.
      void queryClient.invalidateQueries({ queryKey: ["seo-crawl-status", websiteId, user?.id ?? null] });
      void queryClient.invalidateQueries({ queryKey: ["seo-audits", websiteId] });
    },
  });
}

export function useCancelWebsiteCrawl(websiteId: string | null | undefined) {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  return useMutation<string, Error, string>({
    mutationFn: (jobId: string) => cancelCrawl(websiteId!, jobId),
    onSuccess: () => {
      // Cancellation may terminalize the linked running audit, so refresh both
      // lifecycle status and audit history immediately.
      void queryClient.invalidateQueries({ queryKey: ["seo-crawl-status", websiteId, user?.id ?? null] });
      void queryClient.invalidateQueries({ queryKey: ["seo-audits", websiteId] });
    },
  });
}
