import type { SeoUserRole } from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { SEO_TABLES } from "@/services/supabase/supabaseTypes";
import {
  getCurrentUserId,
  requireAuthenticatedUser,
  requireValidUuid,
} from "@/services/supabase/supabaseServiceUtils";
import { normalizeSupabaseError } from "@/services/supabase/supabaseErrors";

export interface SeoWorkspaceRecord {
  id: string;
  name: string;
  owner_user_id: string;
  created_at: string;
  updated_at: string;
}

export interface SeoWorkspaceResolution {
  workspace: SeoWorkspaceRecord | null;
  /** Present when `workspace` is null — a clear, dev-facing reason why. */
  reason?: string;
}

const DEFAULT_WORKSPACE_NAME = "My SEO Workspace";
const NO_MEMBERSHIP_REASON = "Authenticated user has no SEO workspace membership yet.";

/**
 * Reads the current Supabase user's SEO workspace membership (Stage 1
 * `seo_workspace_members`) and returns the most-recently-created active
 * membership's workspace. Read-only — never creates anything. Requires an
 * authenticated user; never throws — returns `{ workspace: null, reason }`
 * for every failure case (no session, no membership, RLS/network error) so
 * callers can fall back to mock data safely.
 *
 * Ordering matters: a test user can legitimately belong to several SEO
 * workspaces at once (e.g. a smoke test's disposable workspace plus the UI
 * seed dataset's workspace, when the guides recommend reusing the same test
 * user across them). Without an explicit ORDER BY, `.limit(1)` returns
 * whichever row Postgres happens to scan first — non-deterministic in
 * practice, and easy to land on a stale/older workspace instead of the one
 * the developer actually means to be working in "right now". Ordering by
 * the membership's own `created_at` (most recent join wins) is the
 * deterministic, sensible default until the app has a real workspace
 * switcher.
 */
export async function getCurrentSeoWorkspace(): Promise<SeoWorkspaceResolution> {
  const userId = await getCurrentUserId();
  if (!userId) {
    return { workspace: null, reason: "No authenticated Supabase user (session missing)." };
  }

  try {
    const { data: memberRows, error: memberError } = await supabase
      .from(SEO_TABLES.workspaceMembers)
      .select("workspace_id")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(1);

    if (memberError) {
      return {
        workspace: null,
        reason: `Could not read SEO workspace membership: ${normalizeSupabaseError(memberError).message}`,
      };
    }

    const workspaceId = memberRows?.[0]?.workspace_id as string | undefined;
    if (!workspaceId) {
      return { workspace: null, reason: NO_MEMBERSHIP_REASON };
    }

    const { data: workspace, error: workspaceError } = await supabase
      .from(SEO_TABLES.workspaces)
      .select("id, name, owner_user_id, created_at, updated_at")
      .eq("id", workspaceId)
      .maybeSingle();

    if (workspaceError) {
      return {
        workspace: null,
        reason: `Could not read SEO workspace: ${normalizeSupabaseError(workspaceError).message}`,
      };
    }

    return { workspace: (workspace as SeoWorkspaceRecord | null) ?? null };
  } catch (error) {
    return { workspace: null, reason: normalizeSupabaseError(error).message };
  }
}

const VALID_SEO_USER_ROLES: ReadonlySet<string> = new Set([
  "owner",
  "admin",
  "team_member",
  "client",
]);

function isSeoUserRole(value: unknown): value is SeoUserRole {
  return typeof value === "string" && VALID_SEO_USER_ROLES.has(value);
}

/**
 * Reads the current Supabase user's real, RLS-backed `seo_role` for one
 * specific workspace (Stage 1 `seo_workspace_members.seo_role` — the
 * authorization source every Stage 6 transition RPC and RLS policy actually
 * checks via `seo_role_in()`/`can_manage_seo_workspace()`). Read-only — a
 * single `SELECT seo_role FROM seo_workspace_members WHERE workspace_id = ?
 * AND user_id = auth.uid() AND status = 'active'`, permitted by the existing
 * `seo_workspace_members_select` RLS policy (any active member may read
 * their own workspace's member list) — no RLS change, no service-role
 * credential, no migration.
 *
 * Returns `null` ONLY when the query succeeds and finds no active
 * membership row for this user in this workspace (a legitimate, expected
 * outcome — e.g. a non-member, or a `status` of `invited`/`suspended`/
 * `removed`). Every other failure — no authenticated session, an invalid
 * `workspaceId`, a network/RLS error, or (defensively) an unrecognized
 * `seo_role` value that doesn't match the `SeoUserRole` union — throws a
 * clear, labeled `Error` instead of silently returning `null`, so a caller
 * can never mistake "couldn't check" for "confirmed no role." Never falls
 * back to `MOCK_CURRENT_ROLE` or any other mock value — Supabase mode
 * either returns the real row or throws.
 */
