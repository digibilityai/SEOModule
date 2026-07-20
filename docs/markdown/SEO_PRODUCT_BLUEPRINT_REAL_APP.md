# Digibility SEO Intelligence - Real App Product Blueprint

## Source Context

This blueprint is converted from the uploaded Digibility SEO Tool Final Module & Feature Blueprint.

Important conversion rule:

The uploaded document contains prototype instructions such as dummy data, no backend, and no real integrations. For this Claude Code build, those instructions are NOT the execution direction.

For the current build, use this interpretation:

- Build a real application architecture.
- Mock data is allowed only through service-layer adapters during UI development.
- Do not hardcode fake data directly inside components.
- Keep all data structures backend-ready.
- Every SEO record must be linked to a website URL and website ID.
- Do not build a dummy-data-only prototype.
- Do not create fake auth.
- Do not create a separate auth system.
- Reuse the Digibility/Supabase auth approach.

---

## Product Positioning

Digibility SEO Intelligence should not become a complex SEO research tool like Semrush or Ahrefs.

It should be a simple SEO execution cockpit for business users.

The product should:

- Understand the website.
- Prioritize the most important SEO actions.
- Explain issues in simple business language.
- Prepare fixes.
- Ask for approval before risky changes.
- Help create SEO content.
- Track page performance.
- Plan off-page authority work safely.
- Show client-friendly progress reports.
- Convert insights into action, approval, expert support, or reporting.

Core promise:

> Enter your website URL and Digibility tells you what is wrong, what matters most, what can be fixed safely, what needs approval, and what should be handled by an expert.

---

## Build Philosophy

### Do not build

- A keyword database clone.
- A complex SEO analyst dashboard.
- A backlink automation spam tool.
- A fake prototype with random dummy data.
- A separate auth system.
- A separate UI style.

### Build

- A guided SEO execution system.
- A website-first SEO workspace.
- An approval-first workflow.
- A simple visibility dashboard.
- A prioritized action cockpit.
- A service-ready system where Digibility can offer expert support.

---

## Core Data Principle

The website URL is the main SEO entity.

Every SEO item must link to:

- user_id
- workspace_id or seo_workspace_id
- website_id
- website_url
- created_by
- created_at
- updated_at
- status
- plan_access_level where required

Core structure:

```text
User / Workspace
→ Website
→ Website Setup
→ Business Onboarding
→ SEO Audits
→ Recommendations
→ Approval Queue
→ Content Studio
→ Page Performance
→ Decline Diagnosis
→ Off-Page Opportunities
→ AI Visibility
→ Competitor Benchmarking
→ 90-Day Roadmap
→ Expert Support
→ Reports
```

---

## Real Build Rule for Mock Data

During UI development, mock data is allowed only like this:

```text
UI Component
→ Service Layer
→ Mock Adapter for now
→ Supabase Adapter later
```

Example:

```text
src/services/seoAuditService.ts
src/services/keywordService.ts
src/services/contentStudioService.ts
src/services/reportService.ts
src/mocks/seoAuditMockData.ts
```

Do not place dummy data directly inside page components.

Every mock object should look like a future Supabase row or API response.

---

## Core User Modules

### 1. SEO Setup & Connections

Purpose:

- Add website URL.
- Check sitemap.
- Check robots.txt.
- Prepare future GSC, GA4, CMS and GBP connection status.

V1 real-app approach:

- Build website setup UI.
- Store website-ready structure.
- Use mock connection states until integrations are built.
- Do not fake actual GSC/GA4 connection.

---

### 2. Business Onboarding

Collect:

- Business name
- Website URL
- Services/products
- Target audience
- Target locations
- Business goals
- Competitors
- Brand proof/trust signals

Why:

SEO recommendations should not be generic. The SEO engine needs business context.

---

### 3. Visibility Dashboard

Show simple scores:

- Overall Visibility Score
- Technical Health
- On-Page SEO Score
- Authority Score
- AI Discovery / GEO Score

Also show:

- Top priority fixes
- Pending approvals
- Recent audit status
- Page performance summary
- Content opportunities
- Expert support alerts

Language rule:

Use business-friendly language first, technical details second.

---

### 4. Technical SEO Audit

Detect and display:

