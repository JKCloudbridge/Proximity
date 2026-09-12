import { requireShop } from "@/lib/auth";
import { AppNav } from "@/components/app-nav";
import { DASHBOARD_NAV_ITEMS } from "@/lib/nav";

// requireShop() (lib/auth.ts) is the real gate here -- redirects to
// /onboarding/shop if the caller has no shop_team_members row yet, so this
// layout never renders for someone who hasn't finished onboarding.
export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { me } = await requireShop();

  return (
    <div className="flex min-h-screen flex-col">
      <AppNav title="Proximity" items={DASHBOARD_NAV_ITEMS} roleLabel={me.role} />
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
