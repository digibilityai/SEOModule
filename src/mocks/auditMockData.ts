import type { SeoAudit, SeoIssue, SeoIssueCategory, SeverityLevel } from "@/types";
import { MOCK_USER_ID, MOCK_WORKSPACE_ID, MOCK_WEBSITES_CONTEXT } from "./mockContext";
import { loadMockCollection, saveMockCollection } from "@/lib/localMockStore";

const AUDITS_STORAGE_KEY = "audits";
const ISSUES_STORAGE_KEY = "issues";

const [siteA, siteB] = MOCK_WEBSITES_CONTEXT;

const seedAudits: SeoAudit[] = [
  {
    id: "aud_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T09:00:00.000Z",
    updated_at: "2026-07-01T09:45:00.000Z",
    frequency: "monthly",
    status: "completed",
    overall_visibility_score: 62,
    technical_health_score: 71,
    onpage_score: 58,
    authority_score: 44,
    ai_discovery_score: 30,
    issue_count: 1,
    started_at: "2026-07-01T09:00:00.000Z",
    completed_at: "2026-07-01T09:45:00.000Z",
  },
  {
    id: "aud_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T09:00:00.000Z",
    updated_at: "2026-07-03T09:40:00.000Z",
    frequency: "weekly",
    status: "completed",
    overall_visibility_score: 48,
    technical_health_score: 55,
    onpage_score: 40,
    authority_score: 52,
    ai_discovery_score: 20,
    issue_count: 1,
    started_at: "2026-07-03T09:00:00.000Z",
    completed_at: "2026-07-03T09:40:00.000Z",
  },
];

const seedIssues: SeoIssue[] = [
  {
    id: "iss_mock_001",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteA.id,
    website_url: siteA.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-01T09:45:00.000Z",
    updated_at: "2026-07-01T09:45:00.000Z",
    audit_id: "aud_mock_001",
    category: "speed",
    severity: "high",
    title: "Homepage loads slowly on mobile",
    simple_explanation: "Your homepage loads slowly on mobile, which can lose visitors.",
    why_it_matters:
      "Slow pages lose visitors before they even see your services, and can lower your search ranking.",
    technical_explanation: "LCP is 4.2s on mobile, above the 2.5s recommended threshold.",
    affected_page_url: `${siteA.website_url}/`,
    impact: "high",
    effort: "medium",
    risk: "low",
    confidence_percentage: 85,
    fix_owner: "developer_needed",
    suggested_next_action: "Compress hero image and enable lazy loading.",
    status: "open",
  },
  {
    id: "iss_mock_002",
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: siteB.id,
    website_url: siteB.website_url,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: "2026-07-03T09:40:00.000Z",
    updated_at: "2026-07-03T09:40:00.000Z",
    audit_id: "aud_mock_002",
    category: "robots_txt",
    severity: "high",
    title: "Robots.txt is blocking key pages",
    simple_explanation: "Your robots.txt file is blocking search engines from key pages.",
    why_it_matters:
      "If search engines can't crawl these pages, they won't show up in search at all, no matter how good the content is.",
    technical_explanation: "Disallow: /services blocks crawling of indexable service pages.",
    affected_page_url: `${siteB.website_url}/robots.txt`,
    impact: "high",
    effort: "low",
    risk: "medium",
    confidence_percentage: 87,
    fix_owner: "digibility_expert",
    suggested_next_action: "Remove the /services disallow rule after client approval.",
    status: "open",
  },
];

export const mockAudits: SeoAudit[] = loadMockCollection(AUDITS_STORAGE_KEY, seedAudits);
export const mockIssues: SeoIssue[] = loadMockCollection(ISSUES_STORAGE_KEY, seedIssues);

function persistAudits(): void {
  saveMockCollection(AUDITS_STORAGE_KEY, mockAudits);
}

function persistIssues(): void {
  saveMockCollection(ISSUES_STORAGE_KEY, mockIssues);
}

export function listAudits(websiteId: string): SeoAudit[] {
  return mockAudits.filter((a) => a.website_id === websiteId);
}

export function getLatestAudit(websiteId: string): SeoAudit | null {
  const audits = listAudits(websiteId).sort(
    (a, b) =>
      new Date(b.completed_at ?? b.started_at).getTime() -
      new Date(a.completed_at ?? a.started_at).getTime(),
  );
  return audits[0] ?? null;
}

export function getAuditById(id: string): SeoAudit | null {
  return mockAudits.find((a) => a.id === id) ?? null;
}

export function listIssuesForAudit(auditId: string): SeoIssue[] {
  return mockIssues.filter((i) => i.audit_id === auditId);
}

interface IssueTemplate {
  category: SeoIssueCategory;
  severity: SeverityLevel;
  title: string;
  simple_explanation: string;
  why_it_matters: string;
  technical_explanation: string;
  pagePath: string;
  impact: SeoIssue["impact"];
  effort: SeoIssue["effort"];
  risk: SeoIssue["risk"];
  confidence_percentage: number;
  fix_owner: SeoIssue["fix_owner"];
  suggested_next_action: string;
}

