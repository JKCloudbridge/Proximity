import { requireAdmin } from "@/lib/auth";
import { AppNav } from "@/components/app-nav";
import { ADMIN_NAV_ITEMS } from "@/lib/nav";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const me = await requireAdmin();

  return (
    <div className="flex min-h-screen flex-col">
      <AppNav title="Proximity Admin" items={ADMIN_NAV_ITEMS} roleLabel={me.role} />
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
