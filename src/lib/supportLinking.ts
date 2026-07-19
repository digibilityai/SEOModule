import type { RelatedModule, SupportRequestType } from "@/types";

interface SupportPrefillParams {
  title: string;
  module: RelatedModule;
  url?: string;
  type?: SupportRequestType;
}

// Builds a link to the Expert Support Desk that pre-fills the "new request"
// form via query params — a simple, non-messy way to let other modules
// (roadmap, decline diagnosis, approvals) hand off context without needing
// a shared mutable draft-request record.
export function buildSupportRequestLink({ title, module, url, type }: SupportPrefillParams): string {
  const params = new URLSearchParams();
  params.set("prefillTitle", title);
  params.set("prefillModule", module);
  if (url) params.set("prefillUrl", url);
  if (type) params.set("prefillType", type);
  return `/seo/support?${params.toString()}`;
}
