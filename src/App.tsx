import { BrowserRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { AuthProvider } from "@/contexts/AuthContext";
import { ActiveWebsiteProvider } from "@/contexts/ActiveWebsiteContext";
import { SessionSync } from "@/components/auth/SessionSync";
import { SeoRoutes } from "@/routes/SeoRoutes";

const queryClient = new QueryClient();

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <ActiveWebsiteProvider>
          {/* Clears cached data + active-website selection when the authenticated
              user changes, so nothing leaks across users (Phase 16B). */}
          <SessionSync />
          <BrowserRouter>
            <SeoRoutes />
          </BrowserRouter>
        </ActiveWebsiteProvider>
      </AuthProvider>
    </QueryClientProvider>
  );
}
