import { useState } from "react";
import type { OffPageOpportunity, OffPageOpportunityStatus, SeoUserRole } from "@/types";
import type { AuthorityOpportunityTransitionAction } from "@/services/supabase/seoOffPageAuthoritySupabaseService";
import { AlertTriangle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  FIX_OWNER_LABEL,
  OPPORTUNITY_STATUS_LABEL,
  OPPORTUNITY_STATUS_VARIANT,
  OPPORTUNITY_TYPE_LABEL,
  SPAM_FLAG_LABEL,
} from "./offPageLabels";
import { RoleGateTooltip } from "./RoleGateTooltip";

// Phase 15C Step 1 — the legal opportunity-transition action set, replacing
// the old unconditional 4/6-button mock set with buttons gated exactly per
// PHASE_15B_STAGE6_WRITE_UX_AUDIT.md §4.1's proposed matrix, itself a direct
// mirror of seo_authority_opportunity_transition's CASE statement
// (supabase/migrations/20260711120020_seo_stage6_authority_activity.sql).
// This table is presentation-only — hiding/disabling a button here is a UX
// convenience, NOT the authorization boundary; the RPC re-checks everything
// server-side regardless of what this file decides to render.

const OPPORTUNITY_TRANSITION_LABEL: Record<AuthorityOpportunityTransitionAction, string> = {
  shortlist: "Shortlist",
  request_approval: "Request approval",
  request_expert_review: "Send to expert review",
  start: "Start",
  complete: "Mark completed",
  reject: "Reject",
  avoid: "Mark as avoided",
};

// Legal `from` status per action — exact mirror of the RPC's CASE statement.
const LEGAL_FROM_STATUS: Record<AuthorityOpportunityTransitionAction, OffPageOpportunityStatus[]> = {
  shortlist: ["suggested"],
  request_approval: ["shortlisted"],
  request_expert_review: ["shortlisted", "approval_required", "in_progress"],
  start: ["approval_required", "expert_review_requested"],
  complete: ["in_progress"],
  reject: ["suggested", "shortlisted", "approval_required", "in_progress", "expert_review_requested"],
  avoid: ["suggested", "shortlisted", "approval_required", "in_progress", "expert_review_requested"],
};

const MANAGER_ROLES: SeoUserRole[] = ["owner", "admin", "team_member"];
const OWNER_ADMIN_ONLY_ROLES: SeoUserRole[] = ["owner", "admin"];

// Role requirement per action — reject is the one opportunity action the RPC
// restricts to owner/admin (see the RPC's `reject` branch); every other
// action only requires the base manager check (owner/admin/team_member).
const REQUIRED_ROLES: Record<AuthorityOpportunityTransitionAction, SeoUserRole[]> = {
  shortlist: MANAGER_ROLES,
  request_approval: MANAGER_ROLES,
  request_expert_review: MANAGER_ROLES,
  start: MANAGER_ROLES,
  complete: MANAGER_ROLES,
  reject: OWNER_ADMIN_ONLY_ROLES,
  avoid: MANAGER_ROLES,
};

const ALL_ACTIONS: AuthorityOpportunityTransitionAction[] = [
  "shortlist",
  "request_approval",
  "request_expert_review",
  "start",
  "complete",
  "reject",
  "avoid",
];

function roleDeniedTooltip(action: AuthorityOpportunityTransitionAction): string {
  const roles = REQUIRED_ROLES[action];
  return roles.length === 2
    ? "Requires the owner or admin role."
    : "Requires the owner, admin, or team member role.";
}

interface OpportunityCardProps {
  opportunity: OffPageOpportunity;
  isSelected: boolean;
  onToggleSelected: (id: string) => void;
  onTransition: (id: string, action: AuthorityOpportunityTransitionAction) => void;
  isMutating: boolean;
  /**
   * The signed-in user's real seo_workspace_members.seo_role for this
   * opportunity's workspace (via getCurrentSeoRole), or null if unknown/no
   * active membership. Only enforced when roleGatingActive is true (Supabase
   * mode) — see roleGatingActive doc below.
   */
  role: SeoUserRole | null;
  /**
   * True only in Supabase mode. Mock mode has no real seo_role concept (no
   * seo_workspace_members rows exist for the mock context), so role gating
   * is skipped there entirely and every legal-by-status action stays
   * enabled — unchanged from the app's pre-existing mock behavior.
   */
  roleGatingActive: boolean;
}

