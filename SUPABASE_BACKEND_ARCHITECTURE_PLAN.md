# Supabase Backend Architecture Plan (Phase 12A → 12B approved)

Planning document only. **No migrations, tables, service changes, or credentials in this phase.**
Goal: define how to convert the current mock-service SEO module into a real Supabase-backed module that plugs into Digibility Core.

Status: **Section A–K = Phase 12A analysis. Section L = Phase 12B approved decisions (authoritative — overrides any conflicting assumption above).**

> **Phase 16A extension (2026-07-13):** customer-authentication and crawler-runtime
> architecture decisions build additively on this plan's no-BFF / Supabase-direct /
> RLS-authoritative foundation (§B, §F) and its plan/usage design (§G). See
> `ADR_CUSTOMER_AUTHENTICATION_FOR_MVP.md` (Option C hybrid — standalone Supabase
> Auth for MVP + future parent-identity adapter), `ADR_CRAWLER_RUNTIME_ARCHITECTURE.md`
> (Option C hybrid — guarded enqueue RPC/thin Edge Function + dedicated service-role
> worker), and `CRAWLER_PHASE_1_IMPLEMENTATION_PLAN.md`. These are **proposed,
> documentation-only** decisions awaiting operator approval; no implementation.

---

## Approved Architecture Decisions — Phase 12B

These decisions are **final and migration-ready**. They resolve the corresponding Section J open questions.

