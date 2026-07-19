import type { SeoAdminWebsiteFilterKey, SeoAdminWebsiteHealth } from "@/types";

export const HEALTH_LABEL: Record<SeoAdminWebsiteHealth, string> = {
  healthy: "Healthy",
  needs_attention: "Needs attention",
  critical: "Critical",
  inactive: "Inactive",
};

export const HEALTH_VARIANT: Record<SeoAdminWebsiteHealth, "default" | "secondary" | "destructive" | "outline"> = {
  healthy: "default",
  needs_attention: "secondary",
  critical: "destructive",
  inactive: "outline",
};

export const WEBSITE_FILTERS: { key: SeoAdminWebsiteFilterKey; label: string }[] = [
  { key: "all", label: "All" },
  { key: "healthy", label: "Healthy" },
  { key: "needs_attention", label: "Needs attention" },
  { key: "critical", label: "Critical" },
  { key: "inactive", label: "Inactive" },
];

export const CONNECTION_STATUS_LABEL: Record<string, string> = {
  not_connected: "Not connected",
  pending: "Pending",
  connected: "Connected",
  error: "Error",
};

export const AUDIT_STATUS_LABEL: Record<string, string> = {
  not_started: "Not started",
  running: "Running",
  completed: "Completed",
  failed: "Failed",
  none: "No audit yet",
};

export const ONBOARDING_STATUS_LABEL: Record<string, string> = {
  not_started: "Not started",
  in_progress: "In progress",
  completed: "Completed",
};
