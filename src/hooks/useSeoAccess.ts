// Phase 16B — the single centralized auth/access resolver used by the route
// guard. Composes the existing primitives (session from AuthContext, the
// has_seo_module_access RPC, and getCurrentSeoWorkspace) into one derived
// status. Deliberately does NOT resolve or gate on seo_role — role/action
// gating stays in the pages/components + RLS/RPC (locked Stage 6 behaviour is
// not duplicated here). Exposes only non-secret state; never tokens/sessions.
import { useCallback } from "react";
import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/contexts/AuthContext";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { checkSeoModuleAccess } from "@/services/supabase/seoAccessService";
import { getCurrentSeoWorkspace } from "@/services/supabase/seoWorkspaceService";

export type SeoAccessStatus =
  | "loading"
  | "no-session"
  | "no-module-access"
  | "no-workspace"
  | "error"
  | "ready";

export interface SeoAccessState {
  status: SeoAccessStatus;
  userId: string | null;
  /** Safe to display; never a token. */
  email: string | null;
  hasModuleAccess: boolean | null;
  workspaceId: string | null;
  refetch: () => void;
}

const MODULE_ACCESS_STALE_MS = 5 * 60 * 1000;

export function useSeoAccess(): SeoAccessState {
  const { user, isAuthenticated, isLoading: sessionLoading } = useAuth();
  const userId = user?.id ?? null;
  const supabaseMode = isSupabaseMode();

  const moduleAccessQuery = useQuery({
    queryKey: ["seo-module-access", userId],
    queryFn: checkSeoModuleAccess,
    enabled: supabaseMode && isAuthenticated && !!userId,
    staleTime: MODULE_ACCESS_STALE_MS,
    retry: false,
  });

  const workspaceQuery = useQuery({
    queryKey: ["seo-current-workspace", userId],
    queryFn: getCurrentSeoWorkspace,
    enabled: supabaseMode && isAuthenticated && moduleAccessQuery.data === true,
    retry: false,
  });

  const refetch = useCallback(() => {
    void moduleAccessQuery.refetch();
    void workspaceQuery.refetch();
  }, [moduleAccessQuery, workspaceQuery]);

  const base: Omit<SeoAccessState, "status"> = {
    userId,
    email: user?.email ?? null,
    hasModuleAccess: moduleAccessQuery.data ?? null,
    workspaceId: workspaceQuery.data?.workspace?.id ?? null,
    refetch,
  };

  let status: SeoAccessStatus;
  if (sessionLoading) {
    status = "loading";
  } else if (!isAuthenticated) {
    status = "no-session";
  } else if (moduleAccessQuery.isError || workspaceQuery.isError) {
    status = "error";
  } else if (moduleAccessQuery.isLoading || moduleAccessQuery.data === undefined) {
    status = "loading";
  } else if (moduleAccessQuery.data === false) {
    status = "no-module-access";
  } else if (workspaceQuery.isLoading || workspaceQuery.data === undefined) {
    status = "loading";
  } else if (!workspaceQuery.data.workspace) {
    status = "no-workspace";
  } else {
    status = "ready";
  }

  return { status, ...base };
}
