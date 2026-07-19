import type {
  CompetitorContentSummary,
  ContentDraft,
  ContentFormatInput,
  ContentFormatType,
  ContentOpportunity,
  ContentWireframe,
  ContentWorkflowStatus,
  DraftSectionAction,
  KeywordPlan,
  NewCustomContentOpportunityInput,
  SeoUserRole,
  SeoWebsite,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import {
  listContentOpportunities,
  getContentOpportunityById,
  createCustomOpportunity,
  startContentPlan as startContentPlanMock,
  updateContentStatus as updateContentStatusMock,
  addContentFeedback,
  ensureKeywordPlan,
  ensureCompetitorSummaries,
  getWireframe,
  generateWireframe as generateWireframeMock,
  approveWireframe as approveWireframeMock,
  getFormatInput,
  saveFormatInput as saveFormatInputMock,
  getDraft,
  generateDraft as generateDraftMock,
  updateDraftSection as updateDraftSectionMock,
  regenerateDraftSection as regenerateDraftSectionMock,
} from "@/mocks/contentStudioMockData";
import { logRecentActivity } from "@/services/dashboardService";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import { logDataModeWarning, requireSupabaseOrFallback } from "@/services/dataMode";
import { normalizeSupabaseErrorMessage } from "@/services/supabase/supabaseErrors";
import {
  ContentTransitionError,
  addSupabaseDraftFeedback,
  approveSupabaseWireframe,
  createSupabaseCustomContentOpportunity,
  fetchSupabaseCompetitorContentSummary,
  fetchSupabaseContentOpportunities,
  fetchSupabaseDraft,
  fetchSupabaseFormatInput,
  fetchSupabaseKeywordPlan,
  fetchSupabaseWireframe,
  generateSupabaseDraft,
  generateSupabaseWireframe,
  regenerateSupabaseDraftSection,
  saveSupabaseFormatInput,
  startSupabaseContentPlan,
  updateSupabaseContentStatus,
  updateSupabaseDraftSection,
} from "@/services/supabase/seoContentStudioSupabaseService";

function logOpportunityActivity(opportunity: ContentOpportunity, summary: string): void {
  void logRecentActivity({
    workspace_id: opportunity.workspace_id,
    website_id: opportunity.website_id,
    website_url: opportunity.website_url,
    user_id: opportunity.user_id,
    activity_type: "content_workflow_update",
    summary,
  });
}

// Workflow-status changes (via the Stage 3 seo_content_transition RPC) go
// through this instead of the standard runWithServiceAdapter: unlike a
// missing config/session (an infra failure that should gracefully fall
// back), a REAL rejection returned by the RPC (invalid transition for the
// current status, unsupported action, not a member, etc.) must NEVER be
// silently masked by a mock "success" — same rule as approvalService.ts's
// runApprovalWrite(). Only pre-RPC failures (no session, no config) fall
// back to mock; a rejection the RPC actually returned is surfaced as a real
// error instead.
async function runContentWrite<T>(
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
    if (error instanceof ContentTransitionError) {
      throw error;
    }
    logDataModeWarning(
      `${label} Supabase call failed (${normalizeSupabaseErrorMessage(error)}); falling back to mock.`,
    );
    return mock();
  }
}

export async function fetchContentOpportunities(websiteId: string): Promise<ContentOpportunity[]> {
  return runWithServiceAdapter({
    label: "contentStudioService.fetchContentOpportunities",
    mock: () => toAsync(listContentOpportunities(websiteId)),
    supabase: () => fetchSupabaseContentOpportunities(websiteId),
  });
}

// Mechanical direct INSERT (user-provided title/keyword, no AI content) —
// falls back to mock like other creation-style operations (e.g. addWebsite,
// ensureApprovalQueueGenerated), not treated as a workflow-transition write.
export async function createCustomContentOpportunity(
  website: SeoWebsite,
  input: NewCustomContentOpportunityInput,
): Promise<ContentOpportunity> {
  return runWithServiceAdapter({
    label: "contentStudioService.createCustomContentOpportunity",
    mock: () => toAsync(createCustomOpportunity(website, input)),
    supabase: () => createSupabaseCustomContentOpportunity(website, input),
  });
}

export async function startContentPlan(opportunityId: string): Promise<ContentOpportunity | null> {
  return runContentWrite(
    "contentStudioService.startContentPlan",
    async () => {
      const updated = startContentPlanMock(opportunityId);
      if (updated) logOpportunityActivity(updated, `Content plan started: ${updated.title}`);
      return toAsync(updated);
    },
    () => startSupabaseContentPlan(opportunityId),
  );
}

export async function fetchKeywordPlan(opportunityId: string): Promise<KeywordPlan | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.fetchKeywordPlan",
    mock: () => {
      const opportunity = getContentOpportunityById(opportunityId);
      if (!opportunity) return toAsync(null);
      return toAsync(ensureKeywordPlan(opportunity));
    },
    supabase: () => fetchSupabaseKeywordPlan(opportunityId),
  });
}

