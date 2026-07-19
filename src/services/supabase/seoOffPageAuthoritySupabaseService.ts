import type {
  AuthorityCampaign,
  CampaignApprovalStatus,
  CampaignTask,
  EffortLevel,
  ImpactLevel,
  NewAuthorityCampaignInput,
  OffPageOpportunity,
  OffPageOpportunityStatus,
  OffPageOpportunityType,
  OwnerType,
  RiskLevel,
  SeoWebsite,
  SpamRiskFlag,
} from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES, SEO_RPCS } from "@/services/supabase/supabaseTypes";
import {
  requireAuthenticatedUser,
  requireValidUuid,
  safeList,
  safeSingle,
} from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";
import { listAccessibleSeoWorkspaces } from "@/services/supabase/seoWorkspaceService";
import { fetchSupabaseWebsitesForWorkspace } from "@/services/supabase/seoWebsiteSupabaseService";

// =============================================================================
// Phase 15A (reads) + Phase 15C Step 1 (opportunity transition writes).
//
// The app's existing OffPageOpportunity / AuthorityCampaign shapes
// (src/types/offpage.ts) predate Stage 6 and assume a simpler model than the
// backend actually has (a stored opportunity_ids[] array + tasks[] embedded
// directly on the campaign). Stage 6's real schema normalizes both of those
// into separate tables (see SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_PLAN.md
// §0 D1/D6):
//   - seo_authority_campaign_opportunities (junction) is the SOURCE OF TRUTH
//     for campaign <-> opportunity membership — AuthorityCampaign.opportunity_ids
//     is DERIVED from it here, never stored.
//   - seo_authority_campaign_tasks holds the campaign's checklist —
//     AuthorityCampaign.tasks is read from it and progress_percentage is
//     COMPUTED (complete / total), never stored, matching D6.
// This file reads Stage 6 and maps it down into the app's existing flat
// shapes, so no UI component or type change is needed for reads — only
// offPageService.ts's read-facing functions change.
//
// WRITES (Phase 15C Step 1 — OPPORTUNITY transitions only): the
// seo_authority_opportunity_transition RPC is now called below
// (transitionSupabaseAuthorityOpportunity), following the exact Phase 13D
// (seoApprovalSupabaseService.ts's ApprovalTransitionError) / Phase 13E
// (ContentTransitionError) non-masking pattern — a real RPC rejection
// (illegal transition, role denied, not found) throws
// AuthorityOpportunityTransitionError and is NEVER swallowed by a mock
// fallback; only a missing session/config falls back to mock (enforced in
// offPageService.ts's runAuthorityOpportunityWrite, not here). No direct
// UPDATE on seo_authority_opportunities appears anywhere in this file — the
// RPC is the only write path. seo_authority_campaign_transition is
// deliberately NOT called anywhere in this file — campaign writes are out of
// scope for this step (see PHASE_15B_STAGE6_WRITE_UX_AUDIT.md §4.2 for the
// proposed campaign matrix, not implemented here).
// =============================================================================

interface SeoAuthorityOpportunityRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  opportunity_type: string;
  title: string;
  source_platform: string;
  target_url: string | null;
  target_domain: string | null;
  suggested_action: string;
  why_it_matters: string;
  expected_authority_impact: string;
  effort: string;
  risk: string;
  confidence_percentage: number | null;
  requires_approval: boolean;
  fix_owner: string;
  status: string;
  spam_risk_flags: string[];
  recommended_next_action: string | null;
  notes: string | null;
  source: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoAuthorityCampaignRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  name: string;
  goal: string;
  campaign_type: string | null;
  approval_status: string;
  owner: string;
  due_date: string | null;
  started_at: string | null;
  completed_at: string | null;
  source: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoAuthorityCampaignTaskRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  campaign_id: string;
  opportunity_id: string | null;
  label: string;
  task_type: string | null;
  owner_type: string | null;
  is_complete: boolean;
  external_action_required: boolean;
  position: number;
  due_date: string | null;
  completed_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

interface SeoAuthorityCampaignOpportunityRow {
  workspace_id: string;
  website_id: string;
  website_url: string;
  campaign_id: string;
  opportunity_id: string;
  created_by: string | null;
  created_at: string;
}

