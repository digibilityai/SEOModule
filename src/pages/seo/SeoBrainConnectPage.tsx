// D-026A SEO PR-1 continuation (Stage 2): the smallest SEO-owned browser step
// between "Brain creates an intent" and "customer returns to Brain". Chromeless,
// like SeoBridgePage, and rendered OUTSIDE the protected app shell — a case A/C
// customer has no SEO session yet.
//
// This page only ever receives the opaque `launchCode`. It never receives
// brainActorId, brainBusinessId, normalizedHost, a website id, or the module
// machine secret, and it never starts website linkage (seo_brain_link_authorize
// is intentionally not called here). Every case A-D decision is read directly
// off the outcome `seo_brain_link_intent_redeem` (and, for case A,
// `link-intent/provision`) already returned — this component does not
// re-derive or re-check any of that logic itself.
import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getBrainAppUrl } from "@/config/runtimeConfig";
import { SEO_DEFAULT_ROUTE, SEO_LOGIN_PATH } from "@/routes/routeAccess";
import {
  establishCaseASession,
  provisionCaseA,
  redeemBrainLinkIntent,
  type BrainLinkIntentRedemption,
} from "@/services/supabase/seoBrainLinkIntentService";
import { stripLaunchCodeFromUrl } from "./brainConnectUrl";

type ViewState =
  | { step: "working" }
  | { step: "confirm"; redemption: BrainLinkIntentRedemption }
  | { step: "confirming" }
  | { step: "provisioning" }
  | { step: "verify-existing" }
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
};

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
          {(state.step === "working" || state.step === "confirming" || state.step === "provisioning") && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground" aria-live="polite">
              <Loader2 className="h-4 w-4 animate-spin" />
              Setting up your secure connection…
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
    case "confirm":
      return "You already have a Digibility Search session. Confirm that you want to connect it to this business.";
    case "verify-existing":
      return "An existing Search account was found. Please sign in to that account before continuing.";
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
 * Applies whatever `seo_brain_link_intent_redeem` (or, for case A,
 * `link-intent/provision`) already decided. This is a direct 1:1 mapping from
 * outcome to screen; it does not evaluate any of the case A-D conditions
 * itself.
 */
function applyOutcome(
  redemption: BrainLinkIntentRedemption,
  setState: (state: ViewState) => void,
  launchCode: string,
): void {
  switch (redemption.outcome) {
    case "case_d_resolved":
    case "case_b_confirmed":
      // The mapping/confirmation this call just resolved IS the identity
      // establishment for these two cases — no further session step is
      // defined for them in the D-026A backend, and none is added here.
      setState({ step: "success" });
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
    setState({ step: "success" });
  } catch (reason) {
    setState({ step: "blocked", message: describeError(reason) });
  }
}
