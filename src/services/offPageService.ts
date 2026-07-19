import type {
  AuthorityCampaign,
  AuthorityOverview,
  NewAuthorityCampaignInput,
  OffPageOpportunity,
  OffPageOpportunityStatus,
  SeoWebsite,
  SpamRiskReview,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { logDataModeWarning, requireSupabaseOrFallback } from "@/services/dataMode";
import { normalizeSupabaseErrorMessage } from "@/services/supabase/supabaseErrors";
import { fetchLatestAudit } from "@/services/auditService";
import {
  AUTHORITY_DATA_SOURCE_STATUS,
  createAuthorityCampaign as createAuthorityCampaignRecord,
  listAuthorityCampaigns,
  listAuthorityOpportunities,
  updateAuthorityCampaignStatus as updateAuthorityCampaignStatusRecord,
  updateAuthorityOpportunityStatus as updateAuthorityOpportunityStatusRecord,
} from "@/mocks/offPageMockData";
import {
  AuthorityCampaignCreationError,
  AuthorityCampaignTransitionError,
  AuthorityOpportunityTransitionError,
  createSupabaseAuthorityCampaign,
  fetchSupabaseAuthorityCampaigns,
  fetchSupabaseAuthorityOpportunities,
  transitionSupabaseAuthorityCampaign,
  transitionSupabaseAuthorityOpportunity,
  type AuthorityCampaignTransitionAction,
  type AuthorityOpportunityTransitionAction,
} from "@/services/supabase/seoOffPageAuthoritySupabaseService";

// Phase 15A: fetchAuthorityOpportunities / fetchAuthorityCampaigns are wired
// via runWithServiceAdapter — mock mode is unchanged; Supabase mode reads
// Stage 6 (seo_authority_opportunities, seo_authority_campaigns +
// seo_authority_campaign_tasks + seo_authority_campaign_opportunities),
// mapped down into these same existing OffPageOpportunity/AuthorityCampaign
// shapes (see seoOffPageAuthoritySupabaseService.ts). No type or UI change.
//
// Phase 15C Step 1: transitionAuthorityOpportunity replaces the old
// status-setting updateAuthorityOpportunityStatus for OPPORTUNITY writes
// only. It takes a Stage 6 RPC ACTION name (shortlist/request_approval/
// request_expert_review/start/complete/reject/avoid) rather than a raw
// target status, since the RPC's own vocabulary is action-based and the
// legal from-status for each action is enforced server-side, not chosen by
// the caller — see seoOffPageAuthoritySupabaseService.ts's
// AuthorityOpportunityTransitionAction. Mock mode still only understands a
// target status (mockOffPageData.updateAuthorityOpportunityStatus, file
// unchanged), so ACTION_TO_MOCK_STATUS below maps each action to the exact
// status the real RPC would set it to, keeping mock and Supabase mode
// visibly equivalent for the same click.
//
// Phase 15D Step 1: createAuthorityCampaign now creates a real Supabase
// campaign row (always in `draft` — never `pending_approval` directly) via
// runAuthorityCampaignWrite, the same non-masking write pattern as
// runAuthorityOpportunityWrite above. Submission for approval, campaign
// approve/reject/return-to-draft, and every campaign task-completion write
// remain explicitly out of scope (see PHASE_15B_STAGE6_WRITE_UX_AUDIT.md §4.2
// for the proposed, not-yet-built, campaign action matrix) — mock mode is
// unchanged and still creates a campaign directly as pending_approval, which
// is a separate, pre-existing mock-only quirk this step does not touch.
//
// Phase 15D Step 2A: submitAuthorityCampaignForApproval wires ONLY the
// Draft -> Pending Approval transition, via the existing, already-TEST-verified
// seo_authority_campaign_transition RPC (`submit_for_approval` action) — never
// a direct approval_status UPDATE. Approve/reject/return-to-draft and task
// completion remain unbuilt. Opportunity writes (Phase 15C) are untouched by
// this step.
//
// Phase 15D Step 2B: approveAuthorityCampaign wires ONLY the Pending Approval
// -> Approved transition, via the same seo_authority_campaign_transition RPC
// (`approve` action) — owner/admin only (the RPC's own extra restriction,
// stricter than submit_for_approval's base check). Reject/return-to-draft and
// task completion remain unbuilt.
//
// Phase 15D Step 2C: rejectAuthorityCampaign wires ONLY the Pending Approval
// -> Rejected transition, via the same seo_authority_campaign_transition RPC
// (`reject` action) — owner/admin only, same restriction as `approve`.
// Return-to-draft and task completion remain unbuilt.
//
// Phase 15D Step 2D: returnCampaignToDraft wires ONLY the Rejected -> Draft
// transition, via the same seo_authority_campaign_transition RPC
// (`return_to_draft` action) — base manager check only (owner/admin/
// team_member), same restriction as `submit_for_approval`. The RPC also
// legally allows return_to_draft from pending_approval, but this step's UI
// exposes it only from rejected, per scope. Task completion and campaign
// editing/deletion remain unbuilt.

export async function fetchAuthorityOpportunities(websiteId: string): Promise<OffPageOpportunity[]> {
  return runWithServiceAdapter({
    label: "offPageService.fetchAuthorityOpportunities",
    mock: () => toAsync(listAuthorityOpportunities(websiteId)),
    supabase: () => fetchSupabaseAuthorityOpportunities(websiteId),
  });
}

// Mirrors the RPC's own v_to per action exactly (migration
// 20260711120020_seo_stage6_authority_activity.sql) — mock-mode-only, used
// solely so a click produces the same visible status change in both modes.
const ACTION_TO_MOCK_STATUS: Record<AuthorityOpportunityTransitionAction, OffPageOpportunityStatus> = {
  shortlist: "shortlisted",
  request_approval: "approval_required",
  request_expert_review: "expert_review_requested",
  start: "in_progress",
  complete: "completed",
  reject: "rejected",
  avoid: "avoided",
};

// Workflow-status changes go through this instead of the standard
// runWithServiceAdapter — same non-masking rule as Phase 13D's
// runApprovalWrite / Phase 13E's runContentWrite: a REAL rejection returned
// by seo_authority_opportunity_transition (illegal transition for the
// opportunity's current status, role not permitted, not found) must NEVER be
// silently masked by a mock "success" — that would defeat the entire point
// of the RPC's server-side state-machine + role enforcement. Only pre-RPC
// failures (no session, no config) fall back to mock; a rejection the RPC
// actually returned is surfaced as a real error instead.
async function runAuthorityOpportunityWrite<T>(
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
    if (error instanceof AuthorityOpportunityTransitionError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}

export async function transitionAuthorityOpportunity(
  id: string,
  action: AuthorityOpportunityTransitionAction,
  note?: string,
): Promise<OffPageOpportunity | null> {
  return runAuthorityOpportunityWrite(
    "offPageService.transitionAuthorityOpportunity",
    () => toAsync(updateAuthorityOpportunityStatusRecord(id, ACTION_TO_MOCK_STATUS[action])),
    () => transitionSupabaseAuthorityOpportunity(id, action, note),
  );
}

export async function fetchAuthorityCampaigns(websiteId: string): Promise<AuthorityCampaign[]> {
  return runWithServiceAdapter({
    label: "offPageService.fetchAuthorityCampaigns",
    mock: () => toAsync(listAuthorityCampaigns(websiteId)),
    supabase: () => fetchSupabaseAuthorityCampaigns(websiteId),
  });
}

// Same non-masking rule as runAuthorityOpportunityWrite above: a REAL
// rejection from creating the campaign row or a required child row
// (seo_authority_campaign_opportunities / seo_authority_campaign_tasks) must
// never be silently masked by a mock "success". Only pre-write failures (no
// session, no config — i.e. no Supabase row was ever created) fall back to
// mock.
async function runAuthorityCampaignWrite<T>(
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
    if (error instanceof AuthorityCampaignCreationError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}

export async function createAuthorityCampaign(
  website: SeoWebsite,
  input: NewAuthorityCampaignInput,
): Promise<AuthorityCampaign> {
  return runAuthorityCampaignWrite(
    "offPageService.createAuthorityCampaign",
    () => toAsync(createAuthorityCampaignRecord(website, input)),
    () => createSupabaseAuthorityCampaign(website, input),
  );
}

// Mirrors the RPC's own v_to for this one action exactly (migration
// 20260711120020_seo_stage6_authority_activity.sql) — mock-mode-only, used
// solely so a click produces the same visible status change in both modes.
const CAMPAIGN_ACTION_TO_MOCK_STATUS: Record<AuthorityCampaignTransitionAction, AuthorityCampaign["approval_status"]> = {
  submit_for_approval: "pending_approval",
  approve: "approved",
  reject: "rejected",
  return_to_draft: "draft",
};

// Same non-masking rule as runAuthorityOpportunityWrite: a REAL rejection
// returned by seo_authority_campaign_transition (illegal transition for the
// campaign's current approval_status, role not permitted, not found) must
// never be silently masked by a mock "success". Only pre-RPC failures (no
// session, no config) fall back to mock.
async function runAuthorityCampaignTransitionWrite<T>(
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
    if (error instanceof AuthorityCampaignTransitionError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}

export async function submitAuthorityCampaignForApproval(
  id: string,
  websiteId: string,
  note?: string,
): Promise<AuthorityCampaign | null> {
  return runAuthorityCampaignTransitionWrite(
    "offPageService.submitAuthorityCampaignForApproval",
    () =>
      toAsync(
        updateAuthorityCampaignStatusRecord(
          id,
          CAMPAIGN_ACTION_TO_MOCK_STATUS.submit_for_approval,
        ),
      ),
    () => transitionSupabaseAuthorityCampaign(id, websiteId, "submit_for_approval", note),
  );
}

export async function approveAuthorityCampaign(
  id: string,
  websiteId: string,
  note?: string,
): Promise<AuthorityCampaign | null> {
  return runAuthorityCampaignTransitionWrite(
    "offPageService.approveAuthorityCampaign",
    () => toAsync(updateAuthorityCampaignStatusRecord(id, CAMPAIGN_ACTION_TO_MOCK_STATUS.approve)),
    () => transitionSupabaseAuthorityCampaign(id, websiteId, "approve", note),
  );
}

export async function rejectAuthorityCampaign(
  id: string,
  websiteId: string,
  note?: string,
): Promise<AuthorityCampaign | null> {
  return runAuthorityCampaignTransitionWrite(
    "offPageService.rejectAuthorityCampaign",
    () => toAsync(updateAuthorityCampaignStatusRecord(id, CAMPAIGN_ACTION_TO_MOCK_STATUS.reject)),
    () => transitionSupabaseAuthorityCampaign(id, websiteId, "reject", note),
  );
}

export async function returnCampaignToDraft(
  id: string,
  websiteId: string,
  note?: string,
): Promise<AuthorityCampaign | null> {
  return runAuthorityCampaignTransitionWrite(
    "offPageService.returnCampaignToDraft",
    () => toAsync(updateAuthorityCampaignStatusRecord(id, CAMPAIGN_ACTION_TO_MOCK_STATUS.return_to_draft)),
    () => transitionSupabaseAuthorityCampaign(id, websiteId, "return_to_draft", note),
  );
}

// Derives from fetchAuthorityOpportunities (now adapter-wired above), so this
// stays correct in both modes automatically — same "derive from the wired
// read" pattern as performanceService.fetchPerformanceSummary (Phase 14A.2).
export async function fetchSpamRiskReview(websiteId: string): Promise<SpamRiskReview[]> {
  const opportunities = await fetchAuthorityOpportunities(websiteId);
  const risky = opportunities.filter((o) => o.risk === "high" || o.spam_risk_flags.length > 0);

  const reviews: SpamRiskReview[] = risky.map((o) => ({
    opportunity_id: o.id,
    opportunity_title: o.title,
    flags: o.spam_risk_flags,
    risk_level: o.risk,
    recommended_action: o.risk === "high" ? "avoid" : "expert_review",
    explanation: o.why_it_matters,
  }));

  return toAsync(reviews);
}

// Derives from fetchAuthorityOpportunities / fetchAuthorityCampaigns (now
// adapter-wired above), same pattern as fetchSpamRiskReview.
export async function fetchAuthorityOverview(
  websiteId: string,
  websiteUrl: string,
): Promise<AuthorityOverview> {
  const [opportunities, campaigns, latestAudit] = await Promise.all([
    fetchAuthorityOpportunities(websiteId),
    fetchAuthorityCampaigns(websiteId),
    fetchLatestAudit(websiteId),
  ]);

  const highRiskCount = opportunities.filter(
    (o) => o.risk === "high" || o.spam_risk_flags.length > 0,
  ).length;

  const completedReviewCount = opportunities.filter(
    (o) => o.opportunity_type === "review" && o.status === "completed",
  ).length;
  const safeOpportunityCount = opportunities.length - highRiskCount;

  return toAsync({
    website_id: websiteId,
    website_url: websiteUrl,
    authority_score: latestAudit?.authority_score ?? 0,
    trust_signal_summary:
      opportunities.length === 0
        ? "No authority opportunities reviewed yet."
        : `${safeOpportunityCount} safe opportunit${safeOpportunityCount === 1 ? "y" : "ies"} identified, ${completedReviewCount} review request${completedReviewCount === 1 ? "" : "s"} completed.`,
    opportunity_count: opportunities.length,
    campaign_count: campaigns.length,
    high_risk_count: highRiskCount,
    data_source_status: AUTHORITY_DATA_SOURCE_STATUS,
  });
}
