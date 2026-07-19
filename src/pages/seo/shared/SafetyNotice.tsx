import { ShieldCheck } from "lucide-react";
import { SAFETY_NOTICE } from "@/lib/safetyRules";

interface SafetyNoticeProps {
  text?: string;
}

export function SafetyNotice({ text = SAFETY_NOTICE }: SafetyNoticeProps) {
  return (
    <div className="flex items-start gap-2 rounded-md border border-border bg-muted/40 p-3 text-sm text-muted-foreground">
      <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0" />
      <p>{text}</p>
    </div>
  );
}
