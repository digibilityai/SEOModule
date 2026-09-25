import { afterEach, describe, expect, it, vi } from "vitest";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS } from "@/services/supabase/supabaseTypes";
import {
  authorizeLinkedWebsite,
  continueCaseD,
  decideCaseDSessionAction,
  establishCaseASession,
  provisionCaseA,
  redeemBrainLinkIntent,
  resolveLinkWebsite,
} from "./seoBrainLinkIntentService";

// D-026A SEO PR-1 continuation (Stage 2). These tests exercise only the thin
// adapter functions the SEO-owned browser step calls: the RPC/fetch wrappers
// and their outcome typing. Case A-D decision logic itself is verified against
// the backend, not re-tested here (see supabase/migrations/20260921120000_
// seo_brain_link_intents.sql and its own verification suite).

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("redeemBrainLinkIntent", () => {
  it("sends the launch code and confirm flag as the documented RPC params", async () => {
    const rpcSpy = vi
      .spyOn(supabase, "rpc")
      .mockResolvedValue({ data: { outcome: "case_d_resolved", intentId: "i1", seoUserId: "u1" }, error: null } as never);

    const result = await redeemBrainLinkIntent("abc123", false);

    expect(rpcSpy).toHaveBeenCalledWith(SEO_RPCS.seoBrainLinkIntentRedeem, {
      p_launch_code: "abc123",
      p_confirm: false,
    });
    expect(result).toEqual({
      outcome: "case_d_resolved",
      intentId: "i1",
      seoUserId: "u1",
      brainConfirmedEmail: undefined,
      businessDisplayName: undefined,
      normalizedHost: undefined,
    });
  });

  it("passes confirm=true through unchanged on the confirmation call", async () => {
    const rpcSpy = vi
      .spyOn(supabase, "rpc")
      .mockResolvedValue({ data: { outcome: "case_b_confirmed", intentId: "i2", seoUserId: "u2" }, error: null } as never);

    await redeemBrainLinkIntent("abc123", true);

    expect(rpcSpy).toHaveBeenCalledWith(SEO_RPCS.seoBrainLinkIntentRedeem, {
      p_launch_code: "abc123",
      p_confirm: true,
    });
  });

  it("surfaces case C (existing_account_verification_required) without extra fields", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { outcome: "existing_account_verification_required" },
      error: null,
    } as never);

    const result = await redeemBrainLinkIntent("abc123", false);

    expect(result.outcome).toBe("existing_account_verification_required");
    expect(result.intentId).toBeUndefined();
    expect(result.seoUserId).toBeUndefined();
  });

  it("surfaces case A (case_a_provisioning_required) with only the confirmed email", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { outcome: "case_a_provisioning_required", brainConfirmedEmail: "customer@example.com" },
      error: null,
    } as never);

    const result = await redeemBrainLinkIntent("abc123", false);

    expect(result.outcome).toBe("case_a_provisioning_required");
    expect(result.brainConfirmedEmail).toBe("customer@example.com");
    expect(result.intentId).toBeUndefined();
  });

  it("surfaces confirmation_required (case B, step 1) with its safe presentation fields", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: {
        outcome: "confirmation_required",
        brainConfirmedEmail: "customer@example.com",
        businessDisplayName: "MappedSkills",
        normalizedHost: "mappedskills.com",
      },
      error: null,
    } as never);

    const result = await redeemBrainLinkIntent("abc123", false);

    expect(result).toMatchObject({
      outcome: "confirmation_required",
      brainConfirmedEmail: "customer@example.com",
      businessDisplayName: "MappedSkills",
      normalizedHost: "mappedskills.com",
    });
  });

  it("surfaces invalid_or_expired_code for a missing/expired/reused launch code", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { outcome: "invalid_or_expired_code" },
      error: null,
    } as never);

    const result = await redeemBrainLinkIntent("stale-code", false);

    expect(result.outcome).toBe("invalid_or_expired_code");
  });

  it("surfaces case_b_conflict without creating anything client-side", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { outcome: "case_b_conflict" },
      error: null,
    } as never);

    const result = await redeemBrainLinkIntent("abc123", true);

    expect(result.outcome).toBe("case_b_conflict");
  });

  it("throws on an RPC-level error", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: null,
      error: { message: "network down" },
    } as never);

    await expect(redeemBrainLinkIntent("abc123", false)).rejects.toThrow("network down");
  });

  it("throws on an unrecognized outcome rather than silently passing it through", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { outcome: "some_future_outcome" },
      error: null,
    } as never);

    await expect(redeemBrainLinkIntent("abc123", false)).rejects.toThrow("unrecognized redemption outcome");
  });
});

