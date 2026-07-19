import type { SeoAudit, SeoWebsite } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const STATUS_LABEL: Record<string, string> = {
  not_started: "Not started",
  running: "Running",
  completed: "Completed",
  failed: "Failed",
};

interface AuditHeaderProps {
  website: SeoWebsite;
  latestAudit: SeoAudit | null;
  isRunning: boolean;
  isMockMode: boolean;
  onRunAudit: () => void;
}

export function AuditHeader({
  website,
  latestAudit,
  isRunning,
  isMockMode,
  onRunAudit,
}: AuditHeaderProps) {
  const displayStatus = isRunning ? "running" : latestAudit?.status ?? "not_started";

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>{website.name}</CardTitle>
            <CardDescription>{website.website_url}</CardDescription>
          </div>

          {isMockMode && (
            <Button onClick={onRunAudit} disabled={isRunning}>
              {isRunning ? "Running audit..." : "Run Audit"}
            </Button>
          )}
        </div>
      </CardHeader>

      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge
            variant={
              displayStatus === "completed"
                ? "default"
                : displayStatus === "failed"
                  ? "destructive"
                  : "secondary"
            }
          >
            {isMockMode ? "Audit" : "Published audit"}: {STATUS_LABEL[displayStatus]}
          </Badge>

          <Badge variant="outline">
            {latestAudit?.completed_at
              ? `${isMockMode ? "Last audit" : "Published"}: ${new Date(
                  latestAudit.completed_at,
                ).toLocaleDateString()}`
              : isMockMode
                ? "No audit yet"
                : "No published audit yet"}
          </Badge>

          {isMockMode && latestAudit?.status === "completed" && (
            <Badge variant="secondary">
              Overall technical score: {latestAudit.technical_health_score}/100
            </Badge>
          )}
        </div>

        <p className="text-xs text-muted-foreground">
          {isMockMode
            ? "Mock audit for local testing. Real crawler integration will come later."
            : "Published technical findings come from the Website crawl workflow below. Crawl lifecycle status is shown separately."}
        </p>
      </CardContent>
    </Card>
  );
}
