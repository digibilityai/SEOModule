import type { ConnectionStatus, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";

const STATUS_LABEL: Record<ConnectionStatus, string> = {
  connected: "Connected",
  pending: "Checking...",
  not_connected: "Not connected",
  error: "Needs attention",
};

const STATUS_VARIANT: Record<ConnectionStatus, "default" | "secondary" | "destructive" | "outline"> = {
  connected: "default",
  pending: "secondary",
  not_connected: "outline",
  error: "destructive",
};

const CHECKED_NOW_FIELDS: { key: keyof SeoWebsite; label: string }[] = [
  { key: "reachable_status", label: "Website reachable" },
  { key: "sitemap_status", label: "Sitemap" },
  { key: "robots_status", label: "Robots.txt" },
];

// These are real third-party integrations that aren't built yet — always show
// "Coming soon" rather than imply a live connection exists.
const FUTURE_INTEGRATIONS = [
  "Google Search Console",
  "GA4",
  "CMS",
  "Google Business Profile",
];

interface WebsiteConnectionHealthProps {
  website: SeoWebsite;
}

export function WebsiteConnectionHealth({ website }: WebsiteConnectionHealthProps) {
  return (
    <div className="space-y-3">
      <div>
        <p className="mb-1 text-xs font-medium text-muted-foreground">Checked now</p>
        <div className="flex flex-wrap gap-2">
          {CHECKED_NOW_FIELDS.map(({ key, label }) => {
            const status = website[key] as ConnectionStatus;
            return (
              <Badge key={key} variant={STATUS_VARIANT[status]}>
                {label}: {STATUS_LABEL[status]}
              </Badge>
            );
          })}
        </div>
      </div>
      <div>
        <p className="mb-1 text-xs font-medium text-muted-foreground">Ready for future connection</p>
        <div className="flex flex-wrap gap-2">
          {FUTURE_INTEGRATIONS.map((label) => (
            <Badge key={label} variant="outline">
              {label}: Coming soon
            </Badge>
          ))}
        </div>
      </div>
    </div>
  );
}
