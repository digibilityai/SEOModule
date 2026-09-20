/**
 * SeoDataPort backed by the four delegated, service-role-only RPCs from
 * migration 20260920120100.
 *
 * Depends on a minimal RpcCaller rather than on a concrete Supabase client, so
 * the mapping below is testable in Node without a Deno runtime or a live
 * project, and so this file has no import edge into the browser application.
 */

import {
  SeoModuleContractError,
  type ModuleErrorCode,
} from "./contract.ts";
import {
  RESOLUTION_VALUES,
  type CrawlFindingsPage,
  type OwnershipStatus,
  type RecommendationsPage,
  type ResolvedTarget,
  type SeoDataPort,
  type TargetResolutionCode,
} from "./port.ts";

export interface RpcError {
  message: string;
  code?: string;
}

export interface RpcCaller {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: RpcError | null }>;
}

function fail(code: ModuleErrorCode, message: string, internal?: string): never {
  throw new SeoModuleContractError(code, message, internal);
}

/**
 * A database failure is `module_unavailable`, never a fallback. There is no
 * mock adapter on this path and no "return something rather than nothing"
 * branch anywhere in this file: the Brain is told SEO could not answer.
 */
async function callRpc(
  caller: RpcCaller,
  fn: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  let response: { data: unknown; error: RpcError | null };
  try {
    response = await caller.rpc(fn, args);
  } catch (error) {
    fail(
      "module_unavailable",
      "The SEO module could not reach its database.",
      `${fn}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  if (response.error) {
    fail("module_unavailable", "The SEO module could not complete this read.", `${fn}: ${response.error.message}`);
  }
  return response.data;
}

function asResolution(value: unknown, fn: string): TargetResolutionCode {
  if (typeof value === "string" && (RESOLUTION_VALUES as readonly string[]).includes(value)) {
    return value as TargetResolutionCode;
  }
  fail(
    "module_unavailable",
    "The SEO module returned an unrecognized target resolution.",
    `${fn}: ${String(value)}`,
  );
}

function asPayload(data: unknown, fn: string): Record<string, unknown> {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    fail("module_unavailable", "The SEO module returned an unexpected payload.", fn);
  }
  return data as Record<string, unknown>;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function createSupabaseSeoDataPort(caller: RpcCaller): SeoDataPort {
  return {
    async resolveTarget(businessId, normalizedHost): Promise<ResolvedTarget> {
      const fn = "seo_brain_resolve_target";
      const data = await callRpc(caller, fn, {
        p_business_id: businessId,
        p_normalized_host: normalizedHost,
      });
      // This RPC is set returning and always emits exactly one row.
      const rows = Array.isArray(data) ? data : [data];
      const row = asPayload(rows[0], fn);
      return {
        resolution: asResolution(row.resolution, fn),
        websiteId: str(row.website_id),
        workspaceId: str(row.workspace_id),
        normalizedHost: str(row.normalized_host),
        websiteUrl: str(row.website_url),
        linkedAt: str(row.linked_at),
      };
    },

    async ownershipStatus(businessId, normalizedHost): Promise<OwnershipStatus> {
      const fn = "seo_brain_ownership_status";
      const payload = asPayload(
        await callRpc(caller, fn, {
          p_business_id: businessId,
          p_normalized_host: normalizedHost,
        }),
        fn,
      );
      return {
        resolution: asResolution(payload.resolution, fn),
        websiteId: str(payload.websiteId),
        verificationHost: str(payload.verificationHost),
        method: str(payload.method),
        ownershipSource: str(payload.ownershipSource),
        status: str(payload.status),
        verifiedAt: str(payload.verifiedAt),
        lastCheckedAt: str(payload.lastCheckedAt),
        failureReason: str(payload.failureReason),
      };
    },

    async crawlFindings(businessId, normalizedHost): Promise<CrawlFindingsPage> {
      const fn = "seo_brain_crawl_findings";
      const payload = asPayload(
        await callRpc(caller, fn, {
          p_business_id: businessId,
          p_normalized_host: normalizedHost,
        }),
        fn,
      );
      const rawFindings = Array.isArray(payload.findings) ? payload.findings : [];
      return {
        resolution: asResolution(payload.resolution, fn),
        websiteId: str(payload.websiteId),
        auditRunId: str(payload.auditRunId),
        auditCompletedAt: str(payload.auditCompletedAt),
        findings: rawFindings.map((entry) => {
          const finding = asPayload(entry, fn);
          return {
            findingKey: String(finding.findingKey ?? ""),
            title: String(finding.title ?? ""),
            observation: String(finding.observation ?? ""),
            recommendedAction: String(finding.recommendedAction ?? ""),
            severity: String(finding.severity ?? ""),
            category: str(finding.category),
            affectedPageUrl: str(finding.affectedPageUrl),
            issueScope: str(finding.issueScope),
            source: str(finding.source),
            crawlJobId: str(finding.crawlJobId),
            sourceIssueFingerprint: str(finding.sourceIssueFingerprint),
            sourceRuleVersion: str(finding.sourceRuleVersion),
          };
        }),
      };
    },

    async currentRecommendations(businessId, normalizedHost): Promise<RecommendationsPage> {
      const fn = "seo_brain_current_recommendations";
      const payload = asPayload(
        await callRpc(caller, fn, {
          p_business_id: businessId,
          p_normalized_host: normalizedHost,
        }),
        fn,
      );
      const rawRecs = Array.isArray(payload.recommendations) ? payload.recommendations : [];
      return {
        resolution: asResolution(payload.resolution, fn),
        websiteId: str(payload.websiteId),
        recommendations: rawRecs.map((entry) => {
          const rec = asPayload(entry, fn);
          return {
            recommendationId: String(rec.recommendationId ?? ""),
            findingKey: String(rec.findingKey ?? ""),
            area: String(rec.area ?? ""),
            title: String(rec.title ?? ""),
            currentValue: str(rec.currentValue),
            suggestedChange: String(rec.suggestedChange ?? ""),
            whyItHelps: String(rec.whyItHelps ?? ""),
            actionType: String(rec.actionType ?? ""),
            impact: String(rec.impact ?? ""),
            effort: String(rec.effort ?? ""),
            risk: String(rec.risk ?? ""),
            status: String(rec.status ?? ""),
            generationMethod: str(rec.generationMethod),
            sourceIssueFingerprint: str(rec.sourceIssueFingerprint),
            auditRunId: str(rec.auditRunId),
            updatedAt: str(rec.updatedAt),
          };
        }),
      };
    },
  };
}
