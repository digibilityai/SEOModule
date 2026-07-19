import { OFFPAGE_FILTERS } from "./offPageLabels";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface OffPageFiltersBarProps {
  active: string;
  onChange: (filter: string) => void;
}

export function OffPageFiltersBar({ active, onChange }: OffPageFiltersBarProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {OFFPAGE_FILTERS.map((f) => (
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
