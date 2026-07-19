-- =============================================================================
-- SEO Backend — Stage 4 (Phase 14A.1) — Migration 13 of 13: Latest Snapshot View
-- =============================================================================
-- Additive only. Builds on mig 12 (seo_page_performance_snapshots). Read-only
-- convenience view: the single latest snapshot row per (page, keyword)
-- combination, for future dashboard/page-list reads that only care about
-- "now," not full history.
--
-- Not SECURITY DEFINER. Uses `security_invoker = true` (Postgres 15+, already
-- relied on implicitly by this project's Supabase test instance) so the view
-- is evaluated with the QUERYING user's own privileges and therefore inherits
-- seo_page_performance_snapshots' existing RLS policies exactly — a member
-- can see latest snapshots for their workspace(s) only; a non-member sees
-- nothing; no bypass, no duplicated policy logic. This migration does not
-- touch Stage 1-3, Core, or any table's RLS.
-- =============================================================================

CREATE OR REPLACE VIEW public.seo_page_performance_latest
WITH (security_invoker = true)
AS
SELECT DISTINCT ON (s.page_id, s.page_keyword_id)
  s.id,
  s.workspace_id,
  s.website_id,
  s.website_url,
  s.page_id,
  s.page_keyword_id,
  s.page_url,
  s.keyword,
  s.snapshot_date,
  s.period_start,
  s.period_end,
  s.source,
  s.clicks,
  s.impressions,
  s.ctr,
  s.average_position,
  s.previous_clicks,
  s.previous_impressions,
  s.previous_ctr,
  s.previous_average_position,
  s.clicks_delta,
  s.impressions_delta,
  s.ctr_delta,
  s.position_delta,
  s.movement_status,
  s.diagnosis_hint,
  s.imported_at,
  s.created_at
FROM public.seo_page_performance_snapshots s
ORDER BY s.page_id, s.page_keyword_id, s.snapshot_date DESC, s.created_at DESC;

-- Views need their own grant even when the underlying table already grants
-- to `authenticated` — RLS (via security_invoker) still applies per-row on
-- top of this statement-level grant, so this does not widen access.
GRANT SELECT ON public.seo_page_performance_latest TO authenticated;
