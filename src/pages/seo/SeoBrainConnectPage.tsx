// D-026A: the SEO-owned browser step between "Brain creates an intent" and
// "customer returns to Brain, genuinely connected". Chromeless, like
// SeoBridgePage, and rendered OUTSIDE the protected app shell: a case A/C/D
// customer may have no SEO session yet.
//
// This page only ever receives the opaque `launchCode`. It never receives
// brainActorId, brainBusinessId, normalizedHost, a website id, or the module
// machine secret. Every case A-D decision is read directly off the outcome
// `seo_brain_link_intent_redeem` (and, for case A, `link-intent/provision`;
// for case D without a live matching session, `link-intent/continue`) already
// returned; this component does not re-derive or re-check any of that logic
// itself. It DOES drive `seo_brain_resolve_link_website` and
// `seo_brain_link_authorize` once a genuine session exists, because completing
// that is this page's whole purpose: a resolved identity alone is never
// presented as a successful connection.
import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getBrainAppUrl } from "@/config/runtimeConfig";
import { SEO_DEFAULT_ROUTE, SEO_LOGIN_PATH } from "@/routes/routeAccess";
import { getCurrentUserId } from "@/services/supabase/supabaseServiceUtils";
import {
  authorizeLinkedWebsite,
  continueCaseD,
  decideCaseDSessionAction,
  establishCaseASession,
  provisionCaseA,
  redeemBrainLinkIntent,
  resolveLinkWebsite,
  type BrainLinkIntentRedemption,
} from "@/services/supabase/seoBrainLinkIntentService";
import { stripLaunchCodeFromUrl } from "./brainConnectUrl";

type ViewState =
  | { step: "working" }
  | { step: "confirm"; redemption: BrainLinkIntentRedemption }
  | { step: "confirming" }
  | { step: "provisioning" }
  | { step: "connecting" }
  | { step: "verify-existing" }
  | { step: "pending-verification" }
  | { step: "blocked"; message: string }
  | { step: "success" };

const BLOCKED_MESSAGES: Record<string, string> = {
  invalid_or_expired_code:
    "This connection link is invalid or has expired. Please start the connection from Marketing Brain again.",
  anonymous_session_not_eligible:
    "Please sign in to your Digibility Search account, then start this connection again from Marketing Brain.",
  seo_access_required:
    "Your Digibility Search account does not currently include SEO access. Contact your administrator.",
  case_b_conflict:
    "Your current Search session is already connected to a different business. Sign out and try again, or contact support.",
  session_mismatch:
    "Your current Search session belongs to a different account. Sign out and try again from Marketing Brain.",
};

/**
 * Failure resolutions from `seo_brain_resolve_link_website` and
 * `seo_brain_link_authorize`. Anything not listed falls back to a generic
 * message rather than exposing an internal resolution code.
 */
const LINKING_FAILURE_MESSAGES: Record<string, string> = {
  unauthorized: "Your Digibility Search account does not currently include SEO access. Contact your administrator.",
  identity_mismatch: "Your current Search session does not match this connection. Please try again from Marketing Brain.",
  intent_expired: "This connection has expired. Please start again from Marketing Brain.",
  actor_mapping_inactive: "This connection is no longer active. Please start again from Marketing Brain.",
  website_ambiguous: "Multiple matching websites were found. Contact support to complete this connection.",
  workspace_ambiguous: "Multiple matching workspaces were found. Contact support to complete this connection.",
  ownership_not_verified: "Domain ownership has not yet been verified for this website.",
  business_host_already_linked: "This business is already connected to this website.",
  website_already_linked: "This website is already connected to a different business.",
};

function describeLinkingFailure(resolution: string): string {
  return LINKING_FAILURE_MESSAGES[resolution] ?? "This connection could not be completed. Please try again.";
}

function returnToBrain(): void {
  const brainUrl = getBrainAppUrl();
  window.location.assign(brainUrl || SEO_DEFAULT_ROUTE);
}

