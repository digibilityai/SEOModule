import type { NewSeoWebsiteInput, SeoWebsite } from "@/types";
import { toAsync } from "@/lib/mockAsync";
import { createWebsite, getWebsiteById, listWebsites } from "@/mocks/websiteMockData";
import { runWithServiceAdapter } from "@/services/serviceAdapter";
import {
  addSupabaseWebsite,
  fetchSupabaseWebsiteById,
  fetchSupabaseWebsites,
} from "@/services/supabase/seoWebsiteSupabaseService";

// `workspaceId` is only meaningful on the mock path (see MOCK_WORKSPACE_ID in
// src/mocks/mockContext.ts). In Supabase mode the workspace is instead
// resolved from the authenticated user's own SEO workspace membership (see
// seoWorkspaceService) — a caller-supplied mock workspace id would not
// correspond to a real row there. See SERVICE_LAYER_WIRING_PLAN.md /
// PHASE_13B_SERVICE_WIRING_NOTES.md.
export async function fetchWebsites(workspaceId: string): Promise<SeoWebsite[]> {
  return runWithServiceAdapter({
    label: "websiteService.fetchWebsites",
    mock: () => toAsync(listWebsites(workspaceId)),
    supabase: () => fetchSupabaseWebsites(),
  });
}

export async function fetchWebsiteById(id: string): Promise<SeoWebsite | null> {
  return runWithServiceAdapter({
    label: "websiteService.fetchWebsiteById",
    mock: () => toAsync(getWebsiteById(id)),
    supabase: () => fetchSupabaseWebsiteById(id),
  });
}

export async function addWebsite(input: NewSeoWebsiteInput): Promise<SeoWebsite> {
  return runWithServiceAdapter({
    label: "websiteService.addWebsite",
    mock: () => toAsync(createWebsite(input)),
    supabase: () => addSupabaseWebsite(input),
  });
}
