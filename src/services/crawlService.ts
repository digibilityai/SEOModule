// Phase 16H / Crawler 1F — data-mode dispatcher for the customer crawl UI.
// Supabase mode = the authoritative RLS/RPC contracts; mock mode = a clearly
// labelled deterministic preview (no Supabase call). Supabase errors are NOT
// masked with mock success (fallbackToMockOnError = false) so real failures
// surface honest customer-safe states.
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { toAsync } from "@/lib/mockAsync";
import type {
  CrawlJobStatus,
  CrawlJobView,
  CrawlPublicationView,
  RequestCrawlResult,
} from "@/types/crawl";
import {
  requestSupabaseAuditCrawl,
  fetchSupabaseLatestCrawl,
  fetchSupabaseCrawlPublication,
  cancelSupabaseCrawl,
} from "@/services/supabase/seoCrawlSupabaseService";
import {
  mockRequestAuditCrawl,
  mockFetchLatestCrawl,
  mockFetchCrawlPublication,
  mockCancelCrawl,
} from "@/mocks/crawlMockData";

export async function requestAuditCrawl(websiteId: string): Promise<RequestCrawlResult> {
  return runWithServiceAdapter({
    label: "crawlService.requestAuditCrawl",
    mock: () => toAsync(mockRequestAuditCrawl(websiteId)),
    supabase: () => requestSupabaseAuditCrawl(websiteId),
    fallbackToMockOnError: false,
  });
}

export async function fetchLatestCrawl(websiteId: string): Promise<CrawlJobView | null> {
  return runWithServiceAdapter({
    label: "crawlService.fetchLatestCrawl",
    mock: () => toAsync(mockFetchLatestCrawl(websiteId)),
    supabase: () => fetchSupabaseLatestCrawl(websiteId),
    fallbackToMockOnError: false,
  });
}

export async function fetchCrawlPublication(
  websiteId: string,
  jobId: string,
): Promise<CrawlPublicationView | null> {
  return runWithServiceAdapter({
    label: "crawlService.fetchCrawlPublication",
    mock: () => toAsync(mockFetchCrawlPublication(jobId)),
    supabase: () => fetchSupabaseCrawlPublication(jobId),
    fallbackToMockOnError: false,
  });
}

export async function cancelCrawl(websiteId: string, jobId: string): Promise<CrawlJobStatus> {
  return runWithServiceAdapter({
    label: "crawlService.cancelCrawl",
    mock: () => toAsync(mockCancelCrawl(jobId)),
    supabase: () => cancelSupabaseCrawl(jobId),
    fallbackToMockOnError: false,
  });
}
