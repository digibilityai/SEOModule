# Digibility SEO Intelligence Module - Project Context

## Project Name

Digibility SEO Intelligence Module

## Main Goal

Build a complete SEO module for Digibility that can work as a standalone paid product as well as plug into the existing Digibility Visibility Management system later.

The SEO module should be built independently, tested independently, and then integrated with the existing Digibility system without changing the core architecture, tech stack, authentication system, UI system, or database principles.

## Business Context

Digibility is an AI-powered visibility management platform for businesses and agencies. The existing system already has a Visibility Management module.

Now we are adding SEO Intelligence as a paid module.

SEO Intelligence should help users improve their search visibility through website audits, keyword research, competitor analysis, SEO recommendations, blog brief generation, page optimization, and reporting.

## Important Business Rules

1. SEO will be a paid add-on for existing Digibility users.
2. A user may also register only for SEO without registering for the Visibility Management system.
3. SEO should not have a separate authentication system.
4. SEO must use Digibility’s existing auth system.
5. Team members can access SEO.
6. Clients can view SEO reports.
7. Clients can also run audits and perform allowed SEO actions.
8. Every SEO record must be linked to a website URL.
9. SEO should use the same UI and UX style as the existing Digibility Visibility Management system.
10. SEO should not look like a separate product pasted into Digibility.
11. SEO should be independently built and tested first.
12. Once mature, SEO should plug into the existing Digibility system.

## Product Positioning

The module should not be treated as a basic SEO tool.

It should be positioned as:

**SEO Intelligence**

The goal is not only to give SEO data, but to convert SEO insights into clear actions for founders, businesses, agencies, team members, and clients.

## Architecture Direction

SEO should be built as an independent module inside the Digibility ecosystem.

The final structure should support:

- Visibility Management only users
- SEO only users
- Users who use both Visibility Management and SEO
- Agencies managing SEO for multiple clients
- Team members working inside client accounts
- Clients viewing reports and running allowed actions

## Shared Platform Dependencies

SEO should depend on Digibility Core for:

- Authentication
- User management
- Workspace management
- Team management
- Client access
- Billing and subscription status
- Role permissions
- Shared UI components
- Shared design system

SEO should not rebuild these from scratch.

## Core SEO Entity

The core entity for SEO is the website URL.

Every SEO audit, keyword record, competitor analysis, SEO report, blog brief, page recommendation, and optimization history should be linked to a website URL.

Recommended structure:

```text
User / Workspace
→ Website URL
→ SEO Audits
→ Keyword Research
→ Competitor Analysis
→ Content Gaps
→ Blog Briefs
→ Page Optimizations
→ SEO Reports
→ SEO Score History
```

## Suggested SEO Features for Version 1

The first version should focus only on the most important SEO features.

### Version 1 Features

1. SEO Dashboard
2. Website URL Management
3. Website SEO Audit
4. Keyword Research
5. Competitor SEO Snapshot
6. Content Gap Suggestions
7. Blog Topic Suggestions
8. Blog Brief Generator
9. On-page SEO Recommendations
10. SEO Reports

Do not overbuild the first version.

## Future SEO Features

These may come later, not necessarily in version 1:

1. Google Search Console integration
2. GA4 integration
3. Rank tracking
4. Backlink tracking
5. Technical SEO crawler
6. Internal linking automation
7. SEO content calendar
8. AI-based page rewriting
9. SEO task assignment
10. Monthly SEO performance reports

## Role Permission Logic

### Owner / Admin

Can:

- Manage billing
- Add or remove team members
- Add or remove clients
- Add website URLs
- Run SEO audits
- Do keyword research
- Generate blog briefs
- View reports
- Export reports
- Delete records where allowed

### Team Member

Can:

- Access assigned workspaces
- Run audits
- Do keyword research
- Generate blog briefs
- Create SEO recommendations
- View reports
- Export reports if allowed

Cannot:

- Manage billing
- Delete workspace
- Change subscription

### Client

Can:

- View SEO reports
- Run audits
- View recommendations
- Perform allowed SEO actions

Cannot:

- Manage billing
- Delete workspace
- Remove team members
- Change core account settings

## Billing Logic

SEO should be module-based.

A user account may have:

- Visibility Management active
- SEO Intelligence active
- Both active
- Only SEO active
- Only Visibility Management active

Do not hardcode SEO as a child of Visibility Management.

## UI and UX Direction

SEO must follow the existing Digibility UI.

Use the same or similar:

- Sidebar
- Cards
- Buttons
- Forms
- Tables
- Dashboard layout
- Typography
- Colors
- Spacing
- Empty states
- Loading states
- Modal design
- Report design

The user should feel that SEO is a native part of Digibility.

## Suggested Navigation

Inside Digibility, SEO may appear as:

**SEO Intelligence**

Suggested menu items:

1. SEO Dashboard
2. Websites
3. Website Audit
4. Keyword Research
5. Competitor Analysis
6. Content Gaps
7. Blog Briefs
8. Page Optimizer
9. Reports
10. Settings

## Data Exchange with Visibility Management

When a user has both Visibility Management and SEO active, the two modules should exchange useful data.

### Visibility Management can send to SEO:

- Business name
- Website URL
- Industry
- Target audience
- Services/products
- Brand positioning
- Target locations
- Competitors
- Existing content calendar
- Published blogs/posts
- Landing pages

### SEO can send to Visibility Management:

- Keyword opportunities
- Blog topics
- Content gap ideas
- Landing page improvement suggestions
- SEO-based content recommendations
- Website issues that affect visibility
- Search visibility insights

## Technical Instruction for Claude Code

When building this module:

1. Do not change the existing Digibility architecture unless absolutely necessary.
2. Do not introduce a new auth system.
3. Do not introduce a new UI design style.
4. Do not introduce a completely different tech stack.
5. Keep the SEO module independent enough to test separately.
6. Keep the SEO module ready for future integration.
7. Use clean APIs for data exchange.
8. Keep every SEO record linked to website URL.
9. Make the module scalable for agencies managing multiple clients.
10. Keep the first version simple, clean, and production-minded.

## Development Principle

Build SEO like a plug-and-play business module.

It should be independent during development, but native after integration.

The goal is:

```text
Standalone when needed.
Integrated when required.
Consistent always.
```
