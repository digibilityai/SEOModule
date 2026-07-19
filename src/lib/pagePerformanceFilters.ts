import type { PagePerformance, PagePerformanceFilterKey } from "@/types";

export const PAGE_PERFORMANCE_FILTERS: { key: PagePerformanceFilterKey; label: string }[] = [
  { key: "all", label: "All pages" },
  { key: "improving", label: "Improving" },
  { key: "stable", label: "Stable" },
  { key: "declining", label: "Declining" },
  { key: "needs_refresh", label: "Needs refresh" },
  { key: "not_enough_data", label: "Not enough data" },
];

export function filterPagesByStatus(
  pages: PagePerformance[],
  filter: PagePerformanceFilterKey,
): PagePerformance[] {
  if (filter === "all") return pages;
  return pages.filter((p) => p.performance_status === filter);
}

export function searchPages(pages: PagePerformance[], query: string): PagePerformance[] {
  const q = query.trim().toLowerCase();
  if (!q) return pages;
  return pages.filter(
    (p) =>
      p.page_url.toLowerCase().includes(q) ||
      p.page_title.toLowerCase().includes(q) ||
      p.primary_keyword.toLowerCase().includes(q) ||
      p.secondary_keywords.some((k) => k.toLowerCase().includes(q)),
  );
}
