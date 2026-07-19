import type {
  CompetitorContentSummary,
  ContentDifficulty,
  ContentDraft,
  ContentFeedbackComment,
  ContentFormatInput,
  ContentFormatType,
  ContentOpportunity,
  ContentWireframe,
  ContentWorkflowStatus,
  DraftSection,
  DraftSectionAction,
  DraftSectionStatus,
  FunnelStage,
  KeywordPlan,
  NewCustomContentOpportunityInput,
  SearchIntent,
  SeoUserRole,
  SeoWebsite,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_RPCS, SEO_TABLES } from "@/services/supabase/supabaseTypes";
import { requireAuthenticatedUser, safeList, safeSingle } from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

// =============================================================================
// Phase 13E — Content Studio Supabase service (Stage 3).
//
// Deferred entirely this phase: seo_content_assets + the private
// seo-content-assets Storage bucket. The current UI's FormatInputSection
// only ever stores a filename STRING for a "file_reference" format — it
// never uploads real bytes ("Only the filename is stored for now — file
// contents aren't processed yet", per that component). Wiring real Storage
// would require building an upload flow the UI doesn't have yet, which is
// explicitly out of scope ("do not upload files unless the existing UI
// already supports upload"). See PHASE_13E_CONTENT_STUDIO_WIRING_NOTES.md.
//
// Status model mismatch: the app's ContentWorkflowStatus (12 values) is a
// simplified view over Stage 3's richer 14-value status enum (which also
// tracks internal vs. client review separately). DB_STATUS_TO_APP_STATUS /
// APP_STATUS_TO_TRANSITION_ACTION below are the best-effort mapping in each
// direction — see the comments on those tables for the reasoning.
// =============================================================================

export class ContentTransitionError extends Error {}

// ---------------------------------------------------------------------------
// Status mapping
// ---------------------------------------------------------------------------

// DB (Stage 3) status → app ContentWorkflowStatus, best-effort. Stage 3
// tracks internal vs. client review separately; the app has no such split,
// so both collapse onto the same app status. "_changes_requested" states map
// to "rejected" (closest semantic match — sent back for rework), which is
// also what a "reject" write produces (see APP_STATUS_TO_TRANSITION_ACTION),
// so a reject → re-read round-trips correctly.
const DB_STATUS_TO_APP_STATUS: Record<string, ContentWorkflowStatus> = {
  idea: "idea_suggested",
  plan_ready: "plan_started",
  wireframe_in_progress: "plan_started",
  wireframe_internal_review: "wireframe_ready",
  wireframe_client_review: "wireframe_ready",
  wireframe_changes_requested: "rejected",
  wireframe_approved: "wireframe_approved",
  draft_in_progress: "draft_ready",
  draft_internal_review: "draft_in_review",
  draft_client_review: "draft_in_review",
  draft_changes_requested: "rejected",
  draft_approved: "draft_approved",
  ready_for_manual_publish: "ready_for_publish",
  archived: "completed",
};

function mapDbStatusToAppStatus(dbStatus: string): ContentWorkflowStatus {
  return DB_STATUS_TO_APP_STATUS[dbStatus] ?? "idea_suggested";
}

// App target status (what updateContentStatus's callers request) → Stage 3
// transition action. "expert_review_requested" has no Stage 3 equivalent yet
// — the RPC's own request_expert_review action is gated to client-review
// states and doesn't apply to this manager-driven flow (Expert Support is a
// later stage per the migration's own comment) — so it's intentionally
// absent and surfaced as a clear ContentTransitionError instead of silently
// no-op'ing or being masked by a mock "success".
const APP_STATUS_TO_TRANSITION_ACTION: Partial<Record<ContentWorkflowStatus, string>> = {
  draft_approved: "approve_draft_internal",
  rejected: "request_draft_changes",
  ready_for_publish: "mark_ready_for_manual_publish",
  completed: "archive",
};

// ---------------------------------------------------------------------------
// RPC helpers
// ---------------------------------------------------------------------------

