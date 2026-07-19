import type { SeoUserRole } from "@/types";

export interface SeoPermissionSet {
  viewReports: boolean;
  runAudits: boolean;
  manageWebsites: boolean;
  manageBilling: boolean;
  approveRecommendations: boolean;
  requestExpertSupport: boolean;
  manageTeam: boolean;
  manageAdminSettings: boolean;
}

type PermissionBucket = "owner_admin" | "team_member" | "client";

export const SEO_PERMISSION_REGISTRY: Record<PermissionBucket, SeoPermissionSet> = {
  owner_admin: {
    viewReports: true,
    runAudits: true,
    manageWebsites: true,
    manageBilling: true,
    approveRecommendations: true,
    requestExpertSupport: true,
    manageTeam: true,
    manageAdminSettings: true,
  },
  team_member: {
    viewReports: true,
    runAudits: true,
    manageWebsites: false,
    manageBilling: false,
    approveRecommendations: true,
    requestExpertSupport: true,
    manageTeam: false,
    manageAdminSettings: false,
  },
  client: {
    viewReports: true,
    runAudits: true,
    manageWebsites: false,
    manageBilling: false,
    approveRecommendations: true,
    requestExpertSupport: true,
    manageTeam: false,
    manageAdminSettings: false,
  },
};

export function getPermissionsForRole(role: SeoUserRole): SeoPermissionSet {
  if (role === "owner" || role === "admin") return SEO_PERMISSION_REGISTRY.owner_admin;
  if (role === "team_member") return SEO_PERMISSION_REGISTRY.team_member;
  return SEO_PERMISSION_REGISTRY.client;
}
