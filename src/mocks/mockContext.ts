import type { SeoPlanTier, SeoUserRole } from "@/types";

export const MOCK_WORKSPACE_ID = "wsp_mock_001";
export const MOCK_USER_ID = "usr_mock_admin_001";

// Workspace-level plan used to evaluate website limits until real
// subscription/billing data comes from Supabase.
export const MOCK_CURRENT_PLAN_TIER: SeoPlanTier = "standard";

// Role simulation until real auth/roles exist. Approval Queue lets this be
// previewed as a different role locally without any real auth system.
export const MOCK_CURRENT_ROLE: SeoUserRole = "owner";

export const MOCK_WEBSITES_CONTEXT = [
  { id: "web_mock_001", website_url: "https://www.acmeplumbing.com" },
  { id: "web_mock_002", website_url: "https://www.brightsmiledental.com" },
] as const;
