import { useAuth } from "@/contexts/AuthContext";
import { useSeoSignOut } from "@/hooks/useSeoSignOut";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { getPlanConfig } from "@/registry/planRegistry";
import { MOCK_CURRENT_PLAN_TIER } from "@/mocks/mockContext";

// Mock current plan until plan/subscription data comes from Supabase.
const MOCK_CURRENT_PLAN = getPlanConfig(MOCK_CURRENT_PLAN_TIER);

export function Header() {
  const { user, isAuthenticated } = useAuth();
  const signOut = useSeoSignOut();

  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-card px-4">
      <div className="flex items-center gap-3">
        <span className="text-sm text-muted-foreground">
          Digibility SEO Intelligence Module
        </span>
        <Badge variant="outline">{MOCK_CURRENT_PLAN.name} plan</Badge>
      </div>
      {isAuthenticated ? (
        <div className="flex items-center gap-3">
          <span className="text-sm text-foreground">{user?.email}</span>
          <Button variant="outline" size="sm" onClick={() => void signOut()}>
            Sign out
          </Button>
        </div>
      ) : (
        <span className="text-sm text-muted-foreground">Not signed in</span>
      )}
    </header>
  );
}
