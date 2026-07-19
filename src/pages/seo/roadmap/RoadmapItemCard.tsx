import { useState } from "react";
import { Link } from "react-router-dom";
import type { RoadmapItem, RoadmapStatus } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { buildSupportRequestLink } from "@/lib/supportLinking";
import {
  FIX_OWNER_LABEL,
  RELATED_MODULE_LABEL,
  RELATED_MODULE_ROUTE,
  ROADMAP_SOURCE_LABEL,
  ROADMAP_STATUS_LABEL,
  ROADMAP_STATUS_VARIANT,
} from "./roadmapLabels";

const PRIORITY_VARIANT: Record<RoadmapItem["priority"], "destructive" | "default" | "secondary"> = {
  high: "destructive",
  medium: "default",
  low: "secondary",
};

const STATUS_OPTIONS: RoadmapStatus[] = ["planned", "in_progress", "blocked", "completed", "skipped"];

interface RoadmapItemCardProps {
  item: RoadmapItem;
  onStatusChange: (id: string, status: RoadmapStatus) => void;
  isMutating: boolean;
}

export function RoadmapItemCard({ item, onStatusChange, isMutating }: RoadmapItemCardProps) {
  const [expanded, setExpanded] = useState(false);
  const route = RELATED_MODULE_ROUTE[item.related_module];

  return (
    <Card>
      <CardHeader className="cursor-pointer select-none space-y-2" onClick={() => setExpanded((e) => !e)}>
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h3 className="font-medium text-foreground">{item.title}</h3>
            <p className="text-xs text-muted-foreground">
              Month {item.month_number} · Week {item.week_number}
            </p>
          </div>
          <Badge variant={ROADMAP_STATUS_VARIANT[item.status]}>{ROADMAP_STATUS_LABEL[item.status]}</Badge>
        </div>

        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant={PRIORITY_VARIANT[item.priority]}>Priority: {item.priority}</Badge>
          <Badge variant="outline">{RELATED_MODULE_LABEL[item.related_module]}</Badge>
          <Badge variant="outline">Source: {ROADMAP_SOURCE_LABEL[item.source]}</Badge>
          <Badge variant="outline">Impact: {item.expected_impact}</Badge>
          <Badge variant="outline">Effort: {item.effort}</Badge>
          <Badge variant="outline">Risk: {item.risk}</Badge>
          <Badge variant="outline">Owner: {FIX_OWNER_LABEL[item.owner]}</Badge>
        </div>
      </CardHeader>

      {expanded && (
        <CardContent className="space-y-3 border-t border-border pt-4 text-sm">
          <p className="text-muted-foreground">{item.explanation}</p>

          <div className="flex flex-wrap items-center gap-2">
            <Select
              className="h-8 w-auto text-xs"
              value={item.status}
              onChange={(e) => onStatusChange(item.id, e.target.value as RoadmapStatus)}
              disabled={isMutating}
            >
              {STATUS_OPTIONS.map((s) => (
                <option key={s} value={s}>
                  {ROADMAP_STATUS_LABEL[s]}
                </option>
              ))}
            </Select>

            {route && (
              <Button asChild size="sm" variant="outline">
                <Link to={route}>Open {RELATED_MODULE_LABEL[item.related_module]}</Link>
              </Button>
            )}

            {item.owner === "digibility_expert" && (
              <Button asChild size="sm" variant="outline">
                <Link
                  to={buildSupportRequestLink({
                    title: item.title,
                    module: item.related_module,
                    type: "strategy_review",
                  })}
                >
                  Request expert support
                </Link>
              </Button>
            )}
          </div>
        </CardContent>
      )}
    </Card>
  );
}