const ISSUE_TEMPLATES: IssueTemplate[] = [
  {
    category: "crawl",
    severity: "high",
    title: "Search engines are wasting time on low-value pages",
    simple_explanation: "Some pages are eating into the time search engines spend crawling your site.",
    why_it_matters:
      "When crawl budget is wasted on unimportant pages, your important pages get crawled and updated less often.",
    technical_explanation:
      "Crawl budget is being spent on duplicate parameter URLs (e.g. ?sort=, ?ref=).",
    pagePath: "/products?sort=price",
    impact: "medium",
    effort: "medium",
    risk: "low",
    confidence_percentage: 82,
    fix_owner: "developer_needed",
    suggested_next_action: "Add crawl rules to skip duplicate parameter URLs.",
  },
  {
    category: "indexability",
    severity: "critical",
    title: "An important page isn't showing up in Google",
    simple_explanation: "One of your key pages isn't eligible to appear in search results.",
    why_it_matters: "A page that can't be indexed gets zero organic traffic, no matter how good it is.",
    technical_explanation: "This page returns a noindex meta tag, likely left over from staging.",
    pagePath: "/services",
    impact: "high",
    effort: "low",
    risk: "medium",
    confidence_percentage: 90,
    fix_owner: "digibility_expert",
    suggested_next_action: "Remove the noindex tag after confirming it isn't intentional.",
  },
  {
    category: "speed",
    severity: "high",
    title: "Your site loads slowly on mobile phones",
    simple_explanation: "Visitors on phones wait longer than they should for your pages to load.",
    why_it_matters: "Slow load times increase bounce rate and can lower your mobile search ranking.",
    technical_explanation: "Largest Contentful Paint (LCP) is 4.1s on mobile, above the 2.5s target.",
    pagePath: "/",
    impact: "high",
    effort: "medium",
    risk: "low",
    confidence_percentage: 85,
    fix_owner: "developer_needed",
    suggested_next_action: "Compress images and enable lazy loading for offscreen content.",
  },
  {
    category: "mobile",
    severity: "medium",
    title: "Some pages are hard to use on phones",
    simple_explanation: "Buttons and text are cramped on mobile screens.",
    why_it_matters: "A frustrating mobile experience drives visitors away before they contact you.",
    technical_explanation:
      "Tap targets are too close together and body text is smaller than 12px on mobile viewports.",
    pagePath: "/contact",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 78,
    fix_owner: "developer_needed",
    suggested_next_action: "Increase button spacing and base font size on mobile.",
  },
  {
    category: "schema",
    severity: "low",
    title: "Search engines can't confirm your business details",
    simple_explanation: "Your business info isn't marked up in a way search engines fully understand.",
    why_it_matters:
      "Structured data helps show rich results like hours, ratings and address directly in search.",
    technical_explanation: "LocalBusiness structured data is missing on the homepage and contact page.",
    pagePath: "/contact",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 80,
    fix_owner: "system_suggestion",
    suggested_next_action: "Add LocalBusiness schema markup with your address and hours.",
  },
  {
    category: "duplicate_content",
    severity: "medium",
    title: "A couple of pages have nearly identical content",
    simple_explanation: "Two pages say almost the same thing, which can confuse search engines.",
    why_it_matters: "Duplicate content can split ranking signals between pages instead of strengthening one.",
    technical_explanation: "Two service pages share 90%+ of their text.",
    pagePath: "/services/duplicate-page",
    impact: "medium",
    effort: "medium",
    risk: "low",
    confidence_percentage: 74,
    fix_owner: "client_action",
    suggested_next_action: "Rewrite one page to focus on a different service angle.",
  },
  {
    category: "broken_links",
    severity: "medium",
    title: "Some links lead to pages that no longer exist",
    simple_explanation: "A few links on your site are dead ends for visitors.",
    why_it_matters: "Broken links frustrate visitors and waste the crawl budget search engines give your site.",
    technical_explanation: "3 internal links return a 404 status code.",
    pagePath: "/blog/old-post",
    impact: "medium",
    effort: "low",
    risk: "low",
    confidence_percentage: 92,
    fix_owner: "developer_needed",
    suggested_next_action: "Update or remove the broken links.",
  },
  {
    category: "sitemap",
    severity: "low",
    title: "Your sitemap is missing a few pages",
    simple_explanation: "Some pages aren't listed in the file that tells search engines what to crawl.",
    why_it_matters: "Pages missing from the sitemap can take longer to get discovered and indexed.",
    technical_explanation: "2 recently published pages aren't listed in sitemap.xml.",
    pagePath: "/sitemap.xml",
    impact: "low",
    effort: "low",
    risk: "low",
    confidence_percentage: 88,
    fix_owner: "system_suggestion",
    suggested_next_action: "Regenerate the sitemap to include the missing pages.",
  },
  {
    category: "robots_txt",
    severity: "high",
    title: "Your robots.txt file may be blocking pages you want found",
    simple_explanation: "A settings file is telling search engines to skip part of your site.",
    why_it_matters: "Blocked sections get zero organic visibility even if the content is excellent.",
    technical_explanation:
      "Disallow: /services blocks crawling of an indexable, revenue-driving section.",
    pagePath: "/robots.txt",
    impact: "high",
    effort: "low",
    risk: "medium",
    confidence_percentage: 87,
    fix_owner: "digibility_expert",
    suggested_next_action: "Remove the disallow rule after confirming it's safe.",
  },
  {
    category: "canonical",
    severity: "medium",
    title: "Some pages point search engines to the wrong 'main' version",
    simple_explanation: "A page is telling search engines that a different page is the real one.",
    why_it_matters: "This can cause the wrong page to rank, or neither page to rank well.",
    technical_explanation: "Canonical tag on /services points to the homepage instead of itself.",
    pagePath: "/services",
    impact: "medium",
    effort: "low",
    risk: "medium",
    confidence_percentage: 79,
    fix_owner: "digibility_expert",
    suggested_next_action: "Correct the canonical tag to reference the page itself.",
  },
  {
    category: "redirects",
    severity: "low",
    title: "Some old links redirect through extra steps",
    simple_explanation: "A few links bounce through more than one redirect before landing.",
    why_it_matters: "Redirect chains slow down page loads and waste a little bit of ranking strength.",
    technical_explanation: "3 URLs redirect twice before reaching the final page.",
    pagePath: "/old-page",
    impact: "low",
    effort: "medium",
    risk: "low",
    confidence_percentage: 76,
    fix_owner: "developer_needed",
    suggested_next_action: "Update links to point directly to the final URL.",
  },
];

