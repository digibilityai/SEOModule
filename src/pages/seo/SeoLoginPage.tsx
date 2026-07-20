// Phase 16B — customer-facing sign-in for EXISTING Supabase users (login only:
// no signup, no password reset, no email verification). Chromeless page using
// the existing design system. NOT the dev harness (which stays dev-only).
import { useEffect, useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate, useSearchParams } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { hasDigibilityBridgeConfig, isMockMode } from "@/config/runtimeConfig";
import { signInSeoCustomer } from "@/services/supabase/seoAccessService";
import {
  RETURN_TO_PARAM,
  SEO_DEFAULT_ROUTE,
  buildDigibilityLoginUrl,
  sanitizeReturnPath,
} from "@/routes/routeAccess";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { HELP_ROUTES } from "@/help/routes";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

export function SeoLoginPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { isAuthenticated, isLoading: sessionLoading } = useAuth();

  const returnTo = sanitizeReturnPath(searchParams.get(RETURN_TO_PARAM)) ?? SEO_DEFAULT_ROUTE;

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const bridgeConfigured = hasDigibilityBridgeConfig();

  useEffect(() => {
    if (isMockMode() || !bridgeConfigured || sessionLoading || isAuthenticated) return;
    window.location.replace(buildDigibilityLoginUrl(returnTo));
  }, [bridgeConfigured, isAuthenticated, returnTo, sessionLoading]);

  // Mock mode: sign-in is not required — explain, don't block.
  if (isMockMode()) {
    return (
      <CenteredShell>
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Digibility SEO Intelligence</CardTitle>
            <CardDescription>
              You're running in mock mode — sign-in is not required. The SEO workflows are available
              directly for development and demonstration.
            </CardDescription>
            <Link to={HELP_ROUTES.SIGN_IN_ACCESS} className={HELP_LINK_CLASSNAME}>
              Trouble signing in?
            </Link>
          </CardHeader>
          <CardContent>
            <Button size="sm" onClick={() => navigate(SEO_DEFAULT_ROUTE, { replace: true })}>
              Continue to the SEO module
            </Button>
          </CardContent>
        </Card>
      </CenteredShell>
    );
  }

  // Already authenticated: skip the form; ProtectedRoute resolves prerequisites.
  if (!sessionLoading && isAuthenticated) {
    return <Navigate to={returnTo} replace />;
  }

  // Production SSO path: Digibility is the only customer login. Keep the
  // standalone form below as a non-breaking TEST/local fallback until bridge
  // configuration is explicitly supplied.
  if (bridgeConfigured) {
    return (
      <CenteredShell>
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Redirecting to Digibility</CardTitle>
            <CardDescription>Sign in once with your Digibility account to open SEO.</CardDescription>
          </CardHeader>
        </Card>
      </CenteredShell>
    );
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (submitting) return;
    setErrorMessage(null);
    setSubmitting(true);
    const result = await signInSeoCustomer(email.trim(), password);
    setSubmitting(false);
    if (!result.success) {
      const raw = result.errorMessage ?? "";
      setErrorMessage(
        /invalid/i.test(raw)
          ? "Invalid email or password. Please try again."
          : raw || "We couldn't sign you in. Please try again.",
      );
      return;
    }
    setPassword("");
    navigate(returnTo, { replace: true });
  };

  return (
    <CenteredShell>
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Sign in to Digibility SEO</CardTitle>
          <CardDescription>Sign in with your existing Digibility account.</CardDescription>
          <Link to={HELP_ROUTES.SIGN_IN_ACCESS} className={HELP_LINK_CLASSNAME}>
            Trouble signing in?
          </Link>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={handleSubmit} noValidate>
            <div className="space-y-1">
              <Label htmlFor="seo-login-email">Email</Label>
              <Input
                id="seo-login-email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@company.com"
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="seo-login-password">Password</Label>
              <Input
                id="seo-login-password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>

            {errorMessage && (
              <p className="text-sm text-destructive" role="alert">
                {errorMessage}
              </p>
            )}

            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting ? "Signing in…" : "Sign in"}
            </Button>

            <p className="text-xs text-muted-foreground">
              Sign-in only. Self-service signup and password recovery aren't available here yet —
              please contact your administrator if you need account help.
            </p>
          </form>
        </CardContent>
      </Card>
    </CenteredShell>
  );
}

function CenteredShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="text-center">
          <p className="text-sm font-medium text-muted-foreground">Digibility SEO Intelligence</p>
        </div>
        {children}
      </div>
    </div>
  );
}
