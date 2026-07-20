// Customer sign-out with Digibility linked logout.
// Clears SEO session + user-scoped UI state, then cascades to Digibility
// /logout so both GoTrue sessions are removed and SEO is not auto-relaunched.
import { useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";
import { getDigibilityAppUrl, hasDigibilityBridgeConfig } from "@/config/runtimeConfig";
import {
  SEO_LOGIN_PATH,
  SEO_LOGOUT_PATH,
  buildDigibilityLogoutCascadeUrl,
} from "@/routes/routeAccess";

export function useSeoSignOut() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { setActiveWebsiteId } = useActiveWebsite();

  return useCallback(async (): Promise<boolean> => {
    // Prefer the dedicated logout route so Digibility cascade is consistent
    // whether Sign out is clicked or Digibility redirects here.
    if (hasDigibilityBridgeConfig() || getDigibilityAppUrl()) {
      window.location.assign(SEO_LOGOUT_PATH);
      return true;
    }

    try {
      await supabase.auth.signOut();
    } catch {
      // Local session removal may still succeed.
    }

    let localCleared = true;
    try {
      const { data } = await supabase.auth.getSession();
      localCleared = !data.session;
    } catch {
      localCleared = true;
    }

    setActiveWebsiteId(null);
    queryClient.clear();

    const digibilityLogout = buildDigibilityLogoutCascadeUrl();
    if (digibilityLogout.startsWith("http")) {
      window.location.assign(digibilityLogout);
      return localCleared;
    }

    navigate(SEO_LOGIN_PATH, { replace: true });
    return localCleared;
  }, [navigate, queryClient, setActiveWebsiteId]);
}
