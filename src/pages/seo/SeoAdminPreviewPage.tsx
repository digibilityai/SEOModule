import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { SeoAdminShell } from "@/modules/seo-admin/SeoAdminShell";

// Temporary standalone route only — see task instructions. This page is not
// the final admin destination. SEO admin is designed to be mounted inside
// the existing Digibility Admin Panel; this route exists only so the
// SeoAdminShell can be previewed and tested in isolation until that
// integration happens.
export function SeoAdminPreviewPage() {
  return (
    <div className="space-y-4">
      <Card className="border-dashed border-warning bg-muted/40">
        <CardHeader>
          <CardTitle>SEO Admin Preview</CardTitle>
          <CardDescription>
            Temporary standalone preview. Final destination: existing Digibility Admin Panel.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground">
            This route (/seo/admin-preview) exists only for local testing of the SEO admin operations
            shell. It is not part of the customer-facing product and is not the final architecture —
            these components are built to be moved into the main Digibility Admin Panel.
          </p>
        </CardContent>
      </Card>

      <SeoAdminShell />
    </div>
  );
}
