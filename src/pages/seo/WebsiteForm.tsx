import { useState, type FormEvent } from "react";
import type { NewSeoWebsiteInput, SeoPlanTier, WebsiteType } from "@/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";

const WEBSITE_TYPE_OPTIONS: { value: WebsiteType; label: string }[] = [
  { value: "service", label: "Service business" },
  { value: "local_business", label: "Local business" },
  { value: "ecommerce", label: "Ecommerce" },
  { value: "content", label: "Content / publisher" },
  { value: "saas", label: "SaaS" },
  { value: "other", label: "Other" },
];

const PLAN_OPTIONS: { value: SeoPlanTier; label: string }[] = [
  { value: "basic", label: "Basic" },
  { value: "standard", label: "Standard" },
  { value: "pro", label: "Pro" },
];

const emptyForm: NewSeoWebsiteInput = {
  website_url: "",
  name: "",
  business_name: "",
  industry: "",
  target_location: "",
  website_type: "service",
  plan: "basic",
};

interface WebsiteFormProps {
  onSubmit: (input: NewSeoWebsiteInput) => void;
  onCancel: () => void;
  isSubmitting: boolean;
  disabled?: boolean;
  disabledReason?: string;
}

export function WebsiteForm({
  onSubmit,
  onCancel,
  isSubmitting,
  disabled,
  disabledReason,
}: WebsiteFormProps) {
  const [form, setForm] = useState<NewSeoWebsiteInput>(emptyForm);
  const [error, setError] = useState<string | null>(null);

  const handleChange = (patch: Partial<NewSeoWebsiteInput>) => {
    setForm((prev) => ({ ...prev, ...patch }));
  };

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    if (!form.website_url.trim() || !form.name.trim() || !form.business_name.trim()) {
      setError("Website URL, website name and business name are required.");
      return;
    }
    setError(null);
    onSubmit(form);
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4 rounded-md border border-border p-4">
      {disabled && disabledReason && (
        <p className="rounded-md bg-warning/10 px-3 py-2 text-sm text-warning-foreground">
          {disabledReason}
        </p>
      )}
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="website_url">Website URL</Label>
          <Input
            id="website_url"
            type="url"
            placeholder="https://www.example.com"
            value={form.website_url}
            onChange={(e) => handleChange({ website_url: e.target.value })}
            disabled={disabled}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="name">Website name</Label>
          <Input
            id="name"
            placeholder="e.g. Acme Plumbing - Main Site"
            value={form.name}
            onChange={(e) => handleChange({ name: e.target.value })}
            disabled={disabled}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="business_name">Business name</Label>
          <Input
            id="business_name"
            placeholder="e.g. Acme Plumbing"
            value={form.business_name}
            onChange={(e) => handleChange({ business_name: e.target.value })}
            disabled={disabled}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="industry">Industry</Label>
          <Input
            id="industry"
            placeholder="e.g. Home Services"
            value={form.industry}
            onChange={(e) => handleChange({ industry: e.target.value })}
            disabled={disabled}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="target_location">Target location</Label>
          <Input
            id="target_location"
            placeholder="e.g. Austin, TX"
            value={form.target_location}
            onChange={(e) => handleChange({ target_location: e.target.value })}
            disabled={disabled}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="website_type">Website type</Label>
          <Select
            id="website_type"
            value={form.website_type}
            onChange={(e) => handleChange({ website_type: e.target.value as WebsiteType })}
            disabled={disabled}
          >
            {WEBSITE_TYPE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="plan">SEO plan</Label>
          <Select
            id="plan"
            value={form.plan}
            onChange={(e) => handleChange({ plan: e.target.value as SeoPlanTier })}
            disabled={disabled}
          >
            {PLAN_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </Select>
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex gap-2">
        <Button type="submit" disabled={disabled || isSubmitting}>
          {isSubmitting ? "Adding..." : "Add website"}
        </Button>
        <Button type="button" variant="outline" onClick={onCancel} disabled={isSubmitting}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