async function callContentTransition(
  opportunityId: string,
  action: string,
  note?: string,
): Promise<string> {
  const { data, error } = await supabase.rpc(SEO_RPCS.contentTransition, {
    p_opportunity_id: opportunityId,
    p_action: action,
    p_note: note ?? null,
  });
  if (error) {
    // Reaching this point means auth already succeeded, so this is the
    // backend's real, authoritative decision (denied action, invalid
    // transition for the current status, opportunity not found, etc.) —
    // never a "not signed in" case. Callers must NOT mask this with mock
    // success (see contentStudioService.ts's runContentWrite()).
    throw new ContentTransitionError(normalizeSupabaseError(error).message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return (row?.new_status as string) ?? "";
}

// Attempts a transition but treats "Invalid transition ... from ..." (Stage
// 3's own message for "already past this step") as a benign no-op. Used to
// tolerantly advance the workflow (e.g. start_wireframe, start_draft,
// submit_draft_internal_review) without failing on a second/idempotent call
// — any OTHER error (permission denial, not found, etc.) still propagates.
async function tryTransition(opportunityId: string, action: string): Promise<void> {
  try {
    await callContentTransition(opportunityId, action);
  } catch (error) {
    if (error instanceof ContentTransitionError && /Invalid transition|Already archived/i.test(error.message)) {
      return;
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Content opportunities
// ---------------------------------------------------------------------------

interface SeoContentOpportunityRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  title: string;
  target_keyword: string;
  search_intent: SearchIntent | null;
  funnel_stage: FunnelStage | null;
  difficulty: ContentDifficulty | null;
  opportunity_score: number;
  reason: string | null;
  is_custom: boolean;
  status: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoContentCommentRow {
  id: string;
  content_opportunity_id: string;
  actor_role_snapshot: string;
  comment_text: string;
  created_at: string;
}

const OPPORTUNITY_COLUMNS =
  "id, workspace_id, website_id, website_url, title, target_keyword, search_intent, funnel_stage, difficulty, opportunity_score, reason, is_custom, status, created_by, created_at, updated_at";

function mapToFeedbackComment(row: SeoContentCommentRow): ContentFeedbackComment {
  return {
    id: row.id,
    author_role: row.actor_role_snapshot as SeoUserRole,
    comment_text: row.comment_text,
    created_at: row.created_at,
  };
}

async function fetchCommentsForOpportunities(ids: string[]): Promise<Map<string, ContentFeedbackComment[]>> {
  if (ids.length === 0) return new Map();
  const rows = await safeList<SeoContentCommentRow>(
    "seoContentStudioSupabaseService.fetchCommentsForOpportunities",
    supabase
      .from(SEO_TABLES.contentComments)
      .select("id, content_opportunity_id, actor_role_snapshot, comment_text, created_at")
      .in("content_opportunity_id", ids)
      .order("created_at", { ascending: true }),
  );
  const byOpp = new Map<string, ContentFeedbackComment[]>();
  for (const row of rows) {
    const list = byOpp.get(row.content_opportunity_id) ?? [];
    list.push(mapToFeedbackComment(row));
    byOpp.set(row.content_opportunity_id, list);
  }
  return byOpp;
}

function mapToContentOpportunity(
  row: SeoContentOpportunityRow,
  comments: ContentFeedbackComment[],
): ContentOpportunity {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    title: row.title,
    target_keyword: row.target_keyword,
    search_intent: row.search_intent ?? "informational",
    funnel_stage: row.funnel_stage ?? "awareness",
    difficulty: row.difficulty ?? "medium",
    opportunity_score: row.opportunity_score,
    reason: row.reason ?? "",
    is_custom: row.is_custom,
    status: mapDbStatusToAppStatus(row.status),
    comments,
  };
}

async function fetchOpportunityRowOrThrow(
  id: string,
  callerLabel: string,
): Promise<SeoContentOpportunityRow> {
  const row = await safeSingle<SeoContentOpportunityRow>(
    callerLabel,
    supabase.from(SEO_TABLES.contentOpportunities).select(OPPORTUNITY_COLUMNS).eq("id", id).maybeSingle(),
  );
  if (!row) {
    throw new Error(`${callerLabel}: content opportunity not found (${id}).`);
  }
  return row;
}

/** Lists content opportunities for a website, with their comments attached. Empty array when none exist. */
export async function fetchSupabaseContentOpportunities(websiteId: string): Promise<ContentOpportunity[]> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.fetchSupabaseContentOpportunities");
  const rows = await safeList<SeoContentOpportunityRow>(
    "seoContentStudioSupabaseService.fetchSupabaseContentOpportunities",
    supabase
      .from(SEO_TABLES.contentOpportunities)
      .select(OPPORTUNITY_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
  const commentsByOpp = await fetchCommentsForOpportunities(rows.map((row) => row.id));
  return rows.map((row) => mapToContentOpportunity(row, commentsByOpp.get(row.id) ?? []));
}

export async function fetchSupabaseContentOpportunityById(id: string): Promise<ContentOpportunity | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.fetchSupabaseContentOpportunityById");
  const row = await safeSingle<SeoContentOpportunityRow>(
    "seoContentStudioSupabaseService.fetchSupabaseContentOpportunityById",
    supabase.from(SEO_TABLES.contentOpportunities).select(OPPORTUNITY_COLUMNS).eq("id", id).maybeSingle(),
  );
  if (!row) return null;
  const commentsByOpp = await fetchCommentsForOpportunities([row.id]);
  return mapToContentOpportunity(row, commentsByOpp.get(row.id) ?? []);
}

/** Direct INSERT (mechanical — user-provided title/keyword, no AI content), matching the manager-write RLS on this table. */
export async function createSupabaseCustomContentOpportunity(
  website: SeoWebsite,
  input: NewCustomContentOpportunityInput,
): Promise<ContentOpportunity> {
  const userId = await requireAuthenticatedUser(
    "seoContentStudioSupabaseService.createSupabaseCustomContentOpportunity",
  );
  const row = await safeSingle<SeoContentOpportunityRow>(
    "seoContentStudioSupabaseService.createSupabaseCustomContentOpportunity",
    supabase
      .from(SEO_TABLES.contentOpportunities)
      .insert({
        workspace_id: website.workspace_id,
        website_id: website.id,
        website_url: website.website_url,
        title: input.title,
        target_keyword: input.target_keyword,
        search_intent: "informational",
        funnel_stage: "awareness",
        difficulty: "medium",
        opportunity_score: 60,
        reason: "Custom title added manually.",
        is_custom: true,
        created_by: userId,
      })
      .select(OPPORTUNITY_COLUMNS)
      .single(),
  );
  if (!row) {
    throw new Error(
      "seoContentStudioSupabaseService.createSupabaseCustomContentOpportunity: insert returned no row.",
    );
  }
  return mapToContentOpportunity(row, []);
}

/** Advances idea → plan_ready via the RPC (never a direct status write). */
export async function startSupabaseContentPlan(opportunityId: string): Promise<ContentOpportunity | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.startSupabaseContentPlan");
  await callContentTransition(opportunityId, "mark_plan_ready");
  return fetchSupabaseContentOpportunityById(opportunityId);
}

/**
 * Applies the app's requested target status via the matching Stage 3 RPC
 * action — never a direct status UPDATE. "draft_approved"/"rejected" both
 * require the opportunity to already be in draft_internal_review; this
 * tolerantly ensures that first (a no-op if already there or past it) so
 * the review buttons work immediately after a draft is generated, matching
 * the mock UI's always-available Approve/Reject buttons.
 */
export async function updateSupabaseContentStatus(
  opportunityId: string,
  status: ContentWorkflowStatus,
): Promise<ContentOpportunity | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.updateSupabaseContentStatus");

  const action = APP_STATUS_TO_TRANSITION_ACTION[status];
  if (!action) {
    throw new ContentTransitionError(
      `Stage 3 has no workflow transition for status "${status}" yet (e.g. Expert Support review is a later stage).`,
    );
  }

  if (action === "approve_draft_internal" || action === "request_draft_changes") {
    await tryTransition(opportunityId, "submit_draft_internal_review");
  }

  await callContentTransition(opportunityId, action);
  return fetchSupabaseContentOpportunityById(opportunityId);
}

/** Adds feedback via the RPC's `comment` action (append-only; logs activity server-side). */
export async function addSupabaseDraftFeedback(
  opportunityId: string,
  _authorRole: SeoUserRole,
  commentText: string,
): Promise<ContentOpportunity | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.addSupabaseDraftFeedback");
  await callContentTransition(opportunityId, "comment", commentText);
  return fetchSupabaseContentOpportunityById(opportunityId);
}

// ---------------------------------------------------------------------------
// Keyword plan
// ---------------------------------------------------------------------------

interface SeoContentKeywordPlanRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  content_opportunity_id: string;
  primary_keyword: string;
  secondary_keywords: string[];
  semantic_keywords: string[];
  question_keywords: string[];
  intent: SearchIntent | null;
  difficulty: ContentDifficulty | null;
  business_relevance: string | null;
  why_it_matters: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const KEYWORD_PLAN_COLUMNS =
  "id, workspace_id, website_id, website_url, content_opportunity_id, primary_keyword, secondary_keywords, semantic_keywords, question_keywords, intent, difficulty, business_relevance, why_it_matters, created_by, created_at, updated_at";

function mapToKeywordPlan(row: SeoContentKeywordPlanRow): KeywordPlan {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    content_opportunity_id: row.content_opportunity_id,
    primary_keyword: row.primary_keyword,
    secondary_keywords: row.secondary_keywords ?? [],
    semantic_keywords: row.semantic_keywords ?? [],
    question_keywords: row.question_keywords ?? [],
    intent: row.intent ?? "informational",
    difficulty: row.difficulty ?? "medium",
    business_relevance: row.business_relevance ?? "",
    why_it_matters: row.why_it_matters ?? "",
  };
}

