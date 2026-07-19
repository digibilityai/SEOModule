import type {
  ExpertSupportRequest,
  NewSupportRequestInput,
  SeoUserRole,
  SeoWebsite,
  SupportActivityEntry,
  SupportActivityType,
  SupportComment,
  SupportStatus,
} from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const REQUESTS_KEY = "support_requests";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has seeded support requests — siteB intentionally has none so
// the "no support requests yet" empty state has something to demonstrate.
const seedSupportRequests: ExpertSupportRequest[] = [
  {
    id: "sup_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-06T10:00:00.000Z",
    updated_at: "2026-07-06T10:30:00.000Z",
    request_type: "technical_seo_fix",
    title: "Help removing a noindex tag safely",
    description:
      "One of our service pages may have a leftover noindex tag from staging. We'd like an expert to confirm it's safe to remove before we touch it.",
    related_module: "audit",
    related_item_url: `${siteA.website_url}/services`,
    priority: "high",
    urgency: "urgent",
    preferred_support_mode: "expert_review",
    notes: "Please confirm before we make any live change.",
    status: "in_review",
    assignee_placeholder: "Awaiting expert assignment",
    comments: [
      {
        id: "cmt_mock_001",
        author_role: "owner",
        comment_text: "Flagging this as urgent — this page normally gets steady traffic.",
        created_at: "2026-07-06T10:05:00.000Z",
      },
    ],
    activity: [
      {
        id: "act_mock_001",
        activity_type: "created",
        summary: "Request submitted.",
        created_at: "2026-07-06T10:00:00.000Z",
      },
      {
        id: "act_mock_002",
        activity_type: "status_changed",
        summary: "Status changed to In review.",
        created_at: "2026-07-06T10:30:00.000Z",
      },
    ],
  },
  {
    id: "sup_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-06T11:00:00.000Z",
    updated_at: "2026-07-06T11:00:00.000Z",
    request_type: "content_review",
    title: "Review new blog draft before publishing",
    description: "Would like a second look at tone and accuracy before this goes live.",
    related_module: "content_studio",
    priority: "medium",
    urgency: "normal",
    preferred_support_mode: "expert_review",
    status: "waiting_for_client",
    assignee_placeholder: "Awaiting expert assignment",
    comments: [],
    activity: [
      {
        id: "act_mock_003",
        activity_type: "created",
        summary: "Request submitted.",
        created_at: "2026-07-06T11:00:00.000Z",
      },
      {
        id: "act_mock_004",
        activity_type: "status_changed",
        summary: "Waiting on additional info from client.",
        created_at: "2026-07-06T11:00:00.000Z",
      },
    ],
  },
  {
    id: "sup_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-06T11:30:00.000Z",
    updated_at: "2026-07-06T11:45:00.000Z",
    request_type: "developer_support",
    title: "Fix robots.txt disallow rule",
    description: "Need a developer to safely remove the disallow rule blocking /services after approval.",
    related_module: "audit",
    related_item_url: `${siteA.website_url}/robots.txt`,
    priority: "high",
    urgency: "urgent",
    preferred_support_mode: "developer_needed",
    status: "assigned",
    assignee_placeholder: "Assigned to Digibility developer",
    comments: [],
    activity: [
      {
        id: "act_mock_005",
        activity_type: "created",
        summary: "Request submitted.",
        created_at: "2026-07-06T11:30:00.000Z",
      },
      {
        id: "act_mock_006",
        activity_type: "status_changed",
        summary: "Assigned to a developer.",
        created_at: "2026-07-06T11:45:00.000Z",
      },
    ],
  },
  {
    id: "sup_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T09:00:00.000Z",
    updated_at: "2026-07-02T09:00:00.000Z",
    request_type: "technical_seo_fix",
    title: "Homepage speed fix rollout",
    description: "Compressed hero image and enabled lazy loading per the audit recommendation.",
    related_module: "audit",
    related_item_url: `${siteA.website_url}/`,
    priority: "high",
    urgency: "normal",
    preferred_support_mode: "developer_needed",
    status: "completed",
    assignee_placeholder: "Completed by Digibility developer",
    comments: [],
    activity: [
      {
        id: "act_mock_007",
        activity_type: "created",
        summary: "Request submitted.",
        created_at: "2026-07-01T09:00:00.000Z",
      },
      {
        id: "act_mock_008",
        activity_type: "completed",
        summary: "Marked completed.",
        created_at: "2026-07-02T09:00:00.000Z",
      },
    ],
  },
];

