import { type NextRequest } from "next/server";
import { updateSession } from "./lib/supabase/proxy";

// Next.js 16 renamed middleware.ts -> proxy.ts (exported function
// literally named `proxy`, not `middleware`) -- confirmed against the
// actually-installed next@16.3.2 by reading baker_ally_admin's own
// proxy.ts (a real, running Next.js 16 project), not assumed from
// training-data memory of older Next.js conventions. Same discipline
// SPRINT_PLANNING.md's standing rule asks for on any third-party package.
export async function proxy(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