// Exposed for the dev harness / any future activity/history UI — no page
// reads this yet (same "raw row, no frontend type" precedent as Stage 5's
// SeoDeclineDiagnosisEvidenceRow).
export interface SeoAuthorityActivityRow {
  id: string;
  workspace_id: string;
  website_id: string;
  website_url: string;
  subject_type: string;
  opportunity_id: string | null;
  campaign_id: string | null;
  activity_type: string;
  from_status: string | null;
  to_status: string | null;
  note: string | null;
  actor_role_snapshot: string | null;
  created_by: string | null;
  created_at: string;
}

const OPPORTUNITY_COLUMNS =
  "id, workspace_id, website_id, website_url, opportunity_type, title, source_platform, target_url, target_domain, suggested_action, why_it_matters, expected_authority_impact, effort, risk, confidence_percentage, requires_approval, fix_owner, status, spam_risk_flags, recommended_next_action, notes, source, created_by, created_at, updated_at";

const CAMPAIGN_COLUMNS =
  "id, workspace_id, website_id, website_url, name, goal, campaign_type, approval_status, owner, due_date, started_at, completed_at, source, created_by, created_at, updated_at";

const CAMPAIGN_TASK_COLUMNS =
  "id, workspace_id, website_id, website_url, campaign_id, opportunity_id, label, task_type, owner_type, is_complete, external_action_required, position, due_date, completed_at, created_by, created_at, updated_at";

const CAMPAIGN_OPPORTUNITY_COLUMNS =
  "workspace_id, website_id, website_url, campaign_id, opportunity_id, created_by, created_at";

const ACTIVITY_COLUMNS =
  "id, workspace_id, website_id, website_url, subject_type, opportunity_id, campaign_id, activity_type, from_status, to_status, note, actor_role_snapshot, created_by, created_at";

// -----------------------------------------------------------------------------
// Mapping: Stage 6 backend CHECK values -> the app's existing frontend domain
// values. Unlike Stage 5's diagnosis_type, Stage 6's opportunity_type/status
// and campaign approval_status/owner vocabularies were deliberately authored
// 1:1 against these exact frontend types (see
// SUPABASE_MIGRATION_STAGE_6_OFFPAGE_AI_VISIBILITY_NOTES.md §7, deviation 1:
// "status vocabularies kept 1:1 with the locked plan + frontend types"), so
// every mapping below is a validated pass-through with a safe fallback for
// any unrecognized/future value — never a throw, never a lossy collapse.
// -----------------------------------------------------------------------------

const VALID_OPPORTUNITY_TYPES: ReadonlySet<string> = new Set([
  "backlink",
  "mention",
  "citation",
  "review",
  "pr",
  "social_community",
  "partnership",
]);
const DEFAULT_OPPORTUNITY_TYPE: OffPageOpportunityType = "backlink";
function mapOpportunityType(value: string): OffPageOpportunityType {
  return VALID_OPPORTUNITY_TYPES.has(value)
    ? (value as OffPageOpportunityType)
    : DEFAULT_OPPORTUNITY_TYPE;
}

const VALID_OPPORTUNITY_STATUSES: ReadonlySet<string> = new Set([
  "suggested",
  "shortlisted",
  "approval_required",
  "in_progress",
  "expert_review_requested",
  "completed",
  "rejected",
  "avoided",
]);
const DEFAULT_OPPORTUNITY_STATUS: OffPageOpportunityStatus = "suggested";
function mapOpportunityStatus(value: string): OffPageOpportunityStatus {
  return VALID_OPPORTUNITY_STATUSES.has(value)
    ? (value as OffPageOpportunityStatus)
    : DEFAULT_OPPORTUNITY_STATUS;
}

const VALID_IMPACT_EFFORT_RISK: ReadonlySet<string> = new Set(["low", "medium", "high"]);
function mapImpact(value: string): ImpactLevel {
  return VALID_IMPACT_EFFORT_RISK.has(value) ? (value as ImpactLevel) : "medium";
}
function mapEffort(value: string): EffortLevel {
  return VALID_IMPACT_EFFORT_RISK.has(value) ? (value as EffortLevel) : "medium";
}
function mapRisk(value: string): RiskLevel {
  return VALID_IMPACT_EFFORT_RISK.has(value) ? (value as RiskLevel) : "medium";
}

