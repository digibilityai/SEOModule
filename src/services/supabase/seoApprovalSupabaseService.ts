import type {
  ActionType,
  ApprovalComment,
  ApprovalItem,
  EffortLevel,
  ImpactLevel,
  OwnerType,
  RecommendationStatus,
  RiskLevel,
  SeoIssue,
  SeoRecommendation,
  SeoUserRole,
  SeoWebsite,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { requireAuthenticatedUser, safeList, safeSingle } from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

// Row shapes as stored (Stage 2 migration 6, seo_approval_items + seo_approval_comments).
interface SeoApprovalItemRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  recommendation_id: string;
  issue_id: string | null;
  title: string;
  page_url: string | null;
  simple_explanation: string;
  suggested_change: string;
  action_type: ActionType;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  fix_owner: OwnerType;
  is_high_risk_category: boolean;
  status: RecommendationStatus;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoApprovalCommentRow {
  id: string;
  approval_item_id: string;
  actor_role_snapshot: string;
  comment_text: string;
  created_at: string;
}

const APPROVAL_ITEM_COLUMNS =
  "id, workspace_id, website_id, website_url, recommendation_id, issue_id, title, page_url, simple_explanation, suggested_change, action_type, impact, effort, risk, confidence_percentage, fix_owner, is_high_risk_category, status, created_by, created_at, updated_at";

/**
 * Thrown when the Stage 2 `seo_approval_transition` RPC itself rejects the
 * call — unknown action, item not found, or (most importantly) the caller's
 * role/risk permission check fails. Deliberately a distinct error type: the
 * approvalService.ts wiring must NOT catch this the same way it catches a
 * missing session/config and silently fall back to mock. A mock "success"
 * would mask a real backend permission denial, defeating the entire point
 * of enforcing role/risk rules server-side.
 */
export class ApprovalTransitionError extends Error {}

function mapToApprovalComment(row: SeoApprovalCommentRow): ApprovalComment {
  return {
    id: row.id,
    author_role: row.actor_role_snapshot as SeoUserRole,
    comment_text: row.comment_text,
    created_at: row.created_at,
  };
}

function mapToApprovalItem(row: SeoApprovalItemRow, comments: ApprovalComment[]): ApprovalItem {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    recommendation_id: row.recommendation_id,
    issue_id: row.issue_id ?? undefined,
    title: row.title,
    page_url: row.page_url ?? undefined,
    simple_explanation: row.simple_explanation,
    suggested_change: row.suggested_change,
    action_type: row.action_type,
    impact: row.impact,
    effort: row.effort,
    risk: row.risk,
    confidence_percentage: row.confidence_percentage,
    fix_owner: row.fix_owner,
    is_high_risk_category: row.is_high_risk_category,
    status: row.status,
    comments,
  };
}

async function fetchCommentsForItems(itemIds: string[]): Promise<Map<string, ApprovalComment[]>> {
  if (itemIds.length === 0) return new Map();
  const rows = await safeList<SeoApprovalCommentRow>(
    "seoApprovalSupabaseService.fetchCommentsForItems",
    supabase
      .from(SEO_TABLES.approvalComments)
      .select("id, approval_item_id, actor_role_snapshot, comment_text, created_at")
      .in("approval_item_id", itemIds)
      .order("created_at", { ascending: true }),
  );
  const byItem = new Map<string, ApprovalComment[]>();
  for (const row of rows) {
    const list = byItem.get(row.approval_item_id) ?? [];
    list.push(mapToApprovalComment(row));
    byItem.set(row.approval_item_id, list);
  }
  return byItem;
}

