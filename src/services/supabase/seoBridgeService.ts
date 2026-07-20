import { supabase } from "@/integrations/supabase/client";
import {
  getDigibilityAnonKey,
  getDigibilityBridgeUrl,
  hasDigibilityBridgeConfig,
} from "@/config/runtimeConfig";
import { sanitizeReturnPath, SEO_DEFAULT_ROUTE } from "@/routes/routeAccess";

export interface SeoBridgeRedemption {
  tokenHash: string;
  verificationType: "magiclink";
  returnTo: string;
}

const ERROR_MESSAGES: Record<string, string> = {
  invalid_launch_code: "This SEO launch link is invalid.",
  launch_code_expired_or_used: "This SEO launch link has expired or was already used.",
  seo_access_required: "Your Digibility account does not currently include SEO access.",
  account_inactive: "Your Digibility account is inactive.",
  bridge_unavailable: "SEO sign-in is temporarily unavailable.",
};

export function parseBridgeRedemption(value: unknown): SeoBridgeRedemption {
  const candidate = value as Partial<SeoBridgeRedemption> | null;
  if (
    !candidate ||
    typeof candidate.tokenHash !== "string" ||
    candidate.tokenHash.length < 20 ||
    candidate.verificationType !== "magiclink"
  ) {
    throw new Error("The SEO bridge returned an invalid response.");
  }
  return {
    tokenHash: candidate.tokenHash,
    verificationType: "magiclink",
    returnTo: sanitizeReturnPath(candidate.returnTo) ?? SEO_DEFAULT_ROUTE,
  };
}

export async function redeemSeoLaunchCode(code: string): Promise<SeoBridgeRedemption> {
  if (!hasDigibilityBridgeConfig()) {
    throw new Error("Digibility SEO single sign-on is not configured.");
  }

  const coreAnonKey = getDigibilityAnonKey();
  const response = await fetch(getDigibilityBridgeUrl(), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: coreAnonKey,
      Authorization: `Bearer ${coreAnonKey}`,
    },
    body: JSON.stringify({ action: "redeem", code }),
  });
  const body = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    const codeValue = typeof body.error === "string" ? body.error : "";
    throw new Error(ERROR_MESSAGES[codeValue] ?? "SEO sign-in could not be completed.");
  }
  return parseBridgeRedemption(body);
}

export async function establishSeoSession(redemption: SeoBridgeRedemption): Promise<void> {
  const { error } = await supabase.auth.verifyOtp({
    token_hash: redemption.tokenHash,
    type: redemption.verificationType,
  });
  if (error) throw new Error("SEO session creation failed. Please launch SEO again from Digibility.");
}
