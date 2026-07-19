import { useState } from "react";
import { Link } from "react-router-dom";
import type { ApprovalItem, RecommendationStatus, SeoUserRole } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { getAvailableActions } from "@/lib/approvalPermissions";
import { buildSupportRequestLink } from "@/lib/supportLinking";

const STATUS_LABEL: Record<RecommendationStatus, string> = {
  suggested: "Suggested",
  needs_review: "Needs review",
  approved: "Approved",
  rejected: "Rejected",
  expert_review_requested: "Expert review requested",
  developer_needed: "Developer needed",
  ready_to_publish: "Ready to publish",
  completed: "Completed",
};

const ACTION_TYPE_LABEL: Record<ApprovalItem["action_type"], string> = {
  auto_suggest: "Auto Suggest",
  approval_required: "Approval Required",
  manual_support: "Manual Support",
  expert_review: "Expert Review",
  avoid: "Avoid",
};

const FIX_OWNER_LABEL: Record<ApprovalItem["fix_owner"], string> = {
  client_action: "Client action",
  developer_needed: "Developer needed",
  digibility_expert: "Digibility expert",
  system_suggestion: "System suggestion",
};

interface ApprovalItemCardProps {
  item: ApprovalItem;
  role: SeoUserRole;
  isMutating: boolean;
  onStatusChange: (id: string, status: RecommendationStatus) => void;
  onSaveSuggestedChange: (id: string, suggestedChange: string) => void;
  onAddComment: (id: string, commentText: string) => void;
}

export function ApprovalItemCard({
  item,
  role,
  isMutating,
  onStatusChange,
  onSaveSuggestedChange,
  onAddComment,
}: ApprovalItemCardProps) {
  const actions = getAvailableActions(role, item);
  const [isEditing, setIsEditing] = useState(false);
  const [draftChange, setDraftChange] = useState(item.suggested_change);
  const [commentText, setCommentText] = useState("");

  const handleSaveEdit = () => {
    onSaveSuggestedChange(item.id, draftChange);
    setIsEditing(false);
  };

  const handleAddComment = () => {
    if (!commentText.trim()) return;
    onAddComment(item.id, commentText.trim());
    setCommentText("");
  };

  return (
    <Card className={item.is_high_risk_category ? "border-destructive/40" : undefined}>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <h3 className="font-medium text-foreground">{item.title}</h3>
          <Badge variant={item.is_high_risk_category ? "destructive" : "outline"}>
            {ACTION_TYPE_LABEL[item.action_type]}
          </Badge>
        </div>
        <p className="break-all text-xs text-muted-foreground">{item.page_url}</p>
        <p className="text-sm text-muted-foreground">{item.simple_explanation}</p>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">Impact: {item.impact}</Badge>
          <Badge variant="outline">Effort: {item.effort}</Badge>
          <Badge variant="outline">Risk: {item.risk}</Badge>
          <Badge variant="outline">Confidence: {item.confidence_percentage}%</Badge>
          <Badge variant="secondary">Status: {STATUS_LABEL[item.status]}</Badge>
          <Badge variant="outline">Owner: {FIX_OWNER_LABEL[item.fix_owner]}</Badge>
        </div>
        <p className="text-xs text-muted-foreground">
          Created {new Date(item.created_at).toLocaleDateString()} · Updated{" "}
          {new Date(item.updated_at).toLocaleDateString()}
        </p>
      </CardHeader>

      <CardContent className="space-y-4 border-t border-border pt-4 text-sm">
        <div>
          <p className="font-medium text-foreground">Suggested change</p>
          {isEditing ? (
            <div className="space-y-2">
              <Textarea value={draftChange} onChange={(e) => setDraftChange(e.target.value)} />
              <div className="flex gap-2">
                <Button size="sm" onClick={handleSaveEdit} disabled={isMutating}>
                  Save
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    setDraftChange(item.suggested_change);
                    setIsEditing(false);
                  }}
                >
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <p className="text-muted-foreground">{item.suggested_change}</p>
          )}
        </div>

        {item.is_high_risk_category && (
          <p className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
            This affects URLs, redirects, canonical tags, noindex tags, robots.txt or sitemap rules
            — it will only be applied after approval.
          </p>
        )}

        <div className="flex flex-wrap gap-2">
          <ActionButton
            label="Approve"
            availability={actions.approve}
            onClick={() => onStatusChange(item.id, "approved")}
            disabledExtra={isMutating}
          />
          <ActionButton
            label="Reject"
            availability={actions.reject}
            onClick={() => onStatusChange(item.id, "rejected")}
            disabledExtra={isMutating}
          />
          <ActionButton
            label="Edit suggestion"
            availability={actions.edit}
            onClick={() => setIsEditing(true)}
            disabledExtra={isMutating || isEditing}
          />
          <ActionButton
            label="Request expert review"
            availability={actions.expert_review}
            onClick={() => onStatusChange(item.id, "expert_review_requested")}
            disabledExtra={isMutating}
          />
          <ActionButton
            label="Send to developer"
            availability={actions.developer_needed}
            onClick={() => onStatusChange(item.id, "developer_needed")}
            disabledExtra={isMutating}
          />
          <ActionButton
            label="Mark completed"
            availability={actions.completed}
            onClick={() => onStatusChange(item.id, "completed")}
            disabledExtra={isMutating}
          />
        </div>

        {(item.fix_owner === "digibility_expert" || item.fix_owner === "developer_needed") && (
          <Button asChild size="sm" variant="outline">
            <Link
              to={buildSupportRequestLink({
                title: item.title,
                module: "approval_queue",
                url: item.page_url,
                type: item.fix_owner === "developer_needed" ? "developer_support" : "strategy_review",
              })}
            >
              Send to Expert Support Desk
            </Link>
          </Button>
        )}

        <div className="space-y-2 border-t border-border pt-3">
          <p className="font-medium text-foreground">Comments</p>
          {item.comments.length === 0 && (
            <p className="text-xs text-muted-foreground">No comments yet.</p>
          )}
          {item.comments.map((comment) => (
            <div key={comment.id} className="rounded-md bg-muted/40 px-3 py-2 text-xs">
              <p className="font-medium text-foreground">
                {comment.author_role} · {new Date(comment.created_at).toLocaleString()}
              </p>
              <p className="text-muted-foreground">{comment.comment_text}</p>
            </div>
          ))}
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
        </div>
      </CardContent>
    </Card>
  );
}

function ActionButton({
  label,
  availability,
  onClick,
  disabledExtra,
}: {
  label: string;
  availability: { allowed: boolean; reason?: string };
  onClick: () => void;
  disabledExtra?: boolean;
}) {
  if (!availability.allowed) {
    return (
      <Button size="sm" variant="outline" disabled title={availability.reason}>
        {label}
      </Button>
    );
  }
  return (
    <Button size="sm" variant="outline" onClick={onClick} disabled={disabledExtra}>
      {label}
    </Button>
  );
}
