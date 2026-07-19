import { useState } from "react";
import type { ImpactLevel, NewSupportRequestInput, RelatedModule, SupportMode, SupportRequestType, SupportUrgency } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { RELATED_MODULE_LABEL, RELATED_MODULE_OPTIONS, REQUEST_TYPE_LABEL, SUPPORT_MODE_LABEL } from "./supportLabels";

const REQUEST_TYPE_OPTIONS: SupportRequestType[] = [
  "technical_seo_fix",
  "content_review",
  "onpage_seo_review",
  "offpage_authority_support",
  "pr_mention_support",
  "publishing_help",
  "strategy_review",
  "developer_support",
  "ai_visibility_review",
  "other",
];

const SUPPORT_MODE_OPTIONS: SupportMode[] = [
  "expert_review",
  "developer_needed",
  "manual_execution",
  "strategy_call",
];

const PRIORITY_OPTIONS: ImpactLevel[] = ["low", "medium", "high"];

export interface NewSupportRequestPrefill {
  title?: string;
  request_type?: SupportRequestType;
  related_module?: RelatedModule;
  related_item_url?: string;
}

interface NewSupportRequestFormProps {
  prefill?: NewSupportRequestPrefill;
  onSubmit: (input: NewSupportRequestInput) => void;
  onCancel: () => void;
  isSubmitting: boolean;
}

export function NewSupportRequestForm({ prefill, onSubmit, onCancel, isSubmitting }: NewSupportRequestFormProps) {
  const [requestType, setRequestType] = useState<SupportRequestType>(prefill?.request_type ?? "technical_seo_fix");
  const [title, setTitle] = useState(prefill?.title ?? "");
  const [description, setDescription] = useState("");
  const [relatedModule, setRelatedModule] = useState<RelatedModule>(prefill?.related_module ?? "other");
  const [relatedItemUrl, setRelatedItemUrl] = useState(prefill?.related_item_url ?? "");
  const [priority, setPriority] = useState<ImpactLevel>("medium");
  const [urgency, setUrgency] = useState<SupportUrgency>("normal");
  const [supportMode, setSupportMode] = useState<SupportMode>("expert_review");
  const [attachmentName, setAttachmentName] = useState("");
  const [notes, setNotes] = useState("");

  const canSubmit = title.trim().length > 0 && description.trim().length > 0;

  const handleSubmit = () => {
    if (!canSubmit) return;
    onSubmit({
      request_type: requestType,
      title: title.trim(),
      description: description.trim(),
      related_module: relatedModule,
      related_item_url: relatedItemUrl.trim() || undefined,
      priority,
      urgency,
      preferred_support_mode: supportMode,
      attachment: attachmentName.trim()
        ? { file_name: attachmentName.trim(), uploaded_at: new Date().toISOString() }
        : undefined,
      notes: notes.trim() || undefined,
    });
  };

  return (
    <Card className="border-dashed">
      <CardHeader>
        <CardTitle className="text-base">New support request</CardTitle>
        <CardDescription>Send this to Digibility experts for review — nothing is sent automatically.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1">
            <Label htmlFor="sup-request-type">Request type</Label>
            <Select
              id="sup-request-type"
              value={requestType}
              onChange={(e) => setRequestType(e.target.value as SupportRequestType)}
            >
              {REQUEST_TYPE_OPTIONS.map((t) => (
                <option key={t} value={t}>
                  {REQUEST_TYPE_LABEL[t]}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="sup-related-module">Related module</Label>
            <Select
              id="sup-related-module"
              value={relatedModule}
              onChange={(e) => setRelatedModule(e.target.value as RelatedModule)}
            >
              {RELATED_MODULE_OPTIONS.map((m) => (
                <option key={m} value={m}>
                  {RELATED_MODULE_LABEL[m]}
                </option>
              ))}
            </Select>
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="sup-title">Request title</Label>
          <Input id="sup-title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Help removing a noindex tag" />
        </div>

        <div className="space-y-1">
          <Label htmlFor="sup-description">Description</Label>
          <Textarea
            id="sup-description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="What do you need help with?"
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor="sup-related-url">Related page/item URL (optional)</Label>
          <Input
            id="sup-related-url"
            value={relatedItemUrl}
            onChange={(e) => setRelatedItemUrl(e.target.value)}
            placeholder="https://..."
          />
        </div>

        <div className="grid gap-3 sm:grid-cols-3">
          <div className="space-y-1">
            <Label htmlFor="sup-priority">Priority</Label>
            <Select id="sup-priority" value={priority} onChange={(e) => setPriority(e.target.value as ImpactLevel)}>
              {PRIORITY_OPTIONS.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="sup-urgency">Urgency</Label>
            <Select id="sup-urgency" value={urgency} onChange={(e) => setUrgency(e.target.value as SupportUrgency)}>
              <option value="normal">Normal</option>
              <option value="urgent">Urgent</option>
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="sup-mode">Preferred support mode</Label>
            <Select id="sup-mode" value={supportMode} onChange={(e) => setSupportMode(e.target.value as SupportMode)}>
              {SUPPORT_MODE_OPTIONS.map((m) => (
                <option key={m} value={m}>
                  {SUPPORT_MODE_LABEL[m]}
                </option>
              ))}
            </Select>
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="sup-attachment">Attachment (filename only — not uploaded)</Label>
          <Input
            id="sup-attachment"
            value={attachmentName}
            onChange={(e) => setAttachmentName(e.target.value)}
            placeholder="e.g. screenshot.png"
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor="sup-notes">Notes/context (optional)</Label>
          <Textarea id="sup-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>

        <div className="flex gap-2">
          <Button size="sm" onClick={handleSubmit} disabled={!canSubmit || isSubmitting}>
            Submit request
          </Button>
          <Button size="sm" variant="outline" onClick={onCancel} disabled={isSubmitting}>
            Cancel
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
