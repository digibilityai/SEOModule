import type {
  ActionType,
  ApprovalComment,
  ApprovalItem,
  OwnerType,
  SeoIssue,
  SeoRecommendation,
  SeoWebsite,
} from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";
import { isHighRiskIssueCategory } from "@/lib/safetyRules";

const STORAGE_KEY = "approvals";

const [siteA, siteB] = MOCK_WEBSITES_CONTEXT;

const seedApprovalItems: ApprovalItem[] = [
  {
    id: "apr_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T10:05:00.000Z",
    updated_at: "2026-07-01T10:05:00.000Z",
    recommendation_id: "rec_mock_001",
    issue_id: "iss_mock_001",
    title: "Compress and lazy-load homepage hero image",
    page_url: `${siteA.website_url}/`,
    simple_explanation: "Your homepage loads slowly on mobile, which can lose visitors.",
    suggested_change: "Compress hero image and enable lazy loading.",
    action_type: "approval_required",
    impact: "high",
    effort: "medium",
    risk: "low",
    confidence_percentage: 85,
    fix_owner: "developer_needed",
    is_high_risk_category: false,
    status: "needs_review",
    comments: [],
  },
  {
    id: "apr_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T10:05:00.000Z",
    updated_at: "2026-07-03T10:05:00.000Z",
    recommendation_id: "rec_mock_002",
    issue_id: "iss_mock_002",
    title: "Update robots.txt to unblock service pages",
    page_url: `${siteB.website_url}/robots.txt`,
    simple_explanation: "Your robots.txt file is blocking search engines from key pages.",
    suggested_change: "Remove the disallow rule blocking /services so it can be indexed.",
    action_type: "expert_review",
    impact: "high",
    effort: "low",
    risk: "medium",
    confidence_percentage: 87,
    fix_owner: "digibility_expert",
    is_high_risk_category: true,
    status: "expert_review_requested",
    comments: [],
  },
];

export const mockApprovalItems: ApprovalItem[] = loadMockCollection(STORAGE_KEY, seedApprovalItems);

function persist(): void {
  saveMockCollection(STORAGE_KEY, mockApprovalItems);
}

export function listApprovalQueue(websiteId: string): ApprovalItem[] {
  return mockApprovalItems.filter((a) => a.website_id === websiteId);
}

export function getApprovalItemById(id: string): ApprovalItem | null {
  return mockApprovalItems.find((a) => a.id === id) ?? null;
}

export function updateApprovalItem(
  id: string,
  patch: Partial<Pick<ApprovalItem, "status" | "suggested_change">>,
): ApprovalItem | null {
  const index = mockApprovalItems.findIndex((a) => a.id === id);
  if (index === -1) return null;
  const updated: ApprovalItem = {
    ...mockApprovalItems[index],
    ...patch,
    updated_at: new Date().toISOString(),
  };
  mockApprovalItems[index] = updated;
  persist();
  return updated;
}

export function addCommentToApprovalItem(
  id: string,
  comment: Pick<ApprovalComment, "author_role" | "comment_text">,
): ApprovalItem | null {
  const index = mockApprovalItems.findIndex((a) => a.id === id);
  if (index === -1) return null;
  const newComment: ApprovalComment = {
    id: `cmt_mock_${Date.now()}`,
    created_at: new Date().toISOString(),
    ...comment,
  };
  const updated: ApprovalItem = {
    ...mockApprovalItems[index],
    comments: [...mockApprovalItems[index].comments, newComment],
    updated_at: new Date().toISOString(),
  };
  mockApprovalItems[index] = updated;
  persist();
  return updated;
}

// Used only when a recommendation's issue doesn't tell us fix_owner directly
// (standalone on-page recommendations with no source issue).
const FIX_OWNER_BY_ACTION_TYPE: Record<ActionType, OwnerType> = {
  auto_suggest: "system_suggestion",
  approval_required: "developer_needed",
  manual_support: "client_action",
  expert_review: "digibility_expert",
  avoid: "system_suggestion",
};

// Creates approval items for any recommendation that doesn't already have
// one for this website (matched by recommendation_id) — safe to call
// repeatedly, never duplicates.
export function createApprovalItemsFromRecommendations(
  website: SeoWebsite,
  recommendations: SeoRecommendation[],
  issues: SeoIssue[],
): ApprovalItem[] {
  const existingRecIds = new Set(
    mockApprovalItems.filter((a) => a.website_id === website.id).map((a) => a.recommendation_id),
  );
  const toCreate = recommendations.filter((r) => !existingRecIds.has(r.id));

  if (toCreate.length === 0) {
    return listApprovalQueue(website.id);
  }

  const now = new Date().toISOString();
  const issueById = new Map(issues.map((i) => [i.id, i]));

  const created: ApprovalItem[] = toCreate.map((rec) => {
    const issue = rec.issue_id ? issueById.get(rec.issue_id) : undefined;
    return {
      id: `apr_mock_${rec.id}`,
      workspace_id: website.workspace_id,
      website_id: website.id,
      website_url: website.website_url,
      user_id: website.user_id,
      created_by: website.user_id,
      created_at: now,
      updated_at: now,
      recommendation_id: rec.id,
      issue_id: rec.issue_id,
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
      is_high_risk_category: issue ? isHighRiskIssueCategory(issue.category) : false,
      status: rec.status,
      comments: [],
    };
  });

  mockApprovalItems.push(...created);
  persist();
  return listApprovalQueue(website.id);
}
