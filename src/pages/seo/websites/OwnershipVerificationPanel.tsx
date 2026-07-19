// P1a Step 5 — customer-facing Domain Ownership Verification UI for one website,
// rendered inside the Websites/onboarding surface (WebsiteCard). Uses ONLY the
// Step 4 hooks (initiate/recheck/reverify/revoke + status). RLS + the Step 2A
// RPCs remain authoritative; the frontend gates are accessible affordances only.
// Completely separate from the locked crawl UI. No polling, no browser DNS, no
// service-role, no claims/internal fields.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useQuery, type UseMutationResult } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useAuth } from "@/contexts/AuthContext";
import { useSeoAccess } from "@/hooks/useSeoAccess";
import { isSupabaseMode } from "@/config/runtimeConfig";
import { getCurrentSeoRole } from "@/services/supabase/seoWorkspaceService";
import {
  useOwnershipVerificationStatus,
  useInitiateOwnershipVerification,
  useRecheckOwnershipVerification,
  useReverifyOwnershipVerification,
  useRevokeOwnershipVerification,
} from "@/hooks/useOwnershipVerification";
import type { SeoUserRole } from "@/types/role";
import type {
  OwnershipVerificationStatus,
  OwnershipVerificationView,
} from "@/types/ownershipVerification";

const MANAGE_ROLES: readonly SeoUserRole[] = ["owner", "admin"];
const ROLE_TOOLTIP = "Requires the owner or admin role.";

const STATUS_META: Record<
  OwnershipVerificationStatus,
  { label: string; variant: "default" | "secondary" | "destructive" | "outline" }
> = {
  unverified: { label: "Not verified", variant: "outline" },
  pending: { label: "Verification pending", variant: "secondary" },
  verified: { label: "Verified", variant: "default" },
  failed: { label: "Verification failed", variant: "destructive" },
  revoked: { label: "Verification revoked", variant: "outline" },
};

// Accessible disabled-control tooltip (hover + keyboard focus). Local to this
// panel so Step 5 is self-contained and never edits the locked Stage 6
// RoleGateTooltip — same accessible pattern.
function RoleTooltip({ show, tooltip, children }: { show: boolean; tooltip: string; children: ReactNode }) {
  if (!show) return <>{children}</>;
  return (
    <span
      tabIndex={0}
      className="group relative inline-block rounded-md focus:outline-none focus-visible:ring-1 focus-visible:ring-ring"
    >
      {children}
      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 text-xs text-popover-foreground shadow-md group-hover:block group-focus:block"
      >
        {tooltip}
      </span>
    </span>
  );
}

