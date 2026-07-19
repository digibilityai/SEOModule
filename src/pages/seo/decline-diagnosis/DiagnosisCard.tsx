import { Link } from "react-router-dom";
import type { DeclineDiagnosis } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { buildSupportRequestLink } from "@/lib/supportLinking";
import { DECLINE_CAUSE_LABEL, FIX_OWNER_LABEL } from "../performance/performanceLabels";

const PRIORITY_VARIANT: Record<DeclineDiagnosis["priority"], "destructive" | "default" | "secondary"> = {
  high: "destructive",
  medium: "default",
  low: "secondary",
};

interface DiagnosisCardProps {
  diagnosis: DeclineDiagnosis;
  pageTitle?: string;
}

export function DiagnosisCard({ diagnosis, pageTitle }: DiagnosisCardProps) {
  return (
    <Card>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h3 className="font-medium text-foreground">
              {pageTitle ?? diagnosis.page_url}
            </h3>
            <p className="break-all text-xs text-muted-foreground">{diagnosis.page_url}</p>
          </div>
          <Badge variant={PRIORITY_VARIANT[diagnosis.priority]}>Priority: {diagnosis.priority}</Badge>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">Likely cause: {DECLINE_CAUSE_LABEL[diagnosis.likely_cause]}</Badge>
          <Badge variant="outline">Confidence: {diagnosis.confidence_percentage}%</Badge>
          <Badge variant="outline">Owner: {FIX_OWNER_LABEL[diagnosis.fix_owner]}</Badge>
          {diagnosis.related_keyword && <Badge variant="outline">Keyword: {diagnosis.related_keyword}</Badge>}
          {diagnosis.needs_expert_support && <Badge variant="secondary">Expert support recommended</Badge>}
        </div>
      </CardHeader>
      <CardContent className="space-y-3 border-t border-border pt-4 text-sm">
        <div>
          <p className="font-medium text-foreground">What this likely means</p>
          <p className="text-muted-foreground">{diagnosis.business_explanation}</p>
        </div>
        <div>
          <p className="font-medium text-foreground">Technical detail</p>
          <p className="text-muted-foreground">{diagnosis.technical_explanation}</p>
        </div>
        <div>
          <p className="font-medium text-foreground">Recommended fix</p>
          <p className="text-muted-foreground">{diagnosis.recommended_fix}</p>
        </div>
        {diagnosis.needs_expert_support && (
          <Button asChild size="sm" variant="outline">
            <Link
              to={buildSupportRequestLink({
                title: `Help with: ${pageTitle ?? diagnosis.page_url}`,
                module: "decline_diagnosis",
                url: diagnosis.page_url,
                type: "technical_seo_fix",
              })}
            >
              Request expert support
            </Link>
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
