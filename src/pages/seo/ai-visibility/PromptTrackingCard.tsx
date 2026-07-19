import type { PromptTrackingRecord } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { VISIBILITY_STATUS_LABEL, VISIBILITY_STATUS_VARIANT } from "./aiVisibilityLabels";

interface PromptTrackingCardProps {
  record: PromptTrackingRecord;
}

export function PromptTrackingCard({ record }: PromptTrackingCardProps) {
  return (
    <Card>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <h3 className="font-medium text-foreground">"{record.prompt_text}"</h3>
          <Badge variant={VISIBILITY_STATUS_VARIANT[record.visibility_status]}>
            {VISIBILITY_STATUS_LABEL[record.visibility_status]}
          </Badge>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">Topic: {record.topic}</Badge>
          <Badge variant={record.brand_mentioned ? "default" : "outline"}>
            Brand mentioned: {record.brand_mentioned ? "Yes" : "No"}
          </Badge>
          <Badge variant={record.our_site_cited ? "default" : "outline"}>
            Your site cited: {record.our_site_cited ? "Yes" : "No"}
          </Badge>
        </div>
        {record.competitors_mentioned.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {record.competitors_mentioned.map((c) => (
              <Badge key={c} variant="outline">
                Competitor: {c}
              </Badge>
            ))}
          </div>
        )}
        {record.citation_sources.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {record.citation_sources.map((s) => (
              <Badge key={s} variant="secondary">
                {s}
              </Badge>
            ))}
          </div>
        )}
      </CardHeader>
      <CardContent className="space-y-2 border-t border-border pt-3 text-sm">
        <div>
          <p className="font-medium text-foreground">Gap summary</p>
          <p className="text-muted-foreground">{record.gap_summary}</p>
        </div>
        <div>
          <p className="font-medium text-foreground">Recommended next step</p>
          <p className="text-muted-foreground">{record.recommended_next_step}</p>
        </div>
      </CardContent>
    </Card>
  );
}
