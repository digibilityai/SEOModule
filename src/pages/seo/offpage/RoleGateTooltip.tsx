import type { ReactNode } from "react";

interface RoleGateTooltipProps {
  /** When false, children render exactly as-is (no wrapper, no tooltip). */
  show: boolean;
  tooltip: string;
  children: ReactNode;
}

// Accessible disabled-control tooltip wrapper. A disabled control has
// `pointer-events: none` and isn't reliably focusable, so neither hover nor
// keyboard focus ever reaches it — wrap it in a non-disabled, focusable
// element and attach the tooltip trigger there instead. This is the exact
// pattern originally inlined in CampaignList's CampaignActionButton; extracted
// here (Phase 15D) so the campaign-create role gate reuses one implementation
// rather than duplicating the tooltip markup. Presentation-only — the
// seo_authority_* RPCs remain the authoritative authorization boundary.
export function RoleGateTooltip({ show, tooltip, children }: RoleGateTooltipProps) {
  if (!show) return <>{children}</>;

  return (
    <span
      tabIndex={0}
      className="group relative inline-block rounded-md focus:outline-none focus-visible:ring-1 focus-visible:ring-ring"
    >
      {children}
      <span
        role="tooltip"
        className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 text-xs text-popover-foreground shadow-md group-hover:block group-focus:block"
      >
        {tooltip}
      </span>
    </span>
  );
}
