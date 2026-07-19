import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import type { SeoAdminWebsiteFilterKey } from "@/types";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  fetchSeoAdminOperationsSummary,
  fetchSeoAdminOverview,
  fetchSeoAdminWebsiteDetail,
  fetchSeoAdminWebsites,
} from "@/services/seoAdminService";
import { AdminOverviewCards } from "./components/AdminOverviewCards";
import { AdminWebsiteFilters } from "./components/AdminWebsiteFilters";
import { AdminWebsiteList } from "./components/AdminWebsiteList";
import { AdminWebsiteDetailPanel } from "./components/AdminWebsiteDetailPanel";
import { AdminOperationsSections } from "./components/AdminOperationsSections";

function filterRows(
  rows: Awaited<ReturnType<typeof fetchSeoAdminWebsites>>,
  filter: SeoAdminWebsiteFilterKey,
) {
  if (filter === "all") return rows;
  return rows.filter((r) => r.health === filter);
}

// Self-contained SEO admin operations shell — fetches its own data via the
// service layer, so it can be mounted as-is inside the main Digibility
// Admin Panel later, or in this temporary standalone preview route.
export function SeoAdminShell() {
  const [filter, setFilter] = useState<SeoAdminWebsiteFilterKey>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const { data: overview, isLoading: isLoadingOverview } = useQuery({
    queryKey: ["seo-admin-overview"],
    queryFn: fetchSeoAdminOverview,
  });

  const { data: websites = [], isLoading: isLoadingWebsites } = useQuery({
    queryKey: ["seo-admin-websites"],
    queryFn: fetchSeoAdminWebsites,
  });

  const { data: operationsSummary, isLoading: isLoadingOperations } = useQuery({
    queryKey: ["seo-admin-operations-summary"],
    queryFn: fetchSeoAdminOperationsSummary,
  });

  const { data: detail, isLoading: isLoadingDetail } = useQuery({
    queryKey: ["seo-admin-website-detail", selectedId],
    queryFn: () => fetchSeoAdminWebsiteDetail(selectedId!),
    enabled: !!selectedId,
  });

  if (isLoadingOverview || isLoadingWebsites || isLoadingOperations) {
    return <p className="text-sm text-muted-foreground">Loading admin data...</p>;
  }

  if (websites.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>No websites yet</CardTitle>
          <CardDescription>No SEO websites exist in this workspace to administer.</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  const filteredRows = filterRows(websites, filter);

  return (
    <div className="space-y-6">
      {overview && <AdminOverviewCards overview={overview} />}

      <div>
        <h2 className="mb-3 text-sm font-medium text-muted-foreground">Client / Website List</h2>
        <AdminWebsiteFilters active={filter} onChange={setFilter} />
        <div className="mt-3 grid gap-4 lg:grid-cols-2">
          <AdminWebsiteList rows={filteredRows} selectedId={selectedId} onSelect={setSelectedId} />

          {!selectedId && (
            <Card>
              <CardContent className="py-8 text-center text-sm text-muted-foreground">
                Select a website from the list to see its admin detail summary.
              </CardContent>
            </Card>
          )}
          {selectedId && isLoadingDetail && <p className="text-sm text-muted-foreground">Loading detail...</p>}
          {selectedId && detail && <AdminWebsiteDetailPanel detail={detail} />}
        </div>
      </div>

      <div>
        <h2 className="mb-3 text-sm font-medium text-muted-foreground">Admin Operations</h2>
        {operationsSummary && <AdminOperationsSections summary={operationsSummary} />}
      </div>
    </div>
  );
}
