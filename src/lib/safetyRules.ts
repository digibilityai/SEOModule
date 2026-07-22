import type { SeoIssue, SeoIssueCategory, SeoRecommendation } from "@/types";

export const SAFETY_NOTICE =
  "Digibility never auto-changes URLs, redirects, canonical tags, noindex tags, robots.txt or sitemap rules, and never publishes content live on its own. Every risky change needs your approval first.";

export const APPROVAL_QUEUE_SAFETY_NOTICE =
  "Digibility will not change live website content, URLs, redirects, canonical tags, noindex tags, robots.txt or sitemap rules without approval.";

export const PERFORMANCE_SAFETY_NOTICE =
  "These are likely reasons and recommended next steps, not guarantees. This may help — nothing here promises a ranking or traffic recovery.";

export const DECLINE_DIAGNOSIS_SAFETY_NOTICE =
  "Each diagnosis is a likely cause based on the data available, not a certainty. Needs review before you or your team act on it.";

export const OFFPAGE_SAFETY_NOTICE =
  "Digibility does not create fake reviews, paid link schemes, PBN links, spammy directories, or mass outreach. All external-facing actions require approval.";

export const AI_VISIBILITY_SAFETY_NOTICE =
  "Mock AI visibility data for local testing. Real AI answer tracking will come later. Nothing here guarantees an AI mention or ranking.";

export const COMPETITOR_SAFETY_NOTICE =
  "These are gaps and opportunities based on estimated benchmarking, not guarantees. Closing a gap may improve visibility — it doesn't guarantee outranking a competitor.";

export const ROADMAP_SAFETY_NOTICE =
  "This 90-day plan is a recommended sequence of next steps, not a guarantee of ranking or traffic improvement. Expert review is recommended for higher-risk actions.";

export const SUPPORT_DESK_SAFETY_NOTICE =
  "Submitting a request sends it to Digibility for review — no ticketing, email, or payment is triggered automatically yet.";

export const REPORTS_SAFETY_NOTICE =
  "This report reflects progress so far, not a guarantee of future ranking, traffic or AI mention growth. Use it to see what's next, not as a promise.";

// Categories where an automated change could break indexing or navigation —
// these always require approval, regardless of the individual issue's risk.
const HIGH_RISK_ISSUE_CATEGORIES: SeoIssueCategory[] = [
  "robots_txt",
  "canonical",
  "redirects",
  "sitemap",
  "indexability",
];

export function isHighRiskIssueCategory(category: SeoIssueCategory): boolean {
  return HIGH_RISK_ISSUE_CATEGORIES.includes(category);
}

export function issueRequiresApproval(issue: SeoIssue): boolean {
  return isHighRiskIssueCategory(issue.category) || issue.risk !== "low";
}

export function recommendationRequiresApproval(recommendation: SeoRecommendation): boolean {
  return (
    recommendation.action_type === "approval_required" ||
    recommendation.action_type === "expert_review" ||
    recommendation.risk !== "low"
  );
}
