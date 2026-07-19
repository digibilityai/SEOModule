import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  checkSupabaseReadiness,
  type SupabaseReadinessResult,
} from "@/services/supabase/supabaseHealthService";

// Development-only diagnostics page. Reachable only by navigating directly
// to /seo/dev/supabase-readiness — it is not registered in the module
// registry and has no sidebar entry. Read-only: performs no database
// writes and does not require login to render successfully.
export function SupabaseReadinessPage() {
  const [result, setResult] = useState<SupabaseReadinessResult | null>(null);
  const [isChecking, setIsChecking] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setIsChecking(true);
    checkSupabaseReadiness()
      .then((next) => {
        if (!cancelled) setResult(next);
      })
      .finally(() => {
        if (!cancelled) setIsChecking(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (!import.meta.env.DEV) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Not available</CardTitle>
          <CardDescription>This diagnostics page is development-only.</CardDescription>
        </CardHeader>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-2">
          <CardTitle>Supabase Readiness</CardTitle>
          <Badge variant="outline">development only</Badge>
        </div>
        <CardDescription>
          Read-only diagnostic for the SEO data-mode switching foundation (Phase 13A). No
          database writes are performed and login is not required. To sign in and test
          authenticated RLS behavior, see{" "}
          <Link to="/seo/dev/auth-test" className="underline">
            Supabase Auth Test →
          </Link>
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        {isChecking && <p className="text-muted-foreground">Checking…</p>}

        {result && (
          <div className="space-y-2">
            <ReadinessRow label="Data mode" value={result.mode} />
            <ReadinessRow
              label="Supabase config present"
              value={result.configured ? "yes" : "no"}
            />
            <ReadinessRow label="Session present" value={result.hasSession ? "yes" : "no"} />
            <ReadinessRow label="Current user id" value={result.userId ?? "(none)"} />
            <ReadinessRow
              label="Mock fallback active"
              value={result.mode === "mock" ? "yes" : "no"}
            />
            <ReadinessRow label="Checked at" value={result.checkedAt} />

            {result.warnings.length > 0 && (
              <div className="mt-4">
                <p className="mb-1 font-medium">Warnings</p>
                <ul className="list-inside list-disc space-y-1 text-muted-foreground">
                  {result.warnings.map((warning) => (
                    <li key={warning}>{warning}</li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function ReadinessRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between border-b border-border py-1 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
