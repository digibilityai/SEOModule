import { useState } from "react";
import type { ExpertSupportRequest, SupportStatus } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { MOCK_CURRENT_ROLE } from "@/mocks/mockContext";
import {
  REQUEST_TYPE_LABEL,
  RELATED_MODULE_LABEL,
  SUPPORT_MODE_LABEL,
  SUPPORT_STATUS_LABEL,
  SUPPORT_STATUS_VARIANT,
  SUPPORT_URGENCY_VARIANT,
} from "./supportLabels";

const CAN_COMPLETE_ROLES = ["owner", "admin"];

interface SupportRequestCardProps {
  request: ExpertSupportRequest;
  onStatusChange: (id: string, status: SupportStatus) => void;
  onAddComment: (id: string, commentText: string) => void;
  onMarkInfoProvided: (id: string) => void;
  onCancelRequest: (id: string) => void;
  isMutating: boolean;
}

export function SupportRequestCard({
  request,
  onStatusChange,
  onAddComment,
  onMarkInfoProvided,
  onCancelRequest,
  isMutating,
}: SupportRequestCardProps) {
  const [expanded, setExpanded] = useState(false);
  const [commentText, setCommentText] = useState("");
  const canComplete = CAN_COMPLETE_ROLES.includes(MOCK_CURRENT_ROLE);
  const isClosed = request.status === "completed" || request.status === "cancelled";

  const handleAddComment = () => {
    if (!commentText.trim()) return;
    onAddComment(request.id, commentText.trim());
    setCommentText("");
  };

  const latestUpdate = request.activity[request.activity.length - 1];

  return (
    <Card>
      <CardHeader className="cursor-pointer select-none space-y-2" onClick={() => setExpanded((e) => !e)}>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <h3 className="font-medium text-foreground">{request.title}</h3>
          <Badge variant={SUPPORT_STATUS_VARIANT[request.status]}>{SUPPORT_STATUS_LABEL[request.status]}</Badge>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">{REQUEST_TYPE_LABEL[request.request_type]}</Badge>
          <Badge variant="outline">{RELATED_MODULE_LABEL[request.related_module]}</Badge>
          <Badge variant="outline">Priority: {request.priority}</Badge>
          <Badge variant={SUPPORT_URGENCY_VARIANT[request.urgency]}>Urgency: {request.urgency}</Badge>
          <Badge variant="outline">{SUPPORT_MODE_LABEL[request.preferred_support_mode]}</Badge>
        </div>
        <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
          <span>Owner: {request.assignee_placeholder ?? "Unassigned"}</span>
          <span>Created {new Date(request.created_at).toLocaleDateString()}</span>
          <span>Updated {new Date(request.updated_at).toLocaleDateString()}</span>
        </div>
        {request.related_item_url && (
          <p className="break-all text-xs text-muted-foreground">Related: {request.related_item_url}</p>
        )}
        {latestUpdate && <p className="text-xs text-muted-foreground">Latest: {latestUpdate.summary}</p>}
      </CardHeader>

      {expanded && (
        <CardContent className="space-y-4 border-t border-border pt-4 text-sm">
          <div>
            <p className="font-medium text-foreground">Full description</p>
            <p className="text-muted-foreground">{request.description}</p>
          </div>
          {request.notes && (
            <div>
              <p className="font-medium text-foreground">Notes</p>
              <p className="text-muted-foreground">{request.notes}</p>
            </div>
          )}
          {request.attachment && (
            <p className="text-xs text-muted-foreground">Attachment: {request.attachment.file_name}</p>
          )}

          <div>
            <p className="font-medium text-foreground">Activity timeline</p>
            <div className="space-y-1">
              {request.activity.map((a) => (
                <p key={a.id} className="text-xs text-muted-foreground">
                  {new Date(a.created_at).toLocaleString()} — {a.summary}
                </p>
              ))}
            </div>
          </div>

          <div className="space-y-2 border-t border-border pt-3">
            <p className="font-medium text-foreground">Comments</p>
            {request.comments.length === 0 && <p className="text-xs text-muted-foreground">No comments yet.</p>}
            {request.comments.map((c) => (
              <div key={c.id} className="rounded-md bg-muted/40 px-3 py-2 text-xs">
                <p className="font-medium text-foreground">
                  {c.author_role} · {new Date(c.created_at).toLocaleString()}
                </p>
                <p className="text-muted-foreground">{c.comment_text}</p>
              </div>
            ))}
            {!isClosed && (
              <div className="flex gap-2">
                <Textarea
                  placeholder="Add a comment..."
                  value={commentText}
                  onChange={(e) => setCommentText(e.target.value)}
                  className="min-h-10"
                />
                <Button size="sm" onClick={handleAddComment} disabled={isMutating || !commentText.trim()}>
                  Add
                </Button>
              </div>
            )}
          </div>

          {!isClosed && (
            <div className="flex flex-wrap gap-2 border-t border-border pt-3">
              {request.status === "waiting_for_client" && (
                <Button size="sm" variant="outline" disabled={isMutating} onClick={() => onMarkInfoProvided(request.id)}>
                  Mark additional info provided
                </Button>
              )}
              <Button
                size="sm"
                variant="outline"
                disabled={isMutating}
                onClick={() => onStatusChange(request.id, "in_progress")}
              >
                Mark in progress
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={isMutating || !canComplete}
                title={!canComplete ? "Only owner/admin can mark requests completed." : undefined}
                onClick={() => onStatusChange(request.id, "completed")}
              >
                Mark completed
              </Button>
              <Button size="sm" variant="destructive" disabled={isMutating} onClick={() => onCancelRequest(request.id)}>
                Cancel request
              </Button>
            </div>
          )}
        </CardContent>
      )}
    </Card>
  );
}