- Crawl issues
- Indexing issues
- Speed issues
- Mobile issues
- Schema issues
- Duplicate content issues
- Broken links
- Sitemap issues
- Robots.txt issues
- Canonical issues
- Redirect issues

Each issue should show:

- Simple explanation
- Technical explanation
- Impact
- Effort
- Risk
- Confidence
- Fix type
- Suggested next action
- Status

---

### 5. On-Page SEO Autopilot

Suggest improvements for:

- Page title
- Meta description
- H1
- H2/H3 structure
- FAQs
- Schema
- Internal links
- Content improvements

Important:

No live website changes should happen without approval.

---

### 6. Approval Queue

Users should be able to:

- Approve
- Reject
- Edit
- Regenerate
- Send to expert review
- Mark as client action
- Mark as developer needed
- Mark as Digibility expert support

Every recommendation should move through a clear status workflow.

Suggested statuses:

```text
Suggested
→ Needs Review
→ Approved
→ Rejected
→ Edited
→ Expert Review Requested
→ Developer Needed
→ Ready to Publish
→ Published / Completed
```

---

### 7. Content Studio

Content workflow:

1. Select recommended title or add custom title.
2. View keyword plan.
3. View competitor content summary.
4. Approve wireframe.
5. Choose format input:
   - Default format
   - Upload PDF/DOCX
   - Paste URL
   - Match brand style
6. Generate draft.
7. Review draft.
8. Approve, reject, edit, or regenerate sections.
9. Move to publish queue or expert review.

Important rule:

Every generated content piece should pass through wireframe approval before full draft generation.

---

### 8. Page Performance Tracker

Track:

- Website page inventory
- Mapped keywords
- Ranking movement
- Clicks
- Impressions
- CTR
- Status:
  - Improving
  - Stable
  - Declining
  - Needs refresh
  - Not enough data

V1 approach:

- Build UI and data structure.
- Use mock performance adapter until GSC integration is added.

---

### 9. Decline Diagnosis Engine

Diagnose:

- CTR drop
- Ranking loss
- Freshness issue
- Indexing issue
- Cannibalization
- Intent mismatch
- Weak title/meta
- Competitor improvement

Output:

- Likely cause
- Confidence
- Recommended fix
- Priority
- Whether expert support is needed

---

### 10. Off-Page Authority Builder

Plan safe authority-building activities:

- Backlink opportunities
- Mentions
- Citations
- Reviews
- PR
- Social/community opportunities
- Partnerships

Important safety rules:

- Do not build automated backlink spam.
- Do not recommend paid links.
- Do not recommend PBNs.
- Do not mass-submit directories.
- Do not generate fake reviews.
- All external-facing actions require approval.

---

### 11. AI Visibility / GEO Engine

Track or prepare for:

- Brand mentions in AI answers
- Competitor mentions
- Citation opportunities
- AI content gaps
- Prompt tracking
- Content that improves AI answer visibility

V1 approach:

- Build as a planning/preview module.
- Real tracking can come later.

---

### 12. Competitor Benchmarking

Compare competitors across:

- Technical health
- Content depth
- Keyword coverage
- Authority signals
- Reviews
- AI visibility
- Page quality

Output:

- What competitors are doing better
- What gaps exist
- What Digibility recommends next

---

### 13. 90-Day SEO Roadmap

Convert findings into a clear plan:

- Weekly actions
- Monthly milestones
- Priority
- Expected impact
- Owner/responsibility
- Status
- Client action vs team action vs expert support

This turns SEO from issue lists into an execution plan.

---

### 14. Expert Support Desk

Users can request Digibility help for:

- Technical fixes
- Content review
- Off-page work
- PR support
- Publishing
- Strategy review
- High-risk changes

This module should convert software insights into service opportunities.

---

### 15. SEO Guardrail Monitor

Monitor risky changes:

- Title changes
- Deleted pages
- Noindex changes
- Canonical changes
- Redirect changes
- Robots.txt changes
- Sitemap changes
- URL changes

Important:

Do not auto-change indexability, canonicals, redirects, robots.txt, sitemap, URLs or live content without approval.

---

### 16. Content Trust Review

Flag:

- Risky claims
- Missing proof
- Outdated information
- Weak expertise
- Sensitive industry risks
- Human review needs

High-risk industries:

- Healthcare
- Finance
- Legal
- Education

---

### 17. Progress Reports

Show:

