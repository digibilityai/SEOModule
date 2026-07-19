import type { PagePerformanceFilterKey } from "@/types";
import { PAGE_PERFORMANCE_FILTERS } from "@/lib/pagePerformanceFilters";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

interface PerformanceFiltersBarProps {
  active: PagePerformanceFilterKey;
  onChange: (filter: PagePerformanceFilterKey) => void;
  search: string;
  onSearchChange: (value: string) => void;
}

export function PerformanceFiltersBar({
  active,
  onChange,
  search,
  onSearchChange,
}: PerformanceFiltersBarProps) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div className="flex flex-wrap gap-2">
        {PAGE_PERFORMANCE_FILTERS.map((f) => (
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
      <Input
        placeholder="Search by page URL or keyword..."
        value={search}
        onChange={(e) => onSearchChange(e.target.value)}
        className="h-8 max-w-xs text-xs"
      />
    </div>
  );
}
