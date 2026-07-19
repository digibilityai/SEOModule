// P1a Step 4 — hooks for the (future Step 5) ownership-verification UI. Query
// keys are user + website scoped (SessionSync clears cache on user change /
// sign-out). No background polling, no DNS retry loop, no worker-status polling.
// Mutations invalidate ONLY the matching ownership-verification query — never a
// crawl query key.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/contexts/AuthContext";
import {
  fetchOwnershipVerification,
  initiateOwnershipVerification,
  recheckOwnershipVerification,
  reverifyOwnershipVerification,
  revokeOwnershipVerification,
} from "@/services/ownershipVerificationService";
import { ownershipVerificationQueryKey } from "@/lib/ownershipVerification";
import type { OwnershipVerificationView } from "@/types/ownershipVerification";

export { ownershipVerificationQueryKey } from "@/lib/ownershipVerification";

/** Read-only status query for a website. No polling (status changes on action). */
export function useOwnershipVerificationStatus(websiteId: string | null | undefined) {
  const { user } = useAuth();
  return useQuery<OwnershipVerificationView>({
    queryKey: ownershipVerificationQueryKey(websiteId, user?.id ?? null),
    queryFn: () => fetchOwnershipVerification(websiteId!),
    enabled: !!websiteId,
  });
}

function useOwnershipMutation(
  websiteId: string | null | undefined,
  action: (id: string) => Promise<OwnershipVerificationView>,
) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const key = ownershipVerificationQueryKey(websiteId, user?.id ?? null);
  return useMutation<OwnershipVerificationView, Error>({
    mutationFn: () => {
      if (!websiteId) throw new Error("websiteId is required for an ownership-verification action.");
      return action(websiteId);
    },
    onSuccess: (view) => {
      // Update + invalidate ONLY this website's ownership-verification query.
      queryClient.setQueryData(key, view);
      void queryClient.invalidateQueries({ queryKey: key });
    },
  });
}

export function useInitiateOwnershipVerification(websiteId: string | null | undefined) {
  return useOwnershipMutation(websiteId, initiateOwnershipVerification);
}

export function useRecheckOwnershipVerification(websiteId: string | null | undefined) {
  return useOwnershipMutation(websiteId, recheckOwnershipVerification);
}

export function useReverifyOwnershipVerification(websiteId: string | null | undefined) {
  return useOwnershipMutation(websiteId, reverifyOwnershipVerification);
}

export function useRevokeOwnershipVerification(websiteId: string | null | undefined) {
  return useOwnershipMutation(websiteId, revokeOwnershipVerification);
}
