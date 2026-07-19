import { Link } from "react-router-dom";
import type { AiContentGap } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { PRIORITY_VARIANT } from "./aiVisibilityLabels";

interface AiContentGapCardProps {
  gap: AiContentGap;
}

export function AiContentGapCard({ gap }: AiContentGapCardProps) {
  return (
    <Card>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <CardTitle className="text-base">{gap.topic}</CardTitle>
          <Badge variant={PRIORITY_VARIANT[gap.priority]}>Priority: {gap.priority}</Badge>
        </div>
        <Badge variant="outline">{gap.suggested_content_type}</Badge>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">
        <div>
          <p className="font-medium text-foreground">Missing answer angle</p>
          <p className="text-muted-foreground">{gap.missing_answer_angle}</p>
        </div>
        <div>
          <p className="font-medium text-foreground">Related keyword/question</p>
          <p className="text-muted-foreground">{gap.related_keyword_or_question}</p>
        </div>
        <div>
          <p className="font-medium text-foreground">Recommended next action</p>
          <p className="text-muted-foreground">{gap.recommended_next_action}</p>
        </div>
        <Button asChild size="sm" variant="outline">
          <Link to="/seo/content-studio">Open Content Studio</Link>
        </Button>
      </CardContent>
    </Card>
  );
}