export async function fetchCompetitorContentSummary(
  opportunityId: string,
  website: SeoWebsite,
): Promise<CompetitorContentSummary[]> {
  return runWithServiceAdapter({
    label: "contentStudioService.fetchCompetitorContentSummary",
    mock: () => {
      const opportunity = getContentOpportunityById(opportunityId);
      if (!opportunity) return toAsync([]);
      return toAsync(ensureCompetitorSummaries(opportunity, website));
    },
    supabase: () => fetchSupabaseCompetitorContentSummary(opportunityId, website),
  });
}

export async function fetchWireframe(opportunityId: string): Promise<ContentWireframe | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.fetchWireframe",
    mock: () => toAsync(getWireframe(opportunityId)),
    supabase: () => fetchSupabaseWireframe(opportunityId),
  });
}

export async function generateWireframe(
  opportunityId: string,
  website: SeoWebsite,
): Promise<ContentWireframe | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.generateWireframe",
    mock: () => {
      const opportunity = getContentOpportunityById(opportunityId);
      if (!opportunity) return toAsync(null);
      return toAsync(generateWireframeMock(opportunity, website));
    },
    supabase: () => generateSupabaseWireframe(opportunityId, website),
  });
}

export async function approveWireframe(opportunityId: string): Promise<ContentWireframe | null> {
  return runContentWrite(
    "contentStudioService.approveWireframe",
    async () => {
      const wireframe = approveWireframeMock(opportunityId);
      const opportunity = getContentOpportunityById(opportunityId);
      if (wireframe && opportunity) {
        logOpportunityActivity(opportunity, `Wireframe approved: ${opportunity.title}`);
      }
      return toAsync(wireframe);
    },
    () => approveSupabaseWireframe(opportunityId),
  );
}

export async function fetchFormatInput(opportunityId: string): Promise<ContentFormatInput | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.fetchFormatInput",
    mock: () => toAsync(getFormatInput(opportunityId)),
    supabase: () => fetchSupabaseFormatInput(opportunityId),
  });
}

export async function saveFormatInput(
  opportunityId: string,
  input: {
    format_type: ContentFormatType;
    reference_url?: string;
    uploaded_file_name?: string;
    custom_instructions?: string;
  },
): Promise<ContentFormatInput | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.saveFormatInput",
    mock: () => {
      const opportunity = getContentOpportunityById(opportunityId);
      if (!opportunity) return toAsync(null);
      return toAsync(saveFormatInputMock(opportunity, input));
    },
    supabase: () => saveSupabaseFormatInput(opportunityId, input),
  });
}

export async function fetchDraft(opportunityId: string): Promise<ContentDraft | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.fetchDraft",
    mock: () => toAsync(getDraft(opportunityId)),
    supabase: () => fetchSupabaseDraft(opportunityId),
  });
}

// Returns null if the wireframe hasn't been approved yet — draft generation
// is blocked until then (both mock and Supabase paths enforce this).
export async function generateDraft(opportunityId: string): Promise<ContentDraft | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.generateDraft",
    mock: () => {
      const opportunity = getContentOpportunityById(opportunityId);
      if (!opportunity) return toAsync(null);
      return toAsync(generateDraftMock(opportunity));
    },
    supabase: () => generateSupabaseDraft(opportunityId),
  });
}

export async function updateDraftSection(
  opportunityId: string,
  sectionId: string,
  action: DraftSectionAction,
  editedContent?: string,
): Promise<ContentDraft | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.updateDraftSection",
    mock: () => toAsync(updateDraftSectionMock(opportunityId, sectionId, action, editedContent)),
    supabase: () => updateSupabaseDraftSection(opportunityId, sectionId, action, editedContent),
  });
}

// Dedicated from updateDraftSection: regenerates only the given section with
// visibly different mock content, tracking a per-section regeneration count.
export async function regenerateDraftSection(
  opportunityId: string,
  sectionId: string,
): Promise<ContentDraft | null> {
  return runWithServiceAdapter({
    label: "contentStudioService.regenerateDraftSection",
    mock: () => toAsync(regenerateDraftSectionMock(opportunityId, sectionId)),
    supabase: () => regenerateSupabaseDraftSection(opportunityId, sectionId),
  });
}

export async function addDraftFeedback(
  opportunityId: string,
  authorRole: SeoUserRole,
  commentText: string,
): Promise<ContentOpportunity | null> {
  return runContentWrite(
    "contentStudioService.addDraftFeedback",
    () =>
      toAsync(
        addContentFeedback(opportunityId, { author_role: authorRole, comment_text: commentText }),
      ),
    () => addSupabaseDraftFeedback(opportunityId, authorRole, commentText),
  );
}

export async function updateContentStatus(
  opportunityId: string,
  status: ContentWorkflowStatus,
): Promise<ContentOpportunity | null> {
  return runContentWrite(
    "contentStudioService.updateContentStatus",
    async () => {
      const updated = updateContentStatusMock(opportunityId, status);
      if (updated && status === "draft_approved") {
        logOpportunityActivity(updated, `Draft approved: ${updated.title}`);
      }
      if (updated && status === "expert_review_requested") {
        logOpportunityActivity(updated, `Sent to expert review: ${updated.title}`);
      }
      return toAsync(updated);
    },
    () => updateSupabaseContentStatus(opportunityId, status),
  );
}
