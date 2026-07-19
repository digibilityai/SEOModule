-- =============================================================================
-- SEO UI TEST DATASET SEED (TEST DATA ONLY)
-- =============================================================================
--                          ****  TEST DATA ONLY  ****
--                    ****  DO NOT RUN ON PRODUCTION  ****
--
-- Purpose: populate one realistic, non-empty demo dataset on the TEST Supabase
-- project so Supabase-mode UI (Phases 13A-13F) has something to show instead
-- of empty states. This is NOT a correctness/RLS test (see
-- supabase/test/seo_stage2_smoke_test.sql / seo_stage3_content_studio_smoke_test.sql
-- for that) — it is a plain data seed, run once as the privileged SQL Editor
-- ("postgres") role, which bypasses RLS by design for seeding.
--
-- This script:
--   - Does NOT create Supabase Auth users and does NOT insert into auth.users.
--     It requires four EXISTING auth.users UUIDs to be pasted in below.
--   - Does NOT use, require, or mention a service role key. It is meant to be
--     pasted into the Supabase Dashboard SQL Editor and run there (the SQL
--     Editor already runs as a privileged Postgres role on your own project;
--     no key of any kind is entered into this script).
--   - Does NOT modify any migration file and does NOT alter table/RLS/trigger
--     definitions — pure DML (INSERT/ON CONFLICT) against already-applied
--     Stage 1-3 tables.
--   - Does NOT TRUNCATE or DROP anything, and does NOT disable RLS anywhere.
--   - Does NOT touch or reference production. Target the TEST project only.
--   - Is idempotent: every INSERT uses a fixed literal UUID (or the table's
--     own natural unique constraint) with ON CONFLICT DO NOTHING / DO UPDATE,
--     so re-running this script is safe and will not create duplicates or
--     delete anything.
--   - Uses the UUID prefix "44444444-" for every row it creates — a prefix
--     not used by either existing smoke test (which use "aaaaaaaa-" /
--     "bbbbbbbb-" / "cccccccc-" / "dddddddd-" / "eeeeeeee-" / "ffffffff-" for
--     Stage 2 and "33333333-" for Stage 3), so this seed cannot collide with
--     or overwrite either smoke test's fixture rows.
--
-- See SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md for full run instructions,
-- how to find test user UUIDs, expected verification counts, and how to
-- exercise the seeded data in the local UI.
-- =============================================================================

-- =============================================================================
-- SECTION 0 — TEST USER UUIDS (REQUIRED — fill these in before running)
-- =============================================================================
-- Paste four EXISTING Supabase Auth user UUIDs below — one per SEO workspace
-- role this seed will create membership for. These must already exist in
-- auth.users on the TEST project (Dashboard -> Authentication -> Users, or
-- the lookup query in SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md §3-4). This
-- script does NOT create users and does NOT accept an email address here —
-- only a UUID. Pasting an email instead of a UUID will be rejected by the
-- guard below.
--
--   owner_user_id  -> workspace owner (full access)
--   admin_user_id  -> workspace admin (full access, not billing-owner)
--   team_user_id   -> team_member (operational access, cannot mark completed
--                     on high-risk approvals, cannot manage members/billing)
--   client_user_id -> client (restricted: read + low-risk approvals only)
--
-- All four MAY be the same user if you only have one test account, but using
-- four distinct users lets you exercise real role-based UI differences.
-- =============================================================================

SELECT set_config('seoseed.owner_user_id',  '48c479db-aedf-452e-af43-05ed1180baaa',  false);
SELECT set_config('seoseed.admin_user_id',  '9830c4d7-167b-4d78-9179-37b60511bd73',  false);
SELECT set_config('seoseed.team_user_id',   '0723d21f-c02c-4725-851f-575f93f2f58c',   false);
SELECT set_config('seoseed.client_user_id', '6c7a04e0-9985-47c3-aad4-f2f0cc5e092c', false);

-- Guard: refuse to run until every UUID above has been replaced with a real,
-- correctly-formatted UUID. Raises a clear, specific exception naming exactly
-- which value is still a placeholder or is not UUID-shaped (e.g. an email
-- pasted by mistake) — this script never silently proceeds with a bad value.
DO $$
DECLARE
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_pairs text[][] := ARRAY[
    ARRAY['owner_user_id',  'REPLACE_WITH_OWNER_USER_UUID'],
    ARRAY['admin_user_id',  'REPLACE_WITH_ADMIN_USER_UUID'],
    ARRAY['team_user_id',   'REPLACE_WITH_TEAM_USER_UUID'],
    ARRAY['client_user_id', 'REPLACE_WITH_CLIENT_USER_UUID']
  ];
  v_key text;
  v_placeholder text;
  v_value text;
  i int;
BEGIN
  FOR i IN 1 .. array_upper(v_pairs, 1) LOOP
    v_key := v_pairs[i][1];
    v_placeholder := v_pairs[i][2];
    v_value := current_setting('seoseed.' || v_key, true);
    IF v_value IS NULL OR v_value = v_placeholder THEN
      RAISE EXCEPTION 'seoseed.% is still a placeholder — paste a real auth.users UUID at the top of this script before running (see SUPABASE_UI_TEST_DATASET_SEED_GUIDE.md).', v_key;
    END IF;
    IF v_value !~ v_uuid_pattern THEN
      RAISE EXCEPTION 'seoseed.% ("%") is not a valid UUID. Paste the user''s UUID from auth.users, not an email address.', v_key, v_value;
    END IF;
  END LOOP;
END $$;

