import type { ImpactLevel } from "@/types";
import type { PromptVisibilityStatus } from "@/types";

export const VISIBILITY_STATUS_LABEL: Record<PromptVisibilityStatus, string> = {
  visible: "Visible",
  partially_visible: "Partially visible",
  not_visible: "Not visible",
  unknown: "Unknown",
};

export const VISIBILITY_STATUS_VARIANT: Record<
  PromptVisibilityStatus,
  "default" | "secondary" | "destructive" | "outline"
> = {
  visible: "default",
  partially_visible: "secondary",
  not_visible: "destructive",
  unknown: "outline",
};

export const PRIORITY_VARIANT: Record<ImpactLevel, "destructive" | "default" | "secondary"> = {
  high: "destructive",
  medium: "default",
  low: "secondary",
};