export function SeoBrainConnectPage() {
  const [searchParams] = useSearchParams();
  // Captured once, into component memory only, and kept for the whole flow
  // (initial redemption, case B confirmation, case A provisioning). It is
  // deliberately NOT read from `searchParams` again, because the effect below
  // removes it from the visible URL. It is never persisted to storage, so a
  // refresh after that removal restarts from Marketing Brain rather than
  // resuming an in-progress flow.
  const [launchCode] = useState(() => (searchParams.get("launchCode") ?? "").trim());
  const started = useRef(false);
  const [state, setState] = useState<ViewState>({ step: "working" });

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    // The one-time code is safely in component memory by now, so drop it from
    // the address bar and from this history entry. `replaceState` rewrites the
    // current entry in place: no navigation, no reload, no remount.
    stripLaunchCodeFromUrl(typeof window === "undefined" ? undefined : window);

    if (!launchCode) {
      setState({ step: "blocked", message: "This connection link is missing its one-time code." });
      return;
    }

    void runInitialRedemption(launchCode, setState);
  }, [launchCode]);

  useEffect(() => {
    if (state.step !== "success") return;
    const timer = window.setTimeout(returnToBrain, 1200);
    return () => window.clearTimeout(timer);
  }, [state.step]);

  const handleConfirm = async () => {
    setState({ step: "confirming" });
    try {
      const redemption = await redeemBrainLinkIntent(launchCode, true);
      applyOutcome(redemption, setState, launchCode);
    } catch (reason) {
      setState({ step: "blocked", message: describeError(reason) });
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-lg">Connecting your Search Intelligence</CardTitle>
          <CardDescription>{describeState(state)}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {(state.step === "working" ||
            state.step === "confirming" ||
            state.step === "provisioning" ||
            state.step === "connecting") && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground" aria-live="polite">
              <Loader2 className="h-4 w-4 animate-spin" />
              {describeState(state)}
            </div>
          )}

          {state.step === "confirm" && (
            <>
              <p className="text-sm text-muted-foreground">
                Connecting{" "}
                <span className="font-medium text-foreground">{state.redemption.brainConfirmedEmail}</span>
                {state.redemption.businessDisplayName
                  ? ` for ${state.redemption.businessDisplayName}`
                  : ""}
                {state.redemption.normalizedHost ? ` (${state.redemption.normalizedHost})` : ""}.
              </p>
              <Button className="w-full" onClick={() => void handleConfirm()}>
                Confirm connection
              </Button>
            </>
          )}

          {state.step === "verify-existing" && (
            <Button className="w-full" onClick={() => window.location.assign(SEO_LOGIN_PATH)}>
              Sign in to your Search account
            </Button>
          )}

          {state.step === "pending-verification" && (
            <>
              <p className="text-sm text-muted-foreground">
                We are verifying that you own this website. This can take a little while, and you can safely
                return to Marketing Brain now and come back once verification completes.
              </p>
              <Button className="w-full" onClick={returnToBrain}>
                Return to Marketing Brain
              </Button>
            </>
          )}

          {state.step === "blocked" && (
            <>
              <p className="text-sm text-destructive" role="alert">
                {state.message}
              </p>
              <Button className="w-full" onClick={returnToBrain}>
                Return to Marketing Brain
              </Button>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function describeState(state: ViewState): string {
  switch (state.step) {
    case "working":
    case "confirming":
      return "Setting up your secure connection…";
    case "provisioning":
      return "Creating your secure Search connection…";
    case "connecting":
      return "Connecting your website…";
    case "confirm":
      return "You already have a Digibility Search session. Confirm that you want to connect it to this business.";
    case "verify-existing":
      return "An existing Search account was found. Please sign in to that account before continuing.";
    case "pending-verification":
      return "Verifying domain ownership…";
    case "success":
      return "Connected. Returning you to your Marketing Brain…";
    case "blocked":
      return "We could not complete your secure connection.";
    default:
      return "";
  }
}

function describeError(reason: unknown): string {
  return reason instanceof Error ? reason.message : "SEO sign-in could not be completed.";
}

/**
 * Applies whatever `seo_brain_link_intent_redeem` already decided. This is a
 * direct 1:1 mapping from outcome to screen; it does not evaluate any of the
 * case A-D conditions itself. Case A/B/D each end, once a genuine SEO session
 * exists, by handing off to `completeLinking`: website resolution and
 * authorization are identical from there regardless of which case produced
 * the session.
 */
function applyOutcome(
  redemption: BrainLinkIntentRedemption,
  setState: (state: ViewState) => void,
  launchCode: string,
): void {
  switch (redemption.outcome) {
    case "case_b_confirmed":
      // The live session that just confirmed IS the identity establishment
      // for case B: no further session step is needed before linking.
      if (!redemption.intentId) {
        setState({ step: "blocked", message: "This connection could not be completed." });
        return;
      }
      setState({ step: "connecting" });
      void completeLinking(redemption.intentId, setState);
      return;

    case "case_d_resolved":
      setState({ step: "provisioning" });
      void runCaseDContinuation(launchCode, redemption, setState);
      return;

    case "confirmation_required":
      setState({ step: "confirm", redemption });
      return;

    case "existing_account_verification_required":
      setState({ step: "verify-existing" });
      return;

    case "case_a_provisioning_required":
      setState({ step: "provisioning" });
      void runCaseAProvisioning(launchCode, setState);
      return;

    case "invalid_or_expired_code":
    case "anonymous_session_not_eligible":
    case "seo_access_required":
    case "case_b_conflict":
      setState({
        step: "blocked",
        message: BLOCKED_MESSAGES[redemption.outcome] ?? "This connection could not be completed.",
      });
      return;
  }
}

async function runInitialRedemption(
  launchCode: string,
  setState: (state: ViewState) => void,
): Promise<void> {
  try {
    const redemption = await redeemBrainLinkIntent(launchCode, false);
    applyOutcome(redemption, setState, launchCode);
  } catch (reason) {
    setState({ step: "blocked", message: describeError(reason) });
  }
}

async function runCaseAProvisioning(
  launchCode: string,
  setState: (state: ViewState) => void,
): Promise<void> {
  try {
    const provisioned = await provisionCaseA(launchCode);
    await establishCaseASession(provisioned);
    setState({ step: "connecting" });
    await completeLinking(provisioned.intentId, setState);
  } catch (reason) {
    setState({ step: "blocked", message: describeError(reason) });
  }
}

/**
 * Case D: the intent already redeemed server-side to an existing, durably
 * mapped SEO user, but this browser's own current session may not belong to
 * that user at all. `decideCaseDSessionAction` is the one place that decides
 * whether it is safe to proceed with the current session, safe to replace it
 * via `continueCaseD`, or must be refused outright; this function only acts
 * on that decision, it never makes it.
 */
async function runCaseDContinuation(
  launchCode: string,
  redemption: BrainLinkIntentRedemption,
  setState: (state: ViewState) => void,
): Promise<void> {
  const intentId = redemption.intentId;
  const mappedSeoUserId = redemption.seoUserId;
  if (!intentId || !mappedSeoUserId) {
    setState({ step: "blocked", message: "This connection could not be completed." });
    return;
  }

  try {
    const currentUserId = await getCurrentUserId();
    const action = decideCaseDSessionAction(currentUserId, mappedSeoUserId);

    if (action === "session_mismatch") {
      setState({ step: "blocked", message: BLOCKED_MESSAGES.session_mismatch });
      return;
    }

    if (action === "continue_required") {
      const continued = await continueCaseD(launchCode);
      await establishCaseASession(continued);
    }

    setState({ step: "connecting" });
    await completeLinking(intentId, setState);
  } catch (reason) {
    setState({ step: "blocked", message: describeError(reason) });
  }
}

/**
 * The single completion path every case (A, B and D) converges on once a
 * genuine SEO session exists for the redeemed intent: resolve the website the
 * intent's host identifies (never a customer selector), and only then
 * authorize the real Brain <-> SEO link. A resolved-but-unverified website is
 * shown as pending, never as connected; only `authorize` actually resolving
 * counts as success.
 */
async function completeLinking(intentId: string, setState: (state: ViewState) => void): Promise<void> {
  try {
    const resolution = await resolveLinkWebsite(intentId);
    if (resolution.resolution !== "resolved" || !resolution.websiteId) {
      setState({ step: "blocked", message: describeLinkingFailure(resolution.resolution) });
      return;
    }

    if (!resolution.verified) {
      setState({ step: "pending-verification" });
      return;
    }

    const authorization = await authorizeLinkedWebsite(intentId, resolution.websiteId);
    if (authorization.resolution !== "resolved") {
      setState({ step: "blocked", message: describeLinkingFailure(authorization.resolution) });
      return;
    }

    setState({ step: "success" });
  } catch (reason) {
    setState({ step: "blocked", message: describeError(reason) });
  }
}
