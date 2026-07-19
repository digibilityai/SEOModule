import type { NewSeoWebsiteInput, SeoWebsite, SeoWorkspace } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const STORAGE_KEY = "websites";

export const mockWorkspace: SeoWorkspace = {
  id: MOCK_WORKSPACE_ID,
  name: "Demo Agency Workspace",
  owner_user_id: MOCK_USER_ID,
  created_at: "2026-05-01T09:00:00.000Z",
  updated_at: "2026-07-01T09:00:00.000Z",
};

const seedWebsites: SeoWebsite[] = [
  {
    id: MOCK_WEBSITES_CONTEXT[0].id,
    workspace_id: MOCK_WORKSPACE_ID,
    user_id: MOCK_USER_ID,
    website_url: MOCK_WEBSITES_CONTEXT[0].website_url,
    name: "Acme Plumbing - Main Site",
    business_name: "Acme Plumbing",
    industry: "Home Services",
    target_location: "Austin, TX",
    website_type: "local_business",
    plan: "standard",
    is_high_risk_industry: false,
    reachable_status: "connected",
    sitemap_status: "connected",
    robots_status: "connected",
    gsc_status: "pending",
    ga4_status: "not_connected",
    cms_status: "not_connected",
    gbp_status: "connected",
    status: "active",
    created_by: MOCK_USER_ID,
    created_at: "2026-06-01T09:00:00.000Z",
    updated_at: "2026-07-01T09:00:00.000Z",
  },
  {
    id: MOCK_WEBSITES_CONTEXT[1].id,
    workspace_id: MOCK_WORKSPACE_ID,
    user_id: MOCK_USER_ID,
    website_url: MOCK_WEBSITES_CONTEXT[1].website_url,
    name: "Bright Smile Dental - Website",
    business_name: "Bright Smile Dental",
    industry: "Healthcare",
    target_location: "Denver, CO",
    website_type: "local_business",
    plan: "basic",
    is_high_risk_industry: true,
    reachable_status: "connected",
    sitemap_status: "connected",
    robots_status: "error",
    gsc_status: "not_connected",
    ga4_status: "not_connected",
    cms_status: "connected",
    gbp_status: "connected",
    status: "active",
    created_by: MOCK_USER_ID,
    created_at: "2026-05-15T09:00:00.000Z",
    updated_at: "2026-07-02T09:00:00.000Z",
  },
];

// Hydrated from localStorage (if present) so websites added via "Add website"
// survive a browser refresh during local/mock-phase testing. Falls back to
// the seed above.
export const mockWebsites: SeoWebsite[] = loadMockCollection(STORAGE_KEY, seedWebsites);

function persist(): void {
  saveMockCollection(STORAGE_KEY, mockWebsites);
}

export function listWebsites(workspaceId: string): SeoWebsite[] {
  return mockWebsites.filter((w) => w.workspace_id === workspaceId);
}

export function getWebsiteById(id: string): SeoWebsite | null {
  return mockWebsites.find((w) => w.id === id) ?? null;
}

export function createWebsite(input: NewSeoWebsiteInput): SeoWebsite {
  const now = new Date().toISOString();
  const website: SeoWebsite = {
    id: `web_mock_${String(mockWebsites.length + 1).padStart(3, "0")}`,
    workspace_id: MOCK_WORKSPACE_ID,
    user_id: MOCK_USER_ID,
    website_url: input.website_url,
    name: input.name,
    business_name: input.business_name,
    industry: input.industry,
    target_location: input.target_location,
    website_type: input.website_type,
    plan: input.plan,
    is_high_risk_industry: false,
    reachable_status: "pending",
    sitemap_status: "not_connected",
    robots_status: "not_connected",
    gsc_status: "not_connected",
    ga4_status: "not_connected",
    cms_status: "not_connected",
    gbp_status: "not_connected",
    status: "active",
    created_by: MOCK_USER_ID,
    created_at: now,
    updated_at: now,
  };
  mockWebsites.push(website);
  persist();
  return website;
}
