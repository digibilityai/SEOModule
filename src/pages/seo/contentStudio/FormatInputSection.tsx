import { useState } from "react";
import type { ContentFormatInput, ContentFormatType } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";

const FORMAT_OPTIONS: { value: ContentFormatType; label: string }[] = [
  { value: "default", label: "Default Digibility format" },
  { value: "url_reference", label: "Paste URL as style reference" },
  { value: "file_reference", label: "Upload PDF/DOCX as format reference" },
  { value: "match_brand_style", label: "Match brand style" },
  { value: "custom_instructions", label: "Custom instructions" },
];

interface FormatInputSectionProps {
  formatInput: ContentFormatInput | null;
  isMutating: boolean;
  onSave: (input: {
    format_type: ContentFormatType;
    reference_url?: string;
    uploaded_file_name?: string;
    custom_instructions?: string;
  }) => void;
}

export function FormatInputSection({ formatInput, isMutating, onSave }: FormatInputSectionProps) {
  const [formatType, setFormatType] = useState<ContentFormatType>(formatInput?.format_type ?? "default");
  const [referenceUrl, setReferenceUrl] = useState(formatInput?.reference_url ?? "");
  const [fileName, setFileName] = useState(formatInput?.uploaded_file_name ?? "");
  const [customInstructions, setCustomInstructions] = useState(
    formatInput?.custom_instructions ?? "",
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Format Input</CardTitle>
        <CardDescription>Choose how the draft should be written.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        <div className="space-y-1.5">
          <Label htmlFor="format-type">Format</Label>
          <Select
            id="format-type"
            value={formatType}
            onChange={(e) => setFormatType(e.target.value as ContentFormatType)}
          >
            {FORMAT_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </Select>
        </div>

        {formatType === "url_reference" && (
          <div className="space-y-1.5">
            <Label htmlFor="reference-url">Reference URL</Label>
            <Input
              id="reference-url"
              value={referenceUrl}
              onChange={(e) => setReferenceUrl(e.target.value)}
              placeholder="https://example.com/a-page-you-like"
            />
          </div>
        )}

        {formatType === "file_reference" && (
          <div className="space-y-1.5">
            <Label htmlFor="reference-file">Reference file</Label>
            <Input
              id="reference-file"
              type="file"
              accept=".pdf,.docx"
              onChange={(e) => setFileName(e.target.files?.[0]?.name ?? "")}
            />
            {fileName && <p className="text-xs text-muted-foreground">Selected: {fileName}</p>}
            <p className="text-xs text-muted-foreground">
              Only the filename is stored for now — file contents aren't processed yet. Real
              document parsing is a future capability.
            </p>
          </div>
        )}

        {formatType === "custom_instructions" && (
          <div className="space-y-1.5">
            <Label htmlFor="custom-instructions">Instructions</Label>
            <Textarea
              id="custom-instructions"
              value={customInstructions}
              onChange={(e) => setCustomInstructions(e.target.value)}
              placeholder="e.g. Keep paragraphs short, use a friendly tone, avoid jargon."
            />
          </div>
        )}

        <Button
          size="sm"
          disabled={isMutating}
          onClick={() =>
            onSave({
              format_type: formatType,
              reference_url: formatType === "url_reference" ? referenceUrl || undefined : undefined,
              uploaded_file_name: formatType === "file_reference" ? fileName || undefined : undefined,
              custom_instructions:
                formatType === "custom_instructions" ? customInstructions || undefined : undefined,
            })
          }
        >
          Save format
        </Button>
      </CardContent>
    </Card>
  );
}
