import { afterEach, describe, expect, it, vi } from "vitest";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS } from "@/services/supabase/supabaseTypes";
import {
  establishCaseASession,
  provisionCaseA,
  redeemBrainLinkIntent,
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
