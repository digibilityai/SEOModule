# Digibility SEO — Help Center Information Architecture

> **DRAFT (Phase 1) — not authoritative.** Content taxonomy, catalogue, learning
> paths, search taxonomy, FAQ inventory, and video architecture. Baseline article
> corpus = the 40 assets (A01–A40) in
> `DIGIBILITY_SEO_SUPPORT_CONTENT_PRODUCTION_MATRIX.md`; new academy/contextual/
> honesty articles added below. No code/DB/production changed.

## 1. Primary logical blocks (validated hierarchy)

| Key | Category | Scope |
|---|---|---|
| A | **Start Here** | Orientation, first day, "is this data real?" |
| B | **Learn SEO, AEO & GEO** | Concept academy (Spec §7) |
| C | **Set Up Digibility SEO** | Access, workspace, website, onboarding |
| D | **Websites & Ownership** | Website management + domain ownership |
| E | **Website Crawling** | Start/monitor/cancel, statuses |
| F | **Audits & Technical SEO** | Audit reading, issues, fixing |
| G | **Recommendations & Approvals** | Recommendation sources + approval workflow |
| H | **Content Studio** | Content workflow (preview generation) |
| I | **Page Inventory & Performance** | Inventory + metric interpretation |
| J | **Decline Diagnosis** | Decline interpretation |
| K | **Off-Page Authority** | Opportunities |
| L | **Authority Campaigns** | Campaign workflow |
| M | **AI Visibility** | Preview reads |
| N | **Reports & Operating Rhythm** | Report reading + cadence |
| O | **Roles, Teams & Agencies** | Roles + multi-client |
| P | **Troubleshooting** | Symptom-based |
| Q | **Account, Access & Settings** | Login/access/settings/connections |
| R | **Feature Availability & Roadmap** | Honesty + what's coming |
| S | **Glossary** | Terms |
| T | **Contact Support** | Escalation |

*Refinement note:* keep O and R prominent — role clarity and feature-status honesty
are the two highest-leverage support-deflection topics for this build.

## 2. Article catalogue

Baseline A01–A40 (from the production matrix) are mapped into categories below;
**new** articles (N-prefixed) fill the academy, honesty, contextual, and value-
proposition gaps. Columns abbreviated for width; full metadata lives per-article
at authoring time.

