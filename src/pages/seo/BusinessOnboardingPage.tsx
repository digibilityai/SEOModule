import { useEffect, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type {
  ContentTone,
  MainSeoGoal,
  NewBusinessOnboardingInput,
  SensitiveIndustry,
} from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import {
  calculateCompletionPercentage,
  fetchOnboardingByWebsiteId,
  resolveOnboardingStatus,
  saveOnboarding,
} from "@/services/businessOnboardingService";
import { useResolvedActiveWebsite } from "@/hooks/useResolvedActiveWebsite";
import { HELP_ROUTES } from "@/help/routes";
import { PlaceholderPage } from "./PlaceholderPage";

const HELP_LINK_CLASSNAME =
  "text-sm font-medium text-primary underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 rounded-sm";

const MAIN_SEO_GOAL_OPTIONS: { value: MainSeoGoal; label: string }[] = [
  { value: "more_leads", label: "Get more leads" },
  { value: "local_visibility", label: "Increase local visibility" },
  { value: "improve_rankings", label: "Improve rankings" },
  { value: "grow_blog_traffic", label: "Grow blog traffic" },
  { value: "improve_ai_visibility", label: "Improve AI visibility" },
  { value: "fix_technical_seo", label: "Fix technical SEO" },
  { value: "improve_conversions", label: "Improve conversions from SEO" },
  { value: "other", label: "Other" },
];

const CONTENT_TONE_OPTIONS: { value: ContentTone; label: string }[] = [
  { value: "professional", label: "Professional" },
  { value: "friendly", label: "Friendly & approachable" },
  { value: "authoritative", label: "Authoritative / expert" },
  { value: "casual", label: "Casual" },
  { value: "other", label: "Other" },
];

const SENSITIVE_INDUSTRY_OPTIONS: { value: SensitiveIndustry; label: string }[] = [
  { value: "healthcare", label: "Healthcare" },
  { value: "finance", label: "Finance" },
  { value: "legal", label: "Legal" },
  { value: "education", label: "Education" },
  { value: "none", label: "None / not sensitive" },
  { value: "other", label: "Other" },
];

interface FormState {
  services_products: string;
  target_audience: string;
  main_seo_goal: MainSeoGoal | "";
  target_locations: string;
  competitors: string;
  proof_trust_signals: string;
  important_pages: string;
  preferred_content_tone: ContentTone | "";
  sensitive_industry: SensitiveIndustry | "";
  notes: string;
}

const emptyForm: FormState = {
  services_products: "",
  target_audience: "",
  main_seo_goal: "",
  target_locations: "",
  competitors: "",
  proof_trust_signals: "",
  important_pages: "",
  preferred_content_tone: "",
  sensitive_industry: "",
  notes: "",
};

function toLines(value: string): string[] {
  return value
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

export function BusinessOnboardingPage() {
  const queryClient = useQueryClient();
  const { activeWebsite, isLoading: isLoadingWebsite } = useResolvedActiveWebsite();
  const [form, setForm] = useState<FormState>(emptyForm);
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const { data: onboarding, isLoading: isLoadingOnboarding } = useQuery({
    queryKey: ["seo-onboarding", activeWebsite?.id],
    queryFn: () => fetchOnboardingByWebsiteId(activeWebsite!.id),
    enabled: !!activeWebsite,
  });

  useEffect(() => {
    if (!onboarding) return;
    setForm({
      services_products: onboarding.services_products,
      target_audience: onboarding.target_audience,
      main_seo_goal: onboarding.main_seo_goal,
      target_locations: onboarding.target_locations.join("\n"),
      competitors: onboarding.competitors.join("\n"),
      proof_trust_signals: onboarding.proof_trust_signals ?? "",
      important_pages: onboarding.important_pages.join("\n"),
      preferred_content_tone: onboarding.preferred_content_tone,
      sensitive_industry: onboarding.sensitive_industry,
      notes: onboarding.notes ?? "",
    });
  }, [onboarding]);

  const saveMutation = useMutation({
    mutationFn: (input: NewBusinessOnboardingInput) => saveOnboarding(input),
    onSuccess: (saved) => {
      queryClient.invalidateQueries({ queryKey: ["seo-onboarding", saved.website_id] });
      setSavedAt(new Date().toLocaleTimeString());
    },
  });

  if (isLoadingWebsite) {
    return <p className="text-sm text-muted-foreground">Loading...</p>;
  }

  if (!activeWebsite) {
    return (
      <PlaceholderPage
        title="Add a website first"
        description="Business onboarding is tied to a website. Add a website to get started."
      />
    );
  }

  const completionPercentage = calculateCompletionPercentage({
    services_products: form.services_products,
    target_audience: form.target_audience,
    main_seo_goal: form.main_seo_goal,
    preferred_content_tone: form.preferred_content_tone,
    sensitive_industry: form.sensitive_industry,
  });
  const status = resolveOnboardingStatus(completionPercentage);

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    const { main_seo_goal, preferred_content_tone, sensitive_industry } = form;
    if (!main_seo_goal || !preferred_content_tone || !sensitive_industry) {
      setError("Select your main SEO goal, preferred content tone and industry sensitivity.");
      return;
    }
    setError(null);
    saveMutation.mutate({
      website_id: activeWebsite.id,
      website_url: activeWebsite.website_url,
      services_products: form.services_products,
      target_audience: form.target_audience,
      main_seo_goal,
      target_locations: toLines(form.target_locations),
      competitors: toLines(form.competitors),
      proof_trust_signals: form.proof_trust_signals || undefined,
      important_pages: toLines(form.important_pages),
      preferred_content_tone,
      sensitive_industry,
      notes: form.notes || undefined,
      status,
      completion_percentage: completionPercentage,
    });
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="space-y-1.5">
            <CardTitle>Business Onboarding</CardTitle>
            <CardDescription>
              Tell us about {activeWebsite.business_name} so SEO recommendations aren't generic.
            </CardDescription>
            <Link to={HELP_ROUTES.BUSINESS_ONBOARDING} className={HELP_LINK_CLASSNAME}>
              Why this matters
            </Link>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant={status === "completed" ? "default" : "secondary"}>
              {status.replace("_", " ")}
            </Badge>
            <Badge variant="outline">{completionPercentage}% complete</Badge>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {isLoadingOnboarding ? (
          <p className="text-sm text-muted-foreground">Loading...</p>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="services_products">Services / products</Label>
              <Textarea
                id="services_products"
                placeholder="What does this business sell or offer?"
                value={form.services_products}
                onChange={(e) => setForm((f) => ({ ...f, services_products: e.target.value }))}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="target_audience">Target audience</Label>
              <Textarea
                id="target_audience"
                placeholder="Who are the ideal customers?"
                value={form.target_audience}
                onChange={(e) => setForm((f) => ({ ...f, target_audience: e.target.value }))}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="main_seo_goal">Main SEO goal</Label>
              <Select
                id="main_seo_goal"
                value={form.main_seo_goal}
                onChange={(e) =>
                  setForm((f) => ({ ...f, main_seo_goal: e.target.value as MainSeoGoal | "" }))
                }
              >
                <option value="" disabled>
                  Select your main SEO goal
                </option>
                {MAIN_SEO_GOAL_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="target_locations">Target locations (one per line)</Label>
              <Textarea
                id="target_locations"
                placeholder={"Austin, TX\nRound Rock, TX"}
                value={form.target_locations}
                onChange={(e) => setForm((f) => ({ ...f, target_locations: e.target.value }))}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="competitors">Competitors (one per line)</Label>
              <Textarea
                id="competitors"
                placeholder="https://www.competitor.com"
                value={form.competitors}
                onChange={(e) => setForm((f) => ({ ...f, competitors: e.target.value }))}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="proof_trust_signals">Proof / trust signals</Label>
              <Textarea
                id="proof_trust_signals"
                placeholder="Years in business, certifications, reviews..."
                value={form.proof_trust_signals}
                onChange={(e) => setForm((f) => ({ ...f, proof_trust_signals: e.target.value }))}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="important_pages">Important pages (one URL per line)</Label>
              <Textarea
                id="important_pages"
                placeholder="https://www.example.com/services"
                value={form.important_pages}
                onChange={(e) => setForm((f) => ({ ...f, important_pages: e.target.value }))}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="preferred_content_tone">Preferred content tone</Label>
              <Select
                id="preferred_content_tone"
                value={form.preferred_content_tone}
                onChange={(e) =>
                  setForm((f) => ({
                    ...f,
                    preferred_content_tone: e.target.value as ContentTone | "",
                  }))
                }
              >
                <option value="" disabled>
                  Select preferred content tone
                </option>
                {CONTENT_TONE_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="sensitive_industry">Sensitive industry</Label>
              <Select
                id="sensitive_industry"
                value={form.sensitive_industry}
                onChange={(e) =>
                  setForm((f) => ({
                    ...f,
                    sensitive_industry: e.target.value as SensitiveIndustry | "",
                  }))
                }
              >
                <option value="" disabled>
                  Select industry sensitivity
                </option>
                {SENSITIVE_INDUSTRY_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </Select>
              <p className="text-xs text-muted-foreground">
                Healthcare, finance, legal and education content goes through an extra trust
                review before publishing.
              </p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="notes">Notes / context</Label>
              <Textarea
                id="notes"
                placeholder="Anything else Digibility should know?"
                value={form.notes}
                onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
              />
            </div>

            {error && <p className="text-sm text-destructive">{error}</p>}

            <div className="flex items-center gap-3">
              <Button type="submit" disabled={saveMutation.isPending}>
                {saveMutation.isPending ? "Saving..." : "Save onboarding"}
              </Button>
              {savedAt && (
                <span className="text-sm text-muted-foreground">Saved at {savedAt}</span>
              )}
            </div>
          </form>
        )}
      </CardContent>
    </Card>
  );
}
