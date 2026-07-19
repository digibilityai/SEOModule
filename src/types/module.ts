import type { SeoPlanTier } from "./plan";

export type SeoModuleStatus = "active" | "planned" | "later";

export interface SeoModule {
  id: string;
  name: string;
  shortDescription: string;
  route: string;
  priority: number;
  planAvailability: SeoPlanTier[];
  status: SeoModuleStatus;
}