/**
 * Reads the keyword plan, creating one with simple deterministic template
 * text on first read if missing — mirrors the mock adapter's
 * ensureKeywordPlan (array construction from the opportunity's own
 * target_keyword; no real keyword research/LLM call). Needed so the
 * downstream wireframe/draft workflow stays reachable in Supabase mode,
 * exactly like mock mode (the real UI only renders WireframeSection once a
 * keyword plan exists).
 */
export async function fetchSupabaseKeywordPlan(opportunityId: string): Promise<KeywordPlan | null> {
  const userId = await requireAuthenticatedUser("seoContentStudioSupabaseService.fetchSupabaseKeywordPlan");

  const existing = await safeSingle<SeoContentKeywordPlanRow>(
    "seoContentStudioSupabaseService.fetchSupabaseKeywordPlan",
    supabase
      .from(SEO_TABLES.contentKeywordPlans)
      .select(KEYWORD_PLAN_COLUMNS)
      .eq("content_opportunity_id", opportunityId)
      .maybeSingle(),
  );
  if (existing) return mapToKeywordPlan(existing);

  const opportunity = await fetchOpportunityRowOrThrow(
    opportunityId,
    "seoContentStudioSupabaseService.fetchSupabaseKeywordPlan",
  );
  const created = await safeSingle<SeoContentKeywordPlanRow>(
    "seoContentStudioSupabaseService.fetchSupabaseKeywordPlan (create)",
    supabase
      .from(SEO_TABLES.contentKeywordPlans)
      .insert({
        workspace_id: opportunity.workspace_id,
        website_id: opportunity.website_id,
        website_url: opportunity.website_url,
        content_opportunity_id: opportunityId,
        primary_keyword: opportunity.target_keyword,
        secondary_keywords: [`${opportunity.target_keyword} tips`, `${opportunity.target_keyword} guide`],
        semantic_keywords: [`${opportunity.target_keyword} near me`, `local ${opportunity.target_keyword}`],
        question_keywords: [
          `what is ${opportunity.target_keyword}`,
          `how much does ${opportunity.target_keyword} cost`,
        ],
        intent: opportunity.search_intent ?? "informational",
        difficulty: opportunity.difficulty ?? "medium",
        business_relevance:
          "Matches what your customers are already searching for before they contact you.",
        why_it_matters:
          "Ranking for these terms brings in visitors who are actively looking for what you offer.",
        created_by: userId,
      })
      .select(KEYWORD_PLAN_COLUMNS)
      .single(),
  );
  if (!created) {
    throw new Error("seoContentStudioSupabaseService.fetchSupabaseKeywordPlan: insert returned no row.");
  }
  return mapToKeywordPlan(created);
}