const VALID_OWNER_TYPES: ReadonlySet<string> = new Set([
  "client_action",
  "developer_needed",
  "digibility_expert",
  "system_suggestion",
]);
const DEFAULT_OWNER: OwnerType = "system_suggestion";
function mapOwner(value: string): OwnerType {
  return VALID_OWNER_TYPES.has(value) ? (value as OwnerType) : DEFAULT_OWNER;
}

// spam_risk_flags is a Postgres text[] already CHECK-constrained (via array
// containment) to exactly the frontend's SpamRiskFlag union at the database
// level — filtered defensively here anyway so a future/unexpected value
// never reaches a label lookup the UI can't render.
const VALID_SPAM_FLAGS: ReadonlySet<string> = new Set([
  "paid_link_risk",
  "irrelevant_directory",
  "pbn_like_site",
  "exact_match_anchor_manipulation",
  "fake_review_risk",
  "mass_outreach_risk",
  "low_relevance",
  "low_trust",
]);
function mapSpamRiskFlags(value: string[]): SpamRiskFlag[] {
  return value.filter((flag): flag is SpamRiskFlag => VALID_SPAM_FLAGS.has(flag));
}

const VALID_APPROVAL_STATUSES: ReadonlySet<string> = new Set([
  "draft",
  "pending_approval",
  "approved",
  "rejected",
]);
const DEFAULT_APPROVAL_STATUS: CampaignApprovalStatus = "draft";
function mapApprovalStatus(value: string): CampaignApprovalStatus {
  return VALID_APPROVAL_STATUSES.has(value)
    ? (value as CampaignApprovalStatus)
    : DEFAULT_APPROVAL_STATUS;
}

// target_domain, recommended_next_action, notes, source, campaign_type,
// started_at, completed_at, task_type, owner_type, external_action_required,
// due_date/completed_at on tasks — all additive Stage 6 columns with no
// frontend field. Read into the raw row types above for potential future
// use, but never mapped into OffPageOpportunity/AuthorityCampaign/CampaignTask
// (per the task's "do not invent behavior for a column with no frontend
// equivalent" rule) — this file only maps fields that already exist on the
// pre-existing frontend types.

function mapToOffPageOpportunity(row: SeoAuthorityOpportunityRow): OffPageOpportunity {
  return {
    id: row.id,
    workspace_id: row.workspace_id,
    website_id: row.website_id,
    website_url: row.website_url,
    user_id: row.created_by ?? "",
    created_by: row.created_by ?? "",
    created_at: row.created_at,
    updated_at: row.updated_at,
    opportunity_type: mapOpportunityType(row.opportunity_type),
    title: row.title,
    source_platform: row.source_platform,
    target_url: row.target_url ?? undefined,
    suggested_action: row.suggested_action,
    why_it_matters: row.why_it_matters,
    expected_authority_impact: mapImpact(row.expected_authority_impact),
    effort: mapEffort(row.effort),
    risk: mapRisk(row.risk),
    confidence_percentage: row.confidence_percentage ?? 0,
    requires_approval: row.requires_approval,
    fix_owner: mapOwner(row.fix_owner),
    status: mapOpportunityStatus(row.status),
    spam_risk_flags: mapSpamRiskFlags(row.spam_risk_flags ?? []),
  };
}

function mapToCampaignTask(row: SeoAuthorityCampaignTaskRow): CampaignTask {
  return {
    id: row.id,
    label: row.label,
    is_complete: row.is_complete,
  };
}

/**
 * Raw seo_authority_opportunities rows for a website. Read-only. Exposed
 * separately from fetchSupabaseAuthorityOpportunities so dev/diagnostic UI can
 * inspect the full backend shape (target_domain, notes, source, etc.) that the
 * flattened OffPageOpportunity type doesn't carry.
 */