| Article ID | Category | Title | User question | Type | Audience | Level | Product area | Related route | Status label | Priority | Aliases (search) | Tags | Related | Contextual placements | Source evidence | Review |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A01 | A | Getting started with Digibility SEO | what is this / where do I start | Quick start | All | Beg | Orientation | /seo/dashboard | Available on TEST | P0 | get started, intro, begin | onboarding | A02,N01,A40 | dashboard empty | Blueprint §2 | product |
| N01 | A | Is my data real? Preview vs live | is this real data | Explanation | All | Beg | Orientation | any | Demo data | P0 | demo, seeded, mock, fake data, test | honesty | A40,A20,A27 | every seeded surface | Blueprint §1.1 | product |
| A02 | Q | Signing in & access states | how do I log in / redirected | How-to+TS | All | Beg | Auth | /seo/login | Available on TEST | P0 | login, sign in, log in, access denied | auth | A03,N02 | login, resolver error | Blueprint §5 | support |
| A03 | Q | SEO access & entitlements | why access required | Explanation | All | Beg | Auth | any | Available on TEST | P0 | no access, entitlement, module access | auth | A02 | access-required state | Blueprint §5 | support |
| N02 | Q | Fixing "resolution error" | error loading access | TS | All | Beg | Auth | any | Available on TEST | P1 | resolver error, cannot load, retry | auth | A02 | resolver error state | Blueprint §5,§21 | support |
| A04 | C | Workspaces & the active website | workspace, switch site | Explanation | All | Beg | Nav | any | Available on TEST | P0 | workspace, switch website, active site, wrong data | nav | A32,A01 | header selector, wrong-site TS | Blueprint §6 | product |
| A05 | C | Adding a website | how add website | How-to | Owner/Admin/Team | Beg | Websites | /seo/websites | Available on TEST | P0 | add site, new website, create website | setup | A06,A07 | websites empty | Blueprint §7 | support |
| A06 | C | Completing business onboarding | fill business profile | How-to | Owner/Admin/Team | Beg | Onboarding | /seo/onboarding | Available on TEST | P0 | onboarding, business profile, setup profile | setup | A05,A07 | onboarding page | Blueprint §7 | product |
| A07 | D | Verifying domain ownership (DNS TXT) | verify my website | How-to+Video | Owner/Admin | Beg | Ownership | /seo/websites | Available on TEST (LOCKED) | P0 | verify, dns, txt, prove ownership, verify domain | ownership,dns | A08,A09,A38 | ownership panel (unverified) | P1a signoff | product |
| A08 | D | Ownership "pending" — what it means | still pending | FAQ+TS | Owner/Admin | Beg | Ownership | /seo/websites | Available on TEST | P0 | pending, not verifying, dns propagate | ownership | A07,A38 | ownership pending badge | Blueprint §8 | support |
| A09 | O | Who can verify ownership | team can't verify | Role guide | Team/Client | Beg | Ownership | /seo/websites | Available on TEST | P1 | permission, role, cannot verify | roles | A31 | ownership read-only | Blueprint §3,§8 | support |
| A38 | D | Keep your verification token safe | is the token secret | Explanation+FAQ | Owner/Admin | Beg | Ownership | /seo/websites | Available on TEST | P0 | token, challenge, secret, security | security | A07 | ownership DNS block | Blueprint §8,§23 | support |
| A10 | E | Starting & monitoring a crawl | how to crawl / scan site | How-to+Video | Owner/Admin/Team | Beg | Crawl | /seo/audit | Available on TEST (LOCKED) | P0 | crawl, scan, site scan, run crawl, spider | crawl | A11,A12,A39 | crawl panel | 16H signoff | product |
| A11 | E | Understanding crawl statuses | what does queued mean | Explanation+Micro | All | Beg | Crawl | /seo/audit | Available on TEST | P0 | queued, running, failed, status, crawling | crawl,status | A10,A39 | each crawl badge | 16H | support |
| A12 | E | "Ownership must be verified" — crawl rejected | cannot start crawl | TS+FAQ | Owner/Admin/Team | Beg | Crawl | /seo/audit | Available on TEST | P0 | cannot crawl, rejected, blocked crawl, verify first | crawl,ownership | A07,A11 | crawl rejection error | P1b signoff | support |
| A39 | E | Retries vs new crawls | why still queued / retry | Explanation+FAQ | Owner/Admin/Team | Int | Crawl | /seo/audit | Available on TEST | P1 | retry, requeue, stuck, queued long, worker | crawl | A11 | retry_wait, queued status | Blueprint §9 | support |
| N03 | E | Why my crawl stays "Queued" (worker not deployed) | queued forever | FAQ+TS | All | Beg | Crawl | /seo/audit | Coming later | P0 | stuck queued, not crawling, worker, never runs | crawl,honesty | A11,A39,N01 | queued status | Blueprint §1.1,§9 | product |
| A13 | F | Reading your technical audit | read audit results | Report interp | All | Int | Audit | /seo/audit | Demo data | P1 | audit, issues, technical seo, results | audit | A14,A19 | audit page/empty | Blueprint §10 | product |
| A14 | F | Fixing technical SEO issues | how fix issues | Workflow | Owner/Admin/Team | Int | Audit | /seo/audit | Demo data | P1 | fix issues, errors, severity, priority | audit | A13,A16 | audit issue cards | Blueprint §10 | product |
| A15 | G | Where recommendations come from | why these recommendations | Explanation+FAQ | All | Int | Recommendations | /seo/page-optimizer | Demo data | P1 | recommendation, suggestions, source | recs | A16 | optimizer list | Blueprint §11 | product |
| A16 | G | The approval workflow | approve reject | Workflow+Video | Owner/Admin/Team | Beg | Approvals | /seo/approvals | Available on TEST | P0 | approve, reject, review, submit, sign off | approvals | A15,A31 | approvals list/actions | Blueprint §11 | product |
| A17 | H | Content Studio workflow | how use content studio | Workflow+Video | Owner/Admin/Team | Int | Content | /seo/content-studio | Available on TEST (gen preview) | P2 | content, draft, wireframe, brief | content | A18,N04 | studio | Blueprint §12 | product |
| A18 | H | File uploads in Content Studio | upload file | FAQ | Owner/Admin/Team | Beg | Content | /seo/content-studio | Coming later | P3 | upload, attach, asset | content | A17 | asset area | Blueprint §12,§18 | support |
| N04 | H | Content generation is a preview | is content AI generated | FAQ | All | Beg | Content | /seo/content-studio | Preview | P2 | ai content, generate, real content | content,honesty | A17,N01 | studio generate control | Blueprint §12 | product |
| A19 | I | Understanding Page Inventory | what is page inventory | Explanation | All | Beg | Page Inventory | /seo/page-performance | Demo data | P1 | pages, inventory, page list | pages | A20 | inventory empty | Blueprint §13 | product |
| A20 | I | Reading Page Performance | read performance / metrics | Report interp+Video | All | Int | Page Performance | /seo/page-performance | Demo data (LOCKED) | P1 | performance, clicks, impressions, ctr, position, traffic | metrics | A21,N05 | performance table | Page Perf lock | product |
| A21 | I | SEO metrics glossary | what is CTR / position | Explanation+Micro | All | Beg | Page Performance | /seo/page-performance | Demo data | P1 | ctr, impressions, clicks, average position, ranking | metrics | A20,A35 | metric cells | Blueprint §13 | support |
| N05 | I | Why this is not live Google data | is this GSC data | FAQ | All | Beg | Page Performance | /seo/page-performance | Demo data | P0 | gsc, ga4, google data, live, manual_seed | honesty | N01,A20 | source label | Blueprint §13 | product |
| A22 | J | Diagnosing a ranking/traffic decline | why did traffic drop | Workflow+Video | Owner/Admin/Team | Int | Decline Diagnosis | /seo/decline-diagnosis | Demo data | P1 | decline, drop, lost ranking, traffic down, why fell | diagnosis | A20,N06 | diagnosis cards | Blueprint §14 | product |
| N06 | J | These diagnoses are seeded, not live AI | is this AI diagnosis | FAQ | All | Beg | Decline Diagnosis | /seo/decline-diagnosis | Demo data | P1 | ai diagnosis, real, live, seeded | honesty | N01,A22 | diagnosis surface | Blueprint §14 | product |
| A23 | K | Evaluating off-page opportunities | how evaluate opportunity | Workflow | Owner/Admin/Team | Int | Off-Page | /seo/off-page | Available on TEST (LOCKED) | P2 | off page, backlink, opportunity, authority | offpage | A24,A25 | opportunity board | Stage 6 | product |
| A24 | O | Off-page roles & the reject rule | why can't I reject | Role guide+FAQ | Team | Int | Off-Page | /seo/off-page | Available on TEST | P2 | reject, permission, role | roles | A31 | disabled reject | Stage 6 | support |
| A25 | L | Authority campaigns end-to-end | create approve campaign | Workflow+Video | Owner/Admin/Team | Int | Campaigns | /seo/off-page | Available on TEST (LOCKED) | P2 | campaign, submit, approve, return to draft | campaigns | A26,A16 | builder/list | Stage 6 | product |
| A26 | L | Campaign limitations today | can I edit/delete campaign | FAQ | Owner/Admin/Team | Beg | Campaigns | /seo/off-page | Coming later | P3 | edit campaign, delete, tasks | honesty | A25 | campaign list | Blueprint §16 | product |
| A27 | M | AI Visibility (preview) | what is ai visibility | Explanation | All | Int | AI Visibility | /seo/ai-visibility | Preview | P3 | ai visibility, geo, aeo, prompts, mentions | ai | N07,B-academy | ai views | Stage 6 | product |
| N07 | M | AI Visibility data is seeded | is this real AI data | FAQ | All | Beg | AI Visibility | /seo/ai-visibility | Demo data | P1 | seeded, manual_seed, live, model data | honesty | N01,A27 | source label | Blueprint §17 | product |
| A28 | R | Preview modules explained | are these live | Explanation+FAQ | All | Beg | Feature availability | competitors/roadmap/reports/support | Mock-only | P3 | mock, not live, coming soon, competitors, roadmap | honesty | N01,A40 | each mock/placeholder page | Blueprint §18 | product |
| N08 | R | Feature availability at a glance | what's live vs coming | Explanation | All | Beg | Feature availability | /seo/help | Mixed | P0 | availability, what works, live, deferred, roadmap | honesty | A28,A40 | Help home status notice | Status doc | product |
| A29 | N | Report interpretation framework | how read report / review | Report interp+Checklist | Owner/Admin | Int | Reports | /seo/reports | Mock-only | P1 | report, review, interpret, monthly | reports | A30,N05 | reports page | Blueprint §19 | product |
| A30 | N | SEO operating cadence checklist | daily weekly monthly | Checklist | Owner/Admin/Team | Beg | Cadence | any | Available on TEST | P1 | checklist, routine, cadence, weekly review | cadence | A29 | dashboard | Blueprint §20 | product |
| A31 | O | Roles and permissions | who can do what | Role guide | All | Beg | Roles | any | Available on TEST | P0 | roles, permission, owner admin team client, can't | roles | A09,A24 | disabled controls | Blueprint §3 | support |
| A32 | O | Agency multi-client workflow | manage many clients | Workflow | Owner/Admin | Int | Agency | /seo/websites | Available on TEST | P2 | agency, multiple clients, switch client, portfolio | agency | A04 | website selector | Blueprint §3,§6 | product |
| A33 | P | SEO troubleshooting guide | something's wrong | TS | All | Beg | Troubleshooting | any | Available on TEST | P0 | error, broken, not working, help | troubleshoot | all TS | Blueprint §21 | support |
| A34 | A | Digibility SEO FAQ | common questions | FAQ | All | Beg | FAQ | /seo/help | Available on TEST | P0 | faq, questions | faq | — | help home | Blueprint | support |
| A35 | S | Digibility SEO glossary | what does X mean | Glossary | All | Beg | Glossary | /seo/help | Available on TEST | P1 | glossary, define, term, meaning | glossary | A21 | help home | Blueprint §22 | support |
| A36 | T | Support diagnostic runbook | (internal) | Runbook | Internal | — | Support ops | internal | Internal only | P0 | runbook, diagnose, support | internal | A23-support | (internal) | Blueprint §23 | support lead |
| A37 | A | Onboarding webinar | full walkthrough | Video | All | Beg | Orientation | any | Available on TEST (preview) | P1 | webinar, walkthrough, training | video | A01 | help videos | Blueprint §24 | product |
| A40 | R | Preview data vs live data | is this real | Explanation+FAQ | All | Beg | Feature availability | any | Demo data | P0 | real, live, demo, preview, seeded | honesty | N01,N08 | seeded surfaces | Blueprint §1.1 | product |
| N09 | B | Why Digibility vs disconnected tools (positioning) | why Digibility | Concept | All | Beg | Positioning | /seo/help | Available on TEST | P2 | why digibility, vs tools, all in one, operating system | positioning | N10,A01 | help academy | Spec §8 | product+marketing |
| N10 | O | How Digibility complements teams/agencies/freelancers | do I still need an agency | Concept | All | Beg | Positioning | /seo/help | Available on TEST | P2 | agency, freelancer, complement, work together | positioning | N09,A32 | agency section | Spec §8 | product+marketing |
| N11 | Q | Settings & connections status | connect gsc/ga4 | Explanation+FAQ | Owner/Admin | Beg | Settings | /seo/settings | Coming later | P2 | connect, gsc, ga4, integration, settings | settings,honesty | N05,A28 | settings page | Blueprint §18 | product |
| N12 | B | SEO/AEO/GEO academy (20 tutorials) | learn seo aeo geo | Concept path | All | Beg→Adv | Academy | /seo/help | Mixed | P1 | seo, aeo, geo, learn, academy, education | academy | B-all | academy block | Spec §7 | **externalReview** |