// ---------------------------------------------------------------------------
// Competitor content summaries
// ---------------------------------------------------------------------------

interface SeoContentCompetitorSummaryRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  content_opportunity_id: string;
  competitor_title: string | null;
  competitor_url: string | null;
  what_they_covered: string | null;
  what_they_missed: string | null;
  our_opportunity: string | null;
  content_gap_angle: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const COMPETITOR_SUMMARY_COLUMNS =
  "id, workspace_id, website_id, website_url, content_opportunity_id, competitor_title, competitor_url, what_they_covered, what_they_missed, our_opportunity, content_gap_angle, created_by, created_at, updated_at";

function mapToCompetitorSummary(row: SeoContentCompetitorSummaryRow): CompetitorContentSummary {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    content_opportunity_id: row.content_opportunity_id,
    competitor_title: row.competitor_title ?? "",
    competitor_url: row.competitor_url ?? "",
    what_they_covered: row.what_they_covered ?? "",
    what_they_missed: row.what_they_missed ?? "",
    our_opportunity: row.our_opportunity ?? "",
    content_gap_angle: row.content_gap_angle ?? "",
  };
}

/**
 * Reads competitor summaries, creating two illustrative placeholder rows on
 * first read if none exist — mirrors the mock adapter's
 * ensureCompetitorSummaries. NOT real competitor scraping: the URLs are
 * clearly example.com-style placeholders, identical in spirit to the mock's
 * own content.
 */
