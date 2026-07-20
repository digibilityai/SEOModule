import { HELP_ROUTES } from "@/help/routes";
import { PlaceholderPage } from "./PlaceholderPage";

export function SeoSettingsPage() {
  return (
    <PlaceholderPage
      title="Settings"
      description="SEO module settings."
      helpRoute={HELP_ROUTES.FEATURE_AVAILABILITY}
      helpLabel="What 'not built yet' means"
    />
  );
}