export async function getCurrentSeoRole(workspaceId: string): Promise<SeoUserRole | null> {
  const userId = await requireAuthenticatedUser("seoWorkspaceService.getCurrentSeoRole");
  requireValidUuid("seoWorkspaceService.getCurrentSeoRole", workspaceId, "workspaceId");

  const { data, error } = await supabase
    .from(SEO_TABLES.workspaceMembers)
    .select("seo_role")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();

  if (error) {
    throw new Error(`seoWorkspaceService.getCurrentSeoRole: ${normalizeSupabaseError(error).message}`);
  }

  if (!data) {
    return null;
  }

  if (!isSeoUserRole(data.seo_role)) {
    throw new Error(
      `seoWorkspaceService.getCurrentSeoRole: unexpected seo_role value "${data.seo_role}" — expected one of owner/admin/team_member/client.`,
    );
  }

  return data.seo_role;
}

export interface SeoAccessibleWorkspace {
  id: string;
  name: string;
}

/**
 * Lists every SEO workspace the current Supabase user is an active member
 * of (not just the single "current" one `getCurrentSeoWorkspace` resolves),
 * most-recently-created first. Read-only, never creates anything. Returns
 * an empty array for every failure case (no session, no membership,
 * RLS/network error) — callers should treat that as "nothing accessible",
 * not as an error to surface.
 *
 * Exists for dev/diagnostic tooling and Page-Performance-style "find a
 * website with real data" searches, where a test user legitimately belongs
 * to several disposable workspaces (smoke tests + the UI seed dataset) and
 * needs to look across all of them, not just whichever one
 * `getCurrentSeoWorkspace` happens to prefer by default.
 */
export async function listAccessibleSeoWorkspaces(): Promise<SeoAccessibleWorkspace[]> {
  const userId = await getCurrentUserId();
  if (!userId) return [];

  const { data: memberRows, error: memberError } = await supabase
    .from(SEO_TABLES.workspaceMembers)
    .select("workspace_id")
    .eq("user_id", userId)
    .eq("status", "active");
  if (memberError || !memberRows || memberRows.length === 0) return [];

  const workspaceIds = [...new Set(memberRows.map((row) => row.workspace_id as string))];

  const { data: workspaceRows, error: workspaceError } = await supabase
    .from(SEO_TABLES.workspaces)
    .select("id, name, created_at")
    .in("id", workspaceIds)
    .order("created_at", { ascending: false });
  if (workspaceError || !workspaceRows) return [];

  return workspaceRows.map((row) => ({ id: row.id as string, name: row.name as string }));
}

/**
 * Returns the current user's SEO workspace, creating one simple default
 * workspace only when the user has no membership at all yet (never on a
 * read error/timeout, to avoid creating a duplicate on a transient failure).
 *
 * Relies entirely on the Stage 1 `seo_workspace_add_owner_member` AFTER
 * INSERT trigger to add the creator as an active 'owner' member — this
 * function does not insert into `seo_workspace_members` itself.
 *
 * Requires an authenticated Supabase user and active `user_module_access`
 * (module='seo') — the Stage 1 `seo_workspaces_insert` RLS policy enforces
 * this. If either is missing, or the insert otherwise fails, this returns
 * `{ workspace: null, reason }` — it never throws and never fakes auth.
 */
export async function getOrCreateDefaultSeoWorkspace(): Promise<SeoWorkspaceResolution> {
  const existing = await getCurrentSeoWorkspace();
  if (existing.workspace) {
    return existing;
  }

  // Only attempt creation when we positively know there's no membership yet.
  // Any other failure reason (no session, read error) is returned as-is.
  if (existing.reason !== NO_MEMBERSHIP_REASON) {
    return existing;
  }

  const userId = await getCurrentUserId();
  if (!userId) {
    return { workspace: null, reason: "No authenticated Supabase user (session missing)." };
  }

  try {
    const { data: created, error: createError } = await supabase
      .from(SEO_TABLES.workspaces)
      .insert({ name: DEFAULT_WORKSPACE_NAME, owner_user_id: userId })
      .select("id, name, owner_user_id, created_at, updated_at")
      .single();

    if (createError) {
      return {
        workspace: null,
        reason: `Could not create a default SEO workspace: ${normalizeSupabaseError(createError).message}`,
      };
    }

    return { workspace: created as SeoWorkspaceRecord };
  } catch (error) {
    return { workspace: null, reason: normalizeSupabaseError(error).message };
  }
}
