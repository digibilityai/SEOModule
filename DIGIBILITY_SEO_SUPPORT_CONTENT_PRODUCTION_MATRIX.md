# Digibility SEO Intelligence — Support-Content Production Matrix

> **DRAFT for ChatGPT review — not yet authoritative.** Production backlog derived
> from `DIGIBILITY_SEO_END_TO_END_USER_JOURNEY_AND_SUPPORT_BLUEPRINT.md`. One row
> per support asset. Documentation-only; no code/DB/production change.

## Legend

- **Priority:** **P0** onboard & safely use · **P1** understand results & act ·
  **P2** optimization/advanced · **P3** preview/deferred-feature education.
- **Current readiness:** *Ready* (feature OPERATIONAL/TEST — documentable now with
  a "preview/seeded" caveat) · *Preview* (seeded/mock — document as preview) ·
  *Blocked* (PLACEHOLDER/DEFERRED — educate on status only).
- **Asset type:** Quick start · How-to · Workflow · Explanation · Report
  interpretation · Troubleshooting · FAQ · Role guide · Checklist · Video ·
  Micro-video · Admin/support runbook.
- Every asset that shows seeded/mock data must carry the honesty caveat (blueprint
  §1.1).

## Sensitive-data rule (applies to every asset)
Never capture or request: passwords, service-role keys, **DNS challenge/TXT
values**, lease tokens, internal worker diagnostics. Blur emails and any
secret-looking ids in all screenshots/videos.

---

## Matrix

