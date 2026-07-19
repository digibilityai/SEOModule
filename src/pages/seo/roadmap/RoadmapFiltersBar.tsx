import type { RoadmapFilterKey } from "@/types";
import { ROADMAP_FILTERS } from "@/lib/roadmapFilters";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface RoadmapFiltersBarProps {
  active: RoadmapFilterKey;
  onChange: (filter: RoadmapFilterKey) => void;
}

export function RoadmapFiltersBar({ active, onChange }: RoadmapFiltersBarProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {ROADMAP_FILTERS.map((f) => (
        <Button
          key={f.key}
          type="button"
          size="sm"
          variant={active === f.key ? "default" : "outline"}
          className={cn("h-7 px-2 text-xs")}
          onClick={() => onChange(f.key)}
        >
          {f.label}
        </Button>
      ))}
    </div>
  );
}