// Guards against stale localStorage from before the Phase 10 schema rewrite
// (old shape had no `activity`/`comments` arrays).
export const mockSupportRequests: ExpertSupportRequest[] = loadMockCollection(
  REQUESTS_KEY,
  seedSupportRequests,
  (item) => Array.isArray(item.activity) && Array.isArray(item.comments),
);

function persist(): void {
  saveMockCollection(REQUESTS_KEY, mockSupportRequests);
}

export function listSupportRequests(websiteId: string): ExpertSupportRequest[] {
  return mockSupportRequests.filter((s) => s.website_id === websiteId);
}

export function getSupportRequestById(id: string): ExpertSupportRequest | null {
  return mockSupportRequests.find((s) => s.id === id) ?? null;
}

function activityEntry(type: SupportActivityType, summary: string): SupportActivityEntry {
  return { id: `act_mock_${Date.now()}`, activity_type: type, summary, created_at: new Date().toISOString() };
}

export function createSupportRequest(
  website: SeoWebsite,
  input: NewSupportRequestInput,
): ExpertSupportRequest {
  const now = new Date().toISOString();
  const request: ExpertSupportRequest = {
    id: `sup_mock_${Date.now()}`,
    workspace_id: website.workspace_id,
    website_id: website.id,
    website_url: website.website_url,
    user_id: website.user_id,
    created_by: website.user_id,
    created_at: now,
    updated_at: now,
    ...input,
    status: "submitted",
    assignee_placeholder: "Awaiting assignment",
    comments: [],
    activity: [activityEntry("created", "Request submitted.")],
  };
  mockSupportRequests.push(request);
  persist();
  return request;
}

function patch(id: string, updater: (req: ExpertSupportRequest) => ExpertSupportRequest): ExpertSupportRequest | null {
  const index = mockSupportRequests.findIndex((s) => s.id === id);
  if (index === -1) return null;
  const updated = updater(mockSupportRequests[index]);
  mockSupportRequests[index] = updated;
  persist();
  return updated;
}

const STATUS_LABEL: Record<SupportStatus, string> = {
  submitted: "Submitted",
  in_review: "In review",
  assigned: "Assigned",
  waiting_for_client: "Waiting for client",
  in_progress: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
};

export function updateSupportRequestStatus(id: string, status: SupportStatus): ExpertSupportRequest | null {
  return patch(id, (req) => {
    const now = new Date().toISOString();
    return {
      ...req,
      status,
      updated_at: now,
      activity: [...req.activity, activityEntry("status_changed", `Status changed to ${STATUS_LABEL[status]}.`)],
    };
  });
}

export function addSupportComment(
  id: string,
  comment: Pick<SupportComment, "author_role" | "comment_text">,
): ExpertSupportRequest | null {
  return patch(id, (req) => {
    const now = new Date().toISOString();
    const newComment: SupportComment = { id: `cmt_mock_${Date.now()}`, created_at: now, ...comment };
    return {
      ...req,
      comments: [...req.comments, newComment],
      updated_at: now,
      activity: [...req.activity, activityEntry("comment_added", "Comment added.")],
    };
  });
}

export function markAdditionalInfoProvided(id: string): ExpertSupportRequest | null {
  return patch(id, (req) => {
    const now = new Date().toISOString();
    const nextStatus: SupportStatus = req.status === "waiting_for_client" ? "in_review" : req.status;
    return {
      ...req,
      status: nextStatus,
      updated_at: now,
      activity: [...req.activity, activityEntry("info_provided", "Additional info provided by client.")],
    };
  });
}

export function cancelSupportRequest(id: string): ExpertSupportRequest | null {
  return patch(id, (req) => {
    const now = new Date().toISOString();
    return {
      ...req,
      status: "cancelled",
      updated_at: now,
      activity: [...req.activity, activityEntry("cancelled", "Request cancelled.")],
    };
  });
}
