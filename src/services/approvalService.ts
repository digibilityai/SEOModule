import type { ApprovalComment, ApprovalItem, SeoIssue, SeoRecommendation, SeoWebsite } from "@/types";
import { toAsync } from "@/lib/mockAsync";
import {
  listApprovalQueue,
  getApprovalItemById,
  updateApprovalItem,
  addCommentToApprovalItem,
  createApprovalItemsFromRecommendations,
} from "@/mocks/approvalMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { logDataModeWarning, requireSupabaseOrFallback } from "@/services/dataMode";
import { normalizeSupabaseErrorMessage } from "@/services/supabase/supabaseErrors";
import {
  ApprovalTransitionError,
  addSupabaseApprovalComment,
  ensureSupabaseApprovalQueueGenerated,
  fetchSupabaseApprovalItemById,
  fetchSupabaseApprovalQueue,
  updateSupabaseApprovalItemFields,
} from "@/services/supabase/seoApprovalSupabaseService";

export async function fetchApprovalQueue(websiteId: string): Promise<ApprovalItem[]> {
  return runWithServiceAdapter({
    label: "approvalService.fetchApprovalQueue",
    mock: () => toAsync(listApprovalQueue(websiteId)),
    supabase: () => fetchSupabaseApprovalQueue(websiteId),
  });
}

export async function fetchApprovalItemById(id: string): Promise<ApprovalItem | null> {
  return runWithServiceAdapter({
    label: "approvalService.fetchApprovalItemById",
    mock: () => toAsync(getApprovalItemById(id)),
    supabase: () => fetchSupabaseApprovalItemById(id),
  });
}

// Idempotent — only creates approval items for recommendations that don't
// already have one for this website. This is a mechanical 1:1 mapping from
// existing recommendation rows (no AI/crawler content synthesis), which
// Stage 2 RLS explicitly permits owner/admin/team_member to do directly —
// unlike recommendation *generation* itself (Phase 13C), which stays
// mock-only. Falls back to mock on any Supabase failure, same as other
// creation-style operations (e.g. addWebsite in Phase 13B).
export async function ensureApprovalQueueGenerated(
  website: SeoWebsite,
  recommendations: SeoRecommendation[],
  issues: SeoIssue[],
): Promise<ApprovalItem[]> {
  return runWithServiceAdapter({
    label: "approvalService.ensureApprovalQueueGenerated",
    mock: () => toAsync(createApprovalItemsFromRecommendations(website, recommendations, issues)),
    supabase: () => ensureSupabaseApprovalQueueGenerated(website, recommendations, issues),
  });
}

// Workflow-status changes and comments go through this instead of the
// standard runWithServiceAdapter: unlike a missing config/session (an infra
// failure that should gracefully fall back), a REAL rejection returned by
// the seo_approval_transition RPC (wrong role, high-risk item, etc.) must
// NEVER be silently masked by a mock "success" — that would defeat the
// entire point of enforcing role/risk rules server-side. Only pre-RPC
// failures (no session, no config) fall back to mock; a rejection the RPC
// actually returned is surfaced as a real error instead.
async function runApprovalWrite<T>(
  label: string,
  mock: () => Promise<T>,
  supabaseFn: () => Promise<T>,
): Promise<T> {
  if (!requireSupabaseOrFallback(label)) {
    return mock();
  }
  try {
    return await supabaseFn();
  } catch (error) {
    if (error instanceof ApprovalTransitionError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}

export async function updateApprovalItemFields(
  id: string,
  patch: Partial<Pick<ApprovalItem, "status" | "suggested_change">>,
): Promise<ApprovalItem | null> {
  return runApprovalWrite(
    "approvalService.updateApprovalItemFields",
    () => toAsync(updateApprovalItem(id, patch)),
    () => updateSupabaseApprovalItemFields(id, patch),
  );
}

export async function addApprovalComment(
  id: string,
  comment: Pick<ApprovalComment, "author_role" | "comment_text">,
): Promise<ApprovalItem | null> {
  return runApprovalWrite(
    "approvalService.addApprovalComment",
    () => toAsync(addCommentToApprovalItem(id, comment)),
    () => addSupabaseApprovalComment(id, comment),
  );
}