-- =============================================================================
-- UUID MAP (all fixed, prefix 44444444- ; 4th group's leading hex digit
-- groups rows by category so nothing collides across sections):
--   1 = workspace/subscription        6 = approval items
--   2 = website/connection/onboarding 7 = approval comments
--   3 = audit run                     8 = approval activity
--   4 = audit issues                  9 = content opportunities
--   5 = recommendations               a-f = content plan/draft/comments/activity
-- =============================================================================

SELECT '=== SEO UI TEST DATASET SEED — starting ===' AS step;

-- =============================================================================
-- SECTION 1 — STAGE 1: access, workspace, website, onboarding
-- =============================================================================
SELECT '=== Section 1: Stage 1 (access, workspace, website, onboarding) ===' AS step;

-- 1a. Grant SEO module access to all four test users (idempotent refresh).
INSERT INTO public.user_module_access (user_id, module_name, is_active)
SELECT current_setting('seoseed.' || k)::uuid, 'seo', true
FROM (VALUES ('owner_user_id'), ('admin_user_id'), ('team_user_id'), ('client_user_id')) v(k)
ON CONFLICT (user_id, module_name) DO UPDATE SET is_active = true;

-- 1b. Plan limits — only seeded if missing (matches Stage 1 migration's own
-- seed rows exactly; defensive, in case a project is missing them).
INSERT INTO public.seo_plan_limits
  (plan_tier, website_limit, audit_frequency, content_opportunity_limit, draft_limit,
   tracked_page_limit, tracked_keyword_limit, competitor_limit, ai_prompt_limit,
   offpage_opportunity_limit, expert_support_limit)
VALUES
  ('basic',    1,  'monthly',                       3,  2, 50,   25,   2,  0,   0,   0),
  ('standard', 3,  'weekly',                        10, 5, 250,  150,  5,  10,  50,  5),
  ('pro',      10, 'weekly_plus_change_monitoring', -1, 15, 1000, 1000, 10, 100, -1, -1)
ON CONFLICT (plan_tier) DO NOTHING;

-- 1c. Workspace. The Stage 1 AFTER INSERT trigger auto-adds owner_user_id as
-- an active 'owner' member — do NOT insert that membership row manually.
INSERT INTO public.seo_workspaces (id, name, owner_user_id, plan_tier, status)
VALUES (
  '44444444-0000-0000-0001-000000000001',
  'UI Seed Workspace',
  current_setting('seoseed.owner_user_id')::uuid,
  'standard',
  'active'
)
ON CONFLICT (id) DO NOTHING;

-- 1d. Remaining workspace members: admin / team_member / client.
INSERT INTO public.seo_workspace_members (workspace_id, user_id, seo_role, status)
VALUES
  ('44444444-0000-0000-0001-000000000001', current_setting('seoseed.admin_user_id')::uuid,  'admin',       'active'),
  ('44444444-0000-0000-0001-000000000001', current_setting('seoseed.team_user_id')::uuid,   'team_member', 'active'),
  ('44444444-0000-0000-0001-000000000001', current_setting('seoseed.client_user_id')::uuid, 'client',      'active')
ON CONFLICT (workspace_id, user_id) DO NOTHING;

-- 1e. Subscription (standard, active) for the workspace owner.
INSERT INTO public.seo_subscriptions
  (id, user_id, workspace_id, plan_tier, status, is_addon, period_start, period_end, created_by)
VALUES (
  '44444444-0000-0000-0001-000000000002',
  current_setting('seoseed.owner_user_id')::uuid,
  '44444444-0000-0000-0001-000000000001',
  'standard',
  'active',
  false,
  current_date,
  current_date + interval '30 days',
  current_setting('seoseed.owner_user_id')::uuid
)
ON CONFLICT (id) DO NOTHING;

-- 1f. Primary website.
INSERT INTO public.seo_websites
  (id, workspace_id, website_url, website_name, business_name, industry, target_location,
   website_type, plan_snapshot, setup_status, is_high_risk_industry, is_active, created_by)
VALUES (
  '44444444-0000-0000-0002-000000000001',
  '44444444-0000-0000-0001-000000000001',
  'https://ui-seed-digibility.example',
  'UI Seed Demo Site',
  'Digibility UI Seed Co',
  'Professional Services',
  'Austin, TX',
  'service',
  'standard',
  'connected',
  false,
  true,
  current_setting('seoseed.owner_user_id')::uuid
)
ON CONFLICT (workspace_id, website_url) DO NOTHING;

-- 1g. Connection status snapshot (re-runnable: refreshes on conflict).
INSERT INTO public.seo_connection_status
  (id, website_id, website_url, workspace_id, website_reachable, sitemap_status,
   robots_status, gsc_status, ga4_status, cms_status, gbp_status, last_checked_at)
VALUES (
  '44444444-0000-0000-0002-000000000002',
  '44444444-0000-0000-0002-000000000001',
  'https://ui-seed-digibility.example',
  '44444444-0000-0000-0001-000000000001',
  'connected', 'connected', 'connected',
  'not_connected', 'not_connected', 'not_connected', 'not_connected',
  now()
)
ON CONFLICT (website_id) DO UPDATE SET
  website_reachable = EXCLUDED.website_reachable,
  sitemap_status     = EXCLUDED.sitemap_status,
  robots_status      = EXCLUDED.robots_status,
  gsc_status          = EXCLUDED.gsc_status,
  ga4_status          = EXCLUDED.ga4_status,
  cms_status          = EXCLUDED.cms_status,
  gbp_status          = EXCLUDED.gbp_status,
  last_checked_at     = EXCLUDED.last_checked_at;

