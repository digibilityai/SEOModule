import type { BrandMentionSummary } from "@/types";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

interface BrandMentionCardProps {
  summary: BrandMentionSummary;
}

export function BrandMentionCard({ summary }: BrandMentionCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Where your brand appears</CardTitle>
        <CardDescription>
          Mentioned in {summary.brand_mention_count} of {summary.total_prompts_tracked} tracked prompts (
          {summary.mention_rate_percentage.toFixed(0)}%).
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-1.5 text-sm text-muted-foreground">
        {summary.where_brand_appears.length === 0 ? (
          <p>No tracked prompts mention your brand yet.</p>
        ) : (
          summary.where_brand_appears.map((item) => <p key={item}>{item}</p>)
        )}
      </CardContent>
    </Card>
  );
}