export async function fetchSupabaseCompetitorContentSummary(
  opportunityId: string,
  website: SeoWebsite,
): Promise<CompetitorContentSummary[]> {
  const userId = await requireAuthenticatedUser(
    "seoContentStudioSupabaseService.fetchSupabaseCompetitorContentSummary",
  );

  const existing = await safeList<SeoContentCompetitorSummaryRow>(
    "seoContentStudioSupabaseService.fetchSupabaseCompetitorContentSummary",
    supabase
      .from(SEO_TABLES.contentCompetitorSummaries)
      .select(COMPETITOR_SUMMARY_COLUMNS)
      .eq("content_opportunity_id", opportunityId)
      .order("created_at", { ascending: true }),
  );
  if (existing.length > 0) return existing.map(mapToCompetitorSummary);

  const opportunity = await fetchOpportunityRowOrThrow(
    opportunityId,
    "seoContentStudioSupabaseService.fetchSupabaseCompetitorContentSummary",
  );
  const slug = opportunity.target_keyword.trim().toLowerCase().replace(/\s+/g, "-");
  const payload = [
    {
      workspace_id: opportunity.workspace_id,
      website_id: opportunity.website_id,
      website_url: opportunity.website_url,
      content_opportunity_id: opportunityId,
      competitor_title: `${opportunity.title} — Complete Guide`,
      competitor_url: `https://www.example-competitor-one.com/${slug}`,
      what_they_covered: "A basic overview and a generic checklist.",
      what_they_missed: "No local information and no clear next step for the reader.",
      our_opportunity: `Add local detail and a clear call-to-action to contact ${website.business_name}.`,
      content_gap_angle: "Localize the content and make it easier to act on.",
      created_by: userId,
    },
    {
      workspace_id: opportunity.workspace_id,
      website_id: opportunity.website_id,
      website_url: opportunity.website_url,
      content_opportunity_id: opportunityId,
      competitor_title: `${opportunity.title} — FAQ`,
      competitor_url: `https://www.example-competitor-two.com/${slug}-faq`,
      what_they_covered: "Short FAQ answering surface-level questions.",
      what_they_missed: "Doesn't address cost or how soon help is available.",
      our_opportunity: "Answer pricing and response-time questions directly.",
      content_gap_angle: "Lead with the practical questions competitors skip.",
      created_by: userId,
    },
  ];

  const created = await safeList<SeoContentCompetitorSummaryRow>(
    "seoContentStudioSupabaseService.fetchSupabaseCompetitorContentSummary (create)",
    supabase.from(SEO_TABLES.contentCompetitorSummaries).insert(payload).select(COMPETITOR_SUMMARY_COLUMNS),
  );
  return created.map(mapToCompetitorSummary);
}

// ---------------------------------------------------------------------------
// Wireframe
// ---------------------------------------------------------------------------

interface SeoContentWireframeRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  content_opportunity_id: string;
  suggested_h1: string | null;
  intro_angle: string | null;
  cta_suggestion: string | null;
  section_outline: string[];
  faq_section: string[];
  internal_link_suggestions: string[];
  schema_suggestion: string | null;
  is_approved: boolean;
  approved_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const WIREFRAME_COLUMNS =
  "id, workspace_id, website_id, website_url, content_opportunity_id, suggested_h1, intro_angle, cta_suggestion, section_outline, faq_section, internal_link_suggestions, schema_suggestion, is_approved, approved_at, created_by, created_at, updated_at";

function mapToWireframe(row: SeoContentWireframeRow): ContentWireframe {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    content_opportunity_id: row.content_opportunity_id,
    suggested_h1: row.suggested_h1 ?? "",
    intro_angle: row.intro_angle ?? "",
    section_outline: row.section_outline ?? [],
    faq_section: row.faq_section ?? [],
    cta_suggestion: row.cta_suggestion ?? "",
    internal_link_suggestions: row.internal_link_suggestions ?? [],
    schema_suggestion: row.schema_suggestion ?? undefined,
    is_approved: row.is_approved,
    approved_at: row.approved_at ?? undefined,
  };
}

export async function fetchSupabaseWireframe(opportunityId: string): Promise<ContentWireframe | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.fetchSupabaseWireframe");
  const row = await safeSingle<SeoContentWireframeRow>(
    "seoContentStudioSupabaseService.fetchSupabaseWireframe",
    supabase
      .from(SEO_TABLES.contentWireframes)
      .select(WIREFRAME_COLUMNS)
      .eq("content_opportunity_id", opportunityId)
      .maybeSingle(),
  );
  return row ? mapToWireframe(row) : null;
}

/**
 * Creates or refreshes the wireframe's CONTENT with simple deterministic
 * template text — no real LLM call. Writes only the wireframe row; the
 * opportunity is tolerantly advanced to wireframe_in_progress via
 * start_wireframe (benign no-op on a second/"Regenerate" call, since
 * start_wireframe isn't itself re-callable once already in progress).
 */
export async function generateSupabaseWireframe(
  opportunityId: string,
  website: SeoWebsite,
): Promise<ContentWireframe | null> {
  const userId = await requireAuthenticatedUser("seoContentStudioSupabaseService.generateSupabaseWireframe");
  const opportunity = await fetchOpportunityRowOrThrow(
    opportunityId,
    "seoContentStudioSupabaseService.generateSupabaseWireframe",
  );

  const row = await safeSingle<SeoContentWireframeRow>(
    "seoContentStudioSupabaseService.generateSupabaseWireframe",
    supabase
      .from(SEO_TABLES.contentWireframes)
      .upsert(
        {
          workspace_id: opportunity.workspace_id,
          website_id: opportunity.website_id,
          website_url: opportunity.website_url,
          content_opportunity_id: opportunityId,
          suggested_h1: opportunity.title,
          intro_angle:
            "Open by acknowledging the reader's situation, then promise a clear, practical answer.",
          section_outline: [
            "Why this matters",
            "Step-by-step guidance",
            "Common mistakes to avoid",
            "When to call a professional",
          ],
          faq_section: [
            `What is ${opportunity.target_keyword}?`,
            "How much does this typically cost?",
            "How soon can I get help?",
          ],
          cta_suggestion: `Book with ${website.business_name} today.`,
          internal_link_suggestions: [website.website_url, `${website.website_url}/services`],
          schema_suggestion: opportunity.search_intent === "informational" ? "FAQPage schema" : null,
          created_by: userId,
        },
        { onConflict: "content_opportunity_id" },
      )
      .select(WIREFRAME_COLUMNS)
      .single(),
  );

  await tryTransition(opportunityId, "start_wireframe");

  return row ? mapToWireframe(row) : null;
}

