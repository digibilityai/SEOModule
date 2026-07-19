import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { fetchWebsites } from "@/services/websiteService";
import { useActiveWebsite } from "@/contexts/ActiveWebsiteContext";
import { MOCK_WORKSPACE_ID } from "@/mocks/mockContext";

// Resolves which website the SEO workspace is "currently" working on,
// defaulting to the first website when none has been explicitly selected.
export function useResolvedActiveWebsite() {
  const { activeWebsiteId, setActiveWebsiteId } = useActiveWebsite();

  const { data: websites = [], isLoading } = useQuery({
    queryKey: ["seo-websites", MOCK_WORKSPACE_ID],
    queryFn: () => fetchWebsites(MOCK_WORKSPACE_ID),
  });

  useEffect(() => {
    if (isLoading || websites.length === 0) return;
    const activeStillExists = websites.some((w) => w.id === activeWebsiteId);
    if (!activeWebsiteId || !activeStillExists) {
      setActiveWebsiteId(websites[0].id);
    }
  }, [isLoading, activeWebsiteId, websites, setActiveWebsiteId]);

  const activeWebsite =
    websites.find((w) => w.id === activeWebsiteId) ?? (websites.length > 0 ? websites[0] : null);

  return { websites, isLoading, activeWebsite, activeWebsiteId, setActiveWebsiteId };
}
