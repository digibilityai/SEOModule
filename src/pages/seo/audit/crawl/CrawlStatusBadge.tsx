import { Badge } from "@/components/ui/badge";
import { crawlStatusLabel, crawlStatusTone } from "@/lib/crawlStatus";
import type { CrawlJobStatus } from "@/types/crawl";

// Tone → styling. A dot + text label ensures status is never conveyed by
// colour alone (accessibility).
const TONE_CLASS: Record<string, string> = {
  pending: "bg-muted text-muted-foreground",
  active: "bg-blue-100 text-blue-800 dark:bg-blue-950 dark:text-blue-200",
  success: "bg-green-100 text-green-800 dark:bg-green-950 dark:text-green-200",
  warning: "bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-200",
  error: "bg-red-100 text-red-800 dark:bg-red-950 dark:text-red-200",
  neutral: "bg-muted text-muted-foreground",
};

export function CrawlStatusBadge({ status }: { status: CrawlJobStatus }) {
  const tone = crawlStatusTone(status);
  const label = crawlStatusLabel(status);
  return (
    <Badge variant="secondary" className={TONE_CLASS[tone] ?? TONE_CLASS.neutral}>
      <span aria-hidden="true" className="mr-1">●</span>
      {label}
    </Badge>
  );
}
