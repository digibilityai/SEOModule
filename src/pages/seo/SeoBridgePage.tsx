import { useEffect, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getDigibilityAppUrl } from "@/config/runtimeConfig";
import {
  establishSeoSession,
  redeemSeoLaunchCode,
} from "@/services/supabase/seoBridgeService";

export function SeoBridgePage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const started = useRef(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const code = searchParams.get("code");
    if (!code) {
      setError("This SEO launch link is missing its one-time code.");
      return;
    }

    void (async () => {
      try {
        const redemption = await redeemSeoLaunchCode(code);
        await establishSeoSession(redemption);
        navigate(redemption.returnTo, { replace: true });
      } catch (reason) {
        setError(reason instanceof Error ? reason.message : "SEO sign-in could not be completed.");
      }
    })();
  }, [navigate, searchParams]);

  const returnToDigibility = () => {
    const appUrl = getDigibilityAppUrl();
    window.location.assign(appUrl || "/seo/login");
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-lg">Digibility SEO Intelligence</CardTitle>
          <CardDescription>
            {error ? "We could not complete your secure launch." : "Completing secure sign-in…"}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {error ? (
            <>
              <p className="text-sm text-destructive" role="alert">{error}</p>
              <Button className="w-full" onClick={returnToDigibility}>
                Return to Digibility
              </Button>
            </>
          ) : (
            <div className="flex items-center gap-2 text-sm text-muted-foreground" aria-live="polite">
              <Loader2 className="h-4 w-4 animate-spin" />
              Verifying your Digibility access
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
