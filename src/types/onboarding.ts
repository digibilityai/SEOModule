import type { SeoBaseRecord } from "./common";

export type MainSeoGoal =
  | "more_leads"
  | "local_visibility"
  | "improve_rankings"
  | "grow_blog_traffic"
  | "improve_ai_visibility"
  | "fix_technical_seo"
  | "improve_conversions"
  | "other";

export type SensitiveIndustry =
  | "healthcare"
  | "finance"
  | "legal"
  | "education"
  | "none"
  | "other";

export type ContentTone =
  | "professional"
  | "friendly"
  | "authoritative"
  | "casual"
  | "other";

export type OnboardingStatus = "not_started" | "in_progress" | "completed";

export interface BusinessOnboarding extends SeoBaseRecord {
  services_products: string;
  target_audience: string;
  main_seo_goal: MainSeoGoal;
  target_locations: string[];
  competitors: string[];
  proof_trust_signals?: string;
  important_pages: string[];
  preferred_content_tone: ContentTone;
  sensitive_industry: SensitiveIndustry;
  notes?: string;
  status: OnboardingStatus;
  completion_percentage: number;
}

export type NewBusinessOnboardingInput = Omit<
  BusinessOnboarding,
  "id" | "workspace_id" | "user_id" | "created_by" | "created_at" | "updated_at"
>;
