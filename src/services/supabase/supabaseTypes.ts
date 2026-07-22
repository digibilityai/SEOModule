// Table / RPC / bucket name constants for the SEO Supabase schema
// (Stage 1-3, applied and test-verified — see BACKEND_MILESTONE_HANDOFF.md).
// Centralizing these avoids typos once services start querying Supabase
// directly. Values must match supabase/migrations/*.sql exactly.
//
// No service currently uses these (Phase 13A only prepares the foundation).

export const SEO_TABLES = {
  // Stage 1 — access / workspaces / websites
  userModuleAccess: "user_module_access",
  planLimits: "seo_plan_limits",
  subscriptions: "seo_subscriptions",
  usageEvents: "seo_usage_events",
  workspaces: "seo_workspaces",
  workspaceMembers: "seo_workspace_members",
  websites: "seo_websites",
  businessOnboarding: "seo_business_onboarding",
  connectionStatus: "seo_connection_status",

  // Stage 2 — audit / recommendations / approval
  auditRuns: "seo_audit_runs",
  auditIssues: "seo_audit_issues",
  recommendations: "seo_recommendations",
  approvalItems: "seo_approval_items",
  approvalComments: "seo_approval_comments",
  approvalActivity: "seo_approval_activity",

  // Stage 3 — content studio
  contentOpportunities: "seo_content_opportunities",
  contentKeywordPlans: "seo_content_keyword_plans",
  contentCompetitorSummaries: "seo_content_competitor_summaries",
  contentWireframes: "seo_content_wireframes",
  contentFormatInputs: "seo_content_format_inputs",
  contentDrafts: "seo_content_drafts",
  contentDraftSections: "seo_content_draft_sections",
  contentSectionRevisions: "seo_content_section_revisions",
  contentComments: "seo_content_comments",
  contentActivity: "seo_content_activity",
  contentAssets: "seo_content_assets",

  // Stage 4 — page performance tracker
  pageInventory: "seo_page_inventory",
  pageKeywords: "seo_page_keywords",
  pagePerformanceSnapshots: "seo_page_performance_snapshots",
  pagePerformanceLatestView: "seo_page_performance_latest",

  // Stage 5 — decline diagnosis engine
  declineDiagnoses: "seo_decline_diagnoses",
  declineDiagnosisEvidence: "seo_decline_diagnosis_evidence",
  declineDiagnosesCurrentView: "seo_decline_diagnoses_current",

  // Stage 6 — off-page authority + AI visibility/GEO
  authorityOpportunities: "seo_authority_opportunities",
  authorityCampaigns: "seo_authority_campaigns",
  authorityCampaignTasks: "seo_authority_campaign_tasks",
  authorityCampaignOpportunities: "seo_authority_campaign_opportunities",
  authorityActivity: "seo_authority_activity",
  aiPromptTracking: "seo_ai_prompt_tracking",
  aiContentGaps: "seo_ai_content_gaps",
  aiMentions: "seo_ai_mentions",

  // Phase 16C — crawler control plane (migration 20260713120025). Job-control /
  // status / append-only event / per-attempt (internal) tables. NOT yet consumed
  // by any frontend service (no crawl UI this phase).
  crawlJobs: "seo_crawl_jobs",
  crawlAttempts: "seo_crawl_attempts",
  crawlEvents: "seo_crawl_events",
  // Phase 16E (Crawler 1C) — worker-owned discovery storage (migration
  // 20260714120027). Customer-readable (own workspace) via RLS; no customer
  // writes. Not yet consumed by any frontend service.
  crawlDiscoveredPages: "seo_crawl_discovered_pages",
  crawlSitemaps: "seo_crawl_sitemaps",
  // Phase 16F (Crawler 1D) — extraction snapshots + deterministic findings
  // (migration 20260714120028). Customer-readable (own workspace) via RLS; no
  // customer writes. NOT the published Audit/Page-Inventory (Phase 1E).
  crawlPageSnapshots: "seo_crawl_page_snapshots",
  crawlIssues: "seo_crawl_issues",
  // Phase 16G (Crawler 1E) — publishing (migration 20260714120029). Publication
  // evidence + the deterministic issue-code→Audit mapping. Publications are
  // customer-readable (own workspace) via RLS; the mapping is reference data.
  // Published customer data lands in the EXISTING seo_page_inventory /
  // seo_audit_issues tables (read via their existing services, not these).
  crawlPublications: "seo_crawl_publications",
  crawlIssueAuditMap: "seo_crawl_issue_audit_map",

  // P1a — Domain Ownership Verification (migration 20260716120031). ONLY the
  // customer-safe verification-state table is listed here for the frontend: the
  // append-only event audit and the INTERNAL claim/lease ledger
  // (seo_ownership_verification_claims) are deliberately NOT exposed — the
  // frontend never reads them (claims are global-admin-only; lease tokens /
  // worker ids / internal diagnostics must never reach the client).
  ownershipVerifications: "seo_ownership_verifications",

  // Reports Stage 1 — persisted progress reports (migration 20260720120035).
  // Customer-readable (own workspace) via RLS; read-only from the frontend
  // (no write RPC / generation ships in Stage 1).
  reports: "seo_reports",

  // Competitor Benchmarking Stage 1 — persisted competitor rows (migration
  // 20260720123000). Workspace/website-scoped RLS (member SELECT incl. client;
  // owner/admin/team_member write). Scores are truthful heuristic ESTIMATES
  // (data_provenance='estimated'), never external measured data.
  competitors: "seo_competitors",
} as const;

