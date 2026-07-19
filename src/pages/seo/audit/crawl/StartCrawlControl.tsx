import { useState } from "react";
import { Button } from "@/components/ui/button";
import { RoleGateTooltip } from "@/pages/seo/offpage/RoleGateTooltip";

interface StartCrawlControlProps {
  websiteUrl: string;
  /** Frontend affordance only — the RPC + RLS remain authoritative. */
  canRequest: boolean;
  /** True when a job is already active (prevents a second concurrent crawl). */
  hasActiveJob: boolean;
  isPending: boolean;
  isMock: boolean;
  onConfirm: () => void;
  errorMessage?: string | null;
}

// Role-gated Start Crawl with an explicit, accessible two-step confirmation
// (no dialog dependency in this repo). Clients see a disabled control with the
// shared accessible role tooltip and can never issue the request.
export function StartCrawlControl({
  websiteUrl,
  canRequest,
  hasActiveJob,
  isPending,
  isMock,
  onConfirm,
  errorMessage,
}: StartCrawlControlProps) {
  const [confirming, setConfirming] = useState(false);

  const disabled = !canRequest || hasActiveJob || isPending;

  if (confirming && canRequest && !hasActiveJob) {
    return (
      <div className="space-y-3 rounded-md border border-border p-4" role="group" aria-label="Confirm crawl">
        <p className="text-sm font-medium">Start a crawl of {websiteUrl}?</p>
        <ul className="list-disc space-y-1 pl-5 text-xs text-muted-foreground">
          <li>Only public pages are analysed. JavaScript rendering and logged-in areas are not crawled.</li>
          <li>The site's robots.txt rules are respected and the crawl is bounded.</li>
          <li>Results populate this website's Audit and Page Inventory.</li>
          {isMock && <li>Preview mode: this is a simulated crawl and writes nothing.</li>}
        </ul>
        <div className="flex gap-2">
          <Button
            size="sm"
            disabled={isPending}
            onClick={() => {
              setConfirming(false);
              onConfirm();
            }}
          >
            {isPending ? "Starting…" : "Confirm crawl"}
          </Button>
          <Button size="sm" variant="outline" onClick={() => setConfirming(false)} disabled={isPending}>
            Cancel
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <RoleGateTooltip
        show={!canRequest}
        tooltip="Requires the owner, admin, or team member role."
      >
        <Button
          size="sm"
          disabled={disabled}
          aria-disabled={disabled}
          onClick={() => setConfirming(true)}
        >
          {isPending ? "Starting…" : "Start crawl"}
        </Button>
      </RoleGateTooltip>
      {hasActiveJob && (
        <p className="text-xs text-muted-foreground">A crawl is already in progress for this website.</p>
      )}
      {errorMessage && (
        <p className="text-xs text-red-600 dark:text-red-400" role="alert">
          {errorMessage}
        </p>
      )}
    </div>
  );
}
