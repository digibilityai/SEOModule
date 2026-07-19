import type { ApprovalItem, SeoUserRole } from "@/types";

export type ApprovalActionKey =
  | "approve"
  | "reject"
  | "edit"
  | "expert_review"
  | "developer_needed"
  | "comment"
  | "completed";

export interface ActionAvailability {
  allowed: boolean;
  reason?: string;
}

type PermissionBucket = "owner_admin" | "team_member" | "client";

function bucketForRole(role: SeoUserRole): PermissionBucket {
  if (role === "owner" || role === "admin") return "owner_admin";
  if (role === "team_member") return "team_member";
  return "client";
}

// A "low-risk, simple suggestion" a client is trusted to approve/reject
// directly — anything touching URLs/redirects/canonical/noindex/robots.txt/
// sitemap (is_high_risk_category) or rated medium/high risk is excluded.
function isLowRiskSimple(item: ApprovalItem): boolean {
  return (
    item.risk === "low" &&
    !item.is_high_risk_category &&
    (item.action_type === "auto_suggest" || item.action_type === "manual_support")
  );
}

function isHighRisk(item: ApprovalItem): boolean {
  return item.risk !== "low" || item.is_high_risk_category;
}

export function getAvailableActions(
  role: SeoUserRole,
  item: ApprovalItem,
): Record<ApprovalActionKey, ActionAvailability> {
  const bucket = bucketForRole(role);

  const actions: Record<ApprovalActionKey, ActionAvailability> = {
    approve: { allowed: false },
    reject: { allowed: false },
    edit: { allowed: false },
    expert_review: { allowed: false },
    developer_needed: { allowed: false },
    comment: { allowed: true },
    completed: { allowed: false },
  };

  if (bucket === "owner_admin") {
    actions.approve = { allowed: true };
    actions.reject = { allowed: true };
    actions.edit = { allowed: true };
    actions.expert_review = { allowed: true };
    actions.developer_needed = { allowed: true };
    actions.completed = { allowed: true };
    return actions;
  }

  if (bucket === "team_member") {
    actions.approve = isHighRisk(item)
      ? { allowed: false, reason: "High-risk items need owner/admin approval." }
      : { allowed: true };
    actions.reject = { allowed: true };
    actions.edit = { allowed: true };
    actions.expert_review = { allowed: true };
    actions.developer_needed = { allowed: true };
    actions.completed = { allowed: false, reason: "Only owner/admin can mark items completed." };
    return actions;
  }

  // client
  const clientCanActDirectly = isLowRiskSimple(item);
  actions.approve = clientCanActDirectly
    ? { allowed: true }
    : { allowed: false, reason: "Clients can only approve low-risk, simple suggestions." };
  actions.reject = clientCanActDirectly
    ? { allowed: true }
    : { allowed: false, reason: "Clients can only reject low-risk, simple suggestions." };
  actions.edit = { allowed: false, reason: "Only team members and admins can edit suggestions." };
  actions.expert_review = { allowed: true };
  actions.developer_needed = isHighRisk(item)
    ? { allowed: true }
    : { allowed: false, reason: "Send to developer is only needed for high-risk items." };
  actions.completed = { allowed: false, reason: "Only owner/admin can mark items completed." };
  return actions;
}

export type ApprovalFilterKey =
  | "all"
  | "needs_review"
  | "approval_required"
  | "expert_review"
  | "developer_needed"
  | "approved"
  | "rejected"
  | "completed"
  | "high_risk";

export const APPROVAL_FILTERS: { key: ApprovalFilterKey; label: string }[] = [
  { key: "all", label: "All" },
  { key: "needs_review", label: "Needs Review" },
  { key: "approval_required", label: "Approval Required" },
  { key: "expert_review", label: "Expert Review" },
  { key: "developer_needed", label: "Developer Needed" },
  { key: "approved", label: "Approved" },
  { key: "rejected", label: "Rejected" },
  { key: "completed", label: "Completed" },
  { key: "high_risk", label: "High Risk" },
];

export function filterApprovalItems(items: ApprovalItem[], filter: ApprovalFilterKey): ApprovalItem[] {
  switch (filter) {
    case "all":
      return items;
    case "needs_review":
      return items.filter((i) => i.status === "suggested" || i.status === "needs_review");
    case "approval_required":
      return items.filter((i) => i.action_type === "approval_required");
    case "expert_review":
      return items.filter((i) => i.status === "expert_review_requested");
    case "developer_needed":
      return items.filter((i) => i.status === "developer_needed");
    case "approved":
      return items.filter((i) => i.status === "approved");
    case "rejected":
      return items.filter((i) => i.status === "rejected");
    case "completed":
      return items.filter((i) => i.status === "completed");
    case "high_risk":
      return items.filter((i) => isHighRisk(i));
    default:
      return items;
  }
}
