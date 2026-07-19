import { APPROVAL_FILTERS, type ApprovalFilterKey } from "@/lib/approvalPermissions";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface ApprovalFiltersBarProps {
  active: ApprovalFilterKey;
  onChange: (filter: ApprovalFilterKey) => void;
}

export function ApprovalFiltersBar({ active, onChange }: ApprovalFiltersBarProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {APPROVAL_FILTERS.map((f) => (
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
