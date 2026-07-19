import React, { createContext, useContext, useState } from "react";

const STORAGE_KEY = "seo_active_website_id";

interface ActiveWebsiteContextType {
  activeWebsiteId: string | null;
  setActiveWebsiteId: (id: string | null) => void;
}

const ActiveWebsiteContext = createContext<ActiveWebsiteContextType | undefined>(undefined);

// Which website the SEO workspace is currently working on. UI preference
// only — persisted to localStorage, not a Supabase-backed record.
export const ActiveWebsiteProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [activeWebsiteId, setActiveWebsiteIdState] = useState<string | null>(() =>
    typeof window !== "undefined" ? window.localStorage.getItem(STORAGE_KEY) : null,
  );

  const setActiveWebsiteId = (id: string | null) => {
    setActiveWebsiteIdState(id);
    if (typeof window === "undefined") return;
    if (id) window.localStorage.setItem(STORAGE_KEY, id);
    else window.localStorage.removeItem(STORAGE_KEY);
  };

  return (
    <ActiveWebsiteContext.Provider value={{ activeWebsiteId, setActiveWebsiteId }}>
      {children}
    </ActiveWebsiteContext.Provider>
  );
};

export const useActiveWebsite = () => {
  const context = useContext(ActiveWebsiteContext);
  if (context === undefined) {
    throw new Error("useActiveWebsite must be used within an ActiveWebsiteProvider");
  }
  return context;
};
