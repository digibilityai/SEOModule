import { Link } from "react-router-dom";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

interface PlaceholderPageProps {
  title: string;
  description: string;
  /** Optional contextual-help target — e.g. a HELP_ROUTES constant. Omit to
   *  render exactly as before (no link). */
  helpRoute?: string;
  /** Visible text for the optional help link. Only used when helpRoute is set. */
  helpLabel?: string;
}

export function PlaceholderPage({ title, description, helpRoute, helpLabel }: PlaceholderPageProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
        {helpRoute && (
          <Link to={helpRoute} className={HELP_LINK_CLASSNAME}>
            {helpLabel ?? "Learn more"}
          </Link>
        )}
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground">
          This is a placeholder. Feature work has not started yet.
        </p>
      </CardContent>
    </Card>
  );
}