/**
 * Approves the wireframe: calls the Stage 3 RPC first (advances the
 * opportunity's workflow status — the authoritative gate), then marks
 * is_approved=true on the wireframe row only if the RPC succeeded. Ordered
 * this way so a wireframe is never marked "approved" without the backend
 * workflow status having genuinely advanced.
 */
export async function approveSupabaseWireframe(opportunityId: string): Promise<ContentWireframe | null> {
  const userId = await requireAuthenticatedUser("seoContentStudioSupabaseService.approveSupabaseWireframe");
  await callContentTransition(opportunityId, "approve_wireframe_internal");

  const row = await safeSingle<SeoContentWireframeRow>(
    "seoContentStudioSupabaseService.approveSupabaseWireframe",
    supabase
      .from(SEO_TABLES.contentWireframes)
      .update({ is_approved: true, approved_at: new Date().toISOString(), approved_by: userId })
      .eq("content_opportunity_id", opportunityId)
      .select(WIREFRAME_COLUMNS)
      .single(),
  );
  return row ? mapToWireframe(row) : null;
}

// ---------------------------------------------------------------------------
// Format input
// ---------------------------------------------------------------------------

interface SeoContentFormatInputRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  content_opportunity_id: string;
  format_type: ContentFormatType;
  reference_url: string | null;
  custom_instructions: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

const FORMAT_INPUT_COLUMNS =
  "id, workspace_id, website_id, website_url, content_opportunity_id, format_type, reference_url, custom_instructions, created_by, created_at, updated_at";

// uploaded_file_name is never populated here — see the file-level comment on
// why asset/Storage wiring is deferred this phase.
function mapToFormatInput(row: SeoContentFormatInputRow): ContentFormatInput {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    content_opportunity_id: row.content_opportunity_id,
    format_type: row.format_type,
    reference_url: row.reference_url ?? undefined,
    uploaded_file_name: undefined,
    custom_instructions: row.custom_instructions ?? undefined,
  };
}

export async function fetchSupabaseFormatInput(opportunityId: string): Promise<ContentFormatInput | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.fetchSupabaseFormatInput");
  const row = await safeSingle<SeoContentFormatInputRow>(
    "seoContentStudioSupabaseService.fetchSupabaseFormatInput",
    supabase
      .from(SEO_TABLES.contentFormatInputs)
      .select(FORMAT_INPUT_COLUMNS)
      .eq("content_opportunity_id", opportunityId)
      .maybeSingle(),
  );
  return row ? mapToFormatInput(row) : null;
}

/**
 * Saves the format/tone settings (a plain structured-data save, not AI
 * content — analogous to businessOnboardingService's saveOnboarding). The
 * `uploaded_file_name` field is intentionally NOT persisted — no safe
 * column exists for it without wiring seo_content_assets/Storage, which is
 * deferred this phase (see file-level comment).
 */
export async function saveSupabaseFormatInput(
  opportunityId: string,
  input: {
    format_type: ContentFormatType;
    reference_url?: string;
    uploaded_file_name?: string;
    custom_instructions?: string;
  },
): Promise<ContentFormatInput | null> {
  const userId = await requireAuthenticatedUser("seoContentStudioSupabaseService.saveSupabaseFormatInput");
  const opportunity = await fetchOpportunityRowOrThrow(
    opportunityId,
    "seoContentStudioSupabaseService.saveSupabaseFormatInput",
  );

  const row = await safeSingle<SeoContentFormatInputRow>(
    "seoContentStudioSupabaseService.saveSupabaseFormatInput",
    supabase
      .from(SEO_TABLES.contentFormatInputs)
      .upsert(
        {
          workspace_id: opportunity.workspace_id,
          website_id: opportunity.website_id,
          website_url: opportunity.website_url,
          content_opportunity_id: opportunityId,
          format_type: input.format_type,
          reference_url: input.reference_url ?? null,
          custom_instructions: input.custom_instructions ?? null,
          created_by: userId,
        },
        { onConflict: "content_opportunity_id" },
      )
      .select(FORMAT_INPUT_COLUMNS)
      .single(),
  );
  return row ? mapToFormatInput(row) : null;
}

// ---------------------------------------------------------------------------
// Draft + sections
// ---------------------------------------------------------------------------

