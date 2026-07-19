import { Link } from "react-router-dom";
import type { PendingApprovalsSummary } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface PendingApprovalsCardProps {
  summary: PendingApprovalsSummary;
}

export function PendingApprovalsCard({ summary }: PendingApprovalsCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Pending Approvals</CardTitle>
        <CardDescription>Nothing goes live without your say-so.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Waiting on your approval</span>
          <span className="font-medium text-foreground">{summary.pending_count}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Needs expert review</span>
          <span className="font-medium text-foreground">{summary.expert_review_count}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Needs a developer</span>
          <span className="font-medium text-foreground">{summary.developer_needed_count}</span>
        </div>
        <Button asChild variant="outline" size="sm" className="mt-2 w-full">
          <Link to="/seo/approvals">Go to approval queue</Link>
        </Button>
      </CardContent>
    </Card>
  );
}
