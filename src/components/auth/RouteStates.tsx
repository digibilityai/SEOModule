// Phase 16B — shared branded states for the route guard, using the existing
// design system (Card / Button / Skeleton). No protected page content leaks
// from any of these states.
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { HELP_ROUTES } from "@/help/routes";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

/** Non-blocking session/access resolving state. Never flashes protected content. */
export function RouteLoadingState() {
  return (
    <div className="mx-auto max-w-2xl space-y-4 py-10" role="status" aria-live="polite">
      <Skeleton className="h-8 w-1/3" />
      <Skeleton className="h-40 w-full" />
      <Skeleton className="h-40 w-full" />
      <span className="sr-only">Loading…</span>
    </div>
  );
}

interface AccessRequiredStateProps {
  variant?: "module" | "admin";
  onRetry?: () => void;
  onSignOut?: () => void;
}

/** Authenticated, but not authorized for this area. Shows sign-out (+ retry). */
export function AccessRequiredState({ variant = "module", onRetry, onSignOut }: AccessRequiredStateProps) {
  const isAdmin = variant === "admin";
  return (
    <div className="mx-auto max-w-lg py-10">
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">
            {isAdmin ? "Admin access required" : "SEO access required"}
          </CardTitle>
          <CardDescription>
            {isAdmin
              ? "You're signed in, but this area requires global-admin access."
              : "You're signed in, but your account doesn't have access to the SEO module yet. Please contact your administrator to request access."}
          </CardDescription>
          {!isAdmin && (
            <Link to={HELP_ROUTES.SIGN_IN_ACCESS} className={HELP_LINK_CLASSNAME}>
              More about access states
            </Link>
          )}
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {onRetry && (
            <Button variant="outline" size="sm" onClick={onRetry}>
              Retry
            </Button>
          )}
          {onSignOut && (
            <Button variant="outline" size="sm" onClick={onSignOut}>
              Sign out
            </Button>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

interface ResolutionErrorStateProps {
  onRetry?: () => void;
  onSignOut?: () => void;
}

/** Recoverable resolution error — offers retry; never silently signs out. */
export function ResolutionErrorState({ onRetry, onSignOut }: ResolutionErrorStateProps) {
  return (
    <div className="mx-auto max-w-lg py-10">
      <Card className="border-destructive/40">
        <CardHeader>
          <CardTitle className="text-lg">We couldn't verify your access</CardTitle>
          <CardDescription>
            A temporary problem stopped us from resolving your account access. This is usually
            transient — please retry.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {onRetry && (
            <Button size="sm" onClick={onRetry}>
              Retry
            </Button>
          )}
          {onSignOut && (
            <Button variant="outline" size="sm" onClick={onSignOut}>
              Sign out
            </Button>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
