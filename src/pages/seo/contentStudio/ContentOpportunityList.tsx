import { useState } from "react";
import type { ContentOpportunity } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const FUNNEL_LABEL: Record<ContentOpportunity["funnel_stage"], string> = {
  awareness: "Awareness",
  consideration: "Consideration",
  conversion: "Conversion",
};

interface ContentOpportunityListProps {
  opportunities: ContentOpportunity[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onStartPlan: (id: string) => void;
  onAddCustomTitle: (title: string, targetKeyword: string) => void;
  isMutating: boolean;
}

export function ContentOpportunityList({
  opportunities,
  selectedId,
  onSelect,
  onStartPlan,
  onAddCustomTitle,
  isMutating,
}: ContentOpportunityListProps) {
  const [customTitle, setCustomTitle] = useState("");
  const [customKeyword, setCustomKeyword] = useState("");

  const handleAddCustom = () => {
    if (!customTitle.trim() || !customKeyword.trim()) return;
    onAddCustomTitle(customTitle.trim(), customKeyword.trim());
    setCustomTitle("");
    setCustomKeyword("");
  };

  return (
    <div className="space-y-3">
      {opportunities.length === 0 && (
        <Card>
          <CardContent className="py-6 text-center text-sm text-muted-foreground">
            No content opportunities yet. Add your own title below to get started.
          </CardContent>
        </Card>
      )}

      {opportunities.map((opp) => (
        <Card
          key={opp.id}
          className={selectedId === opp.id ? "border-primary" : undefined}
          onClick={() => onSelect(opp.id)}
        >
          <CardHeader className="cursor-pointer space-y-2">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <CardTitle className="text-base">{opp.title}</CardTitle>
              <Badge variant="secondary">{opp.opportunity_score}/100</Badge>
            </div>
            <CardDescription>{opp.reason}</CardDescription>
            <div className="flex flex-wrap gap-2 text-xs">
              <Badge variant="outline">Keyword: {opp.target_keyword}</Badge>
              <Badge variant="outline">Intent: {opp.search_intent}</Badge>
              <Badge variant="outline">Stage: {FUNNEL_LABEL[opp.funnel_stage]}</Badge>
              <Badge variant="outline">Difficulty: {opp.difficulty}</Badge>
              <Badge variant="outline">Status: {opp.status.replace(/_/g, " ")}</Badge>
            </div>
          </CardHeader>
          <CardContent>
            <Button
              size="sm"
              disabled={isMutating}
              onClick={(e) => {
                e.stopPropagation();
                onSelect(opp.id);
                if (opp.status === "idea_suggested") onStartPlan(opp.id);
              }}
            >
              {opp.status === "idea_suggested" ? "Start Content Plan" : "Continue"}
            </Button>
          </CardContent>
        </Card>
      ))}

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Add a custom title</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="space-y-1.5">
            <Label htmlFor="custom-title">Title</Label>
            <Input
              id="custom-title"
              value={customTitle}
              onChange={(e) => setCustomTitle(e.target.value)}
              placeholder="e.g. 5 Signs You Need a Plumber Today"
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="custom-keyword">Target keyword</Label>
            <Input
              id="custom-keyword"
              value={customKeyword}
              onChange={(e) => setCustomKeyword(e.target.value)}
              placeholder="e.g. signs you need a plumber"
            />
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={handleAddCustom}
            disabled={isMutating || !customTitle.trim() || !customKeyword.trim()}
          >
            Add title
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
