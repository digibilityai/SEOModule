// Digibility SEO — sidebar navigation grouping.
//
// Deliberately separate from moduleRegistry.ts: that file describes each SEO
// module's marketing metadata (name/description/plan/priority) and is
// consumed elsewhere (e.g. ModulePlaceholderPage) independent of how the
// sidebar organizes links. This file only defines the collapsible-group
// *shape* of the sidebar and references items by id.
//
// Additive, typed, and small by design — no existing type was changed.
// SEO Dashboard (moduleRegistry id "visibility-dashboard" — see that file's
// comment for why the internal id itself is unchanged) is rendered as a
// standalone first link, outside every group, per product requirement.
export interface SeoNavGroupDef {
  id: string;
  label: string;
  /** Ids resolved against SEO_MODULE_REGISTRY or SEO_EXTRA_NAV_ITEMS, in display order. */
  itemIds: string[];
}

export const SEO_DASHBOARD_MODULE_ID = "visibility-dashboard";

// Pages that exist as real routes but aren't in SEO_MODULE_REGISTRY yet
// (mirrors the previous Sidebar.tsx `extraNavItems`, now with stable ids so
// they can be placed inside a logical group like any registry item).
export interface SeoExtraNavItem {
  id: string;
  label: string;
  route: string;
}

export const SEO_EXTRA_NAV_ITEMS: SeoExtraNavItem[] = [
  { id: "keyword-research", label: "Keyword Research", route: "/seo/keyword-research" },
  { id: "content-gaps", label: "Content Gaps", route: "/seo/content-gaps" },
  { id: "blog-briefs", label: "Blog Briefs", route: "/seo/blog-briefs" },
  { id: "settings", label: "Settings", route: "/seo/settings" },
  // Public Help Center — lives outside /seo/*; no auth/workspace/website/role
  // dependency (see src/pages/help/HelpShell.tsx). Grouped here under
  // Settings & Support since that's its natural home; still an ordinary
  // absolute-path NavLink, unaffected by the SEO module's collapse state
  // logic beyond simply being rendered inside it.
  { id: "help-center", label: "Help Center", route: "/help" },
];

// Order here is the approved information architecture: Setup precedes
// Research; Research/Optimize precede Content; Reports/Settings come last.
// Active (non-placeholder) pages are ordered before not-yet-built
// placeholder pages within a group, per the "don't promote placeholders
// above core functioning pages" rule.
export const SEO_NAV_GROUPS: SeoNavGroupDef[] = [
  {
    id: "setup",
    label: "Setup",
    itemIds: ["seo-setup-connections", "business-onboarding"],
  },
  {
    id: "research-strategy",
    label: "Research & Strategy",
    itemIds: [
      "competitor-benchmarking",
      "90-day-seo-roadmap",
      "keyword-research",
      "content-gaps",
    ],
  },
  {
    id: "audit-optimization",
    label: "Audit & Optimization",
    itemIds: [
      "technical-seo-audit",
      "onpage-seo-autopilot",
      "page-performance-tracker",
      "decline-diagnosis-engine",
    ],
  },
  {
    id: "content",
    label: "Content",
    itemIds: ["content-studio", "blog-briefs"],
  },
  {
    id: "offpage-ai-visibility",
    label: "Off-Page & AI Visibility",
    itemIds: ["offpage-authority-builder", "ai-visibility-geo-engine"],
  },
  {
    id: "reports-workflow",
    label: "Reports & Workflow",
    itemIds: ["approval-queue", "progress-reports"],
  },
  {
    id: "settings-support",
    label: "Settings & Support",
    itemIds: ["settings", "expert-support-desk", "help-center"],
  },
];
