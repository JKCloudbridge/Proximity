import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// Used from Server Components/Actions/Route Handlers. Next.js 16 requires
// cookies() to be awaited -- no synchronous access. Don't hoist the client
// into a module-level variable; create a fresh one per call (Fluid compute
// note from Supabase's own example). Ported from baker_ally_admin's
// lib/supabase/server.ts unchanged -- this is Next.js/Supabase-version
// specific plumbing, not domain logic, so there's nothing Proximity-specific
// to adapt here.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Called from a Server Component -- fine, proxy.ts refreshes the
            // session on every request so this write isn't load-bearing here.
          }
        },
      },
    },
  );
}
