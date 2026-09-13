export type NavItem = { href: string; label: string };

// Sprint 12 adds platform settings, discount authoring, and the
// platform-wide ledger (§8.6) -- the admin panel's own remaining named
// scope beyond the Sprint 2 approval-queue skeleton.
export const ADMIN_NAV_ITEMS: NavItem[] = [
  { href: "/admin/shops", label: "Shop approvals" },
  { href: "/admin/riders", label: "Rider approvals" },
  { href: "/admin/settings", label: "Platform settings" },
  { href: "/admin/discounts", label: "Discounts" },
  { href: "/admin/ledger", label: "Ledger" },
];

// Sprint 12 adds Sales and Ledger (§8.4) -- orders/team are still not built
// (no sprint has scheduled a proximity_web order-management view; the
// lightweight equivalent lives in proximity_app per §2's system map).
export const DASHBOARD_NAV_ITEMS: NavItem[] = [
  { href: "/dashboard", label: "Overview" },
  { href: "/dashboard/catalog", label: "Catalog" },
  { href: "/dashboard/sales", label: "Sales" },
  { href: "/dashboard/ledger", label: "Ledger" },
];
