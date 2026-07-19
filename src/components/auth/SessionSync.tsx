// Phase 16B — prevents one user's data/selection from leaking to the next.
// When the authenticated user id changes to a DIFFERENT real user (or clears
// on sign-out), it drops all cached TanStack Query data and the active-website
// selection. First-load / same-user refresh does not clear (so legitimate
// selections persist). Renders nothing.
import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/contexts/AuthContext";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";

export function SessionSync(): null {
  const { user } = useAuth();
  const { setActiveWebsiteId } = useActiveWebsite();
  const queryClient = useQueryClient();
  const previousUserId = useRef<string | null | undefined>(undefined);

  useEffect(() => {
    const currentUserId = user?.id ?? null;
    const previous = previousUserId.current;
    previousUserId.current = currentUserId;

    // Clear only when we had a real previous user and it is now a different
    // user (A → B) or has signed out (A → null). Undefined/null previous =
    // first load or fresh login after a cleared sign-out — nothing to leak.
    if (previous && previous !== currentUserId) {
      queryClient.clear();
      setActiveWebsiteId(null);
    }
  }, [user?.id, queryClient, setActiveWebsiteId]);

  return null;
}
