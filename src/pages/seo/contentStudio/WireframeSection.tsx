import type { ContentWireframe } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";

interface WireframeSectionProps {
  wireframe: ContentWireframe | null;
  isMutating: boolean;
  onGenerate: () => void;
  onApprove: () => void;
}

export function WireframeSection({ wireframe, isMutating, onGenerate, onApprove }: WireframeSectionProps) {
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <CardTitle className="text-base">Wireframe</CardTitle>
            <CardDescription>Approve the outline before a draft is generated.</CardDescription>
          </div>
          {wireframe && (
            <Badge variant={wireframe.is_approved ? "default" : "secondary"}>
              {wireframe.is_approved ? "Approved" : "Needs approval"}
            </Badge>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        {!wireframe && (
          <Button size="sm" onClick={onGenerate} disabled={isMutating}>
            Generate wireframe
          </Button>
        )}
        {wireframe && (
          <>
            <p>
              <span className="font-medium text-foreground">Suggested H1: </span>
              {wireframe.suggested_h1}
            </p>
            <p className="text-muted-foreground">{wireframe.intro_angle}</p>
            <div>
              <p className="font-medium text-foreground">Section outline</p>
              <ul className="ml-4 list-disc text-muted-foreground">
                {wireframe.section_outline.map((section) => (
                  <li key={section}>{section}</li>
                ))}
              </ul>
            </div>
            <div>
              <p className="font-medium text-foreground">FAQ section</p>
              <ul className="ml-4 list-disc text-muted-foreground">
                {wireframe.faq_section.map((q) => (
                  <li key={q}>{q}</li>
                ))}
              </ul>
            </div>
            <p>
              <span className="font-medium text-foreground">CTA: </span>
              {wireframe.cta_suggestion}
            </p>
            <p>
              <span className="font-medium text-foreground">Internal links: </span>
              {wireframe.internal_link_suggestions.join(", ")}
            </p>
            {wireframe.schema_suggestion && (
              <p>
                <span className="font-medium text-foreground">Schema: </span>
                {wireframe.schema_suggestion}
              </p>
            )}
            {!wireframe.is_approved && (
              <div className="flex gap-2">
                <Button size="sm" onClick={onApprove} disabled={isMutating}>
                  Approve wireframe
                </Button>
                <Button size="sm" variant="outline" onClick={onGenerate} disabled={isMutating}>
                  Regenerate
                </Button>
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
