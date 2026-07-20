import type { SeoModule, SeoPlanTier } from "@/types";

export const SEO_MODULE_REGISTRY: SeoModule[] = [
  {
    id: "seo-setup-connections",
    name: "SEO Setup & Connections",
    shortDescription:
      "Add a website, check sitemap/robots, and prepare GSC, GA4, CMS and GBP connections.",
    route: "/seo/websites",
    priority: 1,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "business-onboarding",
    name: "Business Onboarding",
    shortDescription:
      "Collect business context so SEO recommendations aren't generic.",
    route: "/seo/onboarding",
    priority: 2,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    // Internal id kept as "visibility-dashboard" for backward compatibility
    // (it is not user-visible — see src/registry/navigationGroups.ts and
    // DIGIBILITY_SEO_COLLAPSIBLE_NAVIGATION_INFORMATION_ARCHITECTURE.md for
    // the terminology decision). The user-facing name below is "SEO
    // Dashboard": "Visibility" is a separate Digibility module and must not
    // be used as a synonym for SEO.
    id: "visibility-dashboard",
    name: "SEO Dashboard",
    shortDescription:
      "Overall visibility score, sub-scores, top fixes and recent activity.",
    route: "/seo/dashboard",
    priority: 3,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "technical-seo-audit",
    name: "Technical SEO Audit",
    shortDescription:
      "Crawl, indexing, speed, mobile, schema and other technical issues.",
    route: "/seo/audit",
    priority: 4,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "onpage-seo-autopilot",
    name: "On-Page SEO Autopilot",
    shortDescription:
      "Title, meta, headings, FAQs, schema and internal link suggestions.",
    route: "/seo/page-optimizer",
    priority: 5,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "approval-queue",
    name: "Approval Queue",
    shortDescription:
      "Approve, reject, edit or route recommendations before anything goes live.",
    route: "/seo/approvals",
    priority: 6,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "content-studio",
    name: "Content Studio",
    shortDescription:
      "Content opportunities, keyword plan, wireframe approval and draft review.",
    route: "/seo/content-studio",
    priority: 7,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "page-performance-tracker",
    name: "Page Performance Tracker",
    shortDescription:
      "Page inventory, mapped keywords, clicks, impressions and CTR.",
    route: "/seo/page-performance",
    priority: 8,
    planAvailability: ["standard", "pro"],
    status: "active",
  },
  {
    id: "decline-diagnosis-engine",
    name: "Decline Diagnosis Engine",
    shortDescription:
      "Diagnose ranking or CTR decline and recommend a fix.",
    route: "/seo/decline-diagnosis",
    priority: 9,
    planAvailability: ["standard", "pro"],
    status: "active",
  },
  {
    id: "offpage-authority-builder",
    name: "Off-Page Authority Builder",
    shortDescription:
      "Safe backlink, mention, citation, review and PR opportunities.",
    route: "/seo/off-page",
    priority: 10,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "ai-visibility-geo-engine",
    name: "AI Visibility / GEO Engine",
    shortDescription:
      "Brand and competitor mentions in AI answers, prompt tracking and gaps.",
    route: "/seo/ai-visibility",
    priority: 11,
    planAvailability: ["standard", "pro"],
    status: "active",
  },
  {
    id: "competitor-benchmarking",
    name: "Competitor Benchmarking",
    shortDescription:
      "Compare technical, content, authority and AI visibility vs competitors.",
    route: "/seo/competitor-analysis",
    priority: 12,
    planAvailability: ["standard", "pro"],
    status: "active",
  },
  {
    id: "90-day-seo-roadmap",
    name: "90-Day SEO Roadmap",
    shortDescription:
      "Weekly actions and monthly milestones with owner and priority.",
    route: "/seo/roadmap",
    priority: 13,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "expert-support-desk",
    name: "Expert Support Desk",
    shortDescription:
      "Request Digibility help for technical, content, off-page or strategy work.",
    route: "/seo/support",
    priority: 14,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
  {
    id: "seo-guardrail-monitor",
    name: "SEO Guardrail Monitor",
    shortDescription:
      "Watches for risky changes like noindex, canonical, redirect or robots.txt edits.",
    route: "/seo/guardrail",
    priority: 15,
    planAvailability: ["standard", "pro"],
    status: "later",
  },
  {
    id: "content-trust-review",
    name: "Content Trust Review",
    shortDescription:
      "Flags risky claims and missing proof, especially in high-risk industries.",
    route: "/seo/content-trust",
    priority: 16,
    planAvailability: ["basic", "standard", "pro"],
    status: "later",
  },
  {
    id: "progress-reports",
    name: "Progress Reports",
    shortDescription:
      "Client-friendly summary of what improved, what shipped and what's next.",
    route: "/seo/reports",
    priority: 17,
    planAvailability: ["basic", "standard", "pro"],
    status: "active",
  },
];

export function getModuleById(id: string): SeoModule | undefined {
  return SEO_MODULE_REGISTRY.find((m) => m.id === id);
}

export function getModuleByRoute(route: string): SeoModule | undefined {
  return SEO_MODULE_REGISTRY.find((m) => m.route === route);
}

export function getModulesForPlan(plan: SeoPlanTier): SeoModule[] {
  return SEO_MODULE_REGISTRY.filter((m) => m.planAvailability.includes(plan));
}
