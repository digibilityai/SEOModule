import { Badge } from "@/components/ui/badge";
import { FEATURE_STATUS_LABEL, type FeatureStatus } from "@/help/types";

const VARIANT: Record<FeatureStatus, "default" | "secondary" | "outline" | "destructive"> = {
  available: "default",
  available_on_test: "secondary",
  preview: "outline",
  demo_data: "outline",
  mock_only: "outline",
  coming_later: "outline",
  internal_only: "destructive",
};

export function FeatureStatusBadge({ status }: { status: FeatureStatus }) {
  return <Badge variant={VARIANT[status]}>{FEATURE_STATUS_LABEL[status]}</Badge>;
}
