export type NavItem = { href: string; label: string };

// Sprint 2's skeleton: just the two approval queues (§8.6's exit
// criteria). Categories/discounts/commission-editor/ledger etc. land with
// the sprints that build them (Sprint 3, 12).
export const ADMIN_NAV_ITEMS: NavItem[] = [
  { href: "/admin/shops", label: "Shop approvals" },
  { href: "/admin/riders", label: "Rider approvals" },
];

// Catalog/orders/sales/team all land in Sprint 3+ (§8.2-§8.4) -- this
// sprint's dashboard only has a shop-status overview.
export const DASHBOARD_NAV_ITEMS: NavItem[] = [{ href: "/dashboard", label: "Overview" }];
