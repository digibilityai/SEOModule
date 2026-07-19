import type { SeoAdminOperationsSummary } from "@/types";
import { AdminOperationsCard } from "./AdminOperationsCard";

interface AdminOperationsSectionsProps {
  summary: SeoAdminOperationsSummary;
}

const formatPlaceholder = (value: number | null): string => (value === null ? "Not tracked yet" : String(value));

// Reusable — safe to mount inside the main Digibility Admin Panel later.
export function AdminOperationsSections({ summary }: AdminOperationsSectionsProps) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <AdminOperationsCard
        title="Audit Operations"
        metrics={[
          { label: "Latest audit runs", value: summary.audit_operations.latest_runs_count },
          { label: "Failed checks", value: summary.audit_operations.failed_checks_count },
          { label: "Critical issues", value: summary.audit_operations.critical_issues_count },
        ]}
        comingSoonLabel="Issue Library - coming soon"
      />
      <AdminOperationsCard
        title="Recommendation Review"
        metrics={[
          { label: "Pending generated fixes", value: summary.recommendation_review.pending_count },
          { label: "High-risk fixes", value: summary.recommendation_review.high_risk_count },
          { label: "Expert review items", value: summary.recommendation_review.expert_review_count },
        ]}
        comingSoonLabel="Review Queue - coming soon"
      />
      <AdminOperationsCard
        title="Content Operations"
        metrics={[
          { label: "Content plans started", value: summary.content_operations.plans_started_count },
          { label: "Drafts in review", value: summary.content_operations.drafts_in_review_count },
          { label: "Approved drafts", value: summary.content_operations.approved_drafts_count },
          { label: "Trust review needed", value: summary.content_operations.trust_review_needed_count },
        ]}
        comingSoonLabel="Content Review - coming soon"
      />
      <AdminOperationsCard
        title="Support Tickets"
        metrics={[
          { label: "Submitted", value: summary.support_tickets.submitted_count },
          { label: "In review", value: summary.support_tickets.in_review_count },
          { label: "In progress", value: summary.support_tickets.in_progress_count },
          { label: "Waiting for client", value: summary.support_tickets.waiting_for_client_count },
          { label: "Completed", value: summary.support_tickets.completed_count },
        ]}
        comingSoonLabel="Task Assignment - coming soon"
      />
      <AdminOperationsCard
        title="Reports"
        metrics={[
          {
            label: "Latest report generated",
            value: summary.reports.latest_generated_at
              ? new Date(summary.reports.latest_generated_at).toLocaleDateString()
              : "None yet",
          },
          { label: "Reports generated", value: summary.reports.generated_count },
        ]}
        comingSoonLabel="Report Builder - coming soon"
      />
      <AdminOperationsCard
        title="Plans / Access"
        metrics={[
          { label: "Basic plan sites", value: summary.plans_access.plan_distribution.basic },
          { label: "Standard plan sites", value: summary.plans_access.plan_distribution.standard },
          { label: "Pro plan sites", value: summary.plans_access.plan_distribution.pro },
          { label: "Usage limits", value: "Placeholder" },
        ]}
        comingSoonLabel="Subscription Controls - coming soon"
      />
      <AdminOperationsCard
        title="AI Governance"
        metrics={[
          { label: "AI requests", value: formatPlaceholder(summary.ai_governance.ai_requests_placeholder) },
          { label: "Estimated cost", value: formatPlaceholder(summary.ai_governance.estimated_cost_placeholder) },
          { label: "Prompt Library", value: "Placeholder" },
        ]}
        comingSoonLabel="AI Cost Tracking - coming soon"
      />
      <AdminOperationsCard
        title="Integration Health"
        metrics={[
          {
            label: "GSC connected",
            value: `${summary.integration_health.gsc_connected_count}/${summary.integration_health.total_websites}`,
          },
          {
            label: "GA4 connected",
            value: `${summary.integration_health.ga4_connected_count}/${summary.integration_health.total_websites}`,
          },
          {
            label: "CMS connected",
            value: `${summary.integration_health.cms_connected_count}/${summary.integration_health.total_websites}`,
          },
          {
            label: "GBP connected",
            value: `${summary.integration_health.gbp_connected_count}/${summary.integration_health.total_websites}`,
          },
        ]}
        comingSoonLabel="Integration Monitor - coming soon"
      />
      <AdminOperationsCard
        title="QA Review"
        metrics={[
          { label: "High-risk changes needing QA", value: summary.qa_review.high_risk_changes_count },
          { label: "Content trust review items", value: summary.qa_review.content_trust_review_count },
          { label: "Spam risk items", value: summary.qa_review.spam_risk_items_count },
        ]}
        comingSoonLabel="QA Queue - coming soon"
      />
      <AdminOperationsCard
        title="Templates"
        metrics={[
          { label: "Report templates", value: "Placeholder" },
          { label: "Outreach templates", value: "Placeholder" },
          { label: "SEO checklists", value: "Placeholder" },
        ]}
        comingSoonLabel="Template Manager - coming soon"
      />
    </div>
  );
}
