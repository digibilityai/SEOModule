import { useState } from "react";
import type { SeoIssue } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { issueRequiresApproval } from "@/lib/safetyRules";

const STATUS_LABEL: Record<SeoIssue["status"], string> = {
  open: "Open",
  in_review: "In review",
  approved: "Approved",
  fixed: "Fixed",
  ignored: "Ignored",
};

const FIX_OWNER_LABEL: Record<SeoIssue["fix_owner"], string> = {
  client_action: "Client action",
  developer_needed: "Developer needed",
  digibility_expert: "Digibility expert",
  system_suggestion: "System suggestion",
};

const SEVERITY_VARIANT: Record<SeoIssue["severity"], "destructive" | "default" | "secondary" | "outline"> = {
  critical: "destructive",
  high: "default",
  medium: "secondary",
  low: "outline",
};

interface IssueCardProps {
  issue: SeoIssue;
}

export function IssueCard({ issue }: IssueCardProps) {
  const [expanded, setExpanded] = useState(false);
  const needsApproval = issueRequiresApproval(issue);
  const needsHumanHelp = issue.fix_owner === "developer_needed" || issue.fix_owner === "digibility_expert";

  return (
    <Card>
      <CardHeader
        className="cursor-pointer select-none space-y-2"
        onClick={() => setExpanded((e) => !e)}
      >
        <div className="flex flex-wrap items-start justify-between gap-2">
          <h3 className="font-medium text-foreground">{issue.title}</h3>
          <Badge variant={SEVERITY_VARIANT[issue.severity]}>{issue.severity}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">{issue.simple_explanation}</p>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">Category: {issue.category.replace("_", " ")}</Badge>
          <Badge variant="outline">Impact: {issue.impact}</Badge>
          <Badge variant="outline">Effort: {issue.effort}</Badge>
          <Badge variant="outline">Risk: {issue.risk}</Badge>
          <Badge variant="outline">Confidence: {issue.confidence_percentage}%</Badge>
          <Badge variant="outline">Status: {STATUS_LABEL[issue.status]}</Badge>
          <Badge variant="outline">Owner: {FIX_OWNER_LABEL[issue.fix_owner]}</Badge>
        </div>
      </CardHeader>
      {expanded && (
        <CardContent className="space-y-3 border-t border-border pt-4 text-sm">
          <div>
            <p className="font-medium text-foreground">What this means</p>
            <p className="text-muted-foreground">{issue.simple_explanation}</p>
          </div>
          <div>
            <p className="font-medium text-foreground">Why it matters</p>
            <p className="text-muted-foreground">{issue.why_it_matters}</p>
          </div>
          <div>
            <p className="font-medium text-foreground">Technical detail</p>
            <p className="text-muted-foreground">{issue.technical_explanation}</p>
          </div>
          <div>
            <p className="font-medium text-foreground">Affected page</p>
            <p className="break-all text-muted-foreground">{issue.affected_page_url}</p>
          </div>
          <div>
            <p className="font-medium text-foreground">Suggested fix</p>
            <p className="text-muted-foreground">{issue.suggested_next_action}</p>
          </div>
          {needsApproval && (
            <p className="rounded-md bg-warning/10 px-3 py-2 text-warning-foreground">
              This change needs your approval before it's applied.
            </p>
          )}
          {needsHumanHelp && (
            <p className="text-muted-foreground">
              Recommended: {issue.fix_owner === "digibility_expert" ? "Digibility expert support" : "developer help"} for this fix.
            </p>
          )}
          <Button variant="outline" size="sm" onClick={() => setExpanded(false)}>
            Collapse
          </Button>
        </CardContent>
      )}
    </Card>
  );
}