describe("provisionCaseA", () => {
  it("POSTs only the launch code, never brainActorId/brainBusinessId/normalizedHost/a secret", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ intentId: "i1", tokenHash: "a".repeat(64), otpType: "magiclink" }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await provisionCaseA("launch-code-xyz");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toContain("/functions/v1/seo-module-api/link-intent/provision");
    const body = JSON.parse(init.body as string);
    expect(body).toEqual({ launchCode: "launch-code-xyz" });
    expect(init.headers).not.toHaveProperty("authorization");
    expect(result).toEqual({ intentId: "i1", tokenHash: "a".repeat(64), otpType: "magiclink" });
  });

  it("maps an existing_account provisioning error to a safe, actionable message", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        json: async () => ({ error: { code: "existing_account", message: "internal detail" } }),
      }),
    );

    await expect(provisionCaseA("launch-code-xyz")).rejects.toThrow(/already exists for this email/);
  });

  it("maps not_pending to a safe message", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        json: async () => ({ error: { code: "not_pending", message: "internal detail" } }),
      }),
    );

    await expect(provisionCaseA("launch-code-xyz")).rejects.toThrow(/already been used/);
  });
});

describe("establishCaseASession", () => {
  it("verifies the OTP with the exact token hash and type provisioning returned", async () => {
    const verifyOtpSpy = vi.spyOn(supabase.auth, "verifyOtp").mockResolvedValue({ error: null } as never);

    await establishCaseASession({ intentId: "i1", tokenHash: "a".repeat(64), otpType: "magiclink" });

    expect(verifyOtpSpy).toHaveBeenCalledWith({ token_hash: "a".repeat(64), type: "magiclink" });
  });

  it("throws a safe message when verifyOtp fails", async () => {
    vi.spyOn(supabase.auth, "verifyOtp").mockResolvedValue({ error: { message: "boom" } } as never);

    await expect(
      establishCaseASession({ intentId: "i1", tokenHash: "a".repeat(64), otpType: "magiclink" }),
    ).rejects.toThrow("SEO session creation failed");
  });
});

describe("decideCaseDSessionAction", () => {
  it("requires continuation when there is no current session", () => {
    expect(decideCaseDSessionAction(null, "mapped-user-1")).toBe("continue_required");
  });

  it("proceeds with the current session when it already belongs to the mapped user", () => {
    expect(decideCaseDSessionAction("mapped-user-1", "mapped-user-1")).toBe("proceed_with_current_session");
  });

  it("refuses safely rather than silently switching identity on a mismatch", () => {
    expect(decideCaseDSessionAction("someone-else", "mapped-user-1")).toBe("session_mismatch");
  });
});

describe("continueCaseD", () => {
  it("POSTs only the launch code to link-intent/continue", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ intentId: "i1", tokenHash: "a".repeat(64), otpType: "magiclink" }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await continueCaseD("launch-code-xyz");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toContain("/functions/v1/seo-module-api/link-intent/continue");
    expect(JSON.parse(init.body as string)).toEqual({ launchCode: "launch-code-xyz" });
    expect(init.headers).not.toHaveProperty("authorization");
    expect(result).toEqual({ intentId: "i1", tokenHash: "a".repeat(64), otpType: "magiclink" });
  });

  it("maps not_continuable to a safe, actionable message", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        json: async () => ({ error: { code: "not_continuable", message: "internal detail" } }),
      }),
    );

    await expect(continueCaseD("launch-code-xyz")).rejects.toThrow(/no longer eligible for sign-in/);
  });
});