export type SeoTableName = (typeof SEO_TABLES)[keyof typeof SEO_TABLES];

// Stage 1 access-check helpers + Stage 2/3 SECURITY DEFINER RPCs. Stage 1
// helpers have no explicit GRANT EXECUTE in their migration, so they rely on
// Postgres's default PUBLIC execute grant — callable via supabase.rpc() for
// an authenticated user, but callers should still handle an RPC error
// gracefully (e.g. if EXECUTE was later revoked on the target project).
export const SEO_RPCS = {
  hasSeoModuleAccess: "has_seo_module_access",
  // Stage 1 capability helper (migration `…120001`): SECURITY DEFINER, STABLE,
  // `seo_is_global_admin(uid uuid DEFAULT auth.uid())` — reads `public.profiles`
  // for global-admin status. No explicit REVOKE, so it is PostgREST-callable by
  // an authenticated user (`supabase.rpc()`). Used by Phase 16B's route guard to
  // gate `/seo/admin-preview`; the RLS policies remain the authoritative check.
  seoIsGlobalAdmin: "seo_is_global_admin",
  runAudit: "seo_run_audit",
  supersedeRecommendation: "seo_supersede_recommendation",
  approvalTransition: "seo_approval_transition",
  contentTransition: "seo_content_transition",
  // Stage 6 guarded transition RPCs. Not called by any frontend code yet —
  // this phase is read-only (see PHASE_15A_STAGE6_OFFPAGE_AI_VISIBILITY_WIRING_NOTES.md
  // §7 for why) — listed here for documentation/future-use, same precedent as
  // approvalTransition/contentTransition being named before Phase 13D/13E wired them.
  authorityOpportunityTransition: "seo_authority_opportunity_transition",
  authorityCampaignTransition: "seo_authority_campaign_transition",
  // Stage 6 (Phase 15D) — atomic draft campaign creation (migration
  // 20260712120024). One SECURITY DEFINER call creates the campaign row (in
  // `draft`) + its junction links + its tasks in a single transaction.
  authorityCampaignCreate: "seo_authority_campaign_create",
  // Phase 16C — crawler control-plane RPCs (migration 20260713120025). Guarded
  // customer request/cancel (EXECUTE = authenticated only, in-function owner/
  // admin/team_member-or-global-admin gate; client denied). crawlClaimJob is
  // SERVICE-ROLE ONLY (the future worker) — NOT callable by the frontend and
  // listed here for documentation only. No frontend crawl service exists yet.
  crawlRequest: "seo_crawl_request",
  crawlCancel: "seo_crawl_cancel",
  crawlClaimJob: "seo_crawl_claim_job",
  // Phase 16D (Crawler 1B) — SERVICE-ROLE-ONLY worker lifecycle RPCs (migration
  // 20260714120026). NOT frontend-callable (the crawler worker runs server-side
  // with the service-role key); listed for documentation/registry completeness.
  crawlWorkerHeartbeat: "seo_crawl_worker_heartbeat",
  crawlWorkerComplete: "seo_crawl_worker_complete",
  crawlWorkerPartial: "seo_crawl_worker_partial",
  crawlWorkerFail: "seo_crawl_worker_fail",
  crawlWorkerScheduleRetry: "seo_crawl_worker_schedule_retry",
  crawlWorkerAcknowledgeCancellation: "seo_crawl_worker_acknowledge_cancellation",
  crawlRecoverStaleJobs: "seo_crawl_recover_stale_jobs",
  // Phase 16E (Crawler 1C) — SERVICE-ROLE-ONLY discovery persistence RPCs
  // (migration 20260714120027). Not frontend-callable; documentation only.
  crawlWorkerRecordDiscovery: "seo_crawl_worker_record_discovery",
  crawlWorkerUpdateDiscoveryProgress: "seo_crawl_worker_update_discovery_progress",
  // Phase 16F (Crawler 1D) — SERVICE-ROLE-ONLY extraction/issue persistence RPCs
  // (migration 20260714120028). Not frontend-callable; documentation only.
  crawlWorkerRecordSnapshots: "seo_crawl_worker_record_snapshots",
  crawlWorkerRecordIssues: "seo_crawl_worker_record_issues",
  crawlWorkerUpdateExtractionProgress: "seo_crawl_worker_update_extraction_progress",
  // Phase 16G (Crawler 1E) — publishing (migration 20260714120029).
  // crawlRequestAudit: guarded customer orchestration (EXECUTE = authenticated;
  // in-function owner/admin/team_member-or-global-admin gate) that atomically
  // creates+associates an audit run and a crawl job, returning both ids (no
  // "latest run" guessing). No frontend crawl UI calls it yet. publishResults is
  // SERVICE-ROLE ONLY (the worker); listed for documentation only.
  crawlRequestAudit: "seo_crawl_request_audit",
  crawlWorkerPublishResults: "seo_crawl_worker_publish_results",

  // P1a Step 2A — guarded CUSTOMER ownership-verification RPCs (migration
  // 20260716120032): SECURITY DEFINER, EXECUTE = authenticated only, owner/admin
  // gated in-function. These are the ONLY ownership RPCs the frontend may call.
  // The Step 2B service-role claim/result RPCs and the global-admin override RPC
  // are intentionally NOT listed — they are not frontend-callable.
  ownershipVerificationInitiate: "seo_ownership_verification_initiate",
  ownershipVerificationRecheck: "seo_ownership_verification_recheck",
  ownershipVerificationReverify: "seo_ownership_verification_reverify",
  ownershipVerificationRevoke: "seo_ownership_verification_revoke",

  // Reports Stage 2 — guarded synchronous report generation (migration
  // 20260720120036). SECURITY DEFINER, EXECUTE = authenticated only; owner/
  // admin/team_member gated in-function; aggregates the six live areas
  // server-side and upserts the canonical seo_reports row.
  reportGenerate: "seo_report_generate",

  // Reports Stage 3 — read-only export authorization (migration 20260720120038).
  // STABLE SECURITY DEFINER, EXECUTE = authenticated only; owner/admin/team_member
  // gated in-function (client/anon/nonmember/cross-tenant denied). Returns the
  // already-persisted canonical seo_reports row for client-side PDF rendering;
  // never regenerates.
  reportExportData: "seo_report_export_data",
} as const;

export type SeoRpcName = (typeof SEO_RPCS)[keyof typeof SEO_RPCS];

// Stage 3 private Storage bucket (public=false; see Stage 3 migration notes).
export const SEO_STORAGE_BUCKETS = {
  contentAssets: "seo-content-assets",
} as const;

export type SeoStorageBucketName = (typeof SEO_STORAGE_BUCKETS)[keyof typeof SEO_STORAGE_BUCKETS];