export async function fetchSupabaseAuthorityOpportunityRows(
  websiteId: string,
): Promise<SeoAuthorityOpportunityRow[]> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityRows");
  requireValidUuid(
    "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityRows",
    websiteId,
    "websiteId",
  );

  return safeList<SeoAuthorityOpportunityRow>(
    "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityRows",
    supabase
      .from(SEO_TABLES.authorityOpportunities)
      .select(OPPORTUNITY_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
}

/**
 * Main app-facing read: all off-page authority opportunities for a website,
 * mapped into the app's existing OffPageOpportunity[] shape. Matches
 * AuthorityBuilderPage.tsx's "opportunities" list.
 */
export async function fetchSupabaseAuthorityOpportunities(websiteId: string): Promise<OffPageOpportunity[]> {
  const rows = await fetchSupabaseAuthorityOpportunityRows(websiteId);
  return rows.map(mapToOffPageOpportunity);
}

/**
 * Raw seo_authority_campaigns rows for a website. Read-only, dev-harness/
 * diagnostic use — same precedent as fetchSupabaseAuthorityOpportunityRows.
 */
export async function fetchSupabaseAuthorityCampaignRows(websiteId: string): Promise<SeoAuthorityCampaignRow[]> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityCampaignRows");
  requireValidUuid(
    "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityCampaignRows",
    websiteId,
    "websiteId",
  );

  return safeList<SeoAuthorityCampaignRow>(
    "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityCampaignRows",
    supabase
      .from(SEO_TABLES.authorityCampaigns)
      .select(CAMPAIGN_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
}

/**
 * Main app-facing read: all authority campaigns for a website, mapped into
 * the app's existing AuthorityCampaign[] shape.
 *
 * opportunity_ids is DERIVED from the seo_authority_campaign_opportunities
 * junction (D1 — the source of truth, never a stored array). tasks /
 * progress_percentage are DERIVED from seo_authority_campaign_tasks (D6 —
 * progress is complete/total, never a stored column). Both derivations run
 * as one extra query each per website (not per campaign) to keep this
 * O(1)-ish rather than N+1 across campaigns.
 */
export async function fetchSupabaseAuthorityCampaigns(websiteId: string): Promise<AuthorityCampaign[]> {
  const campaignRows = await fetchSupabaseAuthorityCampaignRows(websiteId);
  if (campaignRows.length === 0) return [];

  const [junctionRows, taskRows] = await Promise.all([
    safeList<SeoAuthorityCampaignOpportunityRow>(
      "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityCampaigns (junction)",
      supabase
        .from(SEO_TABLES.authorityCampaignOpportunities)
        .select(CAMPAIGN_OPPORTUNITY_COLUMNS)
        .eq("website_id", websiteId),
    ),
    safeList<SeoAuthorityCampaignTaskRow>(
      "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityCampaigns (tasks)",
      supabase
        .from(SEO_TABLES.authorityCampaignTasks)
        .select(CAMPAIGN_TASK_COLUMNS)
        .eq("website_id", websiteId)
        .order("position", { ascending: true }),
    ),
  ]);

  const opportunityIdsByCampaign = new Map<string, string[]>();
  for (const link of junctionRows) {
    const list = opportunityIdsByCampaign.get(link.campaign_id) ?? [];
    list.push(link.opportunity_id);
    opportunityIdsByCampaign.set(link.campaign_id, list);
  }

  const tasksByCampaign = new Map<string, SeoAuthorityCampaignTaskRow[]>();
  for (const task of taskRows) {
    const list = tasksByCampaign.get(task.campaign_id) ?? [];
    list.push(task);
    tasksByCampaign.set(task.campaign_id, list);
  }

  return campaignRows.map((row) => {
    const tasks = tasksByCampaign.get(row.id) ?? [];
    const completeCount = tasks.filter((t) => t.is_complete).length;
    const progressPercentage = tasks.length > 0 ? Math.round((completeCount / tasks.length) * 100) : 0;

    return {
      id: row.id,
      workspace_id: row.workspace_id,
      website_id: row.website_id,
      website_url: row.website_url,
      user_id: row.created_by ?? "",
      created_by: row.created_by ?? "",
      created_at: row.created_at,
      updated_at: row.updated_at,
      name: row.name,
      goal: row.goal,
      opportunity_ids: opportunityIdsByCampaign.get(row.id) ?? [],
      tasks: tasks.map(mapToCampaignTask),
      approval_status: mapApprovalStatus(row.approval_status),
      owner: mapOwner(row.owner),
      due_date: row.due_date ?? undefined,
      progress_percentage: progressPercentage,
    };
  });
}

/**
 * Raw seo_authority_activity rows for a website (append-only audit trail),
 * newest first. Read-only. No frontend activity/history UI exists yet, so
 * this returns the raw Supabase row shape directly for the dev harness /
 * any future activity-timeline component — same precedent as Stage 5's
 * evidence read.
 */
export async function fetchSupabaseAuthorityActivity(websiteId: string): Promise<SeoAuthorityActivityRow[]> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityActivity");
  requireValidUuid("seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityActivity", websiteId, "websiteId");

  return safeList<SeoAuthorityActivityRow>(
    "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityActivity",
    supabase
      .from(SEO_TABLES.authorityActivity)
      .select(ACTIVITY_COLUMNS)
      .eq("website_id", websiteId)
      .order("created_at", { ascending: false }),
  );
}

export interface WebsiteWithAuthorityData {
  workspaceId: string;
  workspaceName: string;
  websiteId: string;
  websiteUrl: string;
  opportunityCount: number;
  /** How many accessible websites had at least one opportunity (including the returned one) — dev-harness/debug context for why this candidate won. */
  candidateCount: number;
}

/**
 * Searches every SEO workspace the current user is a member of, and every
 * website within each, for the one with the MOST seo_authority_opportunities
 * rows. `null` if none have any. Read-only, no writes.
 *
 * Ranks by count rather than stopping at the first match — same rationale
 * and implementation shape as
 * seoDeclineDiagnosisSupabaseService.findAccessibleWebsiteWithDeclineDiagnosisData
 * (Phase 14B.2 §10): a test user can legitimately belong to several
 * workspaces (a disposable Stage 6 smoke-test workspace alongside the richer
 * UI seed workspace), and "first found" would be non-deterministic /
 * favor whichever workspace happens to be newest rather than the one with
 * real demo data. Does NOT hardcode any workspace/website id, name, or URL.
 */
export async function findAccessibleWebsiteWithAuthorityData(): Promise<WebsiteWithAuthorityData | null> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.findAccessibleWebsiteWithAuthorityData");

  const workspaces = await listAccessibleSeoWorkspaces();
  const candidates: Omit<WebsiteWithAuthorityData, "candidateCount">[] = [];

  for (const workspace of workspaces) {
    const websites = await fetchSupabaseWebsitesForWorkspace(workspace.id);
    for (const website of websites) {
      const rows = await fetchSupabaseAuthorityOpportunityRows(website.id);
      if (rows.length > 0) {
        candidates.push({
          workspaceId: workspace.id,
          workspaceName: workspace.name,
          websiteId: website.id,
          websiteUrl: website.website_url,
          opportunityCount: rows.length,
        });
      }
    }
  }

  if (candidates.length === 0) return null;

  candidates.sort((a, b) => b.opportunityCount - a.opportunityCount);

  return { ...candidates[0], candidateCount: candidates.length };
}

