import type { ReportPeriodKey } from "@/types";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const PERIOD_OPTIONS: { key: ReportPeriodKey; label: string }[] = [
  { key: "current_month", label: "Current month" },
  { key: "last_month", label: "Last month" },
  { key: "last_90_days", label: "Last 90 days" },
];

interface ReportPeriodSelectorProps {
  active: ReportPeriodKey;
  onChange: (period: ReportPeriodKey) => void;
}

export function ReportPeriodSelector({ active, onChange }: ReportPeriodSelectorProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {PERIOD_OPTIONS.map((p) => (
        <Button
          key={p.key}
          type="button"
          size="sm"
          variant={active === p.key ? "default" : "outline"}
          className={cn("h-7 px-2 text-xs")}
          onClick={() => onChange(p.key)}
        >
          {p.label}
        </Button>
      ))}
    </div>
  );
}