export function OpportunityCard({
  opportunity,
  isSelected,
  onToggleSelected,
  onTransition,
  isMutating,
  role,
  roleGatingActive,
}: OpportunityCardProps) {
  const [expanded, setExpanded] = useState(false);
  const isRisky = opportunity.risk === "high" || opportunity.spam_risk_flags.length > 0;

  // Phase 15D create-gating fix — selecting an opportunity is the entry point
  // to campaign creation, which is an owner/admin/team_member privilege (same
  // MANAGER_ROLES base as most actions). Gate the selection control for a real
  // authenticated client so ordinary UI interaction can't reach CampaignBuilder
  // / issue seo_authority_campaign_create. Mock mode (roleGatingActive false)
  // keeps selection open, unchanged. Presentation-only; the RPC still re-checks.
  const selectionRolePermitted =
    !roleGatingActive || (role !== null && MANAGER_ROLES.includes(role));

  const availableActions = ALL_ACTIONS.filter((action) =>
    LEGAL_FROM_STATUS[action].includes(opportunity.status),
  );

  return (
    <Card className={isRisky ? "border-destructive/40" : undefined}>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="flex items-start gap-2">
            <RoleGateTooltip
              show={!selectionRolePermitted}
              tooltip="Requires the owner, admin, or team member role."
            >
              <input
                type="checkbox"
                className="mt-1 h-4 w-4"
                checked={isSelected}
                onChange={() => onToggleSelected(opportunity.id)}
                aria-label={`Select ${opportunity.title} for a campaign`}
                disabled={!selectionRolePermitted}
              />
            </RoleGateTooltip>
            <div className="cursor-pointer" onClick={() => setExpanded((e) => !e)}>
              <h3 className="font-medium text-foreground">{opportunity.title}</h3>
              <p className="text-xs text-muted-foreground">{opportunity.source_platform}</p>
            </div>
          </div>
          <Badge variant={OPPORTUNITY_STATUS_VARIANT[opportunity.status]}>
            {OPPORTUNITY_STATUS_LABEL[opportunity.status]}
          </Badge>
        </div>

        <div className="flex flex-wrap gap-2 text-xs">
          <Badge variant="outline">{OPPORTUNITY_TYPE_LABEL[opportunity.opportunity_type]}</Badge>
          <Badge variant="outline">Authority impact: {opportunity.expected_authority_impact}</Badge>
          <Badge variant="outline">Effort: {opportunity.effort}</Badge>
          <Badge variant="outline">Risk: {opportunity.risk}</Badge>
          <Badge variant="outline">Confidence: {opportunity.confidence_percentage}%</Badge>
          <Badge variant="outline">Owner: {FIX_OWNER_LABEL[opportunity.fix_owner]}</Badge>
          {opportunity.requires_approval && <Badge variant="secondary">Needs approval</Badge>}
        </div>

        {isRisky && (
          <div className="flex items-start gap-2 rounded-md bg-destructive/10 p-2 text-xs text-destructive">
            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            <span>
              Flagged: {opportunity.spam_risk_flags.map((f) => SPAM_FLAG_LABEL[f]).join(", ") || "High risk"}
            </span>
          </div>
        )}

        {/* Rendering-bug fix: this action row previously lived inside
            `{expanded && (...)}` below, so every card loaded with ZERO
            visible buttons until its title was clicked to expand it — the
            reported "no action buttons render on any opportunity card"
            regression, reproduced on a fresh page load with no
            interaction (confirmed: 0 action buttons in the DOM pre-click,
            for every status). availableActions/role logic is unchanged;
            only its position moved so actions are visible immediately,
            same as the status/type/risk badges above. */}
        <div className="flex flex-wrap gap-2 border-t border-border pt-3">
          {availableActions.length === 0 ? (
            <p className="text-xs text-muted-foreground">
              No further actions available — this opportunity has reached a terminal status.
            </p>
          ) : (
            availableActions.map((action) => {
              const rolePermitted =
                !roleGatingActive || (role !== null && REQUIRED_ROLES[action].includes(role));
              const isDestructive = action === "reject" || action === "avoid";

              const button = (
                <Button
                  size="sm"
                  variant={isDestructive ? "destructive" : "outline"}
                  disabled={isMutating || !rolePermitted}
                  onClick={() => onTransition(opportunity.id, action)}
                >
                  {OPPORTUNITY_TRANSITION_LABEL[action]}
                </Button>
              );

              if (rolePermitted) {
                return <span key={action}>{button}</span>;
              }

              // A disabled Button has `pointer-events: none` (see
              // buttonVariants' `disabled:pointer-events-none`) and isn't
              // reliably focusable, so neither hover nor keyboard focus ever
              // reaches it — a `title`/tooltip attached to the button itself
              // never fires. Wrap it in a non-disabled, focusable element and
              // attach the tooltip trigger there instead.
              return (
                <span
                  key={action}
                  tabIndex={0}
                  className="group relative inline-block rounded-md focus:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                >
                  {button}
                  <span
                    role="tooltip"
                    className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 text-xs text-popover-foreground shadow-md group-hover:block group-focus:block"
                  >
                    {roleDeniedTooltip(action)}
                  </span>
                </span>
              );
            })
          )}
        </div>
      </CardHeader>

      {expanded && (
        <CardContent className="space-y-3 border-t border-border pt-4 text-sm">
          <div>
            <p className="font-medium text-foreground">Suggested action</p>
            <p className="text-muted-foreground">{opportunity.suggested_action}</p>
          </div>
          <div>
            <p className="font-medium text-foreground">Why this matters</p>
            <p className="text-muted-foreground">{opportunity.why_it_matters}</p>
          </div>
        </CardContent>
      )}
    </Card>
  );
}
