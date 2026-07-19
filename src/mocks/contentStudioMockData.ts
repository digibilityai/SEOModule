import type {
  CompetitorContentSummary,
  ContentDraft,
  ContentFeedbackComment,
  ContentFormatInput,
  ContentFormatType,
  ContentOpportunity,
  ContentWireframe,
  ContentWorkflowStatus,
  DraftSection,
  DraftSectionAction,
  KeywordPlan,
  NewCustomContentOpportunityInput,
  SeoWebsite,
} from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const OPPORTUNITIES_KEY = "content_opportunities";
const KEYWORD_PLANS_KEY = "content_keyword_plans";
const COMPETITOR_SUMMARIES_KEY = "content_competitor_summaries";
const WIREFRAMES_KEY = "content_wireframes";
const FORMAT_INPUTS_KEY = "content_format_inputs";
const DRAFTS_KEY = "content_drafts";

const [siteA, siteB] = MOCK_WEBSITES_CONTEXT;

const seedOpportunities: ContentOpportunity[] = [
  {
    id: "cop_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-02T09:00:00.000Z",
    updated_at: "2026-07-02T09:00:00.000Z",
    title: "Emergency Plumbing Checklist for Homeowners",
    target_keyword: "emergency plumber checklist",
    search_intent: "informational",
    funnel_stage: "awareness",
    difficulty: "low",
    opportunity_score: 78,
    reason:
      "Low competition, matches a common homeowner search, and fits your emergency service offering.",
    is_custom: false,
    status: "idea_suggested",
    comments: [],
  },
  {
    id: "cop_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-02T09:05:00.000Z",
    updated_at: "2026-07-02T09:05:00.000Z",
    title: "How Much Does Emergency Plumbing Cost in Austin?",
    target_keyword: "emergency plumbing cost austin",
    search_intent: "commercial",
    funnel_stage: "consideration",
    difficulty: "medium",
    opportunity_score: 71,
    reason: "Readers researching cost are close to booking — ranking here can drive direct calls.",
    is_custom: false,
    status: "idea_suggested",
    comments: [],
  },
  {
    id: "cop_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-02T09:10:00.000Z",
    updated_at: "2026-07-02T09:10:00.000Z",
    title: "Book a Same-Day Plumber in Austin",
    target_keyword: "same day plumber austin",
    search_intent: "transactional",
    funnel_stage: "conversion",
    difficulty: "medium",
    opportunity_score: 66,
    reason: "Directly targets ready-to-book searchers already in your service area.",
    is_custom: false,
    status: "idea_suggested",
    comments: [],
  },
  {
    id: "cop_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    title: "What to Expect at Your First Dental Checkup",
    target_keyword: "first dental checkup what to expect",
    search_intent: "informational",
    funnel_stage: "awareness",
    difficulty: "low",
    opportunity_score: 74,
    reason: "Answers a common patient question and builds trust before booking.",
    is_custom: false,
    status: "idea_suggested",
    comments: [],
  },
];

export const mockContentOpportunities: ContentOpportunity[] = loadMockCollection(
  OPPORTUNITIES_KEY,
  seedOpportunities,
);
export const mockKeywordPlans: KeywordPlan[] = loadMockCollection(KEYWORD_PLANS_KEY, []);
export const mockCompetitorSummaries: CompetitorContentSummary[] = loadMockCollection(
  COMPETITOR_SUMMARIES_KEY,
  [],
);
export const mockWireframes: ContentWireframe[] = loadMockCollection(WIREFRAMES_KEY, []);
export const mockFormatInputs: ContentFormatInput[] = loadMockCollection(FORMAT_INPUTS_KEY, []);
export const mockDrafts: ContentDraft[] = loadMockCollection(DRAFTS_KEY, []);

const persistOpportunities = () => saveMockCollection(OPPORTUNITIES_KEY, mockContentOpportunities);
const persistKeywordPlans = () => saveMockCollection(KEYWORD_PLANS_KEY, mockKeywordPlans);
const persistCompetitorSummaries = () =>
  saveMockCollection(COMPETITOR_SUMMARIES_KEY, mockCompetitorSummaries);