- What improved
- What was fixed
- Score movement
- Page progress
- Pending approvals
- Manual support needs
- Next actions

Reports should be client-friendly and simple.

---

## User Panel Feature Groups

### Setup

- Website Setup
- Business Onboarding
- Connection Health

### Dashboard

- Visibility Score
- Top Priority Fixes
- Pending Approvals
- Recent Activity

### Audit

- Technical SEO Issues
- On-Page Recommendations

### Approval

- Approval Queue
- Expert Review Requests

### Content

- Content Opportunity Titles
- Keyword Plan
- Competitor Content Summary
- Wireframe Builder
- Format Input
- Draft Review

### Performance

- Page Inventory
- Page Performance
- Decline Diagnosis

### Off-Page

- Authority Opportunities
- Campaign Builder

### AI Visibility

- AI Prompt Tracking
- Brand Mention Tracking
- Competitor Mention Tracking

### Competitors

- Benchmarking
- Gap Summary

### Planning

- 90-Day SEO Roadmap

### Support

- Expert Support Desk

### Reports

- Monthly Progress Report

---

## Admin Panel Modules

Admin is for Digibility operations, quality, support and billing control.

### Customer Management

- Client List
- Client Detail
- Websites
- Plan
- Health score
- Activity status
- Account notes

### Audit Operations

- Audit Runs
- Issue Library
- Failed checks
- Issue definitions
- Severity
- Fix type
- Customer-friendly explanations

### Recommendation Control

- Recommendation Queue
- Review generated fixes before showing or applying where needed

### Content Operations

- Content Studio Admin
- Content Trust Review Queue
- Briefs
- Keyword plans
- Draft status
- Approval status

### Off-Page Operations

- Authority Campaigns
- Spam Risk Review

### Expert Support

- Support Tickets
- Task Assignment
- SEO expert assignment
- Content writer assignment
- Developer assignment
- Account manager assignment

### Reports

- Report Builder
- Preview report
- Send/export report

### Plans

- Subscription Controls
- Module access controls
- Usage limits

### AI Governance

- Prompt Library
- AI Cost Tracking
- Model usage
- Request type
- Cost per client

### Integrations

- Integration Health
- GSC status
- GA4 status
- CMS status
- GBP status
- Third-party API failures

### Quality

- QA Review Queue
- High-risk change review

### Analytics

- Admin Analytics
- Module usage
- Conversion
- Support requests
- Upgrades
- Churn signals

### Templates

- Report templates
- Outreach templates
- Content formats
- SEO task checklists

---

## Plan Logic

### Basic

Best for small businesses that want visibility health, a simple audit and limited recommendations.

Includes:

- 1 website
- SEO setup and connections
- Monthly basic audit
- Visibility dashboard
- Top 5 priority fixes
- Limited on-page suggestions
- Basic approval queue
- 3 content title suggestions per month
- Basic keyword suggestions
- Basic page list
- Basic monthly roadmap
- Monthly simple report
- Expert support request as paid add-on

### Standard

Best for businesses that want SEO execution support, content planning, approvals, roadmap and progress reporting.

Includes:

- Up to 3 websites
- Weekly audit
- Visibility dashboard
- Top 15 priority fixes
- Full on-page recommendations
- Full approval queue
- 10 content plans per month
- Volume, difficulty and semantic keywords
- Basic competitor summary
- Wireframe builder
- Limited drafts per month
- Page performance tracking
- Basic decline diagnosis
- Off-page opportunity planner and drafts
- Basic AI visibility preview
- Full 90-day roadmap
- Important guardrail alerts
- Monthly detailed report
- Limited support requests

### Pro

Best for growth-focused businesses that want advanced SEO, AI visibility, competitor benchmarking, off-page campaigns and expert support workflows.

Includes:

- Up to 10 websites
- Advanced weekly audit
- Guardrail monitoring
- Advanced visibility insights
- Unlimited prioritized queue
- Advanced on-page recommendations
- Full team workflow
- Unlimited or high content plan cap
- Advanced keyword clusters
- Competitor gaps
- Advanced briefs and templates
- Higher draft limits
- Advanced page and keyword monitoring
- Advanced decline diagnosis
- Off-page campaign builder
- Full AI visibility tracking
- Advanced competitor benchmarking
- Advanced roadmap with ownership
- Advanced report export/share
- Priority expert support workflow

