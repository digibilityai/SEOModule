import type { ConnectionStatus } from "./common";
import type { SeoPlanTier } from "./plan";

export interface SeoWorkspace {
  id: string;
  name: string;
  owner_user_id: string;
  created_at: string;
  updated_at: string;
}

export type WebsiteType =
  | "service"
  | "local_business"
  | "ecommerce"
  | "content"
  | "saas"
  | "other";

export interface SeoWebsite {
  id: string;
  workspace_id: string;
  user_id: string;
  website_url: string;
  name: string;
  business_name: string;
  industry?: string;
  target_location?: string;
  website_type: WebsiteType;
  plan: SeoPlanTier;
  is_high_risk_industry: boolean;
  reachable_status: ConnectionStatus;
  sitemap_status: ConnectionStatus;
  robots_status: ConnectionStatus;
  gsc_status: ConnectionStatus;
  ga4_status: ConnectionStatus;
  cms_status: ConnectionStatus;
  gbp_status: ConnectionStatus;
  status: "active" | "inactive" | "archived";
  created_by: string;
  created_at: string;
  updated_at: string;
}

export type NewSeoWebsiteInput = Pick<
  SeoWebsite,
  | "website_url"
  | "name"
  | "business_name"
  | "industry"
  | "target_location"
  | "website_type"
  | "plan"
>;
