import { useState } from "react";
import type { OffPageOpportunity, OwnerType } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { FIX_OWNER_LABEL } from "./offPageLabels";
import { RoleGateTooltip } from "./RoleGateTooltip";

interface CampaignBuilderProps {
  selectedOpportunities: OffPageOpportunity[];
  onCreate: (input: { name: string; goal: string; owner: OwnerType; due_date?: string }) => void;
  onClearSelection: () => void;
  isMutating: boolean;
  /**
   * Phase 15D create-gating fix: whether the signed-in user's real
   * seo_workspace_members.seo_role may create campaigns (owner/admin/team_member
   * in Supabase mode; always true in mock mode, which has no seo_role concept).
   * Presentation-only — the seo_authority_campaign_create RPC re-checks
   * authorization server-side regardless. Defaults to true so the only existing
   * consumer stays backward-compatible and mock mode is unaffected.
   */
  createRolePermitted?: boolean;
}

const OWNER_OPTIONS: OwnerType[] = ["client_action", "developer_needed", "digibility_expert", "system_suggestion"];

export function CampaignBuilder({
  selectedOpportunities,
  onCreate,
  onClearSelection,
  isMutating,
  createRolePermitted = true,
}: CampaignBuilderProps) {
  const [name, setName] = useState("");
  const [goal, setGoal] = useState("");
  const [owner, setOwner] = useState<OwnerType>("client_action");
  const [dueDate, setDueDate] = useState("");

  if (selectedOpportunities.length === 0) {
    return null;
  }

  const canCreate = name.trim().length > 0 && goal.trim().length > 0;

  const handleCreate = () => {
    // Role check is the defense-in-depth secondary gate: even if a selection or
    // an enabled Create button is reached through stale state, a role-denied
    // user never issues the seo_authority_campaign_create request.
    if (!canCreate || !createRolePermitted) return;
    onCreate({ name: name.trim(), goal: goal.trim(), owner, due_date: dueDate || undefined });
    setName("");
    setGoal("");
    setDueDate("");
  };

  return (
    <Card className="border-dashed">
      <CardHeader>
        <CardTitle className="text-base">Build a campaign from {selectedOpportunities.length} selected opportunit{selectedOpportunities.length === 1 ? "y" : "ies"}</CardTitle>
        <CardDescription>Group opportunities into one plan to review and work through together. No outreach is sent automatically.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap gap-1.5">
          {selectedOpportunities.map((o) => (
            <Badge key={o.id} variant="outline">
              {o.title}
            </Badge>
          ))}
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1">
            <Label htmlFor="campaign-name">Campaign name</Label>
            <Input
              id="campaign-name"
              placeholder="e.g. Local Trust Building — Q3"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="campaign-goal">Campaign goal</Label>
            <Input
              id="campaign-goal"
              placeholder="e.g. Improve local trust and citation coverage"
              value={goal}
              onChange={(e) => setGoal(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="campaign-owner">Owner</Label>
            <Select id="campaign-owner" value={owner} onChange={(e) => setOwner(e.target.value as OwnerType)}>
              {OWNER_OPTIONS.map((o) => (
                <option key={o} value={o}>
                  {FIX_OWNER_LABEL[o]}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="campaign-due-date">Due date (optional)</Label>
            <Input id="campaign-due-date" type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </div>
        </div>

        <div className="flex gap-2">
          <RoleGateTooltip
            show={!createRolePermitted}
            tooltip="Requires the owner, admin, or team member role."
          >
            <Button
              size="sm"
              onClick={handleCreate}
              disabled={!canCreate || isMutating || !createRolePermitted}
            >
              Create campaign
            </Button>
          </RoleGateTooltip>
          <Button size="sm" variant="outline" onClick={onClearSelection} disabled={isMutating}>
            Clear selection
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
