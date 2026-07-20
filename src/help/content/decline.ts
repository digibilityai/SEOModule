import type { HelpArticle } from "../types";

export const DECLINE_ARTICLES: HelpArticle[] = [
  {
    id: "investigating-traffic-ranking-decline",
    slug: "investigating-traffic-ranking-decline",
    title: "Understanding and Investigating a Traffic or Ranking Decline",
    summary:
      "Why traffic or rankings drop, how to read the metrics, and how to use Decline Diagnosis to investigate — with honest confidence levels, not guesses.",
    body: [
      { type: "callout", text: "Words used carefully in this article: \"possible\" means one explanation among several that could apply; \"likely\" means what Digibility's diagnosis suggests based on the data it has; \"confirmed\" means something you verified yourself. Digibility does not claim certainty it doesn't have." },
      { type: "paragraph", text: "A drop in traffic or rankings almost always has more than one plausible explanation. Some causes are on your site (technical or content problems), some are about authority (backlinks and trust), some are external (competitors, search demand, or how AI-generated answers surface results), and many declines are a combination of more than one. The goal of this article is to help you investigate calmly and in the right order, rather than guess." },

      { type: "heading", id: "metrics-explained", text: "Clicks, impressions, CTR, and average position" },
      { type: "paragraph", text: "These four metrics tell different parts of the story, and a decline can show up in only one of them." },
      { type: "definition", term: "Clicks", text: "How many times people clicked through to your page from search results." },
      { type: "definition", term: "Impressions", text: "How many times your page appeared in search results, whether or not it was clicked." },
      { type: "definition", term: "CTR (click-through rate)", text: "Clicks divided by impressions — the share of people who saw your listing and clicked it. CTR can fall even when your ranking position hasn't moved." },
      { type: "definition", term: "Average position", text: "Roughly where your page tends to rank in search results. A worsening (higher) number generally means a ranking loss; an unchanged position with falling clicks points elsewhere." },
      { type: "troubleshootingNote", text: "Always check all four together. Falling clicks with steady impressions and steady position often points to a CTR problem (title/meta or AI-answer competition), not a ranking problem." },

      { type: "heading", id: "temporary-vs-structural", text: "Temporary dips versus structural decline" },
      { type: "paragraph", text: "Small week-to-week movement is normal and often not worth acting on. A decline is more likely to be structural — meaning it reflects a real, ongoing cause rather than noise — when it is sustained across multiple reporting periods, affects more than a single isolated day, and doesn't recover on its own. Until a drop has been sustained for a while, treat it as possible noise rather than a confirmed problem." },

      { type: "heading", id: "technical-causes", text: "Technical causes" },
      { type: "list", items: [
        "An indexing issue — the page isn't being included in search results at all.",
        "Crawl errors or a page that recently became slow, broken, or hard to access.",
        "Accidental blocking via robots.txt, a noindex tag, or a redirect/canonical pointing away from the page.",
        "Mobile usability problems.",
      ] },
      { type: "paragraph", text: "These are possible causes worth ruling out first, since they're usually the most fixable and the most verifiable." },

      { type: "heading", id: "content-causes", text: "Content causes" },
      { type: "list", items: [
        "A content freshness issue — the page hasn't been updated while the topic or competition has moved on.",
        "A content depth gap — the page is thinner or less complete than what's now ranking well.",
        "Keyword cannibalization — two of your own pages competing for the same search intent.",
        "A search-intent mismatch — the page doesn't match what searchers are actually looking for anymore.",
        "A weak title or meta description that reduces clicks even at a steady position.",
      ] },

      { type: "heading", id: "authority-causes", text: "Authority causes" },
      { type: "list", items: [
        "Lost or removed backlinks that were previously supporting the page.",
        "Reduced trust or authority signals relative to the pages now outranking you.",
      ] },
      { type: "paragraph", text: "Authority causes are usually slower-moving and are more likely when the decline is gradual across many pages rather than sudden on one." },

      { type: "heading", id: "competitor-changes", text: "Competitor changes" },
      { type: "paragraph", text: "It's possible your position dropped because a competitor published stronger content, earned more links, or improved their technical performance — with nothing on your own site changing at all. This is a possible explanation you can only confirm by comparing what's now outranking you, not something Digibility can assert on your behalf." },

      { type: "heading", id: "search-demand-changes", text: "Search-demand changes" },
      { type: "paragraph", text: "Sometimes fewer people are searching for a topic at all — a seasonal pattern or a genuine shift in interest. This shows up as falling impressions and clicks with a stable average position, and it is a demand change, not a ranking loss. Confusing the two can lead to fixing something that was never broken." },

      { type: "heading", id: "ai-overviews-aeo-geo", text: "AI Overviews, AEO, and GEO influence" },
      { type: "warning", text: "This section describes an evolving area of search behavior. Nothing here is a confirmed technical fact about how any specific search engine or AI system currently ranks or answers queries." },
      { type: "paragraph", text: "It's possible that AI-generated answer summaries, answer-engine placements, or generative-search results are answering a searcher's question directly — reducing clicks to traditional listings even when your ranking position hasn't dropped. This is a plausible contributing factor worth considering alongside the more established causes above, not a confirmed diagnosis Digibility can currently make for any individual page." },
      { type: "relatedLink", articleSlug: "what-aeo-is", label: "What AEO is" },
      { type: "relatedLink", articleSlug: "what-geo-is", label: "What GEO is" },

      { type: "heading", id: "how-digibility-helps", text: "How Digibility helps investigate" },
      { type: "steps", items: [
        "Open Page Performance Tracker to review clicks, impressions, CTR, and average position per page, including how each compares to the previous period.",
        "Open Decline Diagnosis Engine, which reviews that page performance data and returns a likely cause, a confidence percentage, a plain-language explanation, a technical explanation, and a recommended fix — per page.",
        "Each diagnosis names who should act on it (you, a developer, or a Digibility expert) and, where relevant, offers a direct escalation to expert support.",
      ] },
      { type: "expectedResult", text: "A diagnosis is a likely cause with a stated confidence percentage — not a guarantee. It needs your review before you or your team act on it." },

      { type: "heading", id: "current-limitations", text: "Current product limitations" },
      { type: "statusNotice", text: "Decline Diagnosis currently reasons over the page performance data already recorded in your account. It does not yet pull live signals directly from Google Search Console, GA4, or a live backlink index — those integrations are not yet built. Confidence percentages reflect the diagnosis logic's assessment of the available data, not an external verification." },

      { type: "heading", id: "demo-data-honesty", text: "Demo-data and TEST honesty" },
      { type: "statusNotice", text: "In this build, the performance numbers behind a diagnosis are seeded demo data on the test project, not a live connection to your real Search Console or analytics account. Treat the diagnosis logic and workflow as real and working — treat the specific numbers as illustrative until this is promoted beyond TEST." },
      { type: "relatedLink", articleSlug: "preview-data-versus-live-data", label: "Preview data versus live data" },

      { type: "heading", id: "investigation-workflow", text: "Recommended investigation workflow" },
      { type: "steps", items: [
        "Confirm scope: is the drop on one page, a group of pages, or site-wide?",
        "Check which metric moved — clicks, impressions, average position, or more than one — since they point to different causes.",
        "Open Decline Diagnosis Engine and read the likely cause and confidence percentage for the affected page(s).",
        "Check whether a recent site or content change lines up with when the drop started.",
        "Consider competitor and search-demand explanations before assuming a technical fault — they can look identical to a ranking loss at a glance.",
        "If a diagnosis needs expert support, use the provided escalation link rather than guessing at a fix.",
      ] },

      { type: "heading", id: "choosing-next-actions", text: "Choosing next actions" },
      { type: "list", items: [
        "Technical cause → usually needs a developer; verify the fix, then watch for recovery over the following reporting periods.",
        "Content cause (freshness, depth gap, cannibalization, intent mismatch, weak title/meta) → refresh, expand, or clarify the page yourself, or route it through Content Studio.",
        "Authority cause → consider Off-Page Authority Builder for safe link/mention opportunities; expect this to be the slowest category to show a change.",
        "Competitor or search-demand cause → often no fix is needed on your page; re-evaluate after a full reporting cycle rather than reacting immediately.",
        "Unsure, or the diagnosis says expert support is recommended → escalate through Decline Diagnosis's built-in support link instead of guessing.",
      ] },

      { type: "relatedLink", articleSlug: "technical-content-authority-measurement", label: "Technical SEO, content, authority, and measurement" },
      { type: "relatedLink", articleSlug: "roles-and-permissions", label: "Roles and permissions" },
      { type: "relatedLink", articleSlug: "contacting-support-safely", label: "Contacting support safely" },
    ],
    category: "reports-decline-diagnosis",
    subcategory: "decline-diagnosis",
    contentType: "report_interpretation",
    audienceRoles: ["owner", "admin", "team_member", "agency"],
    level: "intermediate",
    productArea: "decline-diagnosis",
    featureStatus: "available_on_test",
    estimatedReadingMinutes: 9,
    tags: [
      "decline diagnosis", "traffic decline", "ranking decline", "clicks", "impressions",
      "ctr", "average position", "decline diagnosis engine", "page performance",
    ],
    searchAliases: [
      "why did my traffic drop", "my rankings dropped", "rankings fell", "rankings dropped",
      "search traffic decline", "traffic decline", "seo decline", "website traffic down",
      "traffic down", "impressions dropped", "clicks dropped", "my seo is getting worse",
      "seo getting worse", "declining rankings", "losing traffic", "traffic dropped",
      "ranking loss", "why are my rankings falling", "position dropped",
    ],
    relatedArticleIds: [
      "preview-data-versus-live-data", "technical-content-authority-measurement",
      "what-aeo-is", "what-geo-is", "roles-and-permissions", "contacting-support-safely",
    ],
    relevantRoutes: ["/seo/decline-diagnosis", "/seo/page-performance"],
    priority: "P0",
    lastReviewed: "2026-07-19",
    version: "1",
    published: true,
    visibility: "public",
    externalReviewRequired: true,
  },
];
