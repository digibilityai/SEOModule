import { useEffect, useState } from "react";
import { NavLink, useLocation } from "react-router-dom";
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
  HelpCircle,
  ChevronDown,
  ChevronRight,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { SEO_MODULE_REGISTRY } from "@/registry/moduleRegistry";
import { SEO_DASHBOARD_MODULE_ID, SEO_EXTRA_NAV_ITEMS, SEO_NAV_GROUPS } from "@/registry/navigationGroups";

// Icons for every SEO_MODULE_REGISTRY id (unchanged from before this
// restructure) plus the 5 extra, previously-hardcoded pages.
const iconById: Record<string, LucideIcon> = {
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
  "keyword-research": KeyRound,
  "content-gaps": FileSearch,
  "blog-briefs": FileEdit,
  settings: Settings,
  "help-center": HelpCircle,
};

interface ResolvedNavItem {
  id: string;
  label: string;
  route: string;
  icon: LucideIcon;
}

// Single lookup combining the registry (active items only — preserves the
// exact pre-existing filter; no plan/role filtering is added, since none
// existed before) and the extra hardcoded pages, so a group's itemIds can
// reference either source interchangeably.
function buildItemLookup(): Map<string, ResolvedNavItem> {
  const lookup = new Map<string, ResolvedNavItem>();
  for (const m of SEO_MODULE_REGISTRY) {
    if (m.status !== "active") continue;
    lookup.set(m.id, { id: m.id, label: m.name, route: m.route, icon: iconById[m.id] ?? LayoutDashboard });
  }
  for (const item of SEO_EXTRA_NAV_ITEMS) {
    lookup.set(item.id, { id: item.id, label: item.label, route: item.route, icon: iconById[item.id] ?? LayoutDashboard });
  }
  return lookup;
}

const NAV_STORAGE_PREFIX = "digibility_seo_nav:";

function readStoredBoolean(key: string): boolean | undefined {
  if (typeof window === "undefined") return undefined;
  const raw = window.localStorage.getItem(NAV_STORAGE_PREFIX + key);
  if (raw === "true") return true;
  if (raw === "false") return false;
  return undefined;
}

function writeStoredBoolean(key: string, value: boolean): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(NAV_STORAGE_PREFIX + key, String(value));
}

/**
 * Disclosure state persisted to localStorage (same plain-localStorage
 * convention as ActiveWebsiteContext), with a one-time computed default
 * when nothing is stored yet. Once a value exists (from either an explicit
 * toggle or an auto-expand-on-active-route), it takes precedence — the
 * default is never re-applied.
 */
function usePersistedDisclosure(storageKey: string, computeDefault: () => boolean) {
  const [expanded, setExpanded] = useState<boolean>(() => readStoredBoolean(storageKey) ?? computeDefault());

  const toggle = () => {
    setExpanded((prev) => {
      const next = !prev;
      writeStoredBoolean(storageKey, next);
      return next;
    });
  };

  // Auto-expand (never auto-collapse) when this section becomes the active
  // one, so a deep link or in-app navigation to a page inside a collapsed
  // group/module always reveals it — without fighting a user's manual
  // choice to collapse something they're not currently looking at.
  const revealIfActive = (isActive: boolean) => {
    if (isActive && !expanded) {
      setExpanded(true);
      writeStoredBoolean(storageKey, true);
    }
  };

  return { expanded, toggle, revealIfActive };
}

function SidebarLink({ to, label, icon: Icon, indent = false }: { to: string; label: string; icon: LucideIcon; indent?: boolean }) {
  return (
    <NavLink
      to={to}
      className={({ isActive }) =>
        cn(
          "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-sidebar-foreground transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
          indent && "ml-3 pl-6",
          isActive && "bg-sidebar-accent text-sidebar-accent-foreground",
        )
      }
    >
      <Icon className="h-4 w-4 shrink-0" />
      <span className="truncate">{label}</span>
    </NavLink>
  );
}