const persistWireframes = () => saveMockCollection(WIREFRAMES_KEY, mockWireframes);
const persistFormatInputs = () => saveMockCollection(FORMAT_INPUTS_KEY, mockFormatInputs);
const persistDrafts = () => saveMockCollection(DRAFTS_KEY, mockDrafts);

// --- Content opportunities -------------------------------------------------

export function listContentOpportunities(websiteId: string): ContentOpportunity[] {
  return mockContentOpportunities.filter((o) => o.website_id === websiteId);
}

export function getContentOpportunityById(id: string): ContentOpportunity | null {
  return mockContentOpportunities.find((o) => o.id === id) ?? null;
}

export function createCustomOpportunity(
  website: SeoWebsite,
  input: NewCustomContentOpportunityInput,
): ContentOpportunity {
  const now = new Date().toISOString();
  const opportunity: ContentOpportunity = {
    id: `cop_mock_custom_${Date.now()}`,
    workspace_id: website.workspace_id,
    website_id: website.id,
    website_url: website.website_url,
    user_id: website.user_id,
    created_by: website.user_id,
    created_at: now,
    updated_at: now,
    title: input.title,
    target_keyword: input.target_keyword,
    search_intent: "informational",
    funnel_stage: "awareness",
    difficulty: "medium",
    opportunity_score: 60,
    reason: "Custom title added manually.",
    is_custom: true,
    status: "idea_suggested",
    comments: [],
  };
  mockContentOpportunities.push(opportunity);
  persistOpportunities();
  return opportunity;
}

function patchOpportunity(
  id: string,
  patch: Partial<ContentOpportunity>,
): ContentOpportunity | null {
  const index = mockContentOpportunities.findIndex((o) => o.id === id);
  if (index === -1) return null;
  const updated = { ...mockContentOpportunities[index], ...patch, updated_at: new Date().toISOString() };
  mockContentOpportunities[index] = updated;
  persistOpportunities();
  return updated;
}

const STATUS_ORDER: ContentWorkflowStatus[] = [
  "idea_suggested",
  "plan_started",
  "keyword_plan_ready",
  "wireframe_ready",
  "wireframe_approved",
  "draft_ready",
  "draft_in_review",
  "draft_approved",
  "expert_review_requested",
  "ready_for_publish",
  "completed",
];

function advanceStatus(current: ContentWorkflowStatus, next: ContentWorkflowStatus): ContentWorkflowStatus {
  if (current === "rejected") return current;
  const currentIndex = STATUS_ORDER.indexOf(current);
  const nextIndex = STATUS_ORDER.indexOf(next);
  if (nextIndex === -1) return next;
  return nextIndex > currentIndex ? next : current;
}

export function startContentPlan(id: string): ContentOpportunity | null {
  const opportunity = getContentOpportunityById(id);
  if (!opportunity) return null;
  return patchOpportunity(id, { status: advanceStatus(opportunity.status, "plan_started") });
}

export function updateContentStatus(
  id: string,
  status: ContentWorkflowStatus,
): ContentOpportunity | null {
  return patchOpportunity(id, { status });
}

export function addContentFeedback(
  id: string,
  comment: Pick<ContentFeedbackComment, "author_role" | "comment_text">,
): ContentOpportunity | null {
  const opportunity = getContentOpportunityById(id);
  if (!opportunity) return null;
  const newComment: ContentFeedbackComment = {
    id: `cmt_mock_${Date.now()}`,
    created_at: new Date().toISOString(),
    ...comment,
  };
  return patchOpportunity(id, { comments: [...opportunity.comments, newComment] });
}

// --- Keyword plan -----------------------------------------------------------

export function getKeywordPlan(opportunityId: string): KeywordPlan | null {
  return mockKeywordPlans.find((k) => k.content_opportunity_id === opportunityId) ?? null;
}

