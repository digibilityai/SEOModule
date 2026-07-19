import type { AuthorityCampaign, SeoUserRole } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { FIX_OWNER_LABEL } from "./offPageLabels";
import { RoleGateTooltip } from "./RoleGateTooltip";

const APPROVAL_STATUS_LABEL: Record<AuthorityCampaign["approval_status"], string> = {
  draft: "Draft",
  pending_approval: "Pending approval",
  approved: "Approved",
  rejected: "Rejected",
};

// Phase 15D Step 2A/2D — both `submit_for_approval` (from draft) and
// `return_to_draft` (from rejected, this step) share the base manager role
// check (owner/admin/team_member) — same as most opportunity actions, no
// extra owner/admin-only restriction like opportunity `reject`.
// Exported (Phase 15D create-gating fix) so AuthorityBuilderPage reuses this
// exact list for the campaign-CREATE gate — campaign creation carries the same
// owner/admin/team_member privilege as submit — rather than defining a second,
// drift-prone role list.
export const CAMPAIGN_SUBMIT_ROLES: SeoUserRole[] = ["owner", "admin", "team_member"];

// Phase 15D Step 2B/2C — both the RPC's `approve` and `reject` actions are
// only legal from `pending_approval` (hidden for draft/approved/rejected),
// and both carry the RPC's own extra restriction: owner/admin only
// (team_member and client are both denied), mirroring opportunity
// `reject`'s owner/admin-only shape.
const CAMPAIGN_OWNER_ADMIN_ROLES: SeoUserRole[] = ["owner", "admin"];

interface CampaignListProps {
  campaigns: AuthorityCampaign[];
  onSubmitForApproval: (id: string) => void;
  onApprove: (id: string) => void;
  onReject: (id: string) => void;
  onReturnToDraft: (id: string) => void;
  isMutating: boolean;
  /**
   * The signed-in user's real seo_workspace_members.seo_role for this
   * website's workspace, or null if unknown/no active membership. Only
   * enforced when roleGatingActive is true (Supabase mode) — see
   * OpportunityCard.tsx's identical convention.
   */
  role: SeoUserRole | null;
  /** True only in Supabase mode — mock mode has no real seo_role concept. */
  roleGatingActive: boolean;
}

interface CampaignActionButtonProps {
  label: string;
  visible: boolean;
  rolePermitted: boolean;
  isMutating: boolean;
  deniedTooltip: string;
  onClick: () => void;
}

// A disabled Button has `pointer-events: none` and isn't reliably focusable,
// so neither hover nor keyboard focus ever reaches it — wrap it in a
// non-disabled, focusable element and attach the tooltip trigger there
// instead. Same proven pattern as OpportunityCard.tsx's role-denied tooltip.
// Shared here since campaigns now have two independently role-gated actions
// (submit for approval, approve) that both need this exact wrapper.
function CampaignActionButton({
  label,
  visible,
  rolePermitted,
  isMutating,
  deniedTooltip,
  onClick,
}: CampaignActionButtonProps) {
  if (!visible) return null;

  return (
    <RoleGateTooltip show={!rolePermitted} tooltip={deniedTooltip}>
      <Button size="sm" variant="outline" disabled={isMutating || !rolePermitted} onClick={onClick}>
        {label}
      </Button>
    </RoleGateTooltip>
  );
}

export function CampaignList({
  campaigns,
  onSubmitForApproval,
  onApprove,
  onReject,
  onReturnToDraft,
  isMutating,
  role,
  roleGatingActive,
}: CampaignListProps) {
  if (campaigns.length === 0) {
    return (
      <Card>
        <CardContent className="py-6 text-center text-sm text-muted-foreground">
          No campaigns yet. Select a few opportunities above and build one.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {campaigns.map((c) => {
        const canSubmitForApproval = c.approval_status === "draft";
        const isPendingApproval = c.approval_status === "pending_approval";
        const canReturnToDraft = c.approval_status === "rejected";
        const submitRolePermitted =
          !roleGatingActive || (role !== null && CAMPAIGN_SUBMIT_ROLES.includes(role));
        const ownerAdminRolePermitted =
          !roleGatingActive || (role !== null && CAMPAIGN_OWNER_ADMIN_ROLES.includes(role));

        return (
          <Card key={c.id}>
            <CardHeader className="space-y-2">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <CardTitle className="text-base">{c.name}</CardTitle>
                <Badge variant="secondary">{APPROVAL_STATUS_LABEL[c.approval_status]}</Badge>
              </div>
              <p className="text-sm text-muted-foreground">{c.goal}</p>
              <div className="flex flex-wrap gap-2 text-xs">
                <Badge variant="outline">Owner: {FIX_OWNER_LABEL[c.owner]}</Badge>
                <Badge variant="outline">Opportunities: {c.opportunity_ids.length}</Badge>
                <Badge variant="outline">Due: {c.due_date ?? "Not set"}</Badge>
                <Badge variant="outline">Progress: {c.progress_percentage}%</Badge>
              </div>
            </CardHeader>
            <CardContent className="space-y-1.5 border-t border-border pt-3 text-sm">
              <p className="font-medium text-foreground">Checklist</p>
              {c.tasks.map((t) => (
                <div key={t.id} className="flex items-center gap-2 text-muted-foreground">
                  <input type="checkbox" checked={t.is_complete} readOnly className="h-3.5 w-3.5" />
                  <span className={t.is_complete ? "line-through" : undefined}>{t.label}</span>
                </div>
              ))}
            </CardContent>
            {(canSubmitForApproval || isPendingApproval || canReturnToDraft) && (
              <CardFooter className="flex flex-wrap gap-2 border-t border-border pt-3">
                <CampaignActionButton
                  label="Submit for approval"
                  visible={canSubmitForApproval}
                  rolePermitted={submitRolePermitted}
                  isMutating={isMutating}
                  deniedTooltip="Requires the owner, admin, or team member role."
                  onClick={() => onSubmitForApproval(c.id)}
                />
                <CampaignActionButton
                  label="Approve"
                  visible={isPendingApproval}
                  rolePermitted={ownerAdminRolePermitted}
                  isMutating={isMutating}
                  deniedTooltip="Requires the owner or admin role."
                  onClick={() => onApprove(c.id)}
                />
                <CampaignActionButton
                  label="Reject"
                  visible={isPendingApproval}
                  rolePermitted={ownerAdminRolePermitted}
                  isMutating={isMutating}
                  deniedTooltip="Requires the owner or admin role."
                  onClick={() => onReject(c.id)}
                />
                <CampaignActionButton
                  label="Return to Draft"
                  visible={canReturnToDraft}
                  rolePermitted={submitRolePermitted}
                  isMutating={isMutating}
                  deniedTooltip="Requires the owner, admin, or team member role."
                  onClick={() => onReturnToDraft(c.id)}
                />
              </CardFooter>
            )}
          </Card>
        );
      })}
    </div>
  );
}
