# Supabase UI Test Dataset — Seed Guide

**Script:** `supabase/test/seo_seed_ui_test_dataset.sql`

> **TEST DATA ONLY. DO NOT RUN ON PRODUCTION.** This guide and the script it
> documents target the **test** Supabase project only — the same one Stage
> 1-3 migrations and both smoke tests (`seo_stage2_smoke_test.sql`,
> `seo_stage3_content_studio_smoke_test.sql`) were applied and verified
> against (see `BACKEND_MILESTONE_HANDOFF.md`).

---

## 1. Purpose

Frontend service wiring (Phases 13A-13F, see `SERVICE_LAYER_WIRING_PLAN.md`)
is complete: `websiteService`, `businessOnboardingService`, `auditService`,
`recommendationService`, `approvalService`, `contentStudioService`, dashboard
summaries, and the read-only admin preview all have working Supabase paths.
But a freshly-applied test project has **zero rows** in every Stage 1-3
table — so Supabase-mode UI legitimately shows empty states everywhere,
which makes it hard to eyeball whether the wiring actually renders real data
correctly.

This script seeds **one realistic, non-empty workspace** — one website, a
completed audit with issues, a mix of recommendations and approval-queue
items in different statuses, and three Content Studio opportunities at
different lifecycle stages — so you can open the local UI in Supabase mode
and see something that looks like a real, in-progress SEO account instead of
an empty dashboard.

## 2. What This Seed Creates

One workspace ("UI Seed Workspace") with one website
(`https://ui-seed-digibility.example`) and:

