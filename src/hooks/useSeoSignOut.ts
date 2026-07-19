// Phase 16B — customer sign-out. Uses Supabase's own sign-out, then clears
// user-scoped frontend state and returns to the login route. Handles the known
// benign case where the global-revocation network call aborts while the local
// session is still cleared (not a real failure); only reports failure when the
// local session actually persists. Never inspects/prints session storage.
import { useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";
import { SEO_LOGIN_PATH } from "@/routes/routeAccess";

export function useSeoSignOut() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { setActiveWebsiteId } = useActiveWebsite();

  return useCallback(async (): Promise<boolean> => {
    try {
      await supabase.auth.signOut();
    } catch {
      // The global-scope logout request can abort; the local session removal
      // still happens. Fall through and verify below.
    }

    // Genuine-failure check: only fail if the local session is still present.
    let localCleared = true;
    try {
      const { data } = await supabase.auth.getSession();
      localCleared = !data.session;
    } catch {
      localCleared = true;
    }

    // Clear user-scoped frontend state regardless, so nothing leaks to a next
    // user, then return to the customer login route.
    setActiveWebsiteId(null);
    queryClient.clear();
    navigate(SEO_LOGIN_PATH, { replace: true });

    return localCleared;
  }, [navigate, queryClient, setActiveWebsiteId]);
}
