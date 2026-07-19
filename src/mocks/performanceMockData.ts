import type { DeclineDiagnosis, PagePerformance, RefreshRecommendation, SeoWebsite } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const PAGES_KEY = "page_performance";
const DIAGNOSES_KEY = "decline_diagnoses";
const REFRESH_KEY = "refresh_recommendations";

export const DATA_SOURCE_STATUS_MESSAGE =
  "Mock performance data for local testing. GSC/GA4/rank tracking integration will come later.";

const [siteA] = MOCK_WEBSITES_CONTEXT;

// Only siteA has seeded performance data — siteB intentionally has none so
// the "no performance data yet" empty state has something to demonstrate.
const seedPagePerformance: PagePerformance[] = [
  {
    id: "pgp_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    page_title: "Acme Plumbing — Homepage",
    page_url: `${siteA.website_url}/`,
    page_type: "homepage",
    primary_keyword: "emergency plumber austin",
    secondary_keywords: ["24 hour plumber austin", "plumbing company austin"],
    clicks: 320,
    impressions: 5200,
    ctr: 0.0615,
    avg_position: 4.2,
    previous_avg_position: 6.5,
    ranking_movement: 2.3,
    clicks_previous_period: 271,
    impressions_previous_period: 4980,
    previous_ctr: 0.0544,
    traffic_movement_percentage: 18.1,
    performance_status: "improving",
    main_seo_issue: "Homepage loads slowly on mobile, which can undercut this page's rising rankings.",
    recommended_next_action: "Keep an eye on mobile speed so the ranking gains hold.",
  },
  {
    id: "pgp_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    page_title: "Drain Cleaning Services",
    page_url: `${siteA.website_url}/services/drain-cleaning`,
    page_type: "service_page",
    primary_keyword: "drain cleaning service",
    secondary_keywords: ["clogged drain repair", "blocked drain fix"],
    clicks: 42,
    impressions: 1850,
    ctr: 0.0227,
    avg_position: 8.4,
    previous_avg_position: 5.1,
    ranking_movement: -3.3,
    clicks_previous_period: 68,
    impressions_previous_period: 1790,
    previous_ctr: 0.038,
    traffic_movement_percentage: -38.2,
    performance_status: "declining",
    main_seo_issue: "Rankings have slipped for your main drain cleaning keyword.",
    recommended_next_action: "Review the diagnosis below for the likely cause and next step.",
  },
  {
    id: "pgp_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    page_title: "Water Heater Services",
    page_url: `${siteA.website_url}/services/water-heater`,
    page_type: "category_page",
    primary_keyword: "water heater repair austin",
    secondary_keywords: ["water heater installation", "tankless water heater austin"],
    clicks: 55,
    impressions: 2100,
    ctr: 0.0262,
    avg_position: 11.6,
    previous_avg_position: 9.0,
    ranking_movement: -2.6,
    clicks_previous_period: 74,
    impressions_previous_period: 2050,
    previous_ctr: 0.0361,
    traffic_movement_percentage: -25.7,
    performance_status: "declining",
    main_seo_issue: "This page appears to be competing with another page on your own site for the same keyword.",
    recommended_next_action: "Review the diagnosis below for the likely cause and next step.",
  },
  {
    id: "pgp_mock_004",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    page_title: "Emergency Plumbing Checklist for Homeowners",
    page_url: `${siteA.website_url}/blog/emergency-plumbing-checklist`,
    page_type: "blog",
    primary_keyword: "emergency plumber checklist",
    secondary_keywords: ["what to do burst pipe"],
    clicks: 96,
    impressions: 3400,
    ctr: 0.0282,
    avg_position: 12.1,
    previous_avg_position: 11.8,
    ranking_movement: -0.3,
    clicks_previous_period: 101,
    impressions_previous_period: 3600,
    previous_ctr: 0.0281,
    traffic_movement_percentage: -5.0,
    performance_status: "needs_refresh",
    main_seo_issue: "This post hasn't been updated in a while and is starting to feel dated.",
    recommended_next_action: "Refresh the content — see the refresh recommendation below.",
  },
  {
    id: "pgp_mock_005",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    page_title: "Plumbing Services in Round Rock, TX",
    page_url: `${siteA.website_url}/locations/round-rock-tx`,
    page_type: "location_page",
    primary_keyword: "plumber round rock tx",
    secondary_keywords: ["round rock plumbing company"],
    clicks: 61,
    impressions: 1400,
    ctr: 0.0436,
    avg_position: 6.9,
    previous_avg_position: 7.1,
    ranking_movement: 0.2,
    clicks_previous_period: 59,
    impressions_previous_period: 1380,
    previous_ctr: 0.0428,
    traffic_movement_percentage: 3.4,
    performance_status: "stable",
  },
  {
    id: "pgp_mock_006",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:00:00.000Z",
    updated_at: "2026-07-04T09:00:00.000Z",
    page_title: "Spring Drain Cleaning Special",
    page_url: `${siteA.website_url}/promotions/spring-drain-special`,
    page_type: "landing_page",
    primary_keyword: "drain cleaning discount austin",
    secondary_keywords: [],
    clicks: 4,
    impressions: 90,
    ctr: 0.0444,
    avg_position: 0,
    previous_avg_position: 0,
    ranking_movement: 0,
    clicks_previous_period: 0,
    impressions_previous_period: 0,
    previous_ctr: 0,
    traffic_movement_percentage: 0,
    performance_status: "not_enough_data",
    main_seo_issue: "This page was published recently, so there isn't enough search data yet.",
    recommended_next_action: "Check back after a few weeks once more data comes in.",
  },
];

