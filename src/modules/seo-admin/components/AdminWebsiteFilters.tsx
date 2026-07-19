import type { SeoAdminWebsiteFilterKey } from "@/types";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { WEBSITE_FILTERS } from "../adminLabels";

interface AdminWebsiteFiltersProps {
  active: SeoAdminWebsiteFilterKey;
  onChange: (filter: SeoAdminWebsiteFilterKey) => void;
}

export function AdminWebsiteFilters({ active, onChange }: AdminWebsiteFiltersProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {WEBSITE_FILTERS.map((f) => (
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
