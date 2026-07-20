// Public Help Center shell. AUTHENTICATION-FREE BY DESIGN:
//   - no useAuth / useSeoAccess / useResolvedActiveWebsite / role hooks;
//   - no Sidebar / Header / Layout (the authenticated app shell);
//   - no workspace/website/user-specific content;
//   - renders identically signed-in or signed-out, with or without Supabase config.
import { type ReactNode, useEffect } from "react";
import { Link } from "react-router-dom";

/** Adds a noindex meta tag while a public Help route is mounted (removed on unmount). */
function useNoIndex() {
  useEffect(() => {
    const meta = document.createElement("meta");
    meta.name = "robots";
    meta.content = "noindex, nofollow";
    document.head.appendChild(meta);
    return () => {
      document.head.removeChild(meta);
    };
  }, []);
}

export function HelpShell({ children }: { children: ReactNode }) {
  useNoIndex();
  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <a
        href="#help-main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50 focus:rounded-md focus:bg-primary focus:px-3 focus:py-2 focus:text-primary-foreground"
      >
        Skip to content
      </a>
      <header className="border-b border-border bg-card">
        <div className="mx-auto flex h-14 max-w-5xl items-center justify-between px-4">
          <Link to="/help" className="font-heading text-base font-semibold sm:text-lg">
            Digibility SEO Help Center
          </Link>
          <nav aria-label="Help Center navigation" className="flex items-center gap-3 text-sm sm:gap-4">
            <Link to="/help" className="text-muted-foreground hover:text-foreground focus-visible:outline-2">
              Help Center
            </Link>
            <Link to="/seo/support" className="text-muted-foreground hover:text-foreground focus-visible:outline-2">
              Contact Support
            </Link>
            <Link
              to="/seo/login"
              className="rounded-md border border-border px-3 py-1.5 text-foreground hover:bg-accent focus-visible:outline-2"
            >
              Sign in
            </Link>
          </nav>
        </div>
      </header>

      <main id="help-main-content" className="flex-1">
        <div className="mx-auto max-w-5xl px-4 py-8">{children}</div>
      </main>

      <footer className="border-t border-border bg-card">
        <div className="mx-auto flex max-w-5xl flex-col gap-2 px-4 py-6 text-sm text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
          <span>Digibility SEO Intelligence — Help Center</span>
          <div className="flex items-center gap-4">
            <Link to="/help" className="hover:text-foreground focus-visible:outline-2">
              Browse Help Center
            </Link>
            <Link to="/seo/support" className="hover:text-foreground focus-visible:outline-2">
              Contact Support
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