| Area | What's created |
|---|---|
| Access | SEO module access for 4 test users; workspace membership as owner/admin/team_member/client |
| Website setup | 1 website, connection status (reachable/sitemap/robots connected), completed business onboarding |
| Audit | 1 completed audit run, 7 issues (mixed severity/category/status) |
| Recommendations | 8 recommendations — one per allowed `area`, mixed risk levels and `action_type` |
| Approval queue | 7 approval items covering `suggested` / `approved` / `rejected` / `developer_needed` / `completed` / `expert_review_requested` / `ready_to_publish`, plus 3 comments and 13 activity rows |
| Content Studio | 3 opportunities ("SEO Checklist for Small Business Websites" at `plan_ready`, "How to Improve Local Search Visibility" at `draft_in_progress`, "AI Search Visibility Guide for Founders" at `ready_for_manual_publish"), with keyword plans, competitor summaries, wireframes, format inputs, drafts, draft sections, one section-revision history, comments, and a realistic activity trail |

**Not seeded (by design):** `seo_content_assets` / the private
`seo-content-assets` Storage bucket (no upload flow exists in the current
UI — see Phase 13E notes), `seo_usage_events`, and anything under Page
Performance / Decline Diagnosis / Off-Page Authority / AI Visibility /
Competitors / Roadmap / Reports / Admin, none of which have Stage 1-3 tables
to seed against.

Every row uses the fixed UUID prefix `44444444-...`, which does not collide
with either existing smoke test (`aaaaaaaa-`/`bbbbbbbb-`/`cccccccc-`/
`dddddddd-`/`eeeeeeee-`/`ffffffff-` for Stage 2, `33333333-` for Stage 3) —
so you can run this seed alongside either or both smoke tests without any
conflict.

## 3. Where to Get Test User UUIDs

The script needs four **existing** `auth.users` UUIDs — one to seed as each
SEO workspace role (owner / admin / team_member / client). It does **not**
create users. If you don't already have test users:

1. Open the **test** Supabase project's Dashboard → **Authentication → Users**.
2. Create (or reuse) up to four users there (email/password, magic link,
   whatever is convenient) — the same way the existing smoke tests expect
   users to already exist.
3. Copy each user's UUID from that same Users table, **or** use the lookup
   query in §4 below.

You can reuse a single user for all four roles if you only have one test
account — the script accepts the same UUID in all four slots.

## 4. Exact SQL to Fetch UUIDs by Email

Run this in the Supabase SQL Editor (test project) to look up UUIDs for
users you already know the email addresses of:

```sql
select id, email
from auth.users
where email in (
  'owner-test@example.com',
  'admin-test@example.com',
  'team-test@example.com',
  'client-test@example.com'
)
order by email;
```

Replace the four email addresses with your actual test users' emails. Copy
each returned `id` (a UUID) into the matching slot described in §5.

## 5. How to Replace Placeholders

Open `supabase/test/seo_seed_ui_test_dataset.sql` and find **Section 0** near
the top:

```sql
SELECT set_config('seoseed.owner_user_id',  'REPLACE_WITH_OWNER_USER_UUID',  false);
SELECT set_config('seoseed.admin_user_id',  'REPLACE_WITH_ADMIN_USER_UUID',  false);
SELECT set_config('seoseed.team_user_id',   'REPLACE_WITH_TEAM_USER_UUID',   false);
SELECT set_config('seoseed.client_user_id', 'REPLACE_WITH_CLIENT_USER_UUID', false);
```

Replace each `'REPLACE_WITH_..._UUID'` string with a real UUID from §4 (or
the Dashboard), for example:

```sql
SELECT set_config('seoseed.owner_user_id',  '11111111-2222-3333-4444-555555555555', false);
```

**Paste a UUID, never an email.** The script's guard block checks the value
is UUID-shaped and will raise a clear exception (naming exactly which
variable is wrong) if you leave a placeholder in place or paste an email by
mistake — it will not run partway and leave a half-seeded workspace.

## 6. How to Run

1. Confirm your Supabase Dashboard is pointed at the **test** project (check
   the project name/URL in the Dashboard — never a production project).
2. Confirm Stage 1, Stage 2, and Stage 3 migrations are already applied
   (see `BACKEND_MILESTONE_HANDOFF.md` §3-4 — all three stages are marked
   test-verified).
3. Open **SQL Editor** in the Supabase Dashboard.
4. Copy the full contents of `supabase/test/seo_seed_ui_test_dataset.sql`.
5. Paste into a new SQL Editor query.
6. Replace the four placeholders per §5.
7. Click **Run**.
8. Read the **Results/Notices** pane — the last result set is a compact
   verification-count table (see §7). If the guard block raised an
   exception instead, fix the named placeholder and re-run — nothing is
   partially applied, since Postgres runs the whole pasted script in one
   session and the guard fails before any `INSERT` executes.

Re-running the whole script is always safe — every insert is
`ON CONFLICT DO NOTHING` / `DO UPDATE`, so running it twice does not create
duplicates or error out.

## 7. Expected Verification Counts

The script's final `SELECT` prints one row per entity for this seed's
workspace only:

| entity | count |
|---|---|
| workspaces | 1 |
| websites | 1 |
| workspace members | 4 |
| onboarding rows | 1 |
| audit runs | 1 |
| audit issues | 7 |
| recommendations | 8 |
| approval items | 7 |
| approval comments | 3 |
| approval activity | 13 |
| content opportunities | 3 |
| content drafts | 2 |
| content draft sections | 6 |
| content comments | 3 |
| content activity | 16 |

If any count is `0` where the table above expects a non-zero value, re-check
the Notices pane for a raised exception from an earlier statement in the
script (Postgres stops running remaining statements after an unhandled
exception in a pasted multi-statement script).

## 8. How to Test in the Local UI

1. In `Digibility-SEO-Module/.env.local`, set:
   ```bash
   VITE_SUPABASE_URL=<test-project-url>
   VITE_SUPABASE_ANON_KEY=<test-project-anon-key>
   VITE_SEO_DATA_MODE=supabase
   ```
   (Restart the dev server after changing `.env.local` — Vite only reads env
   vars at startup.)
2. `npm run dev`.
3. Visit `/seo/dev/auth-test` and sign in as one of the four seeded users
   (real `supabase.auth.signInWithPassword()` — see
   `PHASE_13B1_DEV_AUTH_TEST_NOTES.md`).
4. Click through the dev-harness buttons in order — each should now report
   non-zero counts instead of the empty-state numbers a fresh project shows:
   - **Test website service** → 1 website found.
   - **Test onboarding service** → onboarding record found.
   - **Test audit service** → 1 audit run, status `completed`.
   - **Test recommendation service** → 8 current recommendation(s).
   - **Test approval service** → 7 approval item(s).
   - **Test content opportunity service** → 3 content opportunit(y/ies).
   - **Test content detail service** → keyword plan / wireframe / draft
     present depending on which seeded opportunity you select.
   - **Test Dashboard Summary Service** (Phase 13F) → non-zero top priority
     fixes and pending-approval counts.
   - **Test Admin Preview Read Service** (Phase 13F) → non-zero website/audit/
     recommendation/approval/content counts.
5. Visit the real customer-facing pages directly — `/seo/dashboard`,
   `/seo/websites`, `/seo/onboarding`, `/seo/audit`, `/seo/approvals`,
   `/seo/content-studio`, `/seo/admin-preview` — and confirm each renders the
   seeded data instead of an empty state.
6. Sign in as different seeded roles (owner/admin/team_member/client) to see
   real role-based differences on `/seo/approvals` (e.g. a client cannot
   approve the high-risk "Unblock service pages from robots.txt" item) and
   `/seo/content-studio` (client actions are gated to client-review statuses).

## 9. Warnings

- **Production is never touched.** This script only ever runs against
  whatever project you paste it into — always double-check the Dashboard's
  project name/URL before running, and never point `.env.local` at a
  production Supabase URL.
- **No Supabase Auth users are created.** The script requires four existing
  `auth.users` UUIDs and fails fast with a clear error if any are missing or
  malformed.
- **No service role key is used, required, or referenced anywhere** in this
  script or this guide. It is designed to be pasted into the Dashboard SQL
  Editor, which already runs with sufficient privilege on your own project —
  no key of any kind is entered.
- **Teardown is optional and commented out.** The bottom of the script has a
  single commented-out `DELETE FROM public.seo_workspaces WHERE id = '...'`
  statement that removes only this seed's workspace (and everything that
  cascades from it) if you ever want to clean it up. It does not touch the
  four test auth users or their module-access grants (they may be reused by
  other seeds or the smoke tests).

## 10. Known Limitations

- **No real crawler.** The seeded audit run/issues are realistic hand-written
  data, not the output of an actual site crawl — there is no crawler in
  Stage 2 (see `PHASE_13C_AUDIT_RECOMMENDATION_WIRING_NOTES.md` §7).
- **No real LLM generation.** Recommendation/wireframe/draft content is
  hand-written seed text, not AI-generated — Stage 2/3 have no LLM
  integration yet (see `PHASE_13E_CONTENT_STUDIO_WIRING_NOTES.md` §7).
- **No real GSC/GA4/CMS/GBP integration.** `seo_connection_status` is seeded
  with plausible-looking values, not a real connection check.
- **No real publishing.** `ready_for_manual_publish` / `ready_to_publish` are
  status markers only — nothing in Stage 2/3 (or this seed) reaches a live
  website or CMS.
- **Storage/asset upload is deferred.** `seo_content_assets` and the private
  `seo-content-assets` bucket are intentionally not seeded — the current UI
  has no real upload flow to exercise against them yet.
