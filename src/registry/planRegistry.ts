import type { AuditFrequency, SeoPlanTier } from "@/types";
import { getModulesForPlan } from "./moduleRegistry";

export interface SeoPlanConfig {
  id: SeoPlanTier;
  name: string;
  websiteLimit: number;
  auditFrequency: AuditFrequency;
  contentOpportunitiesLimit: number | "unlimited";
  contentDraftLimit: number | "unlimited";
  trackedPagesLimit: number;
  trackedKeywordsLimit: number;
  competitorLimit: number;
  aiVisibilityPromptLimit: number | "not_included";
  offPageOpportunityLimit: number | "checklist_only" | "advanced_campaigns";
  expertSupportAccess: "paid_add_on" | "limited_included" | "priority_bundled";
  moduleAccess: string[];
}

export const SEO_PLAN_REGISTRY: Record<SeoPlanTier, SeoPlanConfig> = {
  basic: {
    id: "basic",
    name: "Basic",
    websiteLimit: 1,
    auditFrequency: "monthly",
    contentOpportunitiesLimit: 3,
    contentDraftLimit: 2,
    trackedPagesLimit: 50,
    trackedKeywordsLimit: 25,
    competitorLimit: 2,
    aiVisibilityPromptLimit: "not_included",
    offPageOpportunityLimit: "checklist_only",
    expertSupportAccess: "paid_add_on",
    moduleAccess: getModulesForPlan("basic").map((m) => m.id),
  },
  standard: {
    id: "standard",
    name: "Standard",
    websiteLimit: 3,
    auditFrequency: "weekly",
    contentOpportunitiesLimit: 10,
    contentDraftLimit: 5,
    trackedPagesLimit: 250,
    trackedKeywordsLimit: 150,
    competitorLimit: 5,
    aiVisibilityPromptLimit: 10,
    offPageOpportunityLimit: 50,
    expertSupportAccess: "limited_included",
    moduleAccess: getModulesForPlan("standard").map((m) => m.id),
  },
  pro: {
    id: "pro",
    name: "Pro",
    websiteLimit: 10,
    auditFrequency: "weekly_plus_change_monitoring",
    contentOpportunitiesLimit: "unlimited",
    contentDraftLimit: 15,
    trackedPagesLimit: 1000,
    trackedKeywordsLimit: 1000,
    competitorLimit: 10,
    aiVisibilityPromptLimit: 100,
    offPageOpportunityLimit: "advanced_campaigns",
    expertSupportAccess: "priority_bundled",
    moduleAccess: getModulesForPlan("pro").map((m) => m.id),
  },
};

export function getPlanConfig(plan: SeoPlanTier): SeoPlanConfig {
  return SEO_PLAN_REGISTRY[plan];
}

export function planIncludesModule(plan: SeoPlanTier, moduleId: string): boolean {
  return SEO_PLAN_REGISTRY[plan].moduleAccess.includes(moduleId);
}