*(N12 is the umbrella entry for the 20 academy tutorials specified in Spec §7;
each ships as its own article B01–B20 at authoring time.)*

## 3. Learning paths

| Path | Ordered articles | Duration | Prerequisite | Completion outcome |
|---|---|---|---|---|
| Beginner SEO | B01,B02,B04,B05,B06,B07,B08,B09 | ~50m | none | Understands SEO fundamentals |
| First-day Digibility setup | A01,A02,A04,A05,A06,A07 | ~25m | account | Website added, onboarded, ownership initiated |
| First crawl & audit | A07,A10,A11,N03,A13 | ~25m | verified (or understands why pending) | Crawl started, statuses + audit understood |
| Technical SEO improvement | A13,A14,A19,A20,A16 | ~40m | audit data | Issues prioritized + routed to approval |
| Content workflow | A17,N04,A16 | ~30m | website | Content moved through review/approval |
| Authority-building | A23,A24,A25,A26 | ~35m | off-page data | Opportunities evaluated + campaign run |
| Performance review | A19,A20,A21,N05,A22,N06 | ~40m | performance data | Reads metrics + diagnoses declines (with honesty) |
| Client reporting | A29,A30,A40 | ~25m | reports | Runs a review + communicates preview caveat |
| Agency multi-client | A04,A32,A31 | ~20m | multi-site | Switches clients safely |
| SEO+AEO+GEO strategy | B10,B11,B12,B13,B14,B15,A27,N07 | ~50m | Beginner SEO | Understands the three + Digibility's preview role |