export function ensureKeywordPlan(opportunity: ContentOpportunity): KeywordPlan {
  const existing = getKeywordPlan(opportunity.id);
  if (existing) return existing;

  const now = new Date().toISOString();
  const plan: KeywordPlan = {
    id: `kwp_mock_${opportunity.id}`,
    workspace_id: opportunity.workspace_id,
    website_id: opportunity.website_id,
    website_url: opportunity.website_url,
    user_id: opportunity.user_id,
    created_by: opportunity.user_id,
    created_at: now,
    updated_at: now,
    content_opportunity_id: opportunity.id,
    primary_keyword: opportunity.target_keyword,
    secondary_keywords: [`${opportunity.target_keyword} tips`, `${opportunity.target_keyword} guide`],
    semantic_keywords: [`${opportunity.target_keyword} near me`, `local ${opportunity.target_keyword}`],
    question_keywords: [
      `what is ${opportunity.target_keyword}`,
      `how much does ${opportunity.target_keyword} cost`,
    ],
    intent: opportunity.search_intent,
    difficulty: opportunity.difficulty,
    business_relevance: "Matches what your customers are already searching for before they contact you.",
    why_it_matters: "Ranking for these terms brings in visitors who are actively looking for what you offer.",
  };
  mockKeywordPlans.push(plan);
  persistKeywordPlans();
  patchOpportunity(opportunity.id, {
    status: advanceStatus(opportunity.status, "keyword_plan_ready"),
  });
  return plan;
}

// --- Competitor content summary ---------------------------------------------

export function listCompetitorSummaries(opportunityId: string): CompetitorContentSummary[] {
  return mockCompetitorSummaries.filter((c) => c.content_opportunity_id === opportunityId);
}

export function ensureCompetitorSummaries(
  opportunity: ContentOpportunity,
  website: SeoWebsite,
): CompetitorContentSummary[] {
  const existing = listCompetitorSummaries(opportunity.id);
  if (existing.length > 0) return existing;

  const now = new Date().toISOString();
  const slug = opportunity.target_keyword.trim().toLowerCase().replace(/\s+/g, "-");
  const created: CompetitorContentSummary[] = [
    {
      id: `cci_mock_${opportunity.id}_1`,
      workspace_id: opportunity.workspace_id,
      website_id: opportunity.website_id,
      website_url: opportunity.website_url,
      user_id: opportunity.user_id,
      created_by: opportunity.user_id,
      created_at: now,
      updated_at: now,
      content_opportunity_id: opportunity.id,
      competitor_title: `${opportunity.title} — Complete Guide`,
      competitor_url: `https://www.example-competitor-one.com/${slug}`,
      what_they_covered: "A basic overview and a generic checklist.",
      what_they_missed: "No local information and no clear next step for the reader.",
      our_opportunity: `Add local detail and a clear call-to-action to contact ${website.business_name}.`,
      content_gap_angle: "Localize the content and make it easier to act on.",
    },
    {
      id: `cci_mock_${opportunity.id}_2`,
      workspace_id: opportunity.workspace_id,
      website_id: opportunity.website_id,
      website_url: opportunity.website_url,
      user_id: opportunity.user_id,
      created_by: opportunity.user_id,
      created_at: now,
      updated_at: now,
      content_opportunity_id: opportunity.id,
      competitor_title: `${opportunity.title} — FAQ`,
      competitor_url: `https://www.example-competitor-two.com/${slug}-faq`,
      what_they_covered: "Short FAQ answering surface-level questions.",
      what_they_missed: "Doesn't address cost or how soon help is available.",
      our_opportunity: "Answer pricing and response-time questions directly.",
      content_gap_angle: "Lead with the practical questions competitors skip.",
    },
  ];
  mockCompetitorSummaries.push(...created);
  persistCompetitorSummaries();
  return created;
}

// --- Wireframe ---------------------------------------------------------------

export function getWireframe(opportunityId: string): ContentWireframe | null {
  return mockWireframes.find((w) => w.content_opportunity_id === opportunityId) ?? null;
}