const seedDeclineDiagnoses: DeclineDiagnosis[] = [
  {
    id: "dcl_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:10:00.000Z",
    updated_at: "2026-07-04T09:10:00.000Z",
    page_performance_id: "pgp_mock_002",
    page_url: `${siteA.website_url}/services/drain-cleaning`,
    related_keyword: "drain cleaning service",
    likely_cause: "competitor_improvement",
    confidence_percentage: 72,
    business_explanation:
      "A competitor appears to have published a more detailed page for this service, which may be why you've slipped in the rankings.",
    technical_explanation:
      "Top-ranking competitor pages for this keyword now include pricing, FAQs and before/after photos that this page lacks.",
    recommended_fix:
      "Add pricing guidance, a short FAQ, and a few before/after photos to match the depth competitors now offer.",
    priority: "high",
    fix_owner: "digibility_expert",
    needs_expert_support: true,
  },
  {
    id: "dcl_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:15:00.000Z",
    updated_at: "2026-07-04T09:15:00.000Z",
    page_performance_id: "pgp_mock_003",
    page_url: `${siteA.website_url}/services/water-heater`,
    related_keyword: "water heater repair austin",
    likely_cause: "cannibalization",
    confidence_percentage: 64,
    business_explanation:
      "Another page on your own site seems to be competing with this one for the same search term, which can split your ranking strength.",
    technical_explanation:
      "A blog post targeting a near-identical keyword phrase is also being shown for this query, diluting relevance signals.",
    recommended_fix:
      "Point the blog post toward this service page as the main destination, or narrow the blog post's target keyword.",
    priority: "medium",
    fix_owner: "client_action",
    needs_expert_support: false,
  },
  {
    id: "dcl_mock_003",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:20:00.000Z",
    updated_at: "2026-07-04T09:20:00.000Z",
    page_performance_id: "pgp_mock_004",
    page_url: `${siteA.website_url}/blog/emergency-plumbing-checklist`,
    related_keyword: "emergency plumber checklist",
    likely_cause: "freshness_issue",
    confidence_percentage: 68,
    business_explanation:
      "This post hasn't been updated in a while, and search engines tend to favor content that looks current.",
    technical_explanation:
      "Publish date and referenced pricing/season details are more than a year old with no recent edits.",
    recommended_fix: "Refresh the content with current information and a clearer next step for readers.",
    priority: "medium",
    fix_owner: "client_action",
    needs_expert_support: false,
  },
];

const seedRefreshRecommendations: RefreshRecommendation[] = [
  {
    id: "rfr_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-04T09:20:00.000Z",
    updated_at: "2026-07-04T09:20:00.000Z",
    page_performance_id: "pgp_mock_004",
    page_url: `${siteA.website_url}/blog/emergency-plumbing-checklist`,
    refresh_angle: "Update this checklist for the current year and add local, practical detail.",
    what_to_update: [
      "Publish/updated date and any outdated pricing references",
      "Checklist steps to reflect current best practice",
    ],
    what_to_add: [
      "A short local trust signal (years in business, service area)",
      "A clear FAQ answering the 2-3 most common emergency plumbing questions",
    ],
    what_to_remove: ["Any references to discontinued services or old contact details"],
    suggested_cta_improvement: "Add a same-day emergency booking button near the top of the page.",
    use_content_studio: true,
  },
];