// =============================================================================
// Phase 15C Step 1 — Opportunity transition writes.
//
// The 7 legal action names, exactly matching seo_authority_opportunity_transition's
// CASE statement (supabase/migrations/20260711120020_seo_stage6_authority_activity.sql):
// shortlist / request_approval / request_expert_review / start / complete /
// reject / avoid. Campaign actions (submit_for_approval / approve / reject /
// return_to_draft) are a DIFFERENT RPC (seo_authority_campaign_transition) and
// are intentionally not represented here — out of scope for this step.
// =============================================================================
export type AuthorityOpportunityTransitionAction =
  | "shortlist"
  | "request_approval"
  | "request_expert_review"
  | "start"
  | "complete"
  | "reject"
  | "avoid";

/**
 * Thrown when the seo_authority_opportunity_transition RPC itself rejects the
 * call (illegal transition for the row's current status, role not permitted,
 * opportunity not found, unknown action). This is the backend's real,
 * authoritative decision — reaching this point means auth already succeeded,
 * so it is never a "not signed in" case. Mirrors
 * seoApprovalSupabaseService.ApprovalTransitionError (Phase 13D) /
 * seoContentStudioSupabaseService.ContentTransitionError (Phase 13E) exactly:
 * callers (offPageService.ts's runAuthorityOpportunityWrite) must let this
 * propagate as a real error, never mask it with a mock "success".
 */
export class AuthorityOpportunityTransitionError extends Error {}

async function callAuthorityOpportunityTransition(
  opportunityId: string,
  action: AuthorityOpportunityTransitionAction,
  note?: string,
): Promise<string> {
  const { data, error } = await supabase.rpc(SEO_RPCS.authorityOpportunityTransition, {
    p_opportunity_id: opportunityId,
    p_action: action,
    p_note: note ?? null,
  });
  if (error) {
    throw new AuthorityOpportunityTransitionError(normalizeSupabaseError(error).message);
  }
  return data as string;
}

