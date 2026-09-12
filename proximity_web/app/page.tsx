import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth";

// "/" itself has no content of its own -- proxy.ts already guarantees a
// signed-in user reaches here (anything unauthenticated is bounced to
// /login before this renders), so this page's only job is routing to the
// right authenticated home: admins to the approval queues, everyone else
// to the shopkeeper dashboard (which itself redirects to /onboarding/shop
// if they don't have one yet -- lib/auth.ts's requireShop()).
export default async function RootPage() {
  const me = await requireUser();
  redirect(me.role === "admin" ? "/admin" : "/dashboard");
}
