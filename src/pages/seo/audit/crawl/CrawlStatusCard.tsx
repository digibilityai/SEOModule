import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { CrawlStatusBadge } from "./CrawlStatusBadge";
import {
  isCancellableCrawlStatus,
  isTerminalCrawlStatus,
  formatCrawledOn,
} from "@/lib/crawlStatus";
import type { CrawlJobView, CrawlPublicationView } from "@/types/crawl";

interface CrawlStatusCardProps {
  job: CrawlJobView;
  publication: CrawlPublicationView | null;
  canCancel: boolean;
  isCancelling: boolean;
  onCancel: () => void;
}

function Metric({ label, value }: { label: string; value: number | null }) {
  if (value === null || value === undefined) return null;
  return (
    <div className="rounded-md bg-muted/50 px-3 py-2">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="text-sm font-medium tabular-nums">{value}</div>
    </div>
  );
}

// Customer-safe status detail. Never renders lease tokens, worker ids,
// correlation ids, config or raw diagnostics.
export function CrawlStatusCard({ job, publication, canCancel, isCancelling, onCancel }: CrawlStatusCardProps) {
  const requested = formatCrawledOn(job.requestedAt);
  const started = formatCrawledOn(job.startedAt);
  const finished = formatCrawledOn(job.completedAt);
  const heartbeat = formatCrawledOn(job.heartbeatAt);
  const published = formatCrawledOn(publication?.publishedAt);
  const terminal = isTerminalCrawlStatus(job.status);
  const showCancel = canCancel && isCancellableCrawlStatus(job.status);

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0">
        <CardTitle className="text-base">Crawl status</CardTitle>
        <CrawlStatusBadge status={job.status} />
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Live-region announcement of the current status for screen readers. */}
        <p className="sr-only" aria-live="polite">
          Crawl status: {job.status}
        </p>

        {job.status === "cancellation_requested" && (
          <p className="text-sm text-muted-foreground">
            Cancellation requested. The crawl will stop once the worker acknowledges it.
          </p>
        )}
        {job.status === "retry_wait" && (
          <p className="text-sm text-muted-foreground">
            Waiting to retry (attempt {job.attemptCount}). This is automatic — no action is needed.
          </p>
        )}
        {job.status === "partially_completed" && (
          <p className="text-sm text-muted-foreground">
            Some pages could not be processed or a crawl budget was reached. Usable results below are still valid;
            pages that were not seen this run are not treated as removed.
          </p>
        )}
        {job.status === "failed" && (
          <p className="text-sm text-red-600 dark:text-red-400" role="alert">
            {job.errorMessage ?? "The crawl could not be completed."}
          </p>
        )}
        {publication?.status === "failed" && job.status !== "failed" && (
          <p className="text-sm text-muted-foreground">The crawl produced no usable pages to publish.</p>
        )}

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          <Metric label="Pages discovered" value={job.pagesDiscovered} />
          <Metric label="Pages fetched" value={job.pagesCrawled} />
          <Metric label="Pages extracted" value={job.pagesExtracted} />
          <Metric label="Issues detected" value={job.issuesDetected} />
          <Metric label="Published pages" value={publication ? publication.pagesPublished : null} />
          <Metric label="Published issues" value={publication ? publication.issuesPublished : null} />
        </div>

        <dl className="grid grid-cols-1 gap-x-4 gap-y-1 text-xs text-muted-foreground sm:grid-cols-2">
          {requested && <div><dt className="inline">Requested: </dt><dd className="inline">{requested}</dd></div>}
          {started && <div><dt className="inline">Started: </dt><dd className="inline">{started}</dd></div>}
          {finished && <div><dt className="inline">Finished: </dt><dd className="inline">{finished}</dd></div>}
          {!terminal && heartbeat && (
            <div><dt className="inline">Last activity: </dt><dd className="inline">{heartbeat}</dd></div>
          )}
          {published && <div><dt className="inline">Results published: </dt><dd className="inline">{published}</dd></div>}
        </dl>

        {publication?.status === "published" && (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" asChild>
              <a href="#audit-results">View audit results</a>
            </Button>
            <Button size="sm" variant="outline" asChild>
              <Link to="/seo/page-performance">Open Page Inventory</Link>
            </Button>
          </div>
        )}

        {showCancel && (
          <div className="pt-1">
            <Button size="sm" variant="outline" onClick={onCancel} disabled={isCancelling}>
              {isCancelling ? "Cancelling…" : "Cancel crawl"}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
