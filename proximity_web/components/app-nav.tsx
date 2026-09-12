"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { SignOutButton } from "@/components/sign-out-button";
import { cn } from "@/lib/utils";
import type { NavItem } from "@/lib/nav";

// A plain top nav rather than the shadcn Sidebar primitive baker_ally_admin
// uses -- that component pulls in more Radix/cookie-persisted-state
// machinery than a Sprint 2 "admin panel skeleton" (§11's own words) needs.
// Same role, simpler shape; revisit if the dashboard/admin nav grows enough
// (Sprint 3+ catalog, Sprint 12 settings) to want a real sidebar.
export function AppNav({ title, items, roleLabel }: { title: string; items: NavItem[]; roleLabel: string }) {
  const pathname = usePathname();

  return (
    <header className="flex h-14 items-center justify-between border-b bg-card px-4 sm:px-6">
      <div className="flex items-center gap-6">
        <span className="font-[family-name:var(--font-display)] text-lg font-semibold text-primary">{title}</span>
        <nav className="flex items-center gap-4">
          {items.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "text-sm font-medium text-muted-foreground hover:text-foreground",
                pathname === item.href && "text-foreground",
              )}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </div>
      <div className="flex items-center gap-3">
        <span className="text-xs text-muted-foreground capitalize">{roleLabel}</span>
        <SignOutButton />
      </div>
    </header>
  );
}
