import type {
  SeoBaseRecord,
  AuditFrequency,
  ImpactLevel,
  EffortLevel,
  RiskLevel,
  SeverityLevel,
  OwnerType,
} from "./common";

export type AuditStatus = "not_started" | "running" | "completed" | "failed";

export interface SeoAudit extends SeoBaseRecord {
  frequency: AuditFrequency;
  status: AuditStatus;
  overall_visibility_score: number;
  technical_health_score: number;
  onpage_score: number;
  authority_score: number;
  ai_discovery_score: number;
  issue_count: number;
  started_at: string;
  completed_at?: string;
}

export type SeoIssueCategory =
  | "crawl"
  | "indexability"
  | "speed"
  | "mobile"
  | "schema"
  | "duplicate_content"
  | "broken_links"
  | "sitemap"
  | "robots_txt"
  | "canonical"
  | "redirects";

export type SeoIssueStatus = "open" | "in_review" | "approved" | "fixed" | "ignored";

export interface SeoIssue extends SeoBaseRecord {
  audit_id: string;
  category: SeoIssueCategory;
  severity: SeverityLevel;
  title: string;
  simple_explanation: string;
  why_it_matters: string;
  technical_explanation: string;
  affected_page_url: string;
  impact: ImpactLevel;
  effort: EffortLevel;
  risk: RiskLevel;
  confidence_percentage: number;
  fix_owner: OwnerType;
  suggested_next_action: string;
  status: SeoIssueStatus;
}