1. **Temporary `seo_workspaces` approved (J-1).** Use `seo_workspaces` now — Core has no full workspace/client model yet. Keep nullable `core_workspace_id` / `core_profile_id` mapping fields so it merges cleanly into future Core workspace tables. No data migration expected at merge time.
2. **SEO roles live in `seo_workspace_members` (J-2).** Do **not** overload `profiles.role`. `seo_role` is per-membership, so one user can hold different SEO roles across different SEO workspaces/websites.
3. **SEO uses its own `seo_subscriptions` (J-3).** SEO is a paid add-on **and** can be standalone. Do not force SEO into Core's credit-based `user_subscriptions`. Payment-gateway wiring comes later; `status`/`external_ref` are seeded/manual for now.
4. **`client` = low-permission external user** linked to a website/workspace. **Can**: view reports, run audits, comment, request expert support, approve/reject **safe low-risk** items. **Cannot**: publish, approve high-risk technical changes, change URLs/redirects/canonical/noindex/robots.txt/sitemap, or mark items completed. (Refines J-4 — ships as a permission level in `seo_workspace_members`; `seo_clients`/`seo_client_access` remain optional for agency-managed-customer scoping.)
5. **SEO Admin final home = existing Digibility Admin Panel (J-5).** No separate final SEO admin panel. `/seo/admin-preview` and `src/modules/seo-admin/*` are temporary/reusable only; they mount into the Core Admin Panel and reuse Core `is_admin()`.
6. **`website_id` = source of truth, `website_url` = snapshot (J-6).** Every **operational** SEO record stores both `website_id` (FK) and `website_url` (snapshot), preserving historical context if the URL changes later. Pure child rows (comments, sections, tasks, activity) still derive `website_url` via parent.
7. **Audit history preserved (J-7).** Every audit run creates a **new** `seo_audit_runs` row; never replace prior runs. "Latest" is derived (max `completed_at`) or flagged via an `is_latest`/status marker.
8. **Recommendation history preserved (J-8 refinement).** Recommendations link to `audit_run_id` where relevant. Default views show latest/open; older recommendations are retained for reports and roadmap references (supersede via status, don't delete).
9. **Staged backend rollout.** Do not create all tables in one large migration. Migration order (authoritative):
   1. access/module tables
   2. `seo_workspaces` + members
   3. `seo_websites` + onboarding
   4. audit / recommendations / approval
   5. content studio
   6. performance / diagnosis
   7. off-page / AI visibility
   8. competitor / roadmap
   9. support / reports
   10. admin / supporting tables
   11. RLS policies + seed data

> Sections C–H below already reflect these decisions. Where Section J still lists an item as "confirm," items J-1…J-8 are now **CONFIRMED** per the above; J-9 (usage period) and the file-storage note (J-8 original / now re-numbered) remain open — see updated Section J.

---

## A. Existing System Findings (reference app: `digibility-UI-Kit-small`)

Inspected `supabase/migrations/*`, `src/integrations/supabase/*`, `src/contexts/AuthContext.tsx`.

| Area | Finding |
|---|---|
| **Auth** | Supabase Auth on `auth.users`, PKCE flow, single shared `createClient<Database>` client (`src/integrations/supabase/client.ts`). SEO must reuse this — **no new auth**. |
| **User/profile model** | `public.profiles` 1:1 with `auth.users(id)` (cascade). Columns incl. `role`, `plan` (text: free/starter/professional/business/enterprise), `status`, `is_active`, `onboarding_complete`, `created_by`. |
| **Role model** | Enum `user_role = super_admin \| admin \| account_manager \| support \| user`. Single `profiles.role` column — **no separate `user_roles` table**. RLS helpers already exist: `is_admin(uuid)`, `get_user_role(uuid)`, `has_role(uuid, user_role)` (all `SECURITY DEFINER`, read `profiles.role`). **No `owner` / `team_member` / `client` roles at platform level.** |
| **Subscription/billing** | `subscription_master` (plan catalog) + `user_subscriptions` (per-user, **credit-based**, single active per user via `unique(user_id, status)`, `platform = trial\|razorpay\|manual`, `plan_name`). **No module concept, no SEO plans.** |
| **Workspace / client / team / company** | **None exist.** No multi-tenant/agency workspace model. `client_*` tables (`client_facts`, `client_learning_memory`, `client_trend_profiles`) are brand-context tables, not an agency→client access model. Closest multi-entity concept: `visibility_identity_profiles` (a user may hold multiple brand profiles: business/founder/professional). **No website table.** |
| **Supabase patterns in use** | Timestamptz `created_at/updated_at` defaults, `updated_at` triggers, RLS-on-by-default per table, `SECURITY DEFINER` helper fns for role checks, admin RPCs, storage buckets, edge functions (`SendEmail`, `chatbot`, `embed-faq`). Migrations are additive & timestamp-named. |

**Risks for SEO integration**
1. **No workspace/agency/team backend** → SEO's mock `workspace → members → clients` model has no core counterpart. SEO must ship **temporary `seo_*` workspace tables**, designed to later map into a future Core workspace model.
2. **Role mismatch** → platform roles (`super_admin/admin/account_manager/support/user`) ≠ SEO roles (`owner/admin/team_member/client`). SEO roles must live in a **membership layer**, not on `profiles`.
3. **No module-access concept** → need `user_module_access` to support SEO-only / VM-only / both.
4. **Subscription is single-active, credit-based, not module-based** → SEO needs its own module subscription rows; do not overload `user_subscriptions`.
5. **`website` is a net-new anchor entity** owned entirely by SEO.

---

## B. Recommended Backend Architecture

- **Shared auth**: reuse `auth.users` + `public.profiles`. No SEO auth, no SEO login. `auth.uid()` is the identity everywhere.
- **SEO-only access**: a user with *no* VM subscription still gets a `profiles` row via normal signup; SEO access is granted by a row in `user_module_access(module='seo')` + an active `seo_subscriptions`. VM is never required.
- **SEO module access control**: gate all SEO routes/queries on `user_module_access`. A helper `has_seo_access(uuid)` mirrors the existing `is_admin` pattern.
- **SEO workspace/client layer** (temporary): `seo_workspaces` (tenant boundary) + `seo_workspace_members` (per-user SEO role) + optional `seo_clients` / `seo_client_access` for agency→client viewing. Every workspace has `core_workspace_id UUID NULL` and every member row has `core_user_id = auth.uid()`, so the layer can be merged into a future Core workspace model without data migration pain.
- **Website-first records**: `seo_websites` is the anchor. **Every SEO child record carries `website_id` (FK, required) and `website_url` (denormalized snapshot, required)** — matches the current `SeoBaseRecord` shape and the non-negotiable "every SEO record linked to website URL" rule. All also carry `workspace_id`, `user_id` (owner), `created_by`, `created_at`, `updated_at`.
- **Plan & usage control**: plan tier on `seo_subscriptions.plan_tier` (basic/standard/pro); static caps in `seo_plan_limits` (catalog); consumption in `seo_usage_events` (append-only) rolled up into `seo_usage_counters`. Enforcement in service layer + DB `SECURITY DEFINER` guard functions.
- **Admin operations**: read-mostly views over the same tables, gated by platform `is_admin()` / `super_admin`. SEO admin ships as reusable components (already built in `src/modules/seo-admin/`) that will mount inside the **existing Digibility Admin Panel** — no separate final admin schema. Admin-only tables: `seo_admin_notes`, `seo_issue_library`, `seo_prompt_library`, `seo_templates`, `seo_ai_usage_events`, `seo_integration_health`, `seo_qa_review_items`.
- **Future VM integration**: `seo_websites.core_workspace_id` / `core_profile_id` (nullable) provide the join seam. Data exchange (business name, competitors, published content, etc.) happens later via views/RPCs, not schema coupling now.

---

## C. Proposed Core Tables

Grouped. Format per table in Section D. All `seo_*` tables: `id uuid pk`, `created_at`, `updated_at` (+ trigger), and — unless noted "no website" — `workspace_id`, `website_id`, `website_url`, `user_id`, `created_by`.

**Platform / module access** (workspace/website columns N/A — user-scoped)
- `user_module_access` — which modules a user can use (`seo`, `visibility`).
- `seo_subscriptions` — SEO plan tier + status per user/workspace (billing-ready, no gateway).
- `seo_plan_limits` — static plan→limit catalog (basic/standard/pro).
- `seo_usage_events` — append-only usage log.
- `seo_usage_counters` — current-period rollups for fast limit checks.

**SEO workspace / client access**
- `seo_workspaces` — tenant boundary; `core_workspace_id` nullable seam.
- `seo_workspace_members` — user↔workspace with SEO role (owner/admin/team_member/client).
- `seo_clients` — optional agency-managed client entity.
- `seo_client_access` — which client a client-role user may view.

**Website foundation**
- `seo_websites` — anchor entity (the "website URL"); source of `website_url`.
- `seo_business_onboarding` — business context per website (1:1).
- `seo_connection_status` — GSC/GA4/CMS/GBP/sitemap/robots status placeholders per website.

**Audit / recommendation / approval**
- `seo_audit_runs` · `seo_audit_issues` · `seo_recommendations` · `seo_approval_items` · `seo_approval_comments`.

**Content Studio**
- `seo_content_opportunities` · `seo_keyword_plans` · `seo_competitor_content_summaries` · `seo_content_wireframes` · `seo_content_format_inputs` · `seo_content_drafts` · `seo_content_draft_sections` · `seo_content_feedback`.

**Page performance**
- `seo_page_performance` · `seo_mapped_keywords` · `seo_decline_diagnoses` · `seo_refresh_recommendations`.

**Off-page & AI visibility**
- `seo_authority_opportunities` · `seo_authority_campaigns` · `seo_authority_campaign_tasks` · `seo_ai_prompt_tracking` · `seo_ai_content_gaps` · `seo_ai_mentions`.

**Competitor & roadmap**
- `seo_competitors` · `seo_benchmark_comparisons` · `seo_competitor_gaps` · `seo_roadmap_items`.

**Support & reports**
- `seo_support_requests` · `seo_support_comments` · `seo_support_activity` · `seo_progress_reports` · `seo_report_sections`.

**Admin support**
- `seo_admin_notes` · `seo_issue_library` · `seo_prompt_library` · `seo_templates` · `seo_ai_usage_events` · `seo_integration_health` · `seo_qa_review_items`.

---

## D. Table Design Rules & Per-Table Spec

**Universal rules**
- PK: `id uuid default gen_random_uuid()`.
- Timestamps: `created_at timestamptz default now()`, `updated_at timestamptz default now()` + shared `updated_at` trigger.
- Ownership: `created_by uuid references auth.users(id)`; `user_id uuid` = record owner (default `auth.uid()`).
- **Website linkage**: content/audit/performance/etc. records require `website_id uuid references seo_websites(id) on delete cascade` **and** `website_url text not null` (denormalized snapshot for listing/export/history stability).
- Tenant: `workspace_id uuid references seo_workspaces(id)` on all business records.
- Status columns use `text` + `CHECK` (mirror existing app style), not new enums unless reused ≥3 places.
- Child/detail tables (`*_comments`, `*_sections`, `*_tasks`, `*_activity`, `benchmark_comparisons`, `mapped_keywords`) reference their parent and **inherit `website_id`** but may omit `website_url` (derivable via parent) — see Open Question J-6.

**Access / plan**
| Table | Purpose | Key columns | FKs | Website? | Status |
|---|---|---|---|---|---|
| `user_module_access` | module entitlement | `user_id`, `module` (`seo`/`visibility`), `is_active`, `granted_at`, `granted_by` | `user_id→auth.users` | no | via `is_active` |
| `seo_subscriptions` | SEO plan per user/workspace | `user_id`, `workspace_id`, `plan_tier` (basic/standard/pro), `status` (active/trialing/past_due/cancelled), `period_start`, `period_end`, `is_addon`, `external_ref` | `user_id`, `workspace_id` | no | `status` |
| `seo_plan_limits` | limit catalog | `plan_tier`, `website_limit`, `audit_frequency`, `content_opportunity_limit`, `draft_limit`, `tracked_page_limit`, `tracked_keyword_limit`, `competitor_limit`, `ai_prompt_limit`, `offpage_opportunity_limit`, `expert_support_limit` | — | no | — |
| `seo_usage_events` | append-only usage | `user_id`, `workspace_id`, `website_id?`, `metric`, `amount`, `occurred_at` | `workspace_id` | optional | — |
| `seo_usage_counters` | period rollup | `workspace_id`, `metric`, `period_start`, `used_count` | `workspace_id` | no | — |

**Workspace / client**
| Table | Purpose | Key columns | FKs |
|---|---|---|---|
| `seo_workspaces` | tenant | `name`, `owner_user_id`, `core_workspace_id?`, `plan_tier`, `status` | `owner_user_id→auth.users` |
| `seo_workspace_members` | membership + SEO role | `workspace_id`, `user_id`, `seo_role` (owner/admin/team_member/client), `status`, `invited_by` | `workspace_id`, `user_id` |
| `seo_clients` | agency-managed client | `workspace_id`, `client_name`, `contact_user_id?`, `status` | `workspace_id` |
| `seo_client_access` | client viewing scope | `workspace_id`, `client_id`, `user_id`, `access_level` | `client_id`, `user_id` |

**Website foundation**
| Table | Purpose | Website linkage | Notable columns | Status |
|---|---|---|---|---|
| `seo_websites` | anchor | is the source of `website_url` | `website_url` (unique per workspace), `name`, `business_name`, `industry`, `target_location`, `website_type`, `plan`, `is_high_risk_industry`, `core_profile_id?` | `status` active/inactive/archived |
| `seo_business_onboarding` | context (1:1 website) | `website_id`+`website_url` | `services_products`, `target_audience`, `main_seo_goal`, `target_locations[]`, `competitors[]`, `sensitive_industry`, `completion_percentage` | `status` |
| `seo_connection_status` | integration placeholders | `website_id`+`website_url` | `gsc_status`, `ga4_status`, `cms_status`, `gbp_status`, `sitemap_status`, `robots_status` (all `connection_status`) | per-field |

**Audit / recommendation / approval** (all carry website_id+website_url)
| Table | Purpose | Parent FK | Status |
|---|---|---|---|
| `seo_audit_runs` | audit run + scores | website | not_started/running/completed/failed |
| `seo_audit_issues` | issues per run | `audit_id→seo_audit_runs` | open/in_review/approved/fixed/ignored |
| `seo_recommendations` | fixes (audit + on-page) | `issue_id?` | suggested→…→completed |
| `seo_approval_items` | approval queue | `recommendation_id`, `issue_id?` | RecommendationStatus; `is_high_risk_category`, `fix_owner`, `action_type` |
| `seo_approval_comments` | threaded comments | `approval_item_id` | — |

**Content Studio** (website_id+website_url on all; parent = opportunity)
`seo_content_opportunities` (status workflow) → `seo_keyword_plans` (1:1), `seo_competitor_content_summaries` (n), `seo_content_wireframes` (1:1, `is_approved`), `seo_content_format_inputs` (1:1; **filename/metadata only, no file bytes**), `seo_content_drafts` (1:1) → `seo_content_draft_sections` (n, per-section status + `regeneration_count`), `seo_content_feedback` (n, author_role/comment).

**Page performance** (website_id+website_url)
`seo_page_performance` (page metrics + `performance_status`) → `seo_mapped_keywords` (n, primary/secondary), `seo_decline_diagnoses` (n, `page_performance_id`, cause/confidence/priority/fix_owner/needs_expert_support), `seo_refresh_recommendations` (n, `page_performance_id`, arrays of update/add/remove).

**Off-page & AI visibility** (website_id+website_url)
`seo_authority_opportunities` (type/status/`spam_risk_flags[]`/requires_approval) · `seo_authority_campaigns` (`opportunity_ids[]`, approval_status, progress) → `seo_authority_campaign_tasks` (n) · `seo_ai_prompt_tracking` (prompt/visibility_status/`competitors_mentioned[]`/`citation_sources[]`) · `seo_ai_content_gaps` (topic/priority/next_action) · `seo_ai_mentions` (brand/competitor mention rows feeding summaries).

**Competitor & roadmap** (website_id+website_url)
`seo_competitors` (per-dimension scores, strength status, opportunity arrays) · `seo_benchmark_comparisons` (dimension, our vs avg vs strongest, gap_level) · `seo_competitor_gaps` (gap_type/priority/related_module) · `seo_roadmap_items` (week/month/due_period, source, related_module, priority/impact/effort/risk, owner, status).

**Support & reports** (website_id+website_url; support may reference module/item)
`seo_support_requests` (type/priority/urgency/support_mode/related_module/related_item_url/attachment metadata/status/assignee) → `seo_support_comments` (n), `seo_support_activity` (n, timeline) · `seo_progress_reports` (period, snapshot metrics, `next_actions[]`, status) → `seo_report_sections` (n, section key/body).

**Admin support**
`seo_admin_notes` (per website, internal) · `seo_issue_library` (global issue definitions; no website) · `seo_prompt_library` (global; no website) · `seo_templates` (report/outreach/checklist; no website) · `seo_ai_usage_events` (model/cost/request_type; workspace-scoped) · `seo_integration_health` (per website provider status) · `seo_qa_review_items` (high-risk/trust/spam queue; website-scoped).

---

## E. Relationship Model

```
auth.users ──1:1── profiles                        (Core, shared)
auth.users ──1:n── user_module_access              (seo / visibility)
auth.users ──1:n── seo_subscriptions               (module billing)

seo_workspaces ──1:n── seo_workspace_members ──n:1── auth.users
seo_workspaces ──1:n── seo_websites
seo_workspaces ──1:n── seo_clients ──1:n── seo_client_access ──n:1── auth.users

seo_websites ──1:1── seo_business_onboarding
seo_websites ──1:1── seo_connection_status
seo_websites ──1:n── seo_audit_runs ──1:n── seo_audit_issues
seo_audit_issues ──1:n── seo_recommendations ──1:1── seo_approval_items ──1:n── seo_approval_comments
seo_websites ──1:n── seo_content_opportunities ──1:{1|n}── (keyword_plans, wireframes, format_inputs, drafts→sections, feedback, competitor_summaries)
seo_websites ──1:n── seo_page_performance ──1:n── (mapped_keywords, decline_diagnoses, refresh_recommendations)
seo_websites ──1:n── seo_authority_opportunities ; seo_authority_campaigns ──1:n── campaign_tasks
seo_websites ──1:n── seo_ai_prompt_tracking / seo_ai_content_gaps / seo_ai_mentions
seo_websites ──1:n── seo_competitors / benchmark_comparisons / competitor_gaps / roadmap_items
seo_websites ──1:n── seo_support_requests ──1:n── (support_comments, support_activity)
seo_websites ──1:n── seo_progress_reports ──1:n── seo_report_sections
```
Support request: always `website_id`; optionally `related_module` + `related_item_url` (soft link, no hard FK across modules).

---

## F. RLS Strategy

**Model**: SEO role comes from `seo_workspace_members.seo_role` (workspace-scoped), **not** `profiles.role`. Global admin comes from Core `is_admin()` / `super_admin`. New `SECURITY DEFINER` helpers (mirroring existing `is_admin`):
- `has_seo_access(uid)` → row in `user_module_access` where `module='seo' and is_active`.
- `seo_role_in(uid, workspace_id)` → member's `seo_role` or null.
- `is_seo_workspace_member(uid, workspace_id)` → boolean.
- `is_platform_admin(uid)` → reuse Core `is_admin(uid)` (super_admin/admin).

**Baseline**: RLS ON for every `seo_*` table. `TO authenticated`. All access requires `has_seo_access(auth.uid())` AND membership in the row's `workspace_id`.

| Role | Read | Write |
|---|---|---|
| **owner / admin** (SEO) | all rows in their workspace(s) | manage workspace, websites, members, all SEO records, approvals incl. high-risk |
| **team_member** | rows in workspaces they're a member of | run audits, edit content/recs, approve **low-risk only**; cannot delete workspace or change billing |
| **client** | reports + their permitted website/client rows (`seo_client_access`) | run audits, comment, approve/reject **only low-risk, non-high-risk-category** items; **cannot** approve high-risk technical items, publish live, or touch URL/redirect/canonical/noindex/robots/sitemap items |
| **SEO-only user** | identical to their SEO role above; VM absence is irrelevant | same — access driven purely by `user_module_access` + membership |
| **global admin / super_admin** | all SEO rows across all workspaces (admin views) | admin operations; still no live-publish auto-actions |

**High-risk enforcement** (defense in depth): the client "cannot approve high-risk" rule is enforced by a `WITH CHECK` on `seo_approval_items` UPDATE — a client-role member cannot transition an item to `approved` when `is_high_risk_category = true` or `risk <> 'low'`. Mirrors the existing front-end `approvalPermissions.ts`. No table exposes a "publish live" mutation path; publishing stays a human/expert step.

---

## G. Plan & Usage Control

**Where plan lives**: `seo_subscriptions.plan_tier` (per user, or per workspace if agency) — separate from Core `user_subscriptions`. `is_addon=true` when the user also has VM; SEO-only users simply have an SEO subscription and no VM module access. Static limits live in `seo_plan_limits` (seeded from the app's existing `SEO_PLAN_REGISTRY`).

**Mapping (from current plan registry):**
| Metric | Basic | Standard | Pro |
|---|---|---|---|
| Websites | 1 | 3 | 10 |
| Audit frequency | monthly | weekly | weekly + monitoring |
| Content opportunities | 3/mo | 10/mo | unlimited |
| Drafts | 2/mo | 5/mo | 15/mo |
| Tracked pages | 50 | 250 | 1000 |
| Tracked keywords | 25 | 150 | 1000 |
| Competitors | 2 | 5 | 10 |
| AI prompts | 0 | 10/mo | 100/mo |
| Off-page opportunities | checklist | 50/mo | advanced |
| Expert support | pay-per | limited | priority |

**How usage is tracked**: every metered action writes a `seo_usage_events` row; a trigger/RPC increments `seo_usage_counters` for the current period. **How limits are enforced**: (1) service layer checks counter vs `seo_plan_limits` before the action (fast, UX-friendly); (2) a `SECURITY DEFINER` guard RPC re-checks server-side on create (authoritative). **SEO as paid add-on**: `user_module_access(module='seo')` + active `seo_subscriptions`; VM add-on users get `is_addon=true`. **SEO-only users**: same rows, no VM `user_module_access` — everything gates on SEO access, never on VM.

**Billing readiness (no gateway)**: `seo_subscriptions.external_ref` + `status` are populated manually/seed for now; a future webhook (Razorpay, matching Core) flips `status`. No payment code in this phase.

---

## H. Migration Sequence (build order — do NOT write yet)

1. Access/module: `user_module_access`, `seo_plan_limits`, `seo_subscriptions`, `seo_usage_events`, `seo_usage_counters` + helper fns (`has_seo_access`, guards).
2. Workspace/member: `seo_workspaces`, `seo_workspace_members`, `seo_clients`, `seo_client_access` + role helpers.
3. Website/onboarding: `seo_websites`, `seo_business_onboarding`, `seo_connection_status`.
4. Audit/recommendation/approval (5 tables).
5. Content Studio (8 tables).
6. Performance/diagnosis (4 tables).
7. Off-page/AI visibility (6 tables).
8. Competitor/roadmap (4 tables).
9. Support/report (5 tables).
10. Admin/supporting (7 tables).
11. RLS policies (all tables; enable-on-create, policies in one pass after FKs exist).
12. Seed/test data (plan limits catalog, one demo workspace/website mirroring current mock seeds).

Each step = its own timestamped additive migration, matching Core conventions.

---

## I. Mock → Supabase Replacement Plan

The service layer (`src/services/*`) is already the seam: **components call services, services call mock adapters today** → later services call Supabase. UI never imports mock data directly (verified in Phase 11B), so the swap is invisible to components.

**Order to convert (low-risk-first, follows data dependencies):**
1. `websiteService`, `businessOnboardingService` (foundation; everything reads website).
2. `auditService`, `recommendationService`, `approvalService`.
3. `contentStudioService`, `performanceService`.
4. `offPageService`, `aiVisibilityService`, `competitorService`, `roadmapService`.
5. `supportService`, `reportService`.
6. `seoAdminService` last (aggregates all of the above; convert only after its sources are real).

**Keep mock temporarily**: anything simulating a not-built integration — GSC/GA4/CMS/GBP connection status, audit *crawl* results, AI answer tracking, competitor scraping. These stay generated/mock behind real tables until the external integrations land.

**How to avoid breaking UI**:
- Preserve each service's signature and return shape (`toAsync`-style Promises already match Supabase's async).
- Convert one service at a time behind a per-service adapter flag; run mock + Supabase in parallel during cutover.
- Keep `localMockStore` shape-guards (Phase 11B) until a service is fully migrated.
- Replace `MOCK_WORKSPACE_ID` / `MOCK_USER_ID` / `MOCK_CURRENT_ROLE` with values derived from `auth` + `seo_workspace_members` **only when auth wiring lands** (Phase 12C+), not during table creation.

---

## J. Risks & Open Questions

**Resolved in Phase 12B** (see Approved Decisions section — no longer blockers):
- ✅ **J-1 Core workspace model** → temporary `seo_workspaces` approved with `core_workspace_id`/`core_profile_id` seams.
- ✅ **J-2 Roles** → SEO roles live in `seo_workspace_members`, not `profiles`.
- ✅ **J-3 Billing** → SEO gets its own `seo_subscriptions`; not forced into Core `user_subscriptions`.
- ✅ **J-4 Client definition** → low-permission external member (view reports, run audits, comment, request expert support, approve/reject low-risk only; no publish/high-risk/URL-redirect-canonical-noindex-robots-sitemap/mark-completed). `seo_clients`/`seo_client_access` optional for agency scoping.
- ✅ **J-5 Admin panel** → mounts into existing Digibility Admin Panel, reuses Core `is_admin()`; `/seo/admin-preview` temporary only.
- ✅ **J-6 `website_id` vs `website_url`** → `website_id` source of truth, `website_url` snapshot on every operational record; child rows derive via parent.
- ✅ **J-7 / J-8 History** → audit runs and recommendations preserved (append, never replace); recs link to `audit_run_id`; latest/open shown by default, history retained for reports/roadmap.

**Still open** (non-blocking; decide during Phase 12C table authoring):
1. **Content Studio file uploads** — `format_inputs` stores filename/metadata only today. Confirm real file bytes go to a Supabase Storage bucket later (like Core's onboarding bucket), not a DB column. (Recommendation: Storage bucket.)
2. **Usage period source** — confirm `seo_usage_counters` resets on calendar month vs `seo_subscriptions.period_start`. (Recommendation: `period_start`, aligns resets with billing.)

---

## K. Final Recommendation

Phase 12B review is **complete and approved** (see Approved Architecture Decisions). All blocking questions (J-1…J-8) are resolved; only two non-blocking items remain, decidable during table authoring.

> **Next: Phase 12C — Write additive migrations** in the Section H / Decision-9 staged order: access/module → workspaces+members → websites+onboarding → audit/rec/approval → content studio → performance/diagnosis → off-page/AI → competitor/roadmap → support/reports → admin/supporting → **RLS policies + seed last**. One timestamped migration per stage (not one large migration), matching Core conventions. Wire `auth`-derived workspace/user/role (replacing `MOCK_*` constants) only after tables + RLS land.
