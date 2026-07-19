import type { RoadmapFilterKey, RoadmapItem } from "@/types";

export const ROADMAP_FILTERS: { key: RoadmapFilterKey; label: string }[] = [
  { key: "all", label: "All" },
  { key: "month_1", label: "Month 1" },
  { key: "month_2", label: "Month 2" },
  { key: "month_3", label: "Month 3" },
  { key: "high_priority", label: "High priority" },
  { key: "expert_support", label: "Expert support needed" },
  { key: "completed", label: "Completed" },
  { key: "pending", label: "Pending" },
];

export function filterRoadmapItems(items: RoadmapItem[], filter: RoadmapFilterKey): RoadmapItem[] {
  switch (filter) {
    case "all":
      return items;
    case "month_1":
      return items.filter((i) => i.month_number === 1);
    case "month_2":
      return items.filter((i) => i.month_number === 2);
    case "month_3":
      return items.filter((i) => i.month_number === 3);
    case "high_priority":
      return items.filter((i) => i.priority === "high");
    case "expert_support":
      return items.filter((i) => i.owner === "digibility_expert");
    case "completed":
      return items.filter((i) => i.status === "completed");
    case "pending":
      return items.filter((i) => i.status === "planned" || i.status === "in_progress" || i.status === "blocked");
    default:
      return items;
  }
}