-- 1h. Business onboarding (completed, realistic answers).
INSERT INTO public.seo_business_onboarding
  (id, website_id, website_url, workspace_id, services_products, target_audience,
   main_seo_goal, target_locations, competitors, proof_trust_signals, important_pages,
   preferred_content_tone, sensitive_industry, notes, onboarding_status, completion_percentage, created_by)
VALUES (
  '44444444-0000-0000-0002-000000000003',
  '44444444-0000-0000-0002-000000000001',
  'https://ui-seed-digibility.example',
  '44444444-0000-0000-0001-000000000001',
  'SEO audits, content strategy, and technical optimization for small business websites.',
  'Small business owners and marketing teams evaluating SEO providers.',
  'local_visibility',
  ARRAY['Austin, TX', 'Round Rock, TX'],
  ARRAY['https://example-competitor-alpha.com', 'https://example-competitor-beta.com'],
  '10 years in business, 100+ client audits completed, 4.9-star client rating.',
  ARRAY['https://ui-seed-digibility.example/', 'https://ui-seed-digibility.example/services'],
  'friendly',
  'none',
  'Prioritize plain-English explanations over jargon in all recommendations.',
  'completed',
  100,
  current_setting('seoseed.owner_user_id')::uuid
)
ON CONFLICT (website_id) DO UPDATE SET
  services_products      = EXCLUDED.services_products,
  target_audience        = EXCLUDED.target_audience,
  main_seo_goal          = EXCLUDED.main_seo_goal,
  target_locations       = EXCLUDED.target_locations,
  competitors            = EXCLUDED.competitors,
  proof_trust_signals    = EXCLUDED.proof_trust_signals,
  important_pages        = EXCLUDED.important_pages,
  preferred_content_tone = EXCLUDED.preferred_content_tone,
  sensitive_industry     = EXCLUDED.sensitive_industry,
  notes                  = EXCLUDED.notes,
  onboarding_status      = EXCLUDED.onboarding_status,
  completion_percentage  = EXCLUDED.completion_percentage;

-- =============================================================================
-- SECTION 2 — STAGE 2: audit run, issues, recommendations, approval queue
-- =============================================================================
SELECT '=== Section 2: Stage 2 (audit, recommendations, approval queue) ===' AS step;

-- 2a. One completed audit run (is_latest = true; only run for this website,
-- so the partial unique index on (website_id) WHERE is_latest is satisfied).
INSERT INTO public.seo_audit_runs
  (id, workspace_id, website_id, website_url, frequency, status,
   overall_visibility_score, technical_health_score, onpage_score, authority_score,
   ai_discovery_score, issue_count, is_latest, started_at, completed_at, created_by)
VALUES (
  '44444444-0000-0000-0003-000000000001',
  '44444444-0000-0000-0001-000000000001',
  '44444444-0000-0000-0002-000000000001',
  'https://ui-seed-digibility.example',
  'weekly',
  'completed',
  64, 58, 70, 55, 48,
  7,
  true,
  now() - interval '2 days',
  now() - interval '2 days' + interval '15 minutes',
  current_setting('seoseed.owner_user_id')::uuid
)
ON CONFLICT (id) DO NOTHING;

-- 2b. Seven audit issues spanning severity/category/status (is_high_risk_category
-- is trigger-derived from `category` — intentionally omitted here, not fought).
INSERT INTO public.seo_audit_issues
  (id, workspace_id, website_id, website_url, audit_run_id, category, severity, title,
   simple_explanation, why_it_matters, technical_explanation, affected_page_url,
   impact, effort, risk, confidence_percentage, fix_owner, suggested_next_action, status, created_by)