interface SeoContentDraftRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  content_opportunity_id: string;
  title: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoContentDraftSectionRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  draft_id: string;
  content_opportunity_id: string;
  position: number;
  heading: string;
  content: string;
  status: DraftSectionStatus;
  regeneration_count: number;
  created_by: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

const DRAFT_COLUMNS =
  "id, workspace_id, website_id, website_url, content_opportunity_id, title, created_by, created_at, updated_at";
const DRAFT_SECTION_COLUMNS =
  "id, workspace_id, website_id, website_url, draft_id, content_opportunity_id, position, heading, content, status, regeneration_count, created_by, updated_by, created_at, updated_at";

function mapToDraftSection(row: SeoContentDraftSectionRow): DraftSection {
  return {
    id: row.id,
    heading: row.heading,
    content: row.content,
    status: row.status,
    regeneration_count: row.regeneration_count,
    updated_at: row.updated_at,
  };
}

async function fetchSectionsForDraft(draftId: string): Promise<DraftSection[]> {
  const rows = await safeList<SeoContentDraftSectionRow>(
    "seoContentStudioSupabaseService.fetchSectionsForDraft",
    supabase
      .from(SEO_TABLES.contentDraftSections)
      .select(DRAFT_SECTION_COLUMNS)
      .eq("draft_id", draftId)
      .order("position", { ascending: true }),
  );
  return rows.map(mapToDraftSection);
}

function mapToContentDraft(row: SeoContentDraftRow, sections: DraftSection[]): ContentDraft {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    content_opportunity_id: row.content_opportunity_id,
    title: row.title,
    sections,
  };
}

export async function fetchSupabaseDraft(opportunityId: string): Promise<ContentDraft | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.fetchSupabaseDraft");
  const row = await safeSingle<SeoContentDraftRow>(
    "seoContentStudioSupabaseService.fetchSupabaseDraft",
    supabase
      .from(SEO_TABLES.contentDrafts)
      .select(DRAFT_COLUMNS)
      .eq("content_opportunity_id", opportunityId)
      .maybeSingle(),
  );
  if (!row) return null;
  const sections = await fetchSectionsForDraft(row.id);
  return mapToContentDraft(row, sections);
}

/**
 * Creates the draft + its sections with simple deterministic placeholder
 * content — no real LLM call, matching the mock adapter's own "(Mock draft
 * content...)" text. Blocked until the wireframe is approved (same gate as
 * mock). Tolerantly advances the opportunity to draft_in_progress via
 * start_draft.
 */
export async function generateSupabaseDraft(opportunityId: string): Promise<ContentDraft | null> {
  const userId = await requireAuthenticatedUser("seoContentStudioSupabaseService.generateSupabaseDraft");

  const wireframe = await fetchSupabaseWireframe(opportunityId);
  if (!wireframe || !wireframe.is_approved) {
    return null;
  }
  const opportunity = await fetchOpportunityRowOrThrow(
    opportunityId,
    "seoContentStudioSupabaseService.generateSupabaseDraft",
  );

  await tryTransition(opportunityId, "start_draft");

  const existingDraft = await safeSingle<SeoContentDraftRow>(
    "seoContentStudioSupabaseService.generateSupabaseDraft (lookup)",
    supabase
      .from(SEO_TABLES.contentDrafts)
      .select(DRAFT_COLUMNS)
      .eq("content_opportunity_id", opportunityId)
      .maybeSingle(),
  );

  const draftRow =
    existingDraft ??
    (await safeSingle<SeoContentDraftRow>(
      "seoContentStudioSupabaseService.generateSupabaseDraft (create draft)",
      supabase
        .from(SEO_TABLES.contentDrafts)
        .insert({
          workspace_id: opportunity.workspace_id,
          website_id: opportunity.website_id,
          website_url: opportunity.website_url,
          content_opportunity_id: opportunityId,
          title: wireframe.suggested_h1,
          created_by: userId,
        })
        .select(DRAFT_COLUMNS)
        .single(),
    ));
  if (!draftRow) {
    throw new Error(
      "seoContentStudioSupabaseService.generateSupabaseDraft: could not create the draft row.",
    );
  }

  // Only seed sections the first time — regenerating individual sections is
  // a separate, dedicated action (regenerateSupabaseDraftSection).
  const existingSections = await fetchSectionsForDraft(draftRow.id);
  if (existingSections.length === 0) {
    const sectionPayload = wireframe.section_outline.map((heading, index) => ({
      workspace_id: opportunity.workspace_id,
      website_id: opportunity.website_id,
      website_url: opportunity.website_url,
      draft_id: draftRow.id,
      content_opportunity_id: opportunityId,
      position: index,
      heading,
      content: `This section will cover: ${heading.toLowerCase()}. (Mock draft content for local testing — real AI generation will replace this later.)`,
      created_by: userId,
    }));
    sectionPayload.push({
      workspace_id: opportunity.workspace_id,
      website_id: opportunity.website_id,
      website_url: opportunity.website_url,
      draft_id: draftRow.id,
      content_opportunity_id: opportunityId,
      position: wireframe.section_outline.length,
      heading: "FAQ",
      content: wireframe.faq_section
        .map((q) => `Q: ${q}\nA: (Mock answer for local testing.)`)
        .join("\n\n"),
      created_by: userId,
    });

    const { error } = await supabase.from(SEO_TABLES.contentDraftSections).insert(sectionPayload);
    if (error) {
      throw new Error(
        `seoContentStudioSupabaseService.generateSupabaseDraft: ${normalizeSupabaseError(error).message}`,
      );
    }
  }

  const sections = await fetchSectionsForDraft(draftRow.id);
  return mapToContentDraft(draftRow, sections);
}