export function generateWireframe(opportunity: ContentOpportunity, website: SeoWebsite): ContentWireframe {
  const now = new Date().toISOString();
  const existingIndex = mockWireframes.findIndex((w) => w.content_opportunity_id === opportunity.id);

  const wireframe: ContentWireframe = {
    id: existingIndex >= 0 ? mockWireframes[existingIndex].id : `wfr_mock_${opportunity.id}`,
    workspace_id: opportunity.workspace_id,
    website_id: opportunity.website_id,
    website_url: opportunity.website_url,
    user_id: opportunity.user_id,
    created_by: opportunity.user_id,
    created_at: existingIndex >= 0 ? mockWireframes[existingIndex].created_at : now,
    updated_at: now,
    content_opportunity_id: opportunity.id,
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
    schema_suggestion: opportunity.search_intent === "informational" ? "FAQPage schema" : undefined,
    is_approved: false,
  };

  if (existingIndex >= 0) {
    mockWireframes[existingIndex] = wireframe;
  } else {
    mockWireframes.push(wireframe);
  }
  persistWireframes();
  patchOpportunity(opportunity.id, { status: advanceStatus(opportunity.status, "wireframe_ready") });
  return wireframe;
}

export function approveWireframe(opportunityId: string): ContentWireframe | null {
  const index = mockWireframes.findIndex((w) => w.content_opportunity_id === opportunityId);
  if (index === -1) return null;
  const updated = {
    ...mockWireframes[index],
    is_approved: true,
    approved_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  mockWireframes[index] = updated;
  persistWireframes();

  const opportunity = getContentOpportunityById(opportunityId);
  if (opportunity) {
    patchOpportunity(opportunityId, {
      status: advanceStatus(opportunity.status, "wireframe_approved"),
    });
  }
  return updated;
}

// --- Format input -------------------------------------------------------------

export function getFormatInput(opportunityId: string): ContentFormatInput | null {
  return mockFormatInputs.find((f) => f.content_opportunity_id === opportunityId) ?? null;
}

export function saveFormatInput(
  opportunity: ContentOpportunity,
  input: {
    format_type: ContentFormatType;
    reference_url?: string;
    uploaded_file_name?: string;
    custom_instructions?: string;
  },
): ContentFormatInput {
  const now = new Date().toISOString();
  const existingIndex = mockFormatInputs.findIndex(
    (f) => f.content_opportunity_id === opportunity.id,
  );

  const formatInput: ContentFormatInput = {
    id: existingIndex >= 0 ? mockFormatInputs[existingIndex].id : `fmt_mock_${opportunity.id}`,
    workspace_id: opportunity.workspace_id,
    website_id: opportunity.website_id,
    website_url: opportunity.website_url,
    user_id: opportunity.user_id,
    created_by: opportunity.user_id,
    created_at: existingIndex >= 0 ? mockFormatInputs[existingIndex].created_at : now,
    updated_at: now,
    content_opportunity_id: opportunity.id,
    ...input,
  };

  if (existingIndex >= 0) {
    mockFormatInputs[existingIndex] = formatInput;
  } else {
    mockFormatInputs.push(formatInput);
  }
  persistFormatInputs();
  return formatInput;
}

// --- Draft ----------------------------------------------------------------------

export function getDraft(opportunityId: string): ContentDraft | null {
  return mockDrafts.find((d) => d.content_opportunity_id === opportunityId) ?? null;
}

export function generateDraft(opportunity: ContentOpportunity): ContentDraft | null {
  const wireframe = getWireframe(opportunity.id);
  if (!wireframe || !wireframe.is_approved) {
    // Draft generation is blocked until the wireframe is approved.
    return null;
  }

  const now = new Date().toISOString();
  const sections: DraftSection[] = wireframe.section_outline.map((heading, index) => ({
    id: `sec_mock_${opportunity.id}_${index + 1}`,
    heading,
    content: `This section will cover: ${heading.toLowerCase()}. (Mock draft content for local testing — real AI generation will replace this later.)`,
    status: "generated",
    regeneration_count: 0,
    updated_at: now,
  }));
  sections.push({
    id: `sec_mock_${opportunity.id}_faq`,
    heading: "FAQ",
    content: wireframe.faq_section.map((q) => `Q: ${q}\nA: (Mock answer for local testing.)`).join("\n\n"),
    status: "generated",
    regeneration_count: 0,
    updated_at: now,
  });

  const existingIndex = mockDrafts.findIndex((d) => d.content_opportunity_id === opportunity.id);
  const draft: ContentDraft = {
    id: existingIndex >= 0 ? mockDrafts[existingIndex].id : `drf_mock_${opportunity.id}`,
    workspace_id: opportunity.workspace_id,
    website_id: opportunity.website_id,
    website_url: opportunity.website_url,
    user_id: opportunity.user_id,
    created_by: opportunity.user_id,
    created_at: existingIndex >= 0 ? mockDrafts[existingIndex].created_at : now,
    updated_at: now,
    content_opportunity_id: opportunity.id,
    title: wireframe.suggested_h1,
    sections,
  };

  if (existingIndex >= 0) {
    mockDrafts[existingIndex] = draft;
  } else {
    mockDrafts.push(draft);
  }
  persistDrafts();
  patchOpportunity(opportunity.id, { status: advanceStatus(opportunity.status, "draft_ready") });
  return draft;
}

export function updateDraftSection(
  opportunityId: string,
  sectionId: string,
  action: DraftSectionAction,
  editedContent?: string,
): ContentDraft | null {
  const draftIndex = mockDrafts.findIndex((d) => d.content_opportunity_id === opportunityId);
  if (draftIndex === -1) return null;

  const now = new Date().toISOString();
  const draft = mockDrafts[draftIndex];
  const sections = draft.sections.map((section) => {
    if (section.id !== sectionId) return section;
    if (action === "approve") return { ...section, status: "approved" as const, updated_at: now };
    if (action === "reject") return { ...section, status: "rejected" as const, updated_at: now };
    // edit
    return {
      ...section,
      content: editedContent ?? section.content,
      status: "edited" as const,
      updated_at: now,
    };
  });

  const updatedDraft = { ...draft, sections, updated_at: now };
  mockDrafts[draftIndex] = updatedDraft;
  persistDrafts();

  const opportunity = getContentOpportunityById(opportunityId);
  if (opportunity && opportunity.status === "draft_ready") {
    patchOpportunity(opportunityId, { status: "draft_in_review" });
  }

  return updatedDraft;
}

// A small pool of visibly distinct mock rewrites so regenerating the same
// section repeatedly produces content that is obviously different each
// time, not just the previous text with a timestamp appended.
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

export function regenerateDraftSection(
  opportunityId: string,
  sectionId: string,
): ContentDraft | null {
  const draftIndex = mockDrafts.findIndex((d) => d.content_opportunity_id === opportunityId);
  if (draftIndex === -1) return null;

  const now = new Date().toISOString();
  const draft = mockDrafts[draftIndex];
  const sections = draft.sections.map((section) => {
    if (section.id !== sectionId) return section;
    // Defensive: sections persisted before regeneration_count existed on
    // DraftSection would otherwise make this NaN and crash below.
    const nextCount = (section.regeneration_count ?? 0) + 1;
    const variant = REGENERATION_VARIANTS[(nextCount - 1) % REGENERATION_VARIANTS.length];
    return {
      ...section,
      content: `${variant(section.heading)} (Mock regenerated content #${nextCount} — real AI generation will come later.)`,
      status: "generated" as const,
      regeneration_count: nextCount,
      updated_at: now,
    };
  });

  const updatedDraft = { ...draft, sections, updated_at: now };
  mockDrafts[draftIndex] = updatedDraft;
  persistDrafts();

  const opportunity = getContentOpportunityById(opportunityId);
  if (opportunity && opportunity.status === "draft_ready") {
    patchOpportunity(opportunityId, { status: "draft_in_review" });
  }

  return updatedDraft;
}
