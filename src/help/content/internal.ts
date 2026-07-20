import type { HelpArticle } from "../types";

/**
 * Internal-only content. MUST NEVER appear in the public search index, public
 * category pages, the public homepage, or be reachable via a public article
 * route. Exists in Slice 1 specifically to prove the public/internal
 * separation boundary works end-to-end (see validate.ts and the public route
 * not-found tests).
 */
export const INTERNAL_ARTICLES: HelpArticle[] = [
  {
    id: "support-diagnostic-runbook-internal",
    slug: "support-diagnostic-runbook-internal",
    title: "Support diagnostic runbook (internal)",
    summary: "Internal-only safe diagnostic sequence for the support team. Not for customer access.",
    body: [
      { type: "warning", text: "Internal use only. This content must never be exposed through a public route." },
      { type: "steps", items: [
        "Confirm the reporter's data mode (mock vs Supabase).",
        "Confirm the active website and role.",
        "Reproduce the reported state.",
        "Read the on-screen message verbatim.",
        "Map to the public troubleshooting catalogue before escalating internally.",
      ] },
    ],
    category: "contact-support",
    contentType: "support_runbook",
    audienceRoles: ["internal"],
    level: "beginner",
    productArea: "support-ops",
    featureStatus: "internal_only",
    estimatedReadingMinutes: 2,
    tags: ["internal", "runbook", "support"],
    searchAliases: [],
    relatedArticleIds: [],
    relevantRoutes: [],
    priority: "P0",
    lastReviewed: "2026-07-19",
    version: "1",
    published: true,
    visibility: "internal",
  },
];
