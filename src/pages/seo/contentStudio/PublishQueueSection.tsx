import type { ContentWorkflowStatus } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface PublishQueueSectionProps {
  status: ContentWorkflowStatus;
  isMutating: boolean;
  onSetStatus: (status: ContentWorkflowStatus) => void;
}

export function PublishQueueSection({ status, isMutating, onSetStatus }: PublishQueueSectionProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Publish Queue</CardTitle>
        <CardDescription>
          Digibility will not publish live website content without approval.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <Badge variant={status === "completed" ? "default" : "secondary"}>
          Status: {status.replace(/_/g, " ")}
        </Badge>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => onSetStatus("ready_for_publish")} disabled={isMutating}>
            Ready for publish
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => onSetStatus("expert_review_requested")}
            disabled={isMutating}
          >
            Expert review requested
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => onSetStatus("ready_for_publish")}
            disabled={isMutating}
          >
            Manual publishing needed
          </Button>
          <Button size="sm" variant="outline" onClick={() => onSetStatus("completed")} disabled={isMutating}>
            Mark completed
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
