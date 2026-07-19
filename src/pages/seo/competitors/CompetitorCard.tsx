import { useState } from "react";
import type { Competitor } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { STRENGTH_STATUS_LABEL, STRENGTH_STATUS_VARIANT } from "./competitorLabels";

interface CompetitorCardProps {
  competitor: Competitor;
}

export function CompetitorCard({ competitor }: CompetitorCardProps) {
  const [expanded, setExpanded] = useState(false);

  return (
    <Card>
      <CardHeader className="cursor-pointer select-none space-y-2" onClick={() => setExpanded((e) => !e)}>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h3 className="font-medium text-foreground">{competitor.competitor_name}</h3>
            <p className="break-all text-xs text-muted-foreground">{competitor.competitor_url}</p>
          </div>
          <Badge variant={STRENGTH_STATUS_VARIANT[competitor.status]}>
            {STRENGTH_STATUS_LABEL[competitor.status]}
          </Badge>
        </div>

        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">{competitor.business_category}</Badge>
          {competitor.target_location && <Badge variant="outline">{competitor.target_location}</Badge>}
          <Badge variant="outline">Overall strength: {competitor.overall_strength_score}/100</Badge>
        </div>

        <div className="flex flex-wrap gap-4 text-xs text-muted-foreground">
          <span>Content: {competitor.content_strength_score}</span>
          <span>Technical: {competitor.technical_health_score}</span>
          <span>Authority: {competitor.authority_score}</span>
          <span>AI visibility: {competitor.ai_visibility_score}</span>
          <span>Reviews: {competitor.review_strength_score}</span>
        </div>
      </CardHeader>

      {expanded && (
        <CardContent className="space-y-3 border-t border-border pt-4 text-sm">
          <div>
            <p className="font-medium text-foreground">What they're doing better</p>
            <ul className="list-inside list-disc text-muted-foreground">
              {competitor.what_they_do_better.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </div>
          {competitor.what_they_are_missing.length > 0 && (
            <div>
              <p className="font-medium text-foreground">What they're missing</p>
              <ul className="list-inside list-disc text-muted-foreground">
                {competitor.what_they_are_missing.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          )}
          {competitor.content_opportunities.length > 0 && (
            <div>
              <p className="font-medium text-foreground">Content opportunities</p>
              <ul className="list-inside list-disc text-muted-foreground">
                {competitor.content_opportunities.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          )}
          {competitor.authority_opportunities.length > 0 && (
            <div>
              <p className="font-medium text-foreground">Authority opportunities</p>
              <ul className="list-inside list-disc text-muted-foreground">
                {competitor.authority_opportunities.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          )}
          {competitor.ai_visibility_opportunities.length > 0 && (
            <div>
              <p className="font-medium text-foreground">AI visibility opportunities</p>
              <ul className="list-inside list-disc text-muted-foreground">
                {competitor.ai_visibility_opportunities.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </div>
          )}
          <div>
            <p className="font-medium text-foreground">Suggested next action</p>
            <p className="text-muted-foreground">{competitor.suggested_next_action}</p>
          </div>
          <Button variant="outline" size="sm" onClick={() => setExpanded(false)}>
            Collapse
          </Button>
        </CardContent>
      )}
    </Card>
  );
}