---

## Suggested Usage Limits

| Feature Area | Basic | Standard | Pro |
|---|---:|---:|---:|
| Audit frequency | Monthly | Weekly | Weekly + change monitoring |
| Content opportunities | 3/month | 10/month | Unlimited or high cap |
| Content drafts | 0-2/month | 5/month | 15+/month |
| Tracked pages | Up to 50 | Up to 250 | Up to 1,000+ |
| Tracked keywords | Up to 25 | Up to 150 | Up to 1,000+ |
| Competitors | 2 | 5 | 10+ |
| AI visibility prompts | Not included | 10/month | 100+/month |
| Off-page opportunities | Checklist only | 50/month | Advanced campaigns |
| Expert support requests | Pay per request | Limited included | Priority / bundled |

---

## Fail-Safe Product Rules

These rules must be enforced in product and admin logic.

1. Do not auto-publish meaningful website changes without approval.
2. Do not auto-change URLs, redirects, canonical tags, noindex tags, robots.txt or sitemap rules.
3. Do not promise guaranteed rankings in Google or AI answer engines.
4. Do not build automated backlink spam, mass outreach, fake reviews or mass directory submission.
5. All external-facing off-page actions must require approval.
6. Every recommendation should show impact, effort, risk, confidence and next action.
7. Every SEO issue should be explained in business-friendly language first, technical language second.
8. High-risk industries such as healthcare, finance, legal and education should trigger content trust review.
9. Every generated content piece should pass through wireframe approval before full draft generation.
10. Every manual task should be clearly marked as Client Action, Developer Needed, or Digibility Expert Support.

---

## Recommended Real-App Build Sequence

### Phase 0 - Already Completed

Scaffold separate Vite + React + TypeScript SEO module using Digibility UI style.

### Phase 1 - Product Architecture Layer

Build central module definitions, route structure, service-layer pattern, types, mock adapters and plan access configuration.

Do not build feature-heavy screens yet.

### Phase 2 - Website Setup and Business Onboarding

Build:

- Website setup
- Website list
- Website profile
- Business onboarding
- Connection health placeholders
- Website-level context object

### Phase 3 - Visibility Dashboard and Top Priority Fixes

Build:

- Overall visibility score
- Sub-scores
- Top priority fixes
- Pending approvals
- Recent activity
- Simple business-language summaries

### Phase 4 - Technical SEO Audit and Recommendations

Build:

- Audit summary
- Issue list
- Issue detail
- Recommendation cards
- Impact/effort/risk/confidence
- Status movement

### Phase 5 - Approval Queue

Build:

- Approve
- Reject
- Edit
- Expert review
- Developer needed
- Client action
- Status history

### Phase 6 - Content Studio

Build:

- Content opportunity titles
- Keyword plan
- Competitor content summary
- Wireframe approval
- Format input
- Draft review
- Publish queue placeholder

### Phase 7 - Page Performance and Decline Diagnosis

Build:

- Page inventory
- Mapped keywords
- Performance status
- Decline diagnosis
- Refresh recommendations

### Phase 8 - Off-Page Authority and AI Visibility

Build:

- Authority opportunities
- Safe campaign planner
- AI visibility preview
- GEO gaps
- Competitor mention tracking placeholders

### Phase 9 - Competitor Benchmarking and 90-Day Roadmap

Build:

- Competitor comparison cards
- Gap summaries
- 90-day roadmap
- Weekly/monthly actions
- Ownership and priority

### Phase 10 - Expert Support and Reports

Build:

- Expert support requests
- Task types
- Progress report builder
- Client-friendly report view

### Phase 11 - Admin Panel

Build:

- Client list
- Client detail
- Audit operations
- Issue library
- Recommendation queue
- Content review
- Support tickets
- Plan controls
- Prompt library
- AI cost tracking
- Integration health
- QA queue
- Admin analytics
- Templates

### Phase 12 - Supabase Backend Integration

Replace mock adapters with Supabase queries, tables, RLS policies and real persistence.

---

## Immediate Next Claude Code Task

The next Claude task should NOT build the full product.

The next task should add this product blueprint into the repo and create the real-app architecture foundation:

- domain types
- module registry
- plan registry
- route registry improvements
- service layer pattern
- mock data adapter pattern
- website-first data model placeholder types

No feature-heavy UI yet.