describe("resolveLinkWebsite", () => {
  it("sends the intent id and returns the resolution, website id and verified flag", async () => {
    const rpcSpy = vi
      .spyOn(supabase, "rpc")
      .mockResolvedValue({ data: { resolution: "resolved", websiteId: "w1", verified: true }, error: null } as never);

    const result = await resolveLinkWebsite("intent-1");

    expect(rpcSpy).toHaveBeenCalledWith(SEO_RPCS.seoBrainResolveLinkWebsite, { p_intent_id: "intent-1" });
    expect(result).toEqual({ resolution: "resolved", websiteId: "w1", verified: true });
  });

  it("surfaces an unverified resolution without treating it as a failure", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { resolution: "resolved", websiteId: "w1", verified: false },
      error: null,
    } as never);

    const result = await resolveLinkWebsite("intent-1");
    expect(result.resolution).toBe("resolved");
    expect(result.verified).toBe(false);
  });

  it("surfaces a conflict resolution (e.g. website_ambiguous) without websiteId", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { resolution: "website_ambiguous" },
      error: null,
    } as never);

    const result = await resolveLinkWebsite("intent-1");
    expect(result).toEqual({ resolution: "website_ambiguous", websiteId: undefined, verified: undefined });
  });

  it("throws on an unrecognized resolution rather than silently passing it through", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { resolution: "some_future_resolution" },
      error: null,
    } as never);

    await expect(resolveLinkWebsite("intent-1")).rejects.toThrow("unrecognized resolution");
  });

  it("throws on an RPC-level error", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({ data: null, error: { message: "network down" } } as never);
    await expect(resolveLinkWebsite("intent-1")).rejects.toThrow("network down");
  });
});

describe("authorizeLinkedWebsite", () => {
  it("sends the intent and website ids and returns the resolution on success", async () => {
    const rpcSpy = vi
      .spyOn(supabase, "rpc")
      .mockResolvedValue({ data: { resolution: "resolved", linkId: "l1", websiteId: "w1" }, error: null } as never);

    const result = await authorizeLinkedWebsite("intent-1", "w1");

    expect(rpcSpy).toHaveBeenCalledWith(SEO_RPCS.seoBrainLinkAuthorize, {
      p_intent_id: "intent-1",
      p_website_id: "w1",
    });
    expect(result).toEqual({ resolution: "resolved", linkId: "l1", websiteId: "w1" });
  });

  it("surfaces ownership_not_verified as a non-throwing failure resolution", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { resolution: "ownership_not_verified" },
      error: null,
    } as never);

    const result = await authorizeLinkedWebsite("intent-1", "w1");
    expect(result.resolution).toBe("ownership_not_verified");
    expect(result.linkId).toBeUndefined();
  });

  it("recognizes already_linked (idempotent repeat) as a valid resolution, carrying the existing link id", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { resolution: "already_linked", linkId: "l1", websiteId: "w1" },
      error: null,
    } as never);

    const result = await authorizeLinkedWebsite("intent-1", "w1");
    expect(result).toEqual({ resolution: "already_linked", linkId: "l1", websiteId: "w1" });
  });

  it("throws on an unrecognized resolution rather than silently passing it through", async () => {
    vi.spyOn(supabase, "rpc").mockResolvedValue({
      data: { resolution: "some_future_resolution" },
      error: null,
    } as never);

    await expect(authorizeLinkedWebsite("intent-1", "w1")).rejects.toThrow("unrecognized resolution");
  });
});
