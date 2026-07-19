import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { isSupabaseMode } from "@/config/runtimeConfig";
import {
  useWebsiteCrawlStatus,
  useCrawlPublication,
  useCrawlRequestPermission,
  useRequestWebsiteCrawl,
  useCancelWebsiteCrawl,
} from "@/hooks/useWebsiteCrawl";
import { isTerminalCrawlStatus } from "@/lib/crawlStatus";
import { StartCrawlControl } from "./StartCrawlControl";
import { CrawlStatusCard } from "./CrawlStatusCard";

interface CrawlPanelProps {
  websiteId: string;
  websiteUrl: string;
}

// Orchestrates the customer crawl workflow on the Audit surface. Supabase is
// the single authoritative status source; mock mode shows a clearly labelled
// preview. No worker is required to render this panel.
export function CrawlPanel({ websiteId, websiteUrl }: CrawlPanelProps) {
  const queryClient = useQueryClient();
  const isMock = !isSupabaseMode();

  const { canRequest } = useCrawlRequestPermission();
  const statusQuery = useWebsiteCrawlStatus(websiteId);
  const job = statusQuery.data ?? null;

  const terminal = job ? isTerminalCrawlStatus(job.status) : false;
  const publicationQuery = useCrawlPublication(websiteId, job?.id, !!job && terminal);
  const publication = publicationQuery.data ?? null;

  const requestMutation = useRequestWebsiteCrawl(websiteId);
  const cancelMutation = useCancelWebsiteCrawl(websiteId);

  const hasActiveJob = !!job && !isTerminalCrawlStatus(job.status);

  // When a job reaches a published terminal state, refresh the existing Audit +
  // Page-Inventory queries once so the customer sees the newly published data.
  const publishedFor = useRef<string | null>(null);
  useEffect(() => {
    if (job && terminal && publication?.status === "published" && publishedFor.current !== job.id) {
      publishedFor.current = job.id;
      void queryClient.invalidateQueries({ queryKey: ["seo-audits", websiteId] });
      void queryClient.invalidateQueries({ queryKey: ["seo-issues"] });
      void queryClient.invalidateQueries({ queryKey: ["seo-page-performance", websiteId] });
      void queryClient.invalidateQueries({ queryKey: ["seo-page-inventory", websiteId] });
    }
  }, [job, terminal, publication?.status, websiteId, queryClient]);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Website crawl</CardTitle>
        <CardDescription>
          Run an audit-backed crawl of this website's public pages to refresh its Audit and Page Inventory.
          {isMock && " Preview mode — a simulated crawl that writes nothing."}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <StartCrawlControl
          websiteUrl={websiteUrl}
          canRequest={canRequest}
          hasActiveJob={hasActiveJob}
          isPending={requestMutation.isPending}
          isMock={isMock}
          onConfirm={() => requestMutation.mutate()}
          errorMessage={requestMutation.isError ? "The crawl could not be requested. Please try again." : null}
        />

        {statusQuery.isError && (
          <p className="text-sm text-muted-foreground" role="alert">
            Crawl status is temporarily unavailable. It will refresh automatically.
          </p>
        )}

        {!statusQuery.isLoading && !statusQuery.isError && !job && (
          <p className="text-sm text-muted-foreground">
            No crawl has been requested for this website yet.
          </p>
        )}

        {job && hasActiveJob && isMock === false && (
          <p className="sr-only" aria-live="polite">A crawl is in progress.</p>
        )}

        {job && (
          <CrawlStatusCard
            job={job}
            publication={publication}
            canCancel={canRequest}
            isCancelling={cancelMutation.isPending}
            onCancel={() => cancelMutation.mutate(job.id)}
          />
        )}

        {job && hasActiveJob && isMock === false && (
          <p className="text-xs text-muted-foreground">
            The crawl runs on a background worker. In this test environment it may stay queued until an operator
            runs the worker.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
