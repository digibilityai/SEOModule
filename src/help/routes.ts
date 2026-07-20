// Digibility SEO Help Center — approved contextual-help route constants.
// Each value is a public, published article path under the
// authentication-free /help/article/:articleSlug route (see
// src/routes/SeoRoutes.tsx). Every slug below is verified against the real
// published corpus in src/help/content/index.ts (published===true,
// visibility==="public") — not the earlier speculative Phase-1 mapping doc.
//
// Deliberately minimal: only routes actually used by a contextual-help link
// somewhere in src/pages/seo/**, no generic URL builder, no unused entries,
// no internal-article routes (internal.ts's support-diagnostic-runbook-internal
// is never reachable via publicArticles() and must never appear here).
//
// Wave 2B (first batch): GETTING_STARTED, ADDING_WEBSITE, BUSINESS_ONBOARDING,
// SIGN_IN_ACCESS. Wave 2C (remaining unlocked placements): APPROVAL_WORKFLOW,
// DECLINE_DIAGNOSIS, DIGIBILITY_OPERATING_MODEL, FEATURE_AVAILABILITY.
export const HELP_ROUTES = {
  GETTING_STARTED: "/help/article/getting-started-with-digibility-seo",
  ADDING_WEBSITE: "/help/article/adding-a-website",
  BUSINESS_ONBOARDING: "/help/article/completing-business-onboarding",
  SIGN_IN_ACCESS: "/help/article/signing-in-and-access-states",
  APPROVAL_WORKFLOW: "/help/article/the-approval-workflow",
  DECLINE_DIAGNOSIS: "/help/article/investigating-traffic-ranking-decline",
  DIGIBILITY_OPERATING_MODEL:
    "/help/article/how-digibility-connects-insights-actions-approvals-reporting",
  FEATURE_AVAILABILITY: "/help/article/preview-data-versus-live-data",
} as const;
