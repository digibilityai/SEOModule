// Digibility SEO Help Center — category taxonomy (Slice 1 subset).
// Full taxonomy is documented in DIGIBILITY_SEO_HELP_CENTER_INFORMATION_ARCHITECTURE.md;
// this file scopes to the categories that have real Slice-1 content.
import type { HelpCategory } from "./types";

export const HELP_CATEGORIES: HelpCategory[] = [
  {
    id: "start-here",
    slug: "start-here",
    title: "Start Here",
    description: "Orientation, first steps, and how to tell preview data from live data.",
  },
  {
    id: "learn-seo-aeo-geo",
    slug: "learn-seo-aeo-geo",
    title: "Learn SEO, AEO & GEO",
    description: "What SEO, AEO, and GEO are, why they matter, and how Digibility connects them.",
  },
  {
    id: "set-up-digibility-seo",
    slug: "set-up-digibility-seo",
    title: "Set Up Digibility SEO",
    description: "Adding a website and completing your business onboarding profile.",
  },
  {
    id: "domain-ownership",
    slug: "domain-ownership",
    title: "Websites & Ownership",
    description: "Verifying domain ownership with a DNS TXT record.",
  },
  {
    id: "website-crawling",
    slug: "website-crawling",
    title: "Website Crawling",
    description: "Starting, monitoring, and understanding a website crawl.",
  },
  {
    id: "recommendations-approvals",
    slug: "recommendations-approvals",
    title: "Recommendations, Approvals & Roles",
    description: "How the approval workflow works and who can do what.",
  },
  {
    id: "troubleshooting",
    slug: "troubleshooting",
    title: "Troubleshooting",
    description: "Symptom-based help for common problems.",
  },
  {
    id: "reports-decline-diagnosis",
    slug: "reports-decline-diagnosis",
    title: "Reports & Decline Diagnosis",
    description: "Reading your performance reports and investigating a traffic or ranking decline.",
  },
  {
    id: "feature-availability",
    slug: "feature-availability",
    title: "Feature Availability",
    description: "What's live, what's preview/demo data, and what's coming later.",
  },
  {
    id: "contact-support",
    slug: "contact-support",
    title: "Contact Support",
    description: "How to reach the Digibility support team safely.",
  },
];

export function getCategoryBySlug(slug: string): HelpCategory | undefined {
  return HELP_CATEGORIES.find((c) => c.slug === slug);
}
