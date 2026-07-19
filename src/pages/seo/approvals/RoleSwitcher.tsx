import type { SeoUserRole } from "@/types";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";

const ROLE_OPTIONS: { value: SeoUserRole; label: string }[] = [
  { value: "owner", label: "Owner / Admin" },
  { value: "team_member", label: "Team Member" },
  { value: "client", label: "Client" },
];

interface RoleSwitcherProps {
  role: SeoUserRole;
  onChange: (role: SeoUserRole) => void;
}

export function RoleSwitcher({ role, onChange }: RoleSwitcherProps) {
  return (
    <div className="flex items-center gap-2">
      <Label htmlFor="role-switcher" className="whitespace-nowrap text-xs text-muted-foreground">
        Viewing as
      </Label>
      <Select
        id="role-switcher"
        className="h-8 w-40 text-xs"
        value={role}
        onChange={(e) => onChange(e.target.value as SeoUserRole)}
      >
        {ROLE_OPTIONS.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </Select>
    </div>
  );
}