const SEVERITY_PENALTY: Record<SeverityLevel, number> = {
  critical: 15,
  high: 8,
  medium: 4,
  low: 1,
};

function clampScore(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function nudge(base: number, spread = 6): number {
  return clampScore(base + (Math.random() * spread * 2 - spread));
}

export function generateAuditRun(
  websiteId: string,
  websiteUrl: string,
): { audit: SeoAudit; issues: SeoIssue[] } {
  const now = new Date().toISOString();
  const previous = getLatestAudit(websiteId);

  const technicalHealthScore = clampScore(
    100 - ISSUE_TEMPLATES.reduce((sum, t) => sum + SEVERITY_PENALTY[t.severity], 0),
  );

  const audit: SeoAudit = {
    id: `aud_mock_${String(mockAudits.length + 1).padStart(3, "0")}`,
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: websiteId,
    website_url: websiteUrl,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: now,
    updated_at: now,
    frequency: previous?.frequency ?? "monthly",
    status: "completed",
    overall_visibility_score: previous ? nudge(previous.overall_visibility_score) : nudge(58, 10),
    technical_health_score: technicalHealthScore,
    onpage_score: previous ? nudge(previous.onpage_score) : nudge(55, 10),
    authority_score: previous ? nudge(previous.authority_score) : nudge(45, 10),
    ai_discovery_score: previous ? nudge(previous.ai_discovery_score) : nudge(28, 10),
    issue_count: ISSUE_TEMPLATES.length,
    started_at: now,
    completed_at: now,
  };

  const issues: SeoIssue[] = ISSUE_TEMPLATES.map((template, index) => ({
    id: `iss_mock_${audit.id}_${index + 1}`,
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: websiteId,
    website_url: websiteUrl,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: now,
    updated_at: now,
    audit_id: audit.id,
    category: template.category,
    severity: template.severity,
    title: template.title,
    simple_explanation: template.simple_explanation,
    why_it_matters: template.why_it_matters,
    technical_explanation: template.technical_explanation,
    affected_page_url: `${websiteUrl}${template.pagePath}`,
    impact: template.impact,
    effort: template.effort,
    risk: template.risk,
    confidence_percentage: template.confidence_percentage,
    fix_owner: template.fix_owner,
    suggested_next_action: template.suggested_next_action,
    status: "open",
  }));

  mockAudits.push(audit);
  const remainingIssues = mockIssues.filter((i) => i.website_id !== websiteId);
  mockIssues.length = 0;
  mockIssues.push(...remainingIssues, ...issues);

  persistAudits();
  persistIssues();

  return { audit, issues };
}

export function recordFailedAudit(websiteId: string, websiteUrl: string): SeoAudit {
  const now = new Date().toISOString();
  const previous = getLatestAudit(websiteId);

  const audit: SeoAudit = {
    id: `aud_mock_${String(mockAudits.length + 1).padStart(3, "0")}`,
    workspace_id: MOCK_WORKSPACE_ID,
    website_id: websiteId,
    website_url: websiteUrl,
    user_id: MOCK_USER_ID,
    created_by: MOCK_USER_ID,
    created_at: now,
    updated_at: now,
    frequency: previous?.frequency ?? "monthly",
    status: "failed",
    overall_visibility_score: previous?.overall_visibility_score ?? 0,
    technical_health_score: previous?.technical_health_score ?? 0,
    onpage_score: previous?.onpage_score ?? 0,
    authority_score: previous?.authority_score ?? 0,
    ai_discovery_score: previous?.ai_discovery_score ?? 0,
    issue_count: 0,
    started_at: now,
  };

  mockAudits.push(audit);
  persistAudits();
  return audit;
}