/** Direct per-section UPDATE (approve/reject/edit) — not itself an opportunity workflow transition. */
export async function updateSupabaseDraftSection(
  opportunityId: string,
  sectionId: string,
  action: DraftSectionAction,
  editedContent?: string,
): Promise<ContentDraft | null> {
  await requireAuthenticatedUser("seoContentStudioSupabaseService.updateSupabaseDraftSection");

  const patch =
    action === "approve"
      ? { status: "approved" as const }
      : action === "reject"
        ? { status: "rejected" as const }
        : { status: "edited" as const, content: editedContent };

  const { error } = await supabase.from(SEO_TABLES.contentDraftSections).update(patch).eq("id", sectionId);
  if (error) {
    throw new Error(
      `seoContentStudioSupabaseService.updateSupabaseDraftSection: ${normalizeSupabaseError(error).message}`,
    );
  }

  return fetchSupabaseDraft(opportunityId);
}

// A small pool of visibly distinct deterministic rewrites (matches the mock
// adapter's own REGENERATION_VARIANTS) — no real LLM call.
const REGENERATION_VARIANTS: ((heading: string) => string)[] = [
  (heading) =>
    `Here's a fresh take on ${heading.toLowerCase()}: lead with the key point your reader needs, then back it up with a concrete example.`,
  (heading) =>
    `Updated angle for ${heading.toLowerCase()}: open with the most common question on this topic, then answer it step by step.`,
  (heading) =>
    `Revised draft for ${heading.toLowerCase()}: start with a quick reassurance, then give 2-3 practical tips the reader can act on today.`,
  (heading) =>
    `Another version of ${heading.toLowerCase()}: focus on what makes your business different, backed by a short real-world scenario.`,
];

/**
 * Regenerates one section with deterministic template text (no real LLM
 * call) and appends a row to seo_content_section_revisions — Stage 3's
 * append-only regeneration trail (INSERT-only policy; no update/delete).
 */
export async function regenerateSupabaseDraftSection(
  opportunityId: string,
  sectionId: string,
): Promise<ContentDraft | null> {
  const userId = await requireAuthenticatedUser(
    "seoContentStudioSupabaseService.regenerateSupabaseDraftSection",
  );

  const section = await safeSingle<SeoContentDraftSectionRow>(
    "seoContentStudioSupabaseService.regenerateSupabaseDraftSection (lookup)",
    supabase.from(SEO_TABLES.contentDraftSections).select(DRAFT_SECTION_COLUMNS).eq("id", sectionId).maybeSingle(),
  );
  if (!section) return null;

  const nextCount = (section.regeneration_count ?? 0) + 1;
  const variant = REGENERATION_VARIANTS[(nextCount - 1) % REGENERATION_VARIANTS.length];
  const newContent = `${variant(section.heading)} (Mock regenerated content #${nextCount} — real AI generation will come later.)`;

  const { error: updateError } = await supabase
    .from(SEO_TABLES.contentDraftSections)
    .update({
      content: newContent,
      status: "generated",
      regeneration_count: nextCount,
      updated_by: userId,
    })
    .eq("id", sectionId);
  if (updateError) {
    throw new Error(
      `seoContentStudioSupabaseService.regenerateSupabaseDraftSection: ${normalizeSupabaseError(updateError).message}`,
    );
  }

  const { error: revisionError } = await supabase.from(SEO_TABLES.contentSectionRevisions).insert({
    workspace_id: section.workspace_id,
    website_id: section.website_id,
    website_url: section.website_url,
    draft_section_id: sectionId,
    content_opportunity_id: opportunityId,
    revision_number: nextCount,
    content: newContent,
    reason: "Regenerated via manager action (dev/test content — no real AI generation yet).",
    created_by: userId,
  });
  if (revisionError) {
    throw new Error(
      `seoContentStudioSupabaseService.regenerateSupabaseDraftSection: ${normalizeSupabaseError(revisionError).message}`,
    );
  }

  return fetchSupabaseDraft(opportunityId);
}