function CopyButton({ value, label }: { value: string; label: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  const onCopy = async () => {
    try {
      await navigator.clipboard?.writeText(value);
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard unavailable — value is still visible for manual copy */
    }
  };
  return (
    <Button type="button" size="sm" variant="outline" onClick={onCopy} aria-label={label}>
      <span aria-live="polite">{copied ? "Copied" : "Copy"}</span>
    </Button>
  );
}

/** Owner/admin gate. gatingActive only in Supabase mode (mock has no real role). */
function useOwnershipManagePermission(): { canManage: boolean; gatingActive: boolean } {
  const { user } = useAuth();
  const { workspaceId } = useSeoAccess();
  const gatingActive = isSupabaseMode();
  const roleQuery = useQuery<SeoUserRole | null>({
    queryKey: ["seo-ownership-verification-role", workspaceId, user?.id ?? null],
    queryFn: () => getCurrentSeoRole(workspaceId!),
    enabled: gatingActive && !!workspaceId && !!user?.id,
    retry: false,
  });
  const role = roleQuery.data ?? null;
  const canManage = !gatingActive || (role !== null && (MANAGE_ROLES as readonly string[]).includes(role));
  return { canManage, gatingActive };
}

function DnsInstructions({ view }: { view: OwnershipVerificationView }) {
  if (!view.dnsTxtName || !view.dnsTxtValue) return null;
  return (
    <div className="space-y-2 rounded-md border border-border bg-muted/40 p-3">
      <p className="text-xs font-medium text-muted-foreground">Add this DNS record at your domain host</p>
      <dl className="space-y-2 text-sm">
        <div className="flex items-center gap-2">
          <dt className="w-16 shrink-0 text-muted-foreground">Type</dt>
          <dd className="font-mono">TXT</dd>
        </div>
        <div className="flex items-center gap-2">
          <dt className="w-16 shrink-0 text-muted-foreground">Host</dt>
          <dd className="min-w-0 flex-1 break-all font-mono">{view.dnsTxtName}</dd>
          <CopyButton value={view.dnsTxtName} label="Copy DNS TXT host/name" />
        </div>
        <div className="flex items-center gap-2">
          <dt className="w-16 shrink-0 text-muted-foreground">Value</dt>
          <dd className="min-w-0 flex-1 break-all font-mono">{view.dnsTxtValue}</dd>
          <CopyButton value={view.dnsTxtValue} label="Copy DNS TXT challenge value" />
        </div>
      </dl>
      <p className="text-xs text-muted-foreground">
        DNS changes can take some time to propagate. After adding the record, choose “Check again”.
      </p>
    </div>
  );
}

interface OwnershipVerificationPanelProps {
  websiteId: string;
  websiteUrl: string;
}

// Fixed post-settle cooldown. Spans a typical mutation + invalidation refetch
// (<1s) and absorbs an impatient rapid-click burst, while remaining negligible
// against DNS-TXT propagation timelines (minutes/hours) so it never obstructs a
// deliberate later recheck.
const COOLDOWN_MS = 3000;
type ActionPhase = "idle" | "in_flight" | "cooldown";

export function OwnershipVerificationPanel({ websiteId }: OwnershipVerificationPanelProps) {
  const isMock = !isSupabaseMode();
  const { canManage } = useOwnershipManagePermission();
  const statusQuery = useOwnershipVerificationStatus(websiteId);

  const initiate = useInitiateOwnershipVerification(websiteId);
  const recheck = useRecheckOwnershipVerification(websiteId);
  const reverify = useReverifyOwnershipVerification(websiteId);
  const revoke = useRevokeOwnershipVerification(websiteId);
  const [confirmingRevoke, setConfirmingRevoke] = useState(false);

  const anyPending =
    initiate.isPending || recheck.isPending || reverify.isPending || revoke.isPending;
  const writeError =
    initiate.error || recheck.error || reverify.error || revoke.error || null;

  const view = statusQuery.data;
  const status = view?.status ?? "unverified";
  const meta = STATUS_META[status];

  // Owner/admin action button with the accessible role gate applied for others.
  const gated = (node: ReactNode) => (
    <RoleTooltip show={!canManage} tooltip={ROLE_TOOLTIP}>
      {node}
    </RoleTooltip>
  );

  // Double-submit protection = a per-action explicit lifecycle:
  //   idle → in_flight → cooldown → idle
  // `phaseRef` is the SYNCHRONOUS authoritative guard (blocks same-frame double
  // clicks before `disabled` re-renders); `lockedActions` is a mirrored React
  // state that drives the VISIBLE disabled state. The first click of an idle
  // action fires immediately; the action then stays disabled through the mutation
  // lifecycle, the invalidation-driven status refetch, and a fixed COOLDOWN_MS
  // window after the mutation settles. Clicks while in_flight/cooldown never call
  // mutate and never reset the timer (no keep-alive). After the window the action
  // returns to idle and a later click is intentionally a NEW request. Per-action,
  // so an unrelated action is not blocked by this lock; the pre-existing global
  // in-flight safety (`anyPending`) is preserved independently.
  const phaseRef = useRef<Record<string, ActionPhase>>({});
  const cooldownTimerRef = useRef<Record<string, ReturnType<typeof setTimeout> | null>>({});
  const [lockedActions, setLockedActions] = useState<Record<string, boolean>>({});

  const setActionLocked = (action: string, locked: boolean) => {
    setLockedActions((prev) => (!!prev[action] === locked ? prev : { ...prev, [action]: locked }));
  };

  // Clear any pending cooldown timers on unmount.
  useEffect(() => {
    const timers = cooldownTimerRef.current;
    return () => {
      for (const key of Object.keys(timers)) {
        const t = timers[key];
        if (t) clearTimeout(t);
      }
    };
  }, []);

  const submitOnce = (
    action: string,
    mutation: UseMutationResult<OwnershipVerificationView, Error, void>,
  ) => {
    // Only an idle action may fire. in_flight / cooldown clicks are ignored and
    // do NOT touch the timer (no keep-alive, no reschedule).
    if ((phaseRef.current[action] ?? "idle") !== "idle") return;

    // Synchronous authoritative transition idle → in_flight, before `disabled`
    // re-renders, so a same-frame double click cannot produce a second mutate.
    phaseRef.current[action] = "in_flight";
    setActionLocked(action, true);

    mutation.mutate(undefined, {
      onSettled: () => {
        // in_flight → cooldown (never straight to idle). One fixed timer; the
        // action re-enables only after the full window, with no reschedule.
        phaseRef.current[action] = "cooldown";
        const existing = cooldownTimerRef.current[action];
        if (existing) clearTimeout(existing);
        cooldownTimerRef.current[action] = setTimeout(() => {
          phaseRef.current[action] = "idle";
          cooldownTimerRef.current[action] = null;
          setActionLocked(action, false);
        }, COOLDOWN_MS);
      },
    });
  };

  // Per-action disabled = the global in-flight safety (`anyPending`) OR this
  // action's own in_flight + cooldown lock.
  const actionDisabled = (action: string) => anyPending || !!lockedActions[action];

  return (
    <section aria-label="Domain ownership verification" className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <p className="text-sm font-medium">Domain ownership</p>
        <Badge variant={meta.variant}>{meta.label}</Badge>
        {isMock && <Badge variant="secondary">Preview</Badge>}
      </div>

      {statusQuery.isLoading && (
        <p className="text-sm text-muted-foreground">Loading ownership status…</p>
      )}

      {statusQuery.isError && !statusQuery.isLoading && (
        <p role="alert" className="text-sm text-destructive">
          Could not load ownership status. Please try again.
        </p>
      )}

      {!statusQuery.isLoading && view && (
        <div className="space-y-3">
          {isMock && (
            <p className="text-xs text-muted-foreground">
              Preview mode — ownership verification is simulated here; no real domain is verified.
            </p>
          )}

          {/* ----- state-specific content ----- */}
          {status === "unverified" && (
            <p className="text-sm text-muted-foreground">
              This website’s domain ownership hasn’t been verified yet. Verify ownership to confirm
              you control this domain.
            </p>
          )}

          {status === "pending" && <DnsInstructions view={view} />}

          {status === "verified" && (
            <p className="text-sm text-muted-foreground">
              Ownership verified{view.verifiedHost ? ` for ${view.verifiedHost}` : ""}
              {view.verifiedAt ? ` on ${new Date(view.verifiedAt).toLocaleString()}` : ""}.
            </p>
          )}

          {status === "failed" && (
            <div className="space-y-2">
              <p role="alert" className="text-sm text-destructive">
                {view.failureReason ?? "Verification failed. Check the DNS TXT record and try again."}
              </p>
              <DnsInstructions view={view} />
            </div>
          )}

          {status === "revoked" && (
            <p className="text-sm text-muted-foreground">
              Ownership verification was revoked for this website. Start a fresh verification to
              re-confirm ownership.
            </p>
          )}

          {/* ----- actions (owner/admin only; others read-only) ----- */}
          {!canManage ? (
            <p className="text-xs text-muted-foreground">
              You can view ownership status. {ROLE_TOOLTIP}
            </p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {(status === "unverified" || status === "revoked") &&
                gated(
                  <Button
                    size="sm"
                    disabled={actionDisabled("initiate")}
                    onClick={() => submitOnce("initiate", initiate)}
                  >
                    {initiate.isPending ? "Starting…" : "Verify ownership"}
                  </Button>,
                )}

              {(status === "pending" || status === "failed") &&
                gated(
                  <Button
                    size="sm"
                    disabled={actionDisabled("recheck")}
                    onClick={() => submitOnce("recheck", recheck)}
                  >
                    {recheck.isPending ? "Checking…" : "Check again"}
                  </Button>,
                )}

              {(status === "pending" || status === "failed" || status === "verified") &&
                gated(
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={actionDisabled("reverify")}
                    onClick={() => submitOnce("reverify", reverify)}
                  >
                    {reverify.isPending ? "Rotating…" : "Re-verify (new record)"}
                  </Button>,
                )}

              {status !== "unverified" && status !== "revoked" && !confirmingRevoke &&
                gated(
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={actionDisabled("revoke")}
                    onClick={() => setConfirmingRevoke(true)}
                  >
                    Revoke
                  </Button>,
                )}
            </div>
          )}

          {/* explicit, keyboard-operable revoke confirmation (destructive) */}
          {canManage && confirmingRevoke && (
            <div
              role="group"
              aria-label="Confirm revoke ownership verification"
              className="space-y-2 rounded-md border border-border p-3"
            >
              <p className="text-sm font-medium">Revoke ownership verification for this website?</p>
              <p className="text-xs text-muted-foreground">
                You can start a fresh verification afterwards.
              </p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="destructive"
                  disabled={actionDisabled("revoke")}
                  onClick={() => {
                    setConfirmingRevoke(false);
                    submitOnce("revoke", revoke);
                  }}
                >
                  {revoke.isPending ? "Revoking…" : "Confirm revoke"}
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={revoke.isPending}
                  onClick={() => setConfirmingRevoke(false)}
                >
                  Cancel
                </Button>
              </div>
            </div>
          )}

          {/* genuine RPC authorization/validation/lifecycle errors (never masked) */}
          {writeError && (
            <p role="alert" className="text-sm text-destructive">
              {writeError.message}
            </p>
          )}
        </div>
      )}
    </section>
  );
}
