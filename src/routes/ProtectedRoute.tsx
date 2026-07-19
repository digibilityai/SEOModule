// Phase 16B — route-level protection for /seo/* in Supabase mode.
// This is navigation/UX security ONLY; RLS + guarded RPCs remain the
// authoritative authorization layer, and per-role ACTION gating stays in the
// pages/components (locked Stage 6 logic is never duplicated here).
//
// Mock mode fully bypasses protection (permanent mock support): the module
// stays usable for development/demo without any Supabase session.
import type { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { isMockMode } from "@/config/runtimeConfig";
import { useSeoAccess } from "@/hooks/useSeoAccess";
import { useSeoSignOut } from "@/hooks/useSeoSignOut";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { checkSeoGlobalAdmin } from "@/services/supabase/seoAccessService";
import {
  buildLoginRedirect,
  SEO_SETUP_WEBSITE_ROUTE,
  SEO_SETUP_WORKSPACE_ROUTE,
} from "@/routes/routeAccess";
import {
  AccessRequiredState,
  ResolutionErrorState,
  RouteLoadingState,
} from "@/components/auth/RouteStates";

interface ProtectedRouteProps {
  children: ReactNode;
  /** Route needs a resolved active website (website-scoped data). */
  requireWebsite?: boolean;
  /** Route needs global-admin capability (seo_is_global_admin). */
  requireGlobalAdmin?: boolean;
  /** Setup routes (onboarding/websites): render even without a workspace/website. */
  allowSetup?: boolean;
}

export function ProtectedRoute(props: ProtectedRouteProps) {
  // Mock mode: no hooks, unconditional bypass (stable per session).
  if (isMockMode()) return <>{props.children}</>;
  return <SupabaseProtectedRoute {...props} />;
}

function SupabaseProtectedRoute({
  children,
  requireWebsite = false,
  requireGlobalAdmin = false,
  allowSetup = false,
}: ProtectedRouteProps) {
  const location = useLocation();
  const access = useSeoAccess();
  const signOut = useSeoSignOut();

  // Always call this hook (rules of hooks); it only fetches when required + ready.
  const adminQuery = useQuery({
    queryKey: ["seo-global-admin", access.userId],
    queryFn: checkSeoGlobalAdmin,
    enabled: requireGlobalAdmin && access.status === "ready",
    retry: false,
  });

  const handleSignOut = () => void signOut();

  switch (access.status) {
    case "loading":
      return <RouteLoadingState />;
    case "no-session":
      return (
        <Navigate
          to={buildLoginRedirect(location.pathname + location.search + location.hash)}
          replace
        />
      );
    case "error":
      return <ResolutionErrorState onRetry={access.refetch} onSignOut={handleSignOut} />;
    case "no-module-access":
      return <AccessRequiredState variant="module" onRetry={access.refetch} onSignOut={handleSignOut} />;
    case "no-workspace":
      // Setup routes render so the user can establish a workspace; everything
      // else is routed to onboarding (no redirect loop — onboarding is setup).
      return allowSetup ? <>{children}</> : <Navigate to={SEO_SETUP_WORKSPACE_ROUTE} replace />;
    case "ready":
      break;
  }

  if (requireGlobalAdmin) {
    if (adminQuery.isLoading) return <RouteLoadingState />;
    if (adminQuery.isError) {
      return <ResolutionErrorState onRetry={() => void adminQuery.refetch()} onSignOut={handleSignOut} />;
    }
    if (!adminQuery.data) return <AccessRequiredState variant="admin" onSignOut={handleSignOut} />;
  }

  if (requireWebsite && !allowSetup) {
    return <RequireActiveWebsite>{children}</RequireActiveWebsite>;
  }

  return <>{children}</>;
}

/** Website-scoped gate. `useResolvedActiveWebsite` auto-selects the first
 *  accessible website; "no active website" therefore means the user has zero
 *  websites → route them to the website setup page (a valid setup route). */
function RequireActiveWebsite({ children }: { children: ReactNode }) {
  const { activeWebsite, isLoading } = useResolvedActiveWebsite();
  if (isLoading) return <RouteLoadingState />;
  if (!activeWebsite) return <Navigate to={SEO_SETUP_WEBSITE_ROUTE} replace />;
  return <>{children}</>;
}