// Guards against stale localStorage from before the Phase 7 schema rewrite
// (old shape used `mapped_keywords` instead of `secondary_keywords`, etc.).
export const mockPagePerformance: PagePerformance[] = loadMockCollection(
  PAGES_KEY,
  seedPagePerformance,
  (item) => Array.isArray(item.secondary_keywords),
);
export const mockDeclineDiagnoses: DeclineDiagnosis[] = loadMockCollection(
  DIAGNOSES_KEY,
  seedDeclineDiagnoses,
);
export const mockRefreshRecommendations: RefreshRecommendation[] = loadMockCollection(
  REFRESH_KEY,
  seedRefreshRecommendations,
);

function persistPages(): void {
  saveMockCollection(PAGES_KEY, mockPagePerformance);
}

export function listPagePerformance(websiteId: string): PagePerformance[] {
  return mockPagePerformance.filter((p) => p.website_id === websiteId);
}

export function getPagePerformanceById(id: string): PagePerformance | null {
  return mockPagePerformance.find((p) => p.id === id) ?? null;
}

export function listDeclineDiagnoses(websiteId: string): DeclineDiagnosis[] {
  return mockDeclineDiagnoses.filter((d) => d.website_id === websiteId);
}

export function listDiagnosesForPage(pageId: string): DeclineDiagnosis[] {
  return mockDeclineDiagnoses.filter((d) => d.page_performance_id === pageId);
}

export function listRefreshRecommendations(websiteId: string): RefreshRecommendation[] {
  return mockRefreshRecommendations.filter((r) => r.website_id === websiteId);
}

export function getRefreshRecommendationForPage(pageId: string): RefreshRecommendation | null {
  return mockRefreshRecommendations.find((r) => r.page_performance_id === pageId) ?? null;
}

// A small, generic starter set used when a website has no performance data
// yet (e.g. it was just added, or a fresh workspace). Deliberately simple —
// real GSC/GA4/rank tracking data will replace this generator later.
export function generatePerformanceDataForWebsite(website: SeoWebsite): PagePerformance[] {
  const existing = listPagePerformance(website.id);
  if (existing.length > 0) return existing;

  const now = new Date().toISOString();
  const businessTerm = website.business_name.toLowerCase();

  const generated: PagePerformance[] = [
    {
      id: `pgp_mock_gen_${website.id}_1`,
      workspace_id: website.workspace_id,
      website_id: website.id,
      website_url: website.website_url,
      user_id: website.user_id,
      created_by: website.user_id,
      created_at: now,
      updated_at: now,
      page_title: `${website.business_name} — Homepage`,
      page_url: `${website.website_url}/`,
      page_type: "homepage",
      primary_keyword: `${businessTerm}${website.target_location ? ` ${website.target_location.split(",")[0].toLowerCase()}` : ""}`,
      secondary_keywords: [businessTerm],
      clicks: 140,
      impressions: 2600,
      ctr: 0.0538,
      avg_position: 7.5,
      previous_avg_position: 7.9,
      ranking_movement: 0.4,
      clicks_previous_period: 132,
      impressions_previous_period: 2500,
      previous_ctr: 0.0528,
      traffic_movement_percentage: 6.1,
      performance_status: "stable",
    },
    {
      id: `pgp_mock_gen_${website.id}_2`,
      workspace_id: website.workspace_id,
      website_id: website.id,
      website_url: website.website_url,
      user_id: website.user_id,
      created_by: website.user_id,
      created_at: now,
      updated_at: now,
      page_title: `${website.business_name} — Our Services`,
      page_url: `${website.website_url}/services`,
      page_type: "service_page",
      primary_keyword: `${businessTerm} services`,
      secondary_keywords: [],
      clicks: 58,
      impressions: 1300,
      ctr: 0.0446,
      avg_position: 10.2,
      previous_avg_position: 10.0,
      ranking_movement: -0.2,
      clicks_previous_period: 60,
      impressions_previous_period: 1280,
      previous_ctr: 0.0469,
      traffic_movement_percentage: -3.3,
      performance_status: "not_enough_data",
      main_seo_issue: "Not enough search history yet to judge this page's trend.",
      recommended_next_action: "Check back after a few more weeks of data.",
    },
  ];

  mockPagePerformance.push(...generated);
  persistPages();
  return generated;
}
