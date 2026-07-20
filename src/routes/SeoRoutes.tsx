import { Navigate, Outlet, Route, Routes } from "react-router-dom";
import { Layout } from "@/components/layout/Layout";
import { ProtectedRoute } from "@/routes/ProtectedRoute";
import { SeoLoginPage } from "@/pages/seo/SeoLoginPage";
import { SeoDashboardPage } from "@/pages/seo/SeoDashboardPage";
import { WebsitesPage } from "@/pages/seo/WebsitesPage";
import { BusinessOnboardingPage } from "@/pages/seo/BusinessOnboardingPage";
import { ApprovalQueuePage } from "@/pages/seo/ApprovalQueuePage";
import { WebsiteAuditPage } from "@/pages/seo/WebsiteAuditPage";
import { KeywordResearchPage } from "@/pages/seo/KeywordResearchPage";
import { CompetitorAnalysisPage } from "@/pages/seo/CompetitorAnalysisPage";
import { ContentGapsPage } from "@/pages/seo/ContentGapsPage";
import { BlogBriefsPage } from "@/pages/seo/BlogBriefsPage";
import { ContentStudioPage } from "@/pages/seo/ContentStudioPage";
import { PageOptimizerPage } from "@/pages/seo/PageOptimizerPage";
import { PagePerformancePage } from "@/pages/seo/PagePerformancePage";
import { DeclineDiagnosisPage } from "@/pages/seo/DeclineDiagnosisPage";
import { AuthorityBuilderPage } from "@/pages/seo/AuthorityBuilderPage";
import { AiVisibilityPage } from "@/pages/seo/AiVisibilityPage";
import { RoadmapPage } from "@/pages/seo/RoadmapPage";
import { ExpertSupportPage } from "@/pages/seo/ExpertSupportPage";
import { ReportsPage } from "@/pages/seo/ReportsPage";
import { SeoSettingsPage } from "@/pages/seo/SeoSettingsPage";
import { SeoAdminPreviewPage } from "@/pages/seo/SeoAdminPreviewPage";
import { SupabaseReadinessPage } from "@/pages/seo/dev/SupabaseReadinessPage";
import { SupabaseAuthTestPage } from "@/pages/seo/dev/SupabaseAuthTestPage";
import { HelpHomePage } from "@/pages/help/HelpHomePage";
import { HelpSearchPage } from "@/pages/help/HelpSearchPage";
import { HelpCategoryPage } from "@/pages/help/HelpCategoryPage";
import { HelpArticlePage } from "@/pages/help/HelpArticlePage";
import { HelpDevContentCheckPage } from "@/pages/help/HelpDevContentCheckPage";

// Renders the app shell (Sidebar + Header) around every protected route.
// The customer login route is intentionally rendered OUTSIDE this shell.
function ShellLayout() {
  return (
    <Layout>
      <Outlet />
    </Layout>
  );
}