/**
 * Single-opportunity read by id, used to refresh the row after a successful
 * transition. Same mapping as fetchSupabaseAuthorityOpportunities, just
 * scoped to one row instead of a website's full list.
 */
export async function fetchSupabaseAuthorityOpportunityById(
  id: string,
): Promise<OffPageOpportunity | null> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityById");
  requireValidUuid("seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityById", id, "id");

  const row = await safeSingle<SeoAuthorityOpportunityRow>(
    "seoOffPageAuthoritySupabaseService.fetchSupabaseAuthorityOpportunityById",
    supabase.from(SEO_TABLES.authorityOpportunities).select(OPPORTUNITY_COLUMNS).eq("id", id).maybeSingle(),
  );
  return row ? mapToOffPageOpportunity(row) : null;
}

/**
 * Applies an off-page opportunity workflow action through the Stage 6
 * seo_authority_opportunity_transition RPC — never a direct status UPDATE.
 * The RPC is the only sanctioned path: it enforces the exact
 * action→from-status legality matrix and the role checks (owner/admin/
 * team_member base; reject additionally requires owner/admin) INSIDE the
 * function, and writes the seo_authority_activity audit row server-side.
 * Throws AuthorityOpportunityTransitionError on any RPC rejection — see the
 * class doc above. Returns the refreshed opportunity on success.
 */
export async function transitionSupabaseAuthorityOpportunity(
  id: string,
  action: AuthorityOpportunityTransitionAction,
  note?: string,
): Promise<OffPageOpportunity | null> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityOpportunity");
  requireValidUuid("seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityOpportunity", id, "id");

  await callAuthorityOpportunityTransition(id, action, note);
  return fetchSupabaseAuthorityOpportunityById(id);
}

// =============================================================================
// Phase 15D Step 1B — Atomic draft campaign creation via the
// seo_authority_campaign_create RPC (migration 20260712120024).
//
// Campaign creation has no *transition* RPC (D1/D6 — the two campaign
// transition RPCs only ever move an existing row's approval_status). Phase 15D
// Step 1 originally created a campaign with three separate PostgREST requests
// (campaign INSERT, junction INSERT, task INSERT) plus a best-effort
// client-side compensating DELETE — which is NOT one PostgreSQL transaction and
// could leave a partial campaign if the compensating delete itself failed.
// Step 1B replaces that with a SINGLE call to the guarded SECURITY DEFINER
// seo_authority_campaign_create RPC, which does all three inserts inside one
// PL/pgSQL transaction: any failure rolls the whole call back, leaving zero
// rows. The RPC also resolves workspace_id/website_url server-side, enforces
// the owner/admin/team_member role check, validates the owner value + that every
// opportunity belongs to the same workspace/website, dedupes opportunity ids,
// and always leaves approval_status at its 'draft' column default — never
// 'pending_approval'. Submission for approval and every other campaign
// transition remain out of scope (see PHASE_15B_STAGE6_WRITE_UX_AUDIT.md §4.2).
// =============================================================================

/**
 * Thrown when the seo_authority_campaign_create RPC rejects the call against a
 * real Supabase session — a genuine RLS/role/validation/database rejection,
 * never masked by the mock fallback. Mirrors AuthorityOpportunityTransitionError's
 * contract (see offPageService.ts's runAuthorityCampaignWrite).
 */
export class AuthorityCampaignCreationError extends Error {}

/**
 * Creates one draft campaign atomically via seo_authority_campaign_create, then
 * re-reads it through the existing campaign read mapping so opportunity_ids /
 * tasks / progress_percentage are derived exactly as everywhere else. The RPC
 * returns 'draft' status, junction links, and one task per selected opportunity
 * (label = that opportunity's own suggested_action) — no task/status/owner/
 * workflow behavior is invented here.
 */