## 4. Search taxonomy (synonym / alias map)

**Canonical → synonyms/abbreviations/misspellings/user-language (grounded in the
two source docs):**

- **crawl** → site scan, scan, spider, crawler, "run a crawl", "check my site", craw, crwal
- **domain ownership verification** → verify website, verify domain, prove ownership, dns verify, site verification, "verify my site"
- **DNS TXT / challenge** → txt record, dns record, verification code, token (⚠ never index a real token value)
- **average position** → search position, ranking, rank, serp position, "where do I rank"
- **impressions** → views in search, appearances, "shown in google"
- **clicks** → search visits, traffic from search
- **CTR** → click through rate, click rate
- **movement / declining** → dropping, going down, losing ranking, "why traffic dropped"
- **Decline Diagnosis** → why traffic dropped, ranking loss, traffic drop, lost visitors, decline
- **audit** → technical seo, site health, issues, errors, scan results
- **recommendation** → suggestion, fix, action, advice
- **approval** → review, sign off, approve, reject, submit
- **Content Studio** → content, drafts, briefs, wireframes, blog
- **Off-Page Authority** → backlinks, links, authority, off page, link building
- **authority campaign** → campaign, outreach, link campaign
- **AI Visibility** → geo, generative engine, ai search, chatgpt visibility, ai answers, llm
- **AEO** → answer engine, answer engine optimization, featured answers
- **GEO** → generative engine optimization, ai/llm optimization
- **role denied** → can't, disabled, permission, "why can't I", not allowed, greyed out
- **"I cannot start crawl"** → crawl blocked, crawl disabled, verify first, rejected
- **preview/mock/seeded** → demo data, fake data, not real, test data, sample
- **workspace / active website** → switch site, wrong data, change website, client
- **access required** → no access, entitlement, locked out, can't log in
- **worker not deployed** → stuck queued, never crawls, queued forever

