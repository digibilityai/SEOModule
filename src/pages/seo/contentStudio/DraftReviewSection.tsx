import { useState } from "react";
import type { ContentDraft, DraftSection, DraftSectionAction } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";

const SECTION_STATUS_VARIANT: Record<DraftSection["status"], "default" | "secondary" | "destructive" | "outline"> = {
  generated: "secondary",
  approved: "default",
  rejected: "destructive",
  edited: "outline",
};

interface DraftReviewSectionProps {
  draft: ContentDraft;
  isMutating: boolean;
  isRegeneratingSectionId: string | null;
  regenerateError: string | null;
  onSectionAction: (sectionId: string, action: DraftSectionAction, editedContent?: string) => void;
  onRegenerateSection: (sectionId: string) => void;
  onApproveDraft: () => void;
  onRejectDraft: () => void;
  onSendToExpertReview: () => void;
  onAddFeedback: (text: string) => void;
}

function DraftSectionCard({
  section,
  isMutating,
  isRegenerating,
  onAction,
  onRegenerate,
}: {
  section: DraftSection;
  isMutating: boolean;
  isRegenerating: boolean;
  onAction: (action: DraftSectionAction, editedContent?: string) => void;
  onRegenerate: () => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [draftText, setDraftText] = useState(section.content);

  return (
    <div className="space-y-2 rounded-md border border-border p-3 text-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-medium text-foreground">{section.heading}</p>
        <div className="flex items-center gap-2">
          {section.regeneration_count > 0 && (
            <Badge variant="outline">Regenerated ×{section.regeneration_count}</Badge>
          )}
          <Badge variant={SECTION_STATUS_VARIANT[section.status]}>{section.status}</Badge>
        </div>
      </div>
      {isEditing ? (
        <div className="space-y-2">
          <Textarea value={draftText} onChange={(e) => setDraftText(e.target.value)} />
          <div className="flex gap-2">
            <Button
              size="sm"
              onClick={() => {
                onAction("edit", draftText);
                setIsEditing(false);
              }}
              disabled={isMutating}
            >
              Save
            </Button>
            <Button size="sm" variant="outline" onClick={() => setIsEditing(false)}>
              Cancel
            </Button>
          </div>
        </div>
      ) : (
        <p className="whitespace-pre-line text-muted-foreground">{section.content}</p>
      )}
      {!isEditing && (
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" onClick={() => onAction("approve")} disabled={isMutating}>
            Approve
          </Button>
          <Button size="sm" variant="outline" onClick={() => onAction("reject")} disabled={isMutating}>
            Reject
          </Button>
          <Button size="sm" variant="outline" onClick={onRegenerate} disabled={isRegenerating}>
            {isRegenerating ? "Regenerating..." : "Regenerate"}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              setDraftText(section.content);
              setIsEditing(true);
            }}
            disabled={isMutating}
          >
            Edit
          </Button>
        </div>
      )}
    </div>
  );
}

export function DraftReviewSection({
  draft,
  isMutating,
  isRegeneratingSectionId,
  regenerateError,
  onSectionAction,
  onRegenerateSection,
  onApproveDraft,
  onRejectDraft,
  onSendToExpertReview,
  onAddFeedback,
}: DraftReviewSectionProps) {
  const [feedback, setFeedback] = useState("");

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Draft Review</CardTitle>
        <CardDescription>
          Mock draft content for local testing. Real AI generation will come later.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {regenerateError && (
          <p className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
            {regenerateError}
          </p>
        )}
        <div className="space-y-3">
          {draft.sections.map((section) => (
            <DraftSectionCard
              key={section.id}
              section={section}
              isMutating={isMutating}
              isRegenerating={isRegeneratingSectionId === section.id}
              onAction={(action, editedContent) => onSectionAction(section.id, action, editedContent)}
              onRegenerate={() => onRegenerateSection(section.id)}
            />
          ))}
        </div>

        <div className="flex flex-wrap gap-2 border-t border-border pt-3">
          <Button size="sm" onClick={onApproveDraft} disabled={isMutating}>
            Approve draft
          </Button>
          <Button size="sm" variant="outline" onClick={onRejectDraft} disabled={isMutating}>
            Reject draft
          </Button>
          <Button size="sm" variant="outline" onClick={onSendToExpertReview} disabled={isMutating}>
            Send to expert review
          </Button>
        </div>

        <div className="space-y-2 border-t border-border pt-3 text-sm">
          <p className="font-medium text-foreground">Feedback</p>
          <div className="flex gap-2">
            <Textarea
              placeholder="Add feedback for this draft..."
              value={feedback}
              onChange={(e) => setFeedback(e.target.value)}
              className="min-h-10"
            />
            <Button
              size="sm"
              disabled={isMutating || !feedback.trim()}
              onClick={() => {
                onAddFeedback(feedback.trim());
                setFeedback("");
              }}
            >
              Add
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
