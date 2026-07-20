// Dev-only content-integrity report. Mirrors the existing repo convention of
// dev-only diagnostic pages (see src/pages/seo/dev/*), mounted only in
// development builds via import.meta.env.DEV in SeoRoutes.tsx. Never logs
// full article bodies or any user query — this page validates the STATIC
// corpus only (there is no user input on this page at all).
import { HelpShell } from "./HelpShell";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { validateHelpContent } from "@/help/validate";

export function HelpDevContentCheckPage() {
  const report = validateHelpContent();

  return (
    <HelpShell>
      <div className="space-y-6">
        <div className="space-y-2">
          <h1 className="text-2xl font-bold">Help content integrity check (dev only)</h1>
          <p className="text-muted-foreground">
            Validates the bundled Help Center corpus: unique ids/slugs, resolvable references,
            public/internal separation, required metadata, unique anchors, deterministic search
            ordering, and absence of prohibited internal/sensitive content patterns.
          </p>
        </div>

        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <CardTitle>Result</CardTitle>
              <Badge variant={report.ok ? "default" : "destructive"}>{report.ok ? "PASS" : "FAIL"}</Badge>
            </div>
            <CardDescription>
              {report.counts.total} total articles · {report.counts.public} public ·{" "}
              {report.counts.internal} internal · {report.counts.categories} categories
            </CardDescription>
          </CardHeader>
          <CardContent>
            {report.findings.length === 0 ? (
              <p className="text-sm text-muted-foreground">No findings.</p>
            ) : (
              <ul className="space-y-2 text-sm">
                {report.findings.map((f, i) => (
                  <li key={i} className="flex items-start gap-2">
                    <Badge variant={f.level === "error" ? "destructive" : "outline"}>{f.level}</Badge>
                    <span>
                      <code className="text-xs">{f.code}</code> — {f.message}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </HelpShell>
  );
}
