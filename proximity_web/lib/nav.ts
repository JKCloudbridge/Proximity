export type NavItem = { href: string; label: string };

// Sprint 2's skeleton: just the two approval queues (§8.6's exit
// criteria). Categories/discounts/commission-editor/ledger etc. land with
// the sprints that build them (Sprint 3, 12).
export const ADMIN_NAV_ITEMS: NavItem[] = [
  { href: "/admin/shops", label: "Shop approvals" },
  { href: "/admin/riders", label: "Rider approvals" },
];

// Catalog lands this sprint (§8.2); orders/sales/team are still Sprint 7+/12
// (§8.3-§8.4).
export const DASHBOARD_NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Overview" },
  { href: "/dashboard/catalog", label: "Catalog" },
];