/** Lists approval items for a website, each with its comments attached (tolerant of zero comments). */
export async function fetchSupabaseApprovalQueue(websiteId: string): Promise<ApprovalItem[]> {
  await requireAuthenticatedUser("seoApprovalSupabaseService.fetchSupabaseApprovalQueue");
  const rows = await safeList<SeoApprovalItemRow>(
    "seoApprovalSupabaseService.fetchSupabaseApprovalQueue",
    supabase
      .from(SEO_TABLES.approvalItems)
      .select(APPROVAL_ITEM_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
  const commentsByItem = await fetchCommentsForItems(rows.map((row) => row.id));
  return rows.map((row) => mapToApprovalItem(row, commentsByItem.get(row.id) ?? []));
}

export async function fetchSupabaseApprovalItemById(id: string): Promise<ApprovalItem | null> {
  await requireAuthenticatedUser("seoApprovalSupabaseService.fetchSupabaseApprovalItemById");
  const row = await safeSingle<SeoApprovalItemRow>(
    "seoApprovalSupabaseService.fetchSupabaseApprovalItemById",
    supabase.from(SEO_TABLES.approvalItems).select(APPROVAL_ITEM_COLUMNS).eq("id", id).maybeSingle(),
  );
  if (!row) return null;
  const commentsByItem = await fetchCommentsForItems([row.id]);
  return mapToApprovalItem(row, commentsByItem.get(row.id) ?? []);
}

// Matches the mock adapter's fallback (src/mocks/approvalMockData.ts) — used
// only when a recommendation has no linked issue to derive fix_owner from.
const FIX_OWNER_BY_ACTION_TYPE: Record<ActionType, OwnerType> = {
  auto_suggest: "system_suggestion",
  approval_required: "developer_needed",
  manual_support: "client_action",
  expert_review: "digibility_expert",
  avoid: "system_suggestion",
};

/**
 * Creates a Stage 2 approval item for any recommendation that doesn't
 * already have one for this website yet (the DB's UNIQUE recommendation_id
 * constraint makes this idempotent — safe to call repeatedly). This is a
 * mechanical 1:1 mapping from existing recommendation rows (no AI/crawler
 * content synthesis), which Stage 2 RLS explicitly permits owner/admin/
 * team_member to do via direct INSERT — unlike recommendation *generation*
 * itself (Phase 13C), which stays mock-only.
 *
 * `is_high_risk_category` is intentionally NOT set in the insert payload:
 * the Stage 2 `trg_seo_approval_items_hrc` trigger derives it non-forgeably
 * from the linked issue's category server-side.
 */
export async function ensureSupabaseApprovalQueueGenerated(
  website: SeoWebsite,
  recommendations: SeoRecommendation[],
  issues: SeoIssue[],
): Promise<ApprovalItem[]> {
  const userId = await requireAuthenticatedUser(
    "seoApprovalSupabaseService.ensureSupabaseApprovalQueueGenerated",
  );

  const existingRows = await safeList<{ recommendation_id: string }>(
    "seoApprovalSupabaseService.ensureSupabaseApprovalQueueGenerated (lookup)",
    supabase.from(SEO_TABLES.approvalItems).select("recommendation_id").eq("website_id", website.id),
  );
  const existingRecIds = new Set(existingRows.map((row) => row.recommendation_id));
  const toCreate = recommendations.filter((rec) => !existingRecIds.has(rec.id));

  if (toCreate.length > 0) {
    const issueById = new Map(issues.map((issue) => [issue.id, issue]));
    const payload = toCreate.map((rec) => {
      const issue = rec.issue_id ? issueById.get(rec.issue_id) : undefined;
      return {
        workspace_id: website.workspace_id,
        website_id: website.id,
        website_url: website.website_url,
        recommendation_id: rec.id,
        issue_id: rec.issue_id ?? null,
        title: rec.title,
        page_url: issue?.affected_page_url ?? website.website_url,
        simple_explanation: issue?.simple_explanation ?? rec.why_it_helps,
        suggested_change: rec.suggested_change,
        action_type: rec.action_type,
        impact: rec.impact,
        effort: rec.effort,
        risk: rec.risk,
        confidence_percentage: rec.confidence_percentage,
        fix_owner: issue?.fix_owner ?? FIX_OWNER_BY_ACTION_TYPE[rec.action_type],
        status: rec.status,
        created_by: userId,
      };
    });

    const { error } = await supabase
      .from(SEO_TABLES.approvalItems)
      .upsert(payload, { onConflict: "recommendation_id", ignoreDuplicates: true });
    if (error) {
      throw new Error(
        `seoApprovalSupabaseService.ensureSupabaseApprovalQueueGenerated: ${normalizeSupabaseError(error).message}`,
      );
    }
  }

  return fetchSupabaseApprovalQueue(website.id);
}

// Maps the app's target status (what the UI's mutation buttons ask for) onto
// the Stage 2 seo_approval_transition action that produces it. Statuses with
// no entry here ("suggested", "needs_review", "ready_to_publish") have no
// direct transition action in Stage 2 and are never requested by the current
// UI's mutation buttons.
const STATUS_TO_TRANSITION_ACTION: Partial<Record<RecommendationStatus, string>> = {
  approved: "approve",
  rejected: "reject",
  expert_review_requested: "expert_review",
  developer_needed: "developer_needed",
  completed: "completed",
};

async function callApprovalTransition(
  approvalItemId: string,
  action: string,
  note?: string,
): Promise<void> {
  const { error } = await supabase.rpc(SEO_RPCS.approvalTransition, {
    p_approval_item_id: approvalItemId,
    p_action: action,
    p_comment: note ?? null,
  });
  if (error) {
    // Reaching this point means auth already succeeded, so this is the
    // backend's real, authoritative decision (denied by role/risk rules,
    // item not found, unknown action, etc.) — never a "not signed in" case.
    throw new ApprovalTransitionError(normalizeSupabaseError(error).message);
  }
}

/**
 * Applies a workflow status change through the Stage 2
 * `seo_approval_transition` RPC — never a direct status UPDATE. The RPC is
 * the only sanctioned path for status changes; it enforces the role/risk
 * matrix, mirrors the status onto the linked recommendation, and logs
 * activity server-side.
 *
 * Editing `suggested_change` is a separate, RLS-sanctioned direct UPDATE
 * (Stage 2 migration comment: "not a transition — clients have no UPDATE"),
 * so it's handled with a plain table update instead of the RPC.
 */
export async function updateSupabaseApprovalItemFields(
  id: string,
  patch: Partial<Pick<ApprovalItem, "status" | "suggested_change">>,
): Promise<ApprovalItem | null> {
  await requireAuthenticatedUser("seoApprovalSupabaseService.updateSupabaseApprovalItemFields");

  if (patch.status) {
    const action = STATUS_TO_TRANSITION_ACTION[patch.status];
    if (!action) {
      throw new ApprovalTransitionError(
        `No Stage 2 transition action maps to status "${patch.status}".`,
      );
    }
    await callApprovalTransition(id, action);
    return fetchSupabaseApprovalItemById(id);
  }

  if (patch.suggested_change !== undefined) {
    const { error } = await supabase
      .from(SEO_TABLES.approvalItems)
      .update({ suggested_change: patch.suggested_change })
      .eq("id", id);
    if (error) {
      throw new Error(
        `seoApprovalSupabaseService.updateSupabaseApprovalItemFields: ${normalizeSupabaseError(error).message}`,
      );
    }
    return fetchSupabaseApprovalItemById(id);
  }

  return fetchSupabaseApprovalItemById(id);
}

/**
 * Adds a comment via the RPC's `comment` action (append-only; also logs a
 * `comment_added` activity row server-side). The passed-in `author_role` is
 * intentionally ignored here — Stage 2 always stamps the comment with the
 * caller's REAL workspace role (`seo_role_of`), which cannot be forged from
 * the frontend, unlike the UI's client-side role-simulation selector.
 */
export async function addSupabaseApprovalComment(
  id: string,
  comment: Pick<ApprovalComment, "author_role" | "comment_text">,
): Promise<ApprovalItem | null> {
  await requireAuthenticatedUser("seoApprovalSupabaseService.addSupabaseApprovalComment");
  await callApprovalTransition(id, "comment", comment.comment_text);
  return fetchSupabaseApprovalItemById(id);
}