// Phase 16B — route protection.
// - `/seo/login` is public + chromeless (customer sign-in).
// - Every `/seo/*` product route is wrapped in <ProtectedRoute> (Supabase mode
//   only; mock mode bypasses). Setup routes use `allowSetup`; website-scoped
//   routes use `requireWebsite`; admin preview uses `requireGlobalAdmin`.
// - RLS + guarded RPCs remain the authoritative authorization layer; per-role
//   action gating stays inside the pages (locked Stage 6 behaviour unchanged).
// - `/seo/dev/*` diagnostics are mounted ONLY in development builds.
export function SeoRoutes() {
  return (
    <Routes>
      {/* Public, chromeless */}
      <Route path="/seo/login" element={<SeoLoginPage />} />

      {/* Public Help Center — AUTHENTICATION-FREE, outside the /seo/* protected
          route boundary. These routes must never be wrapped in <ProtectedRoute>
          and must never import useSeoAccess/useResolvedActiveWebsite/role hooks
          (see src/pages/help/HelpShell.tsx). They are reachable signed-out, with
          Supabase config absent, and from a direct/refreshed deep link. */}
      <Route path="/help" element={<HelpHomePage />} />
      <Route path="/help/search" element={<HelpSearchPage />} />
      <Route path="/help/category/:categorySlug" element={<HelpCategoryPage />} />
      <Route path="/help/article/:articleSlug" element={<HelpArticlePage />} />
      {import.meta.env.DEV && (
        <Route path="/help/dev/content-check" element={<HelpDevContentCheckPage />} />
      )}

      {/* Shelled + protected */}
      <Route element={<ShellLayout />}>
        <Route path="/" element={<Navigate to="/seo/dashboard" replace />} />

        {/* Auth-only (no active-website prerequisite) */}
        <Route path="/seo/dashboard" element={<ProtectedRoute><SeoDashboardPage /></ProtectedRoute>} />
        <Route path="/seo/approvals" element={<ProtectedRoute><ApprovalQueuePage /></ProtectedRoute>} />
        <Route path="/seo/support" element={<ProtectedRoute><ExpertSupportPage /></ProtectedRoute>} />
        <Route path="/seo/settings" element={<ProtectedRoute><SeoSettingsPage /></ProtectedRoute>} />

        {/* Setup routes — reachable even without a workspace/website */}
        <Route path="/seo/onboarding" element={<ProtectedRoute allowSetup><BusinessOnboardingPage /></ProtectedRoute>} />
        <Route path="/seo/websites" element={<ProtectedRoute allowSetup><WebsitesPage /></ProtectedRoute>} />

        {/* Website-scoped feature routes */}
        <Route path="/seo/audit" element={<ProtectedRoute requireWebsite><WebsiteAuditPage /></ProtectedRoute>} />
        <Route path="/seo/keyword-research" element={<ProtectedRoute requireWebsite><KeywordResearchPage /></ProtectedRoute>} />
        <Route path="/seo/competitor-analysis" element={<ProtectedRoute requireWebsite><CompetitorAnalysisPage /></ProtectedRoute>} />
        <Route path="/seo/content-gaps" element={<ProtectedRoute requireWebsite><ContentGapsPage /></ProtectedRoute>} />
        <Route path="/seo/blog-briefs" element={<ProtectedRoute requireWebsite><BlogBriefsPage /></ProtectedRoute>} />
        <Route path="/seo/content-studio" element={<ProtectedRoute requireWebsite><ContentStudioPage /></ProtectedRoute>} />
        <Route path="/seo/page-optimizer" element={<ProtectedRoute requireWebsite><PageOptimizerPage /></ProtectedRoute>} />
        <Route path="/seo/page-performance" element={<ProtectedRoute requireWebsite><PagePerformancePage /></ProtectedRoute>} />
        <Route path="/seo/decline-diagnosis" element={<ProtectedRoute requireWebsite><DeclineDiagnosisPage /></ProtectedRoute>} />
        <Route path="/seo/off-page" element={<ProtectedRoute requireWebsite><AuthorityBuilderPage /></ProtectedRoute>} />
        <Route path="/seo/ai-visibility" element={<ProtectedRoute requireWebsite><AiVisibilityPage /></ProtectedRoute>} />
        <Route path="/seo/roadmap" element={<ProtectedRoute requireWebsite><RoadmapPage /></ProtectedRoute>} />
        <Route path="/seo/reports" element={<ProtectedRoute requireWebsite><ReportsPage /></ProtectedRoute>} />

        {/* Admin preview — temporary internal route; requires global-admin.
            Final destination is the parent Digibility Admin Panel (deferred). */}
        <Route
          path="/seo/admin-preview"
          element={<ProtectedRoute requireGlobalAdmin><SeoAdminPreviewPage /></ProtectedRoute>}
        />

        {/* Dev-only diagnostics — mounted only in development builds, never as a
            production utility. Preserved for development workflows; navigate to
            them directly. */}
        {import.meta.env.DEV && (
          <>
            <Route path="/seo/dev/supabase-readiness" element={<SupabaseReadinessPage />} />
            <Route path="/seo/dev/auth-test" element={<SupabaseAuthTestPage />} />
          </>
        )}

        <Route path="*" element={<Navigate to="/seo/dashboard" replace />} />
      </Route>
    </Routes>
  );
}
