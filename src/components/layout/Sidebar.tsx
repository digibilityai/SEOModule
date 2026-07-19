import { NavLink } from "react-router-dom";
import {
  LayoutDashboard,
  Globe,
  Search,
  KeyRound,
  Users,
  FileSearch,
  FileEdit,
  Wrench,
  FileBarChart,
  Settings,
  ClipboardList,
  ClipboardCheck,
  PenSquare,
  TrendingUp,
  Stethoscope,
  Link2,
  Sparkles,
  CalendarCheck,
  LifeBuoy,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { SEO_MODULE_REGISTRY } from "@/registry/moduleRegistry";

const iconByModuleId: Record<string, LucideIcon> = {
  "seo-setup-connections": Globe,
  "business-onboarding": ClipboardList,
  "visibility-dashboard": LayoutDashboard,
  "technical-seo-audit": Search,
  "onpage-seo-autopilot": Wrench,
  "approval-queue": ClipboardCheck,
  "content-studio": PenSquare,
  "page-performance-tracker": TrendingUp,
  "decline-diagnosis-engine": Stethoscope,
  "offpage-authority-builder": Link2,
  "ai-visibility-geo-engine": Sparkles,
  "competitor-benchmarking": Users,
  "90-day-seo-roadmap": CalendarCheck,
  "expert-support-desk": LifeBuoy,
  "progress-reports": FileBarChart,
};

const activeModuleNavItems = SEO_MODULE_REGISTRY.filter((m) => m.status === "active").sort(
  (a, b) => a.priority - b.priority,
);

// Phase-0 pages that don't have a matching Phase-1 module registry entry yet.
const extraNavItems = [
  { to: "/seo/keyword-research", label: "Keyword Research", icon: KeyRound },
  { to: "/seo/content-gaps", label: "Content Gaps", icon: FileSearch },
  { to: "/seo/blog-briefs", label: "Blog Briefs", icon: FileEdit },
  { to: "/seo/settings", label: "Settings", icon: Settings },
];

function SidebarLink({ to, label, icon: Icon }: { to: string; label: string; icon: LucideIcon }) {
  return (
    <NavLink
      to={to}
      className={({ isActive }) =>
        cn(
          "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-sidebar-foreground transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
          isActive && "bg-sidebar-accent text-sidebar-accent-foreground",
        )
      }
    >
      <Icon className="h-4 w-4" />
      {label}
    </NavLink>
  );
}

export function Sidebar() {
  return (
    <aside className="hidden w-64 shrink-0 border-r border-sidebar-border bg-sidebar md:block">
      <div className="flex h-14 items-center border-b border-sidebar-border px-4">
        <span className="font-heading text-lg font-semibold text-sidebar-foreground">
          SEO Intelligence
        </span>
      </div>
      <nav className="space-y-1 p-3">
        {activeModuleNavItems.map((m) => (
          <SidebarLink
            key={m.id}
            to={m.route}
            label={m.name}
            icon={iconByModuleId[m.id] ?? LayoutDashboard}
          />
        ))}
        <div className="my-2 border-t border-sidebar-border" />
        {extraNavItems.map((item) => (
          <SidebarLink key={item.to} {...item} />
        ))}
      </nav>
    </aside>
  );
}
