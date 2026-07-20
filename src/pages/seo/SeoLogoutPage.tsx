import { useEffect, useRef } from "react";
import { useSearchParams } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";
import { getDigibilityAppUrl } from "@/config/runtimeConfig";
import {
  buildDigibilityLogoutCascadeUrl,
  sanitizeLogoutContinueUrl,
} from "@/routes/routeAccess";

/**
 * Public chromeless logout for the SEO app.
 * Clears the SEO GoTrue session, then continues to Digibility login (or a
 * sanitized absolute continue URL on an allowed Digibility origin).
 * Used both for SEO header Sign out and Digibility → SEO logout cascade.
 */
export function SeoLogoutPage() {
  const [searchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const { setActiveWebsiteId } = useActiveWebsite();
  const startedRef = useRef(false);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;

    const run = async () => {
      try {
        await supabase.auth.signOut();
      } catch {
        // Local session may still clear; continue cascade either way.
      }

      setActiveWebsiteId(null);
      queryClient.clear();

      const digibilityOrigin = getDigibilityAppUrl();
      const continueParam = searchParams.get("continue");
      const allowed = digibilityOrigin ? [digibilityOrigin] : [];
      const safeContinue = sanitizeLogoutContinueUrl(continueParam, allowed);

      if (safeContinue) {
        // Digibility already signed out and cascaded here with continue=/login.
        window.location.replace(safeContinue);
        return;
      }

      if (digibilityOrigin) {
        // SEO-initiated sign-out: clear Digibility too (no seoReturnTo).
        window.location.replace(buildDigibilityLogoutCascadeUrl(digibilityOrigin));
        return;
      }

      window.location.replace("/seo/login");
    };

    void run();
  }, [queryClient, searchParams, setActiveWebsiteId]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <p className="text-sm text-muted-foreground">Signing out of SEO…</p>
    </div>
  );
}
