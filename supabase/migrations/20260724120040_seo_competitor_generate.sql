-- =============================================================================
-- SEO Backend — Competitor Benchmarking Stage 2A — Migration:
--   guarded generation RPC  public.seo_competitor_generate(p_website_id uuid)
-- =============================================================================
-- Additive only. Builds on Competitor Stage 1 (`public.seo_competitors`,
-- migration 20260720123000 — NOT edited here) and the existing live source
-- tables `seo_websites`, `seo_business_onboarding` (competitor URL list) and
-- `seo_audit_runs` (our latest-audit scores). Introduces ONE guarded
-- SECURITY DEFINER RPC that (re)generates the deterministic local heuristic
-- competitor benchmark set for a website and persists it via replace-to-match.
--
-- SCOPE (Competitor Benchmarking Stage 2A — guarded generation write path):
--   * Server-derived authorization (authenticated; workspace resolved from the
--     website; owner/admin/team_member or global admin; client/anon/nonmember/
--     cross-tenant denied with a single non-leaking error).
--   * NO client-supplied workspace/actor/scores/provenance/timestamps/metadata:
--     the RPC accepts ONLY p_website_id. The competitor URL list is read
--     server-side from seo_business_onboarding.competitors; "our" comparison
--     score is derived server-side from the latest completed audit.
--   * Deterministic local heuristic estimates (NO external provider, NO worker,
--     NO SEMrush/Ahrefs/GSC/measured/observed/verified/live data). Reproduces
--     the repository's confirmed heuristic (src/mocks/competitorMockData.ts
--     `hashStringToRange(url:dimension, 35, 90)` + 5-dimension mean) so the
--     write path matches the read/mock contract — WITHOUT the mock's
--     non-deterministic regenerate "random nudge", so repeated generation
--     against unchanged inputs is STABLE.
--   * Truthful provenance: every persisted row is data_provenance='estimated'
--     (Stage 1 CHECK constraint) with generation_method='heuristic_v1'.
--   * Transaction-scoped advisory lock keyed by (website, generation op) so
--     concurrent/duplicate Generate actions serialize and converge; the Stage 1
--     UNIQUE(website_id, normalized_competitor_url) is the final guarantee.
--   * Replace-to-match: upsert the generated canonical set, then remove stale
--     rows for THIS website that are no longer in the generated set. Other
--     websites / workspaces are never touched.
--   * anon EXECUTE revoked up-front (folded in — no corrective follow-up needed).
--
-- Does NOT touch any locked module, table, RPC, or contract; does NOT edit the
-- applied Stage 1 migration; does NOT weaken RLS, mock mode, or read paths.
--
-- Heuristic parity note (src/services/competitorService.ts + competitorMockData.ts):
--   score(url, dim)  = 35 + (hash(url||':'||dim) % 55),
--                      hash h := 0; for each char c: h := (h*31 + ascii(c)) % 1000
--   overall          = round(mean(content, technical, authority, ai, review))
--   our_overall      = round(mean of 8 audit-derived dimensions) from the latest
--                      completed audit (0 when no completed audit exists)
--   status           = 'stronger' if overall-our_overall > 5,
--                      'weaker'   if overall-our_overall < -5, else 'similar'
--   normalized url    = lower(host), scheme + leading "www." + path/query/
--                      fragment/port stripped (matches the Stage 1 fixtures and
--                      the mock's `new URL(url).hostname.replace("www.","")`).
--   Qualitative text (competitor_name, business_category, target_location,
--   the *_opportunities / what_they_* arrays, suggested_next_action) uses the
--   mock's first-generation defaults on INSERT and is PRESERVED on UPDATE
--   (mirrors the mock's `existing?.field ?? default`).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Internal pure helper: reproduces the mock's hashStringToRange(seed, 35, 90).
-- IMMUTABLE, no table access, SECURITY INVOKER; only ever called internally by
-- the SECURITY DEFINER generate RPC (which runs as the function owner), so no
-- role needs EXECUTE — revoke from PUBLIC to keep the surface tight.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_competitor_heuristic_score(p_seed text)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  h int := 0;
  i int;
BEGIN
  IF p_seed IS NULL THEN
    RETURN 35;  -- min of the [35,90) range; unreachable in normal use
  END IF;
  FOR i IN 1..length(p_seed) LOOP
    h := (h * 31 + ascii(substr(p_seed, i, 1))) % 1000;
  END LOOP;
  RETURN 35 + (h % 55);  -- min + (hash % (max-min)); max-min = 90-35 = 55
END;
$$;

REVOKE ALL ON FUNCTION public.seo_competitor_heuristic_score(text) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Guarded generation RPC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seo_competitor_generate(
  p_website_id uuid
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_ws           uuid;
  v_url          text;
  v_competitors  text[];
  v_url_set      text[];
  v_norm_set     text[];
  v_count        int := 0;
  -- our latest-audit-derived comparison score
  v_a_tech       int := 0;
  v_a_onpage     int := 0;
  v_a_auth       int := 0;
  v_a_ai         int := 0;
  v_our_overall  int := 0;
BEGIN
  -- 1. Authentication.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required to generate competitor benchmarks.';
  END IF;

  -- 2. Resolve website -> workspace + url server-side (never trust a caller
  --    workspace). A missing website yields the SAME generic error as a role
  --    failure so existence never leaks to an unauthorized caller.
  SELECT w.workspace_id, w.website_url INTO v_ws, v_url
  FROM public.seo_websites w
  WHERE w.id = p_website_id;

  IF v_ws IS NULL
     OR NOT (public.seo_role_in(v_ws, ARRAY['owner','admin','team_member'])
             OR public.seo_is_global_admin()) THEN
    RAISE EXCEPTION 'Not authorized to generate competitor benchmarks for this website.';
  END IF;

  -- 3. Concurrency: transaction-scoped advisory lock keyed deterministically to
  --    (website, generation op) so concurrent Generates serialize and converge
  --    (the Stage 1 unique key is the final guarantee).
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_website_id::text || ':competitor_generate', 0));

  -- 4. Server-derived inputs.
  -- 4a. Competitor URL list from business onboarding (NOT client-supplied).
  SELECT o.competitors INTO v_competitors
  FROM public.seo_business_onboarding o
  WHERE o.website_id = p_website_id;
  IF NOT FOUND OR v_competitors IS NULL THEN
    v_competitors := '{}'::text[];
  END IF;

  -- 4b. Our comparison score from the latest COMPLETED audit (parity with
  --     competitorService.computeOurBenchmarkScores + the 8-dimension mean).
  SELECT a.technical_health_score, a.onpage_score, a.authority_score, a.ai_discovery_score
    INTO v_a_tech, v_a_onpage, v_a_auth, v_a_ai
  FROM public.seo_audit_runs a
  WHERE a.website_id = p_website_id AND a.status = 'completed'
  ORDER BY COALESCE(a.completed_at, a.started_at) DESC
  LIMIT 1;
  IF NOT FOUND THEN
    v_a_tech := 0; v_a_onpage := 0; v_a_auth := 0; v_a_ai := 0;
  END IF;

  v_our_overall := round((
        greatest(0, least(100, v_a_tech))          -- technical_health
      + greatest(0, least(100, v_a_onpage))        -- content_depth
      + greatest(0, least(100, v_a_onpage - 5))    -- keyword_coverage
      + greatest(0, least(100, v_a_auth))          -- authority_signals
      + greatest(0, least(100, v_a_auth - 10))     -- reviews_trust
      + greatest(0, least(100, v_a_ai))            -- ai_visibility
      + greatest(0, least(100, v_a_onpage + 3))    -- page_quality
      + greatest(0, least(100, v_a_tech - 8))      -- local_visibility
    )::numeric / 8)::int;

  -- 5. Build the deterministic, deduplicated canonical competitor set as two
  --    parallel arrays (raw url + normalized url), ordered by first appearance.
  --    De-dup is by normalized url (matches the Stage 1 uniqueness contract).
  SELECT array_agg(url ORDER BY ord), array_agg(norm ORDER BY ord)
    INTO v_url_set, v_norm_set
  FROM (
    SELECT DISTINCT ON (norm) url, norm, ord
    FROM (
      SELECT
        u AS url,
        split_part(split_part(split_part(split_part(
          regexp_replace(
            regexp_replace(lower(btrim(u)), '^[a-z][a-z0-9+.\-]*://', ''),
            '^www\.', ''),
          '/', 1), '?', 1), '#', 1), ':', 1) AS norm,
        ord
      FROM unnest(v_competitors) WITH ORDINALITY AS t(u, ord)
    ) raw
    WHERE url IS NOT NULL AND length(norm) > 0
    ORDER BY norm, ord
  ) dedup;

  v_count := COALESCE(array_length(v_norm_set, 1), 0);

  -- 5b. No competitor URLs configured -> nothing to generate. Mirror the mock's
  --     non-destructive early return: do NOT wipe an existing set on an empty
  --     onboarding list (replace-to-match applies only to a derived set).
  IF v_count = 0 THEN
    RETURN 0;
  END IF;

  -- 6. Upsert the generated canonical set (INSERT ... ON CONFLICT DO UPDATE).
  --    Scores/overall/status/generation_method/provenance are refreshed; the
  --    qualitative + authorship fields are preserved on conflict.
  INSERT INTO public.seo_competitors AS c (
    workspace_id, website_id, website_url,
    competitor_name, competitor_url, normalized_competitor_url,
    business_category,
    content_strength_score, technical_health_score, authority_score,
    ai_visibility_score, review_strength_score, overall_strength_score,
    status,
    what_they_do_better, what_they_are_missing, content_opportunities,
    authority_opportunities, ai_visibility_opportunities, suggested_next_action,
    data_provenance, generation_method, created_by
  )
  SELECT
    v_ws, p_website_id, v_url,
    s.norm,                              -- competitor_name default = normalized host
    s.url, s.norm,
    'General business',
    s.content, s.technical, s.authority, s.ai, s.review, s.overall,
    CASE
      WHEN s.overall - v_our_overall > 5  THEN 'stronger'
      WHEN s.overall - v_our_overall < -5 THEN 'weaker'
      ELSE 'similar'
    END,
    ARRAY['Not enough data yet to know specifics — check back after the next benchmark refresh.']::text[],
    '{}'::text[], '{}'::text[], '{}'::text[], '{}'::text[],
    'Review this competitor''s strengths once more data is available.',
    'estimated', 'heuristic_v1', v_uid
  FROM (
    SELECT
      url, norm, content, technical, authority, ai, review,
      round((content + technical + authority + ai + review)::numeric / 5)::int AS overall
    FROM (
      SELECT
        u.url, u.norm,
        public.seo_competitor_heuristic_score(u.url || ':content')   AS content,
        public.seo_competitor_heuristic_score(u.url || ':technical') AS technical,
        public.seo_competitor_heuristic_score(u.url || ':authority') AS authority,
        public.seo_competitor_heuristic_score(u.url || ':ai')        AS ai,
        public.seo_competitor_heuristic_score(u.url || ':review')    AS review
      FROM unnest(v_url_set, v_norm_set) AS u(url, norm)
    ) q
  ) s
  ON CONFLICT (website_id, normalized_competitor_url) DO UPDATE
    SET competitor_url         = EXCLUDED.competitor_url,
        website_url            = EXCLUDED.website_url,
        content_strength_score = EXCLUDED.content_strength_score,
        technical_health_score = EXCLUDED.technical_health_score,
        authority_score        = EXCLUDED.authority_score,
        ai_visibility_score    = EXCLUDED.ai_visibility_score,
        review_strength_score  = EXCLUDED.review_strength_score,
        overall_strength_score = EXCLUDED.overall_strength_score,
        status                 = EXCLUDED.status,
        generation_method      = EXCLUDED.generation_method,
        data_provenance        = 'estimated',
        updated_at             = now();
        -- competitor_name, business_category, target_location, the *_opportunities
        -- / what_they_* arrays, suggested_next_action, created_by, created_at are
        -- intentionally NOT overwritten (preserved across regeneration).

  -- 7. Replace-to-match: remove stale rows for THIS website only (never touches
  --    other websites / workspaces).
  DELETE FROM public.seo_competitors c
  WHERE c.website_id = p_website_id
    AND c.normalized_competitor_url <> ALL (v_norm_set);

  RETURN v_count;
END;
$$;

-- Grants: authenticated-only EXECUTE (the in-function role gate is authoritative);
-- anon revoked up-front (defense in depth) + PUBLIC revoked. Mirrors the
-- seo_crawl_request / seo_report_generate convention with the anon-revoke folded
-- in so no corrective follow-up migration is required.
REVOKE ALL ON FUNCTION public.seo_competitor_generate(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seo_competitor_generate(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.seo_competitor_generate(uuid) TO authenticated;
