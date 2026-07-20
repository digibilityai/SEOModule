import { HELP_ROUTES } from "@/help/routes";
import { PlaceholderPage } from "./PlaceholderPage";

export function ContentGapsPage() {
  return (
    <PlaceholderPage
      title="Content Gaps"
      description="A dedicated content gap tool hasn't been built yet. Competitor content gaps show up today inside Content Studio's competitor summary."
      helpRoute={HELP_ROUTES.FEATURE_AVAILABILITY}
      helpLabel="What 'not built yet' means"
    />
  );
}