function NavGroupSection({
  group,
  items,
  pathname,
}: {
  group: { id: string; label: string };
  items: ResolvedNavItem[];
  pathname: string;
}) {
  const containsActiveRoute = items.some((item) => item.route === pathname);
  const { expanded, toggle, revealIfActive } = usePersistedDisclosure(`group-expanded:${group.id}`, () => containsActiveRoute);
  const contentId = `seo-nav-group-${group.id}`;

  useEffect(() => {
    revealIfActive(containsActiveRoute);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);

  // A group with zero resolved children never renders (defensive — nothing
  // in the current registry triggers this, but a future "later"-status
  // change to every item in a group must not leave an empty, misleading
  // header behind).
  if (items.length === 0) return null;

  return (
    <div>
      <button
        type="button"
        onClick={toggle}
        aria-expanded={expanded}
        aria-controls={contentId}
        className={cn(
          "flex w-full items-center justify-between gap-2 rounded-md px-3 py-1.5 text-left text-xs font-semibold uppercase tracking-wide text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
          containsActiveRoute && "text-sidebar-foreground",
        )}
      >
        <span className="truncate">{group.label}</span>
        {expanded ? <ChevronDown className="h-3.5 w-3.5 shrink-0" /> : <ChevronRight className="h-3.5 w-3.5 shrink-0" />}
      </button>
      {expanded && (
        <div id={contentId} className="mt-1 space-y-1">
          {items.map((item) => (
            <SidebarLink key={item.id} to={item.route} label={item.label} icon={item.icon} indent />
          ))}
        </div>
      )}
    </div>
  );
}

export function Sidebar() {
  const { pathname } = useLocation();
  const lookup = buildItemLookup();

  const dashboardItem = lookup.get(SEO_DASHBOARD_MODULE_ID);

  const resolvedGroups = SEO_NAV_GROUPS.map((group) => ({
    def: group,
    items: group.itemIds
      .map((id) => lookup.get(id))
      .filter((item): item is ResolvedNavItem => Boolean(item)),
  }));

  // "Inside SEO" also covers the public Help Center, since it's presented
  // as living inside this module's tree in the sidebar even though its
  // route sits outside the authenticated /seo/* boundary.
  const isInsideSeo = pathname.startsWith("/seo/") || pathname === "/help" || pathname.startsWith("/help/");

  const { expanded: seoExpanded, toggle: toggleSeo, revealIfActive: revealSeoIfActive } = usePersistedDisclosure(
    "module-expanded",
    () => true, // Today the entire authenticated app is SEO — default expanded.
  );

  useEffect(() => {
    revealSeoIfActive(isInsideSeo);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);

  const moduleContentId = "seo-nav-module-content";

  return (
    <aside className="hidden w-64 shrink-0 border-r border-sidebar-border bg-sidebar md:block">
      <div className="flex h-14 items-center border-b border-sidebar-border px-4">
        <span className="font-heading text-lg font-semibold text-sidebar-foreground">
          SEO Intelligence
        </span>
      </div>
      <nav className="space-y-1 p-3">
        <button
          type="button"
          onClick={toggleSeo}
          aria-expanded={seoExpanded}
          aria-controls={moduleContentId}
          className={cn(
            "flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-sm font-semibold text-sidebar-foreground transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
            !seoExpanded && isInsideSeo && "bg-sidebar-accent text-sidebar-accent-foreground",
          )}
        >
          <span>SEO</span>
          {seoExpanded ? <ChevronDown className="h-4 w-4 shrink-0" /> : <ChevronRight className="h-4 w-4 shrink-0" />}
        </button>

        {seoExpanded && (
          <div id={moduleContentId} className="space-y-1">
            {dashboardItem && (
              <SidebarLink to={dashboardItem.route} label={dashboardItem.label} icon={dashboardItem.icon} />
            )}
            {resolvedGroups.map(({ def, items }) => (
              <NavGroupSection key={def.id} group={def} items={items} pathname={pathname} />
            ))}
          </div>
        )}
      </nav>
    </aside>
  );
}
