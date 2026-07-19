import type {
  ExpertSupportRequest,
  NewSupportRequestInput,
  SeoWebsite,
  SupportComment,
  SupportStatus,
  SupportSummary,
} from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { getPlanConfig } from "@/registry/planRegistry";
import { MOCK_CURRENT_PLAN_TIER } from "@/mocks/mockContext";
import {
  addSupportComment as addSupportCommentRecord,
  cancelSupportRequest as cancelSupportRequestRecord,
  createSupportRequest as createSupportRequestRecord,
  getSupportRequestById,
  listSupportRequests,
  markAdditionalInfoProvided as markAdditionalInfoProvidedRecord,
  updateSupportRequestStatus as updateSupportRequestStatusRecord,
} from "@/mocks/supportMockData";

const SUPPORT_ACCESS_LABEL: Record<string, string> = {
  paid_add_on: "Expert support available as a paid add-on",
  limited_included: "Limited expert support included in your plan",
  priority_bundled: "Priority expert support included in your plan",
};

export async function fetchSupportRequests(websiteId: string): Promise<ExpertSupportRequest[]> {
  return toAsync(listSupportRequests(websiteId));
}

export async function fetchSupportRequestDetail(id: string): Promise<ExpertSupportRequest | null> {
  return toAsync(getSupportRequestById(id));
}

export async function fetchSupportSummary(
  websiteId: string,
  websiteUrl: string,
): Promise<SupportSummary> {
  const requests = listSupportRequests(websiteId);
  const isOpen = (r: ExpertSupportRequest) => r.status !== "completed" && r.status !== "cancelled";
  const planConfig = getPlanConfig(MOCK_CURRENT_PLAN_TIER);

  return toAsync({
    website_id: websiteId,
    website_url: websiteUrl,
    support_plan_status: SUPPORT_ACCESS_LABEL[planConfig.expertSupportAccess] ?? "Expert support available",
    open_requests_count: requests.filter(isOpen).length,
    pending_expert_review_count: requests.filter((r) => isOpen(r) && r.preferred_support_mode === "expert_review")
      .length,
    developer_needed_count: requests.filter((r) => isOpen(r) && r.preferred_support_mode === "developer_needed")
      .length,
    completed_requests_count: requests.filter((r) => r.status === "completed").length,
  });
}

export async function createSupportRequest(
  website: SeoWebsite,
  input: NewSupportRequestInput,
): Promise<ExpertSupportRequest> {
  return toAsync(createSupportRequestRecord(website, input));
}

export async function updateSupportRequestStatus(
  id: string,
  status: SupportStatus,
): Promise<ExpertSupportRequest | null> {
  return toAsync(updateSupportRequestStatusRecord(id, status));
}

export async function addSupportComment(
  id: string,
  comment: Pick<SupportComment, "author_role" | "comment_text">,
): Promise<ExpertSupportRequest | null> {
  return toAsync(addSupportCommentRecord(id, comment));
}

export async function markAdditionalInfoProvided(id: string): Promise<ExpertSupportRequest | null> {
  return toAsync(markAdditionalInfoProvidedRecord(id));
}

export async function cancelSupportRequest(id: string): Promise<ExpertSupportRequest | null> {
  return toAsync(cancelSupportRequestRecord(id));
}