VALUES
  ('44444444-0000-0000-0004-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'speed', 'high',
   'Homepage load time exceeds 4 seconds on mobile',
   'Your homepage takes too long to load on phones, which turns visitors away.',
   'Slow pages rank lower and lose visitors before content even loads.',
   'Largest Contentful Paint measured at 4.3s on 4G throttling; largely image-weight driven.',
   'https://ui-seed-digibility.example/', 'high', 'medium', 'low', 82,
   'developer_needed', 'Compress and lazy-load homepage hero image; defer non-critical scripts.',
   'open', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0004-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'schema', 'medium',
   'Missing LocalBusiness schema markup',
   'Search engines cannot easily tell they are looking at a local business page.',
   'Local business schema improves how you appear in local search results.',
   'No JSON-LD LocalBusiness block detected on the homepage or service pages.',
   'https://ui-seed-digibility.example/', 'medium', 'low', 'low', 90,
   'system_suggestion', 'Add LocalBusiness JSON-LD schema to the homepage.',
   'open', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0004-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'indexability', 'critical',
   'Key service pages blocked by robots.txt',
   'Search engines are currently told not to look at some of your service pages.',
   'Pages blocked from crawling cannot rank in search results at all.',
   'robots.txt disallow rule matches /services/* pattern, blocking 3 indexable pages.',
   'https://ui-seed-digibility.example/services', 'high', 'low', 'medium', 95,
   'developer_needed', 'Remove the overly broad /services/* disallow rule from robots.txt.',
   'open', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0004-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'mobile', 'medium',
   'Tap targets too small on mobile navigation',
   'Menu links are packed too closely together for comfortable tapping on phones.',
   'Hard-to-tap navigation frustrates mobile visitors and can hurt mobile rankings.',
   'Measured tap target spacing averages 6px, below the recommended 8px minimum.',
   'https://ui-seed-digibility.example/', 'medium', 'medium', 'low', 70,
   'developer_needed', 'Increase spacing between mobile nav menu items.',
   'in_review', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0004-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'duplicate_content', 'low',
   'Duplicate meta descriptions across service pages',
   'Several service pages currently share the exact same short summary text.',
   'Unique summaries help each page stand out and describe itself accurately in search results.',
   '4 service pages share an identical meta description tag.',
   'https://ui-seed-digibility.example/services', 'low', 'low', 'low', 88,
   'system_suggestion', 'Write a unique meta description for each service page.',
   'open', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0004-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'broken_links', 'medium',
   '3 broken internal links found in blog archive',
   'Some links on your blog point to pages that no longer exist.',
   'Broken links waste visitor trust and crawl budget, and hurt user experience.',
   '3 internal <a> hrefs returned HTTP 404 during the crawl.',
   'https://ui-seed-digibility.example/blog', 'medium', 'low', 'low', 92,
   'client_action', 'Update or remove the 3 broken internal links in the blog archive.',
   'fixed', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0004-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', 'canonical', 'high',
   'Missing canonical tags on paginated category pages',
   'Search engines may get confused about which version of a paginated page to rank.',
   'Missing canonical tags can split ranking signal across duplicate paginated URLs.',
   'Pages 2+ of the blog archive lack a rel="canonical" tag.',
   'https://ui-seed-digibility.example/blog?page=2', 'high', 'low', 'high', 85,
   'developer_needed', 'Add self-referencing canonical tags to all paginated blog archive pages.',
   'open', current_setting('seoseed.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 2c. Eight recommendations, one per allowed `area`, mixed risk/action_type
-- (is_high_risk_category is trigger-derived from the linked issue — omitted).
INSERT INTO public.seo_recommendations
  (id, workspace_id, website_id, website_url, audit_run_id, issue_id, area, title,
   current_value, suggested_change, why_it_helps, action_type, impact, effort, risk,
   confidence_percentage, status, is_current, created_by)
VALUES
  ('44444444-0000-0000-0005-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', NULL, 'title',
   'Optimize homepage title tag for local intent',
   'UI Seed Demo Site | Home',
   'UI Seed Demo Site | SEO Audits & Local Visibility in Austin, TX',
   'Including the location and service in the title improves local search matching.',
   'auto_suggest', 'medium', 'low', 'low', 88, 'suggested', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', NULL, 'meta_description',
   'Rewrite meta description for the services page',
   'Learn about our services.',
   'See our full range of SEO services for small businesses in Austin, TX — audits, content, and technical fixes.',
   'A specific, benefit-led description improves click-through from search results.',
   'auto_suggest', 'low', 'low', 'low', 82, 'approved', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', NULL, 'h1',
   'Add a descriptive H1 to the blog listing page',
   NULL,
   'Add H1: "SEO Insights & Guides for Small Businesses"',
   'A clear H1 helps both visitors and search engines understand the page topic.',
   'manual_support', 'medium', 'low', 'low', 75, 'needs_review', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', '44444444-0000-0000-0004-000000000002', 'schema',
   'Add LocalBusiness schema markup',
   NULL,
   'Add JSON-LD LocalBusiness structured data to the homepage, including address and hours.',
   'Structured data improves eligibility for rich local search results.',
   'approval_required', 'medium', 'medium', 'medium', 70, 'needs_review', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', NULL, 'internal_links',
   'Add internal links from blog posts to service pages',
   NULL,
   'Link relevant blog posts to the matching service page using descriptive anchor text.',
   'Internal links help search engines discover and rank service pages, and guide visitors toward conversion.',
   'manual_support', 'medium', 'medium', 'low', 68, 'suggested', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', NULL, 'content',
   'Expand thin service page content with FAQs',
   NULL,
   'Add a 3-5 question FAQ section addressing common client questions on each service page.',
   'Longer, question-focused content captures more long-tail search queries and improves topical depth.',
   'manual_support', 'high', 'high', 'low', 65, 'suggested', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', '44444444-0000-0000-0004-000000000003', 'technical',
   'Unblock service pages from robots.txt',
   'Disallow: /services/*',
   'Remove the /services/* disallow rule from robots.txt so service pages can be crawled and indexed.',
   'Blocked pages cannot rank at all; unblocking is required before any other service-page SEO work matters.',
   'expert_review', 'high', 'low', 'high', 92, 'expert_review_requested', true,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0005-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0003-000000000001', NULL, 'faq',
   'Add a standalone FAQ page',
   NULL,
   'A dedicated /faq page was considered but would duplicate content already planned for service-page FAQs.',
   'Avoids diluting topical relevance by splitting FAQ content across two competing page types.',
   'avoid', 'low', 'low', 'low', 40, 'rejected', true,
   current_setting('seoseed.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 2d. Seven approval items linked to seven of the eight recommendations above,
-- covering the full requested status spread (suggested/approved/rejected/
-- expert_review_requested/developer_needed/completed) plus ready_to_publish.
-- issue_id mirrors the linked recommendation's issue_id so the trigger-derived
-- is_high_risk_category stays internally consistent.
INSERT INTO public.seo_approval_items
  (id, workspace_id, website_id, website_url, recommendation_id, issue_id, title, page_url,
   simple_explanation, suggested_change, action_type, impact, effort, risk, confidence_percentage,
   fix_owner, status, assignee_user_id, created_by)
VALUES
  ('44444444-0000-0000-0006-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000001', NULL,
   'Optimize homepage title tag for local intent', 'https://ui-seed-digibility.example/',
   'Update the homepage title to mention your service and location.',
   'UI Seed Demo Site | SEO Audits & Local Visibility in Austin, TX',
   'auto_suggest', 'medium', 'low', 'low', 88, 'system_suggestion', 'suggested', NULL,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0006-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000002', NULL,
   'Rewrite meta description for the services page', 'https://ui-seed-digibility.example/services',
   'Replace the generic services page description with a specific, benefit-led one.',
   'See our full range of SEO services for small businesses in Austin, TX — audits, content, and technical fixes.',
   'auto_suggest', 'low', 'low', 'low', 82, 'system_suggestion', 'approved', NULL,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0006-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000003', NULL,
   'Add a descriptive H1 to the blog listing page', 'https://ui-seed-digibility.example/blog',
   'Add a clear, descriptive H1 heading to the blog listing page.',
   'Add H1: "SEO Insights & Guides for Small Businesses"',
   'manual_support', 'medium', 'low', 'low', 75, 'client_action', 'rejected', NULL,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0006-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000004', '44444444-0000-0000-0004-000000000002',
   'Add LocalBusiness schema markup', 'https://ui-seed-digibility.example/',
   'Add structured data so search engines recognize this as a local business.',
   'Add JSON-LD LocalBusiness structured data to the homepage, including address and hours.',
   'approval_required', 'medium', 'medium', 'medium', 70, 'developer_needed', 'developer_needed',
   current_setting('seoseed.team_user_id')::uuid, current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0006-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000005', NULL,
   'Add internal links from blog posts to service pages', 'https://ui-seed-digibility.example/blog',
   'Link relevant blog posts to the matching service page.',
   'Link relevant blog posts to the matching service page using descriptive anchor text.',
   'manual_support', 'medium', 'medium', 'low', 68, 'system_suggestion', 'ready_to_publish', NULL,
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0006-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000006', NULL,
   'Expand thin service page content with FAQs', 'https://ui-seed-digibility.example/services',
   'Add an FAQ section addressing common client questions to each service page.',
   'Add a 3-5 question FAQ section addressing common client questions on each service page.',
   'manual_support', 'high', 'high', 'low', 65, 'digibility_expert', 'completed', NULL,
   current_setting('seoseed.owner_user_id')::uuid),

  ('44444444-0000-0000-0006-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0005-000000000007', '44444444-0000-0000-0004-000000000003',
   'Unblock service pages from robots.txt', 'https://ui-seed-digibility.example/services',
   'Remove the robots.txt rule currently blocking service pages from search engines.',
   'Remove the /services/* disallow rule from robots.txt so service pages can be crawled and indexed.',
   'expert_review', 'high', 'low', 'high', 92, 'developer_needed', 'expert_review_requested', NULL,
   current_setting('seoseed.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 2e. Approval comments (append-only).
INSERT INTO public.seo_approval_comments
  (id, workspace_id, website_id, website_url, approval_item_id, author_user_id, actor_role_snapshot, comment_text)
VALUES
  ('44444444-0000-0000-0007-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000001', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'Looks safe to auto-apply — no conflicts with existing meta content.'),

  ('44444444-0000-0000-0007-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000004', current_setting('seoseed.client_user_id')::uuid, 'client',
   'Please confirm this needs a developer before we schedule it.'),

  ('44444444-0000-0000-0007-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000007', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'Escalating to our SEO expert given the search-visibility risk on this indexability issue.')
ON CONFLICT (id) DO NOTHING;

-- 2f. Approval activity (append-only) — a "created" row for every item, plus
-- a "status_changed" row for the ones whose status moved past "suggested".
INSERT INTO public.seo_approval_activity
  (id, workspace_id, website_id, website_url, approval_item_id, actor_user_id, actor_role_snapshot,
   activity_type, from_status, to_status, note)
VALUES
  ('44444444-0000-0000-0008-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000001', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),

  ('44444444-0000-0000-0008-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000002', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),
  ('44444444-0000-0000-0008-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000002', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'status_changed', 'suggested', 'approved', 'Low-risk auto-suggestion approved.'),

  ('44444444-0000-0000-0008-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000003', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),
  ('44444444-0000-0000-0008-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000003', current_setting('seoseed.client_user_id')::uuid, 'client',
   'status_changed', 'suggested', 'rejected', 'Client preferred to keep the existing heading.'),

  ('44444444-0000-0000-0008-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000004', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),
  ('44444444-0000-0000-0008-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000004', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'developer_needed', 'suggested', 'developer_needed', 'Schema markup requires a developer to implement safely.'),

  ('44444444-0000-0000-0008-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000005', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),
  ('44444444-0000-0000-0008-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000005', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'status_changed', 'suggested', 'ready_to_publish', 'Internal linking change approved and queued.'),

  ('44444444-0000-0000-0008-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000006', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),
  ('44444444-0000-0000-0008-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000006', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'completed', 'suggested', 'completed', 'FAQ content expansion completed and published.'),

  ('44444444-0000-0000-0008-000000000012', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000007', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'created', NULL, 'suggested', 'Approval item generated from recommendation.'),
  ('44444444-0000-0000-0008-000000000013', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0006-000000000007', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'expert_review_requested', 'suggested', 'expert_review_requested', 'High-risk robots.txt change escalated to an SEO expert.')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SECTION 3 — STAGE 3: Content Studio (3 opportunities, mixed status)
-- =============================================================================
SELECT '=== Section 3: Stage 3 (Content Studio) ===' AS step;

-- 3a. Three content opportunities in different lifecycle stages.
INSERT INTO public.seo_content_opportunities
  (id, workspace_id, website_id, website_url, title, target_keyword, content_type,
   search_intent, funnel_stage, difficulty, opportunity_score, reason, brief_notes, is_custom, status, created_by)
VALUES
  ('44444444-0000-0000-0009-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'SEO Checklist for Small Business Websites', 'seo checklist for small business', 'guide',
   'informational', 'awareness', 'low', 72,
   'High search volume, low competition entry point for new SEO customers.',
   'Keep it scannable — small business owners want a practical checklist, not theory.',
   false, 'plan_ready', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0009-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'How to Improve Local Search Visibility', 'improve local search visibility', 'blog_post',
   'informational', 'consideration', 'medium', 65,
   'Captures high-intent local business owners actively looking to improve visibility.',
   'Tie back to Google Business Profile and citation consistency.',
   false, 'draft_in_progress', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-0009-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   'AI Search Visibility Guide for Founders', 'ai search visibility guide', 'guide',
   'informational', 'consideration', 'medium', 80,
   'Emerging search behavior; early content captures a growing search category.',
   'Written for founders, not SEO specialists — keep it practical and jargon-light.',
   false, 'ready_for_manual_publish', current_setting('seoseed.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 3b. Keyword plans (one per opportunity).
INSERT INTO public.seo_content_keyword_plans
  (id, workspace_id, website_id, website_url, content_opportunity_id, primary_keyword,
   secondary_keywords, semantic_keywords, question_keywords, intent, difficulty,
   business_relevance, why_it_matters, created_by)
VALUES
  ('44444444-0000-0000-000a-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000001', 'seo checklist for small business',
   ARRAY['small business seo checklist', 'seo checklist 2026'],
   ARRAY['on-page seo', 'technical seo basics'],
   ARRAY['what is an seo checklist'],
   'informational', 'low',
   'Attracts small business owners early in their SEO research, positioning Digibility as an approachable expert.',
   'High search volume, low competition entry point for new SEO customers.',
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000a-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', 'improve local search visibility',
   ARRAY['local seo tips', 'google business profile optimization'],
   ARRAY['local pack rankings', 'nap consistency'],
   ARRAY['how to rank higher in local search'],
   'informational', 'medium',
   'Directly maps to a core value proposition for local-business SEO clients.',
   'Captures high-intent local business owners actively looking to improve visibility.',
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000a-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', 'ai search visibility guide',
   ARRAY['ai search optimization', 'geo seo'],
   ARRAY['generative engine optimization', 'ai discovery'],
   ARRAY['how does ai search work for businesses'],
   'informational', 'medium',
   'Positions Digibility ahead of the AI-search trend for founder/marketer audiences.',
   'Emerging search behavior; early content captures a growing search category.',
   current_setting('seoseed.team_user_id')::uuid)
ON CONFLICT (content_opportunity_id) DO NOTHING;

-- 3c. Competitor summaries (one per opportunity).
INSERT INTO public.seo_content_competitor_summaries
  (id, workspace_id, website_id, website_url, content_opportunity_id, competitor_title,
   competitor_url, what_they_covered, what_they_missed, our_opportunity, content_gap_angle, created_by)
VALUES
  ('44444444-0000-0000-000b-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000001', 'Ultimate SEO Checklist by ExampleCo',
   'https://example-competitor-one.com/seo-checklist',
   'Basic on-page checklist items.', 'No guidance on local or AI search.',
   'Cover local + AI visibility alongside traditional on-page basics.',
   'Broaden the checklist beyond on-page basics.', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000b-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', 'Local SEO 101 by CompetitorHub',
   'https://example-competitor-two.com/local-seo-101',
   'Google Business Profile setup steps.', 'No mention of review strategy or citation consistency.',
   'Add a citation-consistency and review-response section.',
   'Deeper actionable steps beyond basic GBP setup.', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000b-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', 'AI Search Trends by SearchInsightsBlog',
   'https://example-competitor-three.com/ai-search-trends',
   'High-level trend commentary.', 'No practical founder-focused action steps.',
   'Provide a concrete checklist founders can act on this quarter.',
   'Trend piece vs. our practical how-to angle.', current_setting('seoseed.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 3d. Wireframes — only for opportunities that have reached the wireframe
-- stage (opp #1 is still at plan_ready, so it has none yet).
INSERT INTO public.seo_content_wireframes
  (id, workspace_id, website_id, website_url, content_opportunity_id, suggested_h1,
   intro_angle, cta_suggestion, section_outline, faq_section, internal_link_suggestions,
   schema_suggestion, is_approved, approved_at, approved_by, created_by)
VALUES
  ('44444444-0000-0000-000c-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', 'How to Improve Local Search Visibility for Your Business',
   'Open with the cost of being invisible in local search results.',
   'Book a free local SEO visibility check.',
   ARRAY['Why local search visibility matters', 'Optimize your Google Business Profile',
         'Build consistent local citations', 'Earn and respond to reviews', 'Track your local rankings'],
   ARRAY['How long does local SEO take to show results?', 'Do I need a physical address to rank locally?'],
   ARRAY['/seo/audit', '/seo/content-studio'],
   'LocalBusiness + FAQPage', true, now() - interval '3 days',
   current_setting('seoseed.team_user_id')::uuid, current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000c-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', 'AI Search Visibility Guide for Founders',
   'Frame AI search as the next frontier founders cannot ignore.',
   'Get an AI visibility assessment for your website.',
   ARRAY['What AI search visibility means', 'How AI tools choose which businesses to recommend',
         '5 steps to improve your AI discoverability', 'Common AI visibility mistakes to avoid'],
   ARRAY['Is AI search replacing Google?', 'How do I know if AI tools mention my business?'],
   ARRAY['/seo/ai-visibility', '/seo/audit'],
   'Organization + FAQPage', true, now() - interval '5 days',
   current_setting('seoseed.owner_user_id')::uuid, current_setting('seoseed.owner_user_id')::uuid)
ON CONFLICT (content_opportunity_id) DO NOTHING;

-- 3e. Format inputs — same two opportunities as the wireframes above.
INSERT INTO public.seo_content_format_inputs
  (id, workspace_id, website_id, website_url, content_opportunity_id, format_type,
   reference_url, custom_instructions, created_by)
VALUES
  ('44444444-0000-0000-000d-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', 'default', NULL,
   'Keep tone friendly and approachable; short paragraphs for readability.',
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000d-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', 'match_brand_style',
   'https://ui-seed-digibility.example/blog/example-brand-voice-post',
   'Match the confident, plain-English tone used on our existing blog.',
   current_setting('seoseed.owner_user_id')::uuid)
ON CONFLICT (content_opportunity_id) DO NOTHING;

-- 3f. Drafts (one per opportunity that has reached drafting).
INSERT INTO public.seo_content_drafts
  (id, workspace_id, website_id, website_url, content_opportunity_id, title, created_by)
VALUES
  ('44444444-0000-0000-000e-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', 'How to Improve Local Search Visibility (Draft)',
   current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', 'AI Search Visibility Guide for Founders (Draft)',
   current_setting('seoseed.owner_user_id')::uuid)
ON CONFLICT (content_opportunity_id) DO NOTHING;

-- 3g. Draft sections — draft #1 (opp #2, still draft_in_progress) has mixed
-- statuses to look genuinely "in progress"; draft #2 (opp #3, ready to
-- publish) is fully approved.
INSERT INTO public.seo_content_draft_sections
  (id, workspace_id, website_id, website_url, draft_id, content_opportunity_id, position,
   heading, content, status, regeneration_count, created_by)
VALUES
  ('44444444-0000-0000-000e-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000001', '44444444-0000-0000-0009-000000000002', 0,
   'Why Local Search Visibility Matters',
   'Most customers now find local businesses through search before anything else. If your business is hard to find, you are losing customers to competitors who show up first.',
   'approved', 0, current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000001', '44444444-0000-0000-0009-000000000002', 1,
   'Optimize Your Google Business Profile',
   'Claim and fully complete your Google Business Profile, including hours, photos, and a short, accurate description. For example, list all service areas explicitly rather than relying on a single city name.',
   'edited', 1, current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000001', '44444444-0000-0000-0009-000000000002', 2,
   'Build Consistent Local Citations',
   'Make sure your business name, address, and phone number match exactly across every directory listing. Inconsistent citations confuse both customers and search engines.',
   'generated', 0, current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000002', '44444444-0000-0000-0009-000000000003', 0,
   'What AI Search Visibility Means',
   'AI search visibility means how often, and how favorably, AI tools like chat assistants mention your business when someone asks a relevant question.',
   'approved', 0, current_setting('seoseed.owner_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000002', '44444444-0000-0000-0009-000000000003', 1,
   'How AI Tools Choose Which Businesses to Recommend',
   'AI tools favor businesses with clear, well-structured, and frequently updated information across the web — much of which overlaps with strong traditional SEO fundamentals.',
   'approved', 0, current_setting('seoseed.owner_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000002', '44444444-0000-0000-0009-000000000003', 2,
   '5 Steps to Improve Your AI Discoverability',
   'Keep your business information consistent everywhere, publish clear and specific service pages, earn genuine reviews, use structured data, and monitor how AI tools describe you.',
   'approved', 0, current_setting('seoseed.owner_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 3h. Section revisions (append-only) — history for the one edited section.
INSERT INTO public.seo_content_section_revisions
  (id, workspace_id, website_id, website_url, draft_section_id, content_opportunity_id,
   revision_number, content, reason, created_by)
VALUES
  ('44444444-0000-0000-000e-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000004', '44444444-0000-0000-0009-000000000002', 1,
   'Claim and complete your Google Business Profile with accurate hours and photos.',
   'initial generation', current_setting('seoseed.team_user_id')::uuid),

  ('44444444-0000-0000-000e-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-000e-000000000004', '44444444-0000-0000-0009-000000000002', 2,
   'Claim and fully complete your Google Business Profile, including hours, photos, and a short, accurate description. For example, list all service areas explicitly rather than relying on a single city name.',
   'Tightened wording and added a concrete GBP example per client feedback.', current_setting('seoseed.team_user_id')::uuid)
ON CONFLICT (id) DO NOTHING;

-- 3i. Content comments (append-only).
INSERT INTO public.seo_content_comments
  (id, workspace_id, website_id, website_url, content_opportunity_id, draft_section_id,
   author_user_id, actor_role_snapshot, comment_text)
VALUES
  ('44444444-0000-0000-000f-000000000001', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', NULL,
   current_setting('seoseed.client_user_id')::uuid, 'client',
   'This looks great — can we add a note about review response time?'),

  ('44444444-0000-0000-000f-000000000002', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', '44444444-0000-0000-000e-000000000004',
   current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'Added a concrete GBP optimization example per client feedback.'),

  ('44444444-0000-0000-000f-000000000003', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', NULL,
   current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'Approved — ready to hand off for manual publishing.')
ON CONFLICT (id) DO NOTHING;

-- 3j. Content activity (append-only) — a short realistic lifecycle per opportunity.
INSERT INTO public.seo_content_activity
  (id, workspace_id, website_id, website_url, content_opportunity_id, actor_user_id,
   actor_role_snapshot, activity_type, from_status, to_status, note)
VALUES
  -- Opportunity #1 (SEO Checklist) — early stage.
  ('44444444-0000-0000-000f-000000000004', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000001', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'idea', 'Opportunity added to content plan.'),
  ('44444444-0000-0000-000f-000000000005', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000001', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'status_changed', 'idea', 'plan_ready', 'Keyword research completed; ready to plan.'),

  -- Opportunity #2 (Local Search Visibility) — mid stage.
  ('44444444-0000-0000-000f-000000000006', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'created', NULL, 'idea', 'Opportunity added to content plan.'),
  ('44444444-0000-0000-000f-000000000007', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'status_changed', 'idea', 'plan_ready', 'Keyword research completed; ready to plan.'),
  ('44444444-0000-0000-000f-000000000008', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'wireframe_approved', 'wireframe_internal_review', 'wireframe_approved', 'Wireframe approved internally.'),
  ('44444444-0000-0000-000f-000000000009', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', current_setting('seoseed.team_user_id')::uuid, 'team_member',
   'draft_generated', 'wireframe_approved', 'draft_in_progress', 'First draft generated from the approved wireframe.'),
  ('44444444-0000-0000-000f-000000000010', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000002', current_setting('seoseed.client_user_id')::uuid, 'client',
   'comment_added', NULL, NULL, 'Client left feedback on the draft.'),

  -- Opportunity #3 (AI Search Visibility Guide) — full lifecycle to publish-ready.
  ('44444444-0000-0000-000f-000000000011', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'created', NULL, 'idea', 'Opportunity added to content plan.'),
  ('44444444-0000-0000-000f-000000000012', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'wireframe_approved', 'wireframe_internal_review', 'wireframe_approved', 'Wireframe approved internally.'),
  ('44444444-0000-0000-000f-000000000013', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'draft_generated', 'wireframe_approved', 'draft_in_progress', 'Draft generated from the approved wireframe.'),
  ('44444444-0000-0000-000f-000000000014', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'client_review_sent', 'draft_internal_review', 'draft_client_review', 'Draft sent to client for review.'),
  ('44444444-0000-0000-000f-000000000015', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', current_setting('seoseed.client_user_id')::uuid, 'client',
   'client_approved', 'draft_client_review', 'draft_approved', 'Client approved the draft.'),
  ('44444444-0000-0000-000f-000000000016', '44444444-0000-0000-0001-000000000001',
   '44444444-0000-0000-0002-000000000001', 'https://ui-seed-digibility.example',
   '44444444-0000-0000-0009-000000000003', current_setting('seoseed.owner_user_id')::uuid, 'owner',
   'ready_for_manual_publish', 'draft_approved', 'ready_for_manual_publish', 'Marked ready for manual publish — no live-publish path exists.')
ON CONFLICT (id) DO NOTHING;

-- Note: seo_content_assets / the private seo-content-assets Storage bucket are
-- intentionally NOT seeded — Content Studio Storage/asset wiring is out of
-- scope per Phase 13E (no real upload flow in the current UI). No rows are
-- inserted into storage.objects by this script.

-- =============================================================================
-- SECTION 4 — VERIFICATION (compact row counts for this seed's workspace only)
-- =============================================================================
SELECT '=== Section 4: verification counts ===' AS step;

SELECT entity, count FROM (
  SELECT 1 AS ord, 'workspaces'            AS entity, count(*) AS count FROM public.seo_workspaces            WHERE id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 2, 'websites',                 count(*) FROM public.seo_websites               WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 3, 'workspace members',        count(*) FROM public.seo_workspace_members      WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 4, 'onboarding rows',          count(*) FROM public.seo_business_onboarding    WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 5, 'audit runs',               count(*) FROM public.seo_audit_runs             WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 6, 'audit issues',             count(*) FROM public.seo_audit_issues           WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 7, 'recommendations',          count(*) FROM public.seo_recommendations        WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 8, 'approval items',           count(*) FROM public.seo_approval_items         WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 9, 'approval comments',        count(*) FROM public.seo_approval_comments      WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 10, 'approval activity',       count(*) FROM public.seo_approval_activity      WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 11, 'content opportunities',   count(*) FROM public.seo_content_opportunities  WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 12, 'content drafts',          count(*) FROM public.seo_content_drafts         WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 13, 'content draft sections',  count(*) FROM public.seo_content_draft_sections WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 14, 'content comments',        count(*) FROM public.seo_content_comments       WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
  UNION ALL
  SELECT 15, 'content activity',        count(*) FROM public.seo_content_activity       WHERE workspace_id = '44444444-0000-0000-0001-000000000001'
) v
ORDER BY ord;

SELECT '=== SEO UI TEST DATASET SEED — complete. See counts above. ===' AS done;

-- =============================================================================
-- OPTIONAL TEARDOWN (DESTRUCTIVE — deletes ONLY this seed's workspace and
-- everything that cascades from it: website, onboarding, connection status,
-- audit run/issues, recommendations, approval items/comments/activity,
-- content opportunities and every child row). Leaves the 4 test auth users
-- and their `user_module_access` grants untouched (they may be reused by
-- other seeds/smoke tests). Commented out on purpose — uncomment and run
-- manually only if you want to remove this seed's data from the test project.
-- =============================================================================
-- DELETE FROM public.seo_workspaces WHERE id = '44444444-0000-0000-0001-000000000001';