| ID | Product area | User question | Asset type | Audience/role | Prerequisite | Source §§ | Article title | Video title | Learning objective | Steps covered | Screens required | Required account/state | Sensitive data to hide | Article size | Video length | Priority | Readiness | Blocking limitation | Review owner | Update trigger |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A01 | Orientation | What is Digibility SEO and what can I do today? | Quick start | All | Access | 2,25 | Getting started with Digibility SEO | Welcome to Digibility SEO (preview) | Understand scope + preview caveat | Overview, areas, caveats | Dashboard | Any signed-in | email | M | 2–4 min | P0 | Ready (preview) | Whole build TEST-only | Product | Status change |
| A02 | Auth | How do I sign in / why am I redirected? | How-to + Troubleshooting | All | Account | 5 | Signing in and access states | How to sign in | Log in; understand access states | Login, invalid, deep-link, sign-out | Login card, error, dashboard | Any | email | S | 30–60s | P0 | Ready | — | Support | Auth changes |
| A03 | Auth | Why "Access required"? | Explanation + FAQ | All | — | 5,21 | SEO access & entitlements | — | Understand module entitlement | Access-required states | Access-required state | No-entitlement acct | account id | S | — | P0 | Ready | Entitlement in parent | Support | Entitlement model |
| A04 | Navigation | How do workspace + active website work? | Explanation | All | Signed in | 6 | Workspaces and the active website | Switching websites | Understand website-scoped data | Sidebar, selector, switching | Sidebar, header | ≥1 website | site names | M | 2–4 min | P0 | Ready | — | Product | Nav changes |
| A05 | Websites | How do I add a website? | How-to | Owner/Admin/Team | Workspace | 7 | Adding a website | Add your website | Create a website record | Form, validation, save | Website form, success | Manager role | — | S | 2–4 min | P0 | Ready | — | Support | Form changes |
| A06 | Onboarding | How do I complete the business profile? | How-to | Owner/Admin/Team | Website | 7 | Completing business onboarding | Business onboarding | Fill + save profile | All fields, save | Onboarding form | Manager role | — | M | 2–4 min | P0 | Ready | Downstream automation deferred | Product | Field changes |
| A07 | Ownership | How do I verify domain ownership? | How-to + Video | Owner/Admin | Website | 8 | Verifying domain ownership (DNS TXT) | Verify your domain | Add TXT, check, understand states | Initiate, DNS, check, states | Panel, DNS block, states | Owner/Admin | **DNS token** | L | 2–4 min | P0 | Ready | Worker not deployed (stays pending) | Product | P1a changes |
| A08 | Ownership | Why is it still "pending" after I added the record? | FAQ + Troubleshooting | Owner/Admin | Pending | 8,21 | Ownership pending — what it means | — | Understand UI-accepted vs worker-run vs verified | Pending explanation | Pending badge | Owner/Admin | token | S | — | P0 | Ready | Worker not deployed | Support | Worker deploy |
| A09 | Ownership | Team/client can't verify — why? | Role guide | Team/Client | — | 3,8 | Who can verify ownership | — | Understand owner/admin-only | Read-only view + tooltip | Read-only panel | Team/Client | — | S | — | P1 | Ready | — | Support | Role changes |
| A10 | Crawl | How do I start and monitor a crawl? | How-to + Video | Owner/Admin/Team | **Verified** | 9 | Starting and monitoring a crawl | Start a crawl | Enqueue + monitor | Confirm, statuses, freshness | Confirm, status card | Manager, verified | site | L | 2–4 min | P0 | Ready | Worker not deployed → stays Queued | Product | Crawl changes |
| A11 | Crawl | What do the crawl statuses mean? | Explanation + Micro-video | All | — | 9 | Understanding crawl statuses | Crawl statuses explained | Read each status | All 9 statuses | Each badge | Any | — | M | 30–60s | P0 | Ready | — | Support | Status set changes |
| A12 | Crawl | Why was my crawl rejected? | Troubleshooting + FAQ | Owner/Admin/Team | — | 8,9,21 | "Ownership must be verified" — fixing crawl rejection | — | Understand P1b gate | Verify then retry | Rejection message | Manager | token | S | — | P0 | Ready | — | Support | P1b changes |
| A13 | Audit | How do I read an audit? | Report interpretation | All | Completed audit | 10 | Reading your technical audit | Reading an audit | Interpret issues/severity | Issues, severity, scope | Audit page | Seeded audit | — | L | 5–10 min | P1 | Preview | Seeded; no live score | Product | Audit changes |
| A14 | Issues | How do I fix technical issues (by severity)? | Workflow | Owner/Admin/Team | Audit | 10 | Fixing technical SEO issues | — | Prioritize + route to approval | Severity → owner → approval | Audit + approvals | Manager | — | L | 5–10 min | P1 | Preview | Seeded | Product | Audit/approval |
| A15 | Recommendations | Where do recommendations come from? | Explanation + FAQ | All | — | 11 | Recommendations explained | — | Understand seeded vs generated | Source, list | Optimizer/audit | Any | — | M | — | P1 | Preview | No live generation | Product | Generation ships |
| A16 | Approvals | How do approvals work? | Workflow + Video | Owner/Admin/Team | Items | 11 | The approval workflow | Approving work | Submit/approve/reject | Transitions, comments, activity | Approvals page | Manager | — | L | 2–4 min | P0 | Ready | — | Product | Approval RPC |
| A17 | Content Studio | How do I use Content Studio? | Workflow + Video | Owner/Admin/Team | Website | 12 | Content Studio workflow | Content Studio walkthrough | Move content through states | Areas, transitions, review | Studio surfaces | Manager | — | L | 5–10 min | P2 | Preview | Generation + upload deferred | Product | Studio changes |
| A18 | Content Studio | Why can't I upload a file? | FAQ | Owner/Admin/Team | — | 12,18 | File uploads in Content Studio | — | Set expectations | Upload deferred | — | Manager | — | S | — | P3 | Blocked | Upload UI deferred | Support | Upload ships |
| A19 | Page Inventory | What is Page Inventory? | Explanation | All | Pages | 13 | Understanding Page Inventory | — | Read the page list | Pages, owned-vs-crawler | Inventory list | Seeded pages | — | M | 2–4 min | P1 | Preview | Seeded | Product | Inventory changes |
| A20 | Page Performance | How do I read performance metrics? | Report interpretation + Video | All | Snapshots | 13 | Reading Page Performance | Reading Page Performance | Interpret metrics + movement | Clicks/impr/CTR/pos/movement | Performance table | Seeded | — | L | 5–10 min | P1 | Preview | `manual_seed`, no live GSC/GA4 | Product | Ingestion ships |
| A21 | Page Performance | What does each metric mean? | Explanation + Micro-video | All | — | 13 | SEO metrics glossary (clicks/impressions/CTR/position) | Metrics in 60s | Define metrics | Each metric | Metric cells | Any | — | M | 30–60s | P1 | Preview | Seeded | Support | — |
| A22 | Decline Diagnosis | How do I investigate a decline? | Workflow + Video | Owner/Admin/Team | Diagnoses | 14 | Diagnosing a ranking/traffic decline | Decline diagnosis walkthrough | Interpret + route action | 8-step process | Diagnosis cards | Seeded | — | L | 5–10 min | P1 | Preview | Seeded, not live AI, read-only | Product | Live AI ships |
| A23 | Off-Page | How do I evaluate an opportunity? | Workflow | Owner/Admin/Team | Opportunities | 15 | Evaluating off-page opportunities | Off-page opportunities | Evaluate + act | Statuses, actions, spam-risk | Off-page board | Manager | — | L | 5–10 min | P2 | Ready (preview) | Seeded | Product | Stage 6 changes |
| A24 | Off-Page | Why can't I reject an opportunity? | Role guide + FAQ | Team | — | 3,15 | Off-page roles & the reject rule | — | Understand reject = owner/admin | Role gate | Disabled action | Team | — | S | — | P2 | Ready | — | Support | Role changes |
| A25 | Campaigns | How do I create and approve a campaign? | Workflow + Video | Owner/Admin/Team | Opportunities | 16 | Authority campaigns end-to-end | Authority campaign workflow | Create→submit→approve/reject→return | Full state machine | Builder + list | Manager | — | L | 5–10 min | P2 | Ready (preview) | Edit/delete/task-completion deferred | Product | Stage 6 changes |
| A26 | Campaigns | What campaign actions aren't available yet? | FAQ | Owner/Admin/Team | — | 16,25 | Campaign limitations today | — | Set expectations | Deferred items | — | Manager | — | S | — | P3 | Blocked | Edit/delete/tasks deferred | Support | Feature ships |
| A27 | AI Visibility | What is AI Visibility showing me? | Explanation | All | — | 17 | AI Visibility (preview) | AI Visibility preview | Understand preview scope | Prompt/mentions/gaps | AI views | Seeded | — | M | 2–4 min | P3 | Preview | Seeded, no LLM ingestion, reads only | Product | LLM ingestion |
| A28 | Competitors/Roadmap/Reports/Support | Are these live? | Explanation + FAQ | All | — | 18 | Preview modules explained | — | Understand mock/placeholder status | Status per module | Each module | Any | — | M | — | P3 | Blocked | Mock/placeholder | Product | Wiring ships |
| A29 | Reports | How do I read a report / run a review? | Report interpretation + Checklist | Owner/Admin | — | 19,20 | Report interpretation framework | — | 12-step read method + widget template | Framework steps | Reports/dashboard | Any | — | L | 5–10 min | P1 | Preview | Reports mock | Product | Reports wiring |
| A30 | Cadence | What should I do daily/weekly/monthly? | Checklist | Owner/Admin/Team | — | 20 | SEO operating cadence checklist | — | Establish rhythm | D/W/M/Q lists | Multiple | Manager | — | L | — | P1 | Ready (preview) | Data seeded | Product | Cadence changes |
| A31 | Roles | Who can do what? | Role guide | All | — | 3 | Roles and permissions | Roles explained | Understand the matrix | Capability matrix | Disabled controls | All roles | — | L | 2–4 min | P0 | Ready | — | Support | RLS/RPC changes |
| A32 | Agency | How do I manage multiple client websites? | Workflow | Owner/Admin | Multiple sites | 3,6 | Agency multi-client workflow | Managing multiple clients | Switch + scope safely | Website switching | Selector | Multi-site | site names | M | 2–4 min | P2 | Ready | No cross-client aggregate | Product | Multi-site features |
| A33 | Troubleshooting | Something's wrong — what do I check? | Troubleshooting | All | — | 21 | SEO troubleshooting guide | — | Self-serve fixes | 29 symptoms | Various | Any | secrets | XL | — | P0 | Ready | — | Support | Any change |
| A34 | FAQ | Common questions | FAQ | All | — | all | Digibility SEO FAQ | — | Quick answers | Curated Qs | — | Any | secrets | L | — | P0 | Ready | — | Support | Any change |
| A35 | Glossary | What does this term mean? | Explanation | All | — | 22 | Digibility SEO glossary | — | Define terms/statuses | All terms | — | Any | — | M | — | P1 | Ready | — | Support | Term changes |
| A36 | Support ops | Safe diagnostic sequence | Admin/support runbook | Support | — | 23 | Support diagnostic runbook | — | Diagnose without secrets | Safe sequence + safe asks | — | Support | all secrets | L | — | P0 | Ready | — | Support lead | Policy changes |
| A37 | Video program | Full onboarding | Video (webinar) | All | — | 4,24 | — | Digibility SEO onboarding webinar | Day-1→month-1 end-to-end | Full journey | All key screens | Manager+seeded | secrets | — | webinar | P1 | Ready (preview) | Preview data | Product | Major changes |
| A38 | Ownership | Security: protecting your DNS token | Explanation + FAQ | Owner/Admin | — | 8,23 | Keep your verification token safe | — | Never share the token | Security note | Panel (blurred) | Owner/Admin | **token** | S | — | P0 | Ready | — | Support | — |
| A39 | Crawl | Worker retry vs new crawl | Explanation + FAQ | Owner/Admin/Team | — | 9 | Retries vs new crawls | — | Distinguish the two concepts | Retry vs create | Status card | Manager | — | S | 30–60s | P1 | Ready | — | Support | Crawl changes |
| A40 | Data honesty | Is this data real? | Explanation + FAQ | All | — | 1,13,17,25 | Preview data vs live data | — | Identify seeded/mock vs real | Labels, `manual_seed`, Preview | Multiple | Any | — | M | 2–4 min | P0 | Preview | Ingestion deferred | Product | Ingestion ships |

---

## Prioritized production order (recommended)

- **P0 first (onboard & safe use):** A01, A02, A03, A04, A05, A06, A07, A08, A10,
  A11, A12, A16, A31, A33, A34, A36, A38, A40.
- **P1 (understand & act):** A09, A13, A14, A15, A19, A20, A21, A22, A29, A30,
  A35, A37, A39.
- **P2 (optimization/advanced):** A17, A23, A24, A25, A32.
- **P3 (preview/deferred education):** A18, A26, A27, A28.

## Blocking-limitation summary (must be stated in the relevant assets)
- Worker not deployed → crawls stay Queued; ownership rechecks don't auto-run.
- No live GSC/GA4/LLM/backlink ingestion → Page Performance/AI Visibility/Reports
  are seeded/mock.
- Keyword Research, Content Gaps, Blog Briefs = placeholders.
- Competitors/Roadmap/Reports/Support = mock-only.
- Content Studio generation + file upload, campaign edit/delete/tasks, billing/
  usage enforcement, parent integration = deferred.
- Entire module is TEST-only (not production-promoted).

---
*End of production matrix (draft). No code, database, or production state was
changed to produce this document.*