export async function createSupabaseAuthorityCampaign(
  website: SeoWebsite,
  input: NewAuthorityCampaignInput,
): Promise<AuthorityCampaign> {
  await requireAuthenticatedUser(
    "seoOffPageAuthoritySupabaseService.createSupabaseAuthorityCampaign",
  );
  requireValidUuid(
    "seoOffPageAuthoritySupabaseService.createSupabaseAuthorityCampaign",
    website.id,
    "website.id",
  );

  const { data, error } = await supabase.rpc(SEO_RPCS.authorityCampaignCreate, {
    p_website_id: website.id,
    p_name: input.name,
    p_goal: input.goal,
    p_owner: input.owner,
    p_due_date: input.due_date ?? null,
    p_opportunity_ids: input.opportunity_ids,
  });
  if (error) {
    throw new AuthorityCampaignCreationError(normalizeSupabaseError(error).message);
  }

  const newCampaignId = data as string;

  // Re-read via the existing mapping (derives opportunity_ids/tasks/progress).
  const campaigns = await fetchSupabaseAuthorityCampaigns(website.id);
  const created = campaigns.find((c) => c.id === newCampaignId);
  if (!created) {
    throw new AuthorityCampaignCreationError(
      "Campaign was created but could not be read back.",
    );
  }
  return created;
}

// =============================================================================
// Phase 15D Step 2A/2B/2C/2D — Campaign transition writes: Draft -> Pending
// Approval (2A), Pending Approval -> Approved (2B), Pending Approval ->
// Rejected (2C), and Rejected -> Draft (2D, via return_to_draft) ONLY. Uses
// the existing, already-TEST-verified seo_authority_campaign_transition RPC
// (migration 20260711120020) — never a direct approval_status UPDATE. The
// RPC's return_to_draft action also legally accepts pending_approval as a
// from-status, but this step's UI intentionally exposes it only from
// rejected (see PHASE_15B_STAGE6_WRITE_UX_AUDIT.md §4.2's scoped rollout).
// The action type below is deliberately narrowed to only the four actions
// wired so far, so nothing else can be called through it without a future,
// deliberate widening.
// =============================================================================

/** Only "submit_for_approval" (2A), "approve" (2B), "reject" (2C), and "return_to_draft" (2D) are wired — see the file-level comment above. */
export type AuthorityCampaignTransitionAction =
  | "submit_for_approval"
  | "approve"
  | "reject"
  | "return_to_draft";

/**
 * Thrown when the seo_authority_campaign_transition RPC itself rejects the
 * call (illegal transition for the campaign's current approval_status, role
 * not permitted, campaign not found, unknown action). Mirrors
 * AuthorityOpportunityTransitionError's contract exactly (see
 * offPageService.ts's runAuthorityCampaignTransitionWrite): callers must let
 * this propagate as a real error, never mask it with a mock "success".
 */
export class AuthorityCampaignTransitionError extends Error {}

async function callAuthorityCampaignTransition(
  campaignId: string,
  action: AuthorityCampaignTransitionAction,
  note?: string,
): Promise<string> {
  const { data, error } = await supabase.rpc(SEO_RPCS.authorityCampaignTransition, {
    p_campaign_id: campaignId,
    p_action: action,
    p_note: note ?? null,
  });
  if (error) {
    throw new AuthorityCampaignTransitionError(normalizeSupabaseError(error).message);
  }
  return data as string;
}

/**
 * Applies a campaign workflow action through the Stage 6
 * seo_authority_campaign_transition RPC — never a direct approval_status
 * UPDATE. Follows the same structure as transitionSupabaseAuthorityOpportunity:
 * call the RPC, then re-read the row. Campaigns have no single-row-by-id fetch
 * (unlike opportunities) because AuthorityCampaign requires derived
 * opportunity_ids/tasks/progress_percentage — so this re-reads via the
 * existing fetchSupabaseAuthorityCampaigns(websiteId) mapping (same read-back
 * approach already used by createSupabaseAuthorityCampaign above) and returns
 * the matching row. Throws AuthorityCampaignTransitionError on any RPC
 * rejection — see the class doc above. Returns the refreshed campaign on
 * success, or null if it can no longer be found (should not happen in
 * practice; transitions never delete a row).
 */
export async function transitionSupabaseAuthorityCampaign(
  id: string,
  websiteId: string,
  action: AuthorityCampaignTransitionAction,
  note?: string,
): Promise<AuthorityCampaign | null> {
  await requireAuthenticatedUser("seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityCampaign");
  requireValidUuid("seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityCampaign", id, "id");
  requireValidUuid(
    "seoOffPageAuthoritySupabaseService.transitionSupabaseAuthorityCampaign",
    websiteId,
    "websiteId",
  );

  await callAuthorityCampaignTransition(id, action, note);

  const campaigns = await fetchSupabaseAuthorityCampaigns(websiteId);
  return campaigns.find((c) => c.id === id) ?? null;
}