**Status terms (exact-match anchors):** unverified, pending, verified, failed,
revoked; queued, claimed/preparing, running/crawling, retry_wait, cancelling,
completed, partially_completed, failed, cancelled; draft, pending_approval,
approved, rejected; improving, stable, declining, new, no_data.

## 5. FAQ inventory (by category + priority)

- **A/Start (P0):** Is this data real? · What can I do on day 1? · Is Digibility live in production?
- **Q/Access (P0):** Why "access required"? · Why redirected to login? · How do I reset my password? (→ parent)
- **D/Ownership (P0):** Why still pending after I added the TXT? · Is the token a secret? · Team/client can't verify — why?
- **E/Crawl (P0):** Why is my crawl "Queued" forever? · Why was my crawl rejected? · Retry vs new crawl? · Can a client start a crawl?
- **I/Performance (P0/P1):** Is this live Google data? · What is CTR/position? · Why does a page show "no data"?
- **J/Diagnosis (P1):** Are these diagnoses live AI? · Why is a diagnosis missing?
- **H/Content (P2/P3):** Is content AI-generated? · Why can't I upload a file?
- **L/Campaigns (P3):** Can I edit/delete a campaign? · Why is "Return to Draft" missing?
- **M/AI Visibility (P1/P3):** Is AI Visibility live market data?
- **R/Availability (P0):** What's live vs coming? · Why are Competitors/Roadmap/Reports "preview"?
- **O/Roles (P0):** Who can approve/verify/crawl? · Why is this button disabled?

## 6. Video library architecture

| Playlist | Videos (titles) | Notes |
|---|---|---|
| Getting started | Welcome (preview); Sign in; Add your website; Business onboarding | 30s–4m |
| SEO foundations | What is SEO; Why it matters; How ranking works (externalReview) | 2–10m |
| Website setup | Verify your domain (blur token); Understand ownership states | 2–4m |
| Technical SEO | Reading an audit; Fixing issues | 5–10m |
| Reports & metrics | Reading Page Performance; Metrics in 60s; Report framework | 30s–10m |
| Content workflow | Content Studio walkthrough (label preview) | 5–10m |
| Authority workflow | Evaluating opportunities; Campaign workflow | 5–10m |
| AI visibility | AI Visibility preview (label preview) | 2–4m |
| Roles | Roles explained | 2–4m |
| Troubleshooting | Crawl statuses; "Ownership must be verified"; Why still queued | 30s–2m |

**Per-video spec fields (author at production):** title · length · audience ·
prerequisite · route/screens · voiceover goal · related article · required fixture
(e.g., seeded workspace/website; disposable content) · **sensitive content to blur**
(emails, DNS token, ids that look secret) · update trigger (feature promotion or
UI change).
